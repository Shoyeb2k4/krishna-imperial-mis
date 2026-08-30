/// Opening the entry screen on a document that already exists, and telling the user the
/// truth when the record moved underneath them (D-072).
///
/// Two things happen here that do not happen when creating an expense.
///
/// **The version is captured once, at open.** Everything after that — every keystroke,
/// every rebuild, every background sync — leaves it alone. That is the whole conflict
/// mechanism: the server compares the intent against the version the person was actually
/// looking at, and refuses `KM003` if the record has moved since. Re-reading the row at
/// submission would make every conflict disappear, and with it every chance to notice
/// that somebody else's correction was about to be overwritten (§3, D-021).
///
/// **A conflict is presented, never merged.** When the server refuses, the user is shown
/// what they submitted beside what the record now says, and is given one deliberate
/// action: reload the latest and decide again. Financial values are never merged
/// automatically, and the server's copy is never silently overwritten — those are the
/// two things D-005 has forbidden since Phase 0, and a merge of two people's figures is
/// a number nobody chose.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_edit_loader.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_entry_page.dart';

/// Opens the entry screen in edit mode for [expense], or explains why it cannot.
///
/// Returns the expense id when an edit was saved, and null otherwise.
Future<String?> openExpenseEditor(
  BuildContext context,
  WidgetRef ref,
  LocalExpense expense,
) async {
  final outcome = draftFor(expense);

  if (outcome is EditableDraftRefused) {
    // The control should not have been offered, so this is a backstop rather than a
    // path a user normally meets. It still says something true rather than nothing.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.reason.message),
        backgroundColor: AppColors.ink,
      ),
    );
    return null;
  }

  final draft = (outcome as EditableDraftReady).draft;
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) =>
          ExpenseEntryPage.editing(draft, capturedAt: expense.row.capturedAt),
    ),
  );
}

/// Re-reads the current record from the server and shows it beside what was attempted.
///
/// The order matters. The local row still holds **the user's attempted values** — the
/// edit was applied locally and then refused on delivery — so it is captured before the
/// pull, which replaces it with the server's version. Pulling first would leave nothing
/// to compare against and the screen would show the same figures twice.
///
/// The conflicted intent is **not** deleted, retried, or resolved on the user's behalf.
/// It is their work and it stays inspectable (D-048 §2); what this offers is the chance
/// to see both numbers and deliberately re-enter the correction against the current
/// record. No merge, and no silent overwrite of the server.
Future<void> reviewLatestAfterConflict(
  BuildContext context,
  WidgetRef ref,
  LocalExpense expense,
) async {
  final attempted = expense;
  final repository = ref.read(expenseRepositoryProvider);

  final pull = ref.read(expensePullProvider);
  if (pull != null) await pull.pullOne(expense.row.id);

  final current = await repository.load(expense.row.id);
  if (!context.mounted) return;

  final reapply = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    builder: (_) =>
        ExpenseConflictSheet(attempted: attempted, current: current),
  );

  if (reapply != true || current == null || !context.mounted) return;
  await openExpenseEditor(context, ref, current);
}

/// What the user is shown when their edit was refused because the record moved.
///
/// Deliberately not a dialog that offers "overwrite anyway". The two figures are put
/// side by side and the only forward action re-reads the current record — after which
/// the user decides, with both numbers in front of them, whether they still want the
/// correction they were making.
class ExpenseConflictSheet extends ConsumerWidget {
  const ExpenseConflictSheet({
    required this.attempted,
    required this.current,
    super.key,
  });

  /// The document as the user submitted it.
  final LocalExpense attempted;

  /// The document as the server now holds it, once re-read.
  final LocalExpense? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'This expense changed while you were editing it',
          key: const Key('conflict-title'),
          style: AppTypography.heading,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your edit has not been applied. Somebody else changed this record '
          'after you opened it, so applying yours would overwrite a correction '
          'you have not seen.',
          style: AppTypography.body,
        ),
        const SizedBox(height: AppSpacing.lg),
        _Side(
          label: 'WHAT YOU ENTERED',
          expense: attempted,
          fieldKey: const Key('conflict-attempted'),
        ),
        const SizedBox(height: AppSpacing.md),
        _Side(
          label: 'WHAT THE RECORD SAYS NOW',
          expense: current,
          fieldKey: const Key('conflict-current'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const Key('conflict-reapply'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Apply my change again'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: OutlinedButton(
                key: const Key('conflict-dismiss'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Leave it for now'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.expense,
    required this.fieldKey,
  });

  final String label;
  final LocalExpense? expense;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) => Container(
    key: fieldKey,
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.overline),
        const SizedBox(height: AppSpacing.xs),
        if (expense == null)
          Text(
            'Not available on this device yet.',
            style: AppTypography.caption,
          )
        else ...[
          MoneyText(
            expense!.documentTotal ?? expense!.visibleAmount,
            align: TextAlign.left,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${expense!.row.businessDate} · version '
            '${expense!.row.rowVersion}',
            style: AppTypography.caption,
          ),
        ],
      ],
    ),
  );
}
