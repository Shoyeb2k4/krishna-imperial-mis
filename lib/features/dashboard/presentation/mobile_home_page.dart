/// The Android Home — the management dashboard on a phone (Phase 6 Slice 7).
///
/// ## A phone presentation of the same dashboard, not a second one
///
/// Scope, period, authority, coverage, freshness, every figure and every movement come
/// from the same providers the Windows Overview reads
/// (`dashboard_providers.dart`), and every word from the same wording
/// (`dashboard_presentation.dart`). This file only arranges them for a portrait phone: the
/// scope in a bottom sheet, the periods in a horizontal strip, Custom through the Material
/// date-range picker, and the figures stacked rather than gridded. It sums nothing, ranks
/// nothing, rounds no margin, derives no date and reads no repository; the same structural
/// guard as the Overview holds it to that.
///
/// ## What it shows, and what it deliberately does not (D-260)
///
/// Scope, period, freshness, the four headline figures with their comparison indicators,
/// the Net Sales trend, top expense categories, property comparison when consolidated
/// authority exists, and one way through to the full profit & loss.
///
/// **Revenue mix and department spending are not on the phone.** Those belong to the
/// Windows Analytics workspace, which Phase 6 does not reproduce on Android — and a Home
/// screen that listed every analysis would stop being the thing a manager glances at on a
/// rooftop.
///
/// ## The one navigation, and why it is not drill-down
///
/// *See full P&L* switches the shell to the Reports branch. It is a top-level destination
/// the phone already has, not a breakdown: drill-down from a dashboard figure to its
/// transactions is Slice 9's, and nothing here duplicates the P&L's own.
///
/// ## Custom dates
///
/// Chosen on a calendar only — no typed date entry (D-229, approved as final by D-250).
/// The tapped calendar days are the explicit P&L dates, read by year, month and day and
/// never converted through a timezone, UTC or the device clock.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/charts/charts.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/reporting/dashboard_engine.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

/// Space kept clear under the last item, so nothing sits behind the docked [ + ] action.
///
/// The same clearance the phone P&L uses: the action is 56 logical pixels and docks half
/// its height above the bottom bar, and the rest is breathing room.
const dashboardMobileNavigationClearance = 96.0;

class MobileHomePage extends ConsumerStatefulWidget {
  const MobileHomePage({super.key});

  @override
  ConsumerState<MobileHomePage> createState() => _MobileHomePageState();
}

class _MobileHomePageState extends ConsumerState<MobileHomePage> {
  @override
  void initState() {
    super.initState();
    // Render what the cache already holds, then bring it up to date.
    dashboardRefreshWhenOpened(ref, () => mounted);
  }

  @override
  Widget build(BuildContext context) {
    // A new person on the same installation starts a fresh refresh of their own.
    ref.listen(principalProvider.select((p) => p.userId), (previous, next) {
      if (previous != next) dashboardRefreshWhenOpened(ref, () => mounted);
    });

    final stateAsync = ref.watch(dashboardViewProvider);
    final sync = ref.watch(dashboardSyncProvider);
    // Only a dashboard assembled under the authority in force now (D-231, D-242, D-267).
    final presentation = dashboardPresentation(
      state: stateAsync,
      sync: sync,
      principal: ref.watch(principalProvider),
    );
    final unauthorised =
        presentation is DashboardUnavailable &&
        presentation.reason == DashboardUnavailableReason.notAuthorised;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        key: const Key('dashboard-pull-to-refresh'),
        color: AppColors.brass,
        onRefresh: ref.read(dashboardSyncProvider.notifier).refresh,
        child: ListView(
          key: const Key('dashboard-home-page'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            dashboardMobileNavigationClearance,
          ),
          children: [
            _Header(presentation: presentation, sync: sync),
            const SizedBox(height: AppSpacing.md),
            // A reader without qualifying authority is offered no scope and no period:
            // this screen must not tell them which properties exist.
            if (!unauthorised) ...[
              const _ScopeSelector(),
              const SizedBox(height: AppSpacing.sm),
              _PeriodStrip(
                current: switch (presentation) {
                  DashboardAvailable(:final dashboard) =>
                    dashboard.pair.current,
                  _ => null,
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (stateAsync.hasError && presentation is DashboardLoading)
              _MessageCard(
                message: dashboardReadErrorMessage,
                actionLabel: 'Try again',
                onAction: () => ref.invalidate(dashboardViewProvider),
              )
            else
              _Body(presentation: presentation, sync: sync),
          ],
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.presentation, required this.sync});

  final DashboardPresentation presentation;
  final DashboardSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = sync.isRunning;
    final freshness = switch (presentation) {
      DashboardAvailable(:final dashboard) => dashboardFreshnessLine(
        dashboard,
        ref.watch(businessDayRulesProvider).value ?? const {},
      ),
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KRISHNA IMPERIAL MIS', style: AppTypography.overline),
                  const SizedBox(height: AppSpacing.xxs),
                  Text('Overview', style: AppTypography.heading),
                ],
              ),
            ),
            IconButton(
              key: const Key('dashboard-refresh'),
              tooltip: running ? 'Synchronising' : 'Refresh',
              onPressed: running
                  ? null
                  : () => ref.read(dashboardSyncProvider.notifier).refresh(),
              icon: running
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        if (freshness != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            freshness.text,
            key: freshness.key,
            style: freshness.caution
                ? AppTypography.caption.copyWith(color: AppColors.caution)
                : AppTypography.caption,
          ),
        ],
      ],
    );
  }
}

// ── Scope ────────────────────────────────────────────────────────────────────

class _ScopeSelector extends ConsumerWidget {
  const _ScopeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same provider the P&L reads, shown only to the person it was decided for, so a
    // dashboard cannot offer a property the P&L would refuse (D-267).
    final options = pnlScopeOptionsShownTo(
      ref.watch(pnlScopeOptionsProvider),
      ref.watch(principalProvider),
    );
    if (options == null || options.isEmpty) return const SizedBox.shrink();
    final selected =
        ref.watch(dashboardSelectionProvider).scope ?? options.defaultScope;
    final name = switch (selected) {
      PnlConsolidatedScope() => dashboardConsolidatedScopeLabel,
      PnlUnitScope(:final businessUnitId) =>
        options.units
                .where((u) => u.id == businessUnitId)
                .map((u) => u.name)
                .firstOrNull ??
            'Property not available to your account',
      null => 'No property',
    };

    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.allMedium,
        side: BorderSide(color: AppColors.hairline),
      ),
      child: InkWell(
        key: const Key('dashboard-scope-selector'),
        borderRadius: AppRadius.allMedium,
        onTap: () => _openSheet(context, ref, options, selected),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.apartment_outlined,
                size: 20,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PROPERTY', style: AppTypography.overline),
                    Text(
                      name,
                      key: const Key('dashboard-scope-name'),
                      style: AppTypography.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more, color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _openSheet(
    BuildContext context,
    WidgetRef ref,
    PnlScopeOptions options,
    PnlScopeChoice? selected,
  ) {
    final controller = ref.read(dashboardSelectionProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      // Over the whole screen, so no choice sits behind the bottom bar or the [ + ].
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadius.large),
      ),
      builder: (sheetContext) {
        Widget choice(PnlScopeChoice scope, String label, Key key) => ListTile(
          key: key,
          title: Text(label),
          selected: selected == scope,
          selectedColor: AppColors.ink,
          trailing: selected == scope
              ? const Icon(Icons.check, color: AppColors.brass)
              : null,
          onTap: () {
            controller.selectScope(scope);
            Navigator.pop(sheetContext);
          },
        );

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
            ),
            child: SingleChildScrollView(
              key: const Key('dashboard-scope-sheet'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      'Dashboard for',
                      style: AppTypography.subheading,
                    ),
                  ),
                  if (options.consolidatedAllowed)
                    choice(
                      const PnlConsolidatedScope(),
                      dashboardConsolidatedScopeLabel,
                      const Key('dashboard-scope-consolidated'),
                    ),
                  for (final unit in options.units)
                    choice(
                      PnlUnitScope(unit.id),
                      unit.name,
                      Key('dashboard-scope-${unit.id}'),
                    ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Periods ──────────────────────────────────────────────────────────────────

class _PeriodStrip extends ConsumerWidget {
  const _PeriodStrip({this.current});

  /// The period being reported, so the picker opens on it rather than on today.
  final ReportRange? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(dashboardSelectionProvider).period;
    final available =
        ref.watch(dashboardPeriodAvailabilityProvider).value ?? const {};
    final controller = ref.read(dashboardSelectionProvider.notifier);
    final someUnavailable = available.entries.any(
      (e) => e.key != DashboardPeriodKind.custom && !e.value,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          key: const Key('dashboard-period-bar'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final kind in DashboardPeriodKind.values)
                if (kind != DashboardPeriodKind.custom) ...[
                  ChoiceChip(
                    key: Key('dashboard-period-${kind.name}'),
                    label: Text(kind.label),
                    selected:
                        period is DashboardRelativePeriod &&
                        period.kind == kind,
                    onSelected: available[kind] == false
                        ? null
                        : (_) => controller.selectPeriod(kind),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ChoiceChip(
                key: const Key('dashboard-period-custom'),
                avatar: const Icon(Icons.date_range_outlined, size: 16),
                label: Text(DashboardPeriodKind.custom.label),
                selected: period is DashboardCustomPeriod,
                onSelected: (_) => _pickCustom(context, ref),
              ),
            ],
          ),
        ),
        if (period is DashboardCustomPeriod)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Custom: ${dashboardDateLabel(period.from)} – '
              '${dashboardDateLabel(period.to)}',
              key: const Key('dashboard-custom-range'),
              style: AppTypography.caption,
            ),
          ),
        if (someUnavailable)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Some periods are unavailable: the properties are on different business '
              'dates. Use Custom to choose the dates.',
              key: const Key('dashboard-periods-unavailable-note'),
              style: AppTypography.caption,
            ),
          ),
      ],
    );
  }

  Future<void> _pickCustom(BuildContext context, WidgetRef ref) async {
    final initial = dashboardPickerRange(
      ref.read(dashboardSelectionProvider).period,
      current: current,
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: initial,
      currentDate: initial?.end,
      // Calendar only: Android takes no typed dates (D-229, D-250).
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      useRootNavigator: true,
      helpText: 'Dashboard period',
      saveText: 'Apply',
    );
    final dates = dashboardCustomDatesFrom(picked);
    // Dismissed: the selection stays exactly as it was.
    if (dates == null || !context.mounted) return;
    ref
        .read(dashboardSelectionProvider.notifier)
        .selectCustom(dates.from, dates.to);
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

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
      return _MessageCard(
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
    return _Dashboard(
      ready: (presentation as DashboardAvailable).dashboard,
      sync: sync,
    );
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
    final cap = dashboardCapNote(ready.pair);
    final period = dashboardPeriodLine(ready.pair);
    final comparedWith = dashboardComparisonRangeLabel(ready.pair);
    final netSales = _seriesFor(view, TrendMeasure.netSales);

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
        if (cap != null)
          Text(
            cap,
            key: const Key('dashboard-comparison-capped'),
            style: AppTypography.caption,
          ),
        const SizedBox(height: AppSpacing.md),
        _Card(
          key: const Key('dashboard-headline'),
          children: [
            _MobileMetric(
              keyName: 'net-sales',
              label: 'Net Sales',
              amount: result.netSales,
              movement: dashboardMoneyMovement(view.comparison.netSales),
              comparedWith: comparedWith,
              secondary: _Secondary(gross: result.grossSales, gst: result.gst),
            ),
            const Divider(height: AppSpacing.lg, color: AppColors.hairline),
            _MobileMetric(
              keyName: 'expenses',
              label: 'Operating Expenses',
              amount: result.expenses,
              movement: dashboardMoneyMovement(view.comparison.expenses),
              comparedWith: comparedWith,
            ),
            const Divider(height: AppSpacing.lg, color: AppColors.hairline),
            _MobileMetric(
              keyName: 'operating',
              label: dashboardProfitLabel(result),
              amount: result.operatingProfit,
              emphasis: MoneyEmphasis.bySign,
              movement: dashboardMoneyMovement(view.comparison.operatingProfit),
              comparedWith: comparedWith,
            ),
            const Divider(height: AppSpacing.lg, color: AppColors.hairline),
            _MarginMetric(
              margin: result.margin.displayTwoDecimals,
              movement: dashboardMarginMovement(view.comparison.margin),
              previous: dashboardPreviousMarginLabel(view.comparison.margin),
              comparedWith: comparedWith,
            ),
          ],
        ),
        if (netSales != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _Card(
            key: const Key('dashboard-trend-net-sales'),
            children: [
              TrendLineChart(
                title: dashboardTrendTitle(netSales),
                periodLabel: period,
                data: dashboardTrendChartData(netSales),
              ),
            ],
          ),
        ],
        if (view.propertyComparison
            case final PropertyComparisonReady split) ...[
          const SizedBox(height: AppSpacing.lg),
          _PropertyComparison(split: split, period: period),
        ],
        if (view.topExpenseCategories
            case final TopNOutcome<ExpenseHierarchyLine> top) ...[
          const SizedBox(height: AppSpacing.lg),
          _TopExpenses(top: top, period: period, result: result),
        ],
        const SizedBox(height: AppSpacing.lg),
        const _SeeFullPnl(),
      ],
    );
  }

  TrendSeries? _seriesFor(DashboardView view, TrendMeasure measure) {
    for (final series in view.trends) {
      if (series.measure == measure) return series;
    }
    return null;
  }
}

// ── One headline figure ──────────────────────────────────────────────────────

/// Label and figure on one line, the movement under it.
///
/// A phone shape rather than the Overview's column: four stacked blocks would push the
/// last of them off a 740-high screen, and these four are exactly what a manager opens
/// this screen to see. The figure scales down rather than overflow a narrow phone, and is
/// never wrapped or truncated.
class _MobileMetric extends StatelessWidget {
  const _MobileMetric({
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
    ),
    movement: movement,
    comparedWith: comparedWith,
    secondary: secondary,
  );
}

/// The margin, with the previous one printed beside the movement so the three figures on
/// screen reconcile (D-264).
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 4,
                child: Text(label.toUpperCase(), style: AppTypography.overline),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                flex: 6,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: value,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            movement.available
                ? '${movement.text} · vs $comparedWith'
                : movement.text,
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
          if (secondary case final Widget extra) ...[
            const SizedBox(height: AppSpacing.xxs),
            extra,
          ],
        ],
      ),
    ),
  );
}

/// Gross Sales and GST, secondary to Net Sales rather than two more headline figures.
///
/// A [Wrap], so money is never ellipsised to fit a phone: the pair flows onto a second
/// line instead (the D-123 family, met on the Overview at 1366 and here at 360).
class _Secondary extends StatelessWidget {
  const _Secondary({required this.gross, required this.gst});

  final Money gross;
  final Money gst;

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

  /// A [Wrap] rather than a [Row], so the pair flows onto a second line instead of
  /// overflowing: at a raised system font scale on a 360dp phone the label and the
  /// figure together are wider than the card, and the figure is the half that may never
  /// be shortened (D-269, and the D-123 family again).
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
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

// ── Property comparison and the ranked section ──────────────────────────────

class _PropertyComparison extends ConsumerWidget {
  const _PropertyComparison({required this.split, required this.period});

  final PropertyComparisonReady split;
  final String period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(masterGraphProvider).value;
    return _Card(
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

class _TopExpenses extends ConsumerWidget {
  const _TopExpenses({
    required this.top,
    required this.period,
    required this.result,
  });

  final TopNOutcome<ExpenseHierarchyLine> top;
  final String period;
  final PnlResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(masterGraphProvider).value;
    final consolidated = result.isConsolidated;
    return _Card(
      key: const Key('dashboard-top-expenses'),
      children: [
        RankedBarChart(
          title: 'Top expense categories',
          periodLabel: period,
          data: RankedBarChartData.fromTopN<ExpenseHierarchyLine>(
            top,
            label: (line) => [
              if (consolidated) _propertyName(graph, line.businessUnitId),
              _expenseCategoryName(graph, line.categoryId),
            ].join(' · '),
          ),
        ),
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

// ── Through to the full profit & loss ───────────────────────────────────────

/// The one navigation on this screen (D-260).
///
/// It switches the shell to the Reports branch, which is a destination the phone already
/// has. It is **not** drill-down: opening a figure's transactions from a dashboard is
/// Slice 9's, and nothing here duplicates the P&L's own breakdown.
class _SeeFullPnl extends StatelessWidget {
  const _SeeFullPnl();

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('dashboard-see-full-pnl'),
    onPressed: () => StatefulNavigationShell.of(
      context,
    ).goBranch(AppRouter.mobileReportsBranch),
    icon: const Icon(Icons.insert_chart_outlined, size: 18),
    label: const Text('See full P&L'),
  );
}

// ── Building blocks ─────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.allMedium,
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

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.onAction, this.actionLabel});

  final DashboardMessage message;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel ?? message.action?.label;
    return Container(
      key: message.key,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.allMedium,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(message.icon, size: 28, color: AppColors.inkFaint),
          const SizedBox(height: AppSpacing.md),
          Text(
            message.title,
            style: AppTypography.subheading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message.message,
            style: AppTypography.bodyMuted,
            textAlign: TextAlign.center,
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
