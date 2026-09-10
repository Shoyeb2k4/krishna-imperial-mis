/// An independent reference implementation of the Owner Settlement arithmetic.
///
/// OA-2 §31. The parity oracle, in the shape `pnl_reference.dart` established for the P&L:
/// deliberately naive, obviously correct, and written from the **brief** rather than from
/// the production code.
///
/// Three rules make it worth having, and each of them is the reason the P&L oracle exists:
///
/// * **It calls nothing from production.** No `OwnerSettlement`, no `CumulativeEntitlement`,
///   no `OwnerLedgerTotals`, no `Money`. An oracle that delegates proves a function equals
///   itself. It folds plain `int` paise with `for` loops.
/// * **It does not ship.** It lives in `test/`, and a guard asserts nothing in `lib/`
///   references it.
/// * **It shares only the inputs.** Given the same canonical facts it must produce the
///   same figures to the paisa — no tolerance, ever.
library;

/// One canonical owner movement, reduced to the four facts the arithmetic needs.
///
/// Deliberately not `OwnerLedgerEntry`: taking the production type would let a defect in
/// `signedEffect` or `isCanonical` hide by being present on both sides of the comparison.
/// The caller states the direction and whether it counts.
typedef ReferenceMovement = ({
  String ownerId,
  String type,
  String direction,
  int amountPaise,
  String businessDate,
  bool canonical,
});

/// One owner's reference line.
typedef ReferenceLine = ({
  String ownerId,
  int openingPaise,
  int entitlementPaise,
  int withdrawalsPaise,
  int ncPaise,
  int settlementPaidPaise,
  int adjustmentCreditsPaise,
  int adjustmentDebitsPaise,
  int closingPaise,
});

/// The reference statement.
typedef ReferenceStatement = ({
  int operatingProfitPaise,
  int totalAllocatedPaise,
  int remainderPaise,
  List<ReferenceLine> lines,
});

/// Splits a cumulative profit in half the long way: divide, then take what is left.
///
/// Written as an explicit truncation toward zero rather than as `~/`, so this and the
/// production code do not share an operator whose sign behaviour is the very thing under
/// test.
({int each, int remainder}) referenceSplit(int cumulativePaise) {
  final magnitude = cumulativePaise < 0 ? -cumulativePaise : cumulativePaise;
  final halfMagnitude = (magnitude - magnitude % 2) ~/ 2;
  final each = cumulativePaise < 0 ? -halfMagnitude : halfMagnitude;
  return (each: each, remainder: cumulativePaise - each * 2);
}

/// Computes a month's settlement from canonical facts, by hand.
///
/// [ownerIds] is the V1 pair. [movements] is every canonical movement from inception
/// through the period end; the reference filters and dates them itself.
ReferenceStatement referenceSettlement({
  required List<String> ownerIds,
  required int cumulativeBeforePaise,
  required int cumulativeAtEndPaise,
  required String periodStart,
  required String periodEnd,
  required List<ReferenceMovement> movements,
}) {
  final before = referenceSplit(cumulativeBeforePaise);
  final atEnd = referenceSplit(cumulativeAtEndPaise);
  final periodEntitlement = atEnd.each - before.each;

  final lines = <ReferenceLine>[];
  for (final ownerId in ownerIds) {
    var openingMovements = 0;
    var withdrawals = 0;
    var nc = 0;
    var settlementPaid = 0;
    var credits = 0;
    var debits = 0;
    var inPeriodEffect = 0;

    for (final m in movements) {
      if (m.ownerId != ownerId) continue;
      if (!m.canonical) continue;

      // Signed by hand: a credit adds to the position, a debit subtracts from it.
      final signed = m.direction == 'credit' ? m.amountPaise : -m.amountPaise;

      if (m.businessDate.compareTo(periodStart) < 0) {
        openingMovements += signed;
        continue;
      }
      if (m.businessDate.compareTo(periodEnd) > 0) continue;

      inPeriodEffect += signed;
      switch (m.type) {
        case 'withdrawal':
          withdrawals += m.amountPaise;
        case 'nc_consumption':
          nc += m.amountPaise;
        case 'settlement_paid':
          settlementPaid += m.amountPaise;
        case 'manual_adjustment':
          if (m.direction == 'credit') {
            credits += m.amountPaise;
          } else {
            debits += m.amountPaise;
          }
        case 'opening_balance':
          break;
      }
    }

    final opening = before.each + openingMovements;
    lines.add((
      ownerId: ownerId,
      openingPaise: opening,
      entitlementPaise: periodEntitlement,
      withdrawalsPaise: withdrawals,
      ncPaise: nc,
      settlementPaidPaise: settlementPaid,
      adjustmentCreditsPaise: credits,
      adjustmentDebitsPaise: debits,
      closingPaise: opening + periodEntitlement + inPeriodEffect,
    ));
  }

  lines.sort((a, b) => a.ownerId.compareTo(b.ownerId));

  return (
    operatingProfitPaise: cumulativeAtEndPaise - cumulativeBeforePaise,
    totalAllocatedPaise: atEnd.each * 2,
    remainderPaise: atEnd.remainder,
    lines: lines,
  );
}
