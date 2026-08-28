/// Drives the outbox: take what is due, push it once, record what the server said.
///
/// The engine contains no financial logic and no arithmetic. Its entire job is to make
/// "exactly one financial record exists, with the right amount" true in the face of
/// timeouts, crashes, duplicate deliveries, expired sessions and stale edits.
library;

import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/retry_policy.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';

/// What one push cycle did. Returned so callers and tests can assert without reaching
/// into the database.
class SyncCycleReport {
  const SyncCycleReport({
    this.attempted = 0,
    this.applied = 0,
    this.duplicatesReplayed = 0,
    this.conflicts = 0,
    this.rejected = 0,
    this.transientFailures = 0,
    this.authBlocked = false,
  });

  final int attempted;
  final int applied;
  final int duplicatesReplayed;
  final int conflicts;

  /// Refused for a reason a retry cannot fix: closed period, missing capability.
  final int rejected;
  final int transientFailures;
  final bool authBlocked;

  /// Whether anything reached the server successfully this cycle.
  bool get madeProgress => applied > 0 || duplicatesReplayed > 0;

  @override
  String toString() =>
      'SyncCycleReport(attempted: $attempted, applied: $applied, '
      'duplicates: $duplicatesReplayed, conflicts: $conflicts, '
      'rejected: $rejected, transient: $transientFailures, auth: $authBlocked)';
}

class SyncEngine {
  SyncEngine({
    required this.outbox,
    required this.endpoint,
    this.retryPolicy = const RetryPolicy(),
    this.clock = DateTime.now,
    this.batchSize = 25,
    this.inFlightTimeout = const Duration(minutes: 2),
    this.actorUserId,
  });

  final OutboxRepository outbox;
  final RemoteMutationEndpoint endpoint;
  final RetryPolicy retryPolicy;

  /// Injectable so tests can assert the backoff schedule exactly rather than sleeping.
  final DateTime Function() clock;
  final int batchSize;
  final Duration inFlightTimeout;

  /// Whose queued work this engine may send (D-050).
  ///
  /// An outbox entry belongs to the person who created it, not to the installation. On a
  /// shared workstation somebody else signs in minutes later, and their session must not
  /// push, retry or be credited with work they did not do. Null is for maintenance and
  /// for the tests that are about the queue mechanics themselves; the application always
  /// supplies the signed-in user.
  final String? actorUserId;

  bool _cycleInProgress = false;

  /// Reclaims entries stranded in flight by a crash. Call once on startup, before the
  /// first push cycle.
  Future<int> recoverAfterRestart() =>
      outbox.recoverStaleInFlight(now: clock(), olderThan: inFlightTimeout);

  /// Runs one push cycle. Safe to call from a timer, a connectivity change or a manual
  /// "retry now" button; overlapping calls are ignored rather than queued.
  Future<SyncCycleReport> pushOnce() async {
    if (_cycleInProgress) return const SyncCycleReport();
    _cycleInProgress = true;
    try {
      return await _pushOnce();
    } finally {
      _cycleInProgress = false;
    }
  }

  Future<SyncCycleReport> _pushOnce() async {
    final now = clock();
    final due = await outbox.dueEntries(
      now: now,
      limit: batchSize,
      actorUserId: actorUserId,
    );
    if (due.isEmpty) return const SyncCycleReport();

    await outbox.markInFlight(
      due.map((m) => m.mutationId).toList(growable: false),
      now: now,
    );

    late final List<MutationResult> results;
    try {
      results = await endpoint.push(due);
    } on Exception catch (error) {
      // The transport threw rather than answering. We do not know whether the server
      // saw the batch, so every entry goes back to the queue — which is safe only
      // because re-sending the same mutation id replays rather than duplicates.
      for (final mutation in due) {
        await _recordTransientFailure(mutation, '${error.runtimeType}');
      }
      return SyncCycleReport(
        attempted: due.length,
        transientFailures: due.length,
      );
    }

    final byId = {for (final result in results) result.mutationId: result};

    var applied = 0;
    var duplicates = 0;
    var conflicts = 0;
    var rejected = 0;
    var transient = 0;
    var authBlocked = false;

    for (final mutation in due) {
      final result = byId[mutation.mutationId];

      if (result == null) {
        // The server answered the batch but said nothing about this entry. Treat the
        // silence as unknown, not as success.
        await _recordTransientFailure(
          mutation,
          'no result returned for mutation',
        );
        transient++;
        continue;
      }

      switch (result.outcome) {
        case MutationOutcome.applied:
          await outbox.updateStatus(
            mutation.mutationId,
            status: OutboxStatus.done,
          );
          applied++;

        case MutationOutcome.duplicateIgnored:
          // Idempotency working as designed: the server already holds exactly this
          // intent. Not an error, and not a second record.
          await outbox.updateStatus(
            mutation.mutationId,
            status: OutboxStatus.done,
          );
          duplicates++;

        case MutationOutcome.conflict:
          // Never retried automatically. A stale intent must not be re-applied, and a
          // human decides what the record should say.
          await outbox.updateStatus(
            mutation.mutationId,
            status: OutboxStatus.conflict,
            lastError:
                result.message ?? 'Server holds a newer version of this record',
          );
          conflicts++;

        case MutationOutcome.periodClosed:
        case MutationOutcome.notPermitted:
          // Terminal, and not a conflict. A conflict means the *record* moved and a
          // human must choose between two versions; these mean the server has declined
          // outright on its current authority or state, and there is nothing to choose
          // between. Filing them as conflicts would have told the user the wrong story
          // and put them in a resolution flow with no second version to resolve against.
          //
          // The entry is kept exactly as attempted, carrying the server's own reason. It
          // is never dropped, never marked synced, and never retried automatically —
          // repeating a refused request cannot change the answer (D-048 §2).
          await outbox.updateStatus(
            mutation.mutationId,
            status: OutboxStatus.rejected,
            lastError: result.message ?? _rejectionMessage(result.outcome),
          );
          rejected++;

        case MutationOutcome.authExpired:
          authBlocked = true;

        case MutationOutcome.transientFailure:
          await _recordTransientFailure(
            mutation,
            result.message ?? 'transient failure',
          );
          transient++;
      }
    }

    if (authBlocked) {
      await outbox.blockOnAuth(now: clock());
    }

    return SyncCycleReport(
      attempted: due.length,
      applied: applied,
      duplicatesReplayed: duplicates,
      conflicts: conflicts,
      rejected: rejected,
      transientFailures: transient,
      authBlocked: authBlocked,
    );
  }

  /// Called after a successful re-authentication to release a paused queue.
  Future<void> resumeAfterReauthentication() =>
      outbox.unblockAfterAuth(now: clock());

  Future<void> _recordTransientFailure(
    PendingMutation mutation,
    String error,
  ) async {
    final failedAt = clock();
    final attempts = mutation.attemptCount + 1;
    await outbox.updateStatus(
      mutation.mutationId,
      status: OutboxStatus.failed,
      attemptCount: attempts,
      nextAttemptAt: retryPolicy.nextAttemptAt(failedAt, mutation.attemptCount),
      lastError: error,
    );
  }

  static String _rejectionMessage(MutationOutcome outcome) => switch (outcome) {
    MutationOutcome.periodClosed =>
      'This period has been closed. Ask the owner to reopen it before editing.',
    MutationOutcome.notPermitted =>
      'You do not have permission to make this change for this business unit.',
    _ => 'Rejected by the server',
  };
}
