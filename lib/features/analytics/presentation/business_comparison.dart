/// Business Comparison — both properties, side by side, over the same period
/// (Phase 6 Slice 8).
///
/// Crystal Canopy Rooftop and Hotel Krishna Imperial across Net Sales, Operating Expenses,
/// Operating Profit or Loss and Operating Margin, with the combined figures beside them.
/// Shown only for a consolidated scope, which only consolidated authority can select
/// (D-164, D-187); the workspace refuses every other case before this is built.
///
/// ## What this file does and does not do
///
/// It **arranges**. Every figure is a field of the per-property [PnlResult]s
/// `PropertyComparison` computed through `Pnl.compute` — nothing here sums a property's
/// categories or transactions, and nothing works out a margin. A split the domain refused
/// is a stated refusal, never a table of zeros.
///
/// **It ranks nothing.** Properties are listed in the domain's business-unit id order,
/// never in figure order; no property is called better, worse or anything that places
/// one above the other; and a loss is said in words beside the figure rather than told by
/// colour — every figure is drawn in neutral ink, so no property is painted good or bad.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/charts/charts.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_drill.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_widgets.dart';

class BusinessComparisonSection extends ConsumerWidget {
  const BusinessComparisonSection({required this.ready, super.key});

  /// A computed, consolidated dashboard.
  final DashboardReady ready;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ready.view;
    if (view.propertyComparison case final PropertyComparisonReady split) {
      // A property opens its own P&L for the same period, through the shared adapter
      // (Phase 6 Slice 9). Only a property this consolidated view covers.
      final opens = DashboardDrillTargets.of(
        ready,
        ref.watch(principalProvider),
      );
      return _Comparison(
        split: split,
        period: dashboardPeriodLine(ready.pair),
        onProperty: (unitId) {
          if (opens.property(unitId)
              case final DashboardDrillTarget destination) {
            openDashboardTarget(
              context,
              ref,
              destination,
              origin: DashboardDrillOrigin.businessComparison,
            );
          }
        },
      );
    }
    final refusal = switch (view.propertyComparison) {
      PropertyComparisonRefused(:final reason) => reason,
      _ => PropertyComparisonRefusal.singleProperty,
    };
    final message = analyticsComparisonRefused(refusal);
    return DashboardMessageView(
      message: message,
      onAction: message.action == null
          ? null
          : ref.read(dashboardSyncProvider.notifier).refresh,
    );
  }
}

class _Comparison extends ConsumerWidget {
  const _Comparison({
    required this.split,
    required this.period,
    required this.onProperty,
  });

  final PropertyComparisonReady split;
  final String period;

  /// Opens one property's P&L, by its canonical id.
  final ValueChanged<String> onProperty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(masterGraphProvider).value;
    final columns = <({String key, String name, PnlResult result})>[
      for (final property in split.properties)
        (
          key: property.businessUnitId,
          name: dashboardPropertyName(graph, property.businessUnitId),
          result: property.result,
        ),
      (key: 'total', name: analyticsComparisonTotalLabel, result: split.total),
    ];

    return Column(
      key: const Key('analytics-comparison'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardPanel(
          key: const Key('analytics-comparison-table'),
          children: [
            Text(period, style: AppTypography.caption),
            const SizedBox(height: AppSpacing.sm),
            Table(
              columnWidths: {
                0: const FlexColumnWidth(1.4),
                for (var i = 1; i <= columns.length; i++)
                  i: const FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppColors.hairlineStrong),
                    ),
                  ),
                  children: [
                    const _Cell(child: Text('', style: AppTypography.overline)),
                    for (final column in columns)
                      _Cell(
                        child: column.key == 'total'
                            ? Text(
                                column.name,
                                key: Key(
                                  'analytics-comparison-${column.key}-name',
                                ),
                                style: AppTypography.overline,
                                textAlign: TextAlign.right,
                              )
                            : InkWell(
                                key: Key(
                                  'analytics-comparison-${column.key}-open',
                                ),
                                onTap: () => onProperty(column.key),
                                child: Text(
                                  column.name,
                                  key: Key(
                                    'analytics-comparison-${column.key}-name',
                                  ),
                                  style: AppTypography.overline,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                      ),
                  ],
                ),
                _moneyRow(
                  label: 'Net Sales',
                  measure: 'net-sales',
                  columns: columns,
                  amount: (r) => r.netSales,
                ),
                _moneyRow(
                  label: 'Operating Expenses',
                  measure: 'expenses',
                  columns: columns,
                  amount: (r) => r.expenses,
                ),
                _moneyRow(
                  label: 'Operating Profit / Loss',
                  measure: 'operating',
                  columns: columns,
                  amount: (r) => r.operatingProfit,
                  word: analyticsOperatingWord,
                ),
                TableRow(
                  children: [
                    const _Cell(
                      child: Text(
                        'Operating Margin',
                        style: AppTypography.body,
                      ),
                    ),
                    for (final column in columns)
                      _Cell(
                        child: Text(
                          column.result.margin.displayTwoDecimals,
                          key: Key('analytics-comparison-${column.key}-margin'),
                          style: AppTypography.money,
                          textAlign: TextAlign.right,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              analyticsComparisonOrderNote,
              key: Key('analytics-comparison-order-note'),
              style: AppTypography.caption,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        // The chart adds the shape; the exact figures stay visible in the table above
        // without hovering anything.
        DashboardPanel(
          key: const Key('analytics-comparison-chart'),
          children: [
            ComparisonBarChart(
              title: 'Net Sales, expenses and operating result by property',
              periodLabel: period,
              onActivated: (i) =>
                  onProperty(split.properties[i].businessUnitId),
              styles: const [
                ChartTheme.netSales,
                ChartTheme.expenses,
                ChartTheme.operatingProfit,
              ],
              data: ComparisonChartData(
                seriesNames: const [
                  'Net Sales',
                  'Operating Expenses',
                  'Operating Profit / Loss',
                ],
                groups: [
                  for (final property in split.properties)
                    ComparisonGroup(
                      label: dashboardPropertyName(
                        graph,
                        property.businessUnitId,
                      ),
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
        ),
      ],
    );
  }

  TableRow _moneyRow({
    required String label,
    required String measure,
    required List<({String key, String name, PnlResult result})> columns,
    required Money Function(PnlResult) amount,
    String Function(PnlResult)? word,
  }) => TableRow(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.hairline)),
    ),
    children: [
      _Cell(child: Text(label, style: AppTypography.body)),
      for (final column in columns)
        _Cell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // At its natural size, never truncated, wrapped or shrunk: a
              // shortened amount is a wrong amount (D-269, D-286).
              MoneyText(
                amount(column.result),
                key: Key('analytics-comparison-${column.key}-$measure'),
              ),
              if (word != null)
                Text(
                  word(column.result),
                  key: Key('analytics-comparison-${column.key}-$measure-word'),
                  style: AppTypography.caption,
                ),
            ],
          ),
        ),
    ],
  );
}

class _Cell extends StatelessWidget {
  const _Cell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      vertical: AppSpacing.sm,
      horizontal: AppSpacing.xs,
    ),
    child: child,
  );
}
