/// One expense, in as much detail as this user is entitled to.
///
/// Three things it is careful never to do.
///
/// **It never labels a share as a total.** On a scoped record the document total is not
/// on this device at all, so the panel says `Your allocation` and `Shared expense`, and
/// there is no field where ₹58,000 would go.
///
/// **It never decides eligibility by role name.** Whether Edit and Void appear is asked
/// of [ExpenseAuthorizer] — the same domain rules the server re-decides — so the interface
/// and the backend agree for the same reason rather than by coincidence. The server is
/// still the authority; this only avoids offering somebody a form they will be refused.
///
/// **It never confuses a refusal with a conflict.** `Rejected` means the server declined
/// the act; `Conflict` means the record moved. They read differently, they offer different
/// actions, and neither is retried automatically.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/core/design/components/sync_state_chip.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/auth/authorizer.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_authorization.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_edit_loader.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/edit_launcher.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/void_dialog.dart';

class ExpenseDetailPanel extends ConsumerWidget {
  const ExpenseDetailPanel({required this.expenseId, super.key});

  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expense = ref.watch(expenseDetailProvider(expenseId));

    return expense.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text('This expense could not be read. $error'),
      ),
      data: (loaded) => loaded == null
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Text('This expense is no longer on this device.'),
            )
          : _Detail(expense: loaded),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.expense});

  final LocalExpense expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final principal = ref.watch(principalProvider);
    final row = expense.row;
    final voided = row.voidedAt != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (voided) const _VoidedBanner(),
        if (expense.syncState == SyncState.rejected)
          _AttentionBanner(
            title: 'Rejected · needs attention',
            body:
                'The server declined this entry. It has been kept exactly as '
                'you entered it so you can see what was attempted. It will not '
                'be retried on its own.',
            detail: expense.row.pendingMutationId,
          ),
        if (expense.syncState == SyncState.conflict)
          _AttentionBanner(
            title: 'Conflict · someone else changed this',
            body:
                'Your change was based on an earlier version of this expense. '
                'Nothing has been overwritten. Review the current version and '
                'apply your change again if it still applies.',
            action: _BannerAction(
              key: const Key('conflict-review-latest'),
              label: 'Review latest',
              onPressed: () => reviewLatestAfterConflict(context, ref, expense),
            ),
          ),

        _Header(expense: expense),
        const SizedBox(height: AppSpacing.lg),

        _Amount(expense: expense),
        const SizedBox(height: AppSpacing.lg),

        _Field(label: 'Business date', value: row.businessDate),
        if (row.accountingPeriodStart != null)
          _Field(
            label: 'Accounting period',
            value: '${row.accountingPeriodStart} – ${row.accountingPeriodEnd}',
          ),
        _Field(
          label: 'Payment',
          value: row.paymentStatus == 'paid'
              ? 'Paid on ${row.paymentDate}'
              : 'Unpaid',
        ),
        if (row.referenceNumber case final reference?)
          _Field(label: 'Reference', value: reference),
        if (row.notes case final notes?) _Field(label: 'Notes', value: notes),

        const SizedBox(height: AppSpacing.lg),
        _Allocations(expense: expense),

        const SizedBox(height: AppSpacing.lg),
        _Attachments(expense: expense),

        const SizedBox(height: AppSpacing.lg),
        _Provenance(expense: expense),

        const SizedBox(height: AppSpacing.xl),
        _Actions(expense: expense, principal: principal),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.expense});
  final LocalExpense expense;

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
              expense.displayReference,
              key: const Key('detail-reference'),
              style: AppTypography.heading,
            ),
          ),
          SyncStateChip(expense.syncState),
        ],
      ),
      if (expense.row.txnNumber == null)
        Text(
          'The permanent number is issued when this reaches the server.',
          style: AppTypography.caption,
        ),
    ],
  );
}

/// The figure, and an honest label for it.
class _Amount extends StatelessWidget {
  const _Amount({required this.expense});
  final LocalExpense expense;

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
          expense.isScoped ? 'YOUR ALLOCATION' : 'TOTAL',
          key: const Key('amount-label'),
          style: AppTypography.overline,
        ),
        const SizedBox(height: AppSpacing.xxs),
        MoneyText.metric(expense.visibleAmount, align: TextAlign.left),
        if (expense.isScoped) ...[
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
  const _Allocations({required this.expense});
  final LocalExpense expense;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        expense.isScoped ? 'YOUR ALLOCATIONS' : 'ALLOCATIONS',
        style: AppTypography.overline,
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final line in expense.allocations) ...[
        Row(
          children: [
            Expanded(
              child: Text(line.categoryLabel, style: AppTypography.body),
            ),
            MoneyText(Money.fromPaise(line.amountMinor)),
          ],
        ),
        for (final part in expense.periodContributions.where(
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
                        ? '${part.pnlPeriodKey} (default)'
                        : '${part.pnlPeriodKey} (split)',
                    style: AppTypography.caption,
                  ),
                ),
                Text(
                  MoneyFormatter.standard.format(
                    Money.fromPaise(part.amountMinor),
                  ),
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
  const _Attachments({required this.expense});
  final LocalExpense expense;

  @override
  Widget build(BuildContext context) {
    if (expense.attachments.isEmpty) {
      return Text(
        expense.isScoped
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
        for (final attachment in expense.attachments)
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

/// Who did what, when. Belongs here and not in the fast-entry form (§25).
class _Provenance extends StatelessWidget {
  const _Provenance({required this.expense});
  final LocalExpense expense;

  @override
  Widget build(BuildContext context) {
    final row = expense.row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HISTORY', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        _Field(label: 'Recorded by', value: row.createdBy),
        _Field(label: 'Captured', value: row.capturedAt.toIso8601String()),
        if (row.serverUpdatedAt case final updated?)
          _Field(label: 'Server updated', value: updated.toIso8601String()),
        _Field(label: 'Version', value: '${row.rowVersion}'),
        if (row.voidedAt case final voidedAt?) ...[
          _Field(label: 'Voided', value: voidedAt.toIso8601String()),
          _Field(label: 'Voided by', value: row.voidedBy ?? '—'),
          _Field(label: 'Reason', value: row.voidReason ?? '—'),
        ],
      ],
    );
  }
}

/// Edit and Void, offered only when the domain says they would be permitted.
class _Actions extends ConsumerWidget {
  const _Actions({required this.expense, required this.principal});

  final LocalExpense expense;
  final Principal principal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = expense.row;
    if (row.voidedAt != null) {
      return Text(
        'A voided expense cannot be changed. To correct it, record a new one.',
        key: const Key('voided-immutable-note'),
        style: AppTypography.caption,
      );
    }

    final authorizer = ExpenseAuthorizer(ref.watch(authorizerProvider));
    final today = ref.watch(currentBusinessDateProvider);
    final businessDate = BusinessDate.tryParse(row.businessDate) ?? today;
    final record = RecordContext(
      createdByUserId: row.createdBy,
      businessDate: businessDate,
    );

    // ── Edit ────────────────────────────────────────────────────────────────
    //
    // Two separate questions, and both must be yes.
    //
    // *Is this document editable at all?* A scoped share of a shared bill is read-only
    // in V1 (the project lead's rule): the holder has their own ₹25,000 and not the
    // ₹58,000, so they cannot reconcile the document, and nothing here goes looking for
    // the missing figure. A voided document is immutable, and one the server has not
    // accepted has no version to edit from.
    //
    // *May this person edit it?* The ordinary capability, scope, period and edit-window
    // decision, predicted here and re-decided by the server, whose answer is final
    // (D-037). Predicting it is what lets the control be absent rather than present and
    // then refused.
    final editRefusal = editRefusalFor(expense);
    final mayEdit =
        editRefusal == null &&
        authorizer
            .authorizeEditOf(
              principal: principal,
              businessUnitIds: {
                for (final line in expense.allocations) line.businessUnitId,
              },
              periods: {
                for (final part in expense.periodContributions)
                  (unit: part.businessUnitId, periodKey: part.pnlPeriodKey),
              },
              record: record,
              today: today,
            )
            .isAllowed;

    // Predicting eligibility, never deciding it. Asked from the pieces this device has —
    // a scoped reader cannot build the whole aggregate, and still needs to be told
    // whether Void would be permitted. The server re-checks on submission and its
    // answer is final (D-037).
    final mayVoid = authorizer
        .authorizeVoidOf(
          principal: principal,
          businessUnitIds: {
            for (final line in expense.allocations) line.businessUnitId,
          },
          periods: {
            for (final part in expense.periodContributions)
              (unit: part.businessUnitId, periodKey: part.pnlPeriodKey),
          },
          record: record,
          today: today,
          reason: 'preview',
        )
        .isAllowed;

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        if (mayEdit)
          FilledButton.icon(
            key: const Key('edit-expense'),
            onPressed: () => openExpenseEditor(context, ref, expense),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit expense'),
          )
        else if (editRefusal == EditRefusal.scopedProjection)
          // Said plainly rather than left as an absent button. A manager who can see
          // their share and no Edit control should know it is a rule and not a fault.
          Text(
            editRefusal!.message,
            key: const Key('scoped-readonly-note'),
            style: AppTypography.caption,
          ),
        if (mayVoid)
          OutlinedButton.icon(
            key: const Key('void-expense'),
            onPressed: () => showVoidDialog(context, ref, expense),
            icon: const Icon(Icons.block, size: 16),
            label: const Text('Void'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.negative,
              side: const BorderSide(color: AppColors.negative),
            ),
          ),
      ],
    );
  }
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

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({
    required this.title,
    required this.body,
    this.detail,
    this.action,
  });

  final String title;
  final String body;
  final String? detail;

  /// An optional deliberate next step. Never an automatic one: a conflict is resolved by
  /// a person looking at both figures, and the control says what it will do.
  final _BannerAction? action;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('attention-banner'),
    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.caution),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.subheading.copyWith(color: AppColors.caution),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(body, style: AppTypography.bodyMuted),
        if (action case final action?) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: action.key,
              onPressed: action.onPressed,
              child: Text(action.label),
            ),
          ),
        ],
      ],
    ),
  );
}

/// A named action on an attention banner.
class _BannerAction {
  const _BannerAction({
    required this.key,
    required this.label,
    required this.onPressed,
  });

  final Key key;
  final String label;
  final VoidCallback onPressed;
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
