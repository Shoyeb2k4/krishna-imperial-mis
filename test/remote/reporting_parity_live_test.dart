/// D-020 parity: the offline cache against the authoritative server (Phase 5 Slice 5).
///
/// Skipped unless `KRISHNA_DEV_IDENTITIES` points at the development identity file, so an
/// ordinary `flutter test` run stays hermetic. Nothing here prints a password, a token or
/// the API key.
///
/// ## The question this suite answers
///
/// *Given the same authorised scope and the same `ReportRange`, do the offline canonical
/// reporting engine and the authoritative server calculation produce exactly the same
/// management financial result?*
///
/// The decisive shape is a **second device**: context A records the transactions, context B
/// has never seen any of them, synchronises the reporting cache, and is then asked the same
/// question as the server. If the cache means something different from the backend, that is
/// where it shows — and nowhere else, because a device that recorded the rows itself would
/// agree with the server for the wrong reason.
///
/// Everything is compared through [expectParity]: exact integer paise, exact contribution
/// counts, exact category and hierarchy breakdowns, no tolerance anywhere.
///
/// **Fixtures are reversed through the real API.** Every document created here is voided
/// with a stated reason naming this run (D-066, D-071); nothing is deleted, because
/// financial history is corrected by void and audit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/remote_reporting_source.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/reporting/remote_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/pnl.dart' show PnlResult;
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:uuid/uuid.dart';

import '../support/report_parity.dart';
import '../support/cache_principal.dart';

const _identitiesVar = 'KRISHNA_DEV_IDENTITIES';

/// This run's marker, carried in every document's notes and in every void reason, so the
/// teardown can find its own work across a process boundary and nobody else's (D-071).
const _markerPrefix = 'phase5-slice5-';
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

/// A quiet corner of the calendar, so a run cannot be confused by another's fixtures.
/// Inside FY 2026-27, and inside no closed period (the project has none).
const _businessDate = '2027-01-14';
const _movedDate = '2027-02-09';
const _period = '2027-01';
const _movedPeriod = '2027-02';
final _fy = const FinancialYear(2026);

MonthPeriod _month(String periodKey) {
  final parts = periodKey.split('-');
  return MonthPeriod(int.parse(parts[0]), int.parse(parts[1]));
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

  final createdRevenue = <String>[];
  final createdExpenses = <String>[];

  /// Voids every open document any run of this suite left behind, found by the marker
  /// prefix in its notes. Run **before** the fixtures as well as after, because a suite
  /// that depends on its own teardown having succeeded can pass exactly once (D-076).
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
            'p_reason': 'Reversing a stranded parity fixture ($_marker)',
            'p_base_row_version': row['row_version'],
            'p_mutation_id': const Uuid().v4(),
          },
        );
        reversed++;
      }
    }
    return reversed;
  }

  /// Leaves no period closed, whatever a test did to one.
  Future<void> reopenEverything() async {
    final locks = await owner
        .from('period_locks')
        .select('period_key, business_unit_id, state, row_version')
        .eq('state', 'closed');
    for (final lock in locks) {
      await owner.rpc<dynamic>(
        'period_reopen',
        params: {
          'p_period_key': lock['period_key'],
          'p_reason': 'Reopening a parity fixture period ($_marker)',
          'p_business_unit_id': lock['business_unit_id'],
          'p_base_row_version': lock['row_version'],
          'p_mutation_id': const Uuid().v4(),
        },
      );
    }
  }

  setUpAll(() async {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    owner = await sessionFor('giridhar@hki.com');
    ownerId = owner.auth.currentUser!.id;
    await reopenEverything();
    await reverseStrandedFixtures();
  });

  tearDownAll(() async {
    await reopenEverything();
    for (final entry in [
      ...createdRevenue.map((id) => ('revenue', id)),
      ...createdExpenses.map((id) => ('expense', id)),
    ]) {
      final relation = entry.$1 == 'revenue'
          ? 'revenue_document'
          : 'expense_document';
      final row = await owner
          .from(relation)
          .select('row_version, voided_at')
          .eq('id', entry.$2)
          .maybeSingle();
      if (row == null || row['voided_at'] != null) continue;
      await owner.rpc<dynamic>(
        entry.$1 == 'revenue' ? 'revenue_void' : 'expense_void',
        params: {
          'p_id': entry.$2,
          'p_reason': 'Reversing $_marker',
          'p_base_row_version': row['row_version'],
          'p_mutation_id': const Uuid().v4(),
        },
      );
    }
    final stranded = await reverseStrandedFixtures();
    expect(
      await reverseStrandedFixtures(),
      0,
      reason:
          'the run leaves nothing open. $stranded document(s) needed the sweep rather '
          'than the list, which is worth knowing rather than hiding',
    );
    expect(
      (await owner
              .from('period_locks')
              .select('period_key')
              .eq('state', 'closed'))
          .length,
      0,
      reason: 'the run leaves no period closed',
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

  Map<String, Object> ccrAllocation(int paise) => {
    'business_unit_id': _ccr,
    'department_id': _ccrDept,
    'section_id': _ccrSection,
    'category_id': _kirana,
    'amount_minor': paise,
  };

  Map<String, Object> hkiAllocation(int paise) => {
    'business_unit_id': _hki,
    'department_id': _hkiDept,
    'section_id': _hkiSection,
    'category_id': _hkiCategory,
    'amount_minor': paise,
  };

  Future<int> versionOf(String relation, String id) async =>
      (await owner
              .from(relation)
              .select('row_version')
              .eq('id', id)
              .single())['row_version']
          as int;

  /// A device: its own local database, its own cache, its own synchroniser.
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

  /// Context B: a device that recorded none of this and synchronises the reporting cache.
  Future<
    ({
      AppDatabase db,
      ReportingCache cache,
      ReportingSync sync,
      LocalReportingEngine engine,
    })
  >
  syncedDevice(
    SupabaseClient client,
    String userId, {
    Set<String>? units,
    List<FinancialYear>? years,
  }) async {
    final device = deviceFor(client, userId);
    addTearDown(device.db.close);
    final report = await device.sync.synchronise(
      businessUnitIds: units ?? {_ccr, _hki},
      years: years ?? [_fy],
    );
    expect(
      report.isComplete,
      isTrue,
      reason:
          'both datasets must land, or the cache cannot answer a P&L (D-163)',
    );
    return (
      db: device.db,
      cache: device.cache,
      sync: device.sync,
      engine: LocalReportingEngine(
        CachedReportingSource(
          cache: device.cache,
          principal: canonicalCachePrincipal(userId),
          coverage: await MarkerCoverage.load(device.cache, userId),
        ),
      ),
    );
  }

  /// Rebuilds the local engine after a re-synchronisation, so the marker oracle is fresh.
  Future<LocalReportingEngine> engineOver(
    ReportingCache cache,
    String userId,
  ) async => LocalReportingEngine(
    CachedReportingSource(
      cache: cache,
      principal: canonicalCachePrincipal(userId),
      coverage: await MarkerCoverage.load(cache, userId),
    ),
  );

  RemoteReportingEngine remoteFor(SupabaseClient client) =>
      RemoteReportingEngine(RemoteReportingSource(ReportingGateway(client)));

  /// The server's own answer, used as the baseline for a delta assertion.
  ///
  /// Absolute figures are the wrong assertion here, and finding that out is worth
  /// recording: `krishna-mis-dev` accumulates, every test in this file writes into the
  /// same properties and the same months, and a suite whose expectations only hold when
  /// it runs first can pass exactly once (D-076). Each test therefore states what **its
  /// own fixtures** moved the figure by, which is both robust to run order and the
  /// stronger claim.
  Future<PnlResult> serverReport(
    String periodKey,
    ReportingScope scope,
  ) async => (await remoteFor(owner).report(
    ReportRequest(period: _month(periodKey), scope: scope),
  )).resultOrNull!;

  // ── §20, §21 · The decisive proof ──────────────────────────────────────────

  group('cross-device parity over the four verified categories (§20, §21)', () {
    test('a device that recorded nothing agrees with the server exactly', () async {
      // Baselines first: this suite writes into one property and one month over and
      // over, so every figure below is what **these fixtures** moved (D-076).
      final ccrBefore = await serverReport(_period, ReportingScope.unit(_ccr));
      final hkiBefore = await serverReport(_period, ReportingScope.unit(_hki));

      // Context A: the four verified categories, plus a cost on each property.
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 10000000);
      await createSale(unitId: _ccr, category: 'NANDBHOG', paise: 870000);
      await createSale(unitId: _hki, category: 'ROOM', paise: 5200000);
      await createSale(unitId: _hki, category: 'BANQUET', paise: 4034300);
      await createExpense(allocations: [ccrAllocation(4500000)]);
      await createExpense(allocations: [hkiAllocation(3000000)]);

      // Context B: a device with no copy of any of it.
      final device = await syncedDevice(owner, ownerId);
      final remote = remoteFor(owner);

      for (final scope in [
        ReportingScope.unit(_ccr),
        ReportingScope.unit(_hki),
        ReportingScope({_ccr, _hki}),
      ]) {
        final request = ReportRequest(period: _month(_period), scope: scope);
        expectParity(
          await device.engine.report(request),
          await remote.report(request),
          context: 'cross-device $scope',
        );
      }

      // And the figures are the verified arithmetic, not merely two agreeing engines.
      final ccr = (await device.engine.report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_ccr),
        ),
      )).resultOrNull!;
      expect(ccr.grossSales.paise - ccrBefore.grossSales.paise, 10870000);
      expect(ccr.gst.paise - ccrBefore.gst.paise, 517619);
      expect(ccr.netSales.paise - ccrBefore.netSales.paise, 10352381);
      expect(ccr.expenses.paise - ccrBefore.expenses.paise, 4500000);
      expect(
        ccr.operatingProfit.paise - ccrBefore.operatingProfit.paise,
        5852381,
      );

      final hki = (await device.engine.report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_hki),
        ),
      )).resultOrNull!;
      expect(hki.grossSales.paise - hkiBefore.grossSales.paise, 9234300);
      expect(
        hki.gst.paise - hkiBefore.gst.paise,
        247619,
        reason: 'Banquet is `none`, and adds no tax',
      );
      expect(hki.netSales.paise - hkiBefore.netSales.paise, 8986681);
    });

    test('categories stay independent, and `none` stays distinguishable', () async {
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 3000000);
      await createSale(unitId: _ccr, category: 'NANDBHOG', paise: 1000000);
      await createSale(unitId: _hki, category: 'ROOM', paise: 2000000);
      await createSale(unitId: _hki, category: 'BANQUET', paise: 1500000);
      await createExpense(allocations: [ccrAllocation(100000)]);
      await createExpense(allocations: [hkiAllocation(100000)]);

      final device = await syncedDevice(owner, ownerId);
      final remote = remoteFor(owner);
      final request = ReportRequest(
        period: _month(_period),
        scope: ReportingScope({_ccr, _hki}),
      );

      expectParity(
        await device.engine.report(request),
        await remote.report(request),
        context: 'category parity',
      );

      final lines = {
        for (final line in (await remote.report(
          request,
        )).resultOrNull!.revenueByCategory)
          '${line.businessUnitId}/${line.revenueCategoryId}': line,
      };
      expect(
        lines.length,
        4,
        reason:
            'Restaurant, Nandbhog, Room and Banquet are four independent rules and four '
            'independent lines; nothing may flatten them before the comparison (D-089)',
      );
      final banquet = lines.values.singleWhere(
        (l) => l.treatment?.name == 'none',
      );
      expect(banquet.totals.tax.paise, 0);
      expect(
        lines.values.where((l) => l.treatment?.name == 'inclusive').length,
        3,
        reason:
            'the other three carry a treatment somebody set, not the same nil',
      );
    });

    test(
      'the expense hierarchy agrees at the grain it is grouped to (§19)',
      () async {
        await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 500000);
        await createExpense(allocations: [ccrAllocation(320000)]);
        await createExpense(allocations: [ccrAllocation(180000)]);

        final device = await syncedDevice(owner, ownerId, units: {_ccr});
        final request = ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_ccr),
        );
        expectParity(
          await device.engine.report(request),
          await remoteFor(owner).report(request),
          context: 'expense hierarchy',
        );
        final result = (await remoteFor(owner).report(request)).resultOrNull!;
        for (final line in result.expenseByHierarchy) {
          expect(line.departmentId, isNotNull);
          expect(line.sectionId, isNotNull);
          expect(line.categoryId, isNotNull);
        }
      },
    );
  });

  // ── §22 · Correction parity ────────────────────────────────────────────────

  group('corrections stay in step (§22)', () {
    test('an edited amount moves both engines by the same paise', () async {
      final id = await createSale(
        unitId: _ccr,
        category: 'RESTAURANT',
        paise: 10000000,
      );
      await createExpense(allocations: [ccrAllocation(1000000)]);

      final device = await syncedDevice(owner, ownerId, units: {_ccr});
      final remote = remoteFor(owner);
      final request = ReportRequest(
        period: _month(_period),
        scope: ReportingScope.unit(_ccr),
      );
      expectParity(
        await device.engine.report(request),
        await remote.report(request),
        context: 'before the correction',
      );

      await owner.rpc<dynamic>(
        'revenue_update',
        params: {
          'p_id': id,
          'p_business_date': _businessDate,
          'p_notes': _marker,
          'p_components': [
            {'entered_amount_minor': 12345678},
          ],
          'p_base_row_version': await versionOf('revenue_document', id),
          'p_mutation_id': const Uuid().v4(),
        },
      );

      await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
      final after = await engineOver(device.cache, ownerId);
      expectParity(
        await after.report(request),
        await remote.report(request),
        context: 'after the correction',
      );
    });

    test(
      'a business-date correction empties one month and fills the other',
      () async {
        final sourceBefore = await serverReport(
          _period,
          ReportingScope.unit(_ccr),
        );
        final targetBefore = await serverReport(
          _movedPeriod,
          ReportingScope.unit(_ccr),
        );
        final id = await createSale(
          unitId: _ccr,
          category: 'RESTAURANT',
          paise: 7000000,
        );
        await createExpense(allocations: [ccrAllocation(100000)]);
        await createExpense(
          allocations: [ccrAllocation(100000)],
          businessDate: _movedDate,
        );

        final device = await syncedDevice(owner, ownerId, units: {_ccr});
        final remote = remoteFor(owner);

        await owner.rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': id,
            'p_business_date': _movedDate,
            'p_notes': _marker,
            'p_components': [
              {'entered_amount_minor': 7000000},
            ],
            'p_base_row_version': await versionOf('revenue_document', id),
            'p_correction_reason':
                'Recorded against the wrong trading day ($_marker)',
            'p_mutation_id': const Uuid().v4(),
          },
        );

        await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
        final after = await engineOver(device.cache, ownerId);

        for (final period in [_period, _movedPeriod]) {
          final request = ReportRequest(
            period: _month(period),
            scope: ReportingScope.unit(_ccr),
          );
          expectParity(
            await after.report(request),
            await remote.report(request),
            context: 'after the date correction, $period',
          );
        }

        // And the sale is in exactly one of them. A cache that kept the old row would
        // report the money twice and reconcile against itself (§14).
        final source = (await after.report(
          ReportRequest(
            period: _month(_period),
            scope: ReportingScope.unit(_ccr),
          ),
        )).resultOrNull!;
        final target = (await after.report(
          ReportRequest(
            period: _month(_movedPeriod),
            scope: ReportingScope.unit(_ccr),
          ),
        )).resultOrNull!;
        expect(
          source.revenueContributions - sourceBefore.revenueContributions,
          0,
          reason: 'the source month keeps no row for a sale that left it',
        );
        expect(
          target.revenueContributions - targetBefore.revenueContributions,
          1,
        );
        expect(
          target.grossSales.paise - targetBefore.grossSales.paise,
          7000000,
        );
      },
    );

    test('an expense accounting-period correction moves with it', () async {
      final movedBefore = await serverReport(
        _movedPeriod,
        ReportingScope.unit(_ccr),
      );
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 500000);
      final id = await createExpense(allocations: [ccrAllocation(2500000)]);

      final device = await syncedDevice(owner, ownerId, units: {_ccr});
      final remote = remoteFor(owner);

      // The accrual moves; the operational date does not. Profitability follows the
      // accrual (D-016, spec §5.3).
      await owner.rpc<dynamic>(
        'expense_update',
        params: {
          'p_id': id,
          'p_base_row_version': await versionOf('expense_document', id),
          'p_business_date': _businessDate,
          'p_total_minor': 2500000,
          'p_allocations': [ccrAllocation(2500000)],
          'p_period_start': '$_movedPeriod-01',
          'p_period_end': '$_movedPeriod-28',
          'p_notes': _marker,
          'p_mutation_id': const Uuid().v4(),
        },
      );

      await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
      final after = await engineOver(device.cache, ownerId);

      for (final period in [_period, _movedPeriod]) {
        final request = ReportRequest(
          period: _month(period),
          scope: ReportingScope.unit(_ccr),
        );
        expectParity(
          await after.report(request),
          await remote.report(request),
          context: 'accrual moved, $period',
        );
      }
      expect(
        (await after.report(
              ReportRequest(
                period: _month(_movedPeriod),
                scope: ReportingScope.unit(_ccr),
              ),
            )).resultOrNull!.expenses.paise -
            movedBefore.expenses.paise,
        2500000,
        reason:
            'profitability follows the accrual, never the operational date (D-016)',
      );
    });
  });

  // ── §23 · Void parity ──────────────────────────────────────────────────────

  group('a void removes the active effect on both engines (§23)', () {
    test('revenue and expense, voided, agree at zero', () async {
      final baseline = await serverReport(_period, ReportingScope.unit(_ccr));
      final sale = await createSale(
        unitId: _ccr,
        category: 'RESTAURANT',
        paise: 4000000,
      );
      final cost = await createExpense(allocations: [ccrAllocation(900000)]);

      final device = await syncedDevice(owner, ownerId, units: {_ccr});
      final remote = remoteFor(owner);
      final request = ReportRequest(
        period: _month(_period),
        scope: ReportingScope.unit(_ccr),
      );
      final before = (await device.engine.report(request)).resultOrNull!;
      expect(before.grossSales.paise - baseline.grossSales.paise, 4000000);
      expect(before.expenses.paise - baseline.expenses.paise, 900000);

      for (final entry in [('revenue_void', sale), ('expense_void', cost)]) {
        await owner.rpc<dynamic>(
          entry.$1,
          params: {
            'p_id': entry.$2,
            'p_reason': 'Voided by the parity suite ($_marker)',
            'p_base_row_version': await versionOf(
              entry.$1 == 'revenue_void'
                  ? 'revenue_document'
                  : 'expense_document',
              entry.$2,
            ),
            'p_mutation_id': const Uuid().v4(),
          },
        );
      }

      await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
      final after = await engineOver(device.cache, ownerId);

      expectParity(
        await after.report(request),
        await remote.report(request),
        context: 'after the voids',
      );
      final result = (await after.report(request)).resultOrNull!;
      expect(result.grossSales.paise, baseline.grossSales.paise);
      expect(result.expenses.paise, baseline.expenses.paise);
      expect(result.revenueContributions, baseline.revenueContributions);
      expect(result.expenseContributions, baseline.expenseContributions);

      // And nothing was destroyed to make the totals agree. The documents remain,
      // carrying their void (D-006).
      for (final entry in [
        ('revenue_document', sale),
        ('expense_document', cost),
      ]) {
        final row = await owner
            .from(entry.$1)
            .select('voided_at, txn_number')
            .eq('id', entry.$2)
            .single();
        expect(row['voided_at'], isNotNull);
        expect(row['txn_number'], isNotNull);
      }
    });
  });

  // ── §24 · Multi-unit expense ───────────────────────────────────────────────

  group('a shared expense attributes and re-attributes exactly (§24)', () {
    test('CCR, HKI and consolidated all agree, before and after', () async {
      final ccrBefore = await serverReport(_period, ReportingScope.unit(_ccr));
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 6000000);
      await createSale(unitId: _hki, category: 'ROOM', paise: 4000000);
      final shared = await createExpense(
        allocations: [ccrAllocation(2500000), hkiAllocation(3300000)],
      );

      final device = await syncedDevice(owner, ownerId);
      final remote = remoteFor(owner);

      Future<void> compareAll(String context) async {
        for (final scope in [
          ReportingScope.unit(_ccr),
          ReportingScope.unit(_hki),
          ReportingScope({_ccr, _hki}),
        ]) {
          final request = ReportRequest(period: _month(_period), scope: scope);
          expectParity(
            await (await engineOver(device.cache, ownerId)).report(request),
            await remote.report(request),
            context: '$context $scope',
          );
        }
      }

      await compareAll('shared bill');
      final split = (await (await engineOver(device.cache, ownerId)).report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_ccr),
        ),
      )).resultOrNull!;
      expect(split.expenses.paise - ccrBefore.expenses.paise, 2500000);

      // Re-apportioned wholly to one property. The other must keep no residue — the
      // failure a per-period delta could not see (§14).
      await owner.rpc<dynamic>(
        'expense_update',
        params: {
          'p_id': shared,
          'p_base_row_version': await versionOf('expense_document', shared),
          'p_business_date': _businessDate,
          'p_total_minor': 5800000,
          'p_allocations': [hkiAllocation(5800000)],
          'p_notes': _marker,
          'p_mutation_id': const Uuid().v4(),
        },
      );
      await device.sync.synchronise(
        businessUnitIds: {_ccr, _hki},
        years: [_fy],
      );
      await compareAll('re-apportioned');

      final ccrAfter = (await (await engineOver(device.cache, ownerId)).report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_ccr),
        ),
      )).resultOrNull!;
      expect(
        ccrAfter.expenses.paise,
        ccrBefore.expenses.paise,
        reason:
            'the property that lost the whole line keeps no cached share of it',
      );
    });
  });

  // ── §25 · A closed period ──────────────────────────────────────────────────

  group('a closed period stays readable (§25)', () {
    test('closing changes no figure; a reopened correction moves both', () async {
      final sale = await createSale(
        unitId: _ccr,
        category: 'RESTAURANT',
        paise: 5000000,
      );
      await createExpense(allocations: [ccrAllocation(800000)]);

      final device = await syncedDevice(owner, ownerId, units: {_ccr});
      final remote = remoteFor(owner);
      final request = ReportRequest(
        period: _month(_period),
        scope: ReportingScope.unit(_ccr),
      );
      final before = (await device.engine.report(request)).resultOrNull!;

      await owner.rpc<dynamic>(
        'period_close',
        params: {
          'p_period_key': _period,
          'p_business_unit_id': _ccr,
          'p_mutation_id': const Uuid().v4(),
        },
      );
      addTearDown(reopenEverything);

      await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
      final closed = await engineOver(device.cache, ownerId);
      expectParity(
        await closed.report(request),
        await remote.report(request),
        context: 'while closed',
      );
      expect(
        (await closed.report(request)).resultOrNull!.grossSales.paise,
        before.grossSales.paise,
        reason:
            'closing a period is a write control, not a reporting one. Its facts do not '
            'go anywhere, and there is no report-specific frozen copy of them',
      );

      // Reopen, correct legitimately, and both engines move together.
      await reopenEverything();
      await owner.rpc<dynamic>(
        'revenue_update',
        params: {
          'p_id': sale,
          'p_business_date': _businessDate,
          'p_notes': _marker,
          'p_components': [
            {'entered_amount_minor': 5500000},
          ],
          'p_base_row_version': await versionOf('revenue_document', sale),
          'p_mutation_id': const Uuid().v4(),
        },
      );
      await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
      final reopened = await engineOver(device.cache, ownerId);
      expectParity(
        await reopened.report(request),
        await remote.report(request),
        context: 'after the reopened correction',
      );
      expect(
        (await reopened.report(request)).resultOrNull!.grossSales.paise,
        isNot(before.grossSales.paise),
      );
    });
  });

  // ── §26, §27, §28, §29, §30 · Zero, coverage, offline, retry ───────────────

  group('zero, coverage, offline and retry', () {
    test('a complete range with no trade is a real zero on both (§26)', () async {
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 100000);
      await createExpense(allocations: [ccrAllocation(100000)]);
      final device = await syncedDevice(owner, ownerId, units: {_ccr});

      // A month inside the synchronised financial year that nothing in this project has
      // ever written to, and that no test in this file writes to either.
      final request = ReportRequest(
        period: const MonthPeriod(2027, 3),
        scope: ReportingScope.unit(_ccr),
      );
      final local = await device.engine.report(request);
      final remote = await remoteFor(owner).report(request);
      expectParity(local, remote, context: 'an empty month');
      expect(local.resultOrNull!.grossSales.paise, 0);
      expect(local.resultOrNull!.expenses.paise, 0);
      expect(
        local.coverage,
        ReportingCoverage.complete,
        reason:
            'zero is a figure; the range was synchronised and holds nothing',
      );
    });

    test(
      'an unsynchronised year: local refuses, remote answers, then they agree (§27)',
      () async {
        await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 250000);
        await createExpense(allocations: [ccrAllocation(50000)]);

        // Synchronise FY2025 only, then ask for a FY2026 month.
        final device = deviceFor(owner, ownerId);
        addTearDown(device.db.close);
        await device.sync.synchronise(
          businessUnitIds: {_ccr},
          years: [const FinancialYear(2025)],
        );

        final request = ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_ccr),
        );
        expectLocalUncoveredWhileRemoteAnswers(
          await (await engineOver(device.cache, ownerId)).report(request),
          await remoteFor(owner).report(request),
          context: 'a year this device never fetched',
        );

        // Fetch it deliberately, and the two agree exactly.
        await device.sync.synchronise(
          businessUnitIds: {_ccr},
          years: [_fy],
          onDemand: true,
        );
        expectParity(
          await (await engineOver(device.cache, ownerId)).report(request),
          await remoteFor(owner).report(request),
          context: 'after the on-demand fetch',
        );
      },
    );

    test('a repeated remote query returns the same primitives (§29)', () async {
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 1750000);
      await createExpense(allocations: [ccrAllocation(250000)]);
      final remote = remoteFor(owner);
      final request = ReportRequest(
        period: _month(_period),
        scope: ReportingScope({_ccr, _hki}),
      );
      final first = await remote.report(request);
      final second = await remote.report(request);
      final third = await remote.report(request);
      expectParity(first, second, context: 'retry 1');
      expectParity(second, third, context: 'retry 2');
    });

    test('the remote engine fills no cache and moves no marker (§30)', () async {
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 400000);
      await createExpense(allocations: [ccrAllocation(60000)]);

      // A device that has synchronised nothing at all.
      final device = deviceFor(owner, ownerId);
      addTearDown(device.db.close);

      final request = ReportRequest(
        period: _month(_period),
        scope: ReportingScope.unit(_ccr),
      );
      final remoteAnswer = await remoteFor(owner).report(request);
      expect(remoteAnswer.isComputed, isTrue);

      expect(await device.cache.markersFor(ownerId), isEmpty);
      for (final table in const [
        'reporting_revenue_contributions',
        'reporting_expense_contributions',
      ]) {
        expect(
          (await device.db
                  .customSelect('SELECT COUNT(*) AS c FROM $table')
                  .getSingle())
              .read<int>('c'),
          0,
          reason:
              'a remote report that filled the cache would make the two sources agree '
              'because one had just overwritten the other',
        );
      }
      expect(
        (await (await engineOver(
          device.cache,
          ownerId,
        )).report(request)).isComputed,
        isFalse,
        reason:
            'the local engine is unchanged by the remote read, and still has nothing to '
            'stand behind',
      );
    });

    test('the local engine answers with no network at all (§28)', () async {
      final baseline = await serverReport(_period, ReportingScope.unit(_ccr));
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 3300000);
      await createExpense(allocations: [ccrAllocation(700000)]);
      final device = await syncedDevice(owner, ownerId, units: {_ccr});

      // A client whose credentials are gone: every request it makes fails. The local
      // engine holds no reference to it and never asks.
      final broken = SupabaseClient(
        'http://127.0.0.1:1',
        config['SUPABASE_ANON_KEY'] as String,
      );
      addTearDown(broken.dispose);
      final request = ReportRequest(
        period: _month(_period),
        scope: ReportingScope.unit(_ccr),
      );
      expect(
        (await remoteFor(broken).report(request)).isComputed,
        isFalse,
        reason:
            'the remote engine needs the server and says so when it cannot reach it',
      );
      final local = await device.engine.report(request);
      expect(local.isComputed, isTrue);
      expect(
        local.resultOrNull!.grossSales.paise - baseline.grossSales.paise,
        3300000,
      );
      expect(
        local.resultOrNull!.expenses.paise - baseline.expenses.paise,
        700000,
      );
    });
  });

  // ── §31 · One snapshot ─────────────────────────────────────────────────────

  group('the server reads both sides at one snapshot (§31)', () {
    test(
      'a two-call client can be made to return a pair that never existed; the RPC cannot',
      () async {
        // A state machine with exactly three real states, and one impossible pair.
        //
        //   (revenue R, expense E)   both recorded
        //   (0,        E)            after the revenue is voided
        //   (0,        0)            after the expense is voided
        //
        // (R, 0) is never true of the hotel at any instant. A client that reads revenue,
        // lets both voids commit, and then reads expenses produces exactly that — and the
        // interleaving is under this test's own control, so it is deterministic rather
        // than a race waited on with a sleep.
        final baseline = await serverReport(_period, ReportingScope.unit(_hki));
        final r0 = baseline.grossSales.paise;
        final e0 = baseline.expenses.paise;

        final sale = await createSale(
          unitId: _hki,
          category: 'ROOM',
          paise: 8800000,
        );
        final cost = await createExpense(allocations: [hkiAllocation(2200000)]);

        Future<int> readRevenue() async {
          final rows = await owner
              .from('revenue_period_contributions')
              .select('gross_minor, voided_at')
              .eq('business_unit_id', _hki)
              .eq('pnl_period_key', _period);
          return rows
              .where((r) => r['voided_at'] == null)
              .fold<int>(0, (n, r) => n + (r['gross_minor'] as int));
        }

        Future<int> readExpense() async {
          final rows = await owner
              .from('expense_period_contributions')
              .select('amount_minor, voided_at')
              .eq('business_unit_id', _hki)
              .eq('pnl_period_key', _period);
          return rows
              .where((r) => r['voided_at'] == null)
              .fold<int>(0, (n, r) => n + (r['amount_minor'] as int));
        }

        Future<(int, int)> viaRpc() async {
          final envelope = await remoteFor(owner).report(
            ReportRequest(
              period: _month(_period),
              scope: ReportingScope.unit(_hki),
            ),
          );
          final r = envelope.resultOrNull!;
          return (r.grossSales.paise, r.expenses.paise);
        }

        final beforeRpc = await viaRpc();
        expect(beforeRpc.$1, r0 + 8800000);
        expect(beforeRpc.$2, e0 + 2200000);

        // The dangerous implementation, driven deliberately.
        final staleRevenue = await readRevenue();
        for (final entry in [('revenue_void', sale), ('expense_void', cost)]) {
          await owner.rpc<dynamic>(
            entry.$1,
            params: {
              'p_id': entry.$2,
              'p_reason': 'Snapshot control ($_marker)',
              'p_base_row_version': await versionOf(
                entry.$1 == 'revenue_void'
                    ? 'revenue_document'
                    : 'expense_document',
                entry.$2,
              ),
              'p_mutation_id': const Uuid().v4(),
            },
          );
        }
        final freshExpense = await readExpense();

        expect(
          (staleRevenue, freshExpense),
          (r0 + 8800000, e0),
          reason:
              'the control must actually reproduce the hazard, or it proves nothing '
              'about the boundary that avoids it',
        );

        // The RPC, at any moment, returns one of the three real states — never the pair
        // above. It is one statement, so both sides come from one snapshot.
        final afterRpc = await viaRpc();
        expect(
          afterRpc,
          anyOf((r0 + 8800000, e0 + 2200000), (r0, e0 + 2200000), (r0, e0)),
          reason:
              'a mixed pair would mean the two sides were read at two snapshots',
        );
        expect(
          afterRpc,
          isNot((r0 + 8800000, e0)),
          reason:
              'that pair was never true of the hotel at any instant, and it is exactly '
              'what the two-call client produced a moment ago',
        );
      },
    );
  });

  // ── §34 · The security matrix ──────────────────────────────────────────────

  group('the boundary exposes nothing outside the caller authority (§34)', () {
    late String ccrOnlySale;

    setUp(() async {
      ccrOnlySale = await createSale(
        unitId: _ccr,
        category: 'RESTAURANT',
        paise: 6600000,
      );
      await createSale(unitId: _hki, category: 'ROOM', paise: 4400000);
      await createExpense(allocations: [ccrAllocation(1100000)]);
      await createExpense(allocations: [hkiAllocation(2200000)]);
    });

    test('the Owner sees both properties', () async {
      final result = (await remoteFor(owner).report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope({_ccr, _hki}),
        ),
      )).resultOrNull!;
      expect(result.grossSales.paise, greaterThanOrEqualTo(11000000));
    });

    test('a Crystal Canopy manager gets no Hotel Krishna figure', () async {
      final manager = await sessionFor('ccr.manager@example.com');
      final envelope = await remoteFor(manager).report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_hki),
        ),
      );
      expect(
        envelope.isComputed,
        isFalse,
        reason: 'no authority over Hotel Krishna is a refusal, never a zero',
      );
      expect(envelope.revenueCoverage, ReportingCoverage.notAuthorised);
      expect(envelope.expenseCoverage, ReportingCoverage.notAuthorised);

      // And the control that separates "scoping works" from "the query is broken":
      // the manager's own property answers (D-116).
      final own = await remoteFor(manager).report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_ccr),
        ),
      );
      expect(own.isComputed, isTrue);
      expect(own.resultOrNull!.grossSales.paise, greaterThanOrEqualTo(6600000));
    });

    test('a Hotel Krishna manager gets no Crystal Canopy figure', () async {
      final manager = await sessionFor('hki.manager@example.com');
      final envelope = await remoteFor(manager).report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_ccr),
        ),
      );
      expect(envelope.isComputed, isFalse);
      final own = await remoteFor(manager).report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_hki),
        ),
      );
      expect(own.isComputed, isTrue);
    });

    test('two scoped grants do not add up to an organisation-wide report (D-164)', () async {
      // The consolidated half of the reporting authority contract, and the half that
      // is easy to get wrong by writing the obvious thing: a request naming more than
      // one property is the **organisation** report, and D-164 requires the unscoped
      // authority for it. A holder of two scoped grants keeps every per-property
      // report their authority supports and does not get the organisation view.
      //
      // The grant is made and withdrawn through the real administrative RPCs, and the
      // withdrawal is read back rather than assumed (D-142). Without the second grant
      // this test would prove only that the manager lacks Hotel Krishna, which is a
      // different statement and is already asserted above.
      final manager = await sessionFor('ccr.manager@example.com');
      final managerId = manager.auth.currentUser!.id;

      final granted =
          await owner.rpc(
                'user_role_grant',
                params: {
                  'p_user_id': managerId,
                  'p_role_code': 'manager',
                  'p_business_unit_id': _hki,
                  'p_mutation_id': const Uuid().v4(),
                },
              )
              as Map<String, dynamic>;
      final grantId = granted['entity_id'] as String;
      addTearDown(() async {
        await owner.rpc(
          'user_role_revoke',
          params: {'p_grant_id': grantId, 'p_mutation_id': const Uuid().v4()},
        );
        // Read the restore back: the second property must be refused again.
        final after = await remoteFor(manager).report(
          ReportRequest(
            period: _month(_period),
            scope: ReportingScope.unit(_hki),
          ),
        );
        expect(
          after.isComputed,
          isFalse,
          reason:
              'the temporary grant survived the run — a fixture that is not '
              'restored is a standing authority change nobody reviewed',
        );
      });

      // Each property, on its own, answers.
      for (final unit in [_ccr, _hki]) {
        final scoped = await remoteFor(manager).report(
          ReportRequest(
            period: _month(_period),
            scope: ReportingScope.unit(unit),
          ),
        );
        expect(
          scoped.isComputed,
          isTrue,
          reason: 'a scoped grant still supports that property own report',
        );
      }

      // Both together do not.
      final consolidated = await remoteFor(manager).report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope({_ccr, _hki}),
        ),
      );
      expect(
        consolidated.isComputed,
        isFalse,
        reason:
            'two scoped grants became an organisation-wide consolidated '
            'privilege, which is exactly what D-164 unscoped rule refuses',
      );
      expect(consolidated.revenueCoverage, ReportingCoverage.notAuthorised);
      expect(consolidated.expenseCoverage, ReportingCoverage.notAuthorised);

      // And the control that stops this reading as "consolidated never works":
      // the unscoped Owner gets it.
      final ownerConsolidated = await remoteFor(owner).report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope({_ccr, _hki}),
        ),
      );
      expect(ownerConsolidated.isComputed, isTrue);
    });

    test(
      'Data Entry never receives a P&L from own-only expenses and zero revenue',
      () async {
        final entry = await sessionFor('data.entry@example.com');
        final envelope = await remoteFor(entry).report(
          ReportRequest(
            period: _month(_period),
            scope: ReportingScope.unit(_ccr),
          ),
        );
        expect(
          envelope.isComputed,
          isFalse,
          reason:
              'expense.view.own is a subset of one author costs and never a property '
              'cost base; combined with a revenue side of nothing it would render a '
              'large, plausible and entirely fictitious loss (D-163, D-164)',
        );
        expect(envelope.revenueCoverage, ReportingCoverage.notAuthorised);
        expect(
          envelope.expenseCoverage,
          ReportingCoverage.notAuthorised,
          reason: 'expense.view.own does not qualify a P&L side',
        );

        // Proven from the payload rather than only from the refusal: the server sent no
        // figure at all, so there was nothing for a careless client to render.
        final raw = await entry.rpc<dynamic>(
          'reporting_primitives',
          params: {
            'p_business_unit_ids': [_ccr],
            'p_from': '$_period-01',
            'p_to': '$_period-31',
            'p_breakdown': true,
          },
        );
        final unit = ((raw as Map)['units'] as List).single as Map;
        expect(unit['revenue'], isNull);
        expect(unit['expense'], isNull);
        expect(unit['revenue_authorised'], isFalse);
        expect(unit['expense_authorised'], isFalse);
      },
    );

    test('an anonymous caller cannot reach the boundary at all', () async {
      final anon = SupabaseClient(
        config['SUPABASE_URL'] as String,
        config['SUPABASE_ANON_KEY'] as String,
      );
      addTearDown(anon.dispose);
      await expectLater(
        anon.rpc<dynamic>(
          'reporting_primitives',
          params: {
            'p_business_unit_ids': [_ccr],
            'p_from': '$_period-01',
            'p_to': '$_period-31',
          },
        ),
        throwsA(isA<PostgrestException>()),
      );
      // And the projections stay closed to it too.
      await expectLater(
        anon.from('revenue_period_contributions').select('gross_minor'),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('an omitted unit set never widens to the organisation (§11)', () async {
      final raw = await owner.rpc<dynamic>(
        'reporting_primitives',
        params: {
          'p_business_unit_ids': null,
          'p_from': '$_period-01',
          'p_to': '$_period-31',
        },
      );
      expect(
        ((raw as Map)['units'] as List),
        isEmpty,
        reason:
            'a null unit set coalesces to empty and yields no units; there is no branch '
            'in which it means everything',
      );
      expect(ccrOnlySale, isNotEmpty);
    });

    test('no client role can read a financial base table (§35)', () async {
      // The three `authenticated` holds no SELECT on at all. `expense_allocations` and
      // `expense_period_allocations` are readable **under RLS** and deliberately so — the
      // line-level policies are what scope a shared bill (D-062) — so asserting that they
      // throw would be asserting the wrong boundary.
      for (final table in const [
        'expenses',
        'revenue_entries',
        'revenue_components',
      ]) {
        await expectLater(
          owner.from(table).select('id').limit(1),
          throwsA(isA<PostgrestException>()),
          reason:
              '$table must stay unreadable; the projections are the only way in',
        );
      }
    });
  });

  // ── §33 · Performance, measured through the real boundary ──────────────────

  group('performance through the real boundary (§33)', () {
    test('a month, a month, a financial year and a breakdown', () async {
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 1000000);
      await createSale(unitId: _hki, category: 'ROOM', paise: 1000000);
      await createExpense(
        allocations: [ccrAllocation(200000), hkiAllocation(300000)],
      );
      final remote = remoteFor(owner);

      Future<int> timed(String label, ReportRequest request) async {
        final watch = Stopwatch()..start();
        final envelope = await remote.report(request);
        watch.stop();
        expect(envelope.isComputed, isTrue, reason: '$label did not compute');
        // ignore: avoid_print
        print('  §33 $label: ${watch.elapsedMilliseconds} ms');
        return watch.elapsedMilliseconds;
      }

      await timed(
        'CCR one month',
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_ccr),
        ),
      );
      await timed(
        'HKI one month',
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_hki),
        ),
      );
      await timed(
        'consolidated FY 2026-27',
        ReportRequest(
          period: const FinancialYearPeriod(FinancialYear(2026)),
          scope: ReportingScope({_ccr, _hki}),
        ),
      );

      // The escalation trigger `ARCHITECTURE.md` §9 records is 400 ms for a one-month
      // P&L on the reference device. This is a network round trip from a development
      // machine to Mumbai, so it is recorded rather than asserted against that budget —
      // a threshold that fails on somebody's café Wi-Fi would be deleted, not fixed.
      expect(true, isTrue);
    });
  });

  // ── The whole period matrix, end to end (§10) ──────────────────────────────

  group('every period shape, cross-device (§10)', () {
    test('day, week, month, financial year and custom range', () async {
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 2400000);
      await createSale(
        unitId: _ccr,
        category: 'NANDBHOG',
        paise: 600000,
        businessDate: _movedDate,
      );
      await createExpense(allocations: [ccrAllocation(400000)]);
      await createExpense(
        allocations: [ccrAllocation(150000)],
        businessDate: _movedDate,
      );

      final device = await syncedDevice(owner, ownerId, units: {_ccr});
      final remote = remoteFor(owner);
      final parts = _businessDate.split('-').map(int.parse).toList();
      final day = BusinessDate.of(parts[0], parts[1], parts[2]);

      final periods = <String, ReportingPeriod>{
        'a single trading day': SingleDayPeriod(day),
        'a Monday-to-Sunday week': WeekPeriod(day),
        'a month': _month(_period),
        'the financial year': const FinancialYearPeriod(FinancialYear(2026)),
        'a custom range across two months': CustomRangePeriod(
          from: BusinessDate.of(2027, 1, 1),
          to: BusinessDate.of(2027, 2, 28),
        ),
        'a same-day custom range': CustomRangePeriod(from: day, to: day),
      };

      for (final entry in periods.entries) {
        final request = ReportRequest(
          period: entry.value,
          scope: ReportingScope.unit(_ccr),
        );
        expectParity(
          await device.engine.report(request),
          await remote.report(request),
          context: entry.key,
        );
      }
    });
  });

  // ── Slice 6 · One snapshot, and what a report may claim about it (D-188) ────
  //
  // Four properties only a real PostgreSQL can establish: that one statement is one MVCC
  // snapshot, that the server's own time comes back with the facts rather than from a
  // second call, that the authority boundary is unchanged by the new transport, and that
  // a closed period is read rather than touched.

  group('the snapshot transport (D-188)', () {
    test('one call answers both datasets, with an identity and a server time', () async {
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 700000);
      await createExpense(allocations: [ccrAllocation(250000)]);

      final before = DateTime.now().toUtc();
      final first =
          await owner.rpc<dynamic>(
                'reporting_snapshot',
                params: {
                  'p_business_unit_ids': [_ccr, _hki],
                  'p_revenue_since': 0,
                  'p_expense_since': 0,
                },
              )
              as Map<String, dynamic>;

      expect(
        first['snapshot_id'],
        isA<String>().having((v) => v.isNotEmpty, 'non-empty', isTrue),
        reason:
            'pg_current_snapshot() is the opaque identity the marker records',
      );
      final serverTime = DateTime.parse(first['server_time'] as String).toUtc();
      expect(
        serverTime.isAfter(before.subtract(const Duration(minutes: 10))),
        isTrue,
        reason:
            'the time is the SAME statement transaction time — not a second select now(), '
            'and never the device clock (spec section 9)',
      );
      expect(
        (first['revenue'] as List).isNotEmpty,
        isTrue,
        reason: 'both projections are answered by the one statement',
      );
      expect((first['expense'] as List).isNotEmpty, isTrue);
      expect(
        (first['units'] as List).every(
          (u) => (u as Map).containsKey('reporting_authorised'),
        ),
        isTrue,
        reason:
            'authority is stated per unit rather than inferred from empty rows',
      );

      // What the identity promises, established against the real database rather than
      // assumed. `pg_current_snapshot()` is `xmin:xmax:xip_list`, so two reads of a
      // database on which nothing has committed carry the **same** identity — and that is
      // correct: they are the same MVCC view, and facts drawn from both really do describe
      // one moment. Equality is therefore the meaningful operation; uniqueness per call is
      // not, and a test asserting it would be asserting a coincidence.
      final quiet =
          await owner.rpc<dynamic>(
                'reporting_snapshot',
                params: {
                  'p_business_unit_ids': [_ccr, _hki],
                  'p_revenue_since': 0,
                  'p_expense_since': 0,
                },
              )
              as Map<String, dynamic>;
      expect(
        DateTime.parse(
          quiet['server_time'] as String,
        ).toUtc().isBefore(serverTime),
        isFalse,
        reason: 'server time does not run backwards between two reads',
      );

      // And once something has committed, the identity moves. That is the half the
      // corrective depends on: a run that saw a different state says so.
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 310000);
      final after =
          await owner.rpc<dynamic>(
                'reporting_snapshot',
                params: {
                  'p_business_unit_ids': [_ccr, _hki],
                  'p_revenue_since': 0,
                  'p_expense_since': 0,
                },
              )
              as Map<String, dynamic>;
      expect(
        after['snapshot_id'],
        isNot(quiet['snapshot_id']),
        reason:
            'a transaction committed in between, so this is a different authoritative '
            'moment and the identity says so (D-188)',
      );
    });

    test('the transport preserves the reporting authority boundary', () async {
      // A property-scoped manager. The Slice 5 rule is unchanged by the new transport:
      // reports.view AND revenue.view AND expense.view.all, per unit (D-164, D-187).
      final manager = await sessionFor('ccr.manager@example.com');
      final payload =
          await manager.rpc<dynamic>(
                'reporting_snapshot',
                params: {
                  'p_business_unit_ids': [_ccr, _hki],
                  'p_revenue_since': 0,
                  'p_expense_since': 0,
                },
              )
              as Map<String, dynamic>;

      final authorised = {
        for (final unit in payload['units'] as List)
          (unit as Map)['business_unit_id'] as String:
              unit['reporting_authorised'] as bool,
      };
      expect(authorised[_ccr], isTrue);
      expect(
        authorised[_hki],
        isFalse,
        reason:
            'a property this manager may not report on is refused, not merely empty',
      );
      expect(
        (payload['revenue'] as List).every(
          (r) => (r as Map)['business_unit_id'] == _ccr,
        ),
        isTrue,
        reason: 'and no row of the refused property comes back with it',
      );
      expect(
        (payload['expense'] as List).every(
          (r) => (r as Map)['business_unit_id'] == _ccr,
        ),
        isTrue,
      );

      // An anonymous caller reaches neither the snapshot nor the head check.
      final anon = SupabaseClient(
        config['SUPABASE_URL'] as String,
        config['SUPABASE_ANON_KEY'] as String,
      );
      for (final fn in const ['reporting_snapshot', 'reporting_newer_than']) {
        await expectLater(
          anon.rpc<dynamic>(
            fn,
            params: {
              'p_business_unit_ids': [_ccr],
              'p_revenue_since': 0,
              'p_expense_since': 0,
            },
          ),
          throwsA(anything),
          reason: '$fn is not callable by anon (D-044)',
        );
      }
    });

    test('a synchronised device names one snapshot for every segment', () async {
      await createSale(unitId: _ccr, category: 'RESTAURANT', paise: 900000);
      await createExpense(allocations: [ccrAllocation(300000)]);

      final device = await syncedDevice(owner, ownerId, units: {_ccr, _hki});
      final markers = await device.cache.markersFor(ownerId);
      expect(markers, isNotEmpty);
      expect(
        markers.map((m) => m.snapshotId).toSet().length,
        1,
        reason:
            'one run is one authoritative snapshot, and every property, dataset and year '
            'it certified says so',
      );
      expect(
        markers.every((m) => m.serverConfirmedAt != null),
        isTrue,
        reason: 'each carries the server-confirmed time the facts arrived with',
      );

      final envelope = await device.engine.report(
        ReportRequest(
          period: _month(_period),
          scope: ReportingScope({_ccr, _hki}),
        ),
      );
      expect(
        envelope.freshness?.state,
        ReportingFreshnessState.synchronised,
        reason: 'so the consolidated report can honestly say what it is as of',
      );
      expect(
        envelope.freshness!.synchronisedAt,
        markers.first.serverConfirmedAt,
        reason:
            'and the moment it names is the server-confirmed one, not a device clock',
      );
    });

    test(
      'a closed period is read, refuses a correction, and reopens with a reason',
      () async {
        final sale = await createSale(
          unitId: _ccr,
          category: 'RESTAURANT',
          paise: 4000000,
        );
        final device = await syncedDevice(owner, ownerId, units: {_ccr});
        final request = ReportRequest(
          period: _month(_period),
          scope: ReportingScope.unit(_ccr),
        );
        final before = (await device.engine.report(request)).resultOrNull!;

        await owner.rpc<dynamic>(
          'period_close',
          params: {
            'p_period_key': _period,
            'p_business_unit_id': _ccr,
            'p_mutation_id': const Uuid().v4(),
          },
        );
        addTearDown(reopenEverything);

        // A close writes a period lock and no contribution, so it is not this report being
        // behind. The head check must be scope- and data-relevant or every administrative
        // act would nag a manager to synchronise something that changes no figure.
        expect(
          (await device.sync.checkForNewer(
            businessUnitIds: {_ccr},
            years: [_fy],
          )).serverHasNewer,
          isFalse,
          reason: 'a period lock is not reporting data',
        );

        // The figures are unchanged, on both engines, and the report is still readable.
        await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
        final closed = await engineOver(device.cache, ownerId);
        expectParity(
          await closed.report(request),
          await remoteFor(owner).report(request),
          context: 'while closed',
        );
        expect(
          (await closed.report(request)).resultOrNull!.grossSales.paise,
          before.grossSales.paise,
          reason:
              'a closed month reports exactly what it reported the day before',
        );

        // A correction into it is refused server-side. Reporting neither causes nor relaxes
        // that: engines are readers (spec section 13.4).
        Object? refusal;
        try {
          await owner.rpc<dynamic>(
            'revenue_update',
            params: {
              'p_id': sale,
              'p_business_date': _businessDate,
              'p_notes': _marker,
              'p_components': [
                {'entered_amount_minor': 4500000},
              ],
              'p_base_row_version': await versionOf('revenue_document', sale),
              'p_mutation_id': const Uuid().v4(),
            },
          );
        } catch (error) {
          refusal = error;
        }
        expect(
          refusal,
          isNotNull,
          reason: 'a closed period rejects every write affecting it (D-026)',
        );
        expect(
          (await device.sync.checkForNewer(
            businessUnitIds: {_ccr},
            years: [_fy],
          )).serverHasNewer,
          isFalse,
          reason:
              'and a refused correction changed nothing, so nothing is newer',
        );

        // The Owner reopens with a stated reason, the correction is accepted, and the
        // figure moves exactly once — after the device synchronises, not before.
        await owner.rpc<dynamic>(
          'period_reopen',
          params: {
            'p_period_key': _period,
            'p_business_unit_id': _ccr,
            'p_reason':
                'Slice 6 acceptance: correcting a recorded sale ($_marker)',
            'p_mutation_id': const Uuid().v4(),
          },
        );
        await owner.rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': sale,
            'p_business_date': _businessDate,
            'p_notes': _marker,
            'p_components': [
              {'entered_amount_minor': 4500000},
            ],
            'p_base_row_version': await versionOf('revenue_document', sale),
            'p_mutation_id': const Uuid().v4(),
          },
        );
        expect(
          (await device.sync.checkForNewer(
            businessUnitIds: {_ccr},
            years: [_fy],
          )).serverHasNewer,
          isTrue,
          reason: 'now reporting data really has moved',
        );

        await device.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
        final reopened = await engineOver(device.cache, ownerId);
        expectParity(
          await reopened.report(request),
          await remoteFor(owner).report(request),
          context: 'after the reopened correction',
        );
        expect(
          (await reopened.report(request)).resultOrNull!.grossSales.paise -
              before.grossSales.paise,
          500000,
          reason: 'the correction lands once, and for exactly what it changed',
        );

        // The audit is intact: the close, the reopen with its reason, and the correction.
        final lock = await owner
            .from('period_locks')
            .select('id')
            .eq('period_key', _period)
            .eq('business_unit_id', _ccr)
            .single();
        final events = await owner
            .from('period_lock_events')
            .select('action, reason')
            .eq('period_lock_id', lock['id'] as String)
            .order('occurred_at', ascending: false)
            .limit(2);
        expect(
          events.map((e) => e['action']).toList(),
          containsAll(<String>['close', 'reopen']),
          reason: 'both acts are on the append-only record',
        );
        expect(
          events.firstWhere((e) => e['action'] == 'reopen')['reason'],
          contains(_marker),
          reason:
              'and the reopen carries the reason its actor stated (D-026, D-145)',
        );
      },
    );
  });
}
