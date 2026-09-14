/// One expense, rendered from a value and nothing else (Phase 5 Slice 10).
///
/// **It never labels a share as a total.** On a scoped value the invoice total is not there
/// at all, so the body says `Your allocation` and `Shared expense`, and there is no field
/// where the whole bill would go (D-062).
///
/// ## An immutable body, not a panel with its buttons hidden
///
/// This widget owns no action: no edit, void, Review latest, attachment control, sync chip
/// or outbox read, and it imports none of them. The ledger composes its own banners, status
/// and actions into [banners], [status] and [actions]; the P&L drill-down composes none. A
/// structural guard holds both halves of that.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/expenses/expense_document_detail.dart';

class ExpenseDocumentBody extends StatelessWidget {
  const ExpenseDocumentBody({
    required this.detail,
    this.leading,
    this.banners,
    this.status,
    this.actions,
    this.listKey,
    super.key,
  });

  final ExpenseDocumentDetail detail;

  /// Shown first — the drill-down's statement of which bucket this explains.
  final Widget? leading;

  /// Shown under the voided banner — a composing surface's attention banners.
  final Widget? banners;

  /// Shown beside the reference — a composing surface's sync status.
  final Widget? status;

  /// Shown last — a composing surface's controls.
  final Widget? actions;

  final Key? listKey;

  @override
  Widget build(BuildContext context) => ListView(
    key: listKey,
    padding: const EdgeInsets.all(AppSpacing.lg),
    children: [
      if (leading case final leading?) ...[
        leading,
        const SizedBox(height: AppSpacing.md),
      ],
      if (detail.isVoided) const _VoidedBanner(),
      ?banners,

      _Header(detail: detail, status: status),
      const SizedBox(height: AppSpacing.lg),

      _Amount(detail: detail),
      const SizedBox(height: AppSpacing.lg),

      _Field(label: 'Business date', value: detail.businessDate),
      if (detail.accountingPeriodStart != null)
        _Field(
          label: 'Accounting period',
          value:
              '${detail.accountingPeriodStart} – ${detail.accountingPeriodEnd}',
        ),
      _Field(
        label: 'Payment',
        value: detail.paymentStatus == 'paid'
            ? 'Paid on ${detail.paymentDate}'
            : 'Unpaid',
      ),
      if (detail.referenceNumber case final reference?)
        _Field(label: 'Reference', value: reference),
      if (detail.notes case final notes?) _Field(label: 'Notes', value: notes),

      const SizedBox(height: AppSpacing.lg),
      _Allocations(detail: detail),

      const SizedBox(height: AppSpacing.lg),
      _Attachments(detail: detail),

      const SizedBox(height: AppSpacing.lg),
      _Provenance(detail: detail),

      if (actions case final actions?) ...[
        const SizedBox(height: AppSpacing.xl),
        actions,
      ],
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.status});
  final ExpenseDocumentDetail detail;
  final Widget? status;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('EXPENSE', style: AppTypography.overline),
      const SizedBox(height: AppSpacing.xxs),
      Row(
        children: [
          Expanded(
            child: Text(
              detail.displayReference,
              key: const Key('detail-reference'),
              style: AppTypography.heading,
            ),
          ),
          ?status,
        ],
      ),
      if (detail.txnNumber == null)
        Text(
          'The permanent number is issued when this reaches the server.',
          style: AppTypography.caption,
        ),
    ],
  );
}

/// The figure, and an honest label for it.
class _Amount extends StatelessWidget {
  const _Amount({required this.detail});
  final ExpenseDocumentDetail detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.isScoped ? 'YOUR ALLOCATION' : 'TOTAL',
          key: const Key('amount-label'),
          style: AppTypography.overline,
        ),
        const SizedBox(height: AppSpacing.xxs),
        MoneyText.metric(
          detail.visibleAmount,
          key: const Key('detail-visible-amount'),
          align: TextAlign.left,
        ),
        if (detail.isScoped) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Shared expense. This is your business unit\'s allocation — the '
            'document total is not available to you.',
            key: const Key('scoped-explanation'),
            style: AppTypography.caption.copyWith(color: AppColors.caution),
          ),
        ],
      ],
    ),
  );
}

class _Allocations extends StatelessWidget {
  const _Allocations({required this.detail});
  final ExpenseDocumentDetail detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        detail.isScoped ? 'YOUR ALLOCATIONS' : 'ALLOCATIONS',
        style: AppTypography.overline,
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final line in detail.allocations) ...[
        Row(
          children: [
            Expanded(child: Text(line.label, style: AppTypography.body)),
            MoneyText(line.amount),
          ],
        ),
        for (final part in detail.periods.where(
          (p) => p.allocationId == line.id,
        ))
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              top: AppSpacing.xxs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    part.isDerived
                        ? '${part.periodKey} (default)'
                        : '${part.periodKey} (split)',
                    style: AppTypography.caption,
                  ),
                ),
                Text(
                  MoneyFormatter.standard.format(part.amount),
                  style: AppTypography.caption.copyWith(
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ],
  );
}

class _Attachments extends StatelessWidget {
  const _Attachments({required this.detail});
  final ExpenseDocumentDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.attachments.isEmpty) {
      return Text(
        detail.isScoped
            // Truthful about *why* there is nothing, without implying it is missing.
            ? 'Attachments on a shared expense are available to users who can '
                  'see the whole document.'
            : 'No attachments.',
        key: const Key('attachments-note'),
        style: AppTypography.caption,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ATTACHMENTS', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        for (final attachment in detail.attachments)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(
                  Icons.attachment,
                  size: 16,
                  color: AppColors.inkFaint,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    attachment.fileName,
                    style: AppTypography.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  switch (attachment.uploadState) {
                    'uploaded' || 'stagingReclaimed' => 'Uploaded',
                    'failed' => 'Retry needed',
                    _ => 'Pending upload',
                  },
                  style: AppTypography.caption.copyWith(
                    color: attachment.uploadState == 'failed'
                        ? AppColors.syncFailed
                        : AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Who did what, when.
class _Provenance extends StatelessWidget {
  const _Provenance({required this.detail});
  final ExpenseDocumentDetail detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('HISTORY', style: AppTypography.overline),
      const SizedBox(height: AppSpacing.sm),
      _Field(label: 'Recorded by', value: detail.createdBy),
      if (detail.capturedAt case final captured?)
        _Field(label: 'Captured', value: captured.toIso8601String()),
      if (detail.serverUpdatedAt case final updated?)
        _Field(label: 'Server updated', value: updated.toIso8601String()),
      _Field(label: 'Version', value: '${detail.rowVersion}'),
      if (detail.voidedAt case final voidedAt?) ...[
        _Field(label: 'Voided', value: voidedAt.toIso8601String()),
        _Field(label: 'Voided by', value: detail.voidedBy ?? '—'),
        _Field(label: 'Reason', value: detail.voidReason ?? '—'),
      ],
    ],
  );
}

class _VoidedBanner extends StatelessWidget {
  const _VoidedBanner();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('voided-banner'),
    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.negative),
    ),
    child: Row(
      children: [
        const Icon(Icons.block, size: 18, color: AppColors.negative),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            'VOIDED — this expense is excluded from every report and cannot be '
            'changed. It remains in the ledger as history.',
            style: AppTypography.body.copyWith(color: AppColors.negative),
          ),
        ),
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: AppTypography.caption)),
        Expanded(child: Text(value, style: AppTypography.body)),
      ],
    ),
  );
}
