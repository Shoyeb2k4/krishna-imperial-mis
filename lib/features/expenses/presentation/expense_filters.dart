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
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_entry_page.dart';

/// What the ledger is currently showing.
@immutable
final class ExpenseFilter implements ExpenseQuery {
  const ExpenseFilter({
    this.from,
    this.to,
    this.businessUnitId,
    this.departmentId,
    this.sectionId,
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
  final String? departmentId;
  @override
  final String? sectionId;
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
    String? departmentId,
    String? sectionId,
    String? categoryId,
    String? vendorId,
    String? paymentStatus,
    SyncState? syncState,
    String? search,
    bool? includeVoided,
    bool clearDates = false,
    bool clearUnit = false,
    bool clearDepartment = false,
    bool clearSection = false,
    bool clearCategory = false,
    bool clearVendor = false,
    bool clearPayment = false,
    bool clearSync = false,
  }) => ExpenseFilter(
    from: clearDates ? null : (from ?? this.from),
    to: clearDates ? null : (to ?? this.to),
    businessUnitId: clearUnit ? null : (businessUnitId ?? this.businessUnitId),
    departmentId: clearDepartment ? null : (departmentId ?? this.departmentId),
    sectionId: clearSection ? null : (sectionId ?? this.sectionId),
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    vendorId: clearVendor ? null : (vendorId ?? this.vendorId),
    paymentStatus: clearPayment ? null : (paymentStatus ?? this.paymentStatus),
    syncState: clearSync ? null : (syncState ?? this.syncState),
    search: search ?? this.search,
    includeVoided: includeVoided ?? this.includeVoided,
  );

  /// The same filter with any child selection that no longer fits removed.
  ///
  /// The hierarchy is a chain — unit, department, section, category — and narrowing one
  /// rung can leave the rungs below it pointing somewhere unreachable. A stale child is
  /// worse than a wrong one: it is *hidden* behind a collapsed panel and silently
  /// intersects to nothing, so the ledger looks empty and nothing on screen says why
  /// (D-073 §20).
  ///
  /// Resolved against the master graph rather than guessed, so archived masters still
  /// resolve — history is filterable by a category nobody may use for new entries.
  ExpenseFilter withoutOrphanedChildren(MasterGraph graph) {
    var next = this;

    // Walked through `parentId` rather than through denormalised ancestors, because that
    // is what the graph actually holds: category → section → department → business unit.
    if (next.departmentId case final department?) {
      final node = graph.department(department);
      if (node == null ||
          (next.businessUnitId != null &&
              node.parentId != next.businessUnitId)) {
        next = next.copyWith(clearDepartment: true);
      }
    }

    if (next.sectionId case final section?) {
      final node = graph.section(section);
      final parent = node == null
          ? null
          : graph.department(node.parentId ?? '');
      final wrongDepartment =
          next.departmentId != null && node?.parentId != next.departmentId;
      final wrongUnit =
          next.businessUnitId != null &&
          parent?.parentId != next.businessUnitId;
      if (node == null || wrongDepartment || wrongUnit) {
        next = next.copyWith(clearSection: true);
      }
    }

    if (next.categoryId case final category?) {
      final node = graph.expenseCategory(category);
      final section = node == null ? null : graph.section(node.parentId ?? '');
      final department = section == null
          ? null
          : graph.department(section.parentId ?? '');
      final wrongSection =
          next.sectionId != null && node?.parentId != next.sectionId;
      final wrongDepartment =
          next.departmentId != null && section?.parentId != next.departmentId;
      final wrongUnit =
          next.businessUnitId != null &&
          department?.parentId != next.businessUnitId;
      if (node == null || wrongSection || wrongDepartment || wrongUnit) {
        next = next.copyWith(clearCategory: true);
      }
    }

    return next;
  }

  /// How many narrowing choices are active, for the button that hides them.
  int get activeCount => [
    from != null || to != null,
    businessUnitId != null,
    departmentId != null,
    sectionId != null,
    categoryId != null,
    vendorId != null,
    paymentStatus != null,
    syncState != null,
    includeVoided,
  ].where((active) => active).length;

  bool get isEmpty =>
      from == null &&
      to == null &&
      businessUnitId == null &&
      departmentId == null &&
      sectionId == null &&
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

  /// Applies a change, dropping any child selection the change has orphaned.
  ///
  /// The graph is read **here**, not passed in. An earlier version took it as an optional
  /// argument, and the Windows acceptance found what that costs: the business-unit
  /// control called the notifier directly, without one, so moving to the other property
  /// left its department selected behind a collapsed panel — the exact stale-filter case
  /// the rule exists for (D-073 §20). A caller cannot forget what it does not supply.
  void update(ExpenseFilter filter) {
    final graph = ref.read(masterGraphProvider).value;
    state = graph == null ? filter : filter.withoutOrphanedChildren(graph);
  }

  void clear() => state = const ExpenseFilter();
}

final expenseFilterProvider =
    NotifierProvider<ExpenseFilterNotifier, ExpenseFilter>(
      ExpenseFilterNotifier.new,
    );

/// How many documents one "Load more" adds to the ledger (D-317, D-323).
const expenseLedgerPageSize = 50;

/// Who the ledger is being read for: the person and every grant they hold.
///
/// A `Provider<String>` so Riverpod notifies only when the value changes: a session
/// refresh that leaves the person and their grants exactly as they were keeps the pages
/// a reader has loaded (D-245), while a different person or a changed capability starts
/// the ledger again from its first page.
final expenseLedgerAuthorityKeyProvider = Provider<String>((ref) {
  final principal = ref.watch(principalProvider);
  final grants = [
    for (final g in principal.grants)
      '${g.capability.code}@${g.businessUnitId ?? '*'}',
  ]..sort();
  return '${principal.userId}|${grants.join(',')}';
});

/// How many pages of the ledger are loaded.
///
/// Any change to the filter, the search or the reader's authority starts again from
/// one page. Staying on page six of a result set that changed underneath it is how a
/// ledger shows somebody rows from a question they are no longer asking.
class ExpenseLedgerPagesNotifier extends Notifier<int> {
  @override
  int build() {
    ref
      ..watch(expenseFilterProvider)
      ..watch(expenseLedgerAuthorityKeyProvider);
    return 1;
  }

  void loadMore() => state = state + 1;
}

final expenseLedgerPagesProvider =
    NotifierProvider<ExpenseLedgerPagesNotifier, int>(
      ExpenseLedgerPagesNotifier.new,
    );

/// What the ledger is showing, and which question it answers.
///
/// Stamped with the reader's authority and the exact filter and page count it was read
/// for, so a surface can refuse to show a window computed for somebody or something
/// else while the next one loads (D-074, D-231).
@immutable
final class ExpenseLedgerWindow {
  const ExpenseLedgerWindow({
    required this.authorityKey,
    required this.filter,
    required this.pages,
    required this.rows,
    required this.hasMore,
  });

  final String authorityKey;
  final ExpenseFilter filter;
  final int pages;

  /// Every matching document up to `pages × expenseLedgerPageSize`, in ledger order.
  final List<LocalExpense> rows;

  /// Whether at least one further matching document exists.
  final bool hasMore;
}

/// The loaded window of the ledger: every filter applied in SQL, then cut (D-317).
///
/// **One statement for the whole window**, not one per page appended to the last. A
/// page appended by OFFSET is cut against whatever the table held at that moment, so an
/// expense recorded or synced between two "Load more" presses would shift every later
/// page by one and show a row twice or never. Re-reading the window as one ordered
/// query cannot duplicate, skip or reorder anything, and the measurement shows the cost
/// does not justify anything cleverer (D-323).
///
/// Asks for one row beyond the window to learn whether more exist, rather than counting
/// the whole filtered set to draw a button.
///
/// **A stream (D-160).** A row's sync state arrives from the sync worker, which
/// invalidates no provider and knows about no screen.
final filteredExpensesProvider = StreamProvider<ExpenseLedgerWindow>((ref) {
  final key = ref.watch(expenseLedgerAuthorityKeyProvider);
  final filter = ref.watch(expenseFilterProvider);
  final pages = ref.watch(expenseLedgerPagesProvider);
  final limit = pages * expenseLedgerPageSize;

  return ref
      .watch(expenseRepositoryProvider)
      .watchQuery(filter, limit: limit + 1)
      .map(
        (rows) => ExpenseLedgerWindow(
          authorityKey: key,
          filter: filter,
          pages: pages,
          rows: rows.length > limit ? rows.sublist(0, limit) : rows,
          hasMore: rows.length > limit,
        ),
      );
});

/// The window to show, or null while the one for the current question is loading.
///
/// A provider re-reading keeps its previous value while it loads. That is right when a
/// sync lands and wrong the moment the person, their authority or the question changed:
/// the previous window answered something else (D-074, D-231). Compared by identity on
/// the filter, because the filter provider hands out a new object for every change.
ExpenseLedgerWindow? expenseLedgerShownTo(
  ExpenseLedgerWindow? window, {
  required String authorityKey,
  required ExpenseFilter filter,
}) {
  if (window == null) return null;
  if (window.authorityKey != authorityKey) return null;
  if (!identical(window.filter, filter)) return null;
  return window;
}

/// The desktop filter surface (D-073 §19).
///
/// **Progressive, not a wall.** Nine controls laid out at once is a form, and a finance
/// user opening the ledger to look at yesterday's spending should not have to read past
/// eight things they do not want. So the bar carries what is used constantly — a date
/// range, the search, the property — and everything else lives behind **Filters**, which
/// says how many are active so a narrowed ledger is never mysterious.
///
/// Every control feeds the one `ExpenseFilter`, which feeds the one SQL query. No widget
/// filters a list it was handed (spec §27, and the reason paging works at all).
class ExpenseFilterBar extends ConsumerStatefulWidget {
  const ExpenseFilterBar({super.key});

  @override
  ConsumerState<ExpenseFilterBar> createState() => _ExpenseFilterBarState();
}

class _ExpenseFilterBarState extends ConsumerState<ExpenseFilterBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(expenseFilterProvider);
    final graph = ref.watch(masterGraphProvider).value;

    void apply(ExpenseFilter next) =>
        ref.read(expenseFilterProvider.notifier).update(next);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── The bar itself ────────────────────────────────────────────────
          Wrap(
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
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.allSmall,
                    ),
                  ),
                  onChanged: (value) => apply(filter.copyWith(search: value)),
                ),
              ),
              _DateRangeFilter(filter: filter, onChanged: apply),
              _UnitFilter(filter: filter, graph: graph),
              OutlinedButton.icon(
                key: const Key('ledger-more-filters'),
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.tune,
                  size: 16,
                ),
                label: Text(
                  filter.activeCount == 0
                      ? 'Filters'
                      : 'Filters · ${filter.activeCount}',
                ),
              ),
              if (!filter.isEmpty)
                TextButton(
                  key: const Key('ledger-clear-filters'),
                  onPressed: () =>
                      ref.read(expenseFilterProvider.notifier).clear(),
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

          // ── Everything else, closed by default ────────────────────────────
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              key: const Key('ledger-filter-panel'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: AppRadius.allSmall,
                border: Border.all(color: AppColors.hairline),
              ),
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _HierarchyFilter(
                    fieldKey: const Key('ledger-department-filter'),
                    label: 'Department',
                    selected: filter.departmentId,
                    // Narrowed by the property when one is chosen, and offering
                    // everything when none is — the chain is a chain in both directions.
                    options: _departments(graph, filter.businessUnitId),
                    onChanged: (value) => apply(
                      value == null
                          ? filter.copyWith(clearDepartment: true)
                          : filter.copyWith(departmentId: value),
                    ),
                  ),
                  _HierarchyFilter(
                    fieldKey: const Key('ledger-section-filter'),
                    label: 'Section',
                    selected: filter.sectionId,
                    options: _sections(graph, filter),
                    onChanged: (value) => apply(
                      value == null
                          ? filter.copyWith(clearSection: true)
                          : filter.copyWith(sectionId: value),
                    ),
                  ),
                  _HierarchyFilter(
                    fieldKey: const Key('ledger-category-filter'),
                    label: 'Category',
                    selected: filter.categoryId,
                    options: _categories(graph, filter),
                    onChanged: (value) => apply(
                      value == null
                          ? filter.copyWith(clearCategory: true)
                          : filter.copyWith(categoryId: value),
                    ),
                  ),
                  _VendorFilter(filter: filter, onChanged: apply),
                  _PaymentFilter(filter: filter, onChanged: apply),
                  _StatusFilter(filter: filter, onChanged: apply),
                  _Choice(
                    label: 'Include voided',
                    selected: filter.includeVoided,
                    onChanged: (on) =>
                        apply(filter.copyWith(includeVoided: on)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Departments, narrowed to the chosen property when there is one.
  ///
  /// Archived masters are included: history is filterable by a department nobody may use
  /// for new entries, which is the whole point of archiving rather than deleting (D-035).
  List<MasterNode> _departments(MasterGraph? graph, String? unitId) {
    if (graph == null) return const [];
    if (unitId != null) {
      return graph.departmentsOf(unitId, includeArchived: true);
    }
    return [
      for (final unit in graph.businessUnits())
        ...graph.departmentsOf(unit.id, includeArchived: true),
    ];
  }

  List<MasterNode> _sections(MasterGraph? graph, ExpenseFilter filter) {
    if (graph == null) return const [];
    final parents = filter.departmentId != null
        ? [filter.departmentId!]
        : _departments(graph, filter.businessUnitId).map((d) => d.id);
    return [
      for (final parent in parents)
        ...graph.sectionsOf(parent, includeArchived: true),
    ];
  }

  List<MasterNode> _categories(MasterGraph? graph, ExpenseFilter filter) {
    if (graph == null) return const [];
    final parents = filter.sectionId != null
        ? [filter.sectionId!]
        : _sections(graph, filter).map((s) => s.id);
    return [
      for (final parent in parents)
        ...graph.categoriesOf(parent, includeArchived: true),
    ];
  }
}

/// A hierarchy rung, as a dropdown that offers "All".
class _HierarchyFilter extends StatelessWidget {
  const _HierarchyFilter({
    required this.fieldKey,
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String? selected;
  final List<MasterNode> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: DropdownButtonFormField<String?>(
      key: fieldKey,
      // Guarded: a selection the options no longer contain would assert inside the
      // dropdown. The filter clears orphans itself, and this is the belt to that brace.
      initialValue: options.any((o) => o.id == selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder(borderRadius: AppRadius.allSmall),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('All')),
        for (final option in options)
          DropdownMenuItem(value: option.id, child: Text(option.name)),
      ],
      onChanged: onChanged,
    ),
  );
}

/// The business date range, as one control rather than two loose dates.
class _DateRangeFilter extends StatelessWidget {
  const _DateRangeFilter({required this.filter, required this.onChanged});

  final ExpenseFilter filter;
  final ValueChanged<ExpenseFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = filter.from == null && filter.to == null
        ? 'Any date'
        : '${filter.from ?? "…"} → ${filter.to ?? "…"}';

    return OutlinedButton.icon(
      key: const Key('ledger-date-range'),
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime.utc(2020),
          lastDate: DateTime.utc(now.year + 1, 12, 31),
          helpText: 'Business date range',
        );
        if (picked == null) return;
        onChanged(
          filter.copyWith(from: _iso(picked.start), to: _iso(picked.end)),
        );
      },
      onLongPress: () => onChanged(filter.copyWith(clearDates: true)),
      icon: const Icon(Icons.date_range_outlined, size: 16),
      label: Text(label),
    );
  }

  /// The ledger stores business dates as ISO text, so the filter speaks the same
  /// language the column does and the comparison stays an index scan.
  static String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _VendorFilter extends ConsumerWidget {
  const _VendorFilter({required this.filter, required this.onChanged});

  final ExpenseFilter filter;
  final ValueChanged<ExpenseFilter> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(vendorListProvider(true)).value ?? const [];
    if (vendors.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String?>(
        key: const Key('ledger-vendor-filter'),
        initialValue: filter.vendorId,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          labelText: 'Vendor',
          border: OutlineInputBorder(borderRadius: AppRadius.allSmall),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('All')),
          for (final vendor in vendors)
            DropdownMenuItem(value: vendor.id, child: Text(vendor.name)),
        ],
        onChanged: (value) => onChanged(
          value == null
              ? filter.copyWith(clearVendor: true)
              : filter.copyWith(vendorId: value),
        ),
      ),
    );
  }
}

class _PaymentFilter extends StatelessWidget {
  const _PaymentFilter({required this.filter, required this.onChanged});

  final ExpenseFilter filter;
  final ValueChanged<ExpenseFilter> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: DropdownButtonFormField<String?>(
      key: const Key('ledger-payment-filter'),
      initialValue: filter.paymentStatus,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'Payment',
        border: OutlineInputBorder(borderRadius: AppRadius.allSmall),
      ),
      items: const [
        DropdownMenuItem(value: null, child: Text('Any')),
        DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
        DropdownMenuItem(value: 'paid', child: Text('Paid')),
      ],
      onChanged: (value) => onChanged(
        value == null
            ? filter.copyWith(clearPayment: true)
            : filter.copyWith(paymentStatus: value),
      ),
    ),
  );
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.filter, required this.onChanged});

  final ExpenseFilter filter;
  final ValueChanged<ExpenseFilter> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: DropdownButtonFormField<SyncState?>(
      key: const Key('ledger-status-filter'),
      initialValue: filter.syncState,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        labelText: 'Status',
        border: OutlineInputBorder(borderRadius: AppRadius.allSmall),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Any')),
        for (final state in const [
          SyncState.synced,
          SyncState.pendingSync,
          SyncState.syncFailed,
          SyncState.conflict,
          SyncState.rejected,
        ])
          DropdownMenuItem(value: state, child: Text(state.label)),
      ],
      onChanged: (value) => onChanged(
        value == null
            ? filter.copyWith(clearSync: true)
            : filter.copyWith(syncState: value),
      ),
    ),
  );
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
