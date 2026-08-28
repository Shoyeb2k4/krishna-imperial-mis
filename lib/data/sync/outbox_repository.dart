/// Durable queue of user intents awaiting push.
///
/// The outbox lives in the local database, so it survives an app kill, a reboot and a
/// week offline. Nothing is ever silently dropped from it.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';

class OutboxRepository {
  OutboxRepository(this._db);

  final AppDatabase _db;

  /// Enqueues one intent.
  ///
  /// Call this **inside the same transaction** that writes the domain rows. That is the
  /// invariant which makes "saved locally" and "queued for sync" a single atomic fact.
  ///
  /// Re-enqueuing an existing `mutationId` is a no-op rather than an error: a retry
  /// reuses its id by design, and the queue must not grow a second copy of one intent.
  Future<void> enqueue(
    PendingMutation mutation, {
    required DateTime now,
  }) async {
    await _db
        .into(_db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            mutationId: mutation.mutationId,
            entityType: mutation.entityType,
            entityId: mutation.entityId,
            op: mutation.op.name,
            payload: jsonEncode(mutation.payload),
            baseRowVersion: Value(mutation.baseRowVersion),
            nextAttemptAt: now,
            status: OutboxStatus.pending.name,
            createdAt: mutation.createdAt,
            actorUserId: Value(mutation.actorUserId),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Entries the worker may pick up now: retryable status, attempt window elapsed, and
  /// — when an actor is named — queued by that actor.
  ///
  /// The actor filter is the enforcement half of D-050. Without it, whoever happens to be
  /// signed in when connectivity returns would push somebody else's queued financial
  /// intent under their own session, and the server would attribute it to them. Passing
  /// no actor is reserved for maintenance and for tests that are about the queue itself.
  ///
  /// Ordered by creation so a device that has been offline replays its work in the
  /// order the user did it.
  Future<List<PendingMutation>> dueEntries({
    required DateTime now,
    int limit = 25,
    String? actorUserId,
  }) async {
    final rows =
        await (_db.select(_db.syncOutbox)
              ..where(
                (t) =>
                    t.status.isIn(const ['pending', 'failed']) &
                    t.nextAttemptAt.isSmallerOrEqualValue(now) &
                    (actorUserId == null
                        ? const CustomExpression<bool>('1')
                        : t.actorUserId.equals(actorUserId)),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
              ..limit(limit))
            .get();

    return rows.map(_toMutation).toList(growable: false);
  }

  Future<void> markInFlight(
    List<String> mutationIds, {
    required DateTime now,
  }) async {
    if (mutationIds.isEmpty) return;
    await (_db.update(
      _db.syncOutbox,
    )..where((t) => t.mutationId.isIn(mutationIds))).write(
      SyncOutboxCompanion(
        status: Value(OutboxStatus.inFlight.name),
        inFlightSince: Value(now),
      ),
    );
  }

  Future<void> updateStatus(
    String mutationId, {
    required OutboxStatus status,
    DateTime? nextAttemptAt,
    int? attemptCount,
    String? lastError,
    bool clearInFlight = true,
  }) async {
    await (_db.update(
      _db.syncOutbox,
    )..where((t) => t.mutationId.equals(mutationId))).write(
      SyncOutboxCompanion(
        status: Value(status.name),
        nextAttemptAt: nextAttemptAt == null
            ? const Value.absent()
            : Value(nextAttemptAt),
        attemptCount: attemptCount == null
            ? const Value.absent()
            : Value(attemptCount),
        lastError: Value(lastError),
        inFlightSince: clearInFlight ? const Value(null) : const Value.absent(),
      ),
    );
  }

  /// Reclaims entries that were in flight when the process died.
  ///
  /// Safe precisely because push is idempotent: if the server did receive the mutation,
  /// re-sending it replays the stored result instead of creating a second record
  /// (docs/DECISIONS.md D-004).
  Future<int> recoverStaleInFlight({
    required DateTime now,
    Duration olderThan = const Duration(minutes: 2),
  }) async {
    final cutoff = now.subtract(olderThan);
    return (_db.update(_db.syncOutbox)..where(
          (t) =>
              t.status.equals(OutboxStatus.inFlight.name) &
              (t.inFlightSince.isSmallerOrEqualValue(cutoff) |
                  t.inFlightSince.isNull()),
        ))
        .write(
          SyncOutboxCompanion(
            status: Value(OutboxStatus.pending.name),
            nextAttemptAt: Value(now),
            inFlightSince: const Value(null),
          ),
        );
  }

  /// Pauses the whole queue on an unrecoverable auth failure.
  ///
  /// No entry is dropped and **no attempt counter burns**, so a queue that waited
  /// through an expired session does not come back already exhausted.
  Future<void> blockOnAuth({required DateTime now}) async {
    await (_db.update(
          _db.syncOutbox,
        )..where((t) => t.status.isIn(const ['pending', 'failed', 'inFlight'])))
        .write(
          SyncOutboxCompanion(
            status: Value(OutboxStatus.blockedAuth.name),
            inFlightSince: const Value(null),
          ),
        );
  }

  /// Releases an auth-blocked queue after a successful re-authentication.
  Future<void> unblockAfterAuth({required DateTime now}) async {
    await (_db.update(
      _db.syncOutbox,
    )..where((t) => t.status.equals(OutboxStatus.blockedAuth.name))).write(
      SyncOutboxCompanion(
        status: Value(OutboxStatus.pending.name),
        nextAttemptAt: Value(now),
      ),
    );
  }

  Future<OutboxStatus?> statusOf(String mutationId) async {
    final row =
        await (_db.select(_db.syncOutbox)
              ..where((t) => t.mutationId.equals(mutationId))
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : OutboxStatus.fromName(row.status);
  }

  Future<SyncOutboxRow?> entry(String mutationId) =>
      (_db.select(_db.syncOutbox)
            ..where((t) => t.mutationId.equals(mutationId))
            ..limit(1))
          .getSingleOrNull();

  Future<List<SyncOutboxRow>> allEntries() => _db.select(_db.syncOutbox).get();

  /// How many intents exist that the server has not confirmed.
  ///
  /// Drives the "N unsynced entries" freshness badge on every report, and the refusal
  /// to erase local data while work is outstanding.
  Future<int> unsyncedCount() async {
    final count = _db.syncOutbox.mutationId.count();
    final query = _db.selectOnly(_db.syncOutbox)
      ..addColumns([count])
      ..where(_db.syncOutbox.status.isNotValue(OutboxStatus.done.name));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Live count for the UI, so a badge updates itself as the queue drains.
  Stream<int> watchUnsyncedCount() {
    final count = _db.syncOutbox.mutationId.count();
    final query = _db.selectOnly(_db.syncOutbox)
      ..addColumns([count])
      ..where(_db.syncOutbox.status.isNotValue(OutboxStatus.done.name));
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// Removes confirmed entries. Only ever deletes rows the server has acknowledged.
  Future<int> purgeCompleted({required DateTime before}) =>
      (_db.delete(_db.syncOutbox)..where(
            (t) =>
                t.status.equals(OutboxStatus.done.name) &
                t.createdAt.isSmallerThanValue(before),
          ))
          .go();

  PendingMutation _toMutation(SyncOutboxRow row) => PendingMutation(
    mutationId: row.mutationId,
    entityType: row.entityType,
    entityId: row.entityId,
    op: MutationOp.fromName(row.op),
    payload: jsonDecode(row.payload) as Map<String, Object?>,
    createdAt: row.createdAt,
    baseRowVersion: row.baseRowVersion,
    attemptCount: row.attemptCount,
    actorUserId: row.actorUserId,
  );
}
