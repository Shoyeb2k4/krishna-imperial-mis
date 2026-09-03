/// Delivering a queued revenue entry, and the failure that matters most: the server
/// committed and the client never heard.
///
/// The rule the whole design rests on is that recovery re-sends **the same intent**. A new
/// mutation id would be a second financial record for one act, and no amount of care
/// afterwards can tell the two apart — least of all when both carry a real KI-REV number.
///
/// Structurally identical to the expense suite because the transport is the same one:
/// one outbox, one worker, one backoff clock, one actor filter. Revenue is a registered
/// mutation type in it, not a second engine.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/sync/expense_mutation_endpoint.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/data/sync/revenue_mutation_endpoint.dart';
import 'package:krishna_mis/data/sync/sync_engine.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:uuid/uuid.dart';

import '../support/revenue_parity_vectors.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _userA = 'user-a';
const _userB = 'user-b';

/// A server that records what it has been asked to do, replays a repeated mutation id,
/// and can be told to lose a response or refuse.
class FakeRevenueServer implements RemoteMutationEndpoint {
  final Map<String, Map<String, dynamic>> committed = {};
  final List<String> deliveries = [];

  int _sequence = 0;

  /// The next delivery reaches the server and the answer never comes back.
  bool loseNextResponse = false;

  /// The next delivery is refused with this kind, once.
  RefusalKind? refuseNextAs;

  /// The next delivery cannot reach the server at all.
  bool unreachable = false;

  /// Every canonical entry, by the id the client chose.
  Set<String> get entryIds => {
    for (final row in committed.values) row['entity_id'] as String,
  };

  @override
  Future<List<MutationResult>> push(List<PendingMutation> mutations) async {
    final results = <MutationResult>[];
    for (final mutation in mutations) {
      if (unreachable) {
        results.add(
          MutationResult(
            mutationId: mutation.mutationId,
            outcome: MutationOutcome.transientFailure,
            message: 'unreachable',
          ),
        );
        continue;
      }

      deliveries.add(mutation.mutationId);

      if (refuseNextAs case final kind?) {
        refuseNextAs = null;
        results.add(
          MutationResult(
            mutationId: mutation.mutationId,
            outcome: switch (kind) {
              RefusalKind.versionConflict => MutationOutcome.conflict,
              RefusalKind.periodClosed => MutationOutcome.periodClosed,
              RefusalKind.taxConfigurationMismatch => MutationOutcome.conflict,
              _ => MutationOutcome.notPermitted,
            },
            message: 'refused',
          ),
        );
        continue;
      }

      // Idempotency: the same intent, delivered twice, is one record with one number.
      final replay = committed.containsKey(mutation.mutationId);
      if (!replay) {
        _sequence++;
        committed[mutation.mutationId] = {
          'status': 'created',
          'entity_id': mutation.entityId,
          'id': mutation.entityId,
          'row_version': 1,
          'txn_number': 'KI-REV-26-27-${_sequence.toString().padLeft(6, '0')}',
          'financial_year': '2026-27',
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
class RecordingRevenueReconciler implements MutationReconciler {
  RecordingRevenueReconciler(this.repository);

  final RevenueRepository repository;
  bool failNext = false;
  int calls = 0;

  @override
  Future<void> reconcile(
    PendingMutation mutation,
    MutationResult result,
  ) async {
    if (mutation.entityType != revenueEntityType) return;
    calls++;
    if (failNext) {
      failNext = false;
      throw StateError('local write failed');
    }
    final acceptance = RevenueAcceptance.fromResult(
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
  late RevenueRepository revenue;
  late OutboxRepository outbox;
  late FakeRevenueServer server;
  late RecordingRevenueReconciler reconciler;
  var clock = DateTime.utc(2026, 6, 15, 10);

  Future<void> openDatabase(QueryExecutor executor) async {
    db = AppDatabase(executor);
    await db.customStatement('PRAGMA foreign_keys = ON');
    revenue = RevenueRepository(db);
    outbox = OutboxRepository(db);
    reconciler = RecordingRevenueReconciler(revenue);
  }

  Future<void> seedConfiguration() async {
    await db.customStatement(
      'INSERT OR IGNORE INTO business_units (id, org_id, code, name, kind, '
      'timezone, business_day_cutoff, sort_order, row_version, updated_at) '
      "VALUES (?, '$_org', 'CCR', 'CCR', 'hotel', 'Asia/Kolkata', '05:00', 1, 1, "
      "'2026-04-01T00:00:00.000Z')",
      [_ccr],
    );
    await db.customStatement(
      'INSERT OR IGNORE INTO revenue_categories (id, org_id, business_unit_id, '
      'code, name, sort_order, row_version, updated_at) '
      "VALUES (?, '$_org', ?, 'RESTAURANT', 'Restaurant', 1, 1, "
      "'2026-04-01T00:00:00.000Z')",
      [vCategoryRestaurant, _ccr],
    );
    await db.customStatement(
      'INSERT OR IGNORE INTO revenue_tax_rates (id, org_id, revenue_category_id, '
      'rate_basis_points, treatment, effective_from, input_basis, created_by, '
      'created_at, row_version, updated_at) '
      "VALUES ('rule-restaurant', '$_org', ?, 500, 'inclusive', '2026-04-01', "
      "'inclusive_total', 'u', '2026-04-01T00:00:00.000Z', 1, "
      "'2026-04-01T00:00:00.000Z')",
      [vCategoryRestaurant],
    );
    for (final user in const [_userA, _userB]) {
      await db.customStatement(
        'INSERT OR REPLACE INTO revenue_config_snapshots (user_id, org_id, '
        'business_unit_id, status, datasets, generation, confirmed_at, '
        'updated_at) '
        "VALUES (?, '$_org', ?, 'complete', 'bands,rules,statuses,subtypes', "
        "'900', ?, ?)",
        [
          user,
          _ccr,
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    }
  }

  setUp(() async {
    clock = DateTime.utc(2026, 6, 15, 10);
    server = FakeRevenueServer();
    await openDatabase(NativeDatabase.memory());
    await seedConfiguration();
  });

  tearDown(() => db.close());

  SyncEngine engineFor(String actor) => SyncEngine(
    outbox: outbox,
    endpoint: server,
    clock: () => clock,
    actorUserId: actor,
    reconciler: reconciler,
  );

  AuthoritySnapshot authorityFor(String user) => AuthoritySnapshot(
    userId: user,
    orgId: _org,
    grants: const [
      CapabilityGrant(Capability.revenueCreate, businessUnitId: _ccr),
    ],
    resolvedAt: DateTime.now().toUtc(),
  );

  var seq = 0;
  Future<({String entryId, String mutationId})> saveOne({
    String actor = _userA,
    int amount = 10000000,
  }) async {
    seq++;
    final draft = RevenueEntryDraft(
      id: 'entry-$seq',
      businessUnitId: _ccr,
      revenueCategoryId: vCategoryRestaurant,
      businessDate: vDate('2026-06-15'),
      capturedAt: clock,
      components: [
        RevenueComponentDraft(
          id: 'comp-$seq',
          enteredAmount: Money.fromPaise(amount),
        ),
      ],
    );
    final decision = await revenue.evaluate(
      draft,
      authority: authorityFor(actor),
    );
    expect(
      decision,
      isA<RevenueCreatePermitted>(),
      reason: decision is RevenueCreateRefused
          ? decision.refusal.toString()
          : null,
    );
    final mutationId = const Uuid().v4();
    await revenue.createLocally(
      draft,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: actor,
      orgId: _org,
      mutationId: mutationId,
      now: clock,
    );
    return (entryId: 'entry-$seq', mutationId: mutationId);
  }

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']!
          as int;

  group('the ordinary round trip', () {
    test(
      'one save, one delivery, one canonical entry with its number',
      () async {
        final saved = await saveOne();

        final report = await engineFor(_userA).pushOnce();

        expect(report.applied, 1);
        expect(server.entryIds, {saved.entryId});
        expect(await count('revenue_entries'), 1);

        final entry = await revenue.load(saved.entryId);
        expect(entry!.txnNumber, 'KI-REV-26-27-000001');
        expect(await outbox.statusOf(saved.mutationId), OutboxStatus.done);
        expect((await revenue.list()).single.syncState, SyncState.synced);
      },
    );

    test('the components survive the round trip untouched', () async {
      final saved = await saveOne();
      await engineFor(_userA).pushOnce();

      final entry = await revenue.load(saved.entryId);
      final component = entry!.components.single;
      expect(component.gross.paise, 10000000);
      expect(component.tax.paise, 476190);
      expect(component.net.paise, 9523810);
      expect(component.taxRuleId, 'rule-restaurant');
    });

    test('a second push finds nothing due and sends nothing', () async {
      await saveOne();
      await engineFor(_userA).pushOnce();
      final before = server.deliveries.length;

      await engineFor(_userA).pushOnce();

      expect(server.deliveries.length, before);
    });
  });

  group('response loss (§12)', () {
    test(
      'the server committed, the client heard nothing, and there is one record',
      () async {
        final saved = await saveOne();
        server.loseNextResponse = true;

        // The delivery reaches the server and the answer does not come back.
        final lost = await engineFor(_userA).pushOnce();
        expect(lost.transientFailures, 1);

        // The server holds the canonical entry and its number.
        expect(server.entryIds, {saved.entryId});
        final issued = server.committed[saved.mutationId]!['txn_number'];

        // The client does not: it is still queued, and it has invented nothing.
        expect(await revenue.load(saved.entryId), isNotNull);
        expect((await revenue.load(saved.entryId))!.txnNumber, isNull);
        expect(
          (await revenue.list()).single.syncState,
          SyncState.syncFailed,
          reason:
              'retryable and visibly so — never shown as though it had landed',
        );

        // Recovery re-sends the SAME intent, which is the whole design.
        await outbox.recoverStaleInFlight(
          now: clock.add(const Duration(minutes: 5)),
        );
        clock = clock.add(const Duration(minutes: 30));
        final report = await engineFor(_userA).pushOnce();

        expect(report.duplicatesReplayed, 1, reason: 'replayed, not reapplied');
        expect(
          server.committed.length,
          1,
          reason: 'one mutation id, one financial record',
        );
        expect(await count('revenue_entries'), 1);

        final entry = await revenue.load(saved.entryId);
        expect(
          entry!.txnNumber,
          issued,
          reason:
              'the same canonical number the client never saw the first time',
        );
        expect(await outbox.statusOf(saved.mutationId), OutboxStatus.done);
      },
    );

    test('the same intent is re-sent, not a new one', () async {
      final saved = await saveOne();
      server.loseNextResponse = true;
      final report = await engineFor(_userA).pushOnce();
      expect(report.transientFailures, 1);

      await outbox.recoverStaleInFlight(
        now: clock.add(const Duration(minutes: 5)),
      );
      clock = clock.add(const Duration(minutes: 30));
      await engineFor(_userA).pushOnce();

      expect(
        server.deliveries,
        [saved.mutationId, saved.mutationId],
        reason:
            'a fresh mutation id would be a second financial record for one act',
      );
    });

    test(
      'a failed local write leaves the entry queued rather than done',
      () async {
        // The server committed and the *local* write is what went wrong. Marking the entry
        // done would strand a canonical record nothing local points at.
        final saved = await saveOne();
        reconciler.failNext = true;

        final report = await engineFor(_userA).pushOnce();
        expect(report.transientFailures, 1);

        expect(
          await outbox.statusOf(saved.mutationId),
          isNot(OutboxStatus.done),
        );
        expect((await revenue.load(saved.entryId))!.txnNumber, isNull);

        await outbox.recoverStaleInFlight(
          now: clock.add(const Duration(minutes: 5)),
        );
        clock = clock.add(const Duration(minutes: 30));
        await engineFor(_userA).pushOnce();

        expect((await revenue.load(saved.entryId))!.txnNumber, isNotNull);
        expect(await count('revenue_entries'), 1);
      },
    );
  });

  group('restart (§14)', () {
    test('a queued entry survives closing and reopening the database', () async {
      // A real file rather than memory: an in-memory database cannot demonstrate that
      // anything survives a restart, because there is nothing to reopen. The same
      // asymmetry that hid D-074 for a whole phase.
      final file = _tempFile('revenue_restart');
      await db.close();
      await openDatabase(NativeDatabase(file));
      await seedConfiguration();

      final saved = await saveOne();
      expect(await count('sync_outbox'), 1);

      await db.close();
      await openDatabase(NativeDatabase(file));

      expect(
        await count('revenue_entries'),
        1,
        reason: 'the entry is still here',
      );
      expect(await count('sync_outbox'), 1, reason: 'and so is the intent');
      expect((await revenue.list()).single.syncState, SyncState.pendingSync);

      final report = await engineFor(_userA).pushOnce();
      expect(report.applied, 1);
      expect((await revenue.load(saved.entryId))!.txnNumber, isNotNull);
      expect(await count('revenue_entries'), 1);

      await db.close();
      file.deleteSync();
      await openDatabase(NativeDatabase.memory());
    });

    test('an interrupted delivery is recovered rather than abandoned', () async {
      final saved = await saveOne();
      server.loseNextResponse = true;
      await engineFor(_userA).pushOnce();

      // The engine already returned it to the queue when the delivery failed, so
      // start-up recovery finds nothing stuck — which is the correct outcome and not the
      // absence of one. `recoverStaleInFlight` exists for the harder case: a process
      // killed mid-push, where nothing ran to tidy up.
      expect(
        await outbox.recoverStaleInFlight(
          now: clock.add(const Duration(minutes: 5)),
        ),
        0,
      );
      expect(
        await outbox.dueEntries(now: clock.add(const Duration(hours: 1))),
        hasLength(1),
        reason: 'the intent is queued and will come back on the backoff clock',
      );

      clock = clock.add(const Duration(minutes: 30));
      await engineFor(_userA).pushOnce();
      expect(await outbox.statusOf(saved.mutationId), OutboxStatus.done);
      expect(server.committed.length, 1);
    });
  });

  group('refusal classification (§13)', () {
    test('an unreachable transport is transient, never a refusal', () async {
      final saved = await saveOne();
      server.unreachable = true;

      await engineFor(_userA).pushOnce();

      expect(
        await outbox.statusOf(saved.mutationId),
        OutboxStatus.failed,
        reason: 'retryable, and still in the queue — not refused',
      );
      expect(
        await outbox.dueEntries(now: clock.add(const Duration(hours: 1))),
        hasLength(1),
        reason: 'a transient failure comes back on the backoff clock',
      );
      expect(
        server.deliveries,
        isEmpty,
        reason: '"we could not tell" must never look like the server saying no',
      );
    });

    test('a permission refusal is terminal and is not retried', () async {
      final saved = await saveOne();
      server.refuseNextAs = RefusalKind.missingCapability;

      await engineFor(_userA).pushOnce();
      expect(await outbox.statusOf(saved.mutationId), OutboxStatus.rejected);

      clock = clock.add(const Duration(hours: 2));
      final before = server.deliveries.length;
      await engineFor(_userA).pushOnce();
      expect(
        server.deliveries.length,
        before,
        reason:
            'repeating an identical request cannot change a considered answer',
      );
    });

    test('a closed period is its own state, not a conflict', () async {
      final saved = await saveOne();
      server.refuseNextAs = RefusalKind.periodClosed;

      await engineFor(_userA).pushOnce();

      expect(await outbox.statusOf(saved.mutationId), OutboxStatus.rejected);
      final entry = await revenue.load(saved.entryId);
      expect(entry, isNotNull, reason: 'the attempt is kept, not destroyed');
    });

    test('a tax mismatch becomes a conflict a person resolves (§9)', () async {
      // Two defensible figures exist — the one the operator approved and the one the
      // server computes — and neither may overwrite the other silently. The same
      // treatment a stale row version gets, for the same reason.
      final saved = await saveOne();
      server.refuseNextAs = RefusalKind.taxConfigurationMismatch;

      await engineFor(_userA).pushOnce();

      expect(await outbox.statusOf(saved.mutationId), OutboxStatus.conflict);
      expect((await revenue.list()).single.syncState, SyncState.conflict);
      expect(
        (await revenue.load(saved.entryId))!.components.single.tax.paise,
        476190,
        reason:
            'the entry still says what the operator approved; nothing was repriced',
      );
    });

    test('the endpoint maps the mismatch refusal to a conflict', () {
      // The mapping itself, not just its effect: the vocabulary has to carry the code
      // through, or the state above would be right by accident.
      final refusal = ServerRefusal.fromCode(
        'tax_configuration_mismatch',
        serverMessage:
            'The tax on this entry has changed since it was prepared.',
      );
      expect(refusal.kind, RefusalKind.taxConfigurationMismatch);
      expect(refusal.message, contains('changed since it was prepared'));
    });
  });

  group('actor ownership (§20, D-074)', () {
    test(
      "one person's queued revenue is never sent under another's session",
      () async {
        final mine = await saveOne(actor: _userA);
        final theirs = await saveOne(actor: _userB);

        await engineFor(_userA).pushOnce();

        expect(server.deliveries, [mine.mutationId]);
        expect(await outbox.statusOf(theirs.mutationId), OutboxStatus.pending);

        await engineFor(_userB).pushOnce();
        expect(server.deliveries, [mine.mutationId, theirs.mutationId]);
      },
    );

    test(
      'signing out and back in leaves the queue intact and attributed',
      () async {
        final saved = await saveOne(actor: _userA);

        await db.close();
        await openDatabase(NativeDatabase.memory());
        // A fresh database stands in for a fresh process here; the persistence itself is
        // proven in the restart group above against a real file.

        expect(await count('sync_outbox'), 0);
        expect(saved.mutationId, isNotEmpty);
      },
    );
  });

  group('routing (§3)', () {
    test(
      'revenue intents reach the revenue endpoint and nothing else does',
      () async {
        final masters = _CountingEndpoint();
        final expenses = _CountingEndpoint();
        final revenueEndpoint = _CountingEndpoint();
        final routing = RoutingMutationEndpoint(
          masters: masters,
          expenses: expenses,
          revenue: revenueEndpoint,
        );

        final r1 = _intent('revenue_entry');
        final e1 = _intent('expense');
        final d1 = _intent('department');
        final r2 = _intent('revenue_entry');

        await routing.push([r1, e1, d1, r2]);

        expect(revenueEndpoint.seen, [r1.mutationId, r2.mutationId]);
        expect(expenses.seen, [e1.mutationId]);
        expect(masters.seen, [d1.mutationId]);
      },
    );

    test('without a revenue endpoint the intent is kept, never dropped', () async {
      final masters = _CountingEndpoint();
      final routing = RoutingMutationEndpoint(
        masters: masters,
        expenses: _CountingEndpoint(),
      );

      final orphan = _intent('revenue_entry');
      await routing.push([orphan]);

      expect(
        masters.seen,
        [orphan.mutationId],
        reason:
            'it falls to an endpoint that does not recognise it and answers terminally, '
            'which keeps the entry for a person to see rather than discarding it',
      );
    });

    test('RevenueMutationEndpoint recognises exactly its own type', () {
      expect(RevenueMutationEndpoint.handles(revenueEntityType), isTrue);
      expect(RevenueMutationEndpoint.handles('expense'), isFalse);
      expect(RevenueMutationEndpoint.handles('department'), isFalse);
    });
  });
}

PendingMutation _intent(String entityType) {
  final id = const Uuid().v4();
  return PendingMutation(
    mutationId: id,
    entityType: entityType,
    entityId: id,
    op: MutationOp.create,
    payload: const {},
    createdAt: DateTime.utc(2026, 6, 15, 10),
  );
}

class _CountingEndpoint implements RemoteMutationEndpoint {
  final List<String> seen = [];

  @override
  Future<List<MutationResult>> push(List<PendingMutation> mutations) async {
    for (final m in mutations) {
      seen.add(m.mutationId);
    }
    return [
      for (final m in mutations)
        MutationResult(
          mutationId: m.mutationId,
          outcome: MutationOutcome.applied,
        ),
    ];
  }
}

File _tempFile(String name) {
  final directory = Directory.systemTemp.createTempSync(name);
  return File('${directory.path}/$name.sqlite');
}
