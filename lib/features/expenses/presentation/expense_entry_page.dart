/// Recording an expense.
///
/// Built for the case that happens forty times a day and not for the case that happens
/// twice a month. A ₹500 vegetable purchase is: amount, the classification it had last
/// time, Save. Everything else — payment, reference, notes, attachments, splitting
/// between properties, splitting across months — is behind **More details**, closed, and
/// a routine user never opens it.
///
/// Saving does not need a network and never claims one. The local transaction writes the
/// document, its lines, its contributions and the queued intent together (see
/// [ExpenseRepository]); only when that commits does the screen say anything, and what it
/// says offline is "Saved · Pending sync", not an error.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_draft.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/allocation_editor.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/amount_field.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/classification_picker.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/expense_optional_details.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/expense_read_failure.dart';

class ExpenseEntryPage extends ConsumerStatefulWidget {
  const ExpenseEntryPage({super.key}) : editing = null, capturedAt = null;

  /// The same screen, opened on a document that already exists (D-072).
  ///
  /// Not a second form. The project lead's rule is explicit and it is also the only
  /// maintainable choice: an edit screen that duplicated the reconciliation rules, the
  /// period editor and the capability gates would be a second implementation of the
  /// arithmetic that decides company profit. So the page takes a starting draft and
  /// changes almost nothing else — the title, the button, and which repository method
  /// the save lands in.
  const ExpenseEntryPage.editing(
    ExpenseDraft this.editing, {
    required this.capturedAt,
    super.key,
  });

  /// The loaded document, or null when this is a new expense.
  final ExpenseDraft? editing;

  /// The original entry's capture instant.
  ///
  /// Carried rather than re-taken. Correcting a figure does not change when the entry
  /// was made, and `captured_at` is forensic metadata about exactly that (D-019). The
  /// update payload does not restate it, so this value never reaches the server — it is
  /// passed so the aggregate this screen builds is the document it claims to be, rather
  /// than one wearing today's timestamp.
  final DateTime? capturedAt;

  @override
  ConsumerState<ExpenseEntryPage> createState() => _ExpenseEntryPageState();
}

class _ExpenseEntryPageState extends ConsumerState<ExpenseEntryPage> {
  ExpenseDraft? _draft;
  bool _saving = false;
  String? _failure;

  bool get _isEdit => widget.editing != null;

  /// Applies a change to whatever the draft is *now*.
  ///
  /// The classification sheet is a separate route that outlives this page's build, so a
  /// callback capturing the draft would apply every rung of the drill-down to the same
  /// stale value — and only the last one would survive. Caught on a real device: the
  /// form ended up holding a category and no property.
  void _mutate(ExpenseDraft Function(ExpenseDraft) change) =>
      setState(() => _draft = change(_draft!));

  @override
  Widget build(BuildContext context) {
    final graphAsync = ref.watch(masterGraphProvider);
    final principal = ref.watch(principalProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: Text(_isEdit ? 'Edit expense' : 'Add expense'),
        elevation: 0,
      ),
      body: graphAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Plain words and a retry, never the exception: a SQLite or Drift message is
        // nothing a manager can act on (D-322, D-323). The detail goes to the log.
        error: (error, stack) {
          logExpenseReadFailure('The expense set-up', error, stack);
          return ExpenseReadFailure(
            title: 'The set-up could not be read',
            body:
                'Nothing has been saved. This device could not read its list of '
                'properties and categories just now. Try again; if it keeps '
                'happening, restart the app.',
            onRetry: () => ref.invalidate(masterGraphProvider),
          );
        },
        data: (graph) => _form(context, graph, principal),
      ),
    );
  }

  Widget _form(BuildContext context, MasterGraph graph, Principal principal) {
    final units = ExpenseDraft.selectableUnits(graph, principal);
    if (units.isEmpty) {
      // Deliberately does not name a property this user has no access to (§27).
      return const _Message(
        title: 'No business unit available',
        body:
            'You do not currently have access to a business unit, so there is '
            'nowhere to record an expense. Ask an administrator.',
      );
    }

    final draft = _draft ??= widget.editing ?? _startingDraft(graph, principal);
    final problems = draft.problemsFor(principal);
    final canSave = problems.isEmpty && !_saving;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // ── The fast path ───────────────────────────────────────────
              AmountField(
                key: const Key('expense-amount'),
                initial: draft.total,
                autofocus: true,
                enabled: draft.isSimple,
                label: draft.isSimple ? 'Amount' : 'Total amount',
                onChanged: (amount) =>
                    _mutate((current) => current.withTotal(amount)),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (draft.isSimple)
                ClassificationRow(
                  line: draft.allocations.single,
                  graph: graph,
                  principal: principal,
                  lockedBusinessUnitId: units.length == 1
                      ? units.single.id
                      : null,
                  onChanged:
                      ({
                        String? businessUnitId,
                        String? departmentId,
                        String? sectionId,
                        String? categoryId,
                      }) => _mutate(
                        (current) => current.withClassification(
                          current.allocations.single.id,
                          businessUnitId: businessUnitId,
                          departmentId: departmentId,
                          sectionId: sectionId,
                          categoryId: categoryId,
                        ),
                      ),
                )
              else
                AllocationEditor(
                  draft: draft,
                  graph: graph,
                  principal: principal,
                  onChanged: _mutate,
                ),

              const SizedBox(height: AppSpacing.md),
              // Correcting the date of an expense that already exists is a distinct act
              // needing `transaction.correct.business_date` (spec §9). Somebody without
              // it is shown the date and cannot change it, rather than being offered a
              // picker whose every outcome the server would refuse. Recording a *new*
              // expense against a chosen date is untouched — that is `manual`, not a
              // correction, and needs no such permission.
              _BusinessDateRow(
                date: draft.businessDate,
                editable:
                    !draft.isEdit ||
                    ExpenseDraft.mayCorrectBusinessDate(principal),
                onChanged: (date) =>
                    _mutate((current) => current.copyWith(businessDate: date)),
              ),

              // Appears the moment the date actually differs from the one this form was
              // loaded with, and disappears again if it is put back. An ordinary
              // correction never sees it.
              if (draft.movesBusinessDate) ...[
                const SizedBox(height: AppSpacing.sm),
                _CorrectionReasonField(
                  initial: draft.correctionReason,
                  from: draft.originalBusinessDate!,
                  to: draft.businessDate,
                  onChanged: (reason) => _mutate(
                    (current) => current.copyWith(correctionReason: reason),
                  ),
                ),
              ],

              if (draft.isSimple && ExpenseDraft.mayUseSplit(principal)) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('split-expense'),
                    onPressed: () => _mutate((current) => current.asSplit()),
                    icon: const Icon(Icons.call_split, size: 16),
                    label: const Text('Split expense'),
                  ),
                ),
              ],

              // ── Everything else, closed ─────────────────────────────────
              const SizedBox(height: AppSpacing.lg),
              ExpenseOptionalDetails(draft: draft, onChanged: _mutate),

              if (_failure case final message?) ...[
                const SizedBox(height: AppSpacing.lg),
                _FailureNotice(message: message),
              ],
            ],
          ),
        ),
        _SaveBar(
          canSave: canSave,
          saving: _saving,
          problem: problems.isEmpty ? null : problems.first.message,
          onSave: () => _save(graph, principal),
        ),
      ],
    );
  }

  /// A blank expense, pre-filled with what is still safe to offer.
  ///
  /// The business date comes from the unit's cut-off, never the raw device clock (D-019);
  /// the classification comes from last time, and only the part of it that is still
  /// authorised and still active (spec §18).
  ExpenseDraft _startingDraft(MasterGraph graph, Principal principal) {
    final remembered = ref
        .read(lastUsedClassificationProvider)
        .validAgainst(graph, principal);
    final units = ExpenseDraft.selectableUnits(graph, principal);

    return ExpenseDraft.blank(
      businessDate: ref.read(currentBusinessDateProvider),
      businessUnitId:
          remembered.businessUnitId ??
          (units.length == 1 ? units.single.id : null),
      departmentId: remembered.departmentId,
      sectionId: remembered.sectionId,
      categoryId: remembered.categoryId,
    );
  }

  Future<void> _save(MasterGraph graph, Principal principal) async {
    final draft = _draft;
    if (draft == null || !draft.canSave(principal)) return;

    setState(() {
      _saving = true;
      _failure = null;
    });

    try {
      final controller = ref.read(expenseEntryControllerProvider);
      final outcome = _isEdit
          ? await controller.applyEdit(
              draft,
              graph: graph,
              principal: principal,
              capturedAt: widget.capturedAt ?? DateTime.now().toUtc(),
            )
          : await controller.save(draft, graph: graph, principal: principal);

      if (!mounted) return;
      // Only a *new* expense teaches the form what to offer next. Correcting last
      // Tuesday's electricity bill should not change what tomorrow's entry pre-fills.
      if (!_isEdit) {
        ref.read(lastUsedClassificationProvider.notifier).remember(draft);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEdit ? 'Edit saved · Pending sync' : 'Saved · Pending sync',
          ),
          backgroundColor: AppColors.ink,
        ),
      );
      Navigator.of(context).pop(outcome.expenseId);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Nothing was written: the local save is one transaction, and it either
        // committed or it did not. Saying so plainly matters more here than in a
        // create — the document the user was correcting is still exactly as it was.
        _failure = _isEdit
            ? 'This edit was not saved. The expense is unchanged. '
                  '(${error.runtimeType})'
            : 'This expense was not saved. Nothing has been recorded. '
                  '(${error.runtimeType})';
      });
    }
  }
}

class _BusinessDateRow extends StatelessWidget {
  const _BusinessDateRow({
    required this.date,
    required this.onChanged,
    this.editable = true,
  });

  final BusinessDate date;
  final ValueChanged<BusinessDate> onChanged;

  /// False on an edit by somebody without `transaction.correct.business_date`. The row
  /// still shows the date — it is part of the document — and simply does not open.
  final bool editable;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: !editable
        ? null
        : () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.utc(date.year, date.month, date.day),
              firstDate: DateTime.utc(2020),
              lastDate: DateTime.utc(2100),
              helpText: 'Business date',
            );
            if (picked != null) {
              onChanged(BusinessDate.of(picked.year, picked.month, picked.day));
            }
          },
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.allSmall,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, size: 18, color: AppColors.inkFaint),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BUSINESS DATE', style: AppTypography.overline),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  date.iso,
                  key: const Key('business-date'),
                  style: AppTypography.body,
                ),
              ],
            ),
          ),
          if (editable)
            const Icon(Icons.edit_outlined, size: 16, color: AppColors.inkFaint)
          else
            const Icon(
              Icons.lock_outline,
              size: 16,
              color: AppColors.inkFaint,
              semanticLabel: 'The business date cannot be changed here',
            ),
        ],
      ),
    ),
  );
}

/// The reason a business date is being moved.
///
/// Only ever built while the date actually differs from the one the form was loaded
/// with, so an ordinary correction never grows a field (spec §9). What is typed here is
/// carried in the outbox payload and ends up in the append-only audit row, not in the
/// document's notes — the notes are the user's description of the expense, and a
/// correction reason is a statement about a change to it.
class _CorrectionReasonField extends StatelessWidget {
  const _CorrectionReasonField({
    required this.initial,
    required this.from,
    required this.to,
    required this.onChanged,
  });

  final String? initial;
  final BusinessDate from;
  final BusinessDate to;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Business date changed from ${from.iso} to ${to.iso}',
        key: const Key('business-date-correction-notice'),
        style: AppTypography.caption,
      ),
      const SizedBox(height: AppSpacing.xs),
      TextFormField(
        key: const Key('business-date-correction-reason'),
        initialValue: initial,
        onChanged: onChanged,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Why is the date being changed?',
          helperText: 'Kept with the correction in the audit trail.',
        ),
      ),
    ],
  );
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.canSave,
    required this.saving,
    required this.onSave,
    this.problem,
  });

  final bool canSave;
  final bool saving;
  final String? problem;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(top: BorderSide(color: AppColors.hairline)),
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (problem case final message?) ...[
            Text(
              message,
              key: const Key('save-blocked-reason'),
              style: AppTypography.caption.copyWith(color: AppColors.caution),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const Key('save-expense'),
              onPressed: canSave ? onSave : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: AppColors.inkInverse,
                disabledBackgroundColor: AppColors.hairlineStrong,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.allSmall,
                ),
              ),
              child: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save expense'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.negative),
    ),
    child: Text(
      message,
      style: AppTypography.body.copyWith(color: AppColors.negative),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.subheading),
            const SizedBox(height: AppSpacing.sm),
            Text(body, style: AppTypography.bodyMuted),
          ],
        ),
      ),
    ),
  );
}
