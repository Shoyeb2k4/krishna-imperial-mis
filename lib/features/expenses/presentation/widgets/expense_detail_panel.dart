/// One expense, as the ledger shows it: the immutable document body, and the ledger's own
/// banners, status and actions composed around it.
///
/// Three things it is careful never to do.
///
/// **It never labels a share as a total.** The body renders a scoped value as `Your
/// allocation`, and the invoice total is not on this device at all (D-062).
///
/// **It never decides eligibility by role name.** Whether Edit and Void appear is asked of
/// [ExpenseAuthorizer] — the same domain rules the server re-decides. The server is still
/// the authority; this only avoids offering somebody a form they will be refused.
///
/// **It never confuses a refusal with a conflict.** `Rejected` means the server declined
/// the act; `Conflict` means the record moved. Neither is retried automatically.
///
/// The P&L drill-down renders the same [ExpenseDocumentBody] with none of these controls
/// (Phase 5 Slice 10).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/components/sync_state_chip.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/auth/authorizer.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_authorization.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_edit_loader.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/edit_launcher.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/expense_document_body.dart';
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
    final rejected = expense.syncState == SyncState.rejected;
    final conflict = expense.syncState == SyncState.conflict;

    return ExpenseDocumentBody(
      detail: expense.detail,
      banners: rejected || conflict
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rejected)
                  _AttentionBanner(
                    title: 'Rejected · needs attention',
                    body:
                        'The server declined this entry. It has been kept exactly as '
                        'you entered it so you can see what was attempted. It will not '
                        'be retried on its own.',
                    detail: expense.row.pendingMutationId,
                  ),
                if (conflict)
                  _AttentionBanner(
                    title: 'Conflict · someone else changed this',
                    body:
                        'Your change was based on an earlier version of this expense. '
                        'Nothing has been overwritten. Review the current version and '
                        'apply your change again if it still applies.',
                    action: _BannerAction(
                      key: const Key('conflict-review-latest'),
                      label: 'Review latest',
                      onPressed: () =>
                          reviewLatestAfterConflict(context, ref, expense),
                    ),
                  ),
              ],
            )
          : null,
      status: SyncStateChip(expense.syncState),
      actions: _Actions(expense: expense, principal: principal),
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

    // Two separate questions, and both must be yes: is this document editable at all (a
    // scoped share is read-only in V1, a voided one is immutable), and may this person
    // edit it. Predicted here, re-decided by the server (D-037).
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

  /// An optional deliberate next step. Never an automatic one.
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
