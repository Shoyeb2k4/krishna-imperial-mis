/// Delivering a queued revenue entry, and recording what the server said about it.
///
/// The same two classes, with the same division of labour, as the expense endpoint — and
/// deliberately not a second sync engine. Revenue is another registered mutation type in
/// the transport that already exists: one outbox, one worker, one backoff clock, one
/// actor filter (D-050).
///
/// [RevenueMutationEndpoint] sends the intent and translates the answer. It performs no
/// arithmetic, decides no authority, and invents no retry. The security-relevant row of
/// its table is the last one: an *unreachable* transport is a transient failure and never
/// a refusal, because "we could not tell" must never look like the server saying no
/// (D-048 §1).
///
/// [RevenueReconciler] writes the answer back, before the queue entry is marked done. If
/// it fails, the entry stays queued — which is the only safe recovery once the server has
/// committed, because the alternative is a canonical record nothing local points at.
library;

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';

class RevenueMutationEndpoint implements RemoteMutationEndpoint {
  const RevenueMutationEndpoint(this.revenue);

  final RevenueGateway revenue;

  /// Whether this endpoint recognises an entity type. Used by the routing endpoint.
  static bool handles(String entityType) => entityType == revenueEntityType;

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
      // A queued intent this build cannot deliver. Terminal rather than retried for ever:
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
        // `replayed` is the idempotency guarantee working, not an error: the server had
        // already processed this mutation id and handed back the stored result. Exactly
        // one financial record exists, and it is the one this intent created.
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
          // The tax the operator approved is not the tax the server computes, because
          // the configuration changed between preparing this entry and delivering it
          // (KM030). Surfaced as a conflict rather than a refusal on purpose: like a
          // stale version, it is two defensible answers that a person has to choose
          // between, and nothing may be overwritten silently in either direction.
          RefusalKind.taxConfigurationMismatch => MutationOutcome.conflict,
          // Everything else is the server declining outright on its current authority or
          // state. Terminal: there is nothing for a person to choose between.
          _ => MutationOutcome.notPermitted,
        },
        message: refusal.message,
        serverPayload: refusal.detail,
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
      MutationOp.create => revenue.create(
        arguments: payload,
        mutationId: mutation.mutationId,
      ),
      MutationOp.void_ => revenue.voidEntry(
        entryId: mutation.entityId,
        baseRowVersion: mutation.baseRowVersion!,
        reason: '${payload['p_reason']}',
        mutationId: mutation.mutationId,
      ),
      _ => Future.value(null),
    };
  }
}

/// Writes the server's answer onto the local revenue row.
class RevenueReconciler implements MutationReconciler {
  const RevenueReconciler(this.repository, this.gateway);

  final RevenueRepository repository;
  final RevenueGateway gateway;

  @override
  Future<void> reconcile(
    PendingMutation mutation,
    MutationResult result,
  ) async {
    if (mutation.entityType != revenueEntityType) return;

    final acceptance = RevenueAcceptance.fromResult(
      mutation.entityId,
      result.serverPayload,
    );
    if (acceptance != null) {
      await repository.reconcileAcceptance(acceptance);
      return;
    }

    // The answer did not carry what is needed — a replay of a result stored by an older
    // build, or a response shape this one does not recognise. Ask the server what it holds
    // under the same identity rather than assuming, and rather than re-sending: the
    // mutation id already guarantees there is at most one record, so the question is what
    // that record says, not whether to make another.
    final refetched = await gateway.fetchDocument(mutation.entityId);
    switch (refetched) {
      case RemoteOk(:final value) when value != null:
        await repository.reconcileAcceptance(
          RevenueAcceptance(
            entryId: mutation.entityId,
            rowVersion: value['row_version'] as int? ?? 1,
            txnNumber: value['txn_number'] as String?,
            financialYear: value['financial_year']?.toString(),
            serverUpdatedAt: DateTime.tryParse(
              '${value['updated_at']}',
            )?.toUtc(),
          ),
        );
      case RemoteOk():
        // Accepted, and the server will not show it back to this caller. Legitimate: a
        // Data Entry user may hold `revenue.create` without a matching view grant.
        // Nothing to reconcile, and nothing wrong.
        return;
      case RemoteRefused():
      case RemoteUnreachable():
        // Leave it queued. Throwing is what tells the engine to retry this exact intent
        // rather than mark it done or re-identify it.
        throw StateError(
          'revenue ${mutation.entityId} was accepted but could not be re-read',
        );
    }
  }
}
