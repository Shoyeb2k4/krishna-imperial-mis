/// The outbox and sync engine, exercised against injected failures.
///
/// Every test here asserts the same underlying promise: **exactly one financial record
/// exists on the server, with the right amount, and no stale intent was ever applied.**
library;

import 'package:drift/drift.dart' show DatabaseConnection, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/data/sync/sync_engine.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/retry_policy.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';

import '../support/fake_remote_endpoint.dart';

/// Mutation ids are UUIDs — the server stores `mutation_id` as `uuid`, and a fixture
/// that used a short label would be refused as a malformed argument long before any
/// business rule ran. Derived from a name so the tests stay readable and deterministic.
String mid(String name) =>
    const Uuid().v5('c0ffee00-0000-4000-8000-000000000000', name);

void main() {
  late AppDatabase db;
  late OutboxRepository outbox;
  late FakeRemoteEndpoint server;
  late DateTime now;

  DateTime clock() => now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    outbox = OutboxRepository(db);
    server = FakeRemoteEndpoint();
    now = DateTime.utc(2026, 6, 15, 9);
  });

  tearDown(() => db.close());

  SyncEngine engineFor(OutboxRepository repository) => SyncEngine(
    outbox: repository,
    endpoint: server,
    clock: clock,
    // No jitter: the schedule must be assertable to the second.
    retryPolicy: const RetryPolicy(jitterFraction: 0),
  );

  PendingMutation expense({
    String? mutationId,
    String entityId = 'exp-1',
    MutationOp op = MutationOp.create,
    int? baseRowVersion,
    int amountMinor = 845000,
  }) => PendingMutation(
    mutationId: mutationId ?? mid('mut-1'),
    entityType: 'expense',
    entityId: entityId,
    op: op,
    baseRowVersion: baseRowVersion,
    payload: {
      'id': entityId,
      'amount_minor': amountMinor,
      'business_date': '2026-06-15',
      'allocations': [
        {'business_unit': 'CCR', 'amount_minor': amountMinor},
      ],
    },
    createdAt: now,
  );

  group('saving locally', () {
    test('a save queues exactly one pending entry', () async {
      await outbox.enqueue(expense(), now: now);

      expect(await outbox.statusOf(mid('mut-1')), OutboxStatus.pending);
      expect(await outbox.unsyncedCount(), 1);
      // Nothing has reached the server; the save stands on its own.
      expect(server.pushCallCount, 0);
    });

    test('the user-visible state of a queued save is Pending Sync', () async {
      await outbox.enqueue(expense(), now: now);
      final status = await outbox.statusOf(mid('mut-1'));
      expect(status!.userVisibleState, SyncState.pendingSync);
      expect(status.userVisibleState.label, 'Pending Sync');
    });

    test(
      're-enqueuing the same intent does not create a second entry',
      () async {
        await outbox.enqueue(expense(), now: now);
        await outbox.enqueue(expense(), now: now);
        expect((await outbox.allEntries()).length, 1);
      },
    );

    test('a create must not carry a base version, and every other op must', () {
      expect(() => expense(op: MutationOp.update), throwsArgumentError);
      expect(() => expense(op: MutationOp.void_), throwsArgumentError);
      expect(
        () => expense(op: MutationOp.create, baseRowVersion: 3),
        throwsArgumentError,
      );
    });
  });

  group('surviving an app restart', () {
    test('a pending mutation is still queued after the app is killed', () async {
      // One physical database, two application lifetimes. Drift rightly warns when a
      // database class is instantiated twice over one executor; here that is the whole
      // point of the test, so the warning is silenced only for its duration rather
      // than globally, where it would mask a real mistake.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      try {
        final connection = DatabaseConnection(NativeDatabase.memory());
        final firstRun = AppDatabase(connection);
        await OutboxRepository(firstRun).enqueue(expense(), now: now);

        final secondRun = AppDatabase(connection);
        final recovered = OutboxRepository(secondRun);

        expect(await recovered.statusOf(mid('mut-1')), OutboxStatus.pending);
        expect(await recovered.unsyncedCount(), 1);
        await secondRun.close();
      } finally {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
      }
    });

    test(
      'an entry stranded in flight by a crash is reclaimed on startup',
      () async {
        await outbox.enqueue(expense(), now: now);
        await outbox.markInFlight([mid('mut-1')], now: now);
        expect(await outbox.statusOf(mid('mut-1')), OutboxStatus.inFlight);

        // The process dies here. Next launch, three minutes later.
        now = now.add(const Duration(minutes: 3));
        final reclaimed = await engineFor(outbox).recoverAfterRestart();

        expect(reclaimed, 1);
        expect(await outbox.statusOf(mid('mut-1')), OutboxStatus.pending);
      },
    );

    test('an entry only just sent is left alone by crash recovery', () async {
      await outbox.enqueue(expense(), now: now);
      await outbox.markInFlight([mid('mut-1')], now: now);

      now = now.add(const Duration(seconds: 20));
      expect(await engineFor(outbox).recoverAfterRestart(), 0);
      expect(await outbox.statusOf(mid('mut-1')), OutboxStatus.inFlight);
    });
  });

  group('pushing', () {
    test('a successful push marks the record Synced', () async {
      await outbox.enqueue(expense(), now: now);
      final report = await engineFor(outbox).pushOnce();

      expect(report.applied, 1);
      expect(await outbox.statusOf(mid('mut-1')), OutboxStatus.done);
      expect(
        (await outbox.statusOf(mid('mut-1')))!.userVisibleState,
        SyncState.synced,
      );
      expect(server.storedRecords.length, 1);
    });

    test(
      'an entry whose retry window has not elapsed is not picked up',
      () async {
        await outbox.enqueue(
          expense(),
          now: now.add(const Duration(minutes: 5)),
        );
        final report = await engineFor(outbox).pushOnce();
        expect(report.attempted, 0);
        expect(server.pushCallCount, 0);
      },
    );

    test('offline work replays in the order the user did it', () async {
      await outbox.enqueue(
        expense(mutationId: mid('a'), entityId: 'e1'),
        now: now,
      );
      now = now.add(const Duration(minutes: 1));
      await outbox.enqueue(
        expense(mutationId: mid('b'), entityId: 'e2'),
        now: now,
      );
      now = now.add(const Duration(minutes: 1));
      await outbox.enqueue(
        expense(mutationId: mid('c'), entityId: 'e3'),
        now: now,
      );

      await engineFor(outbox).pushOnce();
      expect(server.allReceivedMutations.map((m) => m.mutationId), [
        mid('a'),
        mid('b'),
        mid('c'),
      ]);
    });
  });

  group('idempotency — a retry never creates a second financial record', () {
    test(
      'a timeout after the server applied the write still yields ONE record',
      () async {
        await outbox.enqueue(expense(), now: now);
        final engine = engineFor(outbox);

        // The server applies it, then the connection dies before the client hears back.
        server.throwOnNextPush = true;
        final first = await engine.pushOnce();
        expect(first.transientFailures, 1);
        expect(await outbox.statusOf(mid('mut-1')), OutboxStatus.failed);
        expect(server.storedRecords.length, 1);

        // The client retries with the SAME mutation id.
        now = now.add(const Duration(minutes: 1));
        final second = await engine.pushOnce();

        expect(second.duplicatesReplayed, 1);
        expect(second.applied, 0);
        expect(await outbox.statusOf(mid('mut-1')), OutboxStatus.done);

        // The assertion that matters.
        expect(
          server.storedRecords.length,
          1,
          reason: 'a duplicate record was created',
        );
        expect(
          server.receivedCountFor(mid('mut-1')),
          2,
          reason: 'it really was sent twice',
        );
        expect(
          server.rowVersions['exp-1'],
          1,
          reason: 'the record was written once',
        );
      },
    );

    test('the mutation id is reused across retries, never re-rolled', () async {
      await outbox.enqueue(expense(), now: now);
      final engine = engineFor(outbox);

      server.forcedOutcome = MutationOutcome.transientFailure;
      await engine.pushOnce();
      now = now.add(const Duration(minutes: 1));
      server.forcedOutcome = MutationOutcome.transientFailure;
      await engine.pushOnce();
      now = now.add(const Duration(minutes: 5));
      await engine.pushOnce();

      final ids = server.allReceivedMutations.map((m) => m.mutationId).toSet();
      expect(ids, {mid('mut-1')});
      expect(server.pushCallCount, 3);
      expect(server.storedRecords.length, 1);
    });

    test(
      'a response lost in transit does not lose or duplicate the record',
      () async {
        await outbox.enqueue(expense(), now: now);
        final engine = engineFor(outbox);

        // Server applies the batch, client receives nothing back for it.
        server.dropNextResponse = true;
        final first = await engine.pushOnce();
        expect(first.transientFailures, 1);

        now = now.add(const Duration(minutes: 1));
        final second = await engine.pushOnce();
        expect(second.duplicatesReplayed, 1);
        expect(server.storedRecords.length, 1);
      },
    );
  });

  group('retry and failure state', () {
    test(
      'a transient failure records the error and the next attempt time',
      () async {
        await outbox.enqueue(expense(), now: now);
        server.forcedOutcome = MutationOutcome.transientFailure;

        await engineFor(outbox).pushOnce();

        final entry = await outbox.entry(mid('mut-1'));
        expect(entry!.status, OutboxStatus.failed.name);
        expect(entry.attemptCount, 1);
        expect(entry.lastError, isNotNull);
        // First backoff step is five seconds.
        expect(entry.nextAttemptAt, now.add(const Duration(seconds: 5)));
        expect(
          OutboxStatus.fromName(entry.status).userVisibleState,
          SyncState.syncFailed,
        );
      },
    );

    test('backoff lengthens deterministically with each attempt', () async {
      await outbox.enqueue(expense(), now: now);
      final engine = engineFor(outbox);

      const expected = [
        Duration(seconds: 5),
        Duration(seconds: 15),
        Duration(seconds: 45),
        Duration(minutes: 2),
      ];

      for (var attempt = 0; attempt < expected.length; attempt++) {
        server.forcedOutcome = MutationOutcome.transientFailure;
        await engine.pushOnce();
        final entry = await outbox.entry(mid('mut-1'));
        expect(
          entry!.nextAttemptAt,
          now.add(expected[attempt]),
          reason: 'wrong backoff after attempt ${attempt + 1}',
        );
        now = entry.nextAttemptAt;
      }
    });

    test('the schedule caps rather than growing without limit', () {
      const policy = RetryPolicy(jitterFraction: 0);
      expect(policy.baseDelayFor(0), const Duration(seconds: 5));
      expect(policy.baseDelayFor(7), const Duration(hours: 1));
      expect(policy.baseDelayFor(50), const Duration(hours: 1));
    });

    test(
      'a failed entry is retried automatically once its window elapses',
      () async {
        await outbox.enqueue(expense(), now: now);
        final engine = engineFor(outbox);

        server.forcedOutcome = MutationOutcome.transientFailure;
        await engine.pushOnce();

        // Too early — nothing is attempted.
        now = now.add(const Duration(seconds: 2));
        expect((await engine.pushOnce()).attempted, 0);

        // Window elapsed — it goes again, and succeeds.
        now = now.add(const Duration(seconds: 10));
        expect((await engine.pushOnce()).applied, 1);
        expect(await outbox.statusOf(mid('mut-1')), OutboxStatus.done);
      },
    );
  });

  group('conflict — no financial state is changed on stale intent', () {
    test(
      'an update based on a stale version is refused and surfaced',
      () async {
        // The record exists on the server at v1.
        await outbox.enqueue(expense(), now: now);
        await engineFor(outbox).pushOnce();

        // Another device moves it to v2.
        server.rowVersions['exp-1'] = 2;

        // This device edits from its stale v1 view.
        await outbox.enqueue(
          expense(
            mutationId: mid('mut-2'),
            op: MutationOp.update,
            baseRowVersion: 1,
          ),
          now: now,
        );
        final report = await engineFor(outbox).pushOnce();

        expect(report.conflicts, 1);
        expect(report.applied, 0);
        final entry = await outbox.entry(mid('mut-2'));
        expect(entry!.status, OutboxStatus.conflict.name);
        expect(entry.lastError, contains('stale intent'));
        expect(
          OutboxStatus.fromName(entry.status).userVisibleState,
          SyncState.conflict,
        );
        expect(
          server.rowVersions['exp-1'],
          2,
          reason: 'the server was modified',
        );
      },
    );

    test(
      'a VOID issued from a stale view is refused, not silently applied',
      () async {
        // This is the correction the owner required: a void is a financial state change
        // and must participate in concurrency control (D-021).
        await outbox.enqueue(expense(), now: now);
        await engineFor(outbox).pushOnce();
        expect(server.rowVersions['exp-1'], 1);

        // Device B edits it to v2. Device A still believes it is v3-from-its-own-view.
        server.rowVersions['exp-1'] = 2;
        final beforeVoid = Map<String, Object?>.from(
          server.storedRecords['exp-1']!,
        );

        await outbox.enqueue(
          expense(
            mutationId: mid('void-1'),
            op: MutationOp.void_,
            baseRowVersion: 1,
          ),
          now: now,
        );
        final report = await engineFor(outbox).pushOnce();

        expect(report.conflicts, 1);
        expect(await outbox.statusOf(mid('void-1')), OutboxStatus.conflict);
        expect(
          server.storedRecords['exp-1'],
          beforeVoid,
          reason: 'a stale void changed the record',
        );
        expect(server.storedRecords['exp-1']!['status'], isNot('voided'));
      },
    );

    test('a void on the current version succeeds', () async {
      await outbox.enqueue(expense(), now: now);
      await engineFor(outbox).pushOnce();

      await outbox.enqueue(
        expense(
          mutationId: mid('void-1'),
          op: MutationOp.void_,
          baseRowVersion: 1,
        ),
        now: now,
      );
      final report = await engineFor(outbox).pushOnce();

      expect(report.applied, 1);
      expect(server.storedRecords['exp-1']!['status'], 'voided');
    });

    test(
      're-delivering the same void replays instead of conflicting',
      () async {
        await outbox.enqueue(expense(), now: now);
        await engineFor(outbox).pushOnce();
        await outbox.enqueue(
          expense(
            mutationId: mid('void-1'),
            op: MutationOp.void_,
            baseRowVersion: 1,
          ),
          now: now,
        );

        final engine = engineFor(outbox);
        server.throwOnNextPush = true;
        await engine.pushOnce();

        now = now.add(const Duration(minutes: 1));
        final second = await engine.pushOnce();

        // Same intent, delivered twice: idempotent success, not a conflict.
        expect(second.duplicatesReplayed, 1);
        expect(second.conflicts, 0);
        expect(await outbox.statusOf(mid('void-1')), OutboxStatus.done);
      },
    );

    test('a conflict is never retried automatically', () async {
      await outbox.enqueue(
        expense(
          mutationId: mid('mut-2'),
          op: MutationOp.update,
          baseRowVersion: 9,
        ),
        now: now,
      );
      final engine = engineFor(outbox);
      await engine.pushOnce();
      expect(await outbox.statusOf(mid('mut-2')), OutboxStatus.conflict);

      now = now.add(const Duration(hours: 6));
      final report = await engine.pushOnce();
      expect(
        report.attempted,
        0,
        reason: 'a stale intent was re-sent on its own',
      );
    });
  });

  group('rejections a retry cannot fix', () {
    test('a write into a closed period says so, in those words', () async {
      await outbox.enqueue(expense(), now: now);
      server.forcedOutcome = MutationOutcome.periodClosed;

      final report = await engineFor(outbox).pushOnce();

      expect(report.rejected, 1);
      expect(report.conflicts, 0);
      final entry = await outbox.entry(mid('mut-1'));
      expect(entry!.lastError, contains('period has been closed'));
      expect(entry.lastError, contains('reopen'));
    });

    test('a permission refusal is explained rather than disguised', () async {
      await outbox.enqueue(expense(), now: now);
      server.forcedOutcome = MutationOutcome.notPermitted;

      await engineFor(outbox).pushOnce();
      expect(
        (await outbox.entry(mid('mut-1')))!.lastError,
        contains('permission'),
      );
    });
  });

  group('authentication expiry', () {
    test(
      'the queue pauses without dropping entries or burning attempts',
      () async {
        await outbox.enqueue(
          expense(mutationId: mid('a'), entityId: 'e1'),
          now: now,
        );
        await outbox.enqueue(
          expense(mutationId: mid('b'), entityId: 'e2'),
          now: now,
        );
        server.forcedOutcome = MutationOutcome.authExpired;

        final engine = engineFor(outbox);
        final report = await engine.pushOnce();

        expect(report.authBlocked, isTrue);
        expect(await outbox.statusOf(mid('a')), OutboxStatus.blockedAuth);
        expect(await outbox.statusOf(mid('b')), OutboxStatus.blockedAuth);
        expect(await outbox.unsyncedCount(), 2, reason: 'entries were dropped');
        expect(
          (await outbox.entry(mid('a')))!.attemptCount,
          0,
          reason: 'attempts burned',
        );

        // A blocked queue is not picked up again on its own.
        now = now.add(const Duration(hours: 2));
        expect((await engine.pushOnce()).attempted, 0);

        // After re-authenticating, everything resumes and syncs.
        await engine.resumeAfterReauthentication();
        final resumed = await engine.pushOnce();
        expect(resumed.applied, 2);
        expect(await outbox.unsyncedCount(), 0);
      },
    );
  });

  group('unsynced count drives the freshness badge', () {
    test('counts everything the server has not confirmed', () async {
      expect(await outbox.unsyncedCount(), 0);
      await outbox.enqueue(
        expense(mutationId: mid('a'), entityId: 'e1'),
        now: now,
      );
      await outbox.enqueue(
        expense(mutationId: mid('b'), entityId: 'e2'),
        now: now,
      );
      expect(await outbox.unsyncedCount(), 2);

      await engineFor(outbox).pushOnce();
      expect(await outbox.unsyncedCount(), 0);
    });

    test('a conflicted entry still counts as unsynced', () async {
      await outbox.enqueue(
        expense(mutationId: mid('x'), op: MutationOp.update, baseRowVersion: 5),
        now: now,
      );
      await engineFor(outbox).pushOnce();
      expect(await outbox.statusOf(mid('x')), OutboxStatus.conflict);
      expect(await outbox.unsyncedCount(), 1);
    });

    test('only confirmed entries are ever purged', () async {
      await outbox.enqueue(
        expense(mutationId: mid('done'), entityId: 'e1'),
        now: now,
      );
      await outbox.enqueue(
        expense(
          mutationId: mid('stuck'),
          op: MutationOp.update,
          baseRowVersion: 7,
        ),
        now: now,
      );
      await engineFor(outbox).pushOnce();

      final purged = await outbox.purgeCompleted(
        before: now.add(const Duration(days: 1)),
      );
      expect(purged, 1);
      expect(await outbox.statusOf(mid('done')), isNull);
      expect(await outbox.statusOf(mid('stuck')), OutboxStatus.conflict);
    });
  });

  group('an outbox entry belongs to whoever queued it (D-050)', () {
    // The column existed from the first migration and nothing ever wrote it, so every
    // queued intent was anonymous and the rule could not be enforced at all. Found while
    // running the user-switch acceptance on a real device.
    test('the actor is recorded on the entry', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final outbox = OutboxRepository(db);

      await outbox.enqueue(
        PendingMutation(
          mutationId: const Uuid().v4(),
          entityType: 'vendor',
          entityId: 'v1',
          op: MutationOp.create,
          payload: const {'name': 'Sharma Traders'},
          createdAt: DateTime.utc(2026, 8, 28),
          actorUserId: 'user-a',
        ),
        now: DateTime.utc(2026, 8, 28),
      );

      final row = (await db.select(db.syncOutbox).get()).single;
      expect(row.actorUserId, 'user-a');
    });

    test("a different user is never handed the previous one's queue", () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final outbox = OutboxRepository(db);
      final now = DateTime.utc(2026, 8, 28);

      for (final actor in ['user-a', 'user-b']) {
        await outbox.enqueue(
          PendingMutation(
            mutationId: const Uuid().v4(),
            entityType: 'vendor',
            entityId: 'v-$actor',
            op: MutationOp.create,
            payload: {'name': actor},
            createdAt: now,
            actorUserId: actor,
          ),
          now: now,
        );
      }

      final forA = await outbox.dueEntries(now: now, actorUserId: 'user-a');
      expect(forA, hasLength(1));
      expect(forA.single.actorUserId, 'user-a');
      expect(
        forA.single.payload['name'],
        'user-a',
        reason: "one user must never submit another user's queued mutation",
      );

      // And nothing is lost: the other user's entry is still there, waiting for them.
      final all = await outbox.dueEntries(now: now);
      expect(all, hasLength(2));
    });

    test("a signed-out user's work waits, it is not discarded", () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final outbox = OutboxRepository(db);
      final now = DateTime.utc(2026, 8, 28);

      await outbox.enqueue(
        PendingMutation(
          mutationId: const Uuid().v4(),
          entityType: 'vendor',
          entityId: 'v1',
          op: MutationOp.create,
          payload: const {'name': 'Queued by the previous user'},
          createdAt: now,
          actorUserId: 'user-a',
        ),
        now: now,
      );

      // Somebody else is signed in: they see none of it to push.
      expect(await outbox.dueEntries(now: now, actorUserId: 'user-b'), isEmpty);
      // It is still on the device, and becomes processable again when its own
      // actor signs back in.
      expect(await db.select(db.syncOutbox).get(), hasLength(1));
      expect(
        await outbox.dueEntries(now: now, actorUserId: 'user-a'),
        hasLength(1),
      );
    });
  });
}
