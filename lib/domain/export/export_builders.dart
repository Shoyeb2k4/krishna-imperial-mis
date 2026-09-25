/// Building the export documents from canonical results (Phase 7 Slice 3; D-299).
///
/// **Every builder requires an [ExportPermitted].** Only [ExportAuthority.decide] can make
/// one, so no document exists unless the export or print was permitted for that report
/// and scope first (§51.3) — and a permit issued for a different report or scope is
/// refused here rather than trusted.
///
/// **Every builder copies.** The figures are fields of the canonical result the screen
/// read; the labels come from [ExportLabels]; the order is the screen's
/// ([PnlLineOrder], the domain's own ranking). One call is made into `domain/finance`:
/// [PropertyComparison.of], the canonical per-property split (D-270), to lay out a
/// consolidated P&L in the shape of spec §10. It is the same function that produces the
/// Business Comparison the screen shows; nothing here re-implements it.
///
/// A builder never reads storage, a clock, the network or a session: the caller hands it
/// the result, the freshness and the device's generation time.
library;

import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/pnl_line_order.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';

/// Why a document was not built.
enum ExportBuildRefusal {
  /// The permit was issued for a different report.
  permitForAnotherReport,

  /// The permit's scope is not the scope the result covers.
  permitForAnotherScope,

  /// The comparison was made for a different range from the result's.
  comparisonForAnotherRange,

  /// Business Comparison: the domain could not split the result by property.
  propertySplitUnavailable,
}

sealed class ExportBuild<D extends ExportDocument> {
  const ExportBuild();
}

final class ExportBuilt<D extends ExportDocument> extends ExportBuild<D> {
  const ExportBuilt(this.document);
  final D document;
}

final class ExportNotBuilt<D extends ExportDocument> extends ExportBuild<D> {
  const ExportNotBuilt(this.reason);
  final ExportBuildRefusal reason;
}

/// What every builder needs besides the canonical result.
final class ExportContext {
  const ExportContext({
    required this.permit,
    required this.labels,
    required this.periodName,
    required this.generatedOnDeviceAt,
    required this.timeZoneId,
    required this.freshness,
  });

  final ExportPermitted permit;
  final ExportLabels labels;
  final String periodName;

  /// The device clock at generation. The builder reads no clock of its own.
  final DateTime generatedOnDeviceAt;
  final String timeZoneId;

  /// The report's own freshness claim, or null when it could make none.
  final ReportingFreshness? freshness;
}

abstract final class ExportDocuments {
  // ── Profit & Loss ─────────────────────────────────────────────────────────

  static ExportBuild<PnlExportDocument> profitAndLoss(
    ExportContext context,
    PnlResult result,
  ) {
    final refusal = _checkPermit(
      context.permit,
      ExportReport.profitAndLoss,
      result,
    );
    if (refusal != null) return ExportNotBuilt(refusal);

    final labels = context.labels;
    final List<PnlExportStatement> statements;
    final bool splitShown;
    if (result.isConsolidated) {
      switch (PropertyComparison.of(result)) {
        case PropertyComparisonReady(:final properties):
          statements = [
            for (final p in properties)
              _statement(
                p.result,
                labels,
                title: labels.businessUnit(p.businessUnitId),
                isTotal: false,
                showProperty: false,
              ),
            _statement(
              result,
              labels,
              title: labels.scope(context.permit.scope),
              isTotal: true,
              showProperty: true,
            ),
          ];
          splitShown = true;
        case PropertyComparisonRefused():
          statements = [
            _statement(
              result,
              labels,
              title: labels.scope(context.permit.scope),
              isTotal: true,
              showProperty: true,
            ),
          ];
          splitShown = false;
      }
    } else {
      statements = [
        _statement(
          result,
          labels,
          title: labels.businessUnit(result.businessUnitId!),
          isTotal: false,
          showProperty: false,
        ),
      ];
      splitShown = true;
    }

    return ExportBuilt(
      PnlExportDocument(
        header: _header(context, result),
        statements: List.unmodifiable(statements),
        propertySplitShown: splitShown,
      ),
    );
  }

  static PnlExportStatement _statement(
    PnlResult result,
    ExportLabels labels, {
    required String title,
    required bool isTotal,
    required bool showProperty,
  }) {
    final shown = result.breakdownReconciles;
    return PnlExportStatement(
      title: title,
      isConsolidatedTotal: isTotal,
      grossSales: result.grossSales,
      gst: result.gst,
      netSales: result.netSales,
      expenses: result.expenses,
      operatingProfit: result.operatingProfit,
      margin: result.margin,
      hasTrade:
          result.revenueContributions > 0 || result.expenseContributions > 0,
      revenueLines: shown
          ? List.unmodifiable([
              for (final line in PnlLineOrder.revenue(result))
                PnlExportRevenueLine(
                  propertyLabel: showProperty
                      ? labels.businessUnit(line.businessUnitId)
                      : null,
                  categoryLabel: labels.revenueCategory(line.revenueCategoryId),
                  noGst: line.treatment == TaxTreatment.none,
                  gross: line.totals.gross,
                  gst: line.totals.tax,
                  net: line.totals.net,
                ),
            ])
          : null,
      expenseLines: shown
          ? List.unmodifiable([
              for (final line in PnlLineOrder.expenses(result))
                PnlExportExpenseLine(
                  propertyLabel: showProperty
                      ? labels.businessUnit(line.businessUnitId)
                      : null,
                  departmentLabel: labels.department(line.departmentId),
                  sectionLabel: labels.section(line.sectionId),
                  categoryLabel: labels.expenseCategory(line.categoryId),
                  amount: line.totals.amount,
                ),
            ])
          : null,
    );
  }

  // ── Revenue Analysis ──────────────────────────────────────────────────────

  static ExportBuild<RevenueAnalysisExportDocument> revenueAnalysis(
    ExportContext context, {
    required PnlResult result,
    required PnlComparison comparison,
    required List<TrendSeries> trends,
    required TopNOutcome<RevenueCategoryLine>? revenueMix,
  }) {
    final refusal =
        _checkPermit(context.permit, ExportReport.revenueAnalysis, result) ??
        _checkComparison(comparison, result);
    if (refusal != null) return ExportNotBuilt(refusal);

    TrendSeries? netSalesTrend;
    for (final series in trends) {
      if (series.measure == TrendMeasure.netSales) {
        netSalesTrend = series;
        break;
      }
    }

    final labels = context.labels;
    return ExportBuilt(
      RevenueAnalysisExportDocument(
        header: _header(context, result),
        pair: comparison.pair,
        grossSales: ExportComparedFigure(
          current: result.grossSales,
          comparison: comparison.grossSales,
        ),
        gst: ExportComparedFigure(
          current: result.gst,
          comparison: comparison.gst,
        ),
        netSales: ExportComparedFigure(
          current: result.netSales,
          comparison: comparison.netSales,
        ),
        netSalesTrend: netSalesTrend,
        revenueMix: revenueMix == null
            ? null
            : _ranking(
                revenueMix,
                (line) => _prefixed(
                  result,
                  labels,
                  line.businessUnitId,
                  labels.revenueCategory(line.revenueCategoryId),
                ),
              ),
      ),
    );
  }

  // ── Expense & Department Analysis ────────────────────────────────────────

  static ExportBuild<ExpenseAnalysisExportDocument> expenseAnalysis(
    ExportContext context, {
    required PnlResult result,
    required PnlComparison comparison,
    required List<TrendSeries> trends,
    required TopNOutcome<ExpenseHierarchyLine>? topExpenseCategories,
    required TopNOutcome<ExpenseHierarchyLine>? departmentSpending,
  }) {
    final refusal =
        _checkPermit(context.permit, ExportReport.expenseAnalysis, result) ??
        _checkComparison(comparison, result);
    if (refusal != null) return ExportNotBuilt(refusal);

    // Monthly only (D-255): a daily or weekly expense series is not an export either.
    TrendSeries? monthly;
    for (final series in trends) {
      if (series.measure == TrendMeasure.expenses &&
          series.grain == TrendGrain.monthly) {
        monthly = series;
        break;
      }
    }

    final labels = context.labels;
    return ExportBuilt(
      ExpenseAnalysisExportDocument(
        header: _header(context, result),
        pair: comparison.pair,
        expenses: ExportComparedFigure(
          current: result.expenses,
          comparison: comparison.expenses,
        ),
        monthlyExpenseTrend: monthly,
        topExpenseCategories: topExpenseCategories == null
            ? null
            : _ranking(
                topExpenseCategories,
                (line) => _prefixed(
                  result,
                  labels,
                  line.businessUnitId,
                  labels.expenseCategory(line.categoryId),
                ),
              ),
        departmentSpending: departmentSpending == null
            ? null
            : _ranking(
                departmentSpending,
                (line) => _prefixed(
                  result,
                  labels,
                  line.businessUnitId,
                  labels.department(line.departmentId),
                ),
              ),
      ),
    );
  }

  // ── Business Comparison ───────────────────────────────────────────────────

  static ExportBuild<BusinessComparisonExportDocument> businessComparison(
    ExportContext context, {
    required PnlResult result,
    required PnlComparison comparison,
    required PropertyComparisonOutcome? propertyComparison,
  }) {
    final refusal =
        _checkPermit(context.permit, ExportReport.businessComparison, result) ??
        _checkComparison(comparison, result);
    if (refusal != null) return ExportNotBuilt(refusal);
    if (propertyComparison is! PropertyComparisonReady ||
        propertyComparison.total.range != result.range) {
      return const ExportNotBuilt(ExportBuildRefusal.propertySplitUnavailable);
    }

    final labels = context.labels;
    final total = propertyComparison.total;
    return ExportBuilt(
      BusinessComparisonExportDocument(
        header: _header(context, result),
        pair: comparison.pair,
        columns: List.unmodifiable([
          for (final p in propertyComparison.properties)
            BusinessComparisonExportColumn(
              label: labels.businessUnit(p.businessUnitId),
              isTotal: false,
              netSales: p.result.netSales,
              expenses: p.result.expenses,
              operatingProfit: p.result.operatingProfit,
              margin: p.result.margin,
            ),
          BusinessComparisonExportColumn(
            label: labels.scope(context.permit.scope),
            isTotal: true,
            netSales: total.netSales,
            expenses: total.expenses,
            operatingProfit: total.operatingProfit,
            margin: total.margin,
          ),
        ]),
      ),
    );
  }

  // ── Shared ────────────────────────────────────────────────────────────────

  static ExportHeader _header(ExportContext context, PnlResult result) =>
      ExportHeader(
        report: context.permit.report,
        scopeLabel: context.labels.scope(context.permit.scope),
        consolidated: context.permit.scope.isConsolidated,
        range: result.range,
        periodName: context.periodName,
        freshness: ExportFreshness.of(
          context.freshness,
          generatedOnDeviceAt: context.generatedOnDeviceAt,
          timeZoneId: context.timeZoneId,
        ),
      );

  /// The permit must be for this report and exactly this result's scope.
  static ExportBuildRefusal? _checkPermit(
    ExportPermitted permit,
    ExportReport report,
    PnlResult result,
  ) {
    if (permit.report != report) {
      return ExportBuildRefusal.permitForAnotherReport;
    }
    final scope = permit.scope;
    if (result.isConsolidated) {
      if (!scope.isConsolidated) {
        return ExportBuildRefusal.permitForAnotherScope;
      }
      // Every property the figures come from must be inside the permitted scope.
      final units = <String>{
        for (final l in result.revenueByCategory) l.businessUnitId,
        for (final l in result.expenseByHierarchy) l.businessUnitId,
      };
      if (!scope.businessUnitIds.containsAll(units)) {
        return ExportBuildRefusal.permitForAnotherScope;
      }
      return null;
    }
    return scope == ExportScope.unit(result.businessUnitId!)
        ? null
        : ExportBuildRefusal.permitForAnotherScope;
  }

  static ExportBuildRefusal? _checkComparison(
    PnlComparison comparison,
    PnlResult result,
  ) => comparison.pair.current == result.range
      ? null
      : ExportBuildRefusal.comparisonForAnotherRange;

  /// The screen's wording for a ranked row: "Property · Category" when consolidated.
  static String _prefixed(
    PnlResult result,
    ExportLabels labels,
    String businessUnitId,
    String name,
  ) => result.isConsolidated
      ? '${labels.businessUnit(businessUnitId)} · $name'
      : name;

  static ExportRanking _ranking<L>(
    TopNOutcome<L> outcome,
    String Function(L line) label,
  ) => switch (outcome) {
    TopNRefused(:final reason) => ExportRankingRefused(reason),
    TopNGrouped(:final top, :final others, :final othersCount, :final total) =>
      ExportRankingGrouped(
        rows: List.unmodifiable([
          for (final r in top)
            ExportRankedRow(label: label(r.line), amount: r.amount),
        ]),
        others: others,
        othersCount: othersCount,
        total: total,
      ),
  };
}
