/// Revenue Analysis — where management revenue comes from, and how it is moving
/// (Phase 6 Slice 8).
///
/// Three things, in this order: a ruled summary of Gross Sales, GST and Net Sales against
/// the comparable stretch; the Net Sales trend at the grain the planner chose; and the
/// revenue mix by category, as the composed ranked rows D-269 approved.
///
/// ## What this file does and does not do
///
/// It **arranges**. Gross Sales, GST and Net Sales are the canonical result's own three
/// sums, so they reconcile by construction (Gross = GST + Net) — nothing here derives GST
/// from Gross or Net from anything. The movements are `PnlComparison`'s; the trend and its
/// gaps are `DashboardTrends`'; the category rows, their order and any Others are
/// `TopN`'s, over lines that were checked to add up to Net Sales before they were grouped
/// (D-258). A category that does not reconcile draws no rows at all.
///
/// Not here, deliberately: value-band, supply-subtype, vendor, occupancy, forecast or
/// target analysis — none is part of the canonical reporting model this reads.
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

class RevenueAnalysisSection extends ConsumerWidget {
  const RevenueAnalysisSection({required this.ready, super.key});

  /// A computed dashboard — the workspace shows this section only once
  /// `dashboardPresentation` has said so.
  final DashboardReady ready;

  TrendSeries? _netSalesTrend() {
    for (final series in ready.view.trends) {
      if (series.measure == TrendMeasure.netSales) return series;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ready.view;
    final result = view.resultOrNull!;
    final comparison = view.comparison;
    final period = dashboardPeriodLine(ready.pair);
    final graph = ref.watch(masterGraphProvider).value;
    final trend = _netSalesTrend();
    final mix = view.topRevenueCategories;

    String prefix(String unitId) => result.isConsolidated
        ? '${dashboardPropertyName(graph, unitId)} · '
        : '';

    return Column(
      key: const Key('analytics-revenue'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardPanel(
          key: const Key('analytics-revenue-summary'),
          children: [
            // Gross Sales, less GST, gives Net Sales: three independent canonical sums,
            // stated in the order a P&L reads.
            AnalyticsRuledSummary(
              comparedWith: analyticsComparedWithLine(ready.pair),
              lines: [
                AnalyticsSummaryLine(
                  keyName: 'revenue-gross-sales',
                  label: 'Gross Sales',
                  amount: result.grossSales,
                  movement: dashboardMoneyMovement(comparison.grossSales),
                ),
                AnalyticsSummaryLine(
                  keyName: 'revenue-gst',
                  label: 'Less GST',
                  amount: result.gst,
                  movement: dashboardMoneyMovement(comparison.gst),
                ),
                AnalyticsSummaryLine(
                  keyName: 'revenue-net-sales',
                  label: 'Net Sales',
                  amount: result.netSales,
                  movement: dashboardMoneyMovement(comparison.netSales),
                  strong: true,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        DashboardPanel(
          key: const Key('analytics-revenue-trend'),
          children: [
            if (trend != null)
              TrendLineChart(
                title: dashboardTrendTitle(trend),
                periodLabel: period,
                data: dashboardTrendChartData(trend),
              )
            else
              AnalyticsNote(
                key: const Key('analytics-revenue-no-trend'),
                text: analyticsNoNetSalesTrend(ready.pair.kind),
              ),
          ],
        ),
        if (mix != null) ...[
          const SizedBox(height: AppSpacing.xl),
          DashboardPanel(
            key: const Key('analytics-revenue-mix'),
            children: [
              RankedBarChart(
                title: 'Revenue mix by category',
                periodLabel: '$period · by Net Sales',
                data: RankedBarChartData.fromTopN<RevenueCategoryLine>(
                  mix,
                  label: (line) =>
                      '${prefix(line.businessUnitId)}'
                      '${dashboardRevenueCategoryName(graph, line.revenueCategoryId)}',
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
