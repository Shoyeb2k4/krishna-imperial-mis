/// The Android Profit & Loss surface (Phase 5 Slice 9).
///
/// The Reports tab opens here directly: V1 has one standard reporting surface, so there is
/// no reports menu in front of it. Owner settlement stays on its own private surface.
///
/// ## A phone presentation of the same report, not a second P&L
///
/// Scope, period, authority, coverage, freshness and every figure come from the same
/// providers the Windows surface reads (`pnl_providers.dart`), and every message from the
/// same wording (`pnl_presentation.dart`). This file only arranges them for a portrait
/// phone: the scope in a bottom sheet, the periods in a horizontal strip, Custom through
/// the Material date-range picker, and the figures stacked rather than columned. It sums
/// nothing, rounds no margin, derives no business date and reads no repository; the same
/// structural guard as the Windows page holds it to that.
///
/// ## Custom dates
///
/// Chosen on a calendar only — no typed date entry. The tapped calendar days are the
/// explicit P&L dates, read by year, month and day and never converted through a timezone,
/// UTC or the device clock (`pnlCustomDatesFrom`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/core/design/components/figure_reflow.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_pnl_drilldown_pages.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_presentation.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:krishna_mis/features/export/pnl_share_action.dart';

/// Space kept clear under the last item, so nothing sits behind the docked [ + ] action.
///
/// The action is 56 logical pixels and docks half its height above the bottom bar; the
/// rest is breathing room so the last line is readable with the action beside it.
const pnlMobileNavigationClearance = 96.0;

class MobileProfitAndLossPage extends ConsumerStatefulWidget {
  const MobileProfitAndLossPage({super.key});

  @override
  ConsumerState<MobileProfitAndLossPage> createState() =>
      _MobileProfitAndLossPageState();
}

class _MobileProfitAndLossPageState
    extends ConsumerState<MobileProfitAndLossPage> {
  @override
  void initState() {
    super.initState();
    // Render what the cache already holds, then bring it up to date.
    pnlRefreshWhenOpened(ref, () => mounted);
  }

  @override
  Widget build(BuildContext context) {
    // A new person on the same installation starts a fresh refresh of their own.
    ref.listen(principalProvider.select((p) => p.userId), (previous, next) {
      if (previous != next) pnlRefreshWhenOpened(ref, () => mounted);
    });

    final viewAsync = ref.watch(pnlViewProvider);
    // Only a report computed for the person signed in now (D-074).
    final view = pnlViewShownTo(viewAsync, ref.watch(principalProvider));
    final sync = ref.watch(pnlSyncProvider);
    final controller = ref.read(pnlSyncProvider.notifier);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        key: const Key('pnl-pull-to-refresh'),
        color: AppColors.brass,
        onRefresh: controller.refresh,
        child: ListView(
          key: const Key('pnl-page'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            pnlMobileNavigationClearance,
          ),
          children: [
            _Header(view: view, sync: sync),
            const SizedBox(height: AppSpacing.md),
            const _ScopeSelector(),
            const SizedBox(height: AppSpacing.sm),
            _PresetStrip(view: view),
            const SizedBox(height: AppSpacing.md),
            if (view case final value?)
              _Body(view: value, sync: sync)
            else if (viewAsync.hasError)
              _MessageCard(
                message: pnlReadErrorMessage,
                actionLabel: 'Try again',
                onAction: () {
                  retryFailedReportInputs(ref.exists, ref.read, ref.invalidate);
                  ref.invalidate(pnlViewProvider);
                },
              )
            else
              const _Loading(),
          ],
        ),
      ),
    );
  }
}

// ── Header: title and freshness ──────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header({required this.view, required this.sync});

  final PnlView? view;
  final PnlSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = sync.isRunning;
    final current = view;
    final freshness = current is PnlReportView && current.envelope.isComputed
        ? pnlFreshnessLine(
            current,
            ref.watch(businessDayRulesProvider).value ?? const {},
          )
        : null;

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
                  Text('REPORTS', style: AppTypography.overline),
                  const SizedBox(height: AppSpacing.xxs),
                  Text('Profit & Loss', style: AppTypography.heading),
                ],
              ),
            ),
            // The phone P&L's one export control (Phase 7 Slice 8, D-293). It decides
            // for itself whether it is offered, and shows nothing when it is not.
            const PnlShareAction(),
            IconButton(
              key: const Key('pnl-refresh'),
              tooltip: running ? 'Synchronising' : 'Refresh',
              onPressed: running
                  ? null
                  : () => ref.read(pnlSyncProvider.notifier).refresh(),
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
    final options = pnlScopeOptionsShownTo(
      ref.watch(pnlScopeOptionsProvider),
      ref.watch(principalProvider),
    );
    if (options == null || options.isEmpty) return const SizedBox.shrink();
    final selected =
        ref.watch(pnlSelectionProvider).scope ?? options.defaultScope;
    final name = switch (selected) {
      PnlConsolidatedScope() => 'Both properties (consolidated)',
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
        key: const Key('pnl-scope-selector'),
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
                      key: const Key('pnl-scope-name'),
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
    final controller = ref.read(pnlSelectionProvider.notifier);
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
              key: const Key('pnl-scope-sheet'),
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
                    child: Text('Report on', style: AppTypography.subheading),
                  ),
                  if (options.consolidatedAllowed)
                    choice(
                      const PnlConsolidatedScope(),
                      'Both properties (consolidated)',
                      const Key('pnl-scope-consolidated'),
                    ),
                  for (final unit in options.units)
                    choice(
                      PnlUnitScope(unit.id),
                      unit.name,
                      Key('pnl-scope-${unit.id}'),
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

class _PresetStrip extends ConsumerWidget {
  const _PresetStrip({required this.view});

  final PnlView? view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(pnlSelectionProvider).period;
    final available =
        ref.watch(pnlPresetAvailabilityProvider).value ?? const {};
    final controller = ref.read(pnlSelectionProvider.notifier);
    final someUnavailable = available.values.any((a) => !a);
    final current = view;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          key: const Key('pnl-period-bar'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final preset in RelativePreset.values) ...[
                ChoiceChip(
                  key: Key('pnl-preset-${preset.name}'),
                  label: Text(preset.label),
                  selected:
                      period is PnlPresetPeriod && period.preset == preset,
                  onSelected: available[preset] == false
                      ? null
                      : (_) => controller.selectPreset(preset),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              ChoiceChip(
                key: const Key('pnl-preset-custom'),
                avatar: const Icon(Icons.date_range_outlined, size: 16),
                label: const Text('Custom'),
                selected: period is PnlCustomPeriod,
                onSelected: (_) => _pickCustom(context, ref, current),
              ),
            ],
          ),
        ),
        if (period is PnlCustomPeriod)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Custom: ${pnlDateLabel(period.from)} – ${pnlDateLabel(period.to)}',
              key: const Key('pnl-custom-range'),
              style: AppTypography.caption,
            ),
          ),
        if (someUnavailable)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Some periods are unavailable: the properties are on different business '
              'dates. Use Custom to choose the dates.',
              key: const Key('pnl-presets-unavailable-note'),
              style: AppTypography.caption,
            ),
          ),
      ],
    );
  }

  Future<void> _pickCustom(
    BuildContext context,
    WidgetRef ref,
    PnlView? current,
  ) async {
    final period = ref.read(pnlSelectionProvider).period;
    // Open on the custom range already chosen, otherwise on the period being reported.
    final (from, to) = switch ((period, current)) {
      (PnlCustomPeriod(:final from, :final to), _) => (from, to),
      (_, PnlReportView(:final range)) => (range.from, range.to),
      _ => (null, null),
    };
    final initial = from != null && to != null && from <= to
        ? DateTimeRange(start: pnlCalendarDay(from), end: pnlCalendarDay(to))
        : null;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: initial,
      currentDate: initial?.end,
      // Calendar only: Android takes no typed dates.
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      useRootNavigator: true,
      helpText: 'Profit & loss period',
      saveText: 'Apply',
    );
    final dates = pnlCustomDatesFrom(picked);
    // Dismissed: the selection stays exactly as it was.
    if (dates == null || !context.mounted) return;
    ref.read(pnlSelectionProvider.notifier).selectCustom(dates.from, dates.to);
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
      return _MessageCard(
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

class _Statement extends StatelessWidget {
  const _Statement({
    required this.view,
    required this.result,
    required this.sync,
  });

  final PnlReportView view;
  final PnlResult result;
  final PnlSyncStatus sync;

  @override
  Widget build(BuildContext context) {
    final loss = result.operatingProfit.isNegative;
    final noTrade =
        result.revenueContributions == 0 && result.expenseContributions == 0;
    final notice = pnlSyncNotice(sync);

    return Column(
      key: const Key('pnl-statement'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) _Notice(notice: notice),
        _Card(
          key: const Key('pnl-headline'),
          children: [
            Text(
              'PROFIT & LOSS · ${pnlRangeLabel(view.range)}',
              style: AppTypography.overline,
            ),
            const SizedBox(height: AppSpacing.sm),
            _Figure(
              label: 'Gross Sales',
              amount: result.grossSales,
              keyName: 'pnl-gross',
            ),
            _Figure(label: 'Less GST', amount: result.gst, keyName: 'pnl-gst'),
            _Figure(
              label: 'Net Sales',
              amount: result.netSales,
              keyName: 'pnl-net',
              strong: true,
            ),
            _Figure(
              label: 'Less Expenses',
              amount: result.expenses,
              keyName: 'pnl-expenses',
            ),
            const Divider(height: AppSpacing.lg, color: AppColors.hairline),
            _Figure(
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
          const _MessageCard(
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

    return _Card(
      key: const Key('pnl-revenue-categories'),
      children: [
        Text('REVENUE BY CATEGORY', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        if (lines.isEmpty)
          Text('No revenue in this period.', style: AppTypography.caption),
        for (final line in lines)
          InkWell(
            key: Key(
              'pnl-rev-open-${line.businessUnitId}-${line.revenueCategoryId}',
            ),
            onTap: () => pushPnlDrillLevel(
              context,
              PnlRevenueDocumentsAt(
                anchor,
                businessUnitId: line.businessUnitId,
                revenueCategoryId: line.revenueCategoryId,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LineTitle(
                  label:
                      graph?.revenueCategory(line.revenueCategoryId)?.name ??
                      'Revenue category not on this device',
                  detail: [
                    if (consolidated)
                      graph?.businessUnit(line.businessUnitId)?.name ??
                          'Property',
                    if (line.treatment == TaxTreatment.none) 'No GST',
                  ].join(' · '),
                ),
                for (final (label, suffix, amount) in [
                  ('Gross', 'gross', line.totals.gross),
                  ('GST', 'gst', line.totals.tax),
                  ('Net', 'net', line.totals.net),
                ])
                  _Figure(
                    label: label,
                    amount: amount,
                    keyName:
                        'pnl-rev-${line.businessUnitId}-${line.revenueCategoryId}-$suffix',
                    indent: true,
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        const Divider(height: AppSpacing.md, color: AppColors.hairline),
        // The totals are the headline figures, which the domain has confirmed these lines
        // reconcile to. Nothing is summed here.
        const _LineTitle(label: 'Total', strong: true),
        _Figure(
          label: 'Gross',
          amount: result.grossSales,
          keyName: 'pnl-rev-total-gross',
          strong: true,
          indent: true,
        ),
        _Figure(
          label: 'GST',
          amount: result.gst,
          keyName: 'pnl-rev-total-gst',
          strong: true,
          indent: true,
        ),
        _Figure(
          label: 'Net',
          amount: result.netSales,
          keyName: 'pnl-rev-total-net',
          strong: true,
          indent: true,
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

    return _Card(
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
              onPressed: () =>
                  pushPnlDrillLevel(context, PnlExpenseDepartmentsAt(anchor)),
              child: const Text('By department'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
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
                : () => pushPnlDrillLevel(
                    context,
                    PnlExpenseDocumentsAt(
                      anchor,
                      businessUnitId: line.businessUnitId,
                      departmentId: line.departmentId!,
                      sectionId: line.sectionId!,
                      categoryId: line.categoryId!,
                    ),
                  ),
            child: _Figure(
              label: switch (line.categoryId) {
                final String id =>
                  graph?.expenseCategory(id)?.name ??
                      'Expense category not on this device',
                null => 'Uncategorised',
              },
              detail: [
                if (consolidated)
                  graph?.businessUnit(line.businessUnitId)?.name ?? 'Property',
                if (line.sectionId case final String id)
                  graph?.section(id)?.name ?? 'Section',
              ].join(' · '),
              amount: line.totals.amount,
              keyName:
                  'pnl-exp-${line.businessUnitId}-${line.categoryId}-amount',
            ),
          ),
        const Divider(height: AppSpacing.md, color: AppColors.hairline),
        _Figure(
          label: 'Total',
          amount: result.expenses,
          keyName: 'pnl-exp-total-amount',
          strong: true,
        ),
      ],
    );
  }
}

// ── Building blocks ──────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.allMedium,
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _LineTitle extends StatelessWidget {
  const _LineTitle({
    required this.label,
    this.detail = '',
    this.strong = false,
  });

  final String label;
  final String detail;
  final bool strong;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTypography.body.copyWith(
          fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      if (detail.isNotEmpty) Text(detail, style: AppTypography.caption),
    ],
  );
}

/// One label and one amount on a line. The amount scales down rather than overflow a
/// narrow phone, and the label wraps.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.amount,
    required this.keyName,
    this.labelKey,
    this.detail,
    this.strong = false,
    this.bySign = false,
    this.indent = false,
  });

  final String label;
  final Money amount;
  final String keyName;
  final String? labelKey;
  final String? detail;
  final bool strong;
  final bool bySign;
  final bool indent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      top: AppSpacing.xxs,
      bottom: AppSpacing.xxs,
      left: indent ? AppSpacing.md : 0,
    ),
    // The label and the whole figure share a line while they fit. At a large system
    // font the figure moves to its own line at full size and the row grows taller; it
    // is never shrunk to fit (D-286).
    child: FigureReflow(
      lead: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            key: labelKey == null ? null : Key(labelKey!),
            style: (strong ? AppTypography.body : AppTypography.bodyMuted)
                .copyWith(fontWeight: strong ? FontWeight.w600 : null),
          ),
          if (detail case final String text when text.isNotEmpty)
            Text(text, style: AppTypography.caption),
        ],
      ),
      figure: MoneyText(
        amount,
        key: Key(keyName),
        style: strong ? AppTypography.moneyStrong : AppTypography.money,
        emphasis: bySign ? MoneyEmphasis.bySign : MoneyEmphasis.neutral,
        semanticPrefix: label,
      ),
      rowAlignment: CrossAxisAlignment.start,
      stackedFigureAtEnd: true,
    ),
  );
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

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.onAction, this.actionLabel});

  final PnlStateMessage message;
  final VoidCallback? onAction;

  /// Overrides the label the message's action carries, for actions it does not name.
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
