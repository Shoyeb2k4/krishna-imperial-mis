/// The dashboard engine (Phase 6 Slice 3).
///
/// Everything below runs on the real stack: a real SQLite database, the real canonical
/// reporting cache filled by the real `ReportingSync`, the real `MarkerCoverage`,
/// `CachedReportingSource`, `LocalReportingEngine`, `Pnl.compute` and the real
/// `CanonicalCacheLock`. Only the remote transport is a fake, and it is the same fake the
/// Phase 5 P&L fixtures use.
///
/// Every expected figure is worked by hand from the fixture rows in the comment beside it.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/dashboard_engine.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/canonical_cache_lock.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

import '../support/cache_principal.dart';
import '../support/pnl_fixture.dart';

const _me = 'user-me';

/// Counts what the engine actually reads, without changing what it reads.
final class _Counting
    with PerUnitReportingFacts
    implements ReportingFactsSource {
  _Counting(this.inner);

  final CachedReportingSource inner;
  final scopeReads = <ReportRange>[];
  Future<void> Function()? onScopeRead;

  @override
  Future<UnitReportingFacts> factsFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingScope scope,
  }) => inner.factsFor(
    businessUnitId: businessUnitId,
    range: range,
    scope: scope,
  );

  @override
  Future<ReportingScopeFacts> factsForScope({
    required ReportRange range,
    required ReportingScope scope,
  }) async {
    scopeReads.add(range);
    final facts = await super.factsForScope(range: range, scope: scope);
    if (onScopeRead case final hook?) await hook();
    return facts;
  }

  @override
  Future<ReportingSnapshotEvidence?> snapshotEvidenceFor({
    required ReportRange range,
    required ReportingScope scope,
  }) => inner.snapshotEvidenceFor(range: range, scope: scope);
}

void main() {
  late AppDatabase db;
  late ReportingCache cache;
  late FakeReportingGateway gateway;
  late ReportingSync sync;

  // Thursday 17 September 2026. Month to date is 1–17 September; its comparator is
  // 1–17 August.
  final today = BusinessDate.of(2026, 9, 17);
  final fy = FinancialYear.of(today);

  DashboardPeriodPair pairFor(DashboardPeriodKind kind) =>
      (DashboardPeriods.forToday(kind, today) as DashboardPairResolved).pair;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    cache = ReportingCache(db);
    gateway = FakeReportingGateway();
    sync = ReportingSync(
      cache: cache,
      gateway: gateway,
      ownerUserId: _me,
      orgId: 'test-org',
    );
  });

  tearDown(() => db.close());

  Future<void> synchronise({Set<String> units = const {pnlCcr, pnlHki}}) async {
    final report = await sync.synchronise(
      businessUnitIds: units,
      years: [fy, fy.previous],
    );
    expect(report.isComplete, isTrue);
  }

  Future<_Counting> source() async => _Counting(
    CachedReportingSource(
      cache: cache,
      principal: canonicalCachePrincipal(_me),
      coverage: await MarkerCoverage.load(cache, _me),
    ),
  );

  DashboardEngine engineOver(
    ReportingFactsSource facts, {
    CanonicalCacheLock? lock,
  }) => DashboardEngine(
    reports: LocalReportingEngine(facts),
    lock: lock ?? CanonicalCacheLock(),
  );

  group('a month-to-date dashboard, assembled from the real cache', () {
    // Crystal Canopy only, so the arithmetic is readable.
    //
    //   September (current, 1–17)
    //     sales   3 Sept  gross 10,500.00 tax 500.00  net 10,000.00
    //             9 Sept  gross  6,300.00 tax 300.00  net  6,000.00
    //     costs   4 Sept  2,000.00 · 9 Sept 1,500.00
    //     gross 16,800.00 · GST 800.00 · net 16,000.00 · expenses 3,500.00
    //     operating profit 12,500.00
    //
    //   August (comparison, 1–17)
    //     sales   5 Aug   gross  8,400.00 tax 400.00  net  8,000.00
    //     costs   6 Aug   2,000.00
    //     gross 8,400.00 · GST 400.00 · net 8,000.00 · expenses 2,000.00
    //     operating profit 6,000.00
    //
    //   Outside the comparator on purpose: 25 Aug, to prove the comparison stops at the
    //   17th rather than taking the whole previous month.
    setUp(() async {
      gateway
        ..revenue.add(pnlSale(pnlCcr, '2026-09-03', gross: 1050000, tax: 50000))
        ..revenue.add(pnlSale(pnlCcr, '2026-09-09', gross: 630000, tax: 30000))
        ..revenue.add(pnlSale(pnlCcr, '2026-08-05', gross: 840000, tax: 40000))
        ..revenue.add(
          pnlSale(pnlCcr, '2026-08-25', gross: 9900000, tax: 400000),
        )
        ..expense.add(pnlCost(pnlCcr, '2026-09-04', 200000))
        ..expense.add(pnlCost(pnlCcr, '2026-09-09', 150000))
        ..expense.add(pnlCost(pnlCcr, '2026-08-06', 200000));
      await synchronise();
    });

    test('the headline is the P&L of the period so far', () async {
      final view = await engineOver(await source()).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.monthToDate),
          scope: ReportingScope.unit(pnlCcr),
        ),
      );
      final result = view.resultOrNull!;
      expect(result.grossSales, Money.fromPaise(1680000));
      expect(result.gst, Money.fromPaise(80000));
      expect(result.netSales, Money.fromPaise(1600000));
      expect(result.expenses, Money.fromPaise(350000));
      expect(result.operatingProfit, Money.fromPaise(1250000));
      expect(result.range, pairFor(DashboardPeriodKind.monthToDate).current);
    });

    test('the comparator is the same stretch, not the whole month', () async {
      final view = await engineOver(await source()).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.monthToDate),
          scope: ReportingScope.unit(pnlCcr),
        ),
      );
      // 8,000.00 net, not 8,000.00 + 95,000.00: the 25 August sale is outside 1–17 Aug.
      expect(view.previous.resultOrNull!.netSales, Money.fromPaise(800000));

      // Net Sales 16,000.00 against 8,000.00: +8,000.00, +100.00%.
      final net = view.comparison.netSales as MoneyComparisonAvailable;
      expect(net.change, Money.fromPaise(800000));
      expect(
        (net.percentChange as PercentChangeRatio).percentageScaled(2),
        10000,
      );
      // Operating Profit 12,500.00 against 6,000.00: +6,500.00.
      final profit =
          view.comparison.operatingProfit as MoneyComparisonAvailable;
      expect(profit.change, Money.fromPaise(650000));
      expect(profit.transition, ProfitTransition.none);
    });

    test('a daily Net Sales trend is one point per day, in order', () async {
      final view = await engineOver(await source()).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.monthToDate),
          scope: ReportingScope.unit(pnlCcr),
          trends: const [
            DashboardTrendRequest(
              measure: TrendMeasure.netSales,
              grain: TrendGrain.daily,
            ),
          ],
        ),
      );
      final series = view.trends.single;
      expect(series.points, hasLength(17));
      expect(series.hasGap, isFalse);
      final amounts = [
        for (final point in series.points) (point as TrendValue).amount.paise,
      ];
      // 10,000.00 on the 3rd, 6,000.00 on the 9th, nothing else. Real zeroes, not gaps.
      expect(amounts[2], 1000000);
      expect(amounts[8], 600000);
      expect(amounts.fold<int>(0, (s, a) => s + a), 1600000);
      expect(view.stats.trendPoints, 17);
    });

    test('best and worst day rank Net Sales, and reuse the same reads', () async {
      final facts = await source();
      final view = await engineOver(facts).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.monthToDate),
          scope: ReportingScope.unit(pnlCcr),
          trends: const [
            DashboardTrendRequest(
              measure: TrendMeasure.netSales,
              grain: TrendGrain.daily,
            ),
          ],
          rankDailyNetSales: true,
        ),
      );
      final ranked = view.ranking! as DailyRanked;
      expect(ranked.best, Money.fromPaise(1000000));
      expect(ranked.bestDays, [BusinessDate.of(2026, 9, 3)]);
      expect(ranked.worst, Money.zero);
      // Fifteen quiet days tie at zero, and a tie is reported rather than broken.
      expect(ranked.worstDays, hasLength(15));

      // 17 days + the current period + its comparator, and not one read more: the trend
      // and the ranking are the same seventeen single-day reports.
      expect(view.stats.rangesRead, 19);
      expect(facts.scopeReads, hasLength(19));
      expect(facts.scopeReads.toSet(), hasLength(19));
    });

    test('Top N groups the categories the headline already carries', () async {
      final view = await engineOver(await source()).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.monthToDate),
          scope: ReportingScope.unit(pnlCcr),
          topN: 1,
        ),
      );
      final expenses =
          view.topExpenseCategories! as TopNGrouped<ExpenseHierarchyLine>;
      // One category in the fixture, so it is the whole of Expenses and Others is empty.
      expect(expenses.total, Money.fromPaise(350000));
      expect(expenses.top.single.amount, Money.fromPaise(350000));
      expect(expenses.others, isNull);
      final revenue =
          view.topRevenueCategories! as TopNGrouped<RevenueCategoryLine>;
      expect(revenue.total, Money.fromPaise(1600000));
    });

    test('nothing is asked for by default', () async {
      final facts = await source();
      final view = await engineOver(facts).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.monthToDate),
          scope: ReportingScope.unit(pnlCcr),
        ),
      );
      expect(view.trends, isEmpty);
      expect(view.ranking, isNull);
      expect(view.topExpenseCategories, isNull);
      expect(view.topRevenueCategories, isNull);
      expect(view.stats.rangesRead, 2);
      expect(facts.scopeReads, hasLength(2));
    });
  });

  group('a consolidated financial year to date', () {
    setUp(() async {
      gateway
        ..revenue.add(
          pnlSale(pnlCcr, '2026-05-10', gross: 2100000, tax: 100000),
        )
        ..revenue.add(pnlSale(pnlHki, '2026-07-12', gross: 1050000, tax: 50000))
        ..expense.add(pnlCost(pnlCcr, '2026-06-11', 400000))
        ..expense.add(pnlCost(pnlHki, '2026-08-15', 300000));
      await synchronise();
    });

    test(
      'a monthly trend covers April to September, the last partial',
      () async {
        final facts = await source();
        final view = await engineOver(facts).build(
          DashboardRequest(
            pair: pairFor(DashboardPeriodKind.financialYearToDate),
            scope: ReportingScope(const {pnlCcr, pnlHki}),
            trends: const [
              DashboardTrendRequest(
                measure: TrendMeasure.operatingProfit,
                grain: TrendGrain.monthly,
              ),
            ],
          ),
        );
        final series = view.trends.single;
        expect(series.points, hasLength(6));
        expect(series.points.last.bucket.partial, isTrue);
        expect(series.points.first.bucket.partial, isFalse);

        // May +20,000.00 · June −4,000.00 · July +10,000.00 · August −3,000.00.
        final profits = [
          for (final point in series.points) (point as TrendValue).amount.paise,
        ];
        expect(profits, [0, 2000000, -400000, 1000000, -300000, 0]);

        // Consolidated headline: net 30,000.00 − expenses 7,000.00 = 23,000.00.
        expect(view.resultOrNull!.operatingProfit, Money.fromPaise(2300000));
        expect(view.resultOrNull!.isConsolidated, isTrue);

        // Six buckets + current + comparison.
        expect(view.stats.rangesRead, 8);
        expect(facts.scopeReads, hasLength(8));
      },
    );
  });

  group('a refused period refuses the view', () {
    test('an unsynchronised scope reads nothing but the two headlines', () async {
      // Nothing synchronised: the markers say notDownloaded, for every range.
      final facts = await source();
      final view = await engineOver(facts).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.monthToDate),
          scope: ReportingScope.unit(pnlCcr),
          trends: const [
            DashboardTrendRequest(
              measure: TrendMeasure.netSales,
              grain: TrendGrain.daily,
            ),
          ],
          rankDailyNetSales: true,
          topN: 3,
        ),
      );
      expect(view.isComputed, isFalse);
      expect(view.refusalOrNull, PnlRefusal.bothSidesUnavailable);
      expect(view.revenueCoverage, ReportingCoverage.notDownloaded);

      // No trend, no ranking, no grouping — and, crucially, no thirty-one reads spent
      // arriving at the same refusal thirty-one more times.
      expect(view.trends, isEmpty);
      expect(view.ranking, isNull);
      expect(view.topExpenseCategories, isNull);
      expect(view.stats.rangesRead, 2);
      expect(facts.scopeReads, hasLength(2));

      // The comparison is still produced, and it is unavailable rather than zero.
      expect(view.comparison.netSales, isA<MoneyComparisonUnavailable>());
    });

    test('a refused comparator leaves the headline standing', () async {
      // The current financial year is synchronised and the previous one is not, so a
      // financial-year-to-date comparison reaches back into a range with no coverage.
      gateway.revenue.add(
        pnlSale(pnlCcr, '2026-05-10', gross: 2100000, tax: 100000),
      );
      final report = await sync.synchronise(
        businessUnitIds: {pnlCcr},
        years: [fy],
      );
      expect(report.isComplete, isTrue);

      final view = await engineOver(await source()).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.financialYearToDate),
          scope: ReportingScope.unit(pnlCcr),
        ),
      );
      expect(view.isComputed, isTrue);
      expect(view.previous.isComputed, isFalse);
      expect(view.comparison.netSales, isA<MoneyComparisonUnavailable>());
      expect(
        (view.comparison.netSales as MoneyComparisonUnavailable).side,
        ComparisonSide.previous,
      );
      expect(view.comparison.margin, isA<MarginComparisonUnavailable>());
    });
  });

  group('coverage and freshness are claims about the whole view', () {
    // The rows only; each test synchronises the years its own point needs.
    setUp(() {
      gateway
        ..revenue.add(pnlSale(pnlCcr, '2026-09-03', gross: 1050000, tax: 50000))
        ..expense.add(pnlCost(pnlCcr, '2026-09-04', 200000));
    });

    test('one synchronisation gives one shared claim', () async {
      await synchronise(units: {pnlCcr});
      final view = await engineOver(await source()).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.monthToDate),
          scope: ReportingScope.unit(pnlCcr),
          trends: const [
            DashboardTrendRequest(
              measure: TrendMeasure.netSales,
              grain: TrendGrain.daily,
            ),
          ],
        ),
      );
      expect(view.revenueCoverage, ReportingCoverage.complete);
      expect(view.expenseCoverage, ReportingCoverage.complete);
      expect(view.freshness, isNotNull);
      expect(
        view.freshness!.state,
        ReportingFreshnessState.synchronised,
        reason: 'every read belonged to the same snapshot',
      );
    });

    test('a part with no claim withholds the claim for the whole view', () async {
      // Only the current financial year is synchronised. A financial year to date is
      // therefore certified, and its comparator — a year earlier — is not.
      final report = await sync.synchronise(
        businessUnitIds: {pnlCcr},
        years: [fy],
      );
      expect(report.isComplete, isTrue);

      final view = await engineOver(await source()).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.financialYearToDate),
          scope: ReportingScope.unit(pnlCcr),
        ),
      );
      expect(view.current.freshness, isNotNull);
      expect(view.previous.freshness, isNull);
      expect(
        view.freshness,
        isNull,
        reason:
            'a badge taken from the headline would date the whole view to a moment '
            'part of it does not belong to',
      );
      expect(
        view.expenseCoverage,
        ReportingCoverage.notDownloaded,
        reason: 'the weakest coverage across every read, not the headline’s',
      );
    });
  });

  group('the whole view is one span', () {
    setUp(() async {
      gateway
        ..revenue.add(pnlSale(pnlCcr, '2026-09-03', gross: 1050000, tax: 50000))
        ..expense.add(pnlCost(pnlCcr, '2026-09-04', 200000));
      await synchronise(units: {pnlCcr});
    });

    test('a synchronisation cannot land between two of its reads', () async {
      final lock = CanonicalCacheLock();
      final facts = await source();

      // A write queued on the same lock after the first read has happened. If the view
      // did not hold the lock for all of it, this would commit mid-view and the trend
      // would be half one snapshot and half another (D-188).
      var writeFinished = false;
      var readsWhenWriteFinished = -1;
      Future<void>? write;
      facts.onScopeRead = () async {
        if (write != null) return;
        write = lock.run(() async {
          gateway.revenue.add(
            pnlSale(pnlCcr, '2026-09-10', gross: 2100000, tax: 100000),
          );
          await sync.synchronise(
            businessUnitIds: {pnlCcr},
            years: [fy, fy.previous],
          );
          writeFinished = true;
          readsWhenWriteFinished = facts.scopeReads.length;
        });
        // Give the queued write every chance to run ahead of the rest of the view.
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      };

      final view = await engineOver(facts, lock: lock).build(
        DashboardRequest(
          pair: pairFor(DashboardPeriodKind.monthToDate),
          scope: ReportingScope.unit(pnlCcr),
          trends: const [
            DashboardTrendRequest(
              measure: TrendMeasure.netSales,
              grain: TrendGrain.daily,
            ),
          ],
        ),
      );

      expect(
        writeFinished,
        isFalse,
        reason: 'the write ran while the view was still reading',
      );
      expect(readsWhenWriteFinished, -1);

      // The view is entirely the state before the write: 10,000.00, not 30,000.00.
      expect(view.resultOrNull!.netSales, Money.fromPaise(1000000));
      final amounts = [
        for (final point in view.trends.single.points)
          (point as TrendValue).amount.paise,
      ];
      expect(amounts.fold<int>(0, (s, a) => s + a), 1000000);

      // The write was queued behind the view, not lost. Let it finish before the
      // database closes, and confirm it was waiting for the lock rather than failing.
      await write;
      expect(writeFinished, isTrue);
      expect(readsWhenWriteFinished, 19);
    });
  });
}
