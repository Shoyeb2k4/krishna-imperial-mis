/// The Windows Profit & Loss surface (Phase 5 Slice 8).
///
/// ## What this file does and does not do
///
/// It **formats**. Every figure arrives computed — primitives summed by the local engine
/// over the canonical reporting cache, and every derived figure from `Pnl.compute` in
/// `domain/finance` (D-020). It sums nothing, rounds no margin, reads no repository and
/// derives no business date; a structural guard fails the build if it starts to.
///
/// It **refuses** rather than rendering a zero it cannot stand behind: not authorised, not
/// downloaded, one side unavailable, or a preset the properties disagree about are each
/// their own screen, never ₹0 (D-163). The wording of every such screen is shared with the
/// Android surface (`pnl_presentation.dart`), so the two cannot describe one report
/// differently.
///
/// Category lines are shown only when the domain result says they reconcile exactly with
/// the headline; the totals shown under them are the headline figures themselves.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/components/section_header.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_view.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_presentation.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

class ProfitAndLossPage extends ConsumerStatefulWidget {
  const ProfitAndLossPage({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  ConsumerState<ProfitAndLossPage> createState() => _ProfitAndLossPageState();
}

class _ProfitAndLossPageState extends ConsumerState<ProfitAndLossPage> {
  @override
  void initState() {
    super.initState();
    // Render what the cache already holds, then bring it up to date. Once per session on
    // opening; Refresh repeats it on demand.
    pnlRefreshWhenOpened(ref, () => mounted);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = widget.shellKind == AppShellKind.desktop;
    final density = desktop ? AppDensity.compact : AppDensity.comfortable;
    final viewAsync = ref.watch(pnlViewProvider);
    // Only a report computed for the person signed in now (D-074).
    final view = pnlViewShownTo(viewAsync, ref.watch(principalProvider));
    final sync = ref.watch(pnlSyncProvider);
    final drill = ref.watch(pnlDrillProvider);

    // A drill-down is shown only over the exact report it was opened from: the same person,
    // the same properties and the same P&L dates (Slice 10).
    if (drill != null &&
        view is PnlReportView &&
        view.envelope.isComputed &&
        PnlDrillAnchor.of(view) == drill.location.anchor) {
      return _DrillLayout(
        view: view,
        drill: drill,
        sync: sync,
        density: density,
      );
    }

    return ListView(
      key: const Key('pnl-page'),
      padding: EdgeInsets.all(density.pagePadding),
      children: [
        SectionHeader(
          eyebrow: 'Analytics',
          title: 'Profit & Loss',
          trailing: _RefreshControl(sync: sync),
        ),
        const _ScopeBar(),
        const SizedBox(height: AppSpacing.sm),
        const _PeriodBar(),
        const SizedBox(height: AppSpacing.md),
        // A rebuild keeps the previous report on screen while it re-reads, rather than
        // flashing to a spinner every time a synchronisation lands.
        if (view case final value?)
          _Body(view: value, sync: sync)
        else if (viewAsync.hasError)
          _Message(
            message: pnlReadErrorMessage,
            onAction: () {
              retryFailedReportInputs(ref.exists, ref.read, ref.invalidate);
              ref.invalidate(pnlViewProvider);
            },
            actionLabel: 'Try again',
          )
        else
          const _Loading(),
      ],
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _Body extends ConsumerWidget {
  const _Body({required this.view, required this.sync});

  final PnlView view;
  final PnlSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = pnlStateMessage(
      view,
      sync,
      canAsk: ref.watch(reportingSyncProvider) != null,
    );
    if (message != null) {
      final controller = ref.read(pnlSyncProvider.notifier);
      return _Message(
        message: message,
        onAction: switch (message.action) {
          PnlMessageAction.synchronise => controller.refresh,
          PnlMessageAction.download ||
          PnlMessageAction.retryDownload => controller.download,
          null => null,
        },
      );
    }
    final report = view as PnlReportView;
    return _Statement(
      view: report,
      result: (report.envelope.outcome as PnlComputed).result,
      sync: sync,
    );
  }
}

// ── The drill-down ───────────────────────────────────────────────────────────

/// A level of the breakdown in a pane, with the selected document beside it (Slice 10).
///
/// Scope, period, refresh and freshness stay on screen: changing either of the first two
/// closes the drill-down, and the freshness line is the report's own. The document is the
/// immutable body with nothing composed into it.
class _DrillLayout extends ConsumerWidget {
  const _DrillLayout({
    required this.view,
    required this.drill,
    required this.sync,
    required this.density,
  });

  final PnlReportView view;
  final PnlDrillState drill;
  final PnlSyncStatus sync;
  final AppDensity density;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(pnlDrillProvider.notifier);
    final notice = pnlSyncNotice(sync);
    final freshness = pnlFreshnessLine(
      view,
      ref.watch(businessDayRulesProvider).value ?? const {},
    );
    final selected = drill.selected;

    return Padding(
      key: const Key('pnl-drill-layout'),
      padding: EdgeInsets.all(density.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            eyebrow: 'Analytics',
            title: 'Profit & Loss',
            trailing: _RefreshControl(sync: sync),
          ),
          const _ScopeBar(),
          const SizedBox(height: AppSpacing.sm),
          const _PeriodBar(),
          const SizedBox(height: AppSpacing.sm),
          if (notice != null) _Notice(notice: notice),
          Text(
            '${pnlRangeLabel(view.range)} · ${freshness.text}',
            key: freshness.key,
            style: freshness.caution
                ? AppTypography.caption.copyWith(color: AppColors.caution)
                : AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.xs),
          PnlDrillBreadcrumb(
            location: drill.location,
            onReport: controller.close,
            onOpen: controller.open,
          ),
          const Divider(height: AppSpacing.md, color: AppColors.hairline),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: PnlDrillLevelList(
                    location: drill.location,
                    selected: selected,
                    onOpen: controller.open,
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
                        Expanded(child: PnlDocumentDetail(request: selected)),
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

// ── The statement ────────────────────────────────────────────────────────────

class _Statement extends ConsumerWidget {
  const _Statement({
    required this.view,
    required this.result,
    required this.sync,
  });

  final PnlReportView view;
  final PnlResult result;
  final PnlSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loss = result.operatingProfit.isNegative;
    final noTrade =
        result.revenueContributions == 0 && result.expenseContributions == 0;
    final notice = pnlSyncNotice(sync);
    final freshness = pnlFreshnessLine(
      view,
      ref.watch(businessDayRulesProvider).value ?? const {},
    );

    return Column(
      key: const Key('pnl-statement'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) _Notice(notice: notice),
        Text(
          freshness.text,
          key: freshness.key,
          style: freshness.caution
              ? AppTypography.caption.copyWith(color: AppColors.caution)
              : AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        _Panel(
          key: const Key('pnl-headline'),
          children: [
            Text(
              'PROFIT & LOSS · ${pnlRangeLabel(view.range)}',
              style: AppTypography.overline,
            ),
            const SizedBox(height: AppSpacing.sm),
            _Row(
              label: 'Gross Sales',
              amount: result.grossSales,
              keyName: 'pnl-gross',
            ),
            _Row(label: 'Less GST', amount: result.gst, keyName: 'pnl-gst'),
            _Row(
              label: 'Net Sales',
              amount: result.netSales,
              keyName: 'pnl-net',
              strong: true,
            ),
            _Row(
              label: 'Less Expenses',
              amount: result.expenses,
              keyName: 'pnl-expenses',
            ),
            const Divider(height: AppSpacing.lg, color: AppColors.hairline),
            _Row(
              label: loss ? 'Operating Loss' : 'Operating Profit',
              labelKey: 'pnl-operating-label',
              amount: result.operatingProfit,
              keyName: 'pnl-operating-result',
              strong: true,
              bySign: true,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Operating Margin',
                      style: AppTypography.bodyMuted,
                    ),
                  ),
                  Text(
                    result.margin.displayTwoDecimals,
                    key: const Key('pnl-margin'),
                    style: AppTypography.money,
                  ),
                ],
              ),
            ),
            if (noTrade)
              Text(
                'No accepted transactions in this period.',
                key: const Key('pnl-no-trade'),
                style: AppTypography.caption,
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Accrual basis: figures are attributed by P&L date. Only server-accepted, '
              'non-voided transactions are included. Expenses are gross cost including GST.',
              key: const Key('pnl-basis'),
              style: AppTypography.caption,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (result.breakdownReconciles) ...[
          _RevenueCategories(view: view, result: result),
          const SizedBox(height: AppSpacing.lg),
          _ExpenseCategories(view: view, result: result),
        ] else
          const _Message(
            message: PnlStateMessage(
              key: Key('pnl-breakdown-unreconciled'),
              icon: Icons.rule_outlined,
              title: 'Category breakdown not shown',
              message:
                  'The category lines on this device do not add up exactly to the totals '
                  'above, so they are not shown. Refresh to synchronise again.',
            ),
          ),
      ],
    );
  }
}

class _RevenueCategories extends ConsumerWidget {
  const _RevenueCategories({required this.view, required this.result});

  final PnlReportView view;
  final PnlResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(masterGraphProvider).value;
    final consolidated = result.isConsolidated;
    final lines = pnlRevenueLinesInOrder(result);
    final anchor = PnlDrillAnchor.of(view);
    final drill = ref.read(pnlDrillProvider.notifier);

    return _Panel(
      key: const Key('pnl-revenue-categories'),
      children: [
        Text('REVENUE BY CATEGORY', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        const _ColumnHeads(labels: ['Gross', 'GST', 'Net']),
        if (lines.isEmpty)
          Text('No revenue in this period.', style: AppTypography.caption),
        for (final line in lines)
          InkWell(
            key: Key(
              'pnl-rev-open-${line.businessUnitId}-${line.revenueCategoryId}',
            ),
            onTap: () => drill.open(
              PnlRevenueDocumentsAt(
                anchor,
                businessUnitId: line.businessUnitId,
                revenueCategoryId: line.revenueCategoryId,
              ),
            ),
            child: _Columns(
              keyPrefix:
                  'pnl-rev-${line.businessUnitId}-${line.revenueCategoryId}',
              label:
                  graph?.revenueCategory(line.revenueCategoryId)?.name ??
                  'Revenue category not on this device',
              detail: [
                if (consolidated)
                  graph?.businessUnit(line.businessUnitId)?.name ?? 'Property',
                if (line.treatment == TaxTreatment.none) 'No GST',
              ].join(' · '),
              amounts: [line.totals.gross, line.totals.tax, line.totals.net],
            ),
          ),
        const Divider(height: AppSpacing.md, color: AppColors.hairline),
        // The totals are the headline figures, which the domain has confirmed these lines
        // reconcile to. Nothing is summed here.
        _Columns(
          keyPrefix: 'pnl-rev-total',
          label: 'Total',
          strong: true,
          amounts: [result.grossSales, result.gst, result.netSales],
        ),
      ],
    );
  }
}

class _ExpenseCategories extends ConsumerWidget {
  const _ExpenseCategories({required this.view, required this.result});

  final PnlReportView view;
  final PnlResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(masterGraphProvider).value;
    final consolidated = result.isConsolidated;
    final lines = pnlExpenseLinesInOrder(result);
    final anchor = PnlDrillAnchor.of(view);
    final drill = ref.read(pnlDrillProvider.notifier);

    return _Panel(
      key: const Key('pnl-expense-categories'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'EXPENSES BY CATEGORY',
                style: AppTypography.overline,
              ),
            ),
            TextButton(
              key: const Key('pnl-exp-by-department'),
              onPressed: () => drill.open(PnlExpenseDepartmentsAt(anchor)),
              child: const Text('By department'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const _ColumnHeads(labels: ['Amount']),
        if (lines.isEmpty)
          Text('No expenses in this period.', style: AppTypography.caption),
        for (final line in lines)
          InkWell(
            key: Key('pnl-exp-open-${line.businessUnitId}-${line.categoryId}'),
            // A shortcut to the exact Department + Section + Category bucket.
            onTap:
                line.departmentId == null ||
                    line.sectionId == null ||
                    line.categoryId == null
                ? null
                : () => drill.open(
                    PnlExpenseDocumentsAt(
                      anchor,
                      businessUnitId: line.businessUnitId,
                      departmentId: line.departmentId!,
                      sectionId: line.sectionId!,
                      categoryId: line.categoryId!,
                    ),
                  ),
            child: _Columns(
              keyPrefix: 'pnl-exp-${line.businessUnitId}-${line.categoryId}',
              label: switch (line.categoryId) {
                final String id =>
                  graph?.expenseCategory(id)?.name ??
                      'Expense category not on this device',
                null => 'Uncategorised',
              },
              detail: [
                if (consolidated)
                  graph?.businessUnit(line.businessUnitId)?.name ?? 'Property',
                if (line.departmentId case final String id)
                  graph?.department(id)?.name ?? 'Department',
                if (line.sectionId case final String id)
                  graph?.section(id)?.name ?? 'Section',
              ].join(' · '),
              amounts: [line.totals.amount],
            ),
          ),
        const Divider(height: AppSpacing.md, color: AppColors.hairline),
        _Columns(
          keyPrefix: 'pnl-exp-total',
          label: 'Total',
          strong: true,
          amounts: [result.expenses],
        ),
      ],
    );
  }
}

// ── Synchronisation ─────────────────────────────────────────────────────────

class _RefreshControl extends ConsumerWidget {
  const _RefreshControl({required this.sync});

  final PnlSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = sync.isRunning;
    return TextButton.icon(
      key: const Key('pnl-refresh'),
      onPressed: running
          ? null
          : () => ref.read(pnlSyncProvider.notifier).refresh(),
      icon: running
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh, size: 16),
      label: Text(
        running
            ? (sync.phase == PnlSyncPhase.downloading
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
    final options = pnlScopeOptionsShownTo(
      ref.watch(pnlScopeOptionsProvider),
      ref.watch(principalProvider),
    );
    if (options == null || options.isEmpty) return const SizedBox.shrink();
    final selected =
        ref.watch(pnlSelectionProvider).scope ?? options.defaultScope;
    final controller = ref.read(pnlSelectionProvider.notifier);

    return Wrap(
      key: const Key('pnl-scope-bar'),
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        if (options.consolidatedAllowed)
          ChoiceChip(
            key: const Key('pnl-scope-consolidated'),
            label: const Text('Both properties (consolidated)'),
            selected: selected == const PnlConsolidatedScope(),
            onSelected: (_) =>
                controller.selectScope(const PnlConsolidatedScope()),
          ),
        for (final unit in options.units)
          ChoiceChip(
            key: Key('pnl-scope-${unit.id}'),
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
    final from = BusinessDate.tryParse(_from.text.trim());
    final to = BusinessDate.tryParse(_to.text.trim());
    if (from == null || to == null) {
      setState(() => _error = 'Enter both dates as YYYY-MM-DD.');
      return;
    }
    setState(() => _error = null);
    ref.read(pnlSelectionProvider.notifier).selectCustom(from, to);
  }

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(pnlSelectionProvider).period;
    final available =
        ref.watch(pnlPresetAvailabilityProvider).value ?? const {};
    final controller = ref.read(pnlSelectionProvider.notifier);
    final customSelected = period is PnlCustomPeriod || _editingCustom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          key: const Key('pnl-period-bar'),
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final preset in RelativePreset.values)
              Tooltip(
                message: available[preset] == false
                    ? 'The properties are on different business dates. Use Custom.'
                    : '',
                child: ChoiceChip(
                  key: Key('pnl-preset-${preset.name}'),
                  label: Text(preset.label),
                  selected:
                      !customSelected &&
                      period is PnlPresetPeriod &&
                      period.preset == preset,
                  onSelected: available[preset] == false
                      ? null
                      : (_) {
                          setState(() => _editingCustom = false);
                          controller.selectPreset(preset);
                        },
                ),
              ),
            ChoiceChip(
              key: const Key('pnl-preset-custom'),
              label: const Text('Custom'),
              selected: customSelected,
              onSelected: (_) => setState(() {
                _editingCustom = true;
                if (period is PnlCustomPeriod) {
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
                  key: const Key('pnl-custom-from'),
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
                  key: const Key('pnl-custom-to'),
                  controller: _to,
                  decoration: const InputDecoration(
                    labelText: 'To (YYYY-MM-DD)',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
              FilledButton(
                key: const Key('pnl-custom-apply'),
                onPressed: _apply,
                child: const Text('Apply'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('pnl-custom-error'),
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

// ── Building blocks ──────────────────────────────────────────────────────────

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
      children: children,
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.amount,
    required this.keyName,
    this.labelKey,
    this.strong = false,
    this.bySign = false,
  });

  final String label;
  final Money amount;
  final String keyName;
  final String? labelKey;
  final bool strong;
  final bool bySign;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            key: labelKey == null ? null : Key(labelKey!),
            style: (strong ? AppTypography.body : AppTypography.bodyMuted)
                .copyWith(fontWeight: strong ? FontWeight.w600 : null),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        MoneyText(
          amount,
          key: Key(keyName),
          style: strong ? AppTypography.moneyStrong : AppTypography.money,
          emphasis: bySign ? MoneyEmphasis.bySign : MoneyEmphasis.neutral,
          semanticPrefix: label,
        ),
      ],
    ),
  );
}

/// Width of one right-aligned amount column, in logical pixels.
const _amountColumn = 140.0;

class _ColumnHeads extends StatelessWidget {
  const _ColumnHeads({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      children: [
        const Expanded(child: SizedBox.shrink()),
        for (final label in labels)
          SizedBox(
            width: _amountColumn,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: AppTypography.caption,
            ),
          ),
      ],
    ),
  );
}

class _Columns extends StatelessWidget {
  const _Columns({
    required this.keyPrefix,
    required this.label,
    required this.amounts,
    this.detail = '',
    this.strong = false,
  });

  final String keyPrefix;
  final String label;
  final String detail;
  final List<Money> amounts;
  final bool strong;

  static const _suffixes = {
    1: ['amount'],
    3: ['gross', 'gst', 'net'],
  };

  @override
  Widget build(BuildContext context) {
    final suffixes = _suffixes[amounts.length]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: (strong ? AppTypography.body : AppTypography.bodyMuted)
                      .copyWith(fontWeight: strong ? FontWeight.w600 : null),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption,
                  ),
              ],
            ),
          ),
          for (var i = 0; i < amounts.length; i++)
            SizedBox(
              width: _amountColumn,
              child: MoneyText(
                amounts[i],
                key: Key('$keyPrefix-${suffixes[i]}'),
                style: strong ? AppTypography.moneyStrong : AppTypography.money,
                semanticPrefix: '$label ${suffixes[i]}',
              ),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.notice});

  final PnlNotice notice;

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

  final PnlStateMessage message;
  final VoidCallback? onAction;

  /// Overrides the label the message's action carries, for actions it does not name.
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
    key: Key('pnl-loading'),
    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Center(
      child: SizedBox.square(
        dimension: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}
