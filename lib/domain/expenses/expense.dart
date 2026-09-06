/// The expense aggregate: one document, its allocation lines, and their period
/// contributions.
///
/// Three structural decisions carry almost all of the financial correctness.
///
/// **1 · Classification lives on the lines, never on the document (D-003).** An
/// electricity bill belongs to both properties; a grocery bill belongs to one. Modelling
/// the second as a special case of the first — one line at 100% — means there is one
/// reporting path rather than two, and no expense can fall outside the hierarchy.
///
/// **2 · Every line carries period contributions, always (D-060).** Where a cost genuinely
/// spans months an authorised user splits it; where it does not, the default rule produces
/// a single derived contribution covering the whole amount. Reporting reads *only* those
/// contributions and never the line amount, so a split line contributes ₹30,000 to May and
/// ₹30,000 to June and cannot also contribute ₹60,000 to a document-level date. Double
/// counting is not prevented by a query being careful; there is no second place the amount
/// lives.
///
/// **3 · Money is integer paise throughout, and reconciliation is exact.** `SUM(lines) =
/// total` and `SUM(contributions) = line amount` are invariants of the type: an
/// [ExpenseDocument] that does not balance cannot be constructed. The database enforces
/// the same two sums independently, because a modified client is not a trusted source.
library;

import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

export 'package:krishna_mis/domain/attachments/document_attachment.dart';

/// What an expense's supporting evidence is called in expense code.
typedef ExpenseAttachment = DocumentAttachment;

/// Whether cash has actually moved. Partial payment is not modelled in V1 (spec §5.4).
enum PaymentStatus {
  unpaid,
  paid;

  static PaymentStatus fromName(String value) =>
      PaymentStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () =>
            throw ArgumentError.value(value, 'value', 'unknown payment status'),
      );

  String get label => switch (this) {
    PaymentStatus.unpaid => 'Unpaid',
    PaymentStatus.paid => 'Paid',
  };
}

/// One accounting period's share of one allocation line.
///
/// Always present — see [ExpenseAllocation.periodContributions]. [isDerived] separates
/// "the system applied the default rule" from "a person decided this split", which the
/// interface, the audit trail and the `expense.allocate_periods` capability all care
/// about even though the arithmetic does not.
final class PeriodContribution {
  PeriodContribution({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.amount,
    required this.isDerived,
  }) {
    if (periodStart.compareTo(periodEnd) > 0) {
      throw ArgumentError(
        'An accounting period cannot end before it starts: '
        '${periodStart.iso} … ${periodEnd.iso}',
      );
    }
  }

  /// The default contribution for a line with no deliberate split.
  ///
  /// The whole amount, in the one accounting period the document already names — the
  /// service period if it has one, otherwise the business date's own month. This is the
  /// approved default policy (D-034) expressed as data rather than as a branch in a
  /// query.
  factory PeriodContribution.derivedFrom({
    required String id,
    required Money amount,
    required BusinessDate businessDate,
    BusinessDate? accountingPeriodStart,
    BusinessDate? accountingPeriodEnd,
  }) => PeriodContribution(
    id: id,
    periodStart: accountingPeriodStart ?? businessDate,
    periodEnd: accountingPeriodEnd ?? businessDate,
    amount: amount,
    isDerived: true,
  );

  final String id;
  final BusinessDate periodStart;
  final BusinessDate periodEnd;
  final Money amount;
  final bool isDerived;

  /// The period this share reports into: `COALESCE(accounting_period_end,
  /// business_date)` applied at contribution level (spec §5.2).
  String get periodKey => periodEnd.periodKey;

  /// The date profitability indexes on. Stored, never re-derived at read time.
  BusinessDate get pnlDate => periodEnd;

  @override
  String toString() =>
      'PeriodContribution($periodKey, ${amount.paise}p'
      '${isDerived ? ', derived' : ''})';
}

/// One line of an expense: what it is charged to, how much, and when it reports.
final class ExpenseAllocation {
  ExpenseAllocation({
    required this.id,
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
    required this.amount,
    required this.periodContributions,
    this.categoryLabel = '',
  }) {
    if (amount.paise <= 0) {
      throw ArgumentError.value(
        amount.paise,
        'amount',
        'an allocation line must carry a positive amount — a zero line says nothing '
            'and a negative one is a reversal, which is a separate document',
      );
    }
    if (periodContributions.isEmpty) {
      throw ArgumentError(
        'every line carries at least one period contribution; use '
        'ExpenseAllocation.wholePeriod for the ordinary case',
      );
    }
    final contributed = Money.sum(periodContributions.map((c) => c.amount));
    if (contributed != amount) {
      throw ExpenseImbalance(
        what: 'period contributions on allocation $id',
        expected: amount,
        actual: contributed,
      );
    }
  }

  /// The ordinary line: one period, the whole amount, derived by the default rule.
  factory ExpenseAllocation.wholePeriod({
    required String id,
    required String businessUnitId,
    required String departmentId,
    required String sectionId,
    required String categoryId,
    required Money amount,
    required BusinessDate businessDate,
    BusinessDate? accountingPeriodStart,
    BusinessDate? accountingPeriodEnd,
    String? contributionId,
    String categoryLabel = '',
  }) => ExpenseAllocation(
    id: id,
    businessUnitId: businessUnitId,
    departmentId: departmentId,
    sectionId: sectionId,
    categoryId: categoryId,
    amount: amount,
    categoryLabel: categoryLabel,
    periodContributions: [
      PeriodContribution.derivedFrom(
        id: contributionId ?? '$id:period',
        amount: amount,
        businessDate: businessDate,
        accountingPeriodStart: accountingPeriodStart,
        accountingPeriodEnd: accountingPeriodEnd,
      ),
    ],
  );

  final String id;
  final String businessUnitId;
  final String departmentId;
  final String sectionId;
  final String categoryId;
  final Money amount;

  /// What the category was called when this was recorded (D-035).
  ///
  /// Held on the line so an offline device can render the document without the master
  /// hierarchy — which a scope purge may legitimately have removed (D-048). The server
  /// re-reads the authoritative name when it writes, so a client cannot mislabel history
  /// by sending something else; this copy is for display, not for truth.
  final String categoryLabel;

  /// Never empty. Exactly one derived entry for an ordinary line; two or more chosen
  /// entries for a cost a person deliberately spread across months.
  final List<PeriodContribution> periodContributions;

  /// Whether a person split this line, as opposed to the default rule filling it in.
  ///
  /// Drives the `expense.allocate_periods` capability check and what the audit trail
  /// says. It is `true` for any line whose contributions were not all derived, including
  /// a single-period contribution somebody set by hand.
  bool get hasDeliberatePeriodSplit =>
      periodContributions.length > 1 ||
      periodContributions.any((c) => !c.isDerived);

  /// Every accounting period this line touches.
  Set<String> get periodKeys => {
    for (final contribution in periodContributions) contribution.periodKey,
  };

  @override
  String toString() =>
      'ExpenseAllocation($id, $businessUnitId, ${amount.paise}p, '
      '${periodContributions.length} period(s))';
}

/// Attachments are the same three things for every financial document — a lifecycle, a
/// size policy and a file record — so they live in `domain/attachments/` and are shared
/// with revenue (Slice 11). Re-exported here because every expense surface already
/// imports this library for them, and [ExpenseAttachment] stays the name expense code
/// uses for what is now one class.

/// Raised when money does not reconcile. Carries both sides, because "does not balance"
/// without the figures is useless to whoever has to fix it.
final class ExpenseImbalance implements Exception {
  const ExpenseImbalance({
    required this.what,
    required this.expected,
    required this.actual,
  });

  final String what;
  final Money expected;
  final Money actual;

  Money get difference => actual - expected;

  @override
  String toString() =>
      'ExpenseImbalance: $what must total ${expected.paise}p but totals '
      '${actual.paise}p (out by ${difference.paise}p)';
}

/// The expense document.
///
/// Constructing one asserts every invariant that can be asserted locally. It is not the
/// security boundary — the server re-checks all of it and its answer is final (D-037) —
/// but it does mean an unbalanced expense cannot exist in memory, be handed to a screen,
/// or be written to the local database on its way to the outbox.
final class ExpenseDocument {
  ExpenseDocument({
    required this.id,
    required this.orgId,
    required this.businessDate,
    required this.businessDateSource,
    required this.total,
    required this.allocations,
    required this.paymentStatus,
    required this.createdByUserId,
    required this.capturedAt,
    this.number,
    this.accountingPeriodStart,
    this.accountingPeriodEnd,
    this.vendorId,
    this.paymentDate,
    this.paymentMethodId,
    this.referenceNumber,
    this.notes,
    this.taxAmount,
    this.attachments = const [],
    this.rowVersion = 1,
    this.voidedAt,
    this.voidReason,
  }) {
    if (total.paise <= 0) {
      throw ArgumentError.value(
        total.paise,
        'total',
        'an expense must carry a positive total',
      );
    }
    if (allocations.isEmpty) {
      throw ArgumentError(
        'an expense has at least one allocation line — a simple expense has exactly '
        'one, at 100% (D-003)',
      );
    }
    final allocated = Money.sum(allocations.map((a) => a.amount));
    if (allocated != total) {
      throw ExpenseImbalance(
        what: 'allocation lines on expense $id',
        expected: total,
        actual: allocated,
      );
    }
    if (paymentStatus == PaymentStatus.paid &&
        (paymentDate == null || paymentMethodId == null)) {
      throw ArgumentError(
        'a paid expense states when it was paid and by what means (spec §5.4)',
      );
    }
    if (paymentStatus == PaymentStatus.unpaid && paymentDate != null) {
      throw ArgumentError('an unpaid expense cannot carry a payment date');
    }
    if ((accountingPeriodStart == null) != (accountingPeriodEnd == null)) {
      throw ArgumentError(
        'an accounting period is either fully specified or absent',
      );
    }
    if (accountingPeriodStart != null &&
        accountingPeriodStart!.compareTo(accountingPeriodEnd!) > 0) {
      throw ArgumentError('an accounting period cannot end before it starts');
    }
    if (attachments.length > AttachmentPolicy.maxPerDocument) {
      throw ArgumentError(
        'at most ${AttachmentPolicy.maxPerDocument} attachments per expense',
      );
    }
    final attachmentBytes = attachments.fold<int>(
      0,
      (sum, a) => sum + a.byteSize,
    );
    if (attachmentBytes > AttachmentPolicy.maxTotalBytesPerDocument) {
      throw ArgumentError(
        'attachments total $attachmentBytes bytes, over the '
        '${AttachmentPolicy.maxTotalBytesPerDocument} byte limit for one expense',
      );
    }
    if (isVoided && (voidReason == null || voidReason!.trim().isEmpty)) {
      throw ArgumentError('a void always states why (spec §14)');
    }
  }

  final String id;
  final String orgId;

  /// Null until the server issues one. A client never invents it (see
  /// [ExpenseNumber]).
  final ExpenseNumber? number;

  final BusinessDate businessDate;
  final BusinessDateSource businessDateSource;

  /// The optional service period the cost covers — a salary month, a billing period.
  final BusinessDate? accountingPeriodStart;
  final BusinessDate? accountingPeriodEnd;

  final Money total;
  final List<ExpenseAllocation> allocations;

  final String? vendorId;
  final PaymentStatus paymentStatus;
  final BusinessDate? paymentDate;
  final String? paymentMethodId;
  final String? referenceNumber;
  final String? notes;

  /// Informational only (D-018). Never reduces the expense, never enters a calculation,
  /// never implies recoverability.
  final Money? taxAmount;

  final List<ExpenseAttachment> attachments;

  final String createdByUserId;

  /// The device instant. Forensic metadata; server timestamps are authoritative (§9).
  final DateTime capturedAt;

  final int rowVersion;
  final DateTime? voidedAt;
  final String? voidReason;

  bool get isVoided => voidedAt != null;

  /// Every business unit this expense charges. One for an ordinary expense; more for a
  /// shared bill. The creator needs scope over all of them (spec §7).
  Set<String> get businessUnitIds => {
    for (final allocation in allocations) allocation.businessUnitId,
  };

  bool get isCrossUnit => businessUnitIds.length > 1;

  /// Every accounting period this expense reports into.
  ///
  /// Each one is checked against period locks and the edit window **individually**
  /// (D-034): a split touching a closed month is refused like any other write into it.
  Set<String> get periodKeys => {
    for (final allocation in allocations) ...allocation.periodKeys,
  };

  bool get hasDeliberatePeriodSplit =>
      allocations.any((a) => a.hasDeliberatePeriodSplit);

  /// The canonical reporting rows: one per period contribution, per line.
  ///
  /// **This is the only reporting source.** There is deliberately no document-level
  /// `pnlDate` on this type, so no caller can sum the total against one date *and* the
  /// contributions against their own. A ₹60,000 line split May/June yields exactly two
  /// rows of ₹30,000 and nothing else (D-060).
  Iterable<ExpenseReportingRow> get reportingRows sync* {
    for (final allocation in allocations) {
      for (final contribution in allocation.periodContributions) {
        yield ExpenseReportingRow(
          expenseId: id,
          allocationId: allocation.id,
          contributionId: contribution.id,
          businessUnitId: allocation.businessUnitId,
          departmentId: allocation.departmentId,
          sectionId: allocation.sectionId,
          categoryId: allocation.categoryId,
          periodKey: contribution.periodKey,
          pnlDate: contribution.pnlDate,
          amount: contribution.amount,
        );
      }
    }
  }

  /// What the reporting rows total. Equal to [total] by construction; asserted anyway,
  /// because this is the number that becomes a P&L.
  Money get reportedTotal => Money.sum(reportingRows.map((r) => r.amount));

  /// Only the part of this document a user scoped to [units] is entitled to see.
  ///
  /// Line-level RLS alone is not enough: an unrestricted header total on a shared bill
  /// tells a Crystal Canopy manager exactly what Hotel Krishna was charged, by
  /// subtraction. The server returns this projection rather than the whole document, and
  /// no client is trusted to hide a field it was sent.
  ExpenseProjection projectedFor(Set<String>? units) {
    if (units == null) {
      return ExpenseProjection(
        expense: this,
        visibleAllocations: allocations,
        visibleTotal: total,
        isComplete: true,
      );
    }
    final visible = [
      for (final allocation in allocations)
        if (units.contains(allocation.businessUnitId)) allocation,
    ];
    final visibleTotal = Money.sum(visible.map((a) => a.amount));
    return ExpenseProjection(
      expense: this,
      visibleAllocations: visible,
      visibleTotal: visibleTotal,
      isComplete: visible.length == allocations.length,
    );
  }

  @override
  String toString() =>
      'ExpenseDocument(${number?.formatted ?? id}, ${total.paise}p, '
      '${allocations.length} line(s), ${businessUnitIds.length} unit(s)'
      '${isVoided ? ', voided' : ''})';
}

/// One row of the canonical reporting projection.
final class ExpenseReportingRow {
  const ExpenseReportingRow({
    required this.expenseId,
    required this.allocationId,
    required this.contributionId,
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
    required this.periodKey,
    required this.pnlDate,
    required this.amount,
  });

  final String expenseId;
  final String allocationId;
  final String contributionId;
  final String businessUnitId;
  final String departmentId;
  final String sectionId;
  final String categoryId;
  final String periodKey;
  final BusinessDate pnlDate;
  final Money amount;

  @override
  String toString() =>
      'ExpenseReportingRow($periodKey, $businessUnitId, ${amount.paise}p)';
}

/// What one user may see of one expense.
///
/// [isComplete] is the honest part. A unit-scoped user looking at a shared bill sees
/// their own share and is told that this is a share — rather than being shown a figure
/// that looks like the whole document and is not.
final class ExpenseProjection {
  const ExpenseProjection({
    required this.expense,
    required this.visibleAllocations,
    required this.visibleTotal,
    required this.isComplete,
  });

  final ExpenseDocument expense;
  final List<ExpenseAllocation> visibleAllocations;

  /// The sum of the lines this user may see — **not** the document total, unless they
  /// may see all of them.
  final Money visibleTotal;

  /// Whether this is the whole document. False means lines were withheld.
  final bool isComplete;

  bool get isPartial => !isComplete;

  /// The document total, or null when the user may not see it.
  ///
  /// Withheld deliberately: on a two-property bill the total plus one share is the other
  /// share, so publishing the header total would hand over exactly what the scope was
  /// meant to protect.
  Money? get documentTotal => isComplete ? expense.total : null;

  bool get hasAnythingVisible => visibleAllocations.isNotEmpty;
}
