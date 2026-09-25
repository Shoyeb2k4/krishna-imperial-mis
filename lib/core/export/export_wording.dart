/// The words every exported document uses (Phase 7 Slice 4; D-299, `ARCHITECTURE.md` §51).
///
/// One place, shared by the workbook and the PDF, so a workbook and a PDF of the same
/// report cannot describe a figure differently — D-232's rule for the two P&L surfaces,
/// applied to the two file formats. The figure labels are the screen's own words.
///
/// **Nothing here calculates.** A result word reads the sign of a figure somebody else
/// computed; an instant is turned into words in the zone it was handed. No clock is read.
library;

import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/core/formatting/report_dates.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

const exportProductName = 'Krishna Imperial MIS';

/// The report's title, as the Analytics workspace names it.
String exportReportTitle(ExportReport report) => switch (report) {
  ExportReport.profitAndLoss => 'Profit & Loss',
  ExportReport.revenueAnalysis => 'Revenue Analysis',
  ExportReport.expenseAnalysis => 'Expense & Department Analysis',
  ExportReport.businessComparison => 'Business Comparison',
};

// ── The basis every document states (spec §5.3, §10) ────────────────────────

String exportBasisLine(ExportDateBasis basis) => switch (basis) {
  ExportDateBasis.pnlDateAccrual =>
    'Accrual basis: each amount is placed by its P&L date.',
};

/// The basis as the page header states it, in few words.
String exportBasisShort(ExportDateBasis basis) => switch (basis) {
  ExportDateBasis.pnlDateAccrual => 'Accrual · P&L date',
};

const exportInclusionLine =
    'Includes only transactions the server has accepted; voided and unsynchronised '
    'entries are excluded. Expenses are the gross cost including GST.';

// ── Freshness: three statements, never merged (D-188, §51.6) ────────────────

/// The server-confirmed time the figures belong to — or a plain statement that there is
/// none. The generation time is never offered in its place.
String exportSynchronisedLine(ExportFreshness f) {
  final at = f.synchronisedAt;
  if (at == null) {
    return 'No synchronisation time is stated: these figures do not come from one '
        'synchronisation.';
  }
  return 'Synchronised as of ${reportInstantLabel(at, f.timeZoneId)}';
}

/// Only when a head check actually confirmed it; otherwise nothing is said.
String? exportServerNewerLine(ExportFreshness f) => f.serverHasNewer
    ? 'The server has newer changes than these figures. Refresh the report to '
          'include them.'
    : null;

String exportGeneratedLine(ExportFreshness f) =>
    'Generated on this device at '
    '${reportInstantLabel(f.generatedOnDeviceAt, f.timeZoneId)} (device clock)';

// ── Figure labels: the screen's words ───────────────────────────────────────

const exportGrossSalesLabel = 'Gross Sales';
const exportGstLabel = 'Less GST';
const exportNetSalesLabel = 'Net Sales';
const exportExpensesLabel = 'Less Expenses';
const exportMarginLabel = 'Operating Margin';
const exportNoGstLabel = 'No GST';
const exportNotApplicable = 'N/A';

/// "Operating Profit", or "Operating Loss" for a loss — the P&L screen's own label.
String exportOperatingLabel(Money operatingProfit) =>
    operatingProfit.isNegative ? 'Operating Loss' : 'Operating Profit';

/// A result stated in words beside its sign (spec §20). Break-even is its own word.
String exportResultWord(Money operatingProfit) => operatingProfit.isZero
    ? 'Break-even'
    : operatingProfit.isNegative
    ? 'Loss'
    : 'Profit';

const exportRevenueLinesHeading = 'Revenue by category';
const exportExpenseLinesHeading = 'Expenses by category';
const exportTotalLabel = 'Total';

/// "Page 2 of 5".
String exportPageLabel(int page, int pages) => 'Page $page of $pages';

const exportNoTradeLine = 'No accepted transactions in this period.';

const exportBreakdownNotShownLine =
    'Category lines are not shown: on this device they do not add up exactly to the '
    'totals. Refresh the report to synchronise again.';

const exportSplitNotShownLine =
    'The per-property statements are not shown: this consolidated result could not be '
    'split exactly by property. The consolidated total is complete.';

// ── Filenames (§51.5) ────────────────────────────────────────────────────────

/// How every exported file's name begins — and how the Android share cleanup recognises
/// this app's own files and nothing else.
const exportFileNamePrefix = 'KrishnaImperialMIS_';

/// `KrishnaImperialMIS_ProfitAndLoss_CrystalCanopyRooftop_2026-09-01_2026-09-30.xlsx`.
///
/// Readable names only — never an id. A consolidated document is named "Consolidated".
String exportFileName(ExportHeader header, {required String extension}) {
  final report = switch (header.report) {
    ExportReport.profitAndLoss => 'ProfitAndLoss',
    ExportReport.revenueAnalysis => 'RevenueAnalysis',
    ExportReport.expenseAnalysis => 'ExpenseAndDepartmentAnalysis',
    ExportReport.businessComparison => 'BusinessComparison',
  };
  final scope = header.consolidated
      ? 'Consolidated'
      : header.scopeLabel
            .split(RegExp('[^A-Za-z0-9]+'))
            .where((w) => w.isNotEmpty)
            .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
            .join();
  return '$exportFileNamePrefix${report}_${scope.isEmpty ? 'Scope' : scope}_'
      '${_iso(header.range.from)}_${_iso(header.range.to)}.$extension';
}

String _iso(BusinessDate d) => d.iso;

/// "1 Sep 2026 – 30 Sep 2026".
String exportRangeLabel(ReportRange range) => reportRangeLabel(range);

// ── The analysis exports (Slice 9): the Phase 6 sections' own sentences ──────
//
// Each mirrors the dashboard's wording (`dashboard_presentation.dart`), which a feature
// file owns and a layout here may not import. A test holds the two to the same words.

/// "Compared with 1 Aug 2026 – 19 Aug 2026" — the analysis sections' own line.
String exportComparedWithLine(DashboardPeriodPair pair) =>
    'Compared with ${reportRangeLabel(pair.comparison)}';

/// Why the comparator covers fewer days, when it does (D-251). Null otherwise.
String? exportCapNote(DashboardPeriodPair pair) => pair.comparisonCapped
    ? 'The previous period is shorter: '
          '${pair.comparison.days} days against ${pair.current.days}.'
    : null;

const exportThisPeriodLabel = 'This period';
const exportPreviousPeriodLabel = 'Previous period';
const exportChangeLabel = 'Change';
const exportChangePercentLabel = 'Change %';
const exportNoteLabel = 'Note';

/// Stands where a figure could not be established. It is never zero (D-163).
const exportNotAvailable = 'Not available';

/// Why there is no comparison at all, in the screen's words.
String exportNoComparisonLine(ComparisonSide side) => switch (side) {
  ComparisonSide.previous =>
    'No comparison — the previous period is not available.',
  ComparisonSide.current => 'No comparison — this period is not available.',
  ComparisonSide.both => 'No comparison — neither period is available.',
};

/// The rupee movement the domain computed: `+₹12,500.00`, `-₹1,200.00`, `₹0.00`.
String exportChangeText(MoneyComparisonAvailable c) =>
    MoneyFormatter.movement.format(c.change);

/// The percentage the domain produced, or "N/A" where it produced none (D-253, D-256).
String exportPercentText(MoneyComparisonAvailable c) =>
    c.percentChange.displayTwoDecimals;

/// Why there is no percentage, when there is none. Null when there is one.
String? exportPercentNote(MoneyComparisonAvailable c) =>
    switch (c.percentChange) {
      PercentChangeRatio() => null,
      PercentChangeNotApplicable(:final reason) => switch (reason) {
        PercentNotApplicableReason.previousZero =>
          'No percentage: the previous period was nil.',
        PercentNotApplicableReason.previousNegative =>
          'No percentage: the previous figure was below zero.',
        PercentNotApplicableReason.currentNegative =>
          "No percentage: this period's figure is below zero.",
        PercentNotApplicableReason.negativeSide =>
          'No percentage: a loss on one side.',
        PercentNotApplicableReason.signChanged =>
          c.transition.wording ?? 'No percentage: the sign changed.',
      },
    };

/// The name of a trended measure, as the charts print it.
String exportMeasureLabel(TrendMeasure measure) => switch (measure) {
  TrendMeasure.netSales => 'Net Sales',
  TrendMeasure.expenses => 'Expenses',
  TrendMeasure.operatingProfit => 'Operating Profit',
};

String exportGrainLabel(TrendGrain grain) => switch (grain) {
  TrendGrain.daily => 'daily',
  TrendGrain.weekly => 'weekly',
  TrendGrain.monthly => 'monthly',
};

/// "Net Sales · daily".
String exportTrendTitle(TrendSeries series) =>
    '${exportMeasureLabel(series.measure)} · ${exportGrainLabel(series.grain)}';

/// What one position on a trend is called — the dashboard's own labels. A clipped
/// bucket keeps the dates it actually covers (D-263).
String exportBucketLabel(TrendBucket bucket, TrendGrain grain) =>
    switch (grain) {
      TrendGrain.daily => reportDayLabel(bucket.range.from),
      TrendGrain.weekly => reportShortRangeLabel(bucket.range),
      TrendGrain.monthly =>
        bucket.partial
            ? reportShortRangeLabel(bucket.range)
            : reportMonthLabel(bucket.range.from),
    };

const exportPeriodColumnLabel = 'Period';

/// A clipped first or last bucket: its figure covers only its own dates, and is never
/// stretched to a notional whole week or month (D-263).
const exportPartialPeriodNote = 'Partial period: covers only these dates.';

/// A bucket whose figure could not be established. A gap, never zero (D-263).
const exportTrendGapNote =
    'No figure could be established for this period. It is not zero.';

/// Stated where the period offers no Net Sales trend (Today so far).
String exportNoNetSalesTrendLine(DashboardPeriodKind kind) =>
    '${kind.label} is a single business date, and one point is not a trend.';

/// Stated where the period offers no monthly expense trend (D-255, D-263).
String exportNoExpenseTrendLine(DashboardPeriodKind kind) =>
    'Operating Expenses are trended by month only, because accrual dating makes a daily '
    'or weekly expense figure misleading. ${kind.label} covers fewer than two months, so '
    'there is one monthly point and no trend to draw.';

const exportRevenueMixHeading = 'Revenue mix by category (Net Sales)';
const exportTopExpenseCategoriesHeading = 'Top expense categories';
const exportDepartmentSpendingHeading = 'Department spending';
const exportComparedFiguresHeading = 'Against the same stretch before';
const exportTrendHeading = 'Trend';

/// "Others (3 categories)" — the chart's own label for the exact remainder (D-258).
String exportOthersLabel(int count) =>
    count == 1 ? 'Others (1 category)' : 'Others ($count categories)';

/// Why a ranked set is not shown: its lines do not add up to its total (D-258).
String exportRankingRefusedLine(TopNRefusal reason) => switch (reason) {
  TopNRefusal.doesNotReconcile =>
    'Not shown: the lines do not add up exactly to the total on this device. Refresh '
        'the report to synchronise again.',
};

/// Business Comparison: the fixed order, stated (D-278).
const exportComparisonOrderNote =
    'Properties are listed in a fixed order, not by result. The figures are stated side by '
    'side; neither property is placed above the other.';

const exportFigureColumnLabel = 'Figure';
const exportCategoryColumnLabel = 'Category';
const exportAmountLabel = 'Amount';
const exportDepartmentColumnLabel = 'Department';
const exportOperatingProfitOrLossLabel = 'Operating Profit / Loss';
const exportOperatingExpensesLabel = 'Operating Expenses';
const exportResultLabel = 'Result';
