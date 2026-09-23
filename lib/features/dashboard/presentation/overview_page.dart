/// The Windows Overview — the management dashboard (Phase 6 Slice 6).
///
/// ## What this file does and does not do
///
/// It **arranges**. Every figure arrives decided: the primitives are summed by the local
/// engine over the canonical reporting cache, the P&L by `Pnl.compute`, the movements by
/// `PnlComparison`, the trend buckets and their gaps by `DashboardTrends`, the ranked
/// lines and Others by `TopN`, and the per-property split by `PropertyComparison`. It
/// sums nothing, ranks nothing, rounds no margin, reads no repository and derives no date
/// — the Slice 6 surface guard fails the build if it starts to.
///
/// It **refuses** rather than rendering a zero it cannot stand behind. Not authorised,
/// not downloaded, one side unavailable, or a period the properties disagree about are
/// each their own state, never ₹0 and never an empty chart (D-163). A missing trend point
/// stays a visible break in the line; a clipped week or month stays labelled as clipped
/// (D-263).
///
/// A **failed refresh never blanks a complete dashboard**: a failed run writes nothing
/// (D-048), so the figures on screen are still the last complete canonical snapshot, and
/// the failure is reported beside them.
///
/// The wording of every state is shared with the Android Home surface
/// (`dashboard_presentation.dart`), so the two cannot describe one dashboard differently.
///
/// **Drill-down is Slice 9.** The sections carry selection callbacks and no navigation:
/// nothing here duplicates the P&L drill-down, and no temporary detail screen is invented.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/charts/charts.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/components/section_header.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/reporting/dashboard_engine.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_widgets.dart';

class OverviewPage extends ConsumerStatefulWidget {
  const OverviewPage({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  ConsumerState<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends ConsumerState<OverviewPage> {
  @override
  void initState() {
    super.initState();
    // Render what the cache already holds, then bring it up to date. Once per session on
    // opening; Refresh repeats it on demand.
    dashboardRefreshWhenOpened(ref, () => mounted);
  }

  @override
  Widget build(BuildContext context) {
    final density = widget.shellKind == AppShellKind.desktop
        ? AppDensity.compact
        : AppDensity.comfortable;
    final stateAsync = ref.watch(dashboardViewProvider);
    final sync = ref.watch(dashboardSyncProvider);
    // Only a dashboard assembled under the authority in force now — a different person,
    // or the same person whose qualifying capabilities have moved (D-231, D-242, D-267).
    final presentation = dashboardPresentation(
      state: stateAsync,
      sync: sync,
      principal: ref.watch(principalProvider),
    );

    return ListView(
      key: const Key('dashboard-page'),
      padding: EdgeInsets.all(density.pagePadding),
      children: [
        SectionHeader(
          eyebrow: 'Krishna Imperial MIS',
          title: 'Overview',
          trailing: DashboardRefreshControl(sync: sync),
        ),
        // The scope and period controls are shown only to a reader who has a dashboard to
        // scope: a principal without authority must not learn which properties exist.
        if (presentation is! DashboardUnavailable ||
            presentation.reason !=
                DashboardUnavailableReason.notAuthorised) ...[
          const DashboardScopeBar(),
          const SizedBox(height: AppSpacing.sm),
          const DashboardPeriodBar(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (stateAsync.hasError && presentation is DashboardLoading)
          DashboardMessageView(
            message: dashboardReadErrorMessage,
            onAction: () => ref.invalidate(dashboardViewProvider),
            actionLabel: 'Try again',
          )
        else
          _Body(presentation: presentation, sync: sync),
      ],
    );
  }
}

// ── Body ────────────────────────────────────────────────────────────────────

class _Body extends ConsumerWidget {
  const _Body({required this.presentation, required this.sync});

  final DashboardPresentation presentation;
  final DashboardSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Loading, or a message in place of the figures — never a zero it cannot stand behind.
    if (dashboardStateView(ref, presentation, sync) case final Widget state) {
      return state;
    }

    // A failed refresh is reported beside the figures, never instead of them: a failed
    // run writes nothing, so what is on screen is still the last complete snapshot.
    final available = presentation as DashboardAvailable;
    return _Dashboard(ready: available.dashboard, sync: sync);
  }
}

class _Dashboard extends ConsumerWidget {
  const _Dashboard({required this.ready, required this.sync});

  final DashboardReady ready;
  final DashboardSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ready.view;
    // The headline is computed — `dashboardPresentation` refuses otherwise — so this is
    // the canonical result every figure below comes from.
    final result = view.resultOrNull!;
    final period = dashboardPeriodLine(ready.pair);
    final comparedWith = dashboardComparisonRangeLabel(ready.pair);

    return Column(
      key: const Key('dashboard-body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardStatusLines(ready: ready, sync: sync),
        const SizedBox(height: AppSpacing.lg),
        _Headline(
          result: result,
          comparison: view.comparison,
          comparedWith: comparedWith,
        ),
        const SizedBox(height: AppSpacing.xl),
        _Trends(view: view, period: period),
        if (view.propertyComparison
            case final PropertyComparisonReady split) ...[
          const SizedBox(height: AppSpacing.xl),
          _PropertyComparison(split: split, period: period),
        ],
        const SizedBox(height: AppSpacing.xl),
        _RankedSections(view: view, period: period),
      ],
    );
  }
}

// ── The four headline figures ───────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({
    required this.result,
    required this.comparison,
    required this.comparedWith,
  });

  final PnlResult result;
  final PnlComparison comparison;
  final String comparedWith;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final across = constraints.maxWidth >= dashboardFourAcrossWidth
          ? 4
          : constraints.maxWidth >= dashboardTwoAcrossWidth
          ? 2
          : 1;
      final blocks = <Widget>[
        DashboardMoneyMetric(
          keyName: 'net-sales',
          label: 'Net Sales',
          amount: result.netSales,
          movement: dashboardMoneyMovement(comparison.netSales),
          comparedWith: comparedWith,
          // Gross Sales and GST stay secondary to Net Sales rather than becoming two more
          // headline figures. They are the canonical result's own, so they reconcile with
          // it by construction: Gross = GST + Net.
          secondary: DashboardGrossAndGst(
            gross: result.grossSales,
            gst: result.gst,
          ),
        ),
        DashboardMoneyMetric(
          keyName: 'expenses',
          label: 'Operating Expenses',
          amount: result.expenses,
          movement: dashboardMoneyMovement(comparison.expenses),
          comparedWith: comparedWith,
        ),
        DashboardMoneyMetric(
          keyName: 'operating',
          label: dashboardProfitLabel(result),
          amount: result.operatingProfit,
          emphasis: MoneyEmphasis.bySign,
          movement: dashboardMoneyMovement(comparison.operatingProfit),
          comparedWith: comparedWith,
        ),
        DashboardMarginMetric(
          margin: result.margin.displayTwoDecimals,
          movement: dashboardMarginMovement(comparison.margin),
          previous: dashboardPreviousMarginLabel(comparison.margin),
          comparedWith: comparedWith,
        ),
      ];
      return DashboardGrid(across: across, children: blocks);
    },
  );
}

// ── Trends ──────────────────────────────────────────────────────────────────

class _Trends extends StatelessWidget {
  const _Trends({required this.view, required this.period});

  final DashboardView view;
  final String period;

  TrendSeries? _series(TrendMeasure measure) {
    for (final series in view.trends) {
      if (series.measure == measure) return series;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final netSales = _series(TrendMeasure.netSales);
    // Only where Slice 2 says a monthly cost trend is a trend at all: one bucket shows no
    // direction, and the planner therefore offers none (D-263).
    final profit = _series(TrendMeasure.operatingProfit);

    final panels = <Widget>[
      if (netSales != null)
        DashboardPanel(
          key: const Key('dashboard-trend-net-sales'),
          children: [
            TrendLineChart(
              title: dashboardTrendTitle(netSales),
              periodLabel: period,
              data: dashboardTrendChartData(netSales),
            ),
          ],
        ),
      if (profit != null)
        DashboardPanel(
          key: const Key('dashboard-trend-operating-profit'),
          children: [
            ProfitBarChart(
              title: dashboardTrendTitle(profit),
              periodLabel: period,
              data: dashboardTrendChartData(profit),
            ),
          ],
        ),
    ];
    if (panels.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) => DashboardGrid(
        across:
            constraints.maxWidth >= dashboardTwoColumnWidth && panels.length > 1
            ? 2
            : 1,
        children: panels,
      ),
    );
  }
}

// ── Property comparison ─────────────────────────────────────────────────────

/// Net Sales, Expenses and Operating Profit per property, side by side.
///
/// Rendered only for a consolidated dashboard: [PropertyComparison] refuses a report that
/// covers one property, so a single-property scope has nothing to render here rather than
/// a chart of one bar. No property is labelled a winner, and the order is the domain's —
/// business-unit id, never figure order.
class _PropertyComparison extends ConsumerWidget {
  const _PropertyComparison({required this.split, required this.period});

  final PropertyComparisonReady split;
  final String period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(masterGraphProvider).value;
    return DashboardPanel(
      key: const Key('dashboard-property-comparison'),
      children: [
        ComparisonBarChart(
          title: 'Property comparison',
          periodLabel: period,
          styles: const [
            ChartTheme.netSales,
            ChartTheme.expenses,
            ChartTheme.operatingProfit,
          ],
          data: ComparisonChartData(
            seriesNames: const ['Net Sales', 'Expenses', 'Operating Profit'],
            groups: [
              for (final property in split.properties)
                ComparisonGroup(
                  label: dashboardPropertyName(graph, property.businessUnitId),
                  values: [
                    ChartAmount.money(property.netSales),
                    ChartAmount.money(property.expenses),
                    ChartAmount.money(property.operatingProfit),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Ranked sections ─────────────────────────────────────────────────────────

class _RankedSections extends ConsumerWidget {
  const _RankedSections({required this.view, required this.period});

  final DashboardView view;
  final String period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(masterGraphProvider).value;
    final consolidated = view.resultOrNull!.isConsolidated;

    String unitPrefix(String unitId) =>
        consolidated ? '${dashboardPropertyName(graph, unitId)} · ' : '';

    final revenue = view.topRevenueCategories;
    final expenses = view.topExpenseCategories;
    final departments = view.departmentSpending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (revenue != null)
          DashboardPanel(
            key: const Key('dashboard-revenue-mix'),
            children: [
              RankedBarChart(
                title: 'Revenue mix',
                periodLabel: '$period · by Net Sales',
                data: RankedBarChartData.fromTopN<RevenueCategoryLine>(
                  revenue,
                  label: (line) =>
                      '${unitPrefix(line.businessUnitId)}'
                      '${dashboardRevenueCategoryName(graph, line.revenueCategoryId)}',
                ),
              ),
            ],
          ),
        if (expenses != null || departments != null) ...[
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (context, constraints) => DashboardGrid(
              across:
                  constraints.maxWidth >= dashboardTwoColumnWidth &&
                      expenses != null &&
                      departments != null
                  ? 2
                  : 1,
              children: [
                if (expenses != null)
                  DashboardPanel(
                    key: const Key('dashboard-top-expenses'),
                    children: [
                      RankedBarChart(
                        title: 'Top expense categories',
                        periodLabel: period,
                        data: RankedBarChartData.fromTopN<ExpenseHierarchyLine>(
                          expenses,
                          label: (line) =>
                              '${unitPrefix(line.businessUnitId)}'
                              '${dashboardExpenseCategoryName(graph, line.categoryId)}',
                        ),
                      ),
                    ],
                  ),
                if (departments != null)
                  DashboardPanel(
                    key: const Key('dashboard-departments'),
                    children: [
                      RankedBarChart(
                        title: 'Department spending',
                        periodLabel: period,
                        data: RankedBarChartData.fromTopN<ExpenseHierarchyLine>(
                          departments,
                          label: (line) =>
                              '${unitPrefix(line.businessUnitId)}'
                              '${dashboardDepartmentName(graph, line.departmentId)}',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
