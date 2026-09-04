/// Sales, on the finance workstation.
///
/// A dense table with a persistent detail panel — the Windows shape the expense ledger
/// already established, because a finance user moving between the two should not have to
/// learn a second one.
///
/// Two things it does **not** do, and both are deliberate.
///
/// It does not load the ledger and narrow it in Dart: filtering, ordering and paging all
/// happen in SQL (`RevenueRepository.query`). At a year of history that is the difference
/// between a screen that opens and one that does not (spec §27).
///
/// It does not offer edit or void. Those are Slice 10, and a button that implied them
/// would be a control with nothing behind it — the D-077 mistake, which reached two real
/// devices before anybody noticed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/components/sync_state_chip.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_draft.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_entry_page.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_filters.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_providers.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_detail_panel.dart';

class RevenueLedgerPage extends ConsumerStatefulWidget {
  const RevenueLedgerPage({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  ConsumerState<RevenueLedgerPage> createState() => _RevenueLedgerPageState();
}

class _RevenueLedgerPageState extends ConsumerState<RevenueLedgerPage> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(filteredRevenueProvider);
    final desktop = widget.shellKind == AppShellKind.desktop;

    return switch (rows) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error) => _Empty(
        key: const Key('revenue-ledger-error'),
        title: 'The sales ledger could not be read',
        body: '$error',
      ),
      AsyncData(:final value) => desktop ? _desktop(value) : _mobile(value),
    };
  }

  /// Whether the empty result is "nothing recorded" or "nothing matches".
  ///
  /// Two different sentences, and telling somebody the first when the second is true
  /// sends them looking for a missing entry that is simply filtered out.
  Widget _emptyFor(bool filtered) => filtered
      ? const _Empty(
          key: Key('revenue-ledger-no-matches'),
          title: 'No sales match these filters',
          body: 'Widen the date range, or clear the filters above.',
        )
      : const _Empty(
          key: Key('revenue-ledger-empty'),
          title: 'No sales recorded yet',
          body: 'Use Add Sale to record one. It works offline.',
        );

  Widget _desktop(List<RevenueLedgerRow> rows) {
    final filter = ref.watch(revenueFilterProvider);
    final authority = ref.watch(revenueAuthorityProvider);
    final graph = switch (ref.watch(masterGraphProvider)) {
      AsyncData(:final value) => value,
      _ => MasterGraph.empty(),
    };

    if (RevenueDraft.permittedUnits(graph, authority).isEmpty) {
      return const _Empty(
        key: Key('revenue-ledger-no-scope'),
        title: 'No properties available',
        body:
            'You do not have permission to see sales for any property. '
            'Ask the Owner to grant access.',
      );
    }

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _LedgerHeader(),
              const Divider(height: 1, color: AppColors.hairline),
              const RevenueFilterBar(),
              const Divider(height: 1, color: AppColors.hairline),
              Expanded(
                child: rows.isEmpty
                    ? _emptyFor(!filter.isDefault)
                    : _LedgerTable(
                        rows: rows,
                        selectedId: _selectedId,
                        onSelect: (id) => setState(() => _selectedId = id),
                      ),
              ),
              const Divider(height: 1, color: AppColors.hairline),
              const _Pager(),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.hairline),
        SizedBox(
          width: 380,
          child: _selectedId == null
              ? const _Empty(
                  title: 'Nothing selected',
                  body: 'Choose a sale to see how its tax was calculated.',
                )
              : RevenueDetailPanel(entryId: _selectedId!),
        ),
      ],
    );
  }

  /// Android already has its own recent-sales surface; this arm exists so the page can be
  /// mounted in either shell without becoming a shrunken table (spec §18).
  Widget _mobile(List<RevenueLedgerRow> rows) {
    final filter = ref.watch(revenueFilterProvider);
    if (rows.isEmpty) return _emptyFor(!filter.isDefault);

    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: AppSpacing.lg),
      itemBuilder: (context, index) {
        final row = rows[index];
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                backgroundColor: AppColors.paper,
                appBar: AppBar(title: Text(row.displayReference)),
                body: RevenueDetailPanel(entryId: row.id),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.displayReference, style: AppTypography.body),
                      Text(
                        row.businessDate.iso,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                MoneyText(row.gross, style: AppTypography.body),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LedgerHeader extends ConsumerWidget {
  const _LedgerHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.sm,
    ),
    child: Row(
      children: [
        Text('Sales', style: AppTypography.subheading),
        const Spacer(),
        FilledButton.icon(
          key: const Key('add-revenue'),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<String>(
                builder: (_) => const RevenueEntryPage(),
              ),
            );
            // The ledger is a cached read model, so it has to be told. Without this a
            // finance user records a sale, returns to the ledger, and does not see it —
            // which reads as "my entry was lost" rather than as a stale cache. The
            // Windows expense acceptance found exactly this, one engine earlier.
            ref
              ..invalidate(filteredRevenueProvider)
              ..invalidate(revenueHasMoreProvider)
              ..invalidate(recentRevenueProvider);
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.inkInverse,
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Sale'),
        ),
      ],
    ),
  );
}

class _Pager extends ConsumerWidget {
  const _Pager();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(revenuePageProvider);
    final hasMore = switch (ref.watch(revenueHasMoreProvider)) {
      AsyncData(:final value) => value,
      _ => false,
    };
    final notifier = ref.read(revenuePageProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Page ${page + 1}',
            key: const Key('revenue-page-label'),
            style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
          ),
          const SizedBox(width: AppSpacing.md),
          IconButton(
            key: const Key('revenue-page-previous'),
            tooltip: 'Previous page',
            onPressed: page == 0 ? null : notifier.previous,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            key: const Key('revenue-page-next'),
            tooltip: 'Next page',
            onPressed: hasMore ? notifier.next : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _LedgerTable extends ConsumerWidget {
  const _LedgerTable({
    required this.rows,
    required this.selectedId,
    required this.onSelect,
  });

  final List<RevenueLedgerRow> rows;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graph = switch (ref.watch(masterGraphProvider)) {
      AsyncData(:final value) => value,
      _ => MasterGraph.empty(),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        // Derived from the columns rather than written down beside them. A hand-picked
        // number drifts from the widths it is meant to cover — this one did, by 230
        // pixels, and the table overflowed on an ordinary laptop until the widget suite
        // rendered it at that size.
        //
        // Below this the columns cannot hold a rupee figure without truncating it, and a
        // truncated financial value is worse than a scrollbar, so narrower windows scroll
        // horizontally rather than eliding money.
        final minimumWidth = _minimumTableWidth;
        final table = SizedBox(
          width: constraints.maxWidth < minimumWidth
              ? minimumWidth
              : constraints.maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeaderRow(),
              const Divider(height: 1, color: AppColors.hairline),
              Expanded(
                child: ListView.separated(
                  key: const Key('revenue-ledger-table'),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.hairline),
                  itemBuilder: (_, index) => _Row(
                    row: rows[index],
                    unitName:
                        graph.businessUnit(rows[index].businessUnitId)?.name ??
                        '—',
                    categoryName:
                        graph
                            .revenueCategory(rows[index].revenueCategoryId)
                            ?.name ??
                        '—',
                    selected: rows[index].id == selectedId,
                    onTap: () => onSelect(rows[index].id),
                  ),
                ),
              ),
            ],
          ),
        );

        return constraints.maxWidth < minimumWidth
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              )
            : table;
      },
    );
  }
}

/// The narrowest the table may be drawn without truncating a financial value.
///
/// The sum of the columns plus the row's horizontal padding, computed from the widths
/// themselves so the two cannot drift apart.
final _minimumTableWidth =
    _columns.date +
    _columns.number +
    _columns.unit +
    _columns.category +
    _columns.money * 3 +
    _columns.status +
    _columns.actor +
    AppSpacing.md * 2;

/// Column widths, declared once so the header and every row cannot disagree.
const _columns = (
  date: 104.0,
  number: 168.0,
  unit: 150.0,
  category: 130.0,
  money: 120.0,
  status: 150.0,
  actor: 110.0,
);

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.surfaceMuted,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    child: Row(
      children: [
        _head('Date', _columns.date),
        _head('Transaction no.', _columns.number),
        _head('Property', _columns.unit),
        _head('Category', _columns.category),
        _head('Sales total', _columns.money, right: true),
        _head('GST', _columns.money, right: true),
        _head('Net sales', _columns.money, right: true),
        _head('Status', _columns.status),
        _head('Entered by', _columns.actor),
      ],
    ),
  );

  static Widget _head(String label, double width, {bool right = false}) =>
      SizedBox(
        width: width,
        child: Text(
          label,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: AppTypography.overline,
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.row,
    required this.unitName,
    required this.categoryName,
    required this.selected,
    required this.onTap,
  });

  final RevenueLedgerRow row;
  final String unitName;
  final String categoryName;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final voided = row.voidedAt != null;
    final ink = voided ? AppColors.inkFaint : AppColors.ink;

    return InkWell(
      key: Key('revenue-ledger-row-${row.id}'),
      onTap: onTap,
      child: Container(
        color: selected ? AppColors.brassWash : AppColors.surface,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            _cell(row.businessDate.iso, _columns.date, ink),
            SizedBox(
              width: _columns.number,
              child: Text(
                row.displayReference,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  color: row.txnNumber == null ? AppColors.inkMuted : ink,
                  decoration: voided ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            _cell(unitName, _columns.unit, ink),
            _cell(categoryName, _columns.category, ink),
            _money(row.gross, ink),
            _money(row.tax, voided ? AppColors.inkFaint : AppColors.inkMuted),
            _money(row.net, ink),
            SizedBox(
              width: _columns.status,
              child: Align(
                alignment: Alignment.centerLeft,
                // Voided is a state of the *document*, not of its sync, so it is said
                // rather than folded into the sync chip — a voided sale is fully synced
                // and would otherwise read as though nothing had happened to it.
                child: voided
                    ? const _VoidedChip()
                    : SyncStateChip(row.syncState, compact: true),
              ),
            ),
            _cell(
              _shortActor(row.createdBy),
              _columns.actor,
              AppColors.inkMuted,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _cell(String text, double width, Color color) => SizedBox(
    width: width,
    child: Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.body.copyWith(color: color),
    ),
  );

  Widget _money(Money amount, Color color) => SizedBox(
    width: _columns.money,
    child: MoneyText(
      amount,
      formatter: MoneyFormatter.standard,
      style: AppTypography.body.copyWith(color: color),
    ),
  );

  /// A short, stable handle for the actor.
  ///
  /// The full id is diagnostic detail and belongs in the panel, not in a column an
  /// operator scans. A display name would be better still and needs a profile cache the
  /// client does not have yet — recorded rather than faked.
  static String _shortActor(String userId) =>
      userId.length <= 8 ? userId : userId.substring(0, 8).toUpperCase();
}

class _VoidedChip extends StatelessWidget {
  const _VoidedChip();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('revenue-voided-chip'),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.inkFaint),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.block_outlined, size: 12, color: AppColors.inkFaint),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          'Voided',
          style: AppTypography.caption.copyWith(color: AppColors.inkFaint),
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.body, super.key});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
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
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: AppTypography.body.copyWith(color: AppColors.inkMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
