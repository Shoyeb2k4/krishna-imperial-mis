/// The Windows revenue ledger: what it asks the database for, and what it refuses to show.
///
/// Two kinds of assertion here, and the second matters more than the first.
///
/// The ordinary kind checks that a filter filters and a page pages. The important kind
/// checks that **paging cannot skip or duplicate a row**, and that a retained attempt
/// belonging to somebody else never appears — the defect Windows exposed once already,
/// and only because its database had accumulated history a fresh install does not have
/// (D-074).
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_filters.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _restaurant = 'cat-restaurant';
const _nandbhog = 'cat-nandbhog';
const _room = 'cat-room';
const _banquet = 'cat-banquet';
const _userA = 'user-a';
const _userB = 'user-b';

MasterNode _node(String id, String code, String name, {String? parent}) =>
    MasterNode(id: id, code: code, name: name, parentId: parent);

MasterGraph _graph() => MasterGraph(
  departments: const [],
  sections: const [],
  expenseCategories: const [],
  businessUnits: [
    _node(_ccr, 'CCR', 'Crystal Canopy Rooftop'),
    _node(_hki, 'HKI', 'Hotel Krishna Imperial'),
  ],
  revenueCategories: [
    _node(_restaurant, 'RESTAURANT', 'Restaurant', parent: _ccr),
    _node(_nandbhog, 'NANDBHOG', 'Nandbhog', parent: _ccr),
    _node(_room, 'ROOM', 'Room', parent: _hki),
    _node(_banquet, 'BANQUET', 'Banquet', parent: _hki),
  ],
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late RevenueRepository repository;

  // Reset per test, so an assertion may name the id it just created.
  var seq = 0;

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
      (_nandbhog, _ccr, 'NANDBHOG', 'Nandbhog'),
      (_room, _hki, 'ROOM', 'Room'),
      (_banquet, _hki, 'BANQUET', 'Banquet'),
    ]) {
      await db.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, ?, 1, 1, '2026-04-01T00:00:00.000Z')",
        [c.$1, c.$2, c.$3, c.$4],
      );
      await db.customStatement(
        'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
        'rate_basis_points, treatment, effective_from, input_basis, created_by, '
        'created_at, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, ?, '2026-04-01', 'inclusive_total', 'u', "
        "'2026-04-01T00:00:00.000Z', 1, '2026-04-01T00:00:00.000Z')",
        [
          'rule-${c.$3}',
          c.$1,
          c.$3 == 'BANQUET' ? 0 : 500,
          c.$3 == 'BANQUET' ? 'none' : 'inclusive',
        ],
      );
    }
  });

  tearDown(() => db.close());

  /// Writes one sale directly, so a ledger test can build history without driving a form.
  Future<String> seed({
    String category = _restaurant,
    String unit = _ccr,
    String date = '2026-06-15',
    int amount = 10000000,
    int rateBp = 500,
    String treatment = 'inclusive',
    String actor = _userA,
    String? txnNumber,
    String? sourceReference,
    String? notes,
    String entryKind = 'daily_summary',
    bool voided = false,
    bool quarantined = false,
    String? outboxStatus,
    int components = 1,
    String? capturedAt,
  }) async {
    seq++;
    final id = 'entry-${seq.toString().padLeft(3, '0')}';
    final tax = treatment == 'none'
        ? 0
        : (2 * amount * rateBp + (10000 + rateBp)) ~/ (2 * (10000 + rateBp));

    await db.customStatement(
      'INSERT INTO revenue_entries (id, org_id, business_unit_id, '
      'revenue_category_id, business_date, pnl_period_key, captured_at, '
      'entry_kind, source_reference, notes, created_by, txn_number, '
      'financial_year, voided_at, voided_by, void_reason, scope_revoked_at, '
      'pending_mutation_id, row_version, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)',
      [
        id,
        _org,
        unit,
        category,
        date,
        date.substring(0, 7),
        capturedAt ??
            '2026-06-15T${(9 + seq % 12).toString().padLeft(2, '0')}:00:00.000Z',
        entryKind,
        sourceReference,
        notes,
        actor,
        txnNumber,
        txnNumber == null ? null : '2026-27',
        voided ? '2026-06-20T00:00:00.000Z' : null,
        // A void states who and why, and the schema refuses one that does not
        // (spec §14). The fixture obeys the rule rather than working around it.
        voided ? actor : null,
        voided ? 'Recorded twice' : null,
        quarantined ? '2026-06-21T00:00:00.000Z' : null,
        outboxStatus == null ? null : 'mut-$id',
        '2026-06-15T09:00:00.000Z',
      ],
    );

    for (var i = 0; i < components; i++) {
      final share = amount ~/ components;
      final shareTax = treatment == 'none'
          ? 0
          : (2 * share * rateBp + (10000 + rateBp)) ~/ (2 * (10000 + rateBp));
      await db.customStatement(
        'INSERT INTO revenue_components (id, org_id, revenue_entry_id, '
        'entered_amount_minor, entered_basis, gross_amount_minor, '
        'tax_amount_minor, net_amount_minor, tax_rule_id, tax_rate_basis_points, '
        'tax_treatment) '
        "VALUES (?, ?, ?, ?, 'inclusive_total', ?, ?, ?, ?, ?, ?)",
        [
          '$id-c$i',
          _org,
          id,
          share,
          share,
          shareTax,
          share - shareTax,
          'rule-x',
          rateBp,
          treatment,
        ],
      );
    }

    if (outboxStatus != null) {
      await db.customStatement(
        'INSERT INTO sync_outbox (mutation_id, actor_user_id, entity_type, '
        'entity_id, op, payload, next_attempt_at, status, created_at, '
        'attempt_count) '
        "VALUES (?, ?, ?, ?, 'create', '{}', ?, ?, ?, 0)",
        [
          'mut-$id',
          actor,
          revenueEntityType,
          id,
          '2026-06-15T09:00:00.000Z',
          outboxStatus,
          '2026-06-15T09:00:00.000Z',
        ],
      );
    }

    // Unused, and kept so the signature reads the way the fixture is used.
    if (tax < 0) throw StateError('unreachable');
    return id;
  }

  group('the default ledger', () {
    test('shows everything visible, newest business date first', () async {
      await seed(date: '2026-06-10');
      await seed(date: '2026-06-20');
      await seed(date: '2026-06-15');

      final rows = await repository.query(const RevenueFilter());

      expect(rows.map((r) => r.businessDate.iso), [
        '2026-06-20',
        '2026-06-15',
        '2026-06-10',
      ]);
    });

    test('excludes voided sales unless asked', () async {
      await seed();
      await seed(voided: true);

      expect(await repository.query(const RevenueFilter()), hasLength(1));
      expect(
        await repository.query(const RevenueFilter(includeVoided: true)),
        hasLength(2),
        reason:
            'voided sales are history, and history has to be reachable (D-006)',
      );
    });

    test('carries the columns the desktop table shows', () async {
      await seed(
        txnNumber: 'KI-REV-26-27-000001',
        sourceReference: 'TILL-4',
        notes: 'Evening',
        actor: _userA,
      );

      final row = (await repository.query(const RevenueFilter())).single;

      expect(row.txnNumber, 'KI-REV-26-27-000001');
      expect(row.displayReference, 'KI-REV-26-27-000001');
      expect(row.businessUnitId, _ccr);
      expect(row.revenueCategoryId, _restaurant);
      expect(row.gross.paise, 10000000);
      expect(row.tax.paise, 476190);
      expect(row.net.paise, 9523810);
      expect(row.componentCount, 1);
      expect(row.createdBy, _userA);
      expect(row.entryKind, RevenueEntryKind.dailySummary);
      expect(row.sourceReference, 'TILL-4');
      expect(row.rowVersion, 1);
    });

    test(
      'an unnumbered sale shows a pending reference, never a fake one',
      () async {
        await seed(outboxStatus: 'pending');

        final row = (await repository.query(const RevenueFilter())).single;

        expect(row.txnNumber, isNull);
        expect(row.displayReference, startsWith('Pending number'));
        expect(
          row.displayReference,
          isNot(contains('KI-REV')),
          reason:
              'a permanent-looking reference that later changes is worse than none',
        );
      },
    );
  });

  group('ordering is deterministic', () {
    test('same date and same instant still order stably', () async {
      // Without the `id` tie-break these three have no defined order, and an undefined
      // order across a page boundary is how a row gets shown twice or skipped.
      for (var i = 0; i < 3; i++) {
        await seed(date: '2026-06-15', capturedAt: '2026-06-15T09:00:00.000Z');
      }

      final first = await repository.query(const RevenueFilter());
      final second = await repository.query(const RevenueFilter());

      expect(first.map((r) => r.id).toList(), second.map((r) => r.id).toList());
      expect(
        first.map((r) => r.id).toList(),
        ['entry-003', 'entry-002', 'entry-001'],
        reason: 'id descending, as the query states',
      );
    });
  });

  group('paging', () {
    test('covers every row exactly once across pages', () async {
      for (var i = 0; i < 25; i++) {
        await seed(date: '2026-06-${(i % 28 + 1).toString().padLeft(2, '0')}');
      }

      final seen = <String>[];
      for (var page = 0; page < 5; page++) {
        final rows = await repository.query(
          const RevenueFilter(),
          limit: 6,
          offset: page * 6,
        );
        seen.addAll(rows.map((r) => r.id));
      }

      expect(seen, hasLength(25), reason: 'nothing skipped');
      expect(seen.toSet(), hasLength(25), reason: 'nothing duplicated');
    });

    test('a page beyond the end is empty rather than an error', () async {
      await seed();
      expect(
        await repository.query(const RevenueFilter(), limit: 10, offset: 100),
        isEmpty,
      );
    });

    test('paging respects the filter it was applied with', () async {
      for (var i = 0; i < 8; i++) {
        await seed(category: _restaurant);
      }
      for (var i = 0; i < 8; i++) {
        await seed(category: _room, unit: _hki);
      }

      final seen = <String>[];
      for (var page = 0; page < 3; page++) {
        final rows = await repository.query(
          const RevenueFilter(revenueCategoryId: _room),
          limit: 3,
          offset: page * 3,
        );
        seen.addAll(rows.map((r) => r.id));
      }

      expect(seen, hasLength(8));
      expect(seen.toSet(), hasLength(8));
      for (final id in seen) {
        final row = (await repository.query(
          const RevenueFilter(revenueCategoryId: _room),
          limit: 100,
        )).firstWhere((r) => r.id == id);
        expect(row.revenueCategoryId, _room);
      }
    });
  });

  group('filters', () {
    test(
      'date range is inclusive at both ends, on the business date',
      () async {
        await seed(date: '2026-06-01');
        await seed(date: '2026-06-15');
        await seed(date: '2026-06-30');

        final rows = await repository.query(
          const RevenueFilter(from: '2026-06-01', to: '2026-06-15'),
        );

        expect(rows.map((r) => r.businessDate.iso), [
          '2026-06-15',
          '2026-06-01',
        ]);
      },
    );

    test(
      'the date filter follows the trading day, not the capture instant',
      () async {
        // Recorded at 02:00 on the 16th; it belongs to the 15th under D-067. A ledger that
        // filtered on `captured_at` would put it in the wrong month of somebody's report.
        await seed(date: '2026-06-15', capturedAt: '2026-06-15T20:30:00.000Z');

        expect(
          await repository.query(
            const RevenueFilter(from: '2026-06-15', to: '2026-06-15'),
          ),
          hasLength(1),
        );
        expect(
          await repository.query(
            const RevenueFilter(from: '2026-06-16', to: '2026-06-16'),
          ),
          isEmpty,
        );
      },
    );

    test('business unit', () async {
      await seed(unit: _ccr, category: _restaurant);
      await seed(unit: _hki, category: _room);

      final rows = await repository.query(
        const RevenueFilter(businessUnitId: _hki),
      );
      expect(rows.single.businessUnitId, _hki);
    });

    test('revenue category', () async {
      await seed(category: _restaurant);
      await seed(category: _nandbhog);

      final rows = await repository.query(
        const RevenueFilter(revenueCategoryId: _nandbhog),
      );
      expect(rows.single.revenueCategoryId, _nandbhog);
    });

    test('entry kind', () async {
      await seed();
      await seed(entryKind: 'correction');

      final rows = await repository.query(
        const RevenueFilter(entryKind: RevenueEntryKind.correction),
      );
      expect(rows.single.entryKind, RevenueEntryKind.correction);
    });

    test('entered by', () async {
      await seed(actor: _userA);
      await seed(actor: _userB);

      final rows = await repository.query(
        const RevenueFilter(enteredByUserId: _userB),
      );
      expect(rows.single.createdBy, _userB);
    });

    test('search matches a transaction number', () async {
      await seed(txnNumber: 'KI-REV-26-27-000042');
      await seed(txnNumber: 'KI-REV-26-27-000099');

      final rows = await repository.query(
        const RevenueFilter(search: '000042'),
      );
      expect(rows.single.txnNumber, 'KI-REV-26-27-000042');
    });

    test('search matches a source reference and a note', () async {
      await seed(sourceReference: 'TILL-7');
      await seed(notes: 'Diwali evening');
      await seed();

      expect(
        (await repository.query(
          const RevenueFilter(search: 'TILL-7'),
        )).single.sourceReference,
        'TILL-7',
      );
      expect(
        (await repository.query(
          const RevenueFilter(search: 'Diwali'),
        )).single.notes,
        'Diwali evening',
      );
    });

    test('search does not match the internal identity', () async {
      final id = await seed();

      expect(
        await repository.query(RevenueFilter(search: id)),
        isEmpty,
        reason:
            'a UUID is an identity, not a reference anybody reads and types',
      );
    });

    test('status filter uses the canonical vocabulary', () async {
      await seed(txnNumber: 'KI-REV-26-27-000001');
      await seed(outboxStatus: 'pending');
      await seed(outboxStatus: 'conflict');

      expect(
        (await repository.query(
          const RevenueFilter(syncState: SyncState.synced),
        )).single.txnNumber,
        'KI-REV-26-27-000001',
      );
      expect(
        await repository.query(
          const RevenueFilter(syncState: SyncState.pendingSync),
        ),
        hasLength(1),
      );
      expect(
        await repository.query(
          const RevenueFilter(syncState: SyncState.conflict),
        ),
        hasLength(1),
      );
    });

    test('combined filters narrow rather than replace each other', () async {
      await seed(unit: _ccr, category: _restaurant, date: '2026-06-10');
      await seed(unit: _ccr, category: _restaurant, date: '2026-07-10');
      await seed(unit: _ccr, category: _nandbhog, date: '2026-06-10');
      await seed(unit: _hki, category: _room, date: '2026-06-10');

      final rows = await repository.query(
        const RevenueFilter(
          from: '2026-06-01',
          to: '2026-06-30',
          businessUnitId: _ccr,
          revenueCategoryId: _restaurant,
        ),
      );

      expect(rows, hasLength(1));
      expect(rows.single.businessDate.iso, '2026-06-10');
    });

    test(
      'a filter pair that cannot match returns nothing, not everything',
      () async {
        await seed(unit: _ccr, category: _restaurant);

        // Hotel Krishna + Restaurant. The filter bar prevents this; the query must not
        // quietly widen if something else constructs it.
        expect(
          await repository.query(
            const RevenueFilter(
              businessUnitId: _hki,
              revenueCategoryId: _restaurant,
            ),
          ),
          isEmpty,
        );
      },
    );
  });

  group('scope is authority, not a filter', () {
    test('rows outside the permitted units are never returned', () async {
      await seed(unit: _ccr, category: _restaurant);
      await seed(unit: _hki, category: _room);

      final rows = await repository.query(
        const RevenueFilter(businessUnitIds: {_ccr}),
      );

      expect(rows, hasLength(1));
      expect(rows.single.businessUnitId, _ccr);
    });

    test(
      'scope applies before paging, so a window cannot span forbidden rows',
      () async {
        for (var i = 0; i < 5; i++) {
          await seed(unit: _hki, category: _room);
        }
        await seed(unit: _ccr, category: _restaurant);

        final page = await repository.query(
          const RevenueFilter(businessUnitIds: {_ccr}),
          limit: 3,
        );

        expect(page, hasLength(1));
        expect(page.single.businessUnitId, _ccr);
      },
    );
  });

  group('quarantined work never reaches the ledger (D-070, D-074)', () {
    test('a retained attempt is absent, and is not deleted', () async {
      await seed();
      await seed(quarantined: true, outboxStatus: 'pending');

      expect(await repository.query(const RevenueFilter()), hasLength(1));
      expect(
        await repository.query(const RevenueFilter(includeVoided: true)),
        hasLength(1),
        reason: 'no toggle on this screen can reveal it',
      );

      final stored = await db
          .customSelect('SELECT COUNT(*) AS n FROM revenue_entries')
          .getSingle();
      expect(stored.data['n'], 2, reason: 'hidden, not destroyed');
    });

    test('a status filter cannot surface one either', () async {
      await seed(quarantined: true, outboxStatus: 'pending');

      for (final state in SyncState.values) {
        expect(
          await repository.query(RevenueFilter(syncState: state)),
          isEmpty,
          reason: 'no ${state.name} filter may reveal retained work',
        );
      }
    });

    test('a search cannot surface one either', () async {
      await seed(
        quarantined: true,
        outboxStatus: 'pending',
        notes: 'findable',
        sourceReference: 'TILL-9',
      );

      expect(
        await repository.query(const RevenueFilter(search: 'findable')),
        isEmpty,
      );
      expect(
        await repository.query(const RevenueFilter(search: 'TILL-9')),
        isEmpty,
      );
    });

    test(
      "user B does not see user A's retained work, same scope or not",
      () async {
        await seed(actor: _userA, quarantined: true, outboxStatus: 'pending');

        // Both hold Crystal Canopy. Scope is not authorship (D-074).
        expect(
          await repository.query(const RevenueFilter(businessUnitIds: {_ccr})),
          isEmpty,
        );
        expect(
          await repository.listRetainedAfterRevocation(_userA),
          hasLength(1),
        );
        expect(await repository.listRetainedAfterRevocation(_userB), isEmpty);
      },
    );

    test(
      'canonical synced history is unaffected by another actor being retained',
      () async {
        // The distinction §11 asks for: an actor's retained attempt is hidden, and the
        // property's ordinary synced history is not.
        await seed(actor: _userA, quarantined: true, outboxStatus: 'pending');
        await seed(actor: _userA, txnNumber: 'KI-REV-26-27-000001');

        final rows = await repository.query(
          const RevenueFilter(businessUnitIds: {_ccr}),
        );

        expect(rows, hasLength(1));
        expect(rows.single.txnNumber, 'KI-REV-26-27-000001');
        expect(rows.single.syncState, SyncState.synced);
      },
    );
  });

  group('the accumulated-database case Windows exposed once already', () {
    setUp(() async {
      // A workstation that has been used: synced history, a pending attempt, a voided
      // sale, a conflict and a rejection, across two actors and both properties. A fresh
      // database cannot see the defects this shape can (D-074).
      await seed(actor: _userA, txnNumber: 'KI-REV-26-27-000001');
      await seed(actor: _userA, txnNumber: 'KI-REV-26-27-000002', voided: true);
      await seed(actor: _userA, outboxStatus: 'pending');
      await seed(actor: _userA, outboxStatus: 'conflict');
      await seed(actor: _userB, outboxStatus: 'rejected');
      await seed(
        actor: _userB,
        unit: _hki,
        category: _room,
        txnNumber: 'KI-REV-26-27-000003',
      );
      await seed(actor: _userB, quarantined: true, outboxStatus: 'pending');
    });

    test(
      'an authorised reader sees the canonical history and nothing retained',
      () async {
        final rows = await repository.query(
          const RevenueFilter(businessUnitIds: {_ccr, _hki}),
        );

        expect(
          rows,
          hasLength(5),
          reason: 'the voided one and the retained one are out',
        );
        expect(rows.every((r) => r.voidedAt == null), isTrue);
      },
    );

    test('every status renders from the canonical mapping', () async {
      final rows = await repository.query(
        const RevenueFilter(businessUnitIds: {_ccr, _hki}),
      );
      final states = rows.map((r) => r.syncState).toSet();

      expect(states, contains(SyncState.synced));
      expect(states, contains(SyncState.pendingSync));
      expect(states, contains(SyncState.conflict));
      expect(states, contains(SyncState.rejected));
    });

    test(
      'a scoped reader sees only their property, retained work still absent',
      () async {
        final rows = await repository.query(
          const RevenueFilter(businessUnitIds: {_hki}),
        );

        expect(rows, hasLength(1));
        expect(rows.single.txnNumber, 'KI-REV-26-27-000003');
      },
    );

    test('filters stay correct against accumulated history', () async {
      expect(
        await repository.query(
          const RevenueFilter(
            businessUnitIds: {_ccr, _hki},
            includeVoided: true,
          ),
        ),
        hasLength(6),
      );
      expect(
        await repository.query(
          const RevenueFilter(
            businessUnitIds: {_ccr, _hki},
            syncState: SyncState.synced,
          ),
        ),
        hasLength(2),
      );
    });
  });

  group('the detail load', () {
    test('returns the component snapshot, not today\'s configuration', () async {
      final id = await seed(rateBp: 500, treatment: 'inclusive');

      // The configuration changes afterwards. The recorded sale must not move.
      await db.customStatement('DELETE FROM revenue_tax_rates');

      final entry = await repository.load(id);

      expect(entry, isNotNull);
      expect(entry!.components.single.taxRateBasisPoints, 500);
      expect(entry.components.single.taxTreatment, TaxTreatment.inclusive);
      expect(entry.components.single.tax.paise, 476190);
    });

    test(
      'an untaxed sale is distinguishable from a configured zero rate',
      () async {
        final untaxed = await seed(
          category: _banquet,
          unit: _hki,
          amount: 4034300,
          rateBp: 0,
          treatment: 'none',
        );
        final zeroRate = await seed(
          category: _restaurant,
          amount: 4034300,
          rateBp: 0,
        );

        final a = (await repository.load(untaxed))!.components.single;
        final b = (await repository.load(zeroRate))!.components.single;

        expect(a.tax, Money.zero);
        expect(b.tax, Money.zero);
        expect(
          a.taxTreatment,
          TaxTreatment.none,
          reason: 'a treatment somebody chose',
        );
        expect(
          b.taxTreatment,
          TaxTreatment.inclusive,
          reason: 'a rate somebody set — the same ₹0 and a different statement',
        );
      },
    );

    test('a multi-component sale keeps every part separate', () async {
      final id = await seed(amount: 6000000, components: 2);

      final entry = await repository.load(id);

      expect(entry!.components, hasLength(2));
      expect(
        entry.gross.paise,
        entry.components.fold<int>(0, (sum, c) => sum + c.gross.paise),
      );
      expect(entry.tax.paise + entry.net.paise, entry.gross.paise);
    });
  });

  group('the filter model', () {
    test('changing property clears a category from the other one', () {
      const filter = RevenueFilter(
        businessUnitId: _ccr,
        revenueCategoryId: _restaurant,
      );

      final moved = filter.withBusinessUnit(_hki, _graph());

      expect(moved.businessUnitId, _hki);
      expect(
        moved.revenueCategoryId,
        isNull,
        reason: 'HKI + Restaurant matches nothing and reads as "no sales"',
      );
    });

    test('changing property keeps a category that still belongs to it', () {
      const filter = RevenueFilter(revenueCategoryId: _room);
      final moved = filter.withBusinessUnit(_hki, _graph());

      expect(moved.revenueCategoryId, _room);
    });

    test(
      'clearing the property keeps the category, which is still answerable',
      () {
        const filter = RevenueFilter(
          businessUnitId: _ccr,
          revenueCategoryId: _restaurant,
        );

        final cleared = filter.withBusinessUnit(null, _graph());

        expect(cleared.businessUnitId, isNull);
        expect(cleared.revenueCategoryId, isNull);
      },
    );

    test('a revoked scope drops the filters that named it', () {
      const filter = RevenueFilter(
        businessUnitId: _hki,
        revenueCategoryId: _room,
      );

      final constrained = filter.constrainedTo({_ccr}, _graph());

      expect(constrained.businessUnitId, isNull);
      expect(
        constrained.revenueCategoryId,
        isNull,
        reason:
            'a filter naming a lost property reads as an empty ledger rather '
            'than as a revoked permission',
      );
      expect(constrained.businessUnitIds, {_ccr});
    });

    test('a scope that still covers the filter leaves it alone', () {
      const filter = RevenueFilter(
        businessUnitId: _ccr,
        revenueCategoryId: _restaurant,
      );

      final constrained = filter.constrainedTo({_ccr, _hki}, _graph());

      expect(constrained.businessUnitId, _ccr);
      expect(constrained.revenueCategoryId, _restaurant);
    });

    test('isDefault ignores the scope, which is not a filter', () {
      expect(const RevenueFilter().isDefault, isTrue);
      expect(
        const RevenueFilter(businessUnitIds: {_ccr}).isDefault,
        isTrue,
        reason: 'authority is not something a Clear filters button may drop',
      );
      expect(const RevenueFilter(search: 'x').isDefault, isFalse);
      expect(const RevenueFilter(includeVoided: true).isDefault, isFalse);
    });
  });
}
