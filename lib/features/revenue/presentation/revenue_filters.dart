/// What the Windows revenue ledger is being asked for, and the bar that asks it.
///
/// The model is pure Dart implementing [RevenueQuery], so the repository never learns
/// that a filter bar exists and the dependency rules a user experiences — changing the
/// property clears a category that belonged to the other one — are unit-testable without
/// a widget.
///
/// **The dependency rule is not cosmetic.** `Hotel Krishna Imperial + Restaurant` selects
/// nothing, because Restaurant is a Crystal Canopy category; leaving it selected would
/// present an empty ledger as though there were no sales, when in fact the question was
/// unanswerable. The same cascade the entry form uses, for the same reason.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_draft.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_providers.dart';

final class RevenueFilter implements RevenueQuery {
  const RevenueFilter({
    this.from,
    this.to,
    this.businessUnitId,
    this.revenueCategoryId,
    this.entryKind,
    this.enteredByUserId,
    this.syncState,
    this.search,
    this.includeVoided = false,
    this.businessUnitIds,
  });

  /// ISO dates, because that is how the local column stores them and comparing text to
  /// text keeps the query a plain index scan.
  ///
  /// Against the **business date** (D-067), never the capture instant: a sale rung up at
  /// 02:00 belongs to the previous trading day, and a ledger that filtered on the device
  /// timestamp would put it in the wrong month of somebody's report.
  @override
  final String? from;
  @override
  final String? to;

  @override
  final String? businessUnitId;
  @override
  final String? revenueCategoryId;
  @override
  final RevenueEntryKind? entryKind;
  @override
  final String? enteredByUserId;
  @override
  final SyncState? syncState;

  /// Matches a transaction number, a source reference or a note. Nothing clever — a
  /// finance user looking for `KI-REV-26-27-000042` wants that document and no others.
  ///
  /// The UUID is deliberately not searchable: it is an identity, not a reference anybody
  /// reads off a screen.
  @override
  final String? search;

  /// Voided documents are out of the default view and one toggle away, never hidden
  /// outright: they are history, and history has to be reachable (D-006).
  @override
  final bool includeVoided;

  /// Authority, not a choice. Set from the confirmed scope, and applied in SQL so a
  /// paging window is never computed over rows this reader may not have.
  @override
  final Set<String>? businessUnitIds;

  bool get isDefault =>
      from == null &&
      to == null &&
      businessUnitId == null &&
      revenueCategoryId == null &&
      entryKind == null &&
      enteredByUserId == null &&
      syncState == null &&
      (search == null || search!.trim().isEmpty) &&
      !includeVoided;

  RevenueFilter copyWith({
    String? from,
    String? to,
    String? businessUnitId,
    String? revenueCategoryId,
    RevenueEntryKind? entryKind,
    String? enteredByUserId,
    SyncState? syncState,
    String? search,
    bool? includeVoided,
    Set<String>? businessUnitIds,
    bool clearDates = false,
    bool clearUnit = false,
    bool clearCategory = false,
    bool clearKind = false,
    bool clearActor = false,
    bool clearSync = false,
    bool clearSearch = false,
  }) => RevenueFilter(
    from: clearDates ? null : (from ?? this.from),
    to: clearDates ? null : (to ?? this.to),
    businessUnitId: clearUnit ? null : (businessUnitId ?? this.businessUnitId),
    revenueCategoryId: clearCategory
        ? null
        : (revenueCategoryId ?? this.revenueCategoryId),
    entryKind: clearKind ? null : (entryKind ?? this.entryKind),
    enteredByUserId: clearActor
        ? null
        : (enteredByUserId ?? this.enteredByUserId),
    syncState: clearSync ? null : (syncState ?? this.syncState),
    search: clearSearch ? null : (search ?? this.search),
    includeVoided: includeVoided ?? this.includeVoided,
    businessUnitIds: businessUnitIds ?? this.businessUnitIds,
  );

  /// Chooses a property, clearing a category that belonged to the previous one.
  ///
  /// The cascade is the point. `Hotel Krishna Imperial + Restaurant` matches nothing,
  /// and an empty ledger that looks like "no sales" rather than "impossible question" is
  /// worse than no filter at all.
  RevenueFilter withBusinessUnit(String? unitId, MasterGraph graph) {
    if (unitId == businessUnitId) return this;
    final category = revenueCategoryId;
    final stillValid =
        category != null &&
        unitId != null &&
        graph.revenueCategoriesOf(unitId).any((c) => c.id == category);

    return copyWith(
      businessUnitId: unitId,
      clearUnit: unitId == null,
      clearCategory: !stillValid,
    );
  }

  /// Drops anything the confirmed scope no longer permits.
  ///
  /// Called when authority changes. A filter naming a property this user has lost would
  /// otherwise sit there returning nothing, which reads as an empty ledger rather than as
  /// a revoked permission (D-070).
  RevenueFilter constrainedTo(Set<String>? permitted, MasterGraph graph) {
    if (permitted == null) return copyWith(businessUnitIds: null);

    final unitStillHeld =
        businessUnitId == null || permitted.contains(businessUnitId);
    final category = revenueCategoryId;
    final categoryStillHeld =
        category == null ||
        permitted.any(
          (unit) =>
              graph.revenueCategoriesOf(unit).any((c) => c.id == category),
        );

    return copyWith(
      businessUnitIds: permitted,
      clearUnit: !unitStillHeld,
      clearCategory: !categoryStillHeld,
    );
  }
}

class RevenueFilterNotifier extends Notifier<RevenueFilter> {
  @override
  RevenueFilter build() {
    // Authority decides what this filter may name, and re-decides it whenever the
    // signed-in principal changes — which is what makes a user switch drop a filter the
    // next person does not hold, rather than serving them an empty ledger.
    final authority = ref.watch(revenueAuthorityProvider);
    final graph = switch (ref.watch(masterGraphProvider)) {
      AsyncData(:final value) => value,
      _ => MasterGraph.empty(),
    };

    final permitted = authority == null
        ? <String>{}
        : {
            for (final unit in RevenueDraft.permittedUnits(graph, authority))
              unit.id,
          };

    return RevenueFilter(businessUnitIds: permitted);
  }

  void update(RevenueFilter next) => state = next;

  void setBusinessUnit(String? unitId) {
    final graph = switch (ref.read(masterGraphProvider)) {
      AsyncData(:final value) => value,
      _ => MasterGraph.empty(),
    };
    state = state.withBusinessUnit(unitId, graph);
  }

  /// Back to the default view, keeping the authority constraint.
  ///
  /// Scope is not a filter and is not reset with one: clearing it would widen the query
  /// beyond what the reader may see.
  void reset() => state = RevenueFilter(businessUnitIds: state.businessUnitIds);
}

final revenueFilterProvider =
    NotifierProvider<RevenueFilterNotifier, RevenueFilter>(
      RevenueFilterNotifier.new,
    );

/// How many rows one page of the ledger holds.
const revenuePageSize = 50;

/// Which page of the ledger is showing.
///
/// A filter change returns to the first page. Staying on page four of a result set that
/// no longer has four pages is how a ledger shows an operator nothing and looks broken.
class RevenuePageNotifier extends Notifier<int> {
  @override
  int build() {
    ref.watch(revenueFilterProvider);
    return 0;
  }

  void next() => state = state + 1;
  void previous() => state = state == 0 ? 0 : state - 1;
  void first() => state = 0;
}

final revenuePageProvider = NotifierProvider<RevenuePageNotifier, int>(
  RevenuePageNotifier.new,
);

/// The current page of the ledger.
///
/// **A stream, not a one-shot read (D-160).** A row's sync state arrives from the
/// sync worker, which invalidates no provider and knows about no screen, so a
/// `FutureProvider` here kept whatever state it saw when the query last ran: a
/// corrected sale that had since been accepted went on reading `Syncing`
/// indefinitely. That is D-131, which was fixed for the detail panel and left
/// standing on the ledger.
final filteredRevenueProvider = StreamProvider<List<RevenueLedgerRow>>((ref) {
  ref.watch(principalProvider);
  final filter = ref.watch(revenueFilterProvider);
  final page = ref.watch(revenuePageProvider);

  return ref
      .watch(revenueRepositoryProvider)
      .watchQuery(
        filter,
        limit: revenuePageSize,
        offset: page * revenuePageSize,
      );
});

/// Whether a further page exists, asked by fetching one row beyond this page.
///
/// Cheaper and more honest than a `COUNT(*)` over the whole filtered set, which at a year
/// of history is a scan performed to render an arrow.
final revenueHasMoreProvider = StreamProvider<bool>((ref) {
  ref.watch(principalProvider);
  final filter = ref.watch(revenueFilterProvider);
  final page = ref.watch(revenuePageProvider);

  return ref
      .watch(revenueRepositoryProvider)
      .watchQuery(filter, limit: 1, offset: (page + 1) * revenuePageSize)
      .map((next) => next.isNotEmpty);
});

class RevenueFilterBar extends ConsumerStatefulWidget {
  const RevenueFilterBar({super.key});

  @override
  ConsumerState<RevenueFilterBar> createState() => _RevenueFilterBarState();
}

class _RevenueFilterBarState extends ConsumerState<RevenueFilterBar> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(revenueFilterProvider).search ?? '',
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(revenueFilterProvider);
    final notifier = ref.read(revenueFilterProvider.notifier);
    final graph = switch (ref.watch(masterGraphProvider)) {
      AsyncData(:final value) => value,
      _ => MasterGraph.empty(),
    };
    final authority = ref.watch(revenueAuthorityProvider);
    final units = RevenueDraft.permittedUnits(graph, authority);

    // Only the selected property's categories. Offering all of them would let somebody
    // build a filter pair that cannot match anything.
    final categories = filter.businessUnitId == null
        ? [for (final unit in units) ...graph.revenueCategoriesOf(unit.id)]
        : graph.revenueCategoriesOf(filter.businessUnitId!);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              key: const Key('revenue-filter-search'),
              controller: _search,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Number, reference or note',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) =>
                  notifier.update(filter.copyWith(search: value)),
              onChanged: (value) => notifier.update(
                filter.copyWith(search: value, clearSearch: value.isEmpty),
              ),
            ),
          ),
          _DateField(
            keyName: 'revenue-filter-from',
            label: 'From',
            value: filter.from,
            onChanged: (iso) => notifier.update(
              filter.copyWith(from: iso, clearDates: iso == null),
            ),
          ),
          _DateField(
            keyName: 'revenue-filter-to',
            label: 'To',
            value: filter.to,
            onChanged: (iso) => notifier.update(
              filter.copyWith(to: iso, clearDates: iso == null),
            ),
          ),
          _Dropdown<String>(
            keyName: 'revenue-filter-unit',
            label: 'Property',
            value: filter.businessUnitId,
            options: [
              for (final unit in units) (value: unit.id, label: unit.name),
            ],
            onChanged: notifier.setBusinessUnit,
          ),
          _Dropdown<String>(
            keyName: 'revenue-filter-category',
            label: 'Category',
            value: filter.revenueCategoryId,
            options: [
              for (final category in categories)
                (value: category.id, label: category.name),
            ],
            onChanged: (id) => notifier.update(
              filter.copyWith(revenueCategoryId: id, clearCategory: id == null),
            ),
          ),
          _Dropdown<SyncState>(
            keyName: 'revenue-filter-status',
            label: 'Status',
            value: filter.syncState,
            options: [
              // The canonical vocabulary, not a second one invented here (spec §22).
              for (final state in const [
                SyncState.synced,
                SyncState.pendingSync,
                SyncState.syncFailed,
                SyncState.conflict,
                SyncState.rejected,
              ])
                (value: state, label: state.label),
            ],
            onChanged: (state) => notifier.update(
              filter.copyWith(syncState: state, clearSync: state == null),
            ),
          ),
          FilterChip(
            key: const Key('revenue-filter-voided'),
            label: const Text('Include voided'),
            selected: filter.includeVoided,
            onSelected: (on) =>
                notifier.update(filter.copyWith(includeVoided: on)),
          ),
          if (!filter.isDefault)
            TextButton.icon(
              key: const Key('revenue-filter-reset'),
              onPressed: () {
                _search.clear();
                notifier.reset();
              },
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.keyName,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String keyName;
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: OutlinedButton.icon(
      key: Key(keyName),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(value ?? '') ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          onChanged(
            '${picked.year.toString().padLeft(4, '0')}-'
            '${picked.month.toString().padLeft(2, '0')}-'
            '${picked.day.toString().padLeft(2, '0')}',
          );
        }
      },
      icon: const Icon(Icons.event_outlined, size: 16),
      label: Text(
        value ?? label,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption,
      ),
    ),
  );
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.keyName,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String keyName;
  final String label;
  final T? value;
  final List<({T value, String label})> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: DropdownButtonFormField<T>(
      key: Key(keyName),
      initialValue: value,
      isDense: true,
      // Without this the selected item lays itself out at its natural width and pushes
      // the field 200-odd pixels past its box — the Slice 8 overflow again, in a filter
      // bar rather than a status column. `isExpanded` makes the ellipsis do its job.
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<T>(child: Text('All $label'.toLowerCase())),
        for (final option in options)
          DropdownMenuItem<T>(
            value: option.value,
            child: Text(option.label, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}
