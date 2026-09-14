/// The drill-down beneath a P&L, as both surfaces show it (Phase 5 Slice 10).
///
/// Windows puts a level in a pane with the document beside it; Android pushes a page per
/// level. What a level holds, what it is called and what every refusal says are decided
/// once, here, so the two cannot describe one report differently (D-232).
///
/// ## Read-only, and structurally so
///
/// A document is rendered by the revenue and expense **bodies**, which own no action. This
/// file composes nothing into their action slots and imports no action widget, controller,
/// repository or sync worker; a structural guard holds that even for a person who could
/// edit, void or attach from the ledger.
///
/// It computes nothing. Every figure is a field of a line the providers produced, and every
/// total shown under children is the parent figure itself, shown only once the domain has
/// confirmed the children add up to it exactly.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/expense_document_body.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_presentation.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_document_body.dart';

// ── Wording ─────────────────────────────────────────────────────────────────

/// Shown when a level's children do not add up exactly to its parent.
const pnlDrillUnreconciledText =
    'Transactions not shown — amounts do not add up exactly. Refresh.';

/// Shown when full document detail needs a connection.
const pnlDocumentNotDownloadedText =
    'Detail not downloaded — connect to open this document.';

/// Shown when a fetched document no longer explains the cached row.
const pnlDocumentChangedText =
    'This transaction changed since the report was synchronised. Refresh the report to '
    'open current detail.';

/// Shown when the server withholds a document.
const pnlDocumentNotAvailableText = 'Not available to you.';

/// A level's refusal, in words.
PnlStateMessage pnlDrillMessage(PnlDrillRefusal reason) => switch (reason) {
  PnlDrillRefusal.reportChanged => const PnlStateMessage(
    key: Key('pnl-drill-report-changed'),
    icon: Icons.undo,
    title: 'This report changed',
    message:
        'The person, property or period changed since this level was opened. Return to '
        'Profit & Loss.',
  ),
  PnlDrillRefusal.notAuthorised => const PnlStateMessage(
    key: Key('pnl-drill-not-authorised'),
    icon: Icons.lock_outline,
    title: 'Not available to you',
    message: pnlDocumentNotAvailableText,
  ),
  PnlDrillRefusal.notDownloaded => const PnlStateMessage(
    key: Key('pnl-drill-not-downloaded'),
    icon: Icons.download_outlined,
    title: 'Not downloaded',
    message:
        'This device does not hold the transactions for this range. Synchronise to '
        'download them.',
    action: PnlMessageAction.synchronise,
  ),
  PnlDrillRefusal.unreconciled => const PnlStateMessage(
    key: Key('pnl-drill-unreconciled'),
    icon: Icons.rule_outlined,
    title: 'Transactions not shown',
    message: pnlDrillUnreconciledText,
    action: PnlMessageAction.synchronise,
  ),
};

/// A document's refusal, in words.
PnlStateMessage pnlDocumentMessage(
  PnlDocumentRefusal reason,
) => switch (reason) {
  PnlDocumentRefusal.reportChanged => const PnlStateMessage(
    key: Key('pnl-document-report-changed'),
    icon: Icons.undo,
    title: 'This report changed',
    message:
        'This row is no longer in the report on screen. Return to Profit & Loss.',
  ),
  PnlDocumentRefusal.notAvailable => const PnlStateMessage(
    key: Key('pnl-document-not-available'),
    icon: Icons.lock_outline,
    title: 'Not available',
    message: pnlDocumentNotAvailableText,
  ),
  PnlDocumentRefusal.notDownloaded => const PnlStateMessage(
    key: Key('pnl-document-not-downloaded'),
    icon: Icons.cloud_off_outlined,
    title: 'Detail not downloaded',
    message: pnlDocumentNotDownloadedText,
  ),
  PnlDocumentRefusal.changed => const PnlStateMessage(
    key: Key('pnl-document-changed'),
    icon: Icons.sync_problem_outlined,
    title: 'Transaction changed',
    message: pnlDocumentChangedText,
    action: PnlMessageAction.synchronise,
    actionKey: Key('pnl-document-refresh'),
  ),
};

// ── Where a level is ────────────────────────────────────────────────────────

@immutable
final class PnlDrillCrumb {
  const PnlDrillCrumb({required this.label, required this.key, this.target});

  final String label;
  final Key key;

  /// The level this crumb opens, or null for the P&L itself.
  final PnlDrillLocation? target;
}

/// The path to [location], from the P&L. The last crumb is [location] itself.
List<PnlDrillCrumb> pnlDrillCrumbs(
  PnlDrillLocation location,
  MasterGraph? graph,
) {
  String dept(String id) =>
      graph?.department(id)?.name ?? 'Department not on this device';
  String section(String id) =>
      graph?.section(id)?.name ?? 'Section not on this device';
  String category(String id) =>
      graph?.expenseCategory(id)?.name ?? 'Expense category not on this device';

  const report = PnlDrillCrumb(
    label: 'Profit & Loss',
    key: Key('pnl-crumb-report'),
  );
  final anchor = location.anchor;
  final expenses = PnlDrillCrumb(
    label: 'Expenses',
    key: const Key('pnl-crumb-expenses'),
    target: PnlExpenseDepartmentsAt(anchor),
  );

  return switch (location) {
    PnlRevenueDocumentsAt(:final revenueCategoryId) => [
      report,
      const PnlDrillCrumb(label: 'Revenue', key: Key('pnl-crumb-revenue')),
      PnlDrillCrumb(
        label:
            graph?.revenueCategory(revenueCategoryId)?.name ??
            'Revenue category not on this device',
        key: const Key('pnl-crumb-revenue-category'),
        target: location,
      ),
    ],
    PnlExpenseDepartmentsAt() => [report, expenses],
    PnlExpenseSectionsAt(:final departmentId) => [
      report,
      expenses,
      PnlDrillCrumb(
        label: dept(departmentId),
        key: const Key('pnl-crumb-department'),
        target: location,
      ),
    ],
    PnlExpenseCategoriesAt(
      :final businessUnitId,
      :final departmentId,
      :final sectionId,
    ) =>
      [
        report,
        expenses,
        PnlDrillCrumb(
          label: dept(departmentId),
          key: const Key('pnl-crumb-department'),
          target: PnlExpenseSectionsAt(
            anchor,
            businessUnitId: businessUnitId,
            departmentId: departmentId,
          ),
        ),
        PnlDrillCrumb(
          label: section(sectionId),
          key: const Key('pnl-crumb-section'),
          target: location,
        ),
      ],
    PnlExpenseDocumentsAt(
      :final businessUnitId,
      :final departmentId,
      :final sectionId,
      :final categoryId,
    ) =>
      [
        report,
        expenses,
        PnlDrillCrumb(
          label: dept(departmentId),
          key: const Key('pnl-crumb-department'),
          target: PnlExpenseSectionsAt(
            anchor,
            businessUnitId: businessUnitId,
            departmentId: departmentId,
          ),
        ),
        PnlDrillCrumb(
          label: section(sectionId),
          key: const Key('pnl-crumb-section'),
          target: PnlExpenseCategoriesAt(
            anchor,
            businessUnitId: businessUnitId,
            departmentId: departmentId,
            sectionId: sectionId,
          ),
        ),
        PnlDrillCrumb(
          label: category(categoryId),
          key: const Key('pnl-crumb-category'),
          target: location,
        ),
      ],
  };
}

/// The breadcrumb, for the Windows pane.
class PnlDrillBreadcrumb extends ConsumerWidget {
  const PnlDrillBreadcrumb({
    required this.location,
    required this.onReport,
    required this.onOpen,
    super.key,
  });

  final PnlDrillLocation location;
  final VoidCallback onReport;
  final ValueChanged<PnlDrillLocation> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crumbs = pnlDrillCrumbs(
      location,
      ref.watch(masterGraphProvider).value,
    );
    return Wrap(
      key: const Key('pnl-drill-breadcrumb'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xxs,
      children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0)
            const Icon(
              Icons.chevron_right,
              size: 16,
              color: AppColors.inkFaint,
            ),
          if (i == crumbs.length - 1)
            Text(
              crumbs[i].label,
              key: crumbs[i].key,
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            )
          else
            TextButton(
              key: crumbs[i].key,
              onPressed: switch (crumbs[i].target) {
                final target? => () => onOpen(target),
                null => onReport,
              },
              child: Text(crumbs[i].label),
            ),
        ],
      ],
    );
  }
}

// ── A level ─────────────────────────────────────────────────────────────────

/// One level's rows and the parent they add up to, or the reason there are none.
class PnlDrillLevelList extends ConsumerWidget {
  const PnlDrillLevelList({
    required this.location,
    required this.onOpen,
    required this.onSelect,
    required this.onReportChanged,
    this.selected,
    this.compact = true,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final PnlDrillLocation location;
  final ValueChanged<PnlDrillLocation> onOpen;
  final ValueChanged<PnlDocumentRequest> onSelect;
  final VoidCallback onReportChanged;
  final PnlDocumentRequest? selected;

  /// Amounts beside labels (Windows) or under them (phone).
  final bool compact;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(pnlDrillLevelProvider(location));
    final graph = ref.watch(masterGraphProvider).value;
    final vendors = ref.watch(pnlVendorNamesProvider).value ?? const {};
    final consolidated = location.anchor.isConsolidated;

    String unitName(String id) => graph?.businessUnit(id)?.name ?? 'Property';

    final List<Widget> children = switch (level) {
      AsyncValue(hasValue: true, value: final PnlDrillRefused refused) => [
        PnlDrillMessageView(
          message: pnlDrillMessage(refused.reason),
          actionLabel: refused.reason == PnlDrillRefusal.reportChanged
              ? 'Return to Profit & Loss'
              : 'Refresh',
          onAction: refused.reason == PnlDrillRefusal.reportChanged
              ? onReportChanged
              : refused.reason == PnlDrillRefusal.notAuthorised
              ? null
              : () => ref.read(pnlSyncProvider.notifier).refresh(),
        ),
      ],
      AsyncValue(hasValue: true, value: final PnlExpenseLevelView view) => [
        for (final line in view.children)
          _levelRow(line, view.location, graph, consolidated, unitName),
        const Divider(height: AppSpacing.md, color: AppColors.hairline),
        PnlDrillRow(
          keyName: 'pnl-drill-total',
          label: 'Total',
          amounts: [view.parent.amount],
          strong: true,
          compact: compact,
        ),
      ],
      AsyncValue(hasValue: true, value: final PnlRevenueDocumentsView view) => [
        Text(
          'Each row is one sale recorded in this category, dated by its P&L date.',
          key: const Key('pnl-drill-revenue-note'),
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (view.documents.isEmpty)
          Text('No transactions in this period.', style: AppTypography.caption),
        for (final line in view.documents)
          PnlDrillRow(
            keyName: 'pnl-drill-doc-${line.revenueEntryId}',
            label: pnlDateLabel(line.pnlDate),
            detail: [
              if (consolidated) unitName(line.businessUnitId),
              _count(line.totals.contributions, 'component'),
            ].join(' · '),
            amounts: [line.totals.gross, line.totals.tax, line.totals.net],
            compact: compact,
            selected:
                selected == PnlRevenueDocumentRequest(view.location, line),
            onTap: () =>
                onSelect(PnlRevenueDocumentRequest(view.location, line)),
          ),
        const Divider(height: AppSpacing.md, color: AppColors.hairline),
        PnlDrillRow(
          keyName: 'pnl-drill-total',
          label: 'Total',
          amounts: [
            view.parent.totals.gross,
            view.parent.totals.tax,
            view.parent.totals.net,
          ],
          strong: true,
          compact: compact,
        ),
      ],
      AsyncValue(hasValue: true, value: final PnlExpenseDocumentsView view) => [
        Text(
          "Each row is that document's contribution to this category in this period — "
          'not necessarily the expense total.',
          key: const Key('pnl-drill-contribution-note'),
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (view.documents.isEmpty)
          Text('No transactions in this period.', style: AppTypography.caption),
        for (final line in view.documents)
          PnlDrillRow(
            keyName: 'pnl-drill-doc-${line.expenseId}',
            label: line.spansPeriods
                ? '${pnlDateLabel(line.firstPnlDate)} – ${pnlDateLabel(line.lastPnlDate)}'
                : pnlDateLabel(line.firstPnlDate),
            detail: [
              if (consolidated) unitName(line.businessUnitId),
              switch (line.vendorId) {
                final String id => vendors[id] ?? 'Vendor not on this device',
                null => 'No vendor recorded',
              },
              _count(line.totals.contributions, 'contribution'),
            ].join(' · '),
            amounts: [line.totals.amount],
            compact: compact,
            selected:
                selected == PnlExpenseDocumentRequest(view.location, line),
            onTap: () =>
                onSelect(PnlExpenseDocumentRequest(view.location, line)),
          ),
        const Divider(height: AppSpacing.md, color: AppColors.hairline),
        PnlDrillRow(
          keyName: 'pnl-drill-total',
          label: 'Total',
          amounts: [view.parent.totals.amount],
          strong: true,
          compact: compact,
        ),
      ],
      AsyncError() => [
        PnlDrillMessageView(
          message: pnlReadErrorMessage,
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(pnlDrillLevelProvider(location)),
        ),
      ],
      _ => [
        const Padding(
          key: Key('pnl-drill-loading'),
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ],
    };

    return ListView(
      key: Key('pnl-drill-level-${location.runtimeType}'),
      padding: padding,
      children: children,
    );
  }

  Widget _levelRow(
    ExpenseHierarchyLine line,
    PnlDrillLocation at,
    MasterGraph? graph,
    bool consolidated,
    String Function(String) unitName,
  ) {
    final anchor = at.anchor;
    final unit = line.businessUnitId;
    final detail = consolidated ? unitName(unit) : '';
    return switch (at) {
      PnlExpenseDepartmentsAt() => PnlDrillRow(
        keyName: 'pnl-drill-dept-$unit-${line.departmentId}',
        label:
            graph?.department(line.departmentId!)?.name ??
            'Department not on this device',
        detail: detail,
        amounts: [line.totals.amount],
        compact: compact,
        onTap: () => onOpen(
          PnlExpenseSectionsAt(
            anchor,
            businessUnitId: unit,
            departmentId: line.departmentId!,
          ),
        ),
      ),
      PnlExpenseSectionsAt() => PnlDrillRow(
        keyName: 'pnl-drill-section-$unit-${line.sectionId}',
        label:
            graph?.section(line.sectionId!)?.name ??
            'Section not on this device',
        detail: detail,
        amounts: [line.totals.amount],
        compact: compact,
        onTap: () => onOpen(
          PnlExpenseCategoriesAt(
            anchor,
            businessUnitId: unit,
            departmentId: line.departmentId!,
            sectionId: line.sectionId!,
          ),
        ),
      ),
      _ => PnlDrillRow(
        keyName: 'pnl-drill-category-$unit-${line.categoryId}',
        label:
            graph?.expenseCategory(line.categoryId!)?.name ??
            'Expense category not on this device',
        detail: detail,
        amounts: [line.totals.amount],
        compact: compact,
        onTap: () => onOpen(
          PnlExpenseDocumentsAt(
            anchor,
            businessUnitId: unit,
            departmentId: line.departmentId!,
            sectionId: line.sectionId!,
            categoryId: line.categoryId!,
          ),
        ),
      ),
    };
  }
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// One row of a level. Amounts are shown as they arrive; nothing is summed.
class PnlDrillRow extends StatelessWidget {
  const PnlDrillRow({
    required this.keyName,
    required this.label,
    required this.amounts,
    required this.compact,
    this.detail = '',
    this.strong = false,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final String keyName;
  final String label;
  final String detail;
  final List<Money> amounts;
  final bool compact;
  final bool strong;
  final bool selected;
  final VoidCallback? onTap;

  static const _suffixes = {
    1: ['amount'],
    3: ['gross', 'gst', 'net'],
  };
  static const _labels = {
    1: ['Amount'],
    3: ['Gross', 'GST', 'Net'],
  };

  @override
  Widget build(BuildContext context) {
    final suffixes = _suffixes[amounts.length]!;
    final names = _labels[amounts.length]!;
    final labelStyle = (strong ? AppTypography.body : AppTypography.bodyMuted)
        .copyWith(fontWeight: strong ? FontWeight.w600 : null);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, overflow: TextOverflow.ellipsis, style: labelStyle),
        if (detail.isNotEmpty)
          Text(
            detail,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            style: AppTypography.caption,
          ),
      ],
    );
    Widget money(int i) => MoneyText(
      amounts[i],
      key: Key('$keyName-${suffixes[i]}'),
      style: strong ? AppTypography.moneyStrong : AppTypography.money,
      semanticPrefix: '$label ${names[i]}',
    );

    Widget content(bool columns) => columns
        ? Row(
            children: [
              Expanded(child: title),
              for (var i = 0; i < amounts.length; i++)
                SizedBox(width: 130, child: money(i)),
              SizedBox(
                width: 24,
                child: onTap == null
                    ? null
                    : const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.inkFaint,
                      ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: title),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.inkFaint,
                    ),
                ],
              ),
              for (var i = 0; i < amounts.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: Text(names[i], style: AppTypography.caption),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: money(i),
                      ),
                    ),
                  ],
                ),
            ],
          );

    return Material(
      color: selected ? AppColors.surfaceMuted : Colors.transparent,
      child: InkWell(
        key: Key(keyName),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xs,
            horizontal: AppSpacing.xs,
          ),
          // Columns beside the label where there is room for them and a readable label;
          // stacked under it otherwise — a pane beside an open document is narrow.
          child: LayoutBuilder(
            builder: (context, constraints) => content(
              compact && constraints.maxWidth >= 130.0 * amounts.length + 200,
            ),
          ),
        ),
      ),
    );
  }
}

/// A message in place of a level or a document. Never a figure.
class PnlDrillMessageView extends StatelessWidget {
  const PnlDrillMessageView({
    required this.message,
    this.onAction,
    this.actionLabel,
    super.key,
  });

  final PnlStateMessage message;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel ?? message.action?.label;
    return Padding(
      key: message.key,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.md,
      ),
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

// ── A document ──────────────────────────────────────────────────────────────

/// The document behind a row, rendered by an immutable body with no action composed in.
class PnlDocumentDetail extends ConsumerWidget {
  const PnlDocumentDetail({required this.request, super.key});

  final PnlDocumentRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(pnlDocumentDetailProvider(request));
    final graph = ref.watch(masterGraphProvider).value ?? MasterGraph.empty();

    return switch (detail) {
      AsyncValue(hasValue: true, value: final PnlRevenueDocumentReady ready) =>
        RevenueDocumentBody(
          listKey: const Key('pnl-document-revenue'),
          entry: ready.entry,
          graph: graph,
          leading: _Contribution(
            text:
                'This sale is the source of the row selected in the report. Its figures '
                'below equal that row exactly.',
            amounts: [
              ready.line.totals.gross,
              ready.line.totals.tax,
              ready.line.totals.net,
            ],
          ),
        ),
      AsyncValue(hasValue: true, value: final PnlExpenseDocumentReady ready) =>
        ExpenseDocumentBody(
          listKey: const Key('pnl-document-expense'),
          detail: ready.detail,
          leading: _Contribution(
            text:
                "This expense's contribution to the selected category in this period. "
                'It is not necessarily the expense total shown below.',
            amounts: [ready.line.totals.amount],
          ),
        ),
      AsyncValue(hasValue: true, value: final PnlDocumentRefused refused) =>
        ListView(
          children: [
            PnlDrillMessageView(
              message: pnlDocumentMessage(refused.reason),
              actionLabel: switch (refused.reason) {
                PnlDocumentRefusal.changed => 'Refresh report',
                PnlDocumentRefusal.notDownloaded => 'Try again',
                _ => null,
              },
              onAction: switch (refused.reason) {
                PnlDocumentRefusal.changed =>
                  () => ref.read(pnlSyncProvider.notifier).refresh(),
                PnlDocumentRefusal.notDownloaded => () => ref.invalidate(
                  pnlDocumentDetailProvider(request),
                ),
                _ => null,
              },
            ),
          ],
        ),
      AsyncError() => ListView(
        children: [
          PnlDrillMessageView(
            message: pnlReadErrorMessage,
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(pnlDocumentDetailProvider(request)),
          ),
        ],
      ),
      _ => const Center(
        key: Key('pnl-document-loading'),
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    };
  }
}

class _Contribution extends StatelessWidget {
  const _Contribution({required this.text, required this.amounts});

  final String text;
  final List<Money> amounts;

  static const _suffixes = {
    1: ['amount'],
    3: ['gross', 'gst', 'net'],
  };
  static const _labels = {
    1: ['Contribution'],
    3: ['Gross', 'GST', 'Net'],
  };

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('pnl-document-contribution'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadius.allSmall,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('IN THIS REPORT', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.xxs),
        Text(text, style: AppTypography.caption),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < amounts.length; i++)
          Row(
            children: [
              Expanded(
                child: Text(
                  _labels[amounts.length]![i],
                  style: AppTypography.bodyMuted,
                ),
              ),
              MoneyText(
                amounts[i],
                key: Key(
                  'pnl-document-contribution-${_suffixes[amounts.length]![i]}',
                ),
                style: AppTypography.money,
              ),
            ],
          ),
      ],
    ),
  );
}
