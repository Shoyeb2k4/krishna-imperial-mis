/// Turning a document this device already holds back into the form that made it (D-072).
///
/// ## Why this is a separate file, and a refusal rather than a mapping
///
/// The entry screen and the edit screen are the same screen — spec §18's fast path, the
/// same reconciliation rules, the same period editor, the same capability gates. What
/// differs is only where the draft comes from. So this file is small on purpose: it maps
/// a `LocalExpense` onto an `ExpenseDraft` and it refuses the cases that must not be
/// editable, and it contains no business rule of its own.
///
/// ## The refusal that matters
///
/// **A scoped projection of a shared expense is read-only in V1** (the project lead's
/// rule). A Crystal Canopy manager holding `Your allocation ₹25,000` of a ₹58,000 invoice
/// does not have enough authorised information to reconcile the document, and the model
/// is built so they cannot get it: `documentTotalMinor` is null on a scoped row *by check
/// constraint*, because total minus own share is the other property's share (D-062).
///
/// Three things follow, and each is a thing this file deliberately does **not** do:
///
///  * it does not reconstruct the missing total from anything;
///  * it does not fetch the complete document because Edit was pressed — pressing a
///    button is not a grant of authority, and a client that "just re-reads it" would be
///    asking the server for exactly what the projection withheld;
///  * it does not offer "edit my allocation only". Editing one share of a shared bill is
///    a collaborative workflow with its own concurrency and audit questions, and it is
///    out of V1 scope. Half-implementing it here would be the worst of both.
///
/// A document wholly inside one property the user is scoped to is `complete` *for them*,
/// and is editable under the ordinary rules. "Complete" is about what this device was
/// given, not about how many properties the invoice charges.
library;

import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_draft.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// Why a document cannot be opened for editing.
///
/// Separate from the capability decision on purpose: these are facts about the
/// *document* on this device, and they hold however privileged the reader is. An Owner
/// looking at a voided expense is refused for the same reason a clerk is.
enum EditRefusal {
  /// A partial projection of a shared bill. Read-only in V1.
  scopedProjection,

  /// Voided documents are immutable; a correction is a new document (D-006).
  voided,

  /// The document has not been accepted by the server yet, so there is no version to
  /// base an edit on. The pending create is the thing to wait for, or to fix.
  notYetSynced;

  String get message => switch (this) {
    EditRefusal.scopedProjection =>
      'This is your allocation from a shared expense. The complete expense can '
          'only be edited by an authorised finance user.',
    EditRefusal.voided =>
      'A voided expense cannot be changed. To correct it, record a new one.',
    EditRefusal.notYetSynced =>
      'This expense has not reached the server yet. It can be edited once it '
          'has been accepted.',
  };
}

/// The outcome of trying to open a document for editing.
sealed class EditableDraft {
  const EditableDraft();

  /// The draft, or null when this is a refusal — so a caller that forgets to switch on
  /// the type still cannot get a draft it was not given.
  ExpenseDraft? get draftOrNull =>
      this is EditableDraftReady ? (this as EditableDraftReady).draft : null;
}

final class EditableDraftReady extends EditableDraft {
  const EditableDraftReady(this.draft);
  final ExpenseDraft draft;
}

final class EditableDraftRefused extends EditableDraft {
  const EditableDraftRefused(this.reason);
  final EditRefusal reason;
}

/// Whether [expense] is the *kind* of document that can be edited at all.
///
/// Says nothing about who is asking — that is the authorizer's question, and the
/// server's after it. Separated so a screen can decide whether to render an Edit control
/// without duplicating either half of the reasoning.
EditRefusal? editRefusalFor(LocalExpense expense) {
  if (expense.isScoped) return EditRefusal.scopedProjection;
  if (expense.row.voidedAt != null) return EditRefusal.voided;
  if (expense.row.txnNumber == null) return EditRefusal.notYetSynced;
  return null;
}

/// Loads [expense] into an editable draft, or explains why it cannot be.
EditableDraft draftFor(LocalExpense expense) {
  final refusal = editRefusalFor(expense);
  if (refusal != null) return EditableDraftRefused(refusal);

  // Safe by the refusal above: a complete row carries its document total by check
  // constraint, so this is not an optimistic read.
  final total = expense.documentTotal!;

  final lines = [
    for (final line in expense.allocations)
      AllocationDraft(
        id: line.id,
        businessUnitId: line.businessUnitId,
        departmentId: line.departmentId,
        sectionId: line.sectionId,
        categoryId: line.categoryId,
        amount: Money.fromPaise(line.amountMinor),
        periodSplits: _deliberateSplitsFor(expense, line.id),
      ),
  ]..sort((a, b) => _orderOf(expense, a.id).compareTo(_orderOf(expense, b.id)));

  return EditableDraftReady(
    ExpenseDraft.fromExisting(
      id: expense.row.id,
      rowVersion: expense.row.rowVersion,
      txnNumber: expense.row.txnNumber,
      businessDate:
          BusinessDate.tryParse(expense.row.businessDate) ??
          BusinessDate.of(2000, 1, 1),
      total: total,
      allocations: lines,
      vendorId: expense.row.vendorId,
      paymentStatus: expense.row.paymentStatus == 'paid'
          ? PaymentStatus.paid
          : PaymentStatus.unpaid,
      paymentDate: BusinessDate.tryParse(expense.row.paymentDate ?? ''),
      paymentMethodId: expense.row.paymentMethodId,
      referenceNumber: expense.row.referenceNumber,
      notes: expense.row.notes,
      accountingPeriodStart: BusinessDate.tryParse(
        expense.row.accountingPeriodStart ?? '',
      ),
      accountingPeriodEnd: BusinessDate.tryParse(
        expense.row.accountingPeriodEnd ?? '',
      ),
      attachments: [
        for (final row in expense.attachments)
          ExpenseAttachment(
            id: row.id,
            fileName: row.fileName,
            contentType: row.contentType,
            byteSize: row.byteSize,
            contentHash: row.contentHash,
            uploadState: AttachmentUploadState.values.firstWhere(
              (state) => state.name == row.uploadState,
              orElse: () => AttachmentUploadState.pending,
            ),
            storagePath: row.storagePath,
            localStagingPath: row.localPath,
          ),
      ],
    ),
  );
}

/// The period rows a person *chose*, and only those.
///
/// A derived contribution is the default rule's own bookkeeping (D-060): every line has
/// at least one, the user never asked for it, and the server regenerates it. Loading
/// them into the split editor would show a split nobody made, and — worse — saving would
/// then send them as deliberate, turning an ordinary expense into one that permanently
/// carries an explicit allocation. So they are dropped, and an unsplit line comes back
/// unsplit.
List<PeriodSplitDraft> _deliberateSplitsFor(
  LocalExpense expense,
  String allocationId,
) {
  final deliberate =
      expense.periodContributions
          .where((c) => c.allocationId == allocationId && !c.isDerived)
          .toList()
        ..sort(
          (a, b) => a.accountingPeriodEnd.compareTo(b.accountingPeriodEnd),
        );

  return [
    for (final part in deliberate)
      PeriodSplitDraft(
        id: part.id,
        start:
            BusinessDate.tryParse(part.accountingPeriodStart) ??
            BusinessDate.of(2000, 1, 1),
        end:
            BusinessDate.tryParse(part.accountingPeriodEnd) ??
            BusinessDate.of(2000, 1, 1),
        amount: Money.fromPaise(part.amountMinor),
      ),
  ];
}

int _orderOf(LocalExpense expense, String allocationId) =>
    expense.allocations.firstWhere((line) => line.id == allocationId).sortOrder;
