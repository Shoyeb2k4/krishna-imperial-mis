/// The export document models (Phase 7 Slice 3; D-299, `ARCHITECTURE.md` §51.4).
///
/// One immutable model per exportable report. A model **copies** figures out of the
/// canonical result the corresponding screen already reads — a [PnlResult], a
/// [PnlComparison], a [TrendSeries], a [TopNOutcome], a [PropertyComparisonReady] — and
/// labels resolved from the cached masters. It derives nothing: no P&L, no GST, no
/// category total, no margin, no comparison, no reconciliation. The PDF renderer and the
/// XLSX writer lay these out and do nothing else, so the screen, the workbook and the PDF
/// cannot disagree about a figure (spec §21.3).
///
/// A refusal stays a refusal. A withheld comparison is carried as the domain's own
/// [MoneyComparisonUnavailable], a missing trend bucket as a [TrendGap], a set that did
/// not reconcile as a refused ranking. Nothing here turns any of them into ₹0 (D-163).
///
/// **What never appears in a model:** internal identifiers of any kind (database ids,
/// snapshot ids, change sequences), capability codes, cache metadata or paths. Business
/// unit ids are used only to look labels up and to check that a permit matches its
/// report; they are not stored on any model (§51.8).
library;

import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

// ── Freshness: three statements, never merged (D-188, D-299) ───────────────

/// How current the exported figures are, and when the file was made.
///
/// The three are deliberately separate fields. [generatedOnDeviceAt] is this device's
/// clock and says only when the file was produced; it is never shown as, or mistaken for,
/// the server-confirmed [synchronisedAt].
final class ExportFreshness {
  const ExportFreshness._({
    required this.generatedOnDeviceAt,
    required this.synchronisedAt,
    required this.serverHasNewer,
    required this.timeZoneId,
  });

  /// From the report's own freshness claim — or none, when it could make none.
  factory ExportFreshness.of(
    ReportingFreshness? freshness, {
    required DateTime generatedOnDeviceAt,
    required String timeZoneId,
  }) => ExportFreshness._(
    generatedOnDeviceAt: generatedOnDeviceAt,
    synchronisedAt: freshness?.synchronisedAt,
    serverHasNewer: freshness?.state == ReportingFreshnessState.serverHasNewer,
    timeZoneId: timeZoneId,
  );

  /// The device clock, when the document was generated. Always present, always labelled
  /// as the device's.
  final DateTime generatedOnDeviceAt;

  /// The server-confirmed time of the snapshot the figures belong to, or **null** when the
  /// report could make no freshness claim. Null is not a time and is never printed as one.
  final DateTime? synchronisedAt;

  /// True only when a head check actually confirmed the server has moved on.
  final bool serverHasNewer;

  /// The zone instants are displayed in: display only, nothing is derived from it.
  final String timeZoneId;
}

// ── What every document states ─────────────────────────────────────────────

/// The basis of every exported figure (spec §5.3, §10).
///
/// There is exactly one in V1: accrual, by P&L date, server-accepted non-voided
/// transactions only, expenses at gross cost including GST. It is carried rather than
/// assumed so a renderer states it on every document.
enum ExportDateBasis { pnlDateAccrual }

/// The heading block every document carries.
final class ExportHeader {
  const ExportHeader({
    required this.report,
    required this.scopeLabel,
    required this.consolidated,
    required this.range,
    required this.periodName,
    required this.freshness,
    this.dateBasis = ExportDateBasis.pnlDateAccrual,
  });

  final ExportReport report;

  /// A property's name, or the consolidated scope's wording. Never an id.
  final String scopeLabel;
  final bool consolidated;

  /// The exact inclusive P&L-date range the figures cover.
  final ReportRange range;

  /// How the reader chose it — "This month", "Month to date", "Custom" and so on.
  final String periodName;

  final ExportFreshness freshness;
  final ExportDateBasis dateBasis;
}

/// Labels for the ids a canonical result carries, resolved from the cached masters.
///
/// The implementation lives with the surfaces (they own the master graph and the fallback
/// wording the screen uses); the models only ask. A label is always a string: a master
/// this device does not hold is described in words, never exported as its id.
abstract interface class ExportLabels {
  String businessUnit(String businessUnitId);
  String revenueCategory(String revenueCategoryId);
  String expenseCategory(String? categoryId);
  String department(String? departmentId);
  String section(String? sectionId);

  /// A property's name for one property; the consolidated wording otherwise.
  String scope(ExportScope scope);
}

/// The root of every export document.
sealed class ExportDocument {
  const ExportDocument(this.header);
  final ExportHeader header;
}

// ── Profit & Loss (spec §10) ────────────────────────────────────────────────

/// One revenue category line, as the P&L screen shows it.
final class PnlExportRevenueLine {
  const PnlExportRevenueLine({
    required this.propertyLabel,
    required this.categoryLabel,
    required this.noGst,
    required this.gross,
    required this.gst,
    required this.net,
  });

  /// The property, shown in a consolidated total section only; null otherwise.
  final String? propertyLabel;
  final String categoryLabel;

  /// The category's treatment is `none` — "No GST", distinct from a configured 0%.
  final bool noGst;
  final Money gross;
  final Money gst;
  final Money net;
}

/// One expense category line, as the P&L screen shows it.
final class PnlExportExpenseLine {
  const PnlExportExpenseLine({
    required this.propertyLabel,
    required this.departmentLabel,
    required this.sectionLabel,
    required this.categoryLabel,
    required this.amount,
  });

  final String? propertyLabel;
  final String departmentLabel;
  final String sectionLabel;
  final String categoryLabel;
  final Money amount;
}

/// One P&L statement: one property's, or the consolidated total.
///
/// The category lines are present only when the domain confirmed they reconcile exactly to
/// the headline (`PnlResult.breakdownReconciles`); otherwise they are **absent**, and the
/// renderer says so, exactly as the screen does. The totals under the lines are the
/// headline figures, never a sum of the lines.
final class PnlExportStatement {
  const PnlExportStatement({
    required this.title,
    required this.isConsolidatedTotal,
    required this.grossSales,
    required this.gst,
    required this.netSales,
    required this.expenses,
    required this.operatingProfit,
    required this.margin,
    required this.hasTrade,
    required this.revenueLines,
    required this.expenseLines,
  });

  final String title;
  final bool isConsolidatedTotal;

  final Money grossSales;
  final Money gst;
  final Money netSales;
  final Money expenses;

  /// Negative when the property lost money. Stated in words by the renderer.
  final Money operatingProfit;

  /// Exact; [MarginNotApplicable] when net sales are zero.
  final OperatingMargin margin;

  /// Whether any accepted transaction contributed — a real ₹0 is not "no trade".
  final bool hasTrade;

  /// Null when the breakdown does not reconcile, and is therefore not shown.
  final List<PnlExportRevenueLine>? revenueLines;
  final List<PnlExportExpenseLine>? expenseLines;

  bool get breakdownShown => revenueLines != null && expenseLines != null;
}

/// The Profit & Loss export.
///
/// One property: one statement. Consolidated: one statement per property, then the
/// consolidated total — the report shape of spec §10 — when the domain could split it
/// (`PropertyComparison`); otherwise the consolidated total alone.
final class PnlExportDocument extends ExportDocument {
  const PnlExportDocument({
    required ExportHeader header,
    required this.statements,
    required this.propertySplitShown,
  }) : super(header);

  final List<PnlExportStatement> statements;

  /// False when a consolidated P&L could not be split by property, so only the total is
  /// present. Always true for a one-property report.
  final bool propertySplitShown;

  /// The statement for the whole scope: the one property's, or the consolidated total.
  ///
  /// The builders always place it last — after the per-property statements, when there
  /// are any — so this names a position, and decides nothing.
  PnlExportStatement get scopeStatement => statements.last;
}

// ── The analysis exports (Phase 6 sections, D-290) ─────────────────────────

/// A figure for the period, beside its comparison with the same stretch before (D-251).
final class ExportComparedFigure {
  const ExportComparedFigure({required this.current, required this.comparison});

  /// This period's canonical figure.
  final Money current;

  /// The domain's comparison, carried whole: available with its movement and
  /// percentage, or unavailable with its reason. Never a zero standing in for either.
  final MoneyComparison comparison;
}

/// One ranked row, labelled.
final class ExportRankedRow {
  const ExportRankedRow({required this.label, required this.amount});
  final String label;
  final Money amount;
}

/// A ranked set as the domain grouped it (D-258): the top lines, and an exact Others.
sealed class ExportRanking {
  const ExportRanking();
}

final class ExportRankingRefused extends ExportRanking {
  const ExportRankingRefused(this.reason);
  final TopNRefusal reason;
}

final class ExportRankingGrouped extends ExportRanking {
  const ExportRankingGrouped({
    required this.rows,
    required this.others,
    required this.othersCount,
    required this.total,
  });

  /// In the domain's ranked order.
  final List<ExportRankedRow> rows;

  /// The exact remainder the domain computed, or null when nothing was left over.
  final Money? others;
  final int othersCount;

  /// The headline figure the set reconciled to.
  final Money total;
}

/// The Revenue Analysis export — what the Revenue Analysis section shows.
final class RevenueAnalysisExportDocument extends ExportDocument {
  const RevenueAnalysisExportDocument({
    required ExportHeader header,
    required this.pair,
    required this.grossSales,
    required this.gst,
    required this.netSales,
    required this.netSalesTrend,
    required this.revenueMix,
  }) : super(header);

  /// The period and the stretch it is compared with.
  final DashboardPeriodPair pair;

  final ExportComparedFigure grossSales;
  final ExportComparedFigure gst;
  final ExportComparedFigure netSales;

  /// The Net Sales trend at the planner's grain, or null when the period offers none.
  final TrendSeries? netSalesTrend;

  /// The revenue mix by category, or null when the view carried none.
  final ExportRanking? revenueMix;
}

/// The Expense & Department Analysis export — what that section shows.
final class ExpenseAnalysisExportDocument extends ExportDocument {
  const ExpenseAnalysisExportDocument({
    required ExportHeader header,
    required this.pair,
    required this.expenses,
    required this.monthlyExpenseTrend,
    required this.topExpenseCategories,
    required this.departmentSpending,
  }) : super(header);

  final DashboardPeriodPair pair;
  final ExportComparedFigure expenses;

  /// Monthly only (D-255); null when the period offers no monthly trend.
  final TrendSeries? monthlyExpenseTrend;

  final ExportRanking? topExpenseCategories;
  final ExportRanking? departmentSpending;
}

/// One column of the Business Comparison table.
final class BusinessComparisonExportColumn {
  const BusinessComparisonExportColumn({
    required this.label,
    required this.isTotal,
    required this.netSales,
    required this.expenses,
    required this.operatingProfit,
    required this.margin,
  });

  final String label;
  final bool isTotal;
  final Money netSales;
  final Money expenses;
  final Money operatingProfit;
  final OperatingMargin margin;
}

/// The Business Comparison export: each property, then both together (D-278).
///
/// Properties in the domain's id order — never ranked, and no property is called a
/// winner.
final class BusinessComparisonExportDocument extends ExportDocument {
  const BusinessComparisonExportDocument({
    required ExportHeader header,
    required this.pair,
    required this.columns,
  }) : super(header);

  final DashboardPeriodPair pair;
  final List<BusinessComparisonExportColumn> columns;
}
