/// Delivering a queued expense, and recording what the server said about it.
///
/// Two small classes with one job each, kept apart because they fail differently.
///
/// [ExpenseMutationEndpoint] sends the intent. It performs no arithmetic, decides no
/// authority, and invents no retry — it is a translation table from a stored payload to
/// an RPC, and from a server answer to the outcome the engine already knows how to act
/// on. The security-relevant row of that table is the last one: an *unreachable*
/// transport is a transient failure and never a refusal, because "we could not tell" must
/// never look like the server saying no (D-048 §1).
///
/// [ExpenseReconciler] writes the answer back. It runs before the queue entry is marked
/// done, and if it fails the entry stays queued — see [MutationReconciler] for why that
/// is the only safe recovery once the server has committed.
library;

import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';

class ExpenseMutationEndpoint implements RemoteMutationEndpoint {
  const ExpenseMutationEndpoint(this.expenses);

  final ExpenseGateway expenses;

  /// Whether this endpoint recognises an entity type. Used by the routing endpoint.
  static bool handles(String entityType) => entityType == 'expense';

  @override
  Future<List<MutationResult>> push(List<PendingMutation> mutations) async {
    final results = <MutationResult>[];
    for (final mutation in mutations) {
      results.add(await _one(mutation));
    }
    return results;
  }

  Future<MutationResult> _one(PendingMutation mutation) async {
    final outcome = await _dispatch(mutation);
    if (outcome == null) {
      // A queued intent this build cannot deliver. Terminal rather than retried forever:
      // repeating it cannot teach the client what it is. The entry is kept, so a person
      // can see what was lost rather than discovering the absence later.
      return MutationResult(
        mutationId: mutation.mutationId,
        outcome: MutationOutcome.notPermitted,
        message:
            'This entry cannot be sent by this version of the application. '
            'It has been kept so it is not lost.',
      );
    }

    return switch (outcome) {
      RemoteOk(:final value) => MutationResult(
        mutationId: mutation.mutationId,
        outcome: value['status'] == 'replayed'
            ? MutationOutcome.duplicateIgnored
            : MutationOutcome.applied,
        rowVersion: value['row_version'] as int?,
        serverUpdatedAt: DateTime.tryParse('${value['updated_at']}')?.toUtc(),
        serverPayload: value,
      ),
      RemoteRefused(:final refusal) => MutationResult(
        mutationId: mutation.mutationId,
        outcome: switch (refusal.kind) {
          // The record moved and a person must choose between two versions.
          RefusalKind.versionConflict => MutationOutcome.conflict,
          // A distinct, truthful reason — never dressed up as a conflict (D-026).
          RefusalKind.periodClosed => MutationOutcome.periodClosed,
          // Everything else is the server declining outright on its current authority
          // or state. Terminal: there is nothing for a person to choose between.
          _ => MutationOutcome.notPermitted,
        },
        message: refusal.message,
      ),
      RemoteUnreachable(:final failure) => MutationResult(
        mutationId: mutation.mutationId,
        outcome: failure == RemoteFailure.sessionExpired
            ? MutationOutcome.authExpired
            : MutationOutcome.transientFailure,
        message: failure.message,
      ),
    };
  }

  Future<RemoteOutcome<Map<String, dynamic>>?> _dispatch(
    PendingMutation mutation,
  ) {
    final payload = Map<String, Object?>.from(mutation.payload);
    return switch (mutation.op) {
      // The payload is the one captured at save time, sent verbatim. A create carries no
      // base version because it establishes a new identity (D-021).
      MutationOp.create => expenses.create(
        arguments: payload,
        mutationId: mutation.mutationId,
      ),
      MutationOp.update => expenses.update(
        arguments: payload,
        baseRowVersion: mutation.baseRowVersion!,
        mutationId: mutation.mutationId,
      ),
      MutationOp.void_ => expenses.voidExpense(
        expenseId: mutation.entityId,
        baseRowVersion: mutation.baseRowVersion!,
        reason: '${payload['p_reason']}',
        mutationId: mutation.mutationId,
      ),
      _ => Future.value(null),
    };
  }
}

/// Writes the server's answer onto the local expense row.
class ExpenseReconciler implements MutationReconciler {
  const ExpenseReconciler(this.repository, this.gateway);

  final ExpenseRepository repository;
  final ExpenseGateway gateway;

  @override
  Future<void> reconcile(
    PendingMutation mutation,
    MutationResult result,
  ) async {
    if (mutation.entityType != 'expense') return;

    final acceptance = ExpenseAcceptance.fromResult(
      mutation.entityId,
      result.serverPayload,
    );
    if (acceptance != null) {
      await repository.reconcileAcceptance(acceptance);
      return;
    }

    // The answer did not carry what we need — a replay of an older stored result, or a
    // response shape this build does not recognise. Ask the server what it holds, under
    // the same identity, rather than assuming or re-sending.
    final refetched = await gateway.fetchDocument(mutation.entityId);
    switch (refetched) {
      case RemoteOk(:final value) when value != null:
        await repository.reconcileAcceptance(
          ExpenseAcceptance(
            expenseId: mutation.entityId,
            rowVersion: value['row_version'] as int? ?? 1,
            txnNumber: value['txn_number'] as String?,
            financialYear: value['financial_year'] as int?,
            serverUpdatedAt: DateTime.tryParse(
              '${value['updated_at']}',
            )?.toUtc(),
          ),
        );
      case RemoteOk():
        // Accepted, but the server will not show it to this caller. That is legitimate —
        // a Data Entry user holds `expense.view.own` and could in principle record
        // something they cannot then read back. Nothing to reconcile, and nothing wrong.
        return;
      case RemoteRefused():
      case RemoteUnreachable():
        // Leave it queued. Throwing is what tells the engine to retry this exact intent
        // rather than mark it done or re-identify it.
        throw StateError(
          'expense ${mutation.entityId} was accepted but could not be re-read',
        );
    }
  }
}

/// Sends every queued intent to whichever endpoint knows how to deliver it.
///
/// One worker drains one queue, so the routing lives here rather than in the engine —
/// which should not know that expenses and masters are different kinds of thing.
class RoutingMutationEndpoint implements RemoteMutationEndpoint {
  const RoutingMutationEndpoint({
    required this.masters,
    required this.expenses,
  });

  final RemoteMutationEndpoint masters;
  final RemoteMutationEndpoint expenses;

  @override
  Future<List<MutationResult>> push(List<PendingMutation> mutations) async {
    final expenseIntents = [
      for (final m in mutations)
        if (ExpenseMutationEndpoint.handles(m.entityType)) m,
    ];
    final masterIntents = [
      for (final m in mutations)
        if (!ExpenseMutationEndpoint.handles(m.entityType)) m,
    ];

    return [
      if (masterIntents.isNotEmpty) ...await masters.push(masterIntents),
      if (expenseIntents.isNotEmpty) ...await expenses.push(expenseIntents),
    ];
  }
}
