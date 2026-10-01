/// The Windows Analytics workspace (Phase 6 Slice 8).
///
/// Spec §19 puts four sections under Analytics. They sit behind one segmented selector,
/// which is the pattern Transactions already uses for Expenses and Sales (D-120):
///
/// ```
///     Profit & Loss                  the existing Phase 5 page, embedded unchanged
///     Revenue Analysis               ┐
///     Expense & Department Analysis  ├ one workspace over the dashboard's providers
///     Business Comparison            ┘
/// ```
///
/// ## The Profit & Loss is not rebuilt
///
/// It is `ProfitAndLossPage`, the Slice 8 surface, with its own periods, selection,
/// drill-down and synchronisation. Nothing here reaches into it, and nothing here is a
/// second P&L (D-020).
///
/// ## The three analysis sections are one workspace
///
/// They share the dashboard's selection, its one `DashboardEngine.build` and its
/// authority-stamped state (D-267), so moving between them reads nothing again — every
/// section is a different arrangement of the same prepared view. Each is shown only after
/// `dashboardPresentation` has said the view belongs to the authority in force now; a
/// missing side, an unauthorised scope, a disagreeing period or a failed download is the
/// dashboard's own stated refusal, never a zero (D-163).
///
/// Both halves stay mounted in an [IndexedStack], so a P&L the reader was drilling into
/// is still there when they come back from Revenue Analysis. The workspace is built the
/// first time an analysis section is opened, not before — a reader who only looks at the
/// P&L starts no dashboard synchronisation.
///
/// ## Opening a figure (Phase 6 Slice 9)
///
/// A figure in an analysis section opens through the shared adapter
/// (`dashboard_drill.dart`) into the existing Phase 5 drill-down, shown in place of the
/// section it was opened from. The section stays mounted underneath, so Back returns to the
/// same section, scope, period and place on the page. The Profit & Loss section keeps its
/// own Phase 5 drill-down and is not touched.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/components/section_header.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_navigation.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_presentation.dart';
import 'package:krishna_mis/features/analytics/presentation/business_comparison.dart';
import 'package:krishna_mis/features/analytics/presentation/expense_analysis.dart';
import 'package:krishna_mis/features/analytics/presentation/revenue_analysis.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_drill.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_drill_view.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_widgets.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/profit_and_loss_page.dart';

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  /// Whether an analysis section has been opened yet. Until it has, the workspace is not
  /// built and asks the server nothing.
  bool _workspaceOpened = false;

  @override
  Widget build(BuildContext context) {
    final section = ref.watch(analyticsSectionProvider);
    final analysis =
        section.periodModel == AnalyticsPeriodModel.dashboardToDate;
    if (analysis) _workspaceOpened = true;

    return Column(
      key: const Key('analytics-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<AnalyticsSection>(
              key: const Key('analytics-sections'),
              segments: [
                for (final option in AnalyticsSection.values)
                  ButtonSegment(
                    value: option,
                    label: Text(
                      option.selectorLabel,
                      key: Key('analytics-section-${option.name}'),
                    ),
                  ),
              ],
              selected: {section},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => ref
                  .read(analyticsSectionProvider.notifier)
                  .select(selection.first),
            ),
          ),
        ),
        const Divider(height: 1, color: AppColors.hairline),
        Expanded(
          child: IndexedStack(
            index: analysis ? 1 : 0,
            children: [
              ProfitAndLossPage(shellKind: widget.shellKind),
              if (_workspaceOpened)
                AnalyticsWorkspace(
                  section: section,
                  shellKind: widget.shellKind,
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Revenue Analysis, Expense & Department Analysis and Business Comparison, over the one
/// dashboard state they share.
class AnalyticsWorkspace extends ConsumerStatefulWidget {
  const AnalyticsWorkspace({
    required this.section,
    required this.shellKind,
    super.key,
  });

  final AnalyticsSection section;
  final AppShellKind shellKind;

  @override
  ConsumerState<AnalyticsWorkspace> createState() => _AnalyticsWorkspaceState();
}

class _AnalyticsWorkspaceState extends ConsumerState<AnalyticsWorkspace> {
  @override
  void initState() {
    super.initState();
    // Render what the cache already holds, then bring it up to date — once per authority,
    // shared with the Overview; Refresh repeats it on demand.
    dashboardRefreshWhenOpened(ref, () => mounted);
  }

  @override
  Widget build(BuildContext context) {
    final density = widget.shellKind == AppShellKind.desktop
        ? AppDensity.compact
        : AppDensity.comfortable;
    final section = widget.section;
    final stateAsync = ref.watch(dashboardViewProvider);
    final sync = ref.watch(dashboardSyncProvider);
    final principal = ref.watch(principalProvider);
    // Only a dashboard assembled under the authority in force now — a different person, or
    // the same person whose qualifying capabilities have moved (D-231, D-242, D-267).
    final presentation = dashboardPresentation(
      state: stateAsync,
      sync: sync,
      principal: principal,
    );
    final authorised =
        presentation is! DashboardUnavailable ||
        presentation.reason != DashboardUnavailableReason.notAuthorised;

    // A figure opened from this section is shown in place of it; the section stays mounted
    // underneath so Back finds it exactly as it was.
    final drill = ref.watch(dashboardDrillProvider);
    final drilling =
        drill != null &&
        drill.origin == DashboardDrillOrigin.ofSection(section);

    return IndexedStack(
      index: drilling ? 1 : 0,
      sizing: StackFit.expand,
      children: [
        _workspace(
          density,
          section,
          stateAsync,
          sync,
          presentation,
          authorised,
        ),
        if (drilling)
          DashboardDrillPane(drill: drill, shellKind: widget.shellKind)
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _workspace(
    AppDensity density,
    AnalyticsSection section,
    AsyncValue<DashboardState> stateAsync,
    DashboardSyncStatus sync,
    DashboardPresentation presentation,
    bool authorised,
  ) {
    return ListView(
      key: const Key('analytics-workspace'),
      padding: EdgeInsets.all(density.pagePadding),
      children: [
        SectionHeader(
          eyebrow: 'Krishna Imperial MIS',
          title: section.label,
          trailing: DashboardRefreshControl(sync: sync),
        ),
        // The scope and period controls are shown only to a reader who has a dashboard to
        // scope: a principal without authority must not learn which properties exist.
        if (authorised) ...[
          const Text(
            analyticsPeriodModelNote,
            key: Key('analytics-period-model'),
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
          const DashboardScopeBar(),
          const SizedBox(height: AppSpacing.sm),
          const DashboardPeriodBar(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (stateAsync.hasError && presentation is DashboardLoading)
          DashboardMessageView(
            message: dashboardReadErrorMessage,
            onAction: () {
              retryFailedDashboardInputs(ref.exists, ref.read, ref.invalidate);
              ref.invalidate(dashboardViewProvider);
            },
            actionLabel: 'Try again',
          )
        else
          _Body(section: section, presentation: presentation, sync: sync),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.section,
    required this.presentation,
    required this.sync,
  });

  final AnalyticsSection section;
  final DashboardPresentation presentation;
  final DashboardSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A reader without qualifying authority gets the approved neutral state in every
    // section, before anything section-specific is said (D-259).
    final notAuthorised =
        presentation is DashboardUnavailable &&
        (presentation as DashboardUnavailable).reason ==
            DashboardUnavailableReason.notAuthorised;

    // Business Comparison is a consolidated view. Whether this reader may have one is the
    // P&L's own scope answer (D-164, D-187), and the scope is checked before any figure.
    if (section == AnalyticsSection.businessComparison && !notAuthorised) {
      final options = pnlScopeOptionsShownTo(
        ref.watch(pnlScopeOptionsProvider),
        ref.watch(principalProvider),
      );
      if (options == null) return const DashboardLoadingView();
      if (!options.consolidatedAllowed) {
        return const DashboardMessageView(
          message: analyticsComparisonNotAuthorised,
        );
      }
      final scope =
          ref.watch(dashboardSelectionProvider).scope ?? options.defaultScope;
      if (scope != const PnlConsolidatedScope()) {
        return DashboardMessageView(
          message: analyticsComparisonNeedsBoth,
          actionLabel: analyticsCompareBothLabel,
          onAction: () => ref
              .read(dashboardSelectionProvider.notifier)
              .selectScope(const PnlConsolidatedScope()),
        );
      }
    }

    // Loading, or the dashboard's own message in place of the figures.
    if (dashboardStateView(ref, presentation, sync) case final Widget state) {
      return state;
    }

    // A failed refresh is reported beside the figures, never instead of them: a failed
    // run writes nothing, so what is shown is still the last complete snapshot.
    final ready = (presentation as DashboardAvailable).dashboard;
    return Column(
      key: const Key('analytics-body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardStatusLines(ready: ready, sync: sync),
        const SizedBox(height: AppSpacing.lg),
        switch (section) {
          AnalyticsSection.revenue => RevenueAnalysisSection(ready: ready),
          AnalyticsSection.expenses => ExpenseAnalysisSection(ready: ready),
          AnalyticsSection.businessComparison =>
            // Checked above: the scope is consolidated, so the view is the whole
            // organisation's. A single-property view never reaches this line.
            ready.scope == const PnlConsolidatedScope()
                ? BusinessComparisonSection(ready: ready)
                : const DashboardLoadingView(),
          // The P&L section is the embedded Phase 5 page, never drawn here.
          AnalyticsSection.profitAndLoss => const SizedBox.shrink(),
        },
      ],
    );
  }
}
