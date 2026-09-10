/// Delivering a queued owner movement, and recording what the server said about it.
///
/// The same two classes, with the same division of labour, as the expense and revenue
/// endpoints — and deliberately not a third sync engine. An owner movement is another
/// registered mutation type in the transport that already exists: one outbox, one worker,
/// one backoff clock, one actor filter (D-050, OA-1 §18, §25).
///
/// [OwnerLedgerMutationEndpoint] sends the intent and translates the answer. It performs
/// no arithmetic, decides no authority, and invents no retry. The security-relevant row of
/// its table is the last one: an *unreachable* transport is a transient failure and never
/// a refusal, because "we could not tell" must never look like the server saying no
/// (D-048 §1).
///
/// [OwnerLedgerReconciler] writes the answer back, before the queue entry is marked done.
/// If it fails, the entry stays queued — the only safe recovery once the server has
/// committed, because the alternative is a canonical record nothing local points at.
library;

import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/repositories/owner_ledger_repository.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';

class OwnerLedgerMutationEndpoint implements RemoteMutationEndpoint {
  const OwnerLedgerMutationEndpoint(this.owners);

  final OwnerLedgerGateway owners;

  /// Whether this endpoint recognises an entity type. Used by the routing endpoint.
  static bool handles(String entityType) =>
      entityType == ownerMovementEntityType;

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
            'This movement cannot be sent by this version of the application. '
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
          // The owner the operator was shown is not the one the canonical family mapping
          // resolves to. Surfaced as a **conflict** rather than a refusal, for the reason
          // a stale version is: two defensible answers exist, a person chooses between
          // them, and nothing may be overwritten silently in either direction (§12).
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
      MutationOp.create => owners.create(
        arguments: payload,
        mutationId: mutation.mutationId,
      ),
      // The base version is the one the form opened on — never re-read, so a stale
      // correction conflicts rather than silently retargeting whatever the server now
      // holds (D-021, D-130).
      MutationOp.update => owners.update(
        arguments: payload,
        baseRowVersion: mutation.baseRowVersion!,
        mutationId: mutation.mutationId,
      ),
      MutationOp.void_ => owners.voidMovement(
        entryId: mutation.entityId,
        baseRowVersion: mutation.baseRowVersion!,
        reason: '${payload['p_reason']}',
        mutationId: mutation.mutationId,
      ),
      _ => Future.value(null),
    };
  }
}

/// Writes the server's answer onto the local owner movement.
class OwnerLedgerReconciler implements MutationReconciler {
  const OwnerLedgerReconciler(this.repository, this.gateway);

  final OwnerLedgerRepository repository;
  final OwnerLedgerGateway gateway;

  @override
  Future<void> reconcile(
    PendingMutation mutation,
    MutationResult result,
  ) async {
    if (mutation.entityType != ownerMovementEntityType) return;

    final acceptance = OwnerMovementAcceptance.fromResult(result.serverPayload);
    if (acceptance != null) {
      await repository.reconcileAcceptance(acceptance);
      return;
    }

    // The answer did not carry what is needed — a replay of a result stored by an older
    // build, or a response shape this one does not recognise. Ask the server what it holds
    // under the same identity rather than assuming, and rather than re-sending: the
    // mutation id already guarantees there is at most one record, so the question is what
    // that record says, not whether to make another.
    final refetched = await gateway.fetchMovement(mutation.entityId);
    switch (refetched) {
      case RemoteOk(:final value) when value != null:
        await repository.reconcileAcceptance(
          OwnerMovementAcceptance(
            entryId: mutation.entityId,
            rowVersion: value['row_version'] as int? ?? 1,
            txnNumber: value['txn_number'] as String?,
            financialYear: value['financial_year']?.toString(),
            ownerId: value['owner_id'] as String?,
            businessDateSource: value['business_date_source'] as String?,
          ),
        );
      case RemoteOk():
        // Accepted, and the server will not show it back to this caller. Legitimate: an
        // operator may hold `owner_ledger.create.nc` without the unscoped
        // `owner_ledger.view` that reading the ledger requires — which is exactly the
        // staff-privacy split OA-1 §31 asks for, working. Nothing to reconcile, and
        // nothing wrong.
        return;
      case RemoteRefused():
      case RemoteUnreachable():
        // Leave it queued. Throwing is what tells the engine to retry this exact intent
        // rather than mark it done or re-identify it.
        throw StateError(
          'owner movement ${mutation.entityId} was accepted but could not be '
          're-read',
        );
    }
  }
}
