/// `RemoteReportingEngine`, and the D-020 parity contract at host level.
///
/// Phase 5 Slice 5. One set of canonical facts is fed to **both** paths — into the
/// synchronised reporting cache the local engine reads, and into the payload the server
/// boundary would return — and the two reports are compared to the paisa.
///
/// ## What this proves, and what only `krishna-mis-dev` can
///
/// This proves the **contract**: the wire mapping, the authorisation mapping, the failure
/// mapping, and that both engines end at the same `PnlResult` for the same facts. It cannot
/// prove that `public.reporting_primitives` sums the same rows the cache holds — that is a
/// fact about Postgres, and this project's record is that the defects live exactly there
/// (D-115's RPC that had never created an entry, D-116's capability no role held, D-160's
/// ledger that never refreshed). The live suite does that half.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/remote_reporting_source.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/drift_reporting_source.dart'
    show ReportingCoverageOracle;
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/reporting/remote_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/report_parity.dart';

const _org = 'org-1';
const _me = 'user-me';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _fy = 2026;

/// One canonical revenue component, exactly as both sides receive it.
typedef _Rev = ({
  String id,
  String entry,
  String unit,
  String category,
  String pnlDate,
  int gross,
  int tax,
  int net,
  String treatment,
});

typedef _Exp = ({
  String id,
  String expense,
  String unit,
  String department,
  String section,
  String category,
  String pnlDate,
  int amount,
});

/// The server boundary, modelled from the same fixtures the cache is filled from.
///
/// It reproduces exactly what `public.reporting_primitives` does and nothing more: gate each
/// side on a capability, filter `pnl_date` inclusively, sum in integers, and return **null**
/// for a side the caller may not read.
final class _FakeBoundary extends ReportingGateway {
  _FakeBoundary() : super(SupabaseClient('http://localhost', 'test-key'));

  final List<_Rev> revenue = [];
  final List<_Exp> expenses = [];

  /// Which properties this caller holds `revenue.view` / `expense.view.all` for.
  Set<String> revenueAuthority = {_ccr, _hki};
  Set<String> expenseAuthority = {_ccr, _hki};

  /// Every call made, so a retry can be shown to be a repeat rather than a new question.
  final List<String> calls = [];

  /// When set, the next call fails the way an unreachable server does.
  bool offline = false;

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> primitives({
    required List<String> businessUnitIds,
    required String fromIsoDate,
    required String toIsoDate,
    bool breakdown = false,
  }) async {
    calls.add(
      '${businessUnitIds.join('+')} $fromIsoDate..$toIsoDate b=$breakdown',
    );
    if (offline) {
      return const RemoteUnreachable(RemoteFailure.offline);
    }

    bool inRange(String d) =>
        d.compareTo(fromIsoDate) >= 0 && d.compareTo(toIsoDate) <= 0;

    final units = <Map<String, dynamic>>[];
    for (final unit in businessUnitIds) {
      final revOk = revenueAuthority.contains(unit);
      final expOk = expenseAuthority.contains(unit);
      final rev = revenue
          .where((r) => r.unit == unit && inRange(r.pnlDate))
          .toList();
      final exp = expenses
          .where((e) => e.unit == unit && inRange(e.pnlDate))
          .toList();

      final byCategory = <String, List<_Rev>>{};
      for (final r in rev) {
        (byCategory[r.category] ??= []).add(r);
      }
      final byHierarchy = <String, List<_Exp>>{};
      for (final e in exp) {
        (byHierarchy['${e.department}|${e.section}|${e.category}'] ??= []).add(
          e,
        );
      }

      units.add({
        'business_unit_id': unit,
        'revenue_authorised': revOk,
        'expense_authorised': expOk,
        'revenue': revOk
            ? {
                'gross_minor': rev.fold(0, (int n, r) => n + r.gross),
                'tax_minor': rev.fold(0, (int n, r) => n + r.tax),
                'net_minor': rev.fold(0, (int n, r) => n + r.net),
                'contributions': rev.length,
              }
            : null,
        'expense': expOk
            ? {
                'amount_minor': exp.fold(0, (int n, e) => n + e.amount),
                'contributions': exp.length,
              }
            : null,
        'revenue_by_category': revOk && breakdown
            ? [
                for (final key in byCategory.keys.toList()..sort())
                  {
                    'revenue_category_id': key,
                    'tax_treatment':
                        byCategory[key]!
                                .map((r) => r.treatment)
                                .toSet()
                                .length ==
                            1
                        ? byCategory[key]!.first.treatment
                        : null,
                    'gross_minor': byCategory[key]!.fold(
                      0,
                      (int n, r) => n + r.gross,
                    ),
                    'tax_minor': byCategory[key]!.fold(
                      0,
                      (int n, r) => n + r.tax,
                    ),
                    'net_minor': byCategory[key]!.fold(
                      0,
                      (int n, r) => n + r.net,
                    ),
                    'contributions': byCategory[key]!.length,
                  },
              ]
            : <Map<String, dynamic>>[],
        'expense_by_hierarchy': expOk && breakdown
            ? [
                for (final key in byHierarchy.keys.toList()..sort())
                  {
                    'department_id': key.split('|')[0],
                    'section_id': key.split('|')[1],
                    'category_id': key.split('|')[2],
                    'amount_minor': byHierarchy[key]!.fold(
                      0,
                      (int n, e) => n + e.amount,
                    ),
                    'contributions': byHierarchy[key]!.length,
                  },
              ]
            : <Map<String, dynamic>>[],
      });
    }
    return RemoteOk({'from': fromIsoDate, 'to': toIsoDate, 'units': units});
  }
}

/// Coverage a test controls, so the local engine can be told which years it holds.
final class _Markers implements ReportingCoverageOracle {
  _Markers(this.covered);
  Set<String> covered;

  @override
  ReportingCoverage coverageFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingDatasetSide side,
  }) => covered.contains(businessUnitId)
      ? ReportingCoverage.complete
      : ReportingCoverage.notDownloaded;
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late ReportingCache cache;
  late _FakeBoundary boundary;
  late _Markers markers;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    cache = ReportingCache(db);
    boundary = _FakeBoundary();
    markers = _Markers({_ccr, _hki});
  });
  tearDown(() => db.close());

  LocalReportingEngine local() => LocalReportingEngine(
    CachedReportingSource(cache: cache, ownerUserId: _me, coverage: markers),
  );
  RemoteReportingEngine remote() =>
      RemoteReportingEngine(RemoteReportingSource(boundary));

  /// Records a fact **once**, into both the cache and the server model. One fixture, two
  /// destinations — if the two were seeded separately the suite would be comparing two
  /// transcriptions rather than two engines.
  Future<void> revenueFact({
    required String id,
    required String unit,
    required String category,
    required String pnlDate,
    required int gross,
    required int tax,
    required int net,
    String treatment = 'inclusive',
    String? entry,
  }) async {
    final row = (
      id: id,
      entry: entry ?? 'entry-$id',
      unit: unit,
      category: category,
      pnlDate: pnlDate,
      gross: gross,
      tax: tax,
      net: net,
      treatment: treatment,
    );
    boundary.revenue.add(row);
    await cache.applyYear(
      ownerUserId: _me,
      orgId: _org,
      dataset: ReportingDataset.revenue,
      financialYear: _fy,
      businessUnitIds: {unit},
      documentIds: [row.entry],
      rows: [
        RevenueRowValues(
          contributionId: id,
          revenueEntryId: row.entry,
          businessUnitId: unit,
          revenueCategoryId: category,
          pnlDate: pnlDate,
          pnlPeriodKey: pnlDate.substring(0, 7),
          grossMinor: gross,
          taxMinor: tax,
          netMinor: net,
          taxTreatment: treatment,
          taxRateBasisPoints: 500,
          enteredBasis: 'inclusive_total',
          documentGeneration: 1,
        ),
      ],
      generation: 1,
      onDemand: false,
      now: DateTime.utc(2026, 9, 7),
    );
  }

  Future<void> expenseFact({
    required String id,
    required String unit,
    required String pnlDate,
    required int amount,
    String department = 'dep-1',
    String section = 'sec-1',
    String category = 'cat-kirana',
    String? expense,
  }) async {
    final row = (
      id: id,
      expense: expense ?? 'exp-$id',
      unit: unit,
      department: department,
      section: section,
      category: category,
      pnlDate: pnlDate,
      amount: amount,
    );
    boundary.expenses.add(row);
    await cache.applyYear(
      ownerUserId: _me,
      orgId: _org,
      dataset: ReportingDataset.expense,
      financialYear: _fy,
      businessUnitIds: {unit},
      documentIds: [row.expense],
      rows: [
        ExpenseRowValues(
          contributionId: id,
          expenseId: row.expense,
          allocationId: 'alloc-$id',
          businessUnitId: unit,
          departmentId: department,
          sectionId: section,
          categoryId: category,
          pnlDate: pnlDate,
          pnlPeriodKey: pnlDate.substring(0, 7),
          amountMinor: amount,
          documentGeneration: 1,
        ),
      ],
      generation: 1,
      onDemand: false,
      now: DateTime.utc(2026, 9, 7),
    );
  }

  /// The verified four-category baseline, at the exact paise the parity vectors carry.
  Future<void> theVerifiedFour() async {
    await revenueFact(
      id: 'r-restaurant',
      unit: _ccr,
      category: 'cat-restaurant',
      pnlDate: '2026-06-15',
      gross: 10000000,
      tax: 476190,
      net: 9523810,
    );
    await revenueFact(
      id: 'r-nandbhog',
      unit: _ccr,
      category: 'cat-nandbhog',
      pnlDate: '2026-06-15',
      gross: 870000,
      tax: 41429,
      net: 828571,
    );
    await revenueFact(
      id: 'r-room',
      unit: _hki,
      category: 'cat-room',
      pnlDate: '2026-06-15',
      gross: 5200000,
      tax: 247619,
      net: 4952381,
    );
    await revenueFact(
      id: 'r-banquet',
      unit: _hki,
      category: 'cat-banquet',
      pnlDate: '2026-06-15',
      gross: 4034300,
      tax: 0,
      net: 4034300,
      treatment: 'none',
    );
    await expenseFact(
      id: 'e-ccr',
      unit: _ccr,
      pnlDate: '2026-06-20',
      amount: 4500000,
    );
    await expenseFact(
      id: 'e-hki',
      unit: _hki,
      pnlDate: '2026-06-20',
      amount: 3000000,
    );
  }

  Future<void> parityFor(
    ReportingPeriod period,
    ReportingScope scope, {
    required String context,
  }) async {
    final request = ReportRequest(period: period, scope: scope);
    expectParity(
      await local().report(request),
      await remote().report(request),
      context: context,
    );
  }

  const june = MonthPeriod(2026, 6);

  group('exact parity over the verified baseline', () {
    setUp(theVerifiedFour);

    test('Crystal Canopy, one month', () async {
      await parityFor(june, ReportingScope.unit(_ccr), context: 'CCR June');
      final result = (await local().report(
        ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
      )).resultOrNull!;
      expect(result.grossSales.paise, 10870000);
      expect(result.gst.paise, 517619);
      expect(result.netSales.paise, 10352381);
      expect(result.expenses.paise, 4500000);
      expect(result.operatingProfit.paise, 5852381);
    });

    test('Hotel Krishna, one month', () async {
      await parityFor(june, ReportingScope.unit(_hki), context: 'HKI June');
    });

    test('consolidated', () async {
      await parityFor(
        june,
        ReportingScope({_ccr, _hki}),
        context: 'consolidated June',
      );
      final result = (await remote().report(
        ReportRequest(period: june, scope: ReportingScope({_ccr, _hki})),
      )).resultOrNull!;
      expect(result.grossSales.paise, 20104300);
      expect(result.gst.paise, 765238);
      expect(result.netSales.paise, 19339062);
      expect(result.expenses.paise, 7500000);
    });

    test('per-unit sums equal the consolidated one, on both engines', () async {
      for (final engine in [local(), remote()]) {
        final ccr = (await engine.report(
          ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
        )).resultOrNull!;
        final hki = (await engine.report(
          ReportRequest(period: june, scope: ReportingScope.unit(_hki)),
        )).resultOrNull!;
        final all = (await engine.report(
          ReportRequest(period: june, scope: ReportingScope({_ccr, _hki})),
        )).resultOrNull!;
        expect(
          ccr.grossSales.paise + hki.grossSales.paise,
          all.grossSales.paise,
        );
        expect(ccr.gst.paise + hki.gst.paise, all.gst.paise);
        expect(ccr.netSales.paise + hki.netSales.paise, all.netSales.paise);
        expect(ccr.expenses.paise + hki.expenses.paise, all.expenses.paise);
      }
    });

    test('every period shape the client can ask for', () async {
      final periods = <String, ReportingPeriod>{
        'single day': SingleDayPeriod(BusinessDate.of(2026, 6, 15)),
        'week': WeekPeriod(BusinessDate.of(2026, 6, 15)),
        'month': june,
        'financial year': const FinancialYearPeriod(FinancialYear(2026)),
        'custom range': CustomRangePeriod(
          from: BusinessDate.of(2026, 6, 1),
          to: BusinessDate.of(2026, 6, 30),
        ),
        'same-day custom range': CustomRangePeriod(
          from: BusinessDate.of(2026, 6, 20),
          to: BusinessDate.of(2026, 6, 20),
        ),
        'range spanning the FY boundary': CustomRangePeriod(
          from: BusinessDate.of(2026, 3, 20),
          to: BusinessDate.of(2026, 7, 10),
        ),
      };
      for (final entry in periods.entries) {
        await parityFor(
          entry.value,
          ReportingScope({_ccr, _hki}),
          context: entry.key,
        );
      }
    });

    test(
      'categories stay independent, and none is distinguishable from 0%',
      () async {
        final result = (await remote().report(
          ReportRequest(period: june, scope: ReportingScope({_ccr, _hki})),
        )).resultOrNull!;

        final lines = {
          for (final l in result.revenueByCategory) l.revenueCategoryId: l,
        };
        expect(
          lines.keys.toSet(),
          {'cat-restaurant', 'cat-nandbhog', 'cat-room', 'cat-banquet'},
          reason:
              'Restaurant and Nandbhog share a rate and share no rule; nothing may merge '
              'them before the comparison (D-089)',
        );
        expect(lines['cat-banquet']!.totals.tax.paise, 0);
        expect(lines['cat-banquet']!.treatment?.name, 'none');
        expect(lines['cat-restaurant']!.treatment?.name, 'inclusive');

        // And the parity comparison itself carries the treatment, so a remote engine that
        // returned Banquet as a configured 0% would fail rather than pass on the money.
        await parityFor(
          june,
          ReportingScope({_ccr, _hki}),
          context: 'category treatments',
        );
      },
    );

    test(
      'the expense hierarchy agrees at the grain it is grouped to',
      () async {
        await expenseFact(
          id: 'e-ccr-2',
          unit: _ccr,
          pnlDate: '2026-06-22',
          amount: 175000,
          department: 'dep-2',
          section: 'sec-2',
          category: 'cat-water',
        );
        await parityFor(
          june,
          ReportingScope.unit(_ccr),
          context: 'expense hierarchy',
        );
        final result = (await remote().report(
          ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
        )).resultOrNull!;
        expect(result.expenseByHierarchy.length, 2);
        expect(result.expenseByHierarchy.map((l) => l.categoryId).toSet(), {
          'cat-kirana',
          'cat-water',
        });
      },
    );

    test('no re-rating: two Restaurant days sum to 750715', () async {
      // The paisa the component grain protects. Re-applying 5/105 to the aggregate gives
      // 750714, and neither engine is ever handed a rate with which to try.
      await revenueFact(
        id: 'r-day-1',
        unit: _ccr,
        category: 'cat-parity',
        pnlDate: '2026-07-01',
        gross: 7645000,
        tax: 364048,
        net: 7280952,
      );
      await revenueFact(
        id: 'r-day-2',
        unit: _ccr,
        category: 'cat-parity',
        pnlDate: '2026-07-02',
        gross: 8120000,
        tax: 386667,
        net: 7733333,
      );
      const july = MonthPeriod(2026, 7);
      await parityFor(july, ReportingScope.unit(_ccr), context: 'the paisa');

      for (final engine in [local(), remote()]) {
        final result = (await engine.report(
          ReportRequest(period: july, scope: ReportingScope.unit(_ccr)),
        )).resultOrNull!;
        expect(result.gst.paise, 750715);
        expect(
          result.gst.paise,
          isNot(15765000 * 5 ~/ 105),
          reason:
              're-applying the rate to the aggregate gives 750714, one paisa less than '
              'the sum of what was actually recorded',
        );
      }
    });

    test(
      'a complete range with no trade is a real zero on both engines',
      () async {
        const february = MonthPeriod(2026, 2);
        await parityFor(
          february,
          ReportingScope({_ccr, _hki}),
          context: 'empty range',
        );
        for (final engine in [local(), remote()]) {
          final result = (await engine.report(
            ReportRequest(
              period: february,
              scope: ReportingScope({_ccr, _hki}),
            ),
          )).resultOrNull!;
          expect(result.grossSales.paise, 0);
          expect(result.expenses.paise, 0);
          expect(result.revenueContributions, 0);
          expect(result.expenseContributions, 0);
          expect(result.margin, isA<MarginNotApplicable>());
        }
      },
    );

    test('a server that re-rated an aggregate would be caught (§7)', () async {
      // The control for the paisa. A boundary that answered by applying 5/105 to the
      // aggregate gross instead of summing the stored tax returns 750714 where the truth
      // is 750715 — and the parity suite has to fail on one paisa or it is not a parity
      // suite.
      await revenueFact(
        id: 'r-ctrl-1',
        unit: _ccr,
        category: 'cat-parity',
        pnlDate: '2026-08-01',
        gross: 7645000,
        tax: 364048,
        net: 7280952,
      );
      await revenueFact(
        id: 'r-ctrl-2',
        unit: _ccr,
        category: 'cat-parity',
        pnlDate: '2026-08-02',
        gross: 8120000,
        tax: 386667,
        net: 7733333,
      );

      // Degrade the server model to re-rate, exactly as the forbidden implementation
      // would, and leave every other figure untouched.
      final rerated = boundary.revenue
          .where((r) => r.pnlDate.startsWith('2026-08'))
          .toList();
      final grossTotal = rerated.fold(0, (int n, r) => n + r.gross);
      boundary.revenue
        ..removeWhere((r) => r.pnlDate.startsWith('2026-08'))
        ..add((
          id: 'r-ctrl-rerated',
          entry: 'entry-r-ctrl-1',
          unit: _ccr,
          category: 'cat-parity',
          pnlDate: '2026-08-01',
          gross: grossTotal,
          tax: grossTotal * 5 ~/ 105,
          net: grossTotal - (grossTotal * 5 ~/ 105),
          treatment: 'inclusive',
        ));
      expect(grossTotal * 5 ~/ 105, 750714);

      await expectLater(
        parityFor(
          const MonthPeriod(2026, 8),
          ReportingScope.unit(_ccr),
          context: 're-rated aggregate',
        ),
        throwsA(isA<TestFailure>()),
        reason: 'one paisa is a parity failure, and must be reported as one',
      );
    });

    test('the counts are compared, not only the money', () async {
      // A source that summed the right total over the wrong number of rows would pass on
      // every figure. This is the assertion that would catch it.
      boundary.revenue.add((
        id: 'ghost-a',
        entry: 'entry-ghost',
        unit: _ccr,
        category: 'cat-restaurant',
        pnlDate: '2026-06-15',
        gross: 0,
        tax: 0,
        net: 0,
        treatment: 'inclusive',
      ));
      await expectLater(
        parityFor(june, ReportingScope.unit(_ccr), context: 'row counts'),
        throwsA(isA<TestFailure>()),
      );
    });
  });

  group('authority, and the P&L that must not be assembled', () {
    setUp(theVerifiedFour);

    test('an unauthorised revenue side refuses, naming revenue', () async {
      boundary.revenueAuthority = {_hki};
      final envelope = await remote().report(
        ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
      );
      expect(envelope.refusalOrNull, PnlRefusal.revenueUnavailable);
      expect(envelope.revenueCoverage, ReportingCoverage.notAuthorised);
      expect(envelope.expenseCoverage, ReportingCoverage.complete);
      expect(
        (envelope.outcome as PnlRefused).sideReason,
        ReportingSideUnavailable.notAuthorised,
        reason:
            'not downloaded and not authorised send a reader to two different people',
      );
    });

    test(
      'Data Entry gets a refusal, never own-only expenses against zero revenue',
      () async {
        // The shape §34 names: `expense.view.own` gives a caller some expenses and no
        // revenue grant at all. A P&L built from that would be a large, plausible,
        // entirely fictitious loss.
        boundary.revenueAuthority = {};
        boundary.expenseAuthority = {_ccr};
        final envelope = await remote().report(
          ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
        );
        expect(envelope.isComputed, isFalse);
        expect(envelope.refusalOrNull, PnlRefusal.revenueUnavailable);
      },
    );

    test('neither side authorised refuses as both', () async {
      boundary.revenueAuthority = {};
      boundary.expenseAuthority = {};
      final envelope = await remote().report(
        ReportRequest(period: june, scope: ReportingScope({_ccr, _hki})),
      );
      expect(envelope.refusalOrNull, PnlRefusal.bothSidesUnavailable);
    });

    test('an empty scope asks the server nothing and refuses', () async {
      final envelope = await remote().report(
        ReportRequest(period: june, scope: ReportingScope(const <String>{})),
      );
      expect(envelope.refusalOrNull, PnlRefusal.noPermittedBusinessUnit);
      expect(
        boundary.calls,
        isEmpty,
        reason:
            'an omitted scope must never reach the server as a question it could answer '
            'for the whole organisation (§11)',
      );
    });

    test('a property outside the scope is not asked about', () async {
      await remote().report(
        ReportRequest(period: june, scope: ReportingScope.unit(_ccr)),
      );
      expect(boundary.calls.single, startsWith('$_ccr '));
    });
  });

  group('the remote engine is read-only and independent', () {
    setUp(theVerifiedFour);

    Future<List<int>> cacheCensus() async => [
      for (final table in const [
        'reporting_revenue_contributions',
        'reporting_expense_contributions',
        'reporting_coverage_markers',
      ])
        (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
            .read<int>('c'),
    ];

    test(
      'a repeated query returns the same primitives and writes nothing',
      () async {
        final before = await cacheCensus();
        final request = ReportRequest(
          period: june,
          scope: ReportingScope({_ccr, _hki}),
        );

        final first = await remote().report(request);
        final second = await remote().report(request);
        expectParity(first, second, context: 'retry');

        expect(
          await cacheCensus(),
          before,
          reason: 'the remote read moved a cached row',
        );
        expect(
          boundary.calls.length,
          2,
          reason: 'the second report did ask again',
        );
      },
    );

    test('a report does not move a coverage marker', () async {
      final before = await cache.markersFor(_me);
      await remote().report(
        ReportRequest(period: june, scope: ReportingScope({_ccr, _hki})),
      );
      final after = await cache.markersFor(_me);
      expect(after.length, before.length);
      for (var i = 0; i < before.length; i++) {
        expect(after[i].generation, before[i].generation);
        expect(after[i].financialYear, before[i].financialYear);
      }
    });

    test('an unreachable server refuses; it does not report zero', () async {
      boundary.offline = true;
      final envelope = await remote().report(
        ReportRequest(period: june, scope: ReportingScope({_ccr, _hki})),
      );
      expect(envelope.isComputed, isFalse);
      expect(envelope.refusalOrNull, PnlRefusal.bothSidesUnavailable);
      expect(
        envelope.coverage,
        ReportingCoverage.notDownloaded,
        reason: '"I could not ask" is never "the answer is nothing" (D-048 §1)',
      );
    });

    test(
      'the local engine answers with the server unreachable, from the cache',
      () async {
        boundary.offline = true;
        final envelope = await local().report(
          ReportRequest(period: june, scope: ReportingScope({_ccr, _hki})),
        );
        final result = envelope.resultOrNull!;
        expect(result.grossSales.paise, 20104300);
        expect(result.expenses.paise, 7500000);
        expect(
          boundary.calls,
          isEmpty,
          reason:
              'reporting is never gated on the network, and the local engine does not '
              'know the remote one exists (spec §21.4)',
        );
      },
    );
  });

  group('the permitted asymmetry, stated rather than skipped (§27)', () {
    setUp(theVerifiedFour);

    test(
      'an older range: local refuses as not downloaded, remote answers',
      () async {
        markers.covered = const {};
        final request = ReportRequest(
          period: june,
          scope: ReportingScope({_ccr, _hki}),
        );
        expectLocalUncoveredWhileRemoteAnswers(
          await local().report(request),
          await remote().report(request),
          context: 'a year retention never kept',
        );
      },
    );

    test('once it is downloaded, the two agree exactly', () async {
      markers.covered = const {};
      final request = ReportRequest(
        period: june,
        scope: ReportingScope({_ccr, _hki}),
      );
      expectLocalUncoveredWhileRemoteAnswers(
        await local().report(request),
        await remote().report(request),
        context: 'before the on-demand fetch',
      );

      markers.covered = {_ccr, _hki};
      expectParity(
        await local().report(request),
        await remote().report(request),
        context: 'after the on-demand fetch',
      );
    });
  });
}
