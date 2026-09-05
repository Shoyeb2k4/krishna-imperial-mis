/// The expense being typed, and everything that decides whether it can be saved.
///
/// Pure Dart over a [MasterGraph] and a [Principal]. No Flutter, no database, no network —
/// so the rules a user experiences as "why is Save greyed out" are unit-testable and are
/// the same rules on both platforms.
///
/// Three things it is careful about.
///
/// **A changed parent invalidates its children.** Switching business unit while a Crystal
/// Canopy category is selected must not leave that category selected: it would either be
/// refused by the composite foreign key or, worse, quietly accepted somewhere it does not
/// belong. The cascade is explicit and tested.
///
/// **Money never balances itself.** `Remaining` is shown, and Save stays disabled until it
/// is exactly zero. There is no hidden adjustment line and no rounding row: if ₹25,000 and
/// ₹32,000 are entered against a ₹58,000 bill, the answer is "₹1,000 remaining", not a
/// third line nobody asked for.
///
/// **Capability gates the shape, not just the button.** A cross-unit split needs
/// `expense.allocate_cross_unit` and scope on every unit named; a period split needs
/// `expense.allocate_periods`. The draft refuses to offer what the server would refuse to
/// accept — and the server refuses anyway, because a modified client is not trusted.
library;

import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// One accounting period's share, as it is being typed.
@immutable
final class PeriodSplitDraft {
  const PeriodSplitDraft({
    required this.id,
    required this.start,
    required this.end,
    this.amount,
  });

  final String id;
  final BusinessDate start;
  final BusinessDate end;

  /// Null while the field is empty or unreadable. Not zero: an empty box and a deliberate
  /// nought are different statements, and only one of them is a mistake.
  final Money? amount;

  String get periodKey => end.periodKey;

  PeriodSplitDraft copyWith({
    BusinessDate? start,
    BusinessDate? end,
    Money? amount,
    bool clearAmount = false,
  }) => PeriodSplitDraft(
    id: id,
    start: start ?? this.start,
    end: end ?? this.end,
    amount: clearAmount ? null : (amount ?? this.amount),
  );
}

/// One allocation line, as it is being typed.
@immutable
final class AllocationDraft {
  const AllocationDraft({
    required this.id,
    this.businessUnitId,
    this.departmentId,
    this.sectionId,
    this.categoryId,
    this.amount,
    this.periodSplits = const [],
  });

  final String id;
  final String? businessUnitId;
  final String? departmentId;
  final String? sectionId;
  final String? categoryId;
  final Money? amount;

  /// Empty for the ordinary line. Non-empty only when a person deliberately split it.
  final List<PeriodSplitDraft> periodSplits;

  bool get hasPeriodSplit => periodSplits.isNotEmpty;
  bool get isClassified => categoryId != null;

  /// What the period splits add up to, ignoring the ones still blank.
  Money get splitTotal =>
      Money.sum(periodSplits.map((s) => s.amount ?? Money.zero));

  /// What is left to allocate across periods, or null when there is no split.
  Money? get splitRemaining =>
      hasPeriodSplit && amount != null ? amount! - splitTotal : null;

  bool get splitReconciles =>
      !hasPeriodSplit ||
      (amount != null &&
          periodSplits.every((s) => s.amount != null && s.amount!.isPositive) &&
          splitTotal == amount);

  AllocationDraft copyWith({
    String? businessUnitId,
    String? departmentId,
    String? sectionId,
    String? categoryId,
    Money? amount,
    List<PeriodSplitDraft>? periodSplits,
    bool clearDepartment = false,
    bool clearSection = false,
    bool clearCategory = false,
    bool clearAmount = false,
  }) => AllocationDraft(
    id: id,
    businessUnitId: businessUnitId ?? this.businessUnitId,
    departmentId: clearDepartment ? null : (departmentId ?? this.departmentId),
    sectionId: clearSection ? null : (sectionId ?? this.sectionId),
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    amount: clearAmount ? null : (amount ?? this.amount),
    periodSplits: periodSplits ?? this.periodSplits,
  );
}

/// Why an expense cannot be saved yet. Each one is a sentence a user can act on.
enum DraftProblem {
  amountMissing,
  amountNotPositive,
  classificationIncomplete,
  allocationsDoNotReconcile,
  periodSplitDoesNotReconcile,
  crossUnitNotPermitted,
  unitOutsideScope,
  periodSplitNotPermitted,
  paymentIncomplete,
  attachmentsOverLimit,
  businessDateCorrectionNotPermitted,
  businessDateCorrectionNeedsReason;

  String get message => switch (this) {
    DraftProblem.amountMissing => 'Enter the amount.',
    DraftProblem.amountNotPositive =>
      'An expense must be more than zero. To reverse one, void it and enter a '
          'new one.',
    DraftProblem.classificationIncomplete =>
      'Choose the property, department, section and category.',
    DraftProblem.allocationsDoNotReconcile =>
      'The split does not add up to the total yet.',
    DraftProblem.periodSplitDoesNotReconcile =>
      'An accounting-period split does not add up to its line yet.',
    DraftProblem.crossUnitNotPermitted =>
      'Splitting one expense across properties needs permission you do not '
          'have. Record it against a single property, or ask someone in finance.',
    DraftProblem.unitOutsideScope =>
      'This expense charges a property you do not have access to.',
    DraftProblem.periodSplitNotPermitted =>
      'Spreading a cost across accounting periods needs permission you do not '
          'have.',
    DraftProblem.paymentIncomplete =>
      'A paid expense needs the date it was paid and how.',
    DraftProblem.attachmentsOverLimit =>
      'At most ${AttachmentPolicy.maxPerExpense} attachments, up to '
          '${AttachmentPolicy.maxTotalBytesPerExpense ~/ (1024 * 1024)} MB in '
          'total.',
    DraftProblem.businessDateCorrectionNotPermitted =>
      'Changing the business date of a recorded expense needs permission you do '
          'not have. Ask someone in finance.',
    DraftProblem.businessDateCorrectionNeedsReason =>
      'Say why the business date is being changed. The reason is kept with the '
          'correction.',
  };
}

/// The whole form.
@immutable
final class ExpenseDraft {
  const ExpenseDraft({
    required this.id,
    required this.businessDate,
    required this.allocations,
    this.total,
    this.vendorId,
    this.paymentStatus = PaymentStatus.unpaid,
    this.paymentDate,
    this.paymentMethodId,
    this.referenceNumber,
    this.notes,
    this.accountingPeriodStart,
    this.accountingPeriodEnd,
    this.attachments = const [],
    this.isSplit = false,
    this.baseRowVersion,
    this.txnNumber,
    this.originalBusinessDate,
    this.correctionReason,
  });

  /// A blank expense with one line ready to classify.
  ///
  /// [businessDate] comes from the unit's cut-off, never the raw device clock (D-019),
  /// and the caller derives it — this type does not know what time it is.
  factory ExpenseDraft.blank({
    required BusinessDate businessDate,
    String? id,
    String? businessUnitId,
    String? departmentId,
    String? sectionId,
    String? categoryId,
  }) => ExpenseDraft(
    id: id ?? const Uuid().v7(),
    businessDate: businessDate,
    allocations: [
      AllocationDraft(
        id: const Uuid().v4(),
        businessUnitId: businessUnitId,
        departmentId: departmentId,
        sectionId: sectionId,
        categoryId: categoryId,
      ),
    ],
  );

  /// The same form, loaded from a document that already exists (D-072).
  ///
  /// **Complete documents only.** A scoped projection is read-only in V1, and this
  /// factory refuses one rather than leaving the caller to remember: a scoped record
  /// deliberately does not carry the invoice total, so a draft built from it could not
  /// reconcile, and the only ways to make it reconcile would be to invent the missing
  /// figure or to submit a document that silently drops the other property's lines.
  /// Both are worse than refusing.
  ///
  /// [rowVersion] is captured **here**, at load, and carried unchanged to submission
  /// (§3). It is not refreshed if a background pull discovers a newer version while the
  /// user is typing: that is precisely the situation a conflict exists to surface, and
  /// silently re-basing the draft would let one person overwrite an edit they never saw.
  factory ExpenseDraft.fromExisting({
    required String id,
    required int rowVersion,
    required BusinessDate businessDate,
    required Money total,
    required List<AllocationDraft> allocations,
    String? txnNumber,
    String? vendorId,
    PaymentStatus paymentStatus = PaymentStatus.unpaid,
    BusinessDate? paymentDate,
    String? paymentMethodId,
    String? referenceNumber,
    String? notes,
    BusinessDate? accountingPeriodStart,
    BusinessDate? accountingPeriodEnd,
    List<ExpenseAttachment> attachments = const [],
  }) => ExpenseDraft(
    id: id,
    businessDate: businessDate,
    total: total,
    allocations: allocations,
    vendorId: vendorId,
    paymentStatus: paymentStatus,
    paymentDate: paymentDate,
    paymentMethodId: paymentMethodId,
    referenceNumber: referenceNumber,
    notes: notes,
    accountingPeriodStart: accountingPeriodStart,
    accountingPeriodEnd: accountingPeriodEnd,
    attachments: attachments,
    // A document with more than one line, or with a deliberate period split, opens in
    // the split view — otherwise the editor that hosts those rows is never built and
    // the user would silently be shown a simplified form of their own document.
    isSplit: allocations.length > 1 || allocations.any((a) => a.hasPeriodSplit),
    baseRowVersion: rowVersion,
    txnNumber: txnNumber,
    // Captured here, at load, for the same reason [rowVersion] is: it is the fact the
    // form is being edited *against*. Without it "did the date move?" would have to be
    // asked of whatever the local row says at save time, which a background pull can
    // change under a form somebody is typing into.
    originalBusinessDate: businessDate,
  );

  final String id;
  final BusinessDate businessDate;

  /// The business date this draft was loaded with, or null on a new expense.
  ///
  /// Never a `copyWith` parameter, exactly as [baseRowVersion] is not: every keystroke
  /// rebuilds the draft, and a field that could move there is a field that would.
  final BusinessDate? originalBusinessDate;

  /// Why the business date is being changed. Required by the server on that branch and
  /// on no other, so an ordinary correction never sees this field (spec §9).
  final String? correctionReason;

  /// Whether this edit moves the business date of an already-recorded expense.
  ///
  /// The client's own answer, used to shape the form. It is not sent as a claim: the
  /// server decides the same question from canonical state, and its answer is the one
  /// that governs (D-037).
  bool get movesBusinessDate =>
      originalBusinessDate != null && businessDate != originalBusinessDate;

  /// The version this draft was loaded from, or null when it is a new document.
  ///
  /// Carried load → draft → submit, and never re-based (§3). Its presence is also what
  /// [isEdit] means, so there is one fact rather than two that could disagree.
  final int? baseRowVersion;

  /// The server-issued number, for display while editing. Never generated locally.
  final String? txnNumber;

  /// Whether this draft corrects an existing document rather than creating one.
  bool get isEdit => baseRowVersion != null;

  /// The invoice total. On a simple expense this *is* the single line's amount, and the
  /// two are kept in step so a routine user never sees the word "allocation".
  final Money? total;

  final List<AllocationDraft> allocations;
  final String? vendorId;
  final PaymentStatus paymentStatus;
  final BusinessDate? paymentDate;
  final String? paymentMethodId;
  final String? referenceNumber;
  final String? notes;
  final BusinessDate? accountingPeriodStart;
  final BusinessDate? accountingPeriodEnd;
  final List<ExpenseAttachment> attachments;

  /// Whether the user has deliberately opened the split flow.
  ///
  /// Distinct from `allocations.length > 1`: a split with one line so far is still a
  /// split, and the interface should keep saying so rather than silently reverting.
  final bool isSplit;

  bool get isSimple => !isSplit && allocations.length == 1;

  /// What the lines add up to. Blank lines contribute nothing.
  Money get allocated =>
      Money.sum(allocations.map((a) => a.amount ?? Money.zero));

  /// What is still unallocated. Zero exactly is the only state that saves.
  Money get remaining => (total ?? Money.zero) - allocated;

  bool get reconciles => total != null && total!.isPositive && remaining.isZero;

  Set<String> get businessUnitIds => {
    for (final a in allocations)
      if (a.businessUnitId != null) a.businessUnitId!,
  };

  bool get isCrossUnit => businessUnitIds.length > 1;

  bool get hasAnyPeriodSplit => allocations.any((a) => a.hasPeriodSplit);

  ExpenseDraft copyWith({
    BusinessDate? businessDate,
    Money? total,
    List<AllocationDraft>? allocations,
    String? vendorId,
    PaymentStatus? paymentStatus,
    BusinessDate? paymentDate,
    String? paymentMethodId,
    String? referenceNumber,
    String? notes,
    BusinessDate? accountingPeriodStart,
    BusinessDate? accountingPeriodEnd,
    List<ExpenseAttachment>? attachments,
    bool? isSplit,
    String? correctionReason,
    bool clearTotal = false,
    bool clearVendor = false,
    bool clearPayment = false,
    bool clearAccountingPeriod = false,
  }) => ExpenseDraft(
    id: id,
    businessDate: businessDate ?? this.businessDate,
    total: clearTotal ? null : (total ?? this.total),
    allocations: allocations ?? this.allocations,
    vendorId: clearVendor ? null : (vendorId ?? this.vendorId),
    paymentStatus: paymentStatus ?? this.paymentStatus,
    paymentDate: clearPayment ? null : (paymentDate ?? this.paymentDate),
    paymentMethodId: clearPayment
        ? null
        : (paymentMethodId ?? this.paymentMethodId),
    referenceNumber: referenceNumber ?? this.referenceNumber,
    notes: notes ?? this.notes,
    accountingPeriodStart: clearAccountingPeriod
        ? null
        : (accountingPeriodStart ?? this.accountingPeriodStart),
    accountingPeriodEnd: clearAccountingPeriod
        ? null
        : (accountingPeriodEnd ?? this.accountingPeriodEnd),
    attachments: attachments ?? this.attachments,
    isSplit: isSplit ?? this.isSplit,
    // Never parameters. The version an edit is based on, and the date it was loaded
    // with, are both fixed at load — and a `copyWith` is how every keystroke rebuilds
    // the draft, so offering either here is exactly how a background sync would come to
    // re-base somebody's edit silently (§3). If `originalBusinessDate` could move, an
    // edit that moved the date would stop looking like one halfway through typing.
    baseRowVersion: baseRowVersion,
    txnNumber: txnNumber,
    originalBusinessDate: originalBusinessDate,
    correctionReason: correctionReason ?? this.correctionReason,
  );

  // ── Editing ───────────────────────────────────────────────────────────────

  /// Sets the total. On a simple expense the single line follows it, so a routine user
  /// types one number and never learns the word "allocation".
  ExpenseDraft withTotal(Money? amount) {
    if (isSimple) {
      return copyWith(
        total: amount,
        clearTotal: amount == null,
        allocations: [
          allocations.first.copyWith(
            amount: amount,
            clearAmount: amount == null,
          ),
        ],
      );
    }
    return copyWith(total: amount, clearTotal: amount == null);
  }

  /// Changes one field of the classification, invalidating anything beneath it.
  ///
  /// The cascade is the point. Keeping a Crystal Canopy category selected after switching
  /// to Hotel Krishna would produce a line the composite foreign key refuses — and if it
  /// ever did not, a cost charged to the wrong property.
  ExpenseDraft withClassification(
    String allocationId, {
    String? businessUnitId,
    String? departmentId,
    String? sectionId,
    String? categoryId,
  }) => _mapAllocation(allocationId, (line) {
    if (businessUnitId != null && businessUnitId != line.businessUnitId) {
      return line.copyWith(
        businessUnitId: businessUnitId,
        clearDepartment: true,
        clearSection: true,
        clearCategory: true,
      );
    }
    if (departmentId != null && departmentId != line.departmentId) {
      return line.copyWith(
        departmentId: departmentId,
        clearSection: true,
        clearCategory: true,
      );
    }
    if (sectionId != null && sectionId != line.sectionId) {
      return line.copyWith(sectionId: sectionId, clearCategory: true);
    }
    if (categoryId != null) return line.copyWith(categoryId: categoryId);
    return line;
  });

  ExpenseDraft withAllocationAmount(String allocationId, Money? amount) =>
      _mapAllocation(
        allocationId,
        (line) => line.copyWith(amount: amount, clearAmount: amount == null),
      );

  /// Opens the split flow, keeping what has already been classified.
  ExpenseDraft asSplit() => isSplit ? this : copyWith(isSplit: true);

  /// Adds a line, optionally copying the classification of the last one — which is what
  /// somebody splitting a bill between two departments of the same property wants.
  ExpenseDraft addAllocation({bool copyClassification = false}) {
    final previous = allocations.last;
    return copyWith(
      isSplit: true,
      allocations: [
        ...allocations,
        AllocationDraft(
          id: const Uuid().v4(),
          businessUnitId: copyClassification ? previous.businessUnitId : null,
          departmentId: copyClassification ? previous.departmentId : null,
          sectionId: copyClassification ? previous.sectionId : null,
          categoryId: copyClassification ? previous.categoryId : null,
        ),
      ],
    );
  }

  /// Removes a line. The last one is never removed — an expense has at least one.
  ExpenseDraft removeAllocation(String allocationId) {
    if (allocations.length <= 1) return this;
    return copyWith(
      allocations: [
        for (final a in allocations)
          if (a.id != allocationId) a,
      ],
    );
  }

  /// Splits a line across periods, proposing an even division as a starting point.
  ///
  /// A **proposal**, shown in full before anything is saved, using largest-remainder so
  /// the suggestion already reconciles exactly. The user may change any figure, and
  /// nothing is applied silently (D-034).
  ExpenseDraft proposePeriodSplit(
    String allocationId,
    List<({BusinessDate start, BusinessDate end})> periods,
  ) => _mapAllocation(allocationId, (line) {
    if (periods.isEmpty) return line;
    final amount = line.amount;
    final shares = amount == null
        ? List<Money?>.filled(periods.length, null)
        : amount.allocate(List<int>.filled(periods.length, 1));
    return line.copyWith(
      periodSplits: [
        for (var i = 0; i < periods.length; i++)
          PeriodSplitDraft(
            id: const Uuid().v4(),
            start: periods[i].start,
            end: periods[i].end,
            amount: shares[i],
          ),
      ],
    );
  });

  ExpenseDraft clearPeriodSplit(String allocationId) =>
      _mapAllocation(allocationId, (line) => line.copyWith(periodSplits: []));

  ExpenseDraft withPeriodAmount(
    String allocationId,
    String splitId,
    Money? amount,
  ) => _mapAllocation(
    allocationId,
    (line) => line.copyWith(
      periodSplits: [
        for (final s in line.periodSplits)
          if (s.id == splitId)
            s.copyWith(amount: amount, clearAmount: amount == null)
          else
            s,
      ],
    ),
  );

  ExpenseDraft _mapAllocation(
    String allocationId,
    AllocationDraft Function(AllocationDraft) change,
  ) {
    final updated = [
      for (final a in allocations)
        if (a.id == allocationId) change(a) else a,
    ];
    // On a simple expense the line and the total are one number in two places; keep them
    // together so the header cannot drift from the only line.
    final newTotal = !isSplit && updated.length == 1
        ? updated.first.amount
        : total;
    return copyWith(
      allocations: updated,
      total: newTotal,
      clearTotal: newTotal == null,
    );
  }

  // ── Validation ────────────────────────────────────────────────────────────

  /// Everything wrong with the draft right now, in the order worth telling the user.
  List<DraftProblem> problemsFor(Principal principal) {
    final problems = <DraftProblem>[];

    if (total == null) {
      problems.add(DraftProblem.amountMissing);
    } else if (!total!.isPositive) {
      problems.add(DraftProblem.amountNotPositive);
    }

    if (allocations.any((a) => !a.isClassified)) {
      problems.add(DraftProblem.classificationIncomplete);
    }

    if (total != null && total!.isPositive && !remaining.isZero) {
      problems.add(DraftProblem.allocationsDoNotReconcile);
    }

    if (allocations.any((a) => !a.splitReconciles)) {
      problems.add(DraftProblem.periodSplitDoesNotReconcile);
    }

    for (final unit in businessUnitIds) {
      if (!principal.can(Capability.expenseCreate, businessUnitId: unit)) {
        problems.add(DraftProblem.unitOutsideScope);
        break;
      }
    }

    if (isCrossUnit &&
        !businessUnitIds.every(
          (u) => principal.can(
            Capability.expenseAllocateCrossUnit,
            businessUnitId: u,
          ),
        )) {
      problems.add(DraftProblem.crossUnitNotPermitted);
    }

    if (hasAnyPeriodSplit &&
        !principal.canAnywhere(Capability.expenseAllocatePeriods)) {
      problems.add(DraftProblem.periodSplitNotPermitted);
    }

    if (paymentStatus == PaymentStatus.paid &&
        (paymentDate == null || paymentMethodId == null)) {
      problems.add(DraftProblem.paymentIncomplete);
    }

    if (attachments.length > AttachmentPolicy.maxPerExpense ||
        attachments.fold<int>(0, (s, a) => s + a.byteSize) >
            AttachmentPolicy.maxTotalBytesPerExpense) {
      problems.add(DraftProblem.attachmentsOverLimit);
    }

    // Moving the business date of a recorded expense is its own act, with its own
    // capability and its own mandatory reason (spec §9). Both are checked here so the
    // form can say so before the save, and both are re-decided server-side, which is
    // where the boundary actually is (D-037).
    if (movesBusinessDate) {
      if (!mayCorrectBusinessDate(principal)) {
        problems.add(DraftProblem.businessDateCorrectionNotPermitted);
      }
      if ((correctionReason ?? '').trim().isEmpty) {
        problems.add(DraftProblem.businessDateCorrectionNeedsReason);
      }
    }

    return problems;
  }

  bool canSave(Principal principal) => problemsFor(principal).isEmpty;

  /// Whether this user may even open the split flow.
  ///
  /// A Crystal Canopy manager is not offered Hotel Krishna as a target, so the situation
  /// where they fill in a form and are refused at the end never arises.
  static bool mayUseSplit(Principal principal) =>
      principal.canAnywhere(Capability.expenseAllocateCrossUnit);

  static bool mayUsePeriodSplit(Principal principal) =>
      principal.canAnywhere(Capability.expenseAllocatePeriods);

  /// Whether this user may move the business date of an expense that already exists.
  ///
  /// Used to decide whether the edit form offers a date control at all. Hiding it is not
  /// the security boundary — the server refuses regardless — it is so that nobody fills
  /// in a form that was always going to be refused (spec §13.1).
  ///
  /// Recording a *new* expense with a chosen date is unaffected: that is `manual`, not
  /// `corrected`, and it is what the fast path has always done (D-019).
  static bool mayCorrectBusinessDate(Principal principal) =>
      principal.canAnywhere(Capability.correctBusinessDate);

  /// The properties this user may charge an expense to. The picker offers no others.
  static List<MasterNode> selectableUnits(
    MasterGraph graph,
    Principal principal,
  ) => [
    for (final unit in graph.businessUnits())
      if (principal.can(Capability.expenseCreate, businessUnitId: unit.id))
        unit,
  ];

  // ── Producing the aggregate ───────────────────────────────────────────────

  /// Builds the domain document. Throws if the draft does not reconcile — callers check
  /// [canSave] first, and the aggregate's own invariants are the backstop.
  ExpenseDocument toDocument({
    required String orgId,
    required String createdByUserId,
    required DateTime capturedAt,
    required String Function(String categoryId) labelFor,
  }) => ExpenseDocument(
    id: id,
    orgId: orgId,
    businessDate: businessDate,
    businessDateSource: BusinessDateSource.derived,
    accountingPeriodStart: accountingPeriodStart,
    accountingPeriodEnd: accountingPeriodEnd,
    total: total!,
    allocations: [
      for (final line in allocations)
        if (line.hasPeriodSplit)
          ExpenseAllocation(
            id: line.id,
            businessUnitId: line.businessUnitId!,
            departmentId: line.departmentId!,
            sectionId: line.sectionId!,
            categoryId: line.categoryId!,
            categoryLabel: labelFor(line.categoryId!),
            amount: line.amount!,
            periodContributions: [
              for (final split in line.periodSplits)
                PeriodContribution(
                  id: split.id,
                  periodStart: split.start,
                  periodEnd: split.end,
                  amount: split.amount!,
                  isDerived: false,
                ),
            ],
          )
        else
          ExpenseAllocation.wholePeriod(
            id: line.id,
            businessUnitId: line.businessUnitId!,
            departmentId: line.departmentId!,
            sectionId: line.sectionId!,
            categoryId: line.categoryId!,
            categoryLabel: labelFor(line.categoryId!),
            amount: line.amount!,
            businessDate: businessDate,
            accountingPeriodStart: accountingPeriodStart,
            accountingPeriodEnd: accountingPeriodEnd,
          ),
    ],
    vendorId: vendorId,
    paymentStatus: paymentStatus,
    paymentDate: paymentDate,
    paymentMethodId: paymentMethodId,
    referenceNumber: referenceNumber,
    notes: notes,
    attachments: attachments,
    createdByUserId: createdByUserId,
    capturedAt: capturedAt,
  );
}

/// What the entry form remembers between expenses.
///
/// Only ever a *pre-selection*, and only ever re-offered when it is still authorised and
/// still active — an archived category or a property whose scope was withdrawn is dropped
/// rather than proposed (spec §18).
@immutable
final class LastUsedClassification {
  const LastUsedClassification({
    this.businessUnitId,
    this.departmentId,
    this.sectionId,
    this.categoryId,
  });

  final String? businessUnitId;
  final String? departmentId;
  final String? sectionId;
  final String? categoryId;

  /// The part of this that is still safe to offer.
  ///
  /// Checked from the top down and stopped at the first thing that no longer holds, so a
  /// user is never handed a half-valid chain whose lower rungs belong somewhere else.
  LastUsedClassification validAgainst(MasterGraph graph, Principal principal) {
    final unit = businessUnitId;
    if (unit == null ||
        graph.businessUnit(unit) == null ||
        graph.businessUnit(unit)!.isArchived ||
        !principal.can(Capability.expenseCreate, businessUnitId: unit)) {
      return const LastUsedClassification();
    }

    final department = departmentId;
    if (department == null ||
        graph.department(department) == null ||
        graph.department(department)!.isArchived ||
        graph.department(department)!.parentId != unit) {
      return LastUsedClassification(businessUnitId: unit);
    }

    final section = sectionId;
    if (section == null ||
        graph.section(section) == null ||
        graph.section(section)!.isArchived ||
        graph.section(section)!.parentId != department) {
      return LastUsedClassification(
        businessUnitId: unit,
        departmentId: department,
      );
    }

    final category = categoryId;
    if (category == null ||
        graph.expenseCategory(category) == null ||
        graph.expenseCategory(category)!.isArchived ||
        graph.expenseCategory(category)!.parentId != section) {
      return LastUsedClassification(
        businessUnitId: unit,
        departmentId: department,
        sectionId: section,
      );
    }

    return this;
  }

  static LastUsedClassification from(ExpenseDraft draft) {
    final line = draft.allocations.first;
    return LastUsedClassification(
      businessUnitId: line.businessUnitId,
      departmentId: line.departmentId,
      sectionId: line.sectionId,
      categoryId: line.categoryId,
    );
  }
}
