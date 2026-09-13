/// Cross-device reporting, against the real `krishna-mis-dev` project (Phase 5 Slice 4).
///
/// Skipped unless `KRISHNA_DEV_IDENTITIES` points at the development identity file, so an
/// ordinary `flutter test` run stays hermetic. Nothing here prints a password, a token or
/// the API key.
///
/// **What only a real server can prove.** The host suite drives the synchroniser against
/// a gateway that answers as a projection would. That proves the algorithm and proves
/// nothing about the projection: whether `change_seq` actually advances on a correction,
/// whether a void really comes back carrying `voided_at`, whether RLS scopes the delta the
/// way the detail reads are scoped, and whether the cached paise equal the server's own
/// aggregate to the paisa. Every one of those is a fact about Postgres, and this project's
/// record is that the defects live exactly there — D-115's RPC that had never created an
/// entry, D-116's capability no role held, D-160's ledger that never refreshed.
///
/// **Fixtures are reversed through the real API.** Every document created here is voided
/// with a stated reason naming this run (D-066, D-071); nothing is deleted, because
/// financial history is corrected by void and audit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:uuid/uuid.dart';
import '../support/cache_principal.dart';

const _identitiesVar = 'KRISHNA_DEV_IDENTITIES';

/// This run's marker, carried in every document's notes and in every void reason, so the
/// teardown can find its own work across a process boundary and nobody else's (D-071).
const _markerPrefix = 'phase5-slice4-';
final _marker = '$_markerPrefix${DateTime.now().toUtc().toIso8601String()}';

String _seedId(String path) =>
    const Uuid().v5('d9d3f0a6-4c2b-5f7e-9a10-6b1e2c8f4a70', path);

final _ccr = _seedId('bu:CCR');
final _hki = _seedId('bu:HKI');
final _kirana = _seedId('cat:CCR/FB/FOOD_PROD/KIRANA');
final _ccrDept = _seedId('dept:CCR/FB');
final _ccrSection = _seedId('sec:CCR/FB/FOOD_PROD');
final _hkiCategory = _seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY');
final _hkiDept = _seedId('dept:HKI/HKI_UTIL');
final _hkiSection = _seedId('sec:HKI/HKI_UTIL/HKI_POWER');

/// A quiet corner of the calendar, so a run cannot be confused by the fixtures of
/// another. Inside FY 2026-27, and inside no closed period (the project has none).
const _businessDate = '2026-11-12';
const _movedDate = '2026-12-03';
final _fy = const FinancialYear(2026);

ReportRange _rangeFor(String periodKey) {
  final parts = periodKey.split('-');
  final outcome = MonthPeriod(
    int.parse(parts[0]),
    int.parse(parts[1]),
  ).resolve();
  return (outcome as ReportRangeResolved).range;
}

void main() {
  final identitiesPath = Platform.environment[_identitiesVar];
  if (identitiesPath == null || !File(identitiesPath).existsSync()) return;

  final config =
      jsonDecode(File(r'config/dev.json').readAsStringSync())
          as Map<String, dynamic>;
  final identities =
      jsonDecode(File(identitiesPath).readAsStringSync())
          as Map<String, dynamic>;

  final clients = <String, SupabaseClient>{};

  Future<SupabaseClient> sessionFor(String email) async {
    final existing = clients[email];
    if (existing != null) return existing;
    final fresh = SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_ANON_KEY'] as String,
    );
    await fresh.auth.signInWithPassword(
      email: email,
      password:
          (identities[email] as Map<String, dynamic>)['password'] as String,
    );
    clients[email] = fresh;
    return fresh;
  }

  late SupabaseClient owner;
  late String ownerId;

  /// Everything this run created, so the teardown reverses exactly its own work.
  final createdRevenue = <String>[];
  final createdExpenses = <String>[];

  /// Voids every open document any run of this suite left behind, found by the marker
  /// prefix in its notes — the one identifier that survives a process boundary (D-071).
  ///
  /// Run **before** the fixtures rather than only after them, because a suite that
  /// depends on its own teardown having succeeded can pass exactly once (D-076). A
  /// previous run that failed partway leaves open sales; this reverses them through the
  /// legitimate workflow, and nothing else's, because nobody else writes this prefix.
  Future<int> reverseStrandedFixtures() async {
    var reversed = 0;
    for (final relation in const ['revenue_document', 'expense_document']) {
      final rows = await owner
          .from(relation)
          .select('id, row_version, notes')
          .isFilter('voided_at', null)
          .like('notes', '$_markerPrefix%');
      for (final row in rows) {
        await owner.rpc<dynamic>(
          relation == 'revenue_document' ? 'revenue_void' : 'expense_void',
          params: {
            'p_id': row['id'],
            'p_reason': 'Reversing a stranded reporting fixture ($_marker)',
            'p_base_row_version': row['row_version'],
            'p_mutation_id': const Uuid().v4(),
          },
        );
        reversed++;
      }
    }
    return reversed;
  }

  setUpAll(() async {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    owner = await sessionFor('giridhar@hki.com');
    ownerId = owner.auth.currentUser!.id;
    await reverseStrandedFixtures();
  });

  tearDownAll(() async {
    // Reversed through the legitimate workflow, never by deleting a row (D-006).
    for (final id in createdRevenue) {
      final row = await owner
          .from('revenue_document')
          .select('row_version, voided_at')
          .eq('id', id)
          .maybeSingle();
      if (row == null || row['voided_at'] != null) continue;
      await owner.rpc<dynamic>(
        'revenue_void',
        params: {
          'p_id': id,
          'p_reason': 'Reversing $_marker',
          'p_base_row_version': row['row_version'],
          'p_mutation_id': const Uuid().v4(),
        },
      );
    }
    for (final id in createdExpenses) {
      final row = await owner
          .from('expense_document')
          .select('row_version, voided_at')
          .eq('id', id)
          .maybeSingle();
      if (row == null || row['voided_at'] != null) continue;
      await owner.rpc<dynamic>(
        'expense_void',
        params: {
          'p_id': id,
          'p_reason': 'Reversing $_marker',
          'p_base_row_version': row['row_version'],
          'p_mutation_id': const Uuid().v4(),
        },
      );
    }
    // And a belt-and-braces sweep by marker, in case a test created a document the list
    // above never learned about — the failure mode a hard-coded fixture list has.
    final stranded = await reverseStrandedFixtures();
    expect(
      await reverseStrandedFixtures(),
      0,
      reason:
          'the run leaves nothing open. $stranded document(s) needed the sweep rather '
          'than the list, which is worth knowing rather than hiding',
    );
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  Future<String> categoryId(String unitId, String code) async {
    final row = await owner
        .from('revenue_categories')
        .select('id')
        .eq('code', code)
        .eq('business_unit_id', unitId)
        .single();
    return row['id'] as String;
  }

  /// One accepted sale, through the reviewed RPC — never a table write.
  Future<String> createSale({
    required String unitId,
    required String category,
    required int paise,
    String businessDate = _businessDate,
  }) async {
    final id = const Uuid().v7();
    await owner.rpc<dynamic>(
      'revenue_create',
      params: {
        'p_id': id,
        'p_business_unit_id': unitId,
        'p_revenue_category_id': await categoryId(unitId, category),
        'p_business_date': businessDate,
        'p_notes': _marker,
        'p_components': [
          {'entered_amount_minor': paise},
        ],
        'p_mutation_id': const Uuid().v4(),
      },
    );
    createdRevenue.add(id);
    return id;
  }

  Future<String> createExpense({
    required List<Map<String, Object>> allocations,
    String businessDate = _businessDate,
  }) async {
    final id = const Uuid().v7();
    final total = allocations.fold<int>(
      0,
      (sum, a) => sum + (a['amount_minor']! as int),
    );
    await owner.rpc<dynamic>(
      'expense_create',
      params: {
        'p_id': id,
        'p_business_date': businessDate,
        'p_total_minor': total,
        'p_notes': _marker,
        'p_allocations': allocations,
        'p_mutation_id': const Uuid().v4(),
      },
    );
    createdExpenses.add(id);
    return id;
  }

  /// A device: its own encrypted-shaped local database, its own cache, its own
  /// synchroniser, over one person's authenticated session.
  ({AppDatabase db, ReportingCache cache, ReportingSync sync}) deviceFor(
    SupabaseClient client,
    String userId,
  ) {
    final db = AppDatabase(NativeDatabase.memory());
    final cache = ReportingCache(db);
    return (
      db: db,
      cache: cache,
      sync: ReportingSync(
        cache: cache,
        gateway: ReportingGateway(client),
        ownerUserId: userId,
        orgId: 'live',
      ),
    );
  }

  Future<Money> serverRevenueGross(String unitId, String periodKey) async {
    final rows = await owner
        .from('revenue_period_contributions')
        .select('gross_minor, voided_at')
        .eq('business_unit_id', unitId)
        .eq('pnl_period_key', periodKey);
    return Money.fromPaise(
      rows
          .where((r) => r['voided_at'] == null)
          .fold<int>(0, (sum, r) => sum + (r['gross_minor'] as int)),
    );
  }

  Future<Money> serverExpenseTotal(String unitId, String periodKey) async {
    final rows = await owner
        .from('expense_period_contributions')
        .select('amount_minor, voided_at')
        .eq('business_unit_id', unitId)
        .eq('pnl_period_key', periodKey);
    return Money.fromPaise(
      rows
          .where((r) => r['voided_at'] == null)
          .fold<int>(0, (sum, r) => sum + (r['amount_minor'] as int)),
    );
  }

  group('the projection actually carries a usable generation (D-177)', () {
    test('a correction advances change_seq on the document', () async {
      final id = await createSale(
        unitId: _ccr,
        category: 'RESTAURANT',
        paise: 10000000,
      );
      final before =
          (await owner
                  .from('revenue_period_contributions')
                  .select('change_seq')
                  .eq('revenue_entry_id', id)
                  .single())['change_seq']
              as int;

      final version = (await owner
          .from('revenue_document')
          .select('row_version')
          .eq('id', id)
          .single())['row_version'];
      await owner.rpc<dynamic>(
        'revenue_update',
        params: {
          'p_id': id,
          'p_business_date': _businessDate,
          'p_notes': _marker,
          'p_components': [
            {'entered_amount_minor': 12000000},
          ],
          'p_base_row_version': version,
          'p_mutation_id': const Uuid().v4(),
        },
      );

      final after =
          (await owner
                  .from('revenue_period_contributions')
                  .select('change_seq')
                  .eq('revenue_entry_id', id)
                  .single())['change_seq']
              as int;

      expect(
        after,
        greaterThan(before),
        reason:
            'the whole delta rests on this. Before the D-172 corrective the revenue '
            'generation was frozen after INSERT, so a correction was invisible to any '
            'watermark and a cached figure would have stayed stale for ever',
      );
    });

    test('a void comes back carrying voided_at rather than vanishing', () async {
      final id = await createSale(
        unitId: _ccr,
        category: 'RESTAURANT',
        paise: 7000000,
      );
      final version = (await owner
          .from('revenue_document')
          .select('row_version')
          .eq('id', id)
          .single())['row_version'];
      await owner.rpc<dynamic>(
        'revenue_void',
        params: {
          'p_id': id,
          'p_reason': 'Void visibility check $_marker',
          'p_base_row_version': version,
          'p_mutation_id': const Uuid().v4(),
        },
      );

      final rows = await owner
          .from('revenue_period_contributions')
          .select('voided_at, change_seq')
          .eq('revenue_entry_id', id);

      expect(
        rows,
        isNotEmpty,
        reason:
            'if the projection filtered voided rows, a void would be invisible to the '
            'delta and the cache could never learn to drop it — the one hazard the '
            'document-grain replacement cannot cover on its own',
      );
      expect(rows.single['voided_at'], isNotNull);
    });
  });

  group('cache and server agree to the paisa (§34)', () {
    test('a fresh device reports what the server reports', () async {
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 7645000);
      await createSale(unitId: _ccr, category: 'NANDBHOG', paise: 870000);
      await createSale(unitId: _hki, category: 'BANQUET', paise: 4034300);
      await createExpense(
        allocations: [
          {
            'business_unit_id': _ccr,
            'department_id': _ccrDept,
            'section_id': _ccrSection,
            'category_id': _kirana,
            'amount_minor': 1840000,
          },
        ],
      );

      final device = deviceFor(owner, ownerId);
      addTearDown(device.db.close);

      final report = await device.sync.synchronise(
        businessUnitIds: {_ccr, _hki},
        years: [_fy],
      );
      expect(report.isComplete, isTrue, reason: report.toString());

      final period = _businessDate.substring(0, 7);
      final range = _rangeFor(period);

      for (final unit in [_ccr, _hki]) {
        expect(
          (await device.cache.revenueTotals(
            ownerUserId: ownerId,
            businessUnitId: unit,
            range: range,
          )).gross,
          await serverRevenueGross(unit, period),
          reason:
              'exact integer paise, not a tolerance. A reporting cache that is nearly '
              'right is a P&L that is wrong (spec §21.3)',
        );
        expect(
          (await device.cache.expenseTotals(
            ownerUserId: ownerId,
            businessUnitId: unit,
            range: range,
          )).amount,
          await serverExpenseTotal(unit, period),
        );
      }
    });

    test('Banquet keeps its treatment, distinct from a configured zero', () async {
      final id = await createSale(
        unitId: _hki,
        category: 'BANQUET',
        paise: 4034300,
      );

      final device = deviceFor(owner, ownerId);
      addTearDown(device.db.close);
      await device.sync.synchronise(businessUnitIds: {_hki}, years: [_fy]);

      final row = await device.db
          .customSelect(
            'SELECT tax_treatment, tax_rate_basis_points, tax_minor, gross_minor, '
            'net_minor FROM reporting_revenue_contributions '
            'WHERE owner_user_id = ? AND revenue_entry_id = ?',
            variables: [Variable<String>(ownerId), Variable<String>(id)],
          )
          .getSingle();

      expect(row.read<String>('tax_treatment'), 'none');
      expect(row.read<int>('tax_minor'), 0);
      expect(
        row.read<int>('net_minor'),
        row.read<int>('gross_minor'),
        reason: 'no GST, so the customer total is the net figure',
      );
      expect(
        row.read<int>('tax_rate_basis_points'),
        0,
        reason:
            'the treatment travels because `none` and a configured 0% both give zero '
            'tax and are not the same fact (D-091, D-122)',
      );
    });
  });

  group('two devices, one hotel (§22, §23)', () {
    test(
      'a device that recorded nothing reports the sale another recorded',
      () async {
        await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 5000000);

        final second = deviceFor(owner, ownerId);
        addTearDown(second.db.close);
        await second.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);

        final period = _businessDate.substring(0, 7);
        expect(
          (await second.cache.revenueTotals(
            ownerUserId: ownerId,
            businessUnitId: _ccr,
            range: _rangeFor(period),
          )).gross,
          await serverRevenueGross(_ccr, period),
          reason:
              'this is D-173, closed. The local revenue_entries table on this device is '
              'empty and the P&L is nonetheless the hotel figure',
        );
        expect(
          (await second.db
                  .customSelect('SELECT COUNT(*) AS n FROM revenue_entries')
                  .getSingle())
              .read<int>('n'),
          0,
          reason:
              'and it is a reporting cache rather than transaction replication: this '
              'device can report the sale and cannot open it',
        );
      },
    );

    test(
      'a correction on one device reaches the other on its next delta',
      () async {
        final id = await createSale(
          unitId: _ccr,
          category: 'RESTAURANT',
          paise: 3000000,
        );

        final second = deviceFor(owner, ownerId);
        addTearDown(second.db.close);
        await second.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
        final period = _businessDate.substring(0, 7);
        final before = (await second.cache.revenueTotals(
          ownerUserId: ownerId,
          businessUnitId: _ccr,
          range: _rangeFor(period),
        )).gross;

        final version = (await owner
            .from('revenue_document')
            .select('row_version')
            .eq('id', id)
            .single())['row_version'];
        await owner.rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': id,
            'p_business_date': _businessDate,
            'p_notes': _marker,
            'p_components': [
              {'entered_amount_minor': 4000000},
            ],
            'p_base_row_version': version,
            'p_mutation_id': const Uuid().v4(),
          },
        );

        await second.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
        final after = (await second.cache.revenueTotals(
          ownerUserId: ownerId,
          businessUnitId: _ccr,
          range: _rangeFor(period),
        )).gross;

        expect(after.paise - before.paise, 1000000);
        expect(
          after,
          await serverRevenueGross(_ccr, period),
          reason: 'replaced exactly once, never appended (§14)',
        );
      },
    );

    test('a business-date correction moves the money between periods', () async {
      final id = await createSale(
        unitId: _ccr,
        category: 'RESTAURANT',
        paise: 2500000,
      );

      final device = deviceFor(owner, ownerId);
      addTearDown(device.db.close);
      await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);

      final from = _businessDate.substring(0, 7);
      final to = _movedDate.substring(0, 7);
      final beforeFrom = (await device.cache.revenueTotals(
        ownerUserId: ownerId,
        businessUnitId: _ccr,
        range: _rangeFor(from),
      )).gross;

      final version = (await owner
          .from('revenue_document')
          .select('row_version')
          .eq('id', id)
          .single())['row_version'];
      await owner.rpc<dynamic>(
        'revenue_update',
        params: {
          'p_id': id,
          'p_business_date': _movedDate,
          'p_notes': _marker,
          'p_components': [
            {'entered_amount_minor': 2500000},
          ],
          'p_correction_reason':
              'Recorded against the wrong trading day $_marker',
          'p_base_row_version': version,
          'p_mutation_id': const Uuid().v4(),
        },
      );

      await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);

      expect(
        (await device.cache.revenueTotals(
          ownerUserId: ownerId,
          businessUnitId: _ccr,
          range: _rangeFor(from),
        )).gross,
        Money.fromPaise(beforeFrom.paise - 2500000),
        reason:
            'the case a period-filtered delta cannot see: November returns no row for a '
            'sale that has left November',
      );
      expect(
        (await device.cache.revenueTotals(
          ownerUserId: ownerId,
          businessUnitId: _ccr,
          range: _rangeFor(to),
        )).gross,
        await serverRevenueGross(_ccr, to),
      );
    });

    test('a void removes the effect on every device', () async {
      final id = await createSale(
        unitId: _ccr,
        category: 'RESTAURANT',
        paise: 1500000,
      );

      final device = deviceFor(owner, ownerId);
      addTearDown(device.db.close);
      await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
      final period = _businessDate.substring(0, 7);
      final before = (await device.cache.revenueTotals(
        ownerUserId: ownerId,
        businessUnitId: _ccr,
        range: _rangeFor(period),
      )).gross;

      final version = (await owner
          .from('revenue_document')
          .select('row_version')
          .eq('id', id)
          .single())['row_version'];
      await owner.rpc<dynamic>(
        'revenue_void',
        params: {
          'p_id': id,
          'p_reason': 'Duplicate entry $_marker',
          'p_base_row_version': version,
          'p_mutation_id': const Uuid().v4(),
        },
      );

      await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);

      expect(
        (await device.cache.revenueTotals(
          ownerUserId: ownerId,
          businessUnitId: _ccr,
          range: _rangeFor(period),
        )).gross,
        Money.fromPaise(before.paise - 1500000),
      );
      expect(
        (await device.db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM reporting_revenue_contributions '
                  'WHERE owner_user_id = ? AND revenue_entry_id = ?',
                  variables: [Variable<String>(ownerId), Variable<String>(id)],
                )
                .getSingle())
            .read<int>('n'),
        0,
        reason:
            'the cache holds the active effect only, so no reporting query has to '
            'remember to exclude a void — the rule Slice 1 found applied on one engine '
            'and not the other (D-168)',
      );
    });

    test(
      'a shared bill is attributed to both properties, and re-apportions',
      () async {
        final id = await createExpense(
          allocations: [
            {
              'business_unit_id': _ccr,
              'department_id': _ccrDept,
              'section_id': _ccrSection,
              'category_id': _kirana,
              'amount_minor': 2500000,
            },
            {
              'business_unit_id': _hki,
              'department_id': _hkiDept,
              'section_id': _hkiSection,
              'category_id': _hkiCategory,
              'amount_minor': 3300000,
            },
          ],
        );

        final device = deviceFor(owner, ownerId);
        addTearDown(device.db.close);
        await device.sync.synchronise(
          businessUnitIds: {_ccr, _hki},
          years: [_fy],
        );

        final period = _businessDate.substring(0, 7);
        expect(
          await serverExpenseTotal(_hki, period),
          (await device.cache.expenseTotals(
            ownerUserId: ownerId,
            businessUnitId: _hki,
            range: _rangeFor(period),
          )).amount,
        );

        // Re-apportioned wholly to Crystal Canopy. Hotel Krishna must be left with nothing
        // of it, which only the document-grain delete achieves.
        final hkiBefore = await serverExpenseTotal(_hki, period);
        final version = (await owner
            .from('expense_document')
            .select('row_version')
            .eq('id', id)
            .single())['row_version'];
        await owner.rpc<dynamic>(
          'expense_update',
          params: {
            'p_id': id,
            'p_business_date': _businessDate,
            'p_total_minor': 5800000,
            'p_notes': _marker,
            'p_allocations': [
              {
                'business_unit_id': _ccr,
                'department_id': _ccrDept,
                'section_id': _ccrSection,
                'category_id': _kirana,
                'amount_minor': 5800000,
              },
            ],
            'p_base_row_version': version,
            'p_mutation_id': const Uuid().v4(),
          },
        );

        await device.sync.synchronise(
          businessUnitIds: {_ccr, _hki},
          years: [_fy],
        );

        expect(
          (await device.cache.expenseTotals(
            ownerUserId: ownerId,
            businessUnitId: _hki,
            range: _rangeFor(period),
          )).amount,
          Money.fromPaise(hkiBefore.paise - 3300000),
          reason:
              'a line that no longer exists leaves no residue on the property it used to '
              'charge. Deletion is by document and is not scoped to a unit',
        );
        expect(
          (await device.cache.expenseTotals(
            ownerUserId: ownerId,
            businessUnitId: _hki,
            range: _rangeFor(period),
          )).amount,
          await serverExpenseTotal(_hki, period),
        );
      },
    );
  });

  group('offline after a successful sync (§33)', () {
    test('the P&L is produced with the transport removed', () async {
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 9000000);
      await createExpense(
        allocations: [
          {
            'business_unit_id': _ccr,
            'department_id': _ccrDept,
            'section_id': _ccrSection,
            'category_id': _kirana,
            'amount_minor': 1200000,
          },
        ],
      );

      final device = deviceFor(owner, ownerId);
      addTearDown(device.db.close);
      await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);

      // From here nothing may touch the network. The engine is built over the cache and
      // a marker oracle, both of which are local by construction.
      final engine = LocalReportingEngine(
        CachedReportingSource(
          cache: device.cache,
          principal: canonicalCachePrincipal(ownerId),
          coverage: await MarkerCoverage.load(device.cache, ownerId),
        ),
      );
      final parts = _businessDate.split('-');
      final envelope = await engine.report(
        ReportRequest(
          period: MonthPeriod(int.parse(parts[0]), int.parse(parts[1])),
          scope: ReportingScope.unit(_ccr),
        ),
      );

      expect(envelope.coverage, ReportingCoverage.complete);
      final result = envelope.outcome;
      expect(
        result,
        isA<PnlComputed>(),
        reason:
            'offline reporting is never gated on the network (spec §21.4). A month '
            'synchronised while online stays reportable with the radio off',
      );
      final period = _businessDate.substring(0, 7);
      final pnl = (result as PnlComputed).result;
      expect(pnl.grossSales, await serverRevenueGross(_ccr, period));
      expect(pnl.expenses, await serverExpenseTotal(_ccr, period));
    });
  });

  group('the delta is scoped by the reader own authority (§36)', () {
    test('a Crystal Canopy manager caches nothing of Hotel Krishna', () async {
      await createSale(unitId: _hki, category: 'BANQUET', paise: 2000000);
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 2000000);

      final manager = await sessionFor('ccr.manager@example.com');
      final managerId = manager.auth.currentUser!.id;
      final device = deviceFor(manager, managerId);
      addTearDown(device.db.close);

      await device.sync.synchronise(
        businessUnitIds: {_ccr, _hki},
        years: [_fy],
      );

      final units = await device.db
          .customSelect(
            'SELECT DISTINCT business_unit_id AS u '
            'FROM reporting_revenue_contributions WHERE owner_user_id = ?',
            variables: [Variable<String>(managerId)],
          )
          .get();
      expect(
        [for (final row in units) row.read<String>('u')],
        isNot(contains(_hki)),
        reason:
            'the delta inherits exactly the visibility the detail reads have — RLS on '
            'the projection, not a client-side filter. A bespoke delta RPC would have '
            'been a second place for that boundary to live',
      );
      expect(
        [for (final row in units) row.read<String>('u')],
        contains(_ccr),
        reason:
            'and the control: a suite where the manager sees nothing at all cannot '
            'tell "scoping works" from "the query is broken" (D-116)',
      );
    });

    test('an anonymous caller reads no contribution at all', () async {
      final anon = SupabaseClient(
        config['SUPABASE_URL'] as String,
        config['SUPABASE_ANON_KEY'] as String,
      );
      for (final dataset in ReportingDataset.values) {
        final outcome = await ReportingGateway(
          anon,
        ).changedContributions(dataset: dataset, sinceGeneration: 0);
        expect(
          switch (outcome) {
            RemoteOk(:final value) => value,
            _ => const <Map<String, dynamic>>[],
          },
          isEmpty,
          reason:
              '${dataset.wireName}: nothing in public is readable by anon (D-044)',
        );
      }
    });

    test(
      'the base tables stay unreadable, so the projection is the only way in',
      () async {
        for (final table in const ['revenue_components', 'expenses']) {
          await expectLater(
            owner.from(table).select('id').limit(1),
            throwsA(isA<PostgrestException>()),
            reason:
                '$table: a delta that could reach a base table would be a second read '
                'boundary, and the cheaper one to forget (D-062, D-162)',
          );
        }
      },
    );
  });
}
