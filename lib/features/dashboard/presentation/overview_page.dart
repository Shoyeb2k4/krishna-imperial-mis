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
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

/// Below this the analytical grid collapses to one column. A 1366-wide window beside the
/// 240-pixel sidebar leaves about 1,100, which is comfortably two.
const _twoColumnWidth = 980.0;

/// Below this the four headline figures stop sitting on one line.
const _fourAcrossWidth = 860.0;
const _twoAcrossWidth = 460.0;

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
          trailing: _RefreshControl(sync: sync),
        ),
        // The scope and period controls are shown only to a reader who has a dashboard to
        // scope: a principal without authority must not learn which properties exist.
        if (presentation is! DashboardUnavailable ||
            presentation.reason !=
                DashboardUnavailableReason.notAuthorised) ...[
          const _ScopeBar(),
          const SizedBox(height: AppSpacing.sm),
          const _PeriodBar(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (stateAsync.hasError && presentation is DashboardLoading)
          _Message(
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
    if (presentation is DashboardLoading) return const _Loading();

    final message = dashboardMessageFor(
      presentation,
      sync,
      canAsk: ref.watch(reportingSyncProvider) != null,
    );
    if (message != null) {
      final controller = ref.read(dashboardSyncProvider.notifier);
      return _Message(
        message: message,
        onAction: switch (message.action) {
          DashboardMessageAction.synchronise => controller.refresh,
          DashboardMessageAction.download ||
          DashboardMessageAction.retryDownload => controller.download,
          null => null,
        },
      );
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
    final notice = dashboardNoticeFor(sync);
    final freshness = dashboardFreshnessLine(
      ready,
      ref.watch(businessDayRulesProvider).value ?? const {},
    );
    final cap = dashboardCapNote(ready.pair);
    final period = dashboardPeriodLine(ready.pair);
    final comparedWith = dashboardComparisonRangeLabel(ready.pair);

    return Column(
      key: const Key('dashboard-body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) _Notice(notice: notice),
        Text(
          period,
          key: const Key('dashboard-period-line'),
          style: AppTypography.caption,
        ),
        Text(
          freshness.text,
          key: freshness.key,
          style: freshness.caution
              ? AppTypography.caption.copyWith(color: AppColors.caution)
              : AppTypography.caption,
        ),
        if (cap != null)
          Text(
            cap,
            key: const Key('dashboard-comparison-capped'),
            style: AppTypography.caption,
          ),
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
      final across = constraints.maxWidth >= _fourAcrossWidth
          ? 4
          : constraints.maxWidth >= _twoAcrossWidth
          ? 2
          : 1;
      final blocks = <Widget>[
        _MoneyMetric(
          keyName: 'net-sales',
          label: 'Net Sales',
          amount: result.netSales,
          movement: dashboardMoneyMovement(comparison.netSales),
          comparedWith: comparedWith,
          // Gross Sales and GST stay secondary to Net Sales rather than becoming two more
          // headline figures. They are the canonical result's own, so they reconcile with
          // it by construction: Gross = GST + Net.
          secondary: _Secondary(gross: result.grossSales, gst: result.gst),
        ),
        _MoneyMetric(
          keyName: 'expenses',
          label: 'Operating Expenses',
          amount: result.expenses,
          movement: dashboardMoneyMovement(comparison.expenses),
          comparedWith: comparedWith,
        ),
        _MoneyMetric(
          keyName: 'operating',
          label: dashboardProfitLabel(result),
          amount: result.operatingProfit,
          emphasis: MoneyEmphasis.bySign,
          movement: dashboardMoneyMovement(comparison.operatingProfit),
          comparedWith: comparedWith,
        ),
        _MarginMetric(
          margin: result.margin.displayTwoDecimals,
          movement: dashboardMarginMovement(comparison.margin),
          previous: dashboardPreviousMarginLabel(comparison.margin),
          comparedWith: comparedWith,
        ),
      ];
      return _Grid(across: across, children: blocks);
    },
  );
}

class _Secondary extends StatelessWidget {
  const _Secondary({required this.gross, required this.gst});

  final Money gross;
  final Money gst;

  /// A [Wrap], not a [Row]: at four metrics across a 1366-wide window a column is about
  /// 245 logical pixels, and "Gross ₹13,23,420.00 · GST ₹6,302.00" does not fit on one
  /// line of it. Money is never ellipsised, so the pair flows onto a second line instead
  /// — the lesson D-123 records, met again at a new width.
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.xxs,
    children: [
      _Pair(
        label: 'Gross',
        amount: gross,
        amountKey: const Key('dashboard-gross-sales'),
        semanticPrefix: 'Gross Sales',
      ),
      _Pair(
        label: 'GST',
        amount: gst,
        amountKey: const Key('dashboard-gst'),
        semanticPrefix: 'G S T',
      ),
    ],
  );
}

class _Pair extends StatelessWidget {
  const _Pair({
    required this.label,
    required this.amount,
    required this.amountKey,
    required this.semanticPrefix,
  });

  final String label;
  final Money amount;
  final Key amountKey;
  final String semanticPrefix;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label ', style: AppTypography.caption),
      MoneyText(
        amount,
        key: amountKey,
        style: AppTypography.caption,
        align: TextAlign.left,
        semanticPrefix: semanticPrefix,
      ),
    ],
  );
}

/// One headline figure: its name, its exact amount, and the movement the domain decided.
class _MoneyMetric extends StatelessWidget {
  const _MoneyMetric({
    required this.keyName,
    required this.label,
    required this.amount,
    required this.movement,
    required this.comparedWith,
    this.emphasis = MoneyEmphasis.neutral,
    this.secondary,
  });

  final String keyName;
  final String label;
  final Money amount;
  final MoneyEmphasis emphasis;
  final DashboardMovement movement;
  final String comparedWith;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => _MetricShell(
    keyName: keyName,
    label: label,
    semantics: dashboardMetricSemantics(
      label: label,
      amount: amount,
      movement: movement,
      comparedWith: comparedWith,
    ),
    value: MoneyText(
      amount,
      key: Key('dashboard-$keyName-value'),
      style: AppTypography.metric,
      emphasis: emphasis,
      align: TextAlign.left,
    ),
    movement: movement,
    comparedWith: comparedWith,
    secondary: secondary,
  );
}

/// The margin, and the movement in percentage points.
///
/// The previous period's margin is printed beside the movement on purpose: the three
/// figures a reader can see then add up, because the displayed movement **is** the
/// difference of the two displayed margins (D-264).
class _MarginMetric extends StatelessWidget {
  const _MarginMetric({
    required this.margin,
    required this.movement,
    required this.previous,
    required this.comparedWith,
  });

  final String margin;
  final DashboardMovement movement;
  final String previous;
  final String comparedWith;

  @override
  Widget build(BuildContext context) => _MetricShell(
    keyName: 'margin',
    label: 'Operating Margin',
    semantics:
        'Operating Margin. $margin. '
        '${movement.semanticsWith(comparedWith)}'
        '${movement.available ? ' Previous $previous.' : ''}',
    value: Text(
      margin,
      key: const Key('dashboard-margin-value'),
      style: AppTypography.metric,
    ),
    movement: movement,
    comparedWith: comparedWith,
    secondary: movement.available
        ? Text(
            'Previous $previous',
            key: const Key('dashboard-margin-previous'),
            style: AppTypography.caption,
          )
        : null,
  );
}

class _MetricShell extends StatelessWidget {
  const _MetricShell({
    required this.keyName,
    required this.label,
    required this.semantics,
    required this.value,
    required this.movement,
    required this.comparedWith,
    this.secondary,
  });

  final String keyName;
  final String label;
  final String semantics;
  final Widget value;
  final DashboardMovement movement;
  final String comparedWith;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => Semantics(
    key: Key('dashboard-kpi-$keyName'),
    label: semantics,
    container: true,
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.hairlineStrong, width: 2),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.md,
            bottom: AppSpacing.sm,
            right: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label.toUpperCase(), style: AppTypography.overline),
              const SizedBox(height: AppSpacing.sm),
              value,
              const SizedBox(height: AppSpacing.xs),
              Text(
                movement.text,
                key: Key('dashboard-$keyName-movement'),
                style: movement.available
                    ? AppTypography.caption.copyWith(color: AppColors.ink)
                    : AppTypography.caption,
              ),
              if (movement.note case final String note)
                Text(
                  note,
                  key: Key('dashboard-$keyName-movement-note'),
                  style: AppTypography.caption,
                ),
              if (movement.available)
                Text('vs $comparedWith', style: AppTypography.caption),
              if (secondary case final Widget extra) ...[
                const SizedBox(height: AppSpacing.xs),
                extra,
              ],
            ],
          ),
        ),
      ),
    ),
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
        _Panel(
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
        _Panel(
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
      builder: (context, constraints) => _Grid(
        across: constraints.maxWidth >= _twoColumnWidth && panels.length > 1
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
    return _Panel(
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
                  label: _propertyName(graph, property.businessUnitId),
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
        consolidated ? '${_propertyName(graph, unitId)} · ' : '';

    final revenue = view.topRevenueCategories;
    final expenses = view.topExpenseCategories;
    final departments = view.departmentSpending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (revenue != null)
          _Panel(
            key: const Key('dashboard-revenue-mix'),
            children: [
              RankedBarChart(
                title: 'Revenue mix',
                periodLabel: '$period · by Net Sales',
                data: RankedBarChartData.fromTopN<RevenueCategoryLine>(
                  revenue,
                  label: (line) =>
                      '${unitPrefix(line.businessUnitId)}'
                      '${graph?.revenueCategory(line.revenueCategoryId)?.name ?? 'Revenue category not on this device'}',
                ),
              ),
            ],
          ),
        if (expenses != null || departments != null) ...[
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (context, constraints) => _Grid(
              across:
                  constraints.maxWidth >= _twoColumnWidth &&
                      expenses != null &&
                      departments != null
                  ? 2
                  : 1,
              children: [
                if (expenses != null)
                  _Panel(
                    key: const Key('dashboard-top-expenses'),
                    children: [
                      RankedBarChart(
                        title: 'Top expense categories',
                        periodLabel: period,
                        data: RankedBarChartData.fromTopN<ExpenseHierarchyLine>(
                          expenses,
                          label: (line) =>
                              '${unitPrefix(line.businessUnitId)}'
                              '${_expenseCategoryName(graph, line.categoryId)}',
                        ),
                      ),
                    ],
                  ),
                if (departments != null)
                  _Panel(
                    key: const Key('dashboard-departments'),
                    children: [
                      RankedBarChart(
                        title: 'Department spending',
                        periodLabel: period,
                        data: RankedBarChartData.fromTopN<ExpenseHierarchyLine>(
                          departments,
                          label: (line) =>
                              '${unitPrefix(line.businessUnitId)}'
                              '${_departmentName(graph, line.departmentId)}',
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

String _propertyName(MasterGraph? graph, String id) =>
    graph?.businessUnit(id)?.name ?? 'Property not on this device';

String _expenseCategoryName(MasterGraph? graph, String? id) => switch (id) {
  final String value =>
    graph?.expenseCategory(value)?.name ??
        'Expense category not on this device',
  null => 'Uncategorised',
};

String _departmentName(MasterGraph? graph, String? id) => switch (id) {
  final String value =>
    graph?.department(value)?.name ?? 'Department not on this device',
  null => 'Unassigned',
};

// ── Synchronisation ─────────────────────────────────────────────────────────

class _RefreshControl extends ConsumerWidget {
  const _RefreshControl({required this.sync});

  final DashboardSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = sync.isRunning;
    return TextButton.icon(
      key: const Key('dashboard-refresh'),
      onPressed: running
          ? null
          : () => ref.read(dashboardSyncProvider.notifier).refresh(),
      icon: running
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 16),
      label: Text(
        running
            ? (sync.phase == DashboardSyncPhase.downloading
                  ? 'Downloading'
                  : 'Synchronising')
            : 'Refresh',
      ),
    );
  }
}

// ── Scope and period ────────────────────────────────────────────────────────

class _ScopeBar extends ConsumerWidget {
  const _ScopeBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same provider the P&L reads, shown only to the person it was decided for. A
    // dashboard therefore cannot offer a property the P&L would refuse (D-267).
    final options = pnlScopeOptionsShownTo(
      ref.watch(pnlScopeOptionsProvider),
      ref.watch(principalProvider),
    );
    if (options == null || options.isEmpty) return const SizedBox.shrink();
    final selected =
        ref.watch(dashboardSelectionProvider).scope ?? options.defaultScope;
    final controller = ref.read(dashboardSelectionProvider.notifier);

    return Wrap(
      key: const Key('dashboard-scope-bar'),
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        if (options.consolidatedAllowed)
          ChoiceChip(
            key: const Key('dashboard-scope-consolidated'),
            label: const Text(dashboardConsolidatedScopeLabel),
            selected: selected == const PnlConsolidatedScope(),
            onSelected: (_) =>
                controller.selectScope(const PnlConsolidatedScope()),
          ),
        for (final unit in options.units)
          ChoiceChip(
            key: Key('dashboard-scope-${unit.id}'),
            label: Text(unit.name),
            selected: selected == PnlUnitScope(unit.id),
            onSelected: (_) => controller.selectScope(PnlUnitScope(unit.id)),
          ),
      ],
    );
  }
}

class _PeriodBar extends ConsumerStatefulWidget {
  const _PeriodBar();

  @override
  ConsumerState<_PeriodBar> createState() => _PeriodBarState();
}

class _PeriodBarState extends ConsumerState<_PeriodBar> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  bool _editingCustom = false;
  String? _error;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _apply() {
    // Parsed, never derived: the two dates a reader typed are the P&L dates, and a range
    // that ends before it starts is passed on and refused rather than swapped.
    final from = BusinessDate.tryParse(_from.text.trim());
    final to = BusinessDate.tryParse(_to.text.trim());
    if (from == null || to == null) {
      setState(() => _error = 'Enter both dates as YYYY-MM-DD.');
      return;
    }
    setState(() => _error = null);
    ref.read(dashboardSelectionProvider.notifier).selectCustom(from, to);
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(dashboardSelectionProvider).period;
    final available =
        ref.watch(dashboardPeriodAvailabilityProvider).value ?? const {};
    final controller = ref.read(dashboardSelectionProvider.notifier);
    final customSelected = period is DashboardCustomPeriod || _editingCustom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          key: const Key('dashboard-period-bar'),
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final kind in DashboardPeriodKind.values)
              if (kind != DashboardPeriodKind.custom)
                Tooltip(
                  message: available[kind] == false
                      ? 'The properties are on different business dates. Use Custom.'
                      : '',
                  child: ChoiceChip(
                    key: Key('dashboard-period-${kind.name}'),
                    label: Text(kind.label),
                    selected:
                        !customSelected &&
                        period is DashboardRelativePeriod &&
                        period.kind == kind,
                    onSelected: available[kind] == false
                        ? null
                        : (_) {
                            setState(() => _editingCustom = false);
                            controller.selectPeriod(kind);
                          },
                  ),
                ),
            ChoiceChip(
              key: const Key('dashboard-period-custom'),
              label: Text(DashboardPeriodKind.custom.label),
              selected: customSelected,
              onSelected: (_) => setState(() {
                _editingCustom = true;
                if (period is DashboardCustomPeriod) {
                  _from.text = period.from.iso;
                  _to.text = period.to.iso;
                }
              }),
            ),
          ],
        ),
        if (customSelected) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  key: const Key('dashboard-custom-from'),
                  controller: _from,
                  decoration: const InputDecoration(
                    labelText: 'From (YYYY-MM-DD)',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
              SizedBox(
                width: 150,
                child: TextField(
                  key: const Key('dashboard-custom-to'),
                  controller: _to,
                  decoration: const InputDecoration(
                    labelText: 'To (YYYY-MM-DD)',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
              FilledButton(
                key: const Key('dashboard-custom-apply'),
                onPressed: _apply,
                child: const Text('Apply'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('dashboard-custom-error'),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.caution,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Building blocks ─────────────────────────────────────────────────────────

/// [children] laid out in [across] columns of equal width, wrapping into rows.
///
/// A grid rather than a `Wrap` of fixed widths, so a narrower window narrows the columns
/// instead of pushing the last one off the page.
class _Grid extends StatelessWidget {
  const _Grid({required this.across, required this.children});

  final int across;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += across) {
      final slice = children.sublist(
        i,
        (i + across) > children.length ? children.length : i + across,
      );
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < across; c++) ...[
              if (c > 0) const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: c < slice.length ? slice[c] : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
      if (i + across < children.length) {
        rows.add(const SizedBox(height: AppSpacing.lg));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.notice});

  final DashboardNotice notice;

  @override
  Widget build(BuildContext context) => Padding(
    key: notice.key,
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(notice.icon, size: 16, color: AppColors.caution),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(notice.text, style: AppTypography.caption)),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.message, this.onAction, this.actionLabel});

  final DashboardMessage message;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel ?? message.action?.label;
    return Padding(
      key: message.key,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(message.icon, size: 28, color: AppColors.inkFaint),
          const SizedBox(height: AppSpacing.md),
          Text(
            message.title,
            style: AppTypography.subheading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              message.message,
              style: AppTypography.bodyMuted,
              textAlign: TextAlign.center,
            ),
          ),
          if (label != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              key: message.actionKey,
              onPressed: onAction,
              child: Text(label),
            ),
          ],
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    key: Key('dashboard-loading'),
    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Center(
      child: SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
