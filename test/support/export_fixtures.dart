/// Canonical fixtures for the Phase 7 export tests (Slices 3–5).
///
/// Every result here is produced by the one canonical calculator, [Pnl.compute], or by the
/// domain's own split, comparison, trend and ranking functions — never assembled by hand
/// with figures the domain did not compute. The export layers are then checked against
/// these same objects, which is what spec §21.3's parity means for an export.
library;

import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/export/export_builders.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

// Deliberately id-shaped, so a test can prove none of them reaches a document.
const fxCcr = 'unit-0f3a9c2e-ccr';
const fxHki = 'unit-7b1d44a0-hki';

Money fxP(int paise) => Money.fromPaise(paise);

ReportRange fxRange(BusinessDate from, BusinessDate to) =>
    switch (CustomRangePeriod(from: from, to: to).resolve()) {
      ReportRangeResolved(:final range) => range,
      _ => throw StateError('range'),
    };

final fxSeptember = fxRange(
  BusinessDate.of(2026, 9, 1),
  BusinessDate.of(2026, 9, 19),
);
final fxAugust = fxRange(
  BusinessDate.of(2026, 8, 1),
  BusinessDate.of(2026, 8, 19),
);

RevenueCategoryLine fxRevenue(
  String unit,
  String category, {
  required int gross,
  required int tax,
  TaxTreatment? treatment = TaxTreatment.inclusive,
}) => RevenueCategoryLine(
  businessUnitId: unit,
  revenueCategoryId: category,
  treatment: treatment,
  totals: RevenueTotals(
    gross: fxP(gross),
    tax: fxP(tax),
    net: fxP(gross - tax),
    contributions: 1,
  ),
);

ExpenseHierarchyLine fxExpense(String unit, String category, int amount) =>
    ExpenseHierarchyLine(
      businessUnitId: unit,
      departmentId: '$unit-dept-$category',
      sectionId: '$unit-section-$category',
      categoryId: '$unit-cat-$category',
      totals: ExpenseTotals(amount: fxP(amount), contributions: 1),
    );

/// A result from the canonical calculator. The headline sides are handed to it as the
/// sums an engine would have returned for these lines (`side` overrides one for a
/// deliberately non-reconciling fixture).
PnlResult fxResult({
  required ReportRange range,
  required List<RevenueCategoryLine> revenue,
  required List<ExpenseHierarchyLine> expenses,
  String? businessUnitId,
  RevenueTotals? revenueSide,
}) {
  final outcome = Pnl.compute(
    period: CustomRangePeriod(from: range.from, to: range.to),
    businessUnitId: businessUnitId,
    revenue: SideAvailable(
      revenueSide ??
          revenue.fold(RevenueTotals.zero, (sum, l) => sum + l.totals),
    ),
    expenses: SideAvailable(
      expenses.fold(ExpenseTotals.zero, (sum, l) => sum + l.totals),
    ),
    revenueByCategory: revenue,
    expenseByHierarchy: expenses,
  );
  return (outcome as PnlComputed).result;
}

/// Crystal Canopy on its own, with a Banquet-style untaxed line and a loss-free month.
PnlResult fxCcrSeptember() => fxResult(
  range: fxSeptember,
  businessUnitId: fxCcr,
  revenue: [
    fxRevenue(fxCcr, 'restaurant', gross: 12364200, tax: 588771),
    fxRevenue(fxCcr, 'nandbhog', gross: 870000, tax: 41429),
  ],
  expenses: [
    fxExpense(fxCcr, 'kirana', 9420343),
    fxExpense(fxCcr, 'water', 120000),
  ],
);

List<RevenueCategoryLine> fxConsolidatedRevenue() => [
  fxRevenue(fxCcr, 'restaurant', gross: 12364200, tax: 588771),
  fxRevenue(fxCcr, 'nandbhog', gross: 870000, tax: 41429),
  fxRevenue(
    fxHki,
    'banquet',
    gross: 4034300,
    tax: 0,
    treatment: TaxTreatment.none,
  ),
  fxRevenue(fxHki, 'room', gross: 5200000, tax: 247619),
];

List<ExpenseHierarchyLine> fxConsolidatedExpenses() => [
  fxExpense(fxCcr, 'kirana', 9420343),
  fxExpense(fxCcr, 'water', 120000),
  // Hotel Krishna loses money this month: a negative Operating Profit must survive.
  fxExpense(fxHki, 'electricity', 9500000),
  fxExpense(fxHki, 'diesel', 1234567),
];

PnlResult fxConsolidated({ReportRange? range}) => fxResult(
  range: range ?? fxSeptember,
  revenue: fxConsolidatedRevenue(),
  expenses: fxConsolidatedExpenses(),
);

PnlResult fxConsolidatedAugust() => fxResult(
  range: fxAugust,
  revenue: [
    fxRevenue(fxCcr, 'restaurant', gross: 10000000, tax: 476190),
    fxRevenue(fxHki, 'room', gross: 4000000, tax: 190476),
  ],
  expenses: [fxExpense(fxCcr, 'kirana', 8000000)],
);

final fxPair = DashboardPeriodPair.forTesting(
  current: fxSeptember,
  comparison: fxAugust,
  comparisonCapped: false,
  kind: DashboardPeriodKind.monthToDate,
);

PnlComparison fxComparison({PnlOutcome? current, PnlOutcome? previous}) =>
    PnlComparison.compare(
      pair: fxPair,
      current: current ?? PnlComputed(fxConsolidated()),
      previous: previous ?? PnlComputed(fxConsolidatedAugust()),
    );

/// A daily Net Sales trend over three days with one bucket that could not be established.
TrendSeries fxNetSalesTrendWithGap() {
  final range = fxRange(
    BusinessDate.of(2026, 9, 1),
    BusinessDate.of(2026, 9, 3),
  );
  final buckets = DashboardTrends.buckets(
    range,
    TrendGrain.daily,
    measure: TrendMeasure.netSales,
  );
  PnlOutcome day(TrendBucket b, int gross) => PnlComputed(
    fxResult(
      range: b.range,
      revenue: [fxRevenue(fxCcr, 'restaurant', gross: gross, tax: 0)],
      expenses: const [],
    ),
  );
  return DashboardTrends.series(
    measure: TrendMeasure.netSales,
    grain: TrendGrain.daily,
    buckets: buckets,
    outcomes: [
      day(buckets[0], 150000),
      const PnlRefused(PnlRefusal.revenueUnavailable),
      day(buckets[2], 0),
    ],
  );
}

/// A monthly expense trend over August and September.
TrendSeries fxMonthlyExpenseTrend() {
  final range = fxRange(
    BusinessDate.of(2026, 8, 1),
    BusinessDate.of(2026, 9, 19),
  );
  final buckets = DashboardTrends.buckets(
    range,
    TrendGrain.monthly,
    measure: TrendMeasure.expenses,
  );
  return DashboardTrends.series(
    measure: TrendMeasure.expenses,
    grain: TrendGrain.monthly,
    buckets: buckets,
    outcomes: [
      for (final (i, b) in buckets.indexed)
        PnlComputed(
          fxResult(
            range: b.range,
            revenue: const [],
            expenses: [fxExpense(fxCcr, 'kirana', 100000 * (i + 1))],
          ),
        ),
    ],
  );
}

PropertyComparisonOutcome fxSplit() => PropertyComparison.of(fxConsolidated());

/// Labels that are obviously not ids, keyed by the fixture ids.
final class FxLabels implements ExportLabels {
  const FxLabels();

  static const names = {
    fxCcr: 'Crystal Canopy Rooftop',
    fxHki: 'Hotel Krishna Imperial',
  };

  String _tail(String? id) => (id ?? '').split('-').last;

  String _title(String s) =>
      s.isEmpty ? 'Unassigned' : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  String businessUnit(String businessUnitId) =>
      names[businessUnitId] ?? 'Property not on this device';

  @override
  String revenueCategory(String revenueCategoryId) => _title(revenueCategoryId);

  @override
  String expenseCategory(String? categoryId) => _title(_tail(categoryId));

  @override
  String department(String? departmentId) =>
      '${_title(_tail(departmentId))} dept';

  @override
  String section(String? sectionId) => '${_title(_tail(sectionId))} section';

  @override
  String scope(ExportScope scope) => scope.isConsolidated
      ? 'Both properties (consolidated)'
      : businessUnit(scope.businessUnitIds.single);
}

/// The Owner bundle, unscoped — permitted everything.
final fxOwner = Principal(
  userId: 'user-5d2c8e11-owner',
  grants: [for (final c in RoleTemplates.owner) CapabilityGrant(c)],
);

ExportPermitted fxPermit(
  ExportReport report,
  ExportScope scope, {
  ExportAction action = ExportAction.export,
}) =>
    ExportAuthority.decide(
          fxOwner,
          action: action,
          report: report,
          scope: scope,
        )
        as ExportPermitted;

final fxBoth = ExportScope({fxCcr, fxHki});

final fxGeneratedAt = DateTime.utc(2026, 9, 19, 12, 30);
final fxSynchronisedAt = DateTime.utc(2026, 9, 19, 6, 0);

ReportingFreshness fxFreshness({bool serverHasNewer = false}) {
  final fresh = ReportingFreshness.synchronised(
    ReportingSnapshotEvidence(
      snapshotId: 'snapshot-91ac77:secret',
      serverConfirmedAt: fxSynchronisedAt,
    ),
  );
  return serverHasNewer ? fresh.asServerHasNewer() : fresh;
}

ExportContext fxContext(
  ExportPermitted permit, {
  ReportingFreshness? freshness,
  String periodName = 'Month to date',
}) => ExportContext(
  permit: permit,
  labels: const FxLabels(),
  periodName: periodName,
  generatedOnDeviceAt: fxGeneratedAt,
  timeZoneId: 'Asia/Kolkata',
  freshness: freshness,
);

/// Every string a document carries, gathered by walking its fields — so a test can prove
/// no internal id reached it (§51.8).
List<String> fxDocumentStrings(ExportDocument document) {
  final h = document.header;
  final out = <String>[h.scopeLabel, h.periodName, h.freshness.timeZoneId];
  void ranking(ExportRanking? r) {
    if (r is ExportRankingGrouped) out.addAll(r.rows.map((row) => row.label));
  }

  switch (document) {
    case PnlExportDocument(:final statements):
      for (final s in statements) {
        out.add(s.title);
        for (final l in s.revenueLines ?? const <PnlExportRevenueLine>[]) {
          out.addAll([?l.propertyLabel, l.categoryLabel]);
        }
        for (final l in s.expenseLines ?? const <PnlExportExpenseLine>[]) {
          out.addAll([
            ?l.propertyLabel,
            l.departmentLabel,
            l.sectionLabel,
            l.categoryLabel,
          ]);
        }
      }
    case RevenueAnalysisExportDocument(:final revenueMix):
      ranking(revenueMix);
    case ExpenseAnalysisExportDocument(
      :final topExpenseCategories,
      :final departmentSpending,
    ):
      ranking(topExpenseCategories);
      ranking(departmentSpending);
    case BusinessComparisonExportDocument(:final columns):
      out.addAll(columns.map((c) => c.label));
  }
  return out;
}

/// Everything id-shaped the fixtures use. None of it may appear in a document.
const fxForbidden = [
  fxCcr,
  fxHki,
  '0f3a9c2e',
  '7b1d44a0',
  'snapshot-91ac77',
  'user-5d2c8e11',
  'reports.export',
  'reports.view',
];
