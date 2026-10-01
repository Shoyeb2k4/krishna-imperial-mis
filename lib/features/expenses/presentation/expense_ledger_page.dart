/// The expense ledger: dense on Windows, compact on Android.
///
/// One rule governs every figure it prints, and it is the reason this file is careful:
/// **a scoped share is never presented as an invoice total.** A Crystal Canopy manager
/// looking at the shared electricity bill sees
///
///     Shared · your allocation   ₹25,000
///
/// and never `₹25,000 Total`, because the real total is ₹58,000 and this device does not
/// have it. The read model makes that structural — `documentTotalMinor` is null on a
/// scoped record — and this file's job is to say so in words rather than to imply
/// otherwise by labelling the wrong number.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/components/sync_state_chip.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_filters.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/expense_detail_panel.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/expense_read_failure.dart';

class ExpenseLedgerPage extends ConsumerStatefulWidget {
  const ExpenseLedgerPage({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  ConsumerState<ExpenseLedgerPage> createState() => _ExpenseLedgerPageState();
}

class _ExpenseLedgerPageState extends ConsumerState<ExpenseLedgerPage> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(filteredExpensesProvider);
    // Only the window computed for this person and this exact question is shown. While
    // the next one loads, the previous one answered something else (D-074, D-231).
    final shown = expenseLedgerShownTo(
      state.value,
      authorityKey: ref.watch(expenseLedgerAuthorityKeyProvider),
      filter: ref.watch(expenseFilterProvider),
    );
    final desktop = widget.shellKind == AppShellKind.desktop;
    final body = shown != null
        ? null
        : state.hasError && !state.isLoading
        ? _failure(state.error!, state.stackTrace)
        : const Center(child: CircularProgressIndicator());

    return desktop ? _desktop(shown, body) : body ?? _mobile(shown!);
  }

  /// Plain words and a retry, never the exception (D-323). The detail goes to the
  /// developer log.
  Widget _failure(Object error, StackTrace? stack) {
    logExpenseReadFailure('The expense ledger', error, stack);
    return ExpenseReadFailure(
      title: 'The ledger could not be read',
      body:
          'Nothing has changed. This device could not read its stored expenses '
          'just now. Try again; if it keeps happening, restart the app.',
      onRetry: () => ref.invalidate(filteredExpensesProvider),
    );
  }

  /// What to say when nothing matches. Every filter is applied before the ledger is
  /// cut, so an empty answer means nothing on this device matches at all (D-317).
  Widget _empty({required bool desktop}) {
    if (!ref.watch(expenseFilterProvider).isEmpty) {
      return const _Empty(
        key: Key('expense-ledger-no-match'),
        title: 'No expenses match these filters.',
        body:
            'Every expense on this device was searched. Change or clear the '
            'filters to see others.',
      );
    }
    return desktop
        ? const _Empty(
            key: Key('expense-ledger-none'),
            title: 'No expenses recorded yet.',
            body: 'Record one from the Transactions screen.',
          )
        : const _Empty(
            key: Key('expense-ledger-none'),
            title: 'No expenses recorded yet.',
            body: 'Use the + button to record one. It works offline.',
          );
  }

  // ── Windows: dense table, filters, persistent detail panel ────────────────

  /// The filter bar stays on screen while a window loads or fails, so changing a filter
  /// never takes the controls away from the person changing it.
  Widget _desktop(ExpenseLedgerWindow? shown, Widget? body) => Row(
    children: [
      Expanded(
        flex: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ExpenseFilterBar(),
            const Divider(height: 1),
            Expanded(
              child:
                  body ??
                  (shown!.rows.isEmpty
                      ? _empty(desktop: true)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _LedgerTable(
                                rows: shown.rows,
                                selectedId: _selectedId,
                                onSelect: (id) =>
                                    setState(() => _selectedId = id),
                              ),
                            ),
                            const Divider(height: 1),
                            _LedgerFooter(window: shown),
                          ],
                        )),
            ),
          ],
        ),
      ),
      const VerticalDivider(width: 1, color: AppColors.hairline),
      SizedBox(
        width: 380,
        child: _selectedId == null
            ? const _Empty(
                title: 'Nothing selected',
                body: 'Choose an expense to see its detail and history.',
              )
            : ExpenseDetailPanel(expenseId: _selectedId!),
      ),
    ],
  );

  // ── Android: a compact recent list, not the Windows table shrunk ──────────

  Widget _mobile(ExpenseLedgerWindow shown) {
    final rows = shown.rows;
    if (rows.isEmpty) return _empty(desktop: false);
    return ListView.separated(
      // The last item is the footer: how many are shown, and "Load more" when there are.
      itemCount: rows.length + 1,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: AppSpacing.lg),
      itemBuilder: (context, index) {
        if (index == rows.length) return _LedgerFooter(window: shown);
        final expense = rows[index];
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                backgroundColor: AppColors.paper,
                appBar: AppBar(
                  backgroundColor: AppColors.paper,
                  title: Text(expense.displayReference),
                ),
                body: ExpenseDetailPanel(expenseId: expense.row.id),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _summaryLine(expense),
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          Text(
                            expense.row.businessDate,
                            style: AppTypography.caption,
                          ),
                          Text(' · ', style: AppTypography.caption),
                          Flexible(
                            child: Text(
                              expense.displayReference,
                              style: AppTypography.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(expense.visibleAmount),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (expense.isScoped) ...[
                          const _SharedBadge(compact: true),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        SyncStateChip(expense.syncState, compact: true),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _summaryLine(LocalExpense expense) {
    if (expense.row.voidedAt != null) return 'VOIDED · ${_categories(expense)}';
    return _categories(expense);
  }

  static String _categories(LocalExpense expense) {
    final labels = expense.allocations.map((a) => a.categoryLabel).toSet();
    if (labels.isEmpty) return 'Expense';
    return labels.length == 1
        ? labels.single
        : '${labels.first} + ${labels.length - 1} more';
  }
}

/// The Windows table. It renders whatever page it is given and never
/// asks for "everything".
class _LedgerTable extends StatelessWidget {
  const _LedgerTable({
    required this.rows,
    required this.onSelect,
    this.selectedId,
  });

  final List<LocalExpense> rows;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        color: AppColors.surfaceMuted,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            _header('Date', flex: 2),
            _header('Expense no.', flex: 3),
            _header('Vendor', flex: 3),
            _header('Category', flex: 4),
            _header('Amount', flex: 3, align: TextAlign.right),
            _header('Payment', flex: 2),
            _header('Status', flex: 3),
          ],
        ),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final expense = rows[index];
            final selected = expense.row.id == selectedId;
            final voided = expense.row.voidedAt != null;

            return InkWell(
              onTap: () => onSelect(expense.row.id),
              focusColor: AppColors.brassWash,
              child: Container(
                color: selected ? AppColors.brassWash : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    _cell(expense.row.businessDate, flex: 2),
                    _cell(
                      expense.displayReference,
                      flex: 3,
                      faint: expense.row.txnNumber == null,
                    ),
                    _cell(
                      expense.row.vendorId == null ? '—' : 'Vendor',
                      flex: 3,
                    ),
                    _cell(
                      _ExpenseLedgerPageState._categories(expense),
                      flex: 4,
                      strikethrough: voided,
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(expense.visibleAmount),
                          if (expense.isScoped)
                            Text(
                              'your allocation',
                              key: const Key('scoped-amount-caption'),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.caution,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _cell(
                      expense.row.paymentStatus == 'paid' ? 'Paid' : 'Unpaid',
                      flex: 2,
                    ),
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          if (voided)
                            const _VoidedBadge()
                          else ...[
                            if (expense.isScoped) ...[
                              const _SharedBadge(),
                              const SizedBox(width: AppSpacing.xs),
                            ],
                            SyncStateChip(expense.syncState, compact: true),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ],
  );

  static Widget _header(
    String label, {
    required int flex,
    TextAlign align = TextAlign.left,
  }) => Expanded(
    flex: flex,
    child: Text(
      label.toUpperCase(),
      style: AppTypography.overline,
      textAlign: align,
    ),
  );

  static Widget _cell(
    String value, {
    required int flex,
    bool faint = false,
    bool strikethrough = false,
  }) => Expanded(
    flex: flex,
    child: Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.body.copyWith(
        color: faint ? AppColors.inkFaint : AppColors.ink,
        decoration: strikethrough ? TextDecoration.lineThrough : null,
      ),
    ),
  );
}

/// Says that a figure is a share, so the number beside it is never read as an invoice.
class _SharedBadge extends StatelessWidget {
  const _SharedBadge({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Tooltip(
    message:
        'This expense is shared with another business unit. You can see your '
        'own allocation; the document total is not available to you.',
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.allSmall,
        border: Border.all(color: AppColors.hairlineStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.call_split, size: 11, color: AppColors.inkMuted),
          if (!compact) ...[
            const SizedBox(width: AppSpacing.xxs),
            Text('Shared', style: AppTypography.caption),
          ],
        ],
      ),
    ),
  );
}

class _VoidedBadge extends StatelessWidget {
  const _VoidedBadge();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('voided-badge'),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.negative),
    ),
    child: Text(
      'VOIDED',
      style: AppTypography.caption.copyWith(color: AppColors.negative),
    ),
  );
}

/// How much of the ledger is on screen, and the way to the rest of it (D-317).
///
/// Says plainly whether more matching expenses exist, so a ledger that stops is never
/// mistaken for a ledger that has shown everything.
class _LedgerFooter extends ConsumerWidget {
  const _LedgerFooter({required this.window});

  final ExpenseLedgerWindow window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = window.rows.length;
    final noun = count == 1 ? 'expense' : 'expenses';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          Text(
            window.hasMore
                ? 'Showing the newest $count $noun. More match these filters.'
                : 'Showing all $count matching $noun.',
            key: const Key('expense-ledger-shown-count'),
            style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
          ),
          if (window.hasMore)
            OutlinedButton(
              key: const Key('expense-ledger-load-more'),
              onPressed: () =>
                  ref.read(expenseLedgerPagesProvider.notifier).loadMore(),
              child: const Text('Load $expenseLedgerPageSize more'),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body, super.key});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: AppTypography.subheading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              body,
              style: AppTypography.bodyMuted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
