/// Expense & Department Analysis — where operating money is being spent (Phase 6 Slice 8).
///
/// A ruled Operating Expenses line against the comparable stretch; the **monthly** expense
/// trend where the period offers one; the top expense categories; and department spending.
///
/// ## What this file does and does not do
///
/// It **arranges**. Operating Expenses is the canonical result's own figure and its
/// movement is `PnlComparison`'s. The trend is plotted only at the grain the planner
/// offered, and for expenses that is monthly or nothing (D-255, D-263): a daily or weekly
/// expense series is never requested here, because accrual dating makes it describe when a
/// bill was dated rather than what was spent. Where no monthly trend is offered, the
/// section says why instead of drawing an empty plot.
///
/// The ranked categories and departments are `TopN`'s, over lines checked to add up to
/// Operating Expenses before they were grouped; Others is the domain's exact remainder and
/// is drawn as handed over, never recomputed (D-258). A set that does not reconcile draws
/// no rows at all.
///
/// Not here, deliberately: vendor or supplier rankings, budgets and variance, forecasts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/charts/charts.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_presentation.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_widgets.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_widgets.dart';

class ExpenseAnalysisSection extends ConsumerWidget {
  const ExpenseAnalysisSection({required this.ready, super.key});

  /// A computed dashboard — the workspace shows this section only once
  /// `dashboardPresentation` has said so.
  final DashboardReady ready;

  /// The monthly Operating Expenses series, when the planner offered one.
  TrendSeries? _monthlyExpenses() {
    for (final series in ready.view.trends) {
      if (series.measure == TrendMeasure.expenses &&
          series.grain == TrendGrain.monthly) {
        return series;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ready.view;
    final result = view.resultOrNull!;
    final period = dashboardPeriodLine(ready.pair);
    final graph = ref.watch(masterGraphProvider).value;
    final trend = _monthlyExpenses();
    final categories = view.topExpenseCategories;
    final departments = view.departmentSpending;

    String prefix(String unitId) => result.isConsolidated
        ? '${dashboardPropertyName(graph, unitId)} · '
        : '';

    final ranked = <Widget>[
      if (categories != null)
        DashboardPanel(
          key: const Key('analytics-top-expenses'),
          children: [
            RankedBarChart(
              title: 'Top expense categories',
              periodLabel: period,
              data: RankedBarChartData.fromTopN<ExpenseHierarchyLine>(
                categories,
                label: (line) =>
                    '${prefix(line.businessUnitId)}'
                    '${dashboardExpenseCategoryName(graph, line.categoryId)}',
              ),
            ),
          ],
        ),
      if (departments != null)
        DashboardPanel(
          key: const Key('analytics-departments'),
          children: [
            RankedBarChart(
              title: 'Department spending',
              periodLabel: period,
              data: RankedBarChartData.fromTopN<ExpenseHierarchyLine>(
                departments,
                label: (line) =>
                    '${prefix(line.businessUnitId)}'
                    '${dashboardDepartmentName(graph, line.departmentId)}',
              ),
            ),
          ],
        ),
    ];

    return Column(
      key: const Key('analytics-expenses'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardPanel(
          key: const Key('analytics-expense-summary'),
          children: [
            AnalyticsRuledSummary(
              comparedWith: analyticsComparedWithLine(ready.pair),
              lines: [
                AnalyticsSummaryLine(
                  keyName: 'expense-total',
                  label: 'Operating Expenses',
                  amount: result.expenses,
                  movement: dashboardMoneyMovement(view.comparison.expenses),
                  strong: true,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        DashboardPanel(
          key: const Key('analytics-expense-trend'),
          children: [
            if (trend != null)
              TrendLineChart(
                title: dashboardTrendTitle(trend),
                periodLabel: period,
                style: ChartTheme.expenses,
                data: dashboardTrendChartData(trend),
              )
            else
              AnalyticsNote(
                key: const Key('analytics-expense-no-trend'),
                text: analyticsNoExpenseTrend(ready.pair.kind),
              ),
          ],
        ),
        if (ranked.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (context, constraints) => DashboardGrid(
              across:
                  constraints.maxWidth >= dashboardTwoColumnWidth &&
                      ranked.length > 1
                  ? 2
                  : 1,
              children: ranked,
            ),
          ),
        ],
      ],
    );
  }
}
