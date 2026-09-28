/// The sales recorded lately, on a phone.
///
/// Deliberately **not** a ledger. The Windows ledger — filters, paging, a detail
/// panel, drill-down — is Slice 9, and building a small version of it here would be a
/// second surface to keep in step with the first. What this is for is the question an
/// operator asks straight after saving: *did that go in, and has it reached the office?*
///
/// So each row says the four things that answer it — which day, which category, what the
/// sale came to, and where it is in the sync lifecycle — and nothing else.
///
/// **Quarantined work is absent by construction.** An attempt kept through a confirmed
/// revocation (D-070) is excluded by the repository's own query, and there is no
/// parameter on this screen that could include it. That is not an oversight to be fixed
/// by adding a toggle: retained work reaches its own actor through a dedicated workflow,
/// and a list that could be made to show it is one somebody will eventually make show it
/// to the wrong person (D-074).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/components/sync_state_chip.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_detail_page.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_providers.dart';

class RevenueRecentPage extends ConsumerWidget {
  const RevenueRecentPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(recentRevenueProvider);
    final graphAsync = ref.watch(masterGraphProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Recent sales'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: switch (rowsAsync) {
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        AsyncError() => const _Empty(
          key: Key('revenue-recent-error'),
          icon: Icons.error_outline,
          title: 'Cannot read recent sales',
          body: 'Close and reopen this screen. Nothing has been lost.',
        ),
        AsyncData(:final value) when value.isEmpty => const _Empty(
          key: Key('revenue-recent-empty'),
          icon: Icons.point_of_sale_outlined,
          title: 'No sales recorded yet',
          body: 'Sales you record will appear here, with their sync status.',
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(recentRevenueProvider),
          child: ListView.separated(
            key: const Key('revenue-recent-list'),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: value.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.hairline),
            itemBuilder: (context, index) => _RevenueRow(
              row: value[index],
              // Drill-down: a figure a manager cannot open is a figure they cannot
              // question, and correcting one starts by looking at it (spec §11).
              onOpen: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RevenueDetailPage(entryId: value[index].id),
                ),
              ),
              categoryName: switch (graphAsync) {
                AsyncData(value: final graph) =>
                  graph.revenueCategory(value[index].revenueCategoryId)?.name,
                _ => null,
              },
            ),
          ),
        ),
      },
    );
  }
}

class _RevenueRow extends StatelessWidget {
  const _RevenueRow({required this.row, this.onOpen, this.categoryName});

  final RevenueLedgerRow row;
  final VoidCallback? onOpen;
  final String? categoryName;

  @override
  Widget build(BuildContext context) {
    final voided = row.voidedAt != null;

    return Semantics(
      // One label for the whole row, so a screen reader says the sale rather than
      // spelling out four disconnected fragments.
      label:
          '${categoryName ?? 'Sales'}, ${row.businessDate}, '
          'net ${MoneyFormatter.standard.format(row.net)}, '
          '${row.syncState.label}',
      child: ExcludeSemantics(
        child: Material(
          color: AppColors.surface,
          child: InkWell(
            onTap: onOpen,
            child: Container(
              key: Key('revenue-row-${row.id}'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              categoryName ?? 'Sales',
                              style: AppTypography.body.copyWith(
                                decoration: voided
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: voided
                                    ? AppColors.inkFaint
                                    : AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              // The server-issued number, once there is one. Never before: a
                              // reference that looks permanent and is not is worse than none
                              // (spec §8.4). The UUID is not shown — it is an identity, not a
                              // reference anybody can use.
                              '${row.businessDate.iso}'
                              '${row.txnNumber == null ? '' : ' · ${row.txnNumber}'}',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.inkMuted,
                              ),
                            ),
                            if (row.componentCount > 1) ...[
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                '${row.componentCount} amounts',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.inkFaint,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(
                            row.gross,
                            formatter: MoneyFormatter.standard,
                            style: AppTypography.body,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            'Net ${MoneyFormatter.standard.format(row.net)}',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // The status gets its own line, right-aligned under the figures.
                  //
                  // Not the compact chip: compact renders the icon alone, and "has this
                  // reached the office?" is the question this list exists to answer — an
                  // answer given only in colour and shape is one an operator has to learn
                  // rather than read (spec §22). The full label is long enough that keeping
                  // it beside the amounts overflowed a 430pt phone, which the widget suite
                  // caught and a screenshot would not have: the money still fitted.
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SyncStateChip(row.syncState),
                  ),

                  // The explanation runs the full width of the row rather than sitting in the
                  // right-hand column. A fixed-width box there overflowed a 430pt phone by
                  // five pixels, which the widget suite caught and a screenshot would not
                  // have — the figures still fitted.
                  if (row.syncState == SyncState.conflict) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: AppRadius.allSmall,
                      ),
                      // A tax mismatch is a financial disagreement, not a network problem,
                      // and never a silent repricing (D-114). The review action is Slice 10;
                      // what belongs here is the honest sentence.
                      child: Text(
                        'The tax configuration changed before this could sync. '
                        'Review the latest figures before continuing.',
                        key: Key('revenue-conflict-note-${row.id}'),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.syncConflict,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: AppColors.inkFaint),
          const SizedBox(height: AppSpacing.md),
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
