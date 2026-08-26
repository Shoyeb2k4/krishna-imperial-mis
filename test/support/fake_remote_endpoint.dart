/// A fake server for the sync tests.
///
/// It deliberately models the two things the real `sync_push` RPC must do
/// (docs/ARCHITECTURE.md §5.1):
///
///  1. a `processed_mutations` ledger keyed by `mutation_id`, so a re-delivery replays
///     instead of creating a second record;
///  2. optimistic concurrency on `row_version`, so a stale intent is refused.
///
/// The whole point is that Phase 1 can prove "exactly one financial record exists"
/// against injected failures long before any backend is provisioned.
library;

import 'package:krishna_mis/domain/sync/pending_mutation.dart';

class FakeRemoteEndpoint implements RemoteMutationEndpoint {
  /// The server's record of every mutation id it has ever applied.
  final Map<String, MutationResult> processedMutations = {};

  /// Current row version per entity — the server's view of the truth.
  final Map<String, int> rowVersions = {};

  /// How many distinct financial records the server holds. The assertion that matters.
  final Map<String, Map<String, Object?>> storedRecords = {};

  /// Every batch the client sent, including re-deliveries.
  final List<List<PendingMutation>> receivedBatches = [];

  /// When set, the next [push] throws instead of answering — the "timeout after send"
  /// case, where the client cannot know whether the server saw the batch.
  bool throwOnNextPush = false;

  /// When set, the transport still delivers but the client never sees the reply.
  bool dropNextResponse = false;

  /// Forces a specific outcome regardless of state. Cleared after one push.
  MutationOutcome? forcedOutcome;

  int pushCallCount = 0;

  List<PendingMutation> get allReceivedMutations => [
    for (final batch in receivedBatches) ...batch,
  ];

  int receivedCountFor(String mutationId) =>
      allReceivedMutations.where((m) => m.mutationId == mutationId).length;

  @override
  Future<List<MutationResult>> push(List<PendingMutation> mutations) async {
    pushCallCount++;
    receivedBatches.add(List.of(mutations));

    if (throwOnNextPush) {
      throwOnNextPush = false;
      // The server may or may not have applied it. That ambiguity is the whole reason
      // idempotency exists, so the fake applies the batch *before* throwing.
      for (final mutation in mutations) {
        _apply(mutation);
      }
      throw const _TransportFailure();
    }

    final forced = forcedOutcome;
    forcedOutcome = null;

    final results = <MutationResult>[];
    for (final mutation in mutations) {
      if (forced != null) {
        results.add(
          MutationResult(mutationId: mutation.mutationId, outcome: forced),
        );
        continue;
      }
      results.add(_apply(mutation));
    }

    if (dropNextResponse) {
      dropNextResponse = false;
      return [];
    }
    return results;
  }

  MutationResult _apply(PendingMutation mutation) {
    // 1. Idempotency ledger. A mutation id the server has already seen replays its
    //    stored result and touches nothing.
    final alreadyProcessed = processedMutations[mutation.mutationId];
    if (alreadyProcessed != null) {
      return MutationResult(
        mutationId: mutation.mutationId,
        outcome: MutationOutcome.duplicateIgnored,
        rowVersion: alreadyProcessed.rowVersion,
      );
    }

    // 2. Optimistic concurrency. Applies to update, void, correction and archive —
    //    not only to update (docs/DECISIONS.md D-021).
    final currentVersion = rowVersions[mutation.entityId];
    if (mutation.op.requiresBaseRowVersion) {
      if (currentVersion == null) {
        return MutationResult(
          mutationId: mutation.mutationId,
          outcome: MutationOutcome.conflict,
          message: 'record does not exist on the server',
        );
      }
      if (mutation.baseRowVersion != currentVersion) {
        return MutationResult(
          mutationId: mutation.mutationId,
          outcome: MutationOutcome.conflict,
          rowVersion: currentVersion,
          message:
              'stale intent: based on v${mutation.baseRowVersion}, '
              'server holds v$currentVersion',
        );
      }
    }

    final newVersion = (currentVersion ?? 0) + 1;
    rowVersions[mutation.entityId] = newVersion;
    storedRecords[mutation.entityId] = {
      ...mutation.payload,
      if (mutation.op == MutationOp.void_) 'status': 'voided',
    };

    final result = MutationResult(
      mutationId: mutation.mutationId,
      outcome: MutationOutcome.applied,
      rowVersion: newVersion,
      serverUpdatedAt: DateTime.utc(2026, 6, 15, 12),
    );
    processedMutations[mutation.mutationId] = result;
    return result;
  }
}

class _TransportFailure implements Exception {
  const _TransportFailure();
  @override
  String toString() => 'connection reset';
}
