/// Delivering a queued expense, and the failure that matters most: the server committed
/// and the client never heard.
///
/// The rule the whole design rests on is that recovery re-sends *the same intent*. A new
/// mutation id would be a second financial record for one act, and no amount of care
/// afterwards can tell the two apart.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/data/sync/sync_engine.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

/// A server that records what it has been asked to do, replays a repeated mutation id,
/// and can be told to lose a response or refuse.
class FakeExpenseServer implements RemoteMutationEndpoint {
  final Map<String, Map<String, dynamic>> committed = {};
  final List<String> deliveries = [];

  int _sequence = 0;

  /// The next delivery reaches the server and the answer never comes back.
  bool loseNextResponse = false;

  /// The next delivery is refused with this kind, once.
  RefusalKind? refuseNextAs;

  @override
  Future<List<MutationResult>> push(List<PendingMutation> mutations) async {
    final results = <MutationResult>[];
    for (final mutation in mutations) {
      deliveries.add(mutation.mutationId);

      if (refuseNextAs case final kind?) {
        refuseNextAs = null;
        results.add(
          MutationResult(
            mutationId: mutation.mutationId,
            outcome: switch (kind) {
              RefusalKind.versionConflict => MutationOutcome.conflict,
              RefusalKind.periodClosed => MutationOutcome.periodClosed,
              _ => MutationOutcome.notPermitted,
            },
            message: 'refused',
          ),
        );
        continue;
      }

      // Idempotency: the same intent, delivered twice, is one record.
      final replay = committed.containsKey(mutation.mutationId);
      if (!replay) {
        _sequence++;
        committed[mutation.mutationId] = {
          'status': 'applied',
          'entity_id': mutation.entityId,
          'row_version': 2,
          'txn_number': 'KI-EXP-26-27-${_sequence.toString().padLeft(6, '0')}',
          'financial_year': 2026,
        };
      }

      if (loseNextResponse) {
        loseNextResponse = false;
        // Committed above; the client is told nothing. This is the whole scenario.
        throw const _LostResponse();
      }

      final stored = committed[mutation.mutationId]!;
      results.add(
        MutationResult(
          mutationId: mutation.mutationId,
          outcome: replay
              ? MutationOutcome.duplicateIgnored
              : MutationOutcome.applied,
          rowVersion: stored['row_version'] as int?,
          serverPayload: replay ? {...stored, 'status': 'replayed'} : stored,
        ),
      );
    }
    return results;
  }
}

class _LostResponse implements Exception {
  const _LostResponse();
}

/// Writes acceptances through the real repository, and can be told to fail once — the
/// case where the server committed and the *local* write is what went wrong.
class RecordingReconciler implements MutationReconciler {
  RecordingReconciler(this.repository);

  final ExpenseRepository repository;
  bool failNext = false;
  int calls = 0;

  @override
  Future<void> reconcile(
    PendingMutation mutation,
    MutationResult result,
  ) async {
    calls++;
    if (failNext) {
      failNext = false;
      throw StateError('local write failed');
    }
    final acceptance = ExpenseAcceptance.fromResult(
      mutation.entityId,
      result.serverPayload,
    );
    if (acceptance != null) await repository.reconcileAcceptance(acceptance);
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late ExpenseRepository expenses;

  /// The canonical expense reporting total for a period (D-168).
  ///
  /// Only server-accepted documents contribute, so a fixture that stays local contributes
  /// nothing — which is the correction Slice 1 made and the reason these tests now accept
  /// their expenses before asserting a figure.
  Future<Money> contributionsOf(
    String periodKey, {
    String? businessUnitId,
  }) async => (await expenses.contributionTotals(
    ExpenseContributionQuery(
      periodKey: periodKey,
      businessUnitId: businessUnitId,
    ),
  )).amount;

  late OutboxRepository outbox;
  late FakeExpenseServer server;
  late RecordingReconciler reconciler;
  var clock = DateTime.utc(2026, 6, 15, 10);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await seedMasterData(db, now: clock);
    expenses = ExpenseRepository(db);
    outbox = OutboxRepository(db);
    server = FakeExpenseServer();
    reconciler = RecordingReconciler(expenses);
  });

  tearDown(() => db.close());

  SyncEngine engineFor(String actor) => SyncEngine(
    outbox: outbox,
    endpoint: server,
    clock: () => clock,
    actorUserId: actor,
    reconciler: reconciler,
  );

  Future<String> saveOne({String actor = 'user-1'}) async {
    final expense = simpleExpense();
    final mutationId = const Uuid().v4();
    await expenses.createLocally(
      expense,
      actorUserId: actor,
      mutationId: mutationId,
      now: clock,
    );
    return expense.id;
  }

  group('the ordinary delivery', () {
    test('one push accepts it, numbers it and marks it synced', () async {
      final id = await saveOne();
      final report = await engineFor('user-1').pushOnce();

      expect(report.attempted, 1);
      expect(report.applied, 1);

      final local = await expenses.load(id);
      expect(local!.row.txnNumber, 'KI-EXP-26-27-000001');
      expect(local.row.rowVersion, 2);
      expect(local.row.pendingMutationId, isNull);
      expect(local.syncState, SyncState.synced);
      expect(server.committed, hasLength(1));
    });

    test('only the signed-in actor s work is delivered', () async {
      await saveOne(actor: 'user-a');
      await saveOne(actor: 'user-b');

      final report = await engineFor('user-a').pushOnce();
      expect(report.attempted, 1);
      expect(server.deliveries, hasLength(1));

      final queued = await db.select(db.syncOutbox).get();
      final other = queued.firstWhere((r) => r.actorUserId == 'user-b');
      expect(other.status, OutboxStatus.pending.name);
    });
  });

  group('server committed, response lost', () {
    test(
      'the retry carries the same mutation id and produces one expense',
      () async {
        final id = await saveOne();
        server.loseNextResponse = true;

        final first = await engineFor('user-1').pushOnce();
        expect(first.transientFailures, 1);
        expect(
          server.committed,
          hasLength(1),
          reason: 'the server did commit — that is the premise',
        );

        // Locally: still pending, still unnumbered, still the same intent.
        var local = await expenses.load(id);
        expect(local!.row.txnNumber, isNull);
        expect(local.syncState, SyncState.syncFailed);
        final queued = (await db.select(db.syncOutbox).get()).single;
        final mutationId = queued.mutationId;

        // The backoff elapses and the worker tries again.
        clock = clock.add(const Duration(minutes: 30));
        final second = await engineFor('user-1').pushOnce();

        expect(second.attempted, 1);
        expect(
          second.duplicatesReplayed,
          1,
          reason: 'the server recognised the intent and replayed its answer',
        );
        expect(
          server.deliveries,
          [mutationId, mutationId],
          reason: 'the same identity both times — never a fresh one',
        );
        expect(
          server.committed,
          hasLength(1),
          reason: 'exactly one financial record exists on the server',
        );

        local = await expenses.load(id);
        expect(local!.row.txnNumber, 'KI-EXP-26-27-000001');
        expect(local.syncState, SyncState.synced);
        expect(
          await db.select(db.expenses).get(),
          hasLength(1),
          reason: 'and exactly one locally',
        );
      },
    );

    test(
      'a local write that fails after acceptance leaves the intent queued',
      () async {
        final id = await saveOne();
        reconciler.failNext = true;

        final first = await engineFor('user-1').pushOnce();
        expect(first.applied, 0);
        expect(
          first.transientFailures,
          1,
          reason: 'accepted by the server, not yet recorded here',
        );

        final queued = (await db.select(db.syncOutbox).get()).single;
        expect(
          queued.status,
          OutboxStatus.failed.name,
          reason: 'not done — the local row has not learned its number yet',
        );
        expect(queued.lastError, contains('not yet recorded locally'));

        clock = clock.add(const Duration(minutes: 30));
        await engineFor('user-1').pushOnce();

        final local = await expenses.load(id);
        expect(local!.row.txnNumber, 'KI-EXP-26-27-000001');
        expect(local.syncState, SyncState.synced);
        expect(server.committed, hasLength(1));
        expect(await db.select(db.expenses).get(), hasLength(1));
      },
    );

    test('a third delivery of the same intent still changes nothing', () async {
      final id = await saveOne();
      await engineFor('user-1').pushOnce();

      // Force it back into the queue as a user might by retrying manually.
      final mutationId = server.deliveries.single;
      await outbox.updateStatus(
        mutationId,
        status: OutboxStatus.pending,
        nextAttemptAt: clock,
      );
      await engineFor('user-1').pushOnce();
      await outbox.updateStatus(
        mutationId,
        status: OutboxStatus.pending,
        nextAttemptAt: clock,
      );
      await engineFor('user-1').pushOnce();

      expect(server.deliveries, hasLength(3));
      expect(server.committed, hasLength(1));
      expect(await db.select(db.expenses).get(), hasLength(1));
      expect((await expenses.load(id))!.row.txnNumber, 'KI-EXP-26-27-000001');
    });
  });

  group('refusals are classified, not conflated', () {
    test('a stale version is a Conflict and is never retried', () async {
      await saveOne();
      server.refuseNextAs = RefusalKind.versionConflict;

      final report = await engineFor('user-1').pushOnce();
      expect(report.conflicts, 1);

      final queued = (await db.select(db.syncOutbox).get()).single;
      expect(queued.status, OutboxStatus.conflict.name);
      expect(
        OutboxStatus.conflict.isAutomaticallyRetryable,
        isFalse,
        reason: 'a human resolves a conflict; a worker must not guess',
      );
    });

    test('a closed period is terminal Rejected, not a Conflict', () async {
      await saveOne();
      server.refuseNextAs = RefusalKind.periodClosed;

      final report = await engineFor('user-1').pushOnce();
      expect(report.rejected, 1);
      expect(report.conflicts, 0);

      final queued = (await db.select(db.syncOutbox).get()).single;
      expect(queued.status, OutboxStatus.rejected.name);
      expect(
        OutboxStatus.rejected.userVisibleState,
        SyncState.rejected,
        reason:
            'the record did not move — telling the user somebody edited it '
            'would be a lie',
      );
    });

    test('a withdrawn permission is terminal Rejected', () async {
      // Queued while authorised, delivered after the scope was revoked. Authority at
      // delivery time is what counts, and the server decides it.
      await saveOne();
      server.refuseNextAs = RefusalKind.missingCapability;

      final report = await engineFor('user-1').pushOnce();
      expect(report.rejected, 1);

      final queued = (await db.select(db.syncOutbox).get()).single;
      expect(queued.status, OutboxStatus.rejected.name);
      expect(
        server.committed,
        isEmpty,
        reason: 'nothing was written — cached authority is not write authority',
      );

      // And the local row honestly reports that it is not on the server.
      final local = await expenses.load(
        (await db.select(db.expenses).get()).single.id,
      );
      expect(local!.syncState, SyncState.rejected);
      expect(local.syncState.isOnServer, isFalse);
      expect(local.row.txnNumber, isNull);
    });

    test('a rejected intent is kept and stays inspectable', () async {
      await saveOne();
      server.refuseNextAs = RefusalKind.missingCapability;
      await engineFor('user-1').pushOnce();

      clock = clock.add(const Duration(days: 1));
      final again = await engineFor('user-1').pushOnce();
      expect(again.attempted, 0, reason: 'terminal means terminal');

      final queued = (await db.select(db.syncOutbox).get()).single;
      expect(queued.payload, contains('p_total_minor'));
      expect(queued.lastError, isNotNull);
    });
  });

  group('what a delivered expense is worth', () {
    test('the reported total is unchanged by delivery', () async {
      final expense = sharedCrossPeriodExpense();
      await expenses.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: clock,
      );
      await engineFor('user-1').pushOnce();

      expect(
        await contributionsOf('2026-05') + await contributionsOf('2026-06'),
        Money.fromRupees(58000),
      );
    });
  });
}
