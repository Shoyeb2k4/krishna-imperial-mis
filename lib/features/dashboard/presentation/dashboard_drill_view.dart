/// The Windows pane a dashboard or analytics figure opens (Phase 6 Slice 9).
///
/// It is the **existing** Phase 5 drill-down, arranged in the place the figure was on: the
/// same breadcrumb, the same level list, the same immutable document bodies and the same
/// refusals, composed with nothing added to them. What a level holds, whether it adds up,
/// and whether the person signed in now may see it are all decided by the Phase 5
/// providers. This file reads nothing and calculates nothing.
///
/// Back returns to the surface the figure was on. That surface is kept mounted underneath
/// while the pane is open, so its section, scope, period and place on the page are exactly
/// as they were.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/core/formatting/report_dates.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_drill.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_view.dart';

class DashboardDrillPane extends ConsumerWidget {
  const DashboardDrillPane({
    required this.drill,
    required this.shellKind,
    super.key,
  });

  final DashboardDrillState drill;
  final AppShellKind shellKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = shellKind == AppShellKind.desktop
        ? AppDensity.compact
        : AppDensity.comfortable;
    final controller = ref.read(dashboardDrillProvider.notifier);
    final origin = drill.origin;
    final location = drill.location;
    final selected = drill.selected;
    // The dashboard's own synchronisation: the years a figure's range needs are the years
    // the dashboard period already asks for.
    void refresh() => ref.read(dashboardSyncProvider.notifier).refresh();

    return Padding(
      key: const Key('dashboard-drill'),
      padding: EdgeInsets.all(density.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('dashboard-drill-back'),
              onPressed: controller.close,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text('Back to ${origin.label}'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            reportRangeLabel(location.anchor.range),
            key: const Key('dashboard-drill-range'),
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.xs),
          PnlDrillBreadcrumb(
            location: location,
            reportLabel: origin.label,
            onReport: controller.close,
            onOpen: controller.openLevel,
          ),
          const Divider(height: AppSpacing.md, color: AppColors.hairline),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: PnlDrillLevelList(
                    location: location,
                    selected: selected,
                    reportLabel: origin.label,
                    onRefresh: refresh,
                    onOpen: controller.openLevel,
                    onSelect: controller.select,
                    onReportChanged: controller.close,
                  ),
                ),
                if (selected != null) ...[
                  const VerticalDivider(width: 1, color: AppColors.hairline),
                  SizedBox(
                    width: 420,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            key: const Key('pnl-document-close'),
                            tooltip: 'Close',
                            onPressed: controller.closeDocument,
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ),
                        Expanded(
                          child: PnlDocumentDetail(
                            request: selected,
                            reportLabel: origin.label,
                            onRefresh: refresh,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
