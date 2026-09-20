/// The dashboard workloads the Phase 6 Slice 3 performance gate measures.
///
/// Shared by the host measurement and the on-device one, so the two report the same work
/// rather than two things that resemble each other. The fixture is a representative year
/// of trade for two properties, written into the **real** canonical reporting cache, and
/// the workloads are the dashboards D-251 … D-263 actually offer.
///
/// Nothing here is a production path: it is a fixture and a list of requests.
library;

import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart'
    show ReportingDataset;
import 'package:krishna_mis/data/reporting/dashboard_engine.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

const dashboardCcr = 'unit-ccr';
const dashboardHki = 'unit-hki';

/// Revenue components per property per trading day.
const _salesPerDay = 3;

/// Expense contributions per property per trading day.
const _costsPerDay = 2;

const _expenseCategories = [
  'kirana',
  'vegetables',
  'electricity',
  'payroll',
  'maintenance',
  'water',
];
const _revenueCategories = ['restaurant', 'nandbhog'];

String _iso(BusinessDate date) => date.iso;

/// Writes [years] of representative trade for both properties into [db]'s reporting
/// cache, as one authoritative snapshot.
///
/// Returns how many rows were written, per side.
Future<({int revenue, int expense})> seedDashboardFixture(
  AppDatabase db, {
  required List<FinancialYear> years,
  String ownerUserId = 'user-me',
  String orgId = 'test-org',
  DateTime? serverConfirmedAt,
}) async {
  final cache = ReportingCache(db);
  final confirmedAt = serverConfirmedAt ?? DateTime.utc(2027, 4, 1, 3);
  var revenueRows = 0;
  var expenseRows = 0;
  var seq = 0;

  final revenueByYear = <int, List<ReportingRowValues>>{};
  final expenseByYear = <int, List<ReportingRowValues>>{};
  final revenueDocuments = <String>[];
  final expenseDocuments = <String>[];

  for (final year in years) {
    final revenue = <ReportingRowValues>[];
    final expense = <ReportingRowValues>[];
    var day = year.startsOn;
    while (day <= year.endsOn) {
      for (final unit in const [dashboardCcr, dashboardHki]) {
        for (var i = 0; i < _salesPerDay; i++) {
          seq++;
          // Amounts vary by day and index so no aggregate is trivially degenerate.
          final gross = 500000 + (day.day * 1000) + (i * 37700);
          final tax = gross ~/ 21; // an inclusive 5% treatment, to the paisa
          revenueDocuments.add('re-$seq');
          revenue.add(
            RevenueRowValues(
              contributionId: 'rc-$seq',
              revenueEntryId: 're-$seq',
              businessUnitId: unit,
              revenueCategoryId:
                  '$unit-${_revenueCategories[i % _revenueCategories.length]}',
              pnlDate: _iso(day),
              pnlPeriodKey: day.periodKey,
              grossMinor: gross,
              taxMinor: tax,
              netMinor: gross - tax,
              taxTreatment: 'inclusive',
              taxRateBasisPoints: 500,
              enteredBasis: 'inclusive_total',
              documentGeneration: seq,
            ),
          );
          revenueRows++;
        }
        for (var i = 0; i < _costsPerDay; i++) {
          seq++;
          final category =
              _expenseCategories[(day.day + i) % _expenseCategories.length];
          expenseDocuments.add('ex-$seq');
          expense.add(
            ExpenseRowValues(
              contributionId: 'ec-$seq',
              expenseId: 'ex-$seq',
              allocationId: 'al-$seq',
              businessUnitId: unit,
              departmentId: '$unit-dept-${i % 2}',
              sectionId: '$unit-section-${i % 2}',
              categoryId: '$unit-$category',
              pnlDate: _iso(day),
              pnlPeriodKey: day.periodKey,
              amountMinor: 40000 + (day.day * 700) + (i * 5300),
              documentGeneration: seq,
            ),
          );
          expenseRows++;
        }
      }
      day = day.addDays(1);
    }
    revenueByYear[year.openingYear] = revenue;
    expenseByYear[year.openingYear] = expense;
  }

  await cache.applySnapshot(
    ownerUserId: ownerUserId,
    orgId: orgId,
    snapshotId: 'dashboard-fixture',
    serverConfirmedAt: confirmedAt,
    businessUnitIds: const {dashboardCcr, dashboardHki},
    financialYears: [for (final year in years) year.openingYear],
    datasets: {
      ReportingDataset.revenue: DatasetApplication(
        documentIds: revenueDocuments,
        rowsByYear: revenueByYear,
        generationByYear: {for (final y in years) y.openingYear: seq},
      ),
      ReportingDataset.expense: DatasetApplication(
        documentIds: expenseDocuments,
        rowsByYear: expenseByYear,
        generationByYear: {for (final y in years) y.openingYear: seq},
      ),
    },
    onDemand: false,
    now: confirmedAt,
  );

  return (revenue: revenueRows, expense: expenseRows);
}

/// One measured dashboard.
final class DashboardWorkload {
  const DashboardWorkload({
    required this.name,
    required this.request,
    required this.expectedReads,
    required this.expectedTrendPoints,
  });

  final String name;
  final DashboardRequest request;

  /// Distinct ranges the plan must read. Deterministic, so a regression that doubled the
  /// work would fail rather than merely being slower on a busy machine.
  final int expectedReads;
  final int expectedTrendPoints;
}

DashboardPeriodPair _pair(DashboardPeriodKind kind, BusinessDate today) =>
    (DashboardPeriods.forToday(kind, today) as DashboardPairResolved).pair;

DashboardPeriodPair _custom(BusinessDate from, BusinessDate to) =>
    (DashboardPeriods.forCustom(from: from, to: to) as DashboardPairResolved)
        .pair;

const _netDaily = DashboardTrendRequest(
  measure: TrendMeasure.netSales,
  grain: TrendGrain.daily,
);
const _netWeekly = DashboardTrendRequest(
  measure: TrendMeasure.netSales,
  grain: TrendGrain.weekly,
);
const _netMonthly = DashboardTrendRequest(
  measure: TrendMeasure.netSales,
  grain: TrendGrain.monthly,
);
const _costMonthly = DashboardTrendRequest(
  measure: TrendMeasure.expenses,
  grain: TrendGrain.monthly,
);
const _profitMonthly = DashboardTrendRequest(
  measure: TrendMeasure.operatingProfit,
  grain: TrendGrain.monthly,
);

/// The workloads, consolidated across both properties — the heavier scope.
///
/// Every one is a dashboard the rulings actually permit: the grains come from
/// [DashboardTrends.grainsFor], so nothing measured here is work the product would
/// refuse to do.
List<DashboardWorkload> dashboardWorkloads() {
  final scope = ReportingScope(const {dashboardCcr, dashboardHki});

  // 31 March 2027: a financial year to date that is the whole financial year.
  final fullYear = _pair(
    DashboardPeriodKind.financialYearToDate,
    BusinessDate.of(2027, 3, 31),
  );
  // 17 September 2026: the ordinary mid-year case.
  final midYear = _pair(
    DashboardPeriodKind.financialYearToDate,
    BusinessDate.of(2026, 9, 17),
  );
  // 30 September 2026: a whole month to date, the busiest dashboard there is.
  final wholeMonth = _pair(
    DashboardPeriodKind.monthToDate,
    BusinessDate.of(2026, 9, 30),
  );
  final week = _pair(
    DashboardPeriodKind.weekToDate,
    BusinessDate.of(2026, 9, 17),
  );
  final custom365 = _custom(
    BusinessDate.of(2026, 4, 1),
    BusinessDate.of(2027, 3, 31),
  );
  final custom180 = _custom(
    BusinessDate.of(2026, 4, 1),
    BusinessDate.of(2026, 9, 27),
  );
  final custom31 = _custom(
    BusinessDate.of(2026, 9, 1),
    BusinessDate.of(2026, 10, 1),
  );

  return [
    DashboardWorkload(
      name: 'financial year to date, whole year, monthly x3, top 5',
      request: DashboardRequest(
        pair: fullYear,
        scope: scope,
        trends: const [_netMonthly, _costMonthly, _profitMonthly],
        topN: 5,
      ),
      // April to March is 12 buckets, shared by all three series, + current + comparison.
      expectedReads: 14,
      expectedTrendPoints: 36,
    ),
    DashboardWorkload(
      name: 'financial year to date, mid-year, monthly x3, top 5',
      request: DashboardRequest(
        pair: midYear,
        scope: scope,
        trends: const [_netMonthly, _costMonthly, _profitMonthly],
        topN: 5,
      ),
      expectedReads: 8,
      expectedTrendPoints: 18,
    ),
    DashboardWorkload(
      name: 'month to date, daily + weekly, ranked, top 5',
      request: DashboardRequest(
        pair: wholeMonth,
        scope: scope,
        trends: const [_netDaily, _netWeekly],
        rankDailyNetSales: true,
        topN: 5,
      ),
      // 30 days + 5 weeks + current + comparison; the ranking reuses the 30.
      expectedReads: 37,
      expectedTrendPoints: 35,
    ),
    DashboardWorkload(
      name: 'week to date, daily, ranked',
      request: DashboardRequest(
        pair: week,
        scope: scope,
        trends: const [_netDaily],
        rankDailyNetSales: true,
        topN: 5,
      ),
      expectedReads: 6,
      expectedTrendPoints: 4,
    ),
    DashboardWorkload(
      name: 'custom 365 days, monthly x3',
      request: DashboardRequest(
        pair: custom365,
        scope: scope,
        trends: const [_netMonthly, _costMonthly, _profitMonthly],
        topN: 5,
      ),
      expectedReads: 14,
      expectedTrendPoints: 36,
    ),
    DashboardWorkload(
      name: 'custom 180 days, weekly',
      request: DashboardRequest(
        pair: custom180,
        scope: scope,
        trends: const [_netWeekly],
        topN: 5,
      ),
      expectedReads: 28,
      expectedTrendPoints: 26,
    ),
    DashboardWorkload(
      name: 'custom 31 days, daily, ranked',
      request: DashboardRequest(
        pair: custom31,
        scope: scope,
        trends: const [_netDaily],
        rankDailyNetSales: true,
        topN: 5,
      ),
      expectedReads: 33,
      expectedTrendPoints: 31,
    ),
  ];
}
