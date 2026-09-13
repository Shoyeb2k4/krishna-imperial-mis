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
/// their own screen, never ₹0 (D-163).
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
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:timezone/timezone.dart' as tz;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(pnlSyncProvider).phase == PnlSyncPhase.idle) {
        ref.read(pnlSyncProvider.notifier).refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final desktop = widget.shellKind == AppShellKind.desktop;
    final density = desktop ? AppDensity.compact : AppDensity.comfortable;
    final view = ref.watch(pnlViewProvider);
    final sync = ref.watch(pnlSyncProvider);

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
        if (view.value case final value?)
          _Body(view: value, sync: sync)
        else if (view.hasError)
          _Message(
            key: const Key('pnl-read-error'),
            icon: Icons.error_outline,
            title: 'The profit & loss could not be read on this device',
            message:
                'Nothing has been changed. Try again; if it persists, report it.',
            action: ('Try again', () => ref.invalidate(pnlViewProvider)),
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
  Widget build(BuildContext context, WidgetRef ref) => switch (view) {
    PnlNotAuthorised() => const _NotAuthorised(),
    PnlInvalidRange() => const _Message(
      key: Key('pnl-invalid-range'),
      icon: Icons.date_range_outlined,
      title: 'That range ends before it starts',
      message:
          'Choose a start date on or before the end date. The range is never swapped for you.',
    ),
    PnlPresetUnavailable(:final preset, :final resolution) => _Message(
      key: const Key('pnl-preset-unavailable'),
      icon: Icons.event_busy_outlined,
      title: '${preset.label} is not available for this report',
      message: switch (resolution) {
        PresetRangesDiffer() =>
          'The properties in this report are on different business dates, so '
              '"${preset.label}" does not describe one period for all of them. Use '
              'Custom to choose the dates explicitly.',
        _ =>
          'A property\'s business-date rules could not be read on this device, so '
              '"${preset.label}" cannot be worked out for it. Use Custom to choose the '
              'dates explicitly.',
      },
    ),
    PnlReportView() => _Report(view: view as PnlReportView, sync: sync),
  };
}

class _NotAuthorised extends StatelessWidget {
  const _NotAuthorised();

  @override
  Widget build(BuildContext context) => const _Message(
    key: Key('pnl-not-authorised'),
    icon: Icons.lock_outline,
    title: 'Profit & loss not available to your account',
    message:
        'A profit & loss needs report, revenue and full expense access for a property. '
        'No partial profit & loss is shown.',
  );
}

class _Report extends ConsumerWidget {
  const _Report({required this.view, required this.sync});

  final PnlReportView view;
  final PnlSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outcome = view.envelope.outcome;
    return switch (outcome) {
      PnlComputed(:final result) => _Statement(
        view: view,
        result: result,
        sync: sync,
      ),
      PnlRefused() => _Refused(view: view, sync: sync),
    };
  }
}

/// A refused report. Never a figure (D-163).
class _Refused extends ConsumerWidget {
  const _Refused({required this.view, required this.sync});

  final PnlReportView view;
  final PnlSyncStatus sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenue = view.envelope.revenueCoverage;
    final expenses = view.envelope.expenseCoverage;
    final controller = ref.read(pnlSyncProvider.notifier);
    final canAsk = ref.watch(reportingSyncProvider) != null;
    final range = _rangeLabel(view.range);

    if (revenue == ReportingCoverage.notAuthorised &&
        expenses == ReportingCoverage.notAuthorised) {
      return const _NotAuthorised();
    }

    final bothNotDownloaded =
        revenue == ReportingCoverage.notDownloaded &&
        expenses == ReportingCoverage.notDownloaded;
    final unreachable =
        sync.phase == PnlSyncPhase.failed && sync.failure != null;

    if (bothNotDownloaded) {
      if (sync.phase == PnlSyncPhase.downloading) {
        return _Message(
          key: const Key('pnl-downloading'),
          icon: Icons.downloading_outlined,
          title: 'Downloading required history',
          message: 'Fetching the canonical figures for $range.',
        );
      }
      if (sync.phase == PnlSyncPhase.synchronising) {
        return _Message(
          key: const Key('pnl-synchronising'),
          icon: Icons.sync,
          title: 'Synchronising',
          message:
              'Bringing the profit & loss for $range up to date on this device.',
        );
      }
      if (sync.phase == PnlSyncPhase.failed &&
          sync.lastAction == PnlSyncAction.download) {
        return _Message(
          key: const Key('pnl-download-failed'),
          icon: Icons.cloud_off_outlined,
          title: 'Download failed',
          message: unreachable
              ? 'A connection is required to download this history, and the server '
                    'could not be reached. Nothing is shown rather than an incomplete figure.'
              : 'The server did not provide this history. Nothing is shown rather than '
                    'an incomplete figure.',
          action: canAsk ? ('Try again', controller.download) : null,
        );
      }

      final years = view.olderYears.map((y) => 'FY ${y.label}').join(', ');
      return _Message(
        key: const Key('pnl-not-downloaded'),
        icon: Icons.download_outlined,
        title: 'Not downloaded',
        message: view.offersDownload
            ? 'This device does not hold the history for $range '
                  '($years). ${unreachable || !canAsk ? 'A connection is required to download it.' : 'It can be downloaded now.'}'
            : unreachable || !canAsk
            ? 'This device does not hold the profit & loss for $range yet, and a '
                  'connection is required to synchronise it.'
            : 'This device does not hold the profit & loss for $range yet.',
        action: !canAsk
            ? null
            : view.offersDownload
            ? ('Download required data', controller.download)
            : ('Synchronise', controller.refresh),
        actionKey: view.offersDownload
            ? const Key('pnl-download')
            : const Key('pnl-synchronise'),
      );
    }

    final refusal = view.envelope.refusalOrNull;
    final (key, title) = switch (refusal) {
      PnlRefusal.revenueUnavailable => (
        const Key('pnl-revenue-unavailable'),
        'Revenue unavailable',
      ),
      PnlRefusal.expensesUnavailable => (
        const Key('pnl-expense-unavailable'),
        'Expenses unavailable',
      ),
      _ => (
        const Key('pnl-both-unavailable'),
        'Revenue and expenses unavailable',
      ),
    };
    return _Message(
      key: key,
      icon: Icons.report_gmailerrorred_outlined,
      title: title,
      message:
          'Revenue: ${_coverageText(revenue)}. Expenses: ${_coverageText(expenses)}. '
          'A profit & loss needs both sides complete, so no figure is shown.',
      action:
          canAsk &&
              (revenue == ReportingCoverage.notDownloaded ||
                  expenses == ReportingCoverage.notDownloaded)
          ? ('Synchronise', controller.refresh)
          : null,
    );
  }
}

String _coverageText(ReportingCoverage coverage) => switch (coverage) {
  ReportingCoverage.complete => 'complete',
  ReportingCoverage.notDownloaded => 'not downloaded to this device',
  ReportingCoverage.notAuthorised => 'not available to your account',
};

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

    return Column(
      key: const Key('pnl-statement'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SyncNotice(sync: sync),
        _Freshness(view: view),
        const SizedBox(height: AppSpacing.md),
        _Panel(
          key: const Key('pnl-headline'),
          children: [
            Text(
              'PROFIT & LOSS · ${_rangeLabel(view.range)}',
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
          _RevenueCategories(result: result),
          const SizedBox(height: AppSpacing.lg),
          _ExpenseCategories(result: result),
        ] else
          const _Message(
            key: Key('pnl-breakdown-unreconciled'),
            icon: Icons.rule_outlined,
            title: 'Category breakdown not shown',
            message:
                'The category lines on this device do not add up exactly to the totals '
                'above, so they are not shown. Refresh to synchronise again.',
          ),
      ],
    );
  }
}

class _RevenueCategories extends ConsumerWidget {
  const _RevenueCategories({required this.result});

  final PnlResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(masterGraphProvider).value;
    final consolidated = result.isConsolidated;
    final lines = [...result.revenueByCategory]
      ..sort((a, b) {
        final unit = a.businessUnitId.compareTo(b.businessUnitId);
        return unit != 0
            ? unit
            : a.revenueCategoryId.compareTo(b.revenueCategoryId);
      });

    return _Panel(
      key: const Key('pnl-revenue-categories'),
      children: [
        Text('REVENUE BY CATEGORY', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        const _ColumnHeads(labels: ['Gross', 'GST', 'Net']),
        if (lines.isEmpty)
          Text('No revenue in this period.', style: AppTypography.caption),
        for (final line in lines)
          _Columns(
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
  const _ExpenseCategories({required this.result});

  final PnlResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = ref.watch(masterGraphProvider).value;
    final consolidated = result.isConsolidated;
    final lines = [...result.expenseByHierarchy]
      ..sort((a, b) {
        final unit = a.businessUnitId.compareTo(b.businessUnitId);
        return unit != 0
            ? unit
            : (a.categoryId ?? '').compareTo(b.categoryId ?? '');
      });

    return _Panel(
      key: const Key('pnl-expense-categories'),
      children: [
        Text('EXPENSES BY CATEGORY', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        const _ColumnHeads(labels: ['Amount']),
        if (lines.isEmpty)
          Text('No expenses in this period.', style: AppTypography.caption),
        for (final line in lines)
          _Columns(
            keyPrefix: 'pnl-exp-${line.businessUnitId}-${line.categoryId}',
            label: switch (line.categoryId) {
              final String id =>
                graph?.expenseCategory(id)?.name ??
                    'Expense category not on this device',
              null => 'Uncategorised',
            },
            detail: consolidated
                ? graph?.businessUnit(line.businessUnitId)?.name ?? 'Property'
                : '',
            amounts: [line.totals.amount],
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

// ── Freshness and synchronisation ───────────────────────────────────────────

class _Freshness extends ConsumerWidget {
  const _Freshness({required this.view});

  final PnlReportView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final freshness = view.envelope.freshness;
    if (freshness == null) {
      return Text(
        'Complete, but these figures do not come from one synchronisation, so no single '
        'time is stated.',
        key: const Key('pnl-freshness-none'),
        style: AppTypography.caption,
      );
    }
    final zone = _displayZone(ref, view);
    final when = _instantLabel(freshness.synchronisedAt, zone);
    return switch (freshness.state) {
      ReportingFreshnessState.synchronised => Text(
        'Synchronised as of $when',
        key: const Key('pnl-freshness-synchronised'),
        style: AppTypography.caption,
      ),
      ReportingFreshnessState.serverHasNewer => Text(
        'Synchronised as of $when · the server has newer changes. Refresh to update.',
        key: const Key('pnl-freshness-server-newer'),
        style: AppTypography.caption.copyWith(color: AppColors.caution),
      ),
    };
  }
}

/// What the last synchronisation means for figures already on screen.
class _SyncNotice extends StatelessWidget {
  const _SyncNotice({required this.sync});

  final PnlSyncStatus sync;

  @override
  Widget build(BuildContext context) {
    if (sync.isRunning) {
      return _Notice(
        key: const Key('pnl-refreshing'),
        icon: Icons.sync,
        text: sync.phase == PnlSyncPhase.downloading
            ? 'Downloading. The figures below are as last synchronised.'
            : 'Refreshing. The figures below are as last synchronised.',
      );
    }
    if (sync.phase == PnlSyncPhase.failed) {
      return sync.failure != null
          ? const _Notice(
              key: Key('pnl-offline'),
              icon: Icons.cloud_off_outlined,
              text:
                  'The server could not be reached. These figures are the complete report '
                  'this device last synchronised.',
            )
          : const _Notice(
              key: Key('pnl-sync-refused'),
              icon: Icons.cloud_off_outlined,
              text:
                  'The server did not accept the last synchronisation. These figures are the '
                  'complete report this device last synchronised.',
            );
    }
    return const SizedBox.shrink();
  }
}

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
    final options = ref.watch(pnlScopeOptionsProvider).value;
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
  const _Notice({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.caution),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: AppTypography.caption)),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.actionKey,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final (String, VoidCallback)? action;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: Column(
      children: [
        Icon(icon, size: 28, color: AppColors.inkFaint),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: AppTypography.subheading,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            message,
            style: AppTypography.bodyMuted,
            textAlign: TextAlign.center,
          ),
        ),
        if (action case (final label, final onPressed)) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            key: actionKey,
            onPressed: onPressed,
            child: Text(label),
          ),
        ],
      ],
    ),
  );
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

// ── Display formatting ───────────────────────────────────────────────────────

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _dateLabel(BusinessDate d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}';

String _rangeLabel(ReportRange range) => range.from == range.to
    ? _dateLabel(range.from)
    : '${_dateLabel(range.from)} – ${_dateLabel(range.to)}';

/// The zone a server-confirmed time is displayed in: the first property in scope's own
/// zone. Display only; nothing is derived from it.
String _displayZone(WidgetRef ref, PnlReportView view) {
  final rules = ref.watch(businessDayRulesProvider).value ?? const {};
  final sorted = rules.keys.toList()..sort();
  final unit = switch (view.scope) {
    PnlUnitScope(:final businessUnitId) => businessUnitId,
    PnlConsolidatedScope() => sorted.isEmpty ? null : sorted.first,
  };
  return rules[unit]?.timeZoneId ?? 'UTC';
}

String _instantLabel(DateTime instant, String zone) {
  final local = tz.TZDateTime.from(instant, tz.getLocation(zone));
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} ${local.year}, $hh:$mm ${local.timeZoneName}';
}
