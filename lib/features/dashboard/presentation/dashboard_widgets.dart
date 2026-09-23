/// The Windows building blocks a dashboard surface is arranged from (Phase 6 Slice 8).
///
/// Slice 6 wrote these privately inside the Overview. Slice 8's Analytics workspace needs
/// the same scope bar, period bar, refresh control, state messages, headline metrics and
/// panels over the **same** providers, so they live here once rather than as a copy that
/// reads the same today — the drift D-119, D-131 and D-232 each record. Every key is the
/// one Slice 6 shipped, so nothing that finds them had to change.
///
/// ## What this file does not do
///
/// It computes no figure, decides no authority, derives no business date and ranks
/// nothing. A metric is handed its [Money] and the movement `domain/finance` decided; a
/// ranked name is looked up by id; the scope bar offers the P&L's own qualifying scopes
/// ([pnlScopeOptionsShownTo]); the period bar hands two typed dates to the planner and
/// never swaps them. The dashboard surface guard holds all of that over this file too.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

/// Below this an analytical grid collapses to one column. A 1366-wide window beside the
/// 240-pixel sidebar leaves about 1,100, which is comfortably two.
const dashboardTwoColumnWidth = 980.0;

/// Below this four headline figures stop sitting on one line.
const dashboardFourAcrossWidth = 860.0;
const dashboardTwoAcrossWidth = 460.0;

// ── Names, looked up by id ──────────────────────────────────────────────────

String dashboardPropertyName(MasterGraph? graph, String id) =>
    graph?.businessUnit(id)?.name ?? 'Property not on this device';

String dashboardRevenueCategoryName(MasterGraph? graph, String id) =>
    graph?.revenueCategory(id)?.name ?? 'Revenue category not on this device';

String dashboardExpenseCategoryName(MasterGraph? graph, String? id) =>
    switch (id) {
      final String value =>
        graph?.expenseCategory(value)?.name ??
            'Expense category not on this device',
      null => 'Uncategorised',
    };

String dashboardDepartmentName(MasterGraph? graph, String? id) => switch (id) {
  final String value =>
    graph?.department(value)?.name ?? 'Department not on this device',
  null => 'Unassigned',
};

// ── Synchronisation ─────────────────────────────────────────────────────────

class DashboardRefreshControl extends ConsumerWidget {
  const DashboardRefreshControl({required this.sync, super.key});

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

class DashboardScopeBar extends ConsumerWidget {
  const DashboardScopeBar({super.key});

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

class DashboardPeriodBar extends ConsumerStatefulWidget {
  const DashboardPeriodBar({super.key});

  @override
  ConsumerState<DashboardPeriodBar> createState() => _DashboardPeriodBarState();
}

class _DashboardPeriodBarState extends ConsumerState<DashboardPeriodBar> {
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

// ── What is said above the figures ──────────────────────────────────────────

/// The refresh notice, the period, the freshness claim and the comparison cap, in the
/// order Slice 6 shipped them.
class DashboardStatusLines extends ConsumerWidget {
  const DashboardStatusLines({
    required this.ready,
    required this.sync,
    super.key,
  });

  final DashboardReady ready;
  final DashboardSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = dashboardNoticeFor(sync);
    final freshness = dashboardFreshnessLine(
      ready,
      ref.watch(businessDayRulesProvider).value ?? const {},
    );
    final cap = dashboardCapNote(ready.pair);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (notice != null) DashboardNoticeLine(notice: notice),
        Text(
          dashboardPeriodLine(ready.pair),
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
      ],
    );
  }
}

// ── Headline metrics ────────────────────────────────────────────────────────

/// Gross Sales and GST, secondary to Net Sales. The canonical result's own figures, so
/// they reconcile with it by construction: Gross = GST + Net.
class DashboardGrossAndGst extends StatelessWidget {
  const DashboardGrossAndGst({
    required this.gross,
    required this.gst,
    super.key,
  });

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
///
/// Its keys are `dashboard-$keyName-value`, `dashboard-$keyName-movement` and
/// `dashboard-kpi-$keyName`, so two surfaces showing the same measure name it apart by
/// [keyName] alone.
class DashboardMoneyMetric extends StatelessWidget {
  const DashboardMoneyMetric({
    required this.keyName,
    required this.label,
    required this.amount,
    required this.movement,
    required this.comparedWith,
    this.emphasis = MoneyEmphasis.neutral,
    this.secondary,
    super.key,
  });

  final String keyName;
  final String label;
  final Money amount;
  final MoneyEmphasis emphasis;
  final DashboardMovement movement;
  final String comparedWith;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) => DashboardMetricShell(
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
class DashboardMarginMetric extends StatelessWidget {
  const DashboardMarginMetric({
    required this.margin,
    required this.movement,
    required this.previous,
    required this.comparedWith,
    this.keyName = 'margin',
    super.key,
  });

  final String keyName;
  final String margin;
  final DashboardMovement movement;
  final String previous;
  final String comparedWith;

  @override
  Widget build(BuildContext context) => DashboardMetricShell(
    keyName: keyName,
    label: 'Operating Margin',
    semantics:
        'Operating Margin. $margin. '
        '${movement.semanticsWith(comparedWith)}'
        '${movement.available ? ' Previous $previous.' : ''}',
    value: Text(
      margin,
      key: Key('dashboard-$keyName-value'),
      style: AppTypography.metric,
    ),
    movement: movement,
    comparedWith: comparedWith,
    secondary: movement.available
        ? Text(
            'Previous $previous',
            key: Key('dashboard-$keyName-previous'),
            style: AppTypography.caption,
          )
        : null,
  );
}

class DashboardMetricShell extends StatelessWidget {
  const DashboardMetricShell({
    required this.keyName,
    required this.label,
    required this.semantics,
    required this.value,
    required this.movement,
    required this.comparedWith,
    this.secondary,
    super.key,
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

// ── Layout ──────────────────────────────────────────────────────────────────

/// [children] laid out in [across] columns of equal width, wrapping into rows.
///
/// A grid rather than a `Wrap` of fixed widths, so a narrower window narrows the columns
/// instead of pushing the last one off the page.
class DashboardGrid extends StatelessWidget {
  const DashboardGrid({
    required this.across,
    required this.children,
    super.key,
  });

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

class DashboardPanel extends StatelessWidget {
  const DashboardPanel({required this.children, super.key});

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

// ── States ──────────────────────────────────────────────────────────────────

class DashboardNoticeLine extends StatelessWidget {
  const DashboardNoticeLine({required this.notice, super.key});

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

class DashboardMessageView extends StatelessWidget {
  const DashboardMessageView({
    required this.message,
    this.onAction,
    this.actionLabel,
    super.key,
  });

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

class DashboardLoadingView extends StatelessWidget {
  const DashboardLoadingView({super.key});

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

/// The message in place of a dashboard, with its one action bound to the synchroniser —
/// or null when [presentation] is a dashboard to be drawn as figures.
Widget? dashboardStateView(
  WidgetRef ref,
  DashboardPresentation presentation,
  DashboardSyncStatus sync,
) {
  if (presentation is DashboardLoading) return const DashboardLoadingView();
  final message = dashboardMessageFor(
    presentation,
    sync,
    canAsk: ref.watch(reportingSyncProvider) != null,
  );
  if (message == null) return null;
  final controller = ref.read(dashboardSyncProvider.notifier);
  return DashboardMessageView(
    message: message,
    onAction: switch (message.action) {
      DashboardMessageAction.synchronise => controller.refresh,
      DashboardMessageAction.download ||
      DashboardMessageAction.retryDownload => controller.download,
      null => null,
    },
  );
}
