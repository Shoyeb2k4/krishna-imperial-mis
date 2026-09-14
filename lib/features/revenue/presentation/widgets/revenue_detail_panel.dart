/// One sale, as the ledger shows it: the immutable document body, and the ledger's own
/// status, banners and controls composed around it.
///
/// The figures, rule snapshots and evidence list come from [RevenueDocumentBody], which
/// owns no action. What a person may *do* here — correct, void, review the latest version,
/// attach evidence — is this surface's, and is composed into the body's slots. The P&L
/// drill-down renders the same body with none of them (Phase 5 Slice 10).
///
/// **Nothing here consults today's tax configuration**; the body reads every figure from
/// the component's own snapshot (D-080, D-091).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/components/sync_state_chip.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_providers.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_actions.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_conflict.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_document_body.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_evidence.dart';

class RevenueDetailPanel extends ConsumerWidget {
  const RevenueDetailPanel({required this.entryId, super.key});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(revenueDetailProvider(entryId));
    final graph = switch (ref.watch(masterGraphProvider)) {
      AsyncData(:final value) => value,
      _ => MasterGraph.empty(),
    };
    // From the outbox, not from whichever ledger query happened to have run: the phone
    // reaches this surface with no ledger loaded at all.
    final syncState = switch (ref.watch(revenueSyncStateProvider(entryId))) {
      AsyncData(:final value) => value,
      _ => null,
    };

    // A value that has been loaded once keeps being shown while it is re-read, rather than
    // flashing to a spinner every time the outbox moves.
    return switch (entry) {
      AsyncValue(hasValue: true, value: null) => const _Message(
        key: Key('revenue-detail-missing'),
        text: 'This sale is no longer in the local ledger.',
      ),
      AsyncValue(hasValue: true, :final value) => RevenueDocumentBody(
        entry: value!,
        graph: graph,
        status: syncState == null ? null : SyncStateChip(syncState),
        attention: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Two defensible answers and nobody entitled to overwrite the other. Nothing is
            // merged, and the only forward action re-reads the record first.
            if (syncState == SyncState.conflict)
              _ConflictBanner(entry: value)
            else if (syncState == SyncState.rejected)
              const _RejectedBanner(),
            // Correction and void, offered only where the capability and the document's
            // own state permit. A voided sale offers neither and says so.
            RevenueActions(entry: value),
          ],
        ),
        evidence: RevenueEvidence(entry: value),
      ),
      AsyncError() => const _Message(
        key: Key('revenue-detail-error'),
        text: 'This sale could not be read.',
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class _ConflictBanner extends ConsumerWidget {
  const _ConflictBanner({required this.entry});

  final RevenueEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    key: const Key('revenue-conflict-banner'),
    margin: const EdgeInsets.only(top: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.syncConflict),
      borderRadius: AppRadius.allSmall,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Conflict · this sale changed',
          style: AppTypography.body.copyWith(color: AppColors.syncConflict),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your correction was based on an earlier version, or on tax '
          'configuration that has since changed. Nothing has been overwritten. '
          'Review what the sale says now and correct it again if it still '
          'applies.',
          style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          key: const Key('revenue-conflict-review-latest'),
          onPressed: () => reviewLatestRevenue(context, ref, entry),
          child: const Text('Review latest'),
        ),
      ],
    ),
  );
}

class _RejectedBanner extends StatelessWidget {
  const _RejectedBanner();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('revenue-rejected-banner'),
    margin: const EdgeInsets.only(top: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.negative),
      borderRadius: AppRadius.allSmall,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rejected · needs attention',
          style: AppTypography.body.copyWith(color: AppColors.negative),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'The server declined this entry. It has been kept exactly as it was '
          'entered so you can see what was attempted, and it will not be '
          'retried on its own.',
          style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
        ),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.body.copyWith(color: AppColors.inkMuted),
      ),
    ),
  );
}
