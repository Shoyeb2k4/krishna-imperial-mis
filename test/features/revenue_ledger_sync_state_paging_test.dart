/// The Revenue ledger's sync-state filter is decided **before** the page is cut.
///
/// Until this remediation it was applied in Dart to whichever page the statement had
/// already cut, so a conflict older than the newest fifty sales was unreachable: page one
/// of "Conflict" read empty while older conflicts existed, and "is there another page"
/// answered no. The same defect class D-317 and D-323 closed for the Expense ledger,
/// reproduced here on the Revenue code itself rather than assumed from the analogy.
///
/// The fixture is shaped so the defect is visible: the newest sales are all synced, and
/// every conflict sits behind them, more than one page deep and more than one page long.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_filters.dart';

import '../support/test_session.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _restaurant = 'cat-restaurant';
const _room = 'cat-room';
const _userA = 'user-a';
const _userB = 'user-b';

/// Newest sales: synced, all on later business dates than any conflict.
const _syncedCount = 60;

/// Conflicts behind them: more than one page of 50, so page two matters.
const _conflictCount = 75;

/// How many of the conflicts are Hotel Krishna Room sales (the rest are CCR Restaurant).
const _conflictRoomCount = 30;

/// A session that a test can move to another person, as a user switch does.
class _SwitchableSession extends StubSession {
  _SwitchableSession(super.initial);

  void become(SessionState next) => state = next;
}

SessionState _sessionFor(String userId, Set<String> units) => readySession(
  authority: AuthoritySnapshot(
    userId: userId,
    orgId: _org,
    resolvedAt: DateTime.utc(2026, 10, 2),
    grants: [
      for (final unit in units)
        for (final capability in const [
          Capability.revenueCreate,
          Capability.revenueView,
          Capability.mastersView,
        ])
          CapabilityGrant(capability, businessUnitId: unit),
    ],
  ),
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late RevenueRepository repository;
  var seq = 0;

  Future<String> seed({
    required String date,
    required String capturedAt,
    String unit = _ccr,
    String category = _restaurant,
    String? outboxStatus,
    bool numbered = true,
  }) async {
    seq++;
    final id = 'entry-${seq.toString().padLeft(4, '0')}';
    await db.customStatement(
      'INSERT INTO revenue_entries (id, org_id, business_unit_id, '
      'revenue_category_id, business_date, pnl_period_key, captured_at, '
      'entry_kind, created_by, txn_number, financial_year, pending_mutation_id, '
      'row_version, updated_at) '
      "VALUES (?, ?, ?, ?, ?, ?, ?, 'daily_summary', ?, ?, ?, ?, 1, ?)",
      [
        id,
        _org,
        unit,
        category,
        date,
        date.substring(0, 7),
        capturedAt,
        _userA,
        numbered ? 'KI-REV-26-27-${seq.toString().padLeft(6, '0')}' : null,
        numbered ? '2026-27' : null,
        outboxStatus == null ? null : 'mut-$id',
        '2026-06-15T09:00:00.000Z',
      ],
    );
    await db.customStatement(
      'INSERT INTO revenue_components (id, org_id, revenue_entry_id, '
      'entered_amount_minor, entered_basis, gross_amount_minor, '
      'tax_amount_minor, net_amount_minor, tax_rule_id, tax_rate_basis_points, '
      'tax_treatment) '
      "VALUES (?, ?, ?, 105000, 'inclusive_total', 105000, 5000, 100000, "
      "'rule-x', 500, 'inclusive')",
      ['$id-c0', _org, id],
    );
    if (outboxStatus != null) {
      await db.customStatement(
        'INSERT INTO sync_outbox (mutation_id, actor_user_id, entity_type, '
        'entity_id, op, payload, next_attempt_at, status, created_at, '
        'attempt_count) '
        "VALUES (?, ?, ?, ?, 'update', '{}', ?, ?, ?, 0)",
        [
          'mut-$id',
          _userA,
          revenueEntityType,
          id,
          '2026-06-15T09:00:00.000Z',
          outboxStatus,
          '2026-06-15T09:00:00.000Z',
        ],
      );
    }
    return id;
  }

  /// Every conflict id, in the ledger's own order: business date, capture instant, id,
  /// all descending. Written from the fixture, not read back from the code under test.
  late List<String> conflictsInOrder;
  late List<String> roomConflictsInOrder;

  /// Every Hotel Krishna sale, conflicted or synced.
  late Set<String> hkiIds;

  setUp(() async {
    seq = 0;
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    repository = RevenueRepository(db);

    for (final unit in const [
      (_ccr, 'CCR', 'Crystal Canopy Rooftop'),
      (_hki, 'HKI', 'Hotel Krishna Imperial'),
    ]) {
      await db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, 'hotel', 'Asia/Kolkata', '05:00', 1, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [unit.$1, unit.$2, unit.$3],
      );
    }
    for (final c in const [
      (_restaurant, _ccr, 'RESTAURANT', 'Restaurant'),
      (_room, _hki, 'ROOM', 'Room'),
    ]) {
      await db.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, ?, 1, 1, '2026-04-01T00:00:00.000Z')",
        [c.$1, c.$2, c.$3, c.$4],
      );
    }

    // The conflicts first, on May dates. Groups of three share one business date and
    // one capture instant, so the id tie-break decides their order — and some of those
    // groups straddle the page boundary at 50.
    final conflicts = <({String id, String date, String captured})>[];
    final room = <String>{};
    for (var i = 0; i < _conflictCount; i++) {
      final day = 1 + i ~/ 3;
      final date = '2026-05-${day.toString().padLeft(2, '0')}';
      final captured = '${date}T10:00:00.000Z';
      final isRoom = i % 5 < 2 && room.length < _conflictRoomCount;
      final id = await seed(
        date: date,
        capturedAt: captured,
        unit: isRoom ? _hki : _ccr,
        category: isRoom ? _room : _restaurant,
        outboxStatus: OutboxStatus.conflict.name,
      );
      if (isRoom) room.add(id);
      conflicts.add((id: id, date: date, captured: captured));
    }
    // Then the newest sales, all synced, all in July: they fill the first page. Every
    // fourth is a Hotel Krishna Room sale, so the newest page holds rows a Crystal
    // Canopy-only reader must never be shown.
    hkiIds = <String>{...room};
    for (var i = 0; i < _syncedCount; i++) {
      final date = '2026-07-${(1 + i % 28).toString().padLeft(2, '0')}';
      final isHki = i % 4 == 0;
      final id = await seed(
        date: date,
        capturedAt: '${date}T0${i % 10}:00:00.000Z',
        unit: isHki ? _hki : _ccr,
        category: isHki ? _room : _restaurant,
      );
      if (isHki) hkiIds.add(id);
    }

    conflicts.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      final byCapture = b.captured.compareTo(a.captured);
      if (byCapture != 0) return byCapture;
      return b.id.compareTo(a.id);
    });
    conflictsInOrder = [for (final c in conflicts) c.id];
    roomConflictsInOrder = [
      for (final id in conflictsInOrder)
        if (room.contains(id)) id,
    ];
    expect(roomConflictsInOrder, hasLength(_conflictRoomCount));
  });

  tearDown(() => db.close());

  const conflictFilter = RevenueFilter(syncState: SyncState.conflict);

  Future<List<String>> walk(RevenueQuery filter) async {
    final seen = <String>[];
    for (var page = 0; ; page++) {
      final rows = await repository.query(
        filter,
        limit: revenuePageSize,
        offset: page * revenuePageSize,
      );
      seen.addAll(rows.map((r) => r.id));
      if (rows.length < revenuePageSize) break;
      if (page > 20) fail('paging did not end');
    }
    return seen;
  }

  group('the repository decides sync state before the page is cut', () {
    test('every conflict is reachable, beyond the first page', () async {
      final seen = await walk(conflictFilter);
      expect(seen, hasLength(_conflictCount));
      expect(seen, conflictsInOrder);
    });

    test('the first page fills from the whole matching set', () async {
      final first = await repository.query(
        conflictFilter,
        limit: revenuePageSize,
      );
      expect(first, hasLength(revenuePageSize));
      expect(first.map((r) => r.id), conflictsInOrder.take(revenuePageSize));
      expect(first.every((r) => r.syncState == SyncState.conflict), isTrue);
    });

    test('the second page continues exactly where the first ended', () async {
      final second = await repository.query(
        conflictFilter,
        limit: revenuePageSize,
        offset: revenuePageSize,
      );
      expect(
        second.map((r) => r.id).toList(),
        conflictsInOrder.skip(revenuePageSize).toList(),
      );
    });

    test('nothing is duplicated and nothing is skipped', () async {
      final seen = await walk(conflictFilter);
      expect(seen.toSet(), hasLength(seen.length), reason: 'no duplicate');
      expect(seen.toSet(), conflictsInOrder.toSet(), reason: 'no gap');
    });

    test(
      'whether another page exists is answered from matching rows',
      () async {
        // The ledger asks for one row beyond the page.
        final beyondFirst = await repository.query(
          conflictFilter,
          limit: 1,
          offset: revenuePageSize,
        );
        expect(beyondFirst, hasLength(1));
        final beyondSecond = await repository.query(
          conflictFilter,
          limit: 1,
          offset: 2 * revenuePageSize,
        );
        expect(beyondSecond, isEmpty);
      },
    );

    test('with no sync state the whole ledger is there', () async {
      final seen = await walk(const RevenueFilter());
      expect(seen, hasLength(_conflictCount + _syncedCount));
      expect(seen.toSet(), hasLength(_conflictCount + _syncedCount));
    });

    test('sync state combines with the other filters', () async {
      final seen = await walk(
        const RevenueFilter(
          syncState: SyncState.conflict,
          revenueCategoryId: _room,
        ),
      );
      expect(seen, roomConflictsInOrder);

      final scoped = await walk(
        const RevenueFilter(
          syncState: SyncState.conflict,
          businessUnitIds: {_ccr},
        ),
      );
      expect(scoped, hasLength(_conflictCount - _conflictRoomCount));
      expect(
        scoped.toSet().intersection(roomConflictsInOrder.toSet()),
        isEmpty,
      );

      final synced = await walk(
        const RevenueFilter(syncState: SyncState.synced),
      );
      expect(synced, hasLength(_syncedCount));
    });

    test('the SQL state is the Dart state, for every outbox status', () async {
      // One sale per status, plus an unnumbered and a numbered sale with nothing queued.
      // Every status this build knows must be found by its own filter and by no other.
      final expected = <String, SyncState>{};
      for (final status in OutboxStatus.values) {
        // The ledger joins only entries that are not done.
        if (status == OutboxStatus.done) continue;
        final id = await seed(
          date: '2026-08-01',
          capturedAt: '2026-08-01T10:00:00.000Z',
          outboxStatus: status.name,
        );
        expected[id] = status.userVisibleState;
      }
      expected[await seed(
            date: '2026-08-01',
            capturedAt: '2026-08-01T10:00:00.000Z',
            numbered: false,
          )] =
          SyncState.pendingSync;
      expected[await seed(
            date: '2026-08-01',
            capturedAt: '2026-08-01T10:00:00.000Z',
          )] =
          SyncState.synced;

      const august = RevenueFilter(from: '2026-08-01', to: '2026-08-01');
      final all = await repository.query(august);
      for (final row in all) {
        expect(row.syncState, expected[row.id], reason: row.id);
      }
      for (final state in SyncState.values) {
        final found = await repository.query(
          RevenueFilter(from: '2026-08-01', to: '2026-08-01', syncState: state),
        );
        expect(found.map((r) => r.id).toSet(), {
          for (final e in expected.entries)
            if (e.value == state) e.key,
        }, reason: state.name);
      }
    });
  });

  group('the ledger providers', () {
    late _SwitchableSession session;
    late ProviderContainer container;

    setUp(() async {
      session = _SwitchableSession(_sessionFor(_userA, {_ccr, _hki}));
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(() => session),
        ],
      );
      addTearDown(container.dispose);
      container.listen(filteredRevenueProvider, (_, _) {});
      container.listen(revenueHasMoreProvider, (_, _) {});
      // The filter is rebuilt once the master graph has loaded; wait for that.
      await container.read(masterGraphProvider.future);
    });

    Future<List<String>> page() async => [
      for (final row in await container.read(filteredRevenueProvider.future))
        row.id,
    ];

    Future<bool> hasMore() => container.read(revenueHasMoreProvider.future);

    void filterBy(RevenueFilter Function(RevenueFilter) change) {
      final notifier = container.read(revenueFilterProvider.notifier);
      notifier.update(change(container.read(revenueFilterProvider)));
    }

    test('both conflict pages are reachable, and say so', () async {
      filterBy((f) => f.copyWith(syncState: SyncState.conflict));
      expect(await page(), conflictsInOrder.take(revenuePageSize));
      expect(await hasMore(), isTrue);

      container.read(revenuePageProvider.notifier).next();
      expect(await page(), conflictsInOrder.skip(revenuePageSize));
      expect(await hasMore(), isFalse);
    });

    test('changing the sync state returns to the first page', () async {
      filterBy((f) => f.copyWith(syncState: SyncState.conflict));
      container.read(revenuePageProvider.notifier).next();
      expect(container.read(revenuePageProvider), 1);

      filterBy((f) => f.copyWith(syncState: SyncState.synced));
      expect(container.read(revenuePageProvider), 0);
      final synced = await page();
      expect(synced, hasLength(revenuePageSize));
      expect(synced.toSet().intersection(conflictsInOrder.toSet()), isEmpty);
    });

    test('clearing the sync state restores the full ledger', () async {
      filterBy((f) => f.copyWith(syncState: SyncState.conflict));
      container.read(revenuePageProvider.notifier).next();
      filterBy((f) => f.copyWith(clearSync: true));

      expect(container.read(revenuePageProvider), 0);
      final first = await page();
      expect(first, hasLength(revenuePageSize));
      expect(
        first.toSet().intersection(conflictsInOrder.toSet()),
        isEmpty,
        reason: 'the newest fifty are the synced July sales',
      );
      expect(await hasMore(), isTrue);
    });

    test(
      "a person change publishes none of the previous person's rows",
      () async {
        expect(
          (await page()).toSet().intersection(hkiIds),
          isNotEmpty,
          reason:
              'the fixture is only meaningful if A sees Hotel Krishna sales',
        );
        filterBy((f) => f.copyWith(syncState: SyncState.conflict));
        container.read(revenuePageProvider.notifier).next();
        expect((await page()).toSet().intersection(hkiIds), isNotEmpty);

        final published = <List<String>>[];
        container.listen(filteredRevenueProvider, (_, next) {
          if (next case AsyncData(:final value)) {
            published.add([for (final r in value) r.id]);
          }
        });

        session.become(_sessionFor(_userB, {_ccr}));
        await container.read(masterGraphProvider.future);
        final after = await page();

        expect(container.read(revenueFilterProvider).syncState, isNull);
        expect(container.read(revenueFilterProvider).businessUnitIds, {_ccr});
        expect(container.read(revenuePageProvider), 0);
        expect(after, hasLength(revenuePageSize));
        expect(after.toSet().intersection(hkiIds), isEmpty);

        // B's own conflict filter, both pages: Crystal Canopy conflicts only.
        filterBy((f) => f.copyWith(syncState: SyncState.conflict));
        final bConflicts = await page();
        expect(bConflicts, [
          for (final id in conflictsInOrder)
            if (!hkiIds.contains(id)) id,
        ]);
        expect(await hasMore(), isFalse);

        expect(published, isNotEmpty);
        for (final ids in published) {
          expect(
            ids.toSet().intersection(hkiIds),
            isEmpty,
            reason: 'a Hotel Krishna sale published after the switch to B',
          );
        }
      },
    );
  });
}
