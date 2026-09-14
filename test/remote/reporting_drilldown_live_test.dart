/// Slice 10 against `krishna-mis-dev`: the read-only drill-down, across devices and scopes.
///
/// Skipped unless `KRISHNA_DEV_IDENTITIES` points at the development identity file, so an
/// ordinary `flutter test` run stays hermetic. Nothing here prints a password, a token or
/// the API key.
///
/// ## What only the real server can answer
///
///   1. A device that recorded nothing drills into a document another device recorded,
///      through the canonical cache, and opens it — without the document landing in its
///      ordinary transaction tables, its outbox or its reporting cache.
///   2. A Crystal Canopy reader, established by the server's own capability answer, opens a
///      shared bill and is given only Crystal Canopy's allocation (D-062).
///   3. A Hotel Krishna document cannot be reached from a Crystal Canopy drill-down, and the
///      server withholds it even from a forged request.
///   4. A correction after the report synchronised makes the fetched document refuse to
///      explain the cached row, until the report is refreshed.
///   5. A closed period's documents stay readable.
///
/// **Fixtures are reversed through the real API**, with a reason naming this run, and swept
/// before and after (D-066, D-071, D-076). Nothing is deleted.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/remote/report_document_reader.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:krishna_mis/data/reporting/cached_drilldown_source.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_document_detail.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/pnl_drilldown.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:uuid/uuid.dart';

const _identitiesVar = 'KRISHNA_DEV_IDENTITIES';

const _markerPrefix = 'phase5-slice10-';
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

/// A quiet corner of the calendar, inside FY 2026-27 and away from the other suites' dates.
const _businessDate = '2027-01-22';
const _period = '2027-01';
const _fy = FinancialYear(2026);

final _range =
    (CustomRangePeriod(
              from: BusinessDate.of(2027, 1, 1),
              to: BusinessDate.of(2027, 1, 31),
            ).resolve()
            as ReportRangeResolved)
        .range;

List<CapabilityGrant> _pnl([String? unit]) => [
  CapabilityGrant(Capability.reportsView, businessUnitId: unit),
  CapabilityGrant(Capability.revenueView, businessUnitId: unit),
  CapabilityGrant(Capability.expenseViewAll, businessUnitId: unit),
];

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

  Future<int> reverseStrandedFixtures() async {
    var reversed = 0;
    for (final relation in const ['revenue_document', 'expense_document']) {
      final rows = await owner
          .from(relation)
          .select('id, row_version')
          .isFilter('voided_at', null)
          .like('notes', '$_markerPrefix%');
      for (final row in rows) {
        await owner.rpc<dynamic>(
          relation == 'revenue_document' ? 'revenue_void' : 'expense_void',
          params: {
            'p_id': row['id'],
            'p_reason': 'Reversing a Slice 10 drill-down fixture ($_marker)',
            'p_base_row_version': row['row_version'],
            'p_mutation_id': const Uuid().v4(),
          },
        );
        reversed++;
      }
    }
    return reversed;
  }

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
          'p_reason':
              'Reopening a Slice 10 drill-down fixture period ($_marker)',
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
    await reverseStrandedFixtures();
    expect(
      await reverseStrandedFixtures(),
      0,
      reason: 'the run leaves nothing open',
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

  Future<String> revenueCategory(String unit, String code) async =>
      (await owner
              .from('revenue_categories')
              .select('id')
              .eq('code', code)
              .eq('business_unit_id', unit)
              .single())['id']
          as String;

  Future<String> createSale(int paise) async {
    final id = const Uuid().v7();
    await owner.rpc<dynamic>(
      'revenue_create',
      params: {
        'p_id': id,
        'p_business_unit_id': _ccr,
        'p_revenue_category_id': await revenueCategory(_ccr, 'RESTAURANT'),
        'p_business_date': _businessDate,
        'p_notes': _marker,
        'p_components': [
          {'entered_amount_minor': paise},
        ],
        'p_mutation_id': const Uuid().v4(),
      },
    );
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

  Future<String> createExpense(List<Map<String, Object>> allocations) async {
    final id = const Uuid().v7();
    await owner.rpc<dynamic>(
      'expense_create',
      params: {
        'p_id': id,
        'p_business_date': _businessDate,
        'p_total_minor': allocations.fold<int>(
          0,
          (sum, a) => sum + (a['amount_minor']! as int),
        ),
        'p_notes': _marker,
        'p_allocations': allocations,
        'p_mutation_id': const Uuid().v4(),
      },
    );
    return id;
  }

  /// A device that recorded none of this, synchronised for [userId].
  Future<({AppDatabase db, ReportingCache cache, ReportingSync sync})> device(
    SupabaseClient client,
    String userId, {
    required Set<String> units,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = ReportingCache(db);
    final sync = ReportingSync(
      cache: cache,
      gateway: ReportingGateway(client),
      ownerUserId: userId,
      orgId: 'live',
    );
    final report = await sync.synchronise(businessUnitIds: units, years: [_fy]);
    expect(report.isComplete, isTrue);
    return (db: db, cache: cache, sync: sync);
  }

  Future<CachedDrilldownSource> sourceOver(
    ReportingCache cache,
    String userId,
    List<CapabilityGrant> grants,
  ) async => CachedDrilldownSource(
    cache: cache,
    principal: Principal(userId: userId, grants: grants),
    coverage: await MarkerCoverage.load(cache, userId),
  );

  ReportDocumentReader readerFor(SupabaseClient client) => ReportDocumentReader(
    expenses: ExpenseGateway(client),
    revenue: RevenueGateway(client),
  );

  Future<Map<String, int>> counts(AppDatabase db) async => {
    for (final table in const [
      'expenses',
      'expense_allocations',
      'expense_period_allocations',
      'expense_attachments',
      'revenue_entries',
      'revenue_components',
      'revenue_attachments',
      'sync_outbox',
      'reporting_revenue_contributions',
      'reporting_expense_contributions',
      'reporting_coverage_markers',
    ])
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS c FROM $table')
                  .getSingle())
              .read<int>('c'),
  };

  List<T> rowsOf<T>(DrilldownRows<T> rows) => switch (rows) {
    DrilldownRowsAvailable(:final rows) => rows,
    DrilldownRowsUnavailable(:final reason) => fail('unavailable: $reason'),
  };

  Future<List<ExpenseDocumentLine>> ccrKirana(
    CachedDrilldownSource source,
  ) async => rowsOf(
    await source.expenseDocuments(
      scope: ReportingScope.unit(_ccr),
      range: _range,
      businessUnitId: _ccr,
      departmentId: _ccrDept,
      sectionId: _ccrSection,
      categoryId: _kirana,
    ),
  );

  Future<List<RevenueDocumentLine>> ccrRestaurant(
    CachedDrilldownSource source,
  ) async => rowsOf(
    await source.revenueDocuments(
      scope: ReportingScope.unit(_ccr),
      range: _range,
      businessUnitId: _ccr,
      revenueCategoryId: await revenueCategory(_ccr, 'RESTAURANT'),
    ),
  );

  /// What the server itself says this caller may report on, per property — the capability
  /// answer, never a role name.
  ///
  /// One property per call. A request naming both properties is the consolidated report,
  /// which needs unscoped authority, so asking about them together would refuse a scoped
  /// reader both of them (D-164, D-187) — true, and a different question.
  Future<Map<String, bool>> reportingAuthority(SupabaseClient client) async {
    final authority = <String, bool>{};
    for (final unit in [_ccr, _hki]) {
      final answer = Map<String, dynamic>.from(
        await client.rpc<dynamic>(
              'reporting_primitives',
              params: {
                'p_business_unit_ids': [unit],
                'p_from': _range.from.iso,
                'p_to': _range.to.iso,
              },
            )
            as Map,
      );
      final raw = (answer['units'] as List).single as Map;
      authority[unit] =
          raw['revenue_authorised'] == true &&
          raw['expense_authorised'] == true;
    }
    return authority;
  }

  test('a device that recorded nothing opens a document another device recorded, '
      'and persists none of it', () async {
    final sale = await createSale(1234500);
    final expense = await createExpense([ccrAllocation(456700)]);

    final b = await device(owner, ownerId, units: {_ccr, _hki});
    final source = await sourceOver(b.cache, ownerId, _pnl());

    // The rows under the category lines, exact.
    final restaurant = await ccrRestaurant(source);
    final saleLine = restaurant.firstWhere((l) => l.revenueEntryId == sale);
    final categoryLine = (await b.cache.revenueByCategory(
      ownerUserId: ownerId,
      businessUnitId: _ccr,
      range: _range,
    )).firstWhere((l) => l.revenueCategoryId == saleLine.revenueCategoryId);
    expect(
      PnlDrilldown.revenueChildrenReconcile(
        categoryLine.totals,
        restaurant.map((l) => l.totals),
      ),
      isTrue,
    );
    final costLine = (await ccrKirana(
      source,
    )).firstWhere((l) => l.expenseId == expense);
    expect(costLine.totals.amount.paise, 456700);

    final before = await counts(b.db);
    expect(before['expenses'], 0);
    expect(before['revenue_entries'], 0);
    expect(before['sync_outbox'], 0);

    final reader = readerFor(owner);
    final saleDetail = await reader.revenueFor(saleLine, range: _range);
    expect(saleDetail, isA<ReportDocumentReady<RevenueEntry>>());
    final entry = (saleDetail as ReportDocumentReady<RevenueEntry>).document;
    expect(entry.txnNumber, startsWith('KI-REV-'));
    expect(entry.gross.paise, saleLine.totals.gross.paise);

    final costDetail = await reader.expenseFor(costLine, range: _range);
    expect(costDetail, isA<ReportDocumentReady<ExpenseDocumentDetail>>());
    final detail =
        (costDetail as ReportDocumentReady<ExpenseDocumentDetail>).document;
    expect(detail.txnNumber, startsWith('KI-EXP-'));
    expect(detail.isScoped, isFalse);

    // Nothing landed in the ordinary transaction tables, the outbox or the cache.
    expect(await counts(b.db), before);
  });

  test(
    'a Crystal Canopy reader opens only its allocation of a shared bill',
    () async {
      final shared = await createExpense([
        ccrAllocation(2500000),
        hkiAllocation(3300000),
      ]);
      final manager = await sessionFor('ccr.manager@example.com');
      final managerId = manager.auth.currentUser!.id;
      final authority = await reportingAuthority(manager);
      expect(
        authority[_ccr],
        isTrue,
        reason: 'the server grants Crystal Canopy',
      );
      expect(authority[_hki], isFalse, reason: 'and withholds Hotel Krishna');

      final m = await device(manager, managerId, units: {_ccr});
      final source = await sourceOver(m.cache, managerId, _pnl(_ccr));
      final line = (await ccrKirana(
        source,
      )).firstWhere((l) => l.expenseId == shared);
      expect(line.totals.amount.paise, 2500000);

      final before = await counts(m.db);
      final outcome = await readerFor(manager).expenseFor(line, range: _range);
      expect(outcome, isA<ReportDocumentReady<ExpenseDocumentDetail>>());
      final detail =
          (outcome as ReportDocumentReady<ExpenseDocumentDetail>).document;
      expect(detail.isScoped, isTrue);
      expect(detail.visibleAmount.paise, 2500000);
      expect(detail.allocations.every((a) => a.businessUnitId == _ccr), isTrue);
      expect(detail.allocations.any((a) => a.amount.paise == 3300000), isFalse);
      expect(await counts(m.db), before);
    },
  );

  test(
    'a Hotel Krishna document cannot be opened from a Crystal Canopy drill-down',
    () async {
      final hkiOnly = await createExpense([hkiAllocation(3300000)]);
      final manager = await sessionFor('ccr.manager@example.com');
      final managerId = manager.auth.currentUser!.id;
      final m = await device(manager, managerId, units: {_ccr});
      final source = await sourceOver(m.cache, managerId, _pnl(_ccr));

      // Not listable: outside the reader's authority and outside a Crystal Canopy report.
      for (final scope in [
        ReportingScope.unit(_hki),
        ReportingScope.unit(_ccr),
      ]) {
        expect(
          await source.expenseDocuments(
            scope: scope,
            range: _range,
            businessUnitId: _hki,
            departmentId: _hkiDept,
            sectionId: _hkiSection,
            categoryId: _hkiCategory,
          ),
          isA<DrilldownRowsUnavailable<ExpenseDocumentLine>>().having(
            (r) => r.reason,
            'reason',
            ReportingCoverage.notAuthorised,
          ),
        );
      }
      // And a forged request naming it is withheld by the server itself.
      final forged = ExpenseDocumentLine(
        businessUnitId: _hki,
        departmentId: _hkiDept,
        sectionId: _hkiSection,
        categoryId: _hkiCategory,
        expenseId: hkiOnly,
        firstPnlDate: BusinessDate.tryParse(_businessDate)!,
        lastPnlDate: BusinessDate.tryParse(_businessDate)!,
        totals: rowsOf(
          await (await sourceOver(
            (await device(owner, ownerId, units: {_hki})).cache,
            ownerId,
            _pnl(),
          )).expenseDocuments(
            scope: ReportingScope.unit(_hki),
            range: _range,
            businessUnitId: _hki,
            departmentId: _hkiDept,
            sectionId: _hkiSection,
            categoryId: _hkiCategory,
          ),
        ).firstWhere((l) => l.expenseId == hkiOnly).totals,
      );
      expect(
        await readerFor(manager).expenseFor(forged, range: _range),
        isA<ReportDocumentNotAvailable<ExpenseDocumentDetail>>(),
      );
    },
  );

  test(
    'a correction after the report synchronised is refused until the report is refreshed',
    () async {
      final sale = await createSale(3456700);
      final b = await device(owner, ownerId, units: {_ccr});
      var line = (await ccrRestaurant(
        await sourceOver(b.cache, ownerId, _pnl()),
      )).firstWhere((l) => l.revenueEntryId == sale);

      await owner.rpc<dynamic>(
        'revenue_update',
        params: {
          'p_id': sale,
          'p_business_date': _businessDate,
          'p_notes': _marker,
          'p_components': [
            {'entered_amount_minor': 2222200},
          ],
          'p_base_row_version': (await owner
              .from('revenue_document')
              .select('row_version')
              .eq('id', sale)
              .single())['row_version'],
          'p_mutation_id': const Uuid().v4(),
        },
      );

      final reader = readerFor(owner);
      expect(
        await reader.revenueFor(line, range: _range),
        isA<ReportDocumentChanged<RevenueEntry>>(),
        reason: 'the fresher figures are not presented as the cached row',
      );

      await b.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
      line = (await ccrRestaurant(
        await sourceOver(b.cache, ownerId, _pnl()),
      )).firstWhere((l) => l.revenueEntryId == sale);
      expect(line.totals.gross.paise, 2222200);
      expect(
        await reader.revenueFor(line, range: _range),
        isA<ReportDocumentReady<RevenueEntry>>(),
      );
    },
  );

  test("a closed period's documents remain readable", () async {
    final sale = await createSale(789000);
    final expense = await createExpense([ccrAllocation(120300)]);
    final b = await device(owner, ownerId, units: {_ccr});

    await owner.rpc<dynamic>(
      'period_close',
      params: {
        'p_period_key': _period,
        'p_business_unit_id': _ccr,
        'p_mutation_id': const Uuid().v4(),
      },
    );
    addTearDown(reopenEverything);

    await b.sync.synchronise(businessUnitIds: {_ccr}, years: [_fy]);
    final source = await sourceOver(b.cache, ownerId, _pnl());
    final saleLine = (await ccrRestaurant(
      source,
    )).firstWhere((l) => l.revenueEntryId == sale);
    final costLine = (await ccrKirana(
      source,
    )).firstWhere((l) => l.expenseId == expense);
    final reader = readerFor(owner);
    expect(
      await reader.revenueFor(saleLine, range: _range),
      isA<ReportDocumentReady<RevenueEntry>>(),
    );
    expect(
      await reader.expenseFor(costLine, range: _range),
      isA<ReportDocumentReady<ExpenseDocumentDetail>>(),
    );
    await reopenEverything();
  });
}
