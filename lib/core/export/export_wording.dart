/// The words every exported document uses (Phase 7 Slice 4; D-299, `ARCHITECTURE.md` §51).
///
/// One place, shared by the workbook and the PDF, so a workbook and a PDF of the same
/// report cannot describe a figure differently — D-232's rule for the two P&L surfaces,
/// applied to the two file formats. The figure labels are the screen's own words.
///
/// **Nothing here calculates.** A result word reads the sign of a figure somebody else
/// computed; an instant is turned into words in the zone it was handed. No clock is read.
library;

import 'package:krishna_mis/core/formatting/report_dates.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
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

const exportNoTradeLine = 'No accepted transactions in this period.';

const exportBreakdownNotShownLine =
    'Category lines are not shown: on this device they do not add up exactly to the '
    'totals. Refresh the report to synchronise again.';

const exportSplitNotShownLine =
    'The per-property statements are not shown: this consolidated result could not be '
    'split exactly by property. The consolidated total is complete.';

// ── Filenames (§51.5) ────────────────────────────────────────────────────────

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
  return 'KrishnaImperialMIS_${report}_${scope.isEmpty ? 'Scope' : scope}_'
      '${_iso(header.range.from)}_${_iso(header.range.to)}.$extension';
}

String _iso(BusinessDate d) => d.iso;

/// "1 Sep 2026 – 30 Sep 2026".
String exportRangeLabel(ReportRange range) => reportRangeLabel(range);
