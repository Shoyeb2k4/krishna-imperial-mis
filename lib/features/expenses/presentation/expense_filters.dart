/// Filtering the ledger, without ever loading the whole of it.
///
/// The filter is pushed into the query rather than applied to a list in Dart, and the
/// query is paged. A finance workstation will eventually be looking at years of history;
/// "fetch everything and filter in memory" is the pattern that works beautifully in
/// development and falls over on the day it matters (spec §27).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_entry_page.dart';

/// What the ledger is currently showing.
@immutable
final class ExpenseFilter implements ExpenseQuery {
  const ExpenseFilter({
    this.from,
    this.to,
    this.businessUnitId,
    this.categoryId,
    this.vendorId,
    this.paymentStatus,
    this.syncState,
    this.search,
    this.includeVoided = false,
  });

  /// ISO dates, because that is how the local column stores them and comparing text to
  /// text keeps the query a plain index scan.
  @override
  final String? from;
  @override
  final String? to;
  @override
  final String? businessUnitId;
  @override
  final String? categoryId;
  @override
  final String? vendorId;
  @override
  final String? paymentStatus;
  @override
  final SyncState? syncState;

  /// Matches an expense number or a reference. Nothing clever — a finance user looking
  /// for `KI-EXP-26-27-000042` wants that document and no others.
  @override
  final String? search;

  /// Voided documents are out of the default view and one toggle away, never hidden
  /// outright: they are history, and history has to be reachable (D-006).
  @override
  final bool includeVoided;

  ExpenseFilter copyWith({
    String? from,
    String? to,
    String? businessUnitId,
    String? categoryId,
    String? vendorId,
    String? paymentStatus,
    SyncState? syncState,
    String? search,
    bool? includeVoided,
    bool clearDates = false,
    bool clearUnit = false,
    bool clearPayment = false,
    bool clearSync = false,
  }) => ExpenseFilter(
    from: clearDates ? null : (from ?? this.from),
    to: clearDates ? null : (to ?? this.to),
    businessUnitId: clearUnit ? null : (businessUnitId ?? this.businessUnitId),
    categoryId: categoryId ?? this.categoryId,
    vendorId: vendorId ?? this.vendorId,
    paymentStatus: clearPayment ? null : (paymentStatus ?? this.paymentStatus),
    syncState: clearSync ? null : (syncState ?? this.syncState),
    search: search ?? this.search,
    includeVoided: includeVoided ?? this.includeVoided,
  );

  bool get isEmpty =>
      from == null &&
      to == null &&
      businessUnitId == null &&
      categoryId == null &&
      vendorId == null &&
      paymentStatus == null &&
      syncState == null &&
      (search == null || search!.isEmpty) &&
      !includeVoided;
}

class ExpenseFilterNotifier extends Notifier<ExpenseFilter> {
  @override
  ExpenseFilter build() => const ExpenseFilter();

  void update(ExpenseFilter filter) => state = filter;
  void clear() => state = const ExpenseFilter();
}

final expenseFilterProvider =
    NotifierProvider<ExpenseFilterNotifier, ExpenseFilter>(
      ExpenseFilterNotifier.new,
    );

/// The ledger page, filtered and paged in SQL.
final filteredExpensesProvider = FutureProvider<List<LocalExpense>>((ref) {
  // Re-read on a change of principal for the same reason `recentExpensesProvider` does:
  // a cached ledger must not outlive the session that filled it (D-072 acceptance).
  ref.watch(principalProvider);
  return ref
      .watch(expenseRepositoryProvider)
      .query(ref.watch(expenseFilterProvider));
});

class ExpenseFilterBar extends ConsumerWidget {
  const ExpenseFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(expenseFilterProvider);
    final graph = ref.watch(masterGraphProvider).value;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              key: const Key('ledger-search'),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Expense number or reference',
                prefixIcon: Icon(Icons.search, size: 16),
                border: OutlineInputBorder(borderRadius: AppRadius.allSmall),
              ),
              onChanged: (value) => ref
                  .read(expenseFilterProvider.notifier)
                  .update(filter.copyWith(search: value)),
            ),
          ),
          _UnitFilter(filter: filter, graph: graph),
          _Choice(
            label: 'Unpaid only',
            selected: filter.paymentStatus == 'unpaid',
            onChanged: (on) => ref
                .read(expenseFilterProvider.notifier)
                .update(
                  on
                      ? filter.copyWith(paymentStatus: 'unpaid')
                      : filter.copyWith(clearPayment: true),
                ),
          ),
          _Choice(
            label: 'Needs attention',
            selected: filter.syncState == SyncState.rejected,
            onChanged: (on) => ref
                .read(expenseFilterProvider.notifier)
                .update(
                  on
                      ? filter.copyWith(syncState: SyncState.rejected)
                      : filter.copyWith(clearSync: true),
                ),
          ),
          _Choice(
            label: 'Include voided',
            selected: filter.includeVoided,
            onChanged: (on) => ref
                .read(expenseFilterProvider.notifier)
                .update(filter.copyWith(includeVoided: on)),
          ),
          if (!filter.isEmpty)
            TextButton(
              onPressed: () => ref.read(expenseFilterProvider.notifier).clear(),
              child: const Text('Clear filters'),
            ),
          FilledButton.icon(
            key: const Key('add-expense'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<String>(
                builder: (_) => const ExpenseEntryPage(),
              ),
            ),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add expense'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ink,
              foregroundColor: AppColors.inkInverse,
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.allSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitFilter extends ConsumerWidget {
  const _UnitFilter({required this.filter, this.graph});

  final ExpenseFilter filter;
  final MasterGraph? graph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = graph?.businessUnits() ?? const [];
    if (units.length < 2) return const SizedBox.shrink();

    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String?>(
        key: const Key('ledger-unit-filter'),
        initialValue: filter.businessUnitId,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'Business unit',
          border: OutlineInputBorder(borderRadius: AppRadius.allSmall),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('All')),
          for (final unit in units)
            DropdownMenuItem(value: unit.id, child: Text(unit.name)),
        ],
        onChanged: (value) => ref
            .read(expenseFilterProvider.notifier)
            .update(
              value == null
                  ? filter.copyWith(clearUnit: true)
                  : filter.copyWith(businessUnitId: value),
            ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: onChanged,
    showCheckmark: false,
    selectedColor: AppColors.brassWash,
    side: BorderSide(
      color: selected ? AppColors.brass : AppColors.hairlineStrong,
    ),
  );
}
