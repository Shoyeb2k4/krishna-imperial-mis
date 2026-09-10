/// The Owner Settlement Engine, proven against the brief's own reference controls.
///
/// Phase 5 OA-2 §34 … §43. Every figure here is exact paise and every control is one the
/// project lead wrote down, so a later reader can check the software against the
/// instruction rather than against itself.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/owner_accounts/owner.dart';
import 'package:krishna_mis/domain/owner_accounts/owner_ledger.dart';
import 'package:krishna_mis/domain/owner_accounts/settlement/owner_entitlement.dart';
import 'package:krishna_mis/domain/owner_accounts/settlement/owner_settlement.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

import '../support/owner_settlement_reference.dart';

/// ₹1 = 100 paise. Written out so a control reads like the brief.
Money rupees(int amount) => Money.fromPaise(amount * 100);

BusinessDate d(int y, int m, int day) => BusinessDate.of(y, m, day);

const ownerA = 'owner-a';
const ownerB = 'owner-b';

/// The approved V1 vector, effective from the fixture inception.
OwnershipResolution vector({int fromYear = 2026, int fromMonth = 1}) =>
    OwnershipShareSet([
      OwnershipShare(
        id: 'share-a',
        ownerId: ownerA,
        shareBasisPoints: v1ShareBasisPoints,
        effectiveFrom: d(fromYear, fromMonth, 1),
      ),
      OwnershipShare(
        id: 'share-b',
        ownerId: ownerB,
        shareBasisPoints: v1ShareBasisPoints,
        effectiveFrom: d(fromYear, fromMonth, 1),
      ),
    ]).resolveV1For(d(2026, 6, 1), d(2026, 6, 30));

int _seq = 0;

OwnerLedgerEntry movement({
  required String ownerId,
  required OwnerMovementType type,
  required OwnerLedgerDirection direction,
  required Money amount,
  BusinessDate? on,
  bool accepted = true,
  bool voided = false,
  String? familyMemberId,
}) {
  _seq++;
  return OwnerLedgerEntry(
    id: 'movement-$_seq',
    orgId: 'org',
    businessUnitId: 'hki',
    businessDate: on ?? d(2026, 6, 15),
    businessDateSource: BusinessDateSource.derived,
    movementType: type,
    direction: direction,
    amount: amount,
    ownerId: ownerId,
    txnNumber: accepted
        ? 'KI-OWN-26-27-${_seq.toString().padLeft(6, '0')}'
        : null,
    financialYear: accepted ? '26-27' : null,
    familyMemberId: familyMemberId,
    reason: type == OwnerMovementType.manualAdjustment ? 'stated' : null,
    createdByUserId: 'user',
    capturedAt: DateTime.utc(2026, 6, 15, 10),
    rowVersion: 1,
    voidedAt: voided ? DateTime.utc(2026, 6, 20) : null,
    voidReason: voided ? 'stated' : null,
  );
}

/// June 2026, with settlement inception well before it, coverage established.
OwnerSettlementOutcome settleJune({
  required Money cumulativeBefore,
  required Money cumulativeAtEnd,
  List<OwnerLedgerEntry> movements = const [],
  Map<String, Money> byUnit = const {},
  BusinessDate? inception,
  OwnershipResolution? ownership,
  bool coverage = true,
}) => OwnerSettlement.compute(
  periodKey: '2026-06',
  periodStart: d(2026, 6, 1),
  periodEnd: d(2026, 6, 30),
  inception: inception ?? d(2026, 1, 1),
  ownership: ownership ?? vector(),
  operatingProfit: CanonicalOperatingProfit(
    cumulativeBeforePeriod: cumulativeBefore,
    cumulativeAtPeriodEnd: cumulativeAtEnd,
    byBusinessUnitForPeriod: byUnit,
  ),
  canonicalMovements: movements,
  ledgerCoverageComplete: coverage,
);

OwnerSettlementLine lineFor(OwnerSettlementOutcome outcome, String ownerId) =>
    (outcome as OwnerSettlementComputed).lines.firstWhere(
      (l) => l.ownerId == ownerId,
    );

void main() {
  setUp(() => _seq = 0);

  // ═══════════════════════════════════════════════════════════════════════════
  group('§34 · reference control A, the worked example', () {
    // Opening ₹0 · monthly Operating Profit ₹2,00,000 · entitlement ₹1,00,000 each.
    // Owner A: withdrawal ₹20,000, NC ₹5,000, settlement paid ₹25,000, no adjustments.
    // Owner B: nothing.
    late OwnerSettlementOutcome outcome;

    setUp(() {
      outcome = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(200000),
        movements: [
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.withdrawal,
            direction: OwnerLedgerDirection.debit,
            amount: rupees(20000),
          ),
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.ncConsumption,
            direction: OwnerLedgerDirection.debit,
            amount: rupees(5000),
          ),
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.settlementPaid,
            direction: OwnerLedgerDirection.debit,
            amount: rupees(25000),
          ),
        ],
      );
    });

    test('Owner A closes at ₹50,000 due', () {
      final a = lineFor(outcome, ownerA);
      expect(a.openingPosition, Money.zero);
      expect(a.profitEntitlement, rupees(100000));
      expect(a.withdrawals, rupees(20000));
      expect(a.ncConsumption, rupees(5000));
      expect(a.settlementPaid, rupees(25000));
      expect(a.adjustmentCredits, Money.zero);
      expect(a.adjustmentDebits, Money.zero);
      expect(a.closingPosition, rupees(50000));
      expect(a.reconciles, isTrue);
    });

    test('Owner B, with no movements at all, closes at ₹1,00,000 due', () {
      final b = lineFor(outcome, ownerB);
      expect(b.profitEntitlement, rupees(100000));
      expect(b.closingPosition, rupees(100000));
      expect(b.netMovements, Money.zero);
    });

    test(
      'and the statement agrees with the independent oracle, to the paisa',
      () {
        final reference = referenceSettlement(
          ownerIds: [ownerA, ownerB],
          cumulativeBeforePaise: 0,
          cumulativeAtEndPaise: 20000000,
          periodStart: '2026-06-01',
          periodEnd: '2026-06-30',
          movements: [
            (
              ownerId: ownerA,
              type: 'withdrawal',
              direction: 'debit',
              amountPaise: 2000000,
              businessDate: '2026-06-15',
              canonical: true,
            ),
            (
              ownerId: ownerA,
              type: 'nc_consumption',
              direction: 'debit',
              amountPaise: 500000,
              businessDate: '2026-06-15',
              canonical: true,
            ),
            (
              ownerId: ownerA,
              type: 'settlement_paid',
              direction: 'debit',
              amountPaise: 2500000,
              businessDate: '2026-06-15',
              canonical: true,
            ),
          ],
        );

        final computed = outcome as OwnerSettlementComputed;
        expect(computed.operatingProfit.paise, reference.operatingProfitPaise);
        expect(
          computed.totalEntitlementAllocated.paise,
          reference.totalAllocatedPaise,
        );
        expect(computed.undistributedRemainder.paise, reference.remainderPaise);
        for (var i = 0; i < computed.lines.length; i++) {
          final l = computed.lines[i];
          final r = reference.lines[i];
          expect(l.ownerId, r.ownerId);
          expect(l.openingPosition.paise, r.openingPaise);
          expect(l.profitEntitlement.paise, r.entitlementPaise);
          expect(l.withdrawals.paise, r.withdrawalsPaise);
          expect(l.ncConsumption.paise, r.ncPaise);
          expect(l.settlementPaid.paise, r.settlementPaidPaise);
          expect(l.adjustmentCredits.paise, r.adjustmentCreditsPaise);
          expect(l.adjustmentDebits.paise, r.adjustmentDebitsPaise);
          expect(l.closingPosition.paise, r.closingPaise);
        }
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§35 · a loss is shared, and never clamped', () {
    test('Operating Profit of −₹1,00,000 gives each owner −₹50,000', () {
      final outcome = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: -rupees(100000),
      );

      for (final ownerId in [ownerA, ownerB]) {
        final line = lineFor(outcome, ownerId);
        expect(line.profitEntitlement, -rupees(50000));
        expect(line.closingPosition, -rupees(50000));
        expect(
          line.closingPosition.isNegative,
          isTrue,
          reason: 'a loss reduces the position; it is not floored at zero (§7)',
        );
      }
    });

    test(
      'a loss following a profit reduces the position by exactly the share',
      () {
        // Cumulative ₹2,00,000 through May, then a ₹1,00,000 loss in June.
        final outcome = settleJune(
          cumulativeBefore: rupees(200000),
          cumulativeAtEnd: rupees(100000),
        );
        final a = lineFor(outcome, ownerA);
        expect(a.openingPosition, rupees(100000));
        expect(a.profitEntitlement, -rupees(50000));
        expect(a.closingPosition, rupees(50000));
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§36 · opening balances, with the direction proven explicitly', () {
    test('a credit opening raises the position and a debit opening lowers it', () {
      // Owner A opening credit ₹30,000; Owner B opening debit ₹10,000; then ₹50,000
      // entitlement each. Both openings are dated before the period, so they land in the
      // opening position rather than in the month's activity.
      final outcome = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
        movements: [
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.openingBalance,
            direction: OwnerLedgerDirection.credit,
            amount: rupees(30000),
            on: d(2026, 1, 1),
          ),
          movement(
            ownerId: ownerB,
            type: OwnerMovementType.openingBalance,
            direction: OwnerLedgerDirection.debit,
            amount: rupees(10000),
            on: d(2026, 1, 1),
          ),
        ],
      );

      final a = lineFor(outcome, ownerA);
      expect(a.openingPosition, rupees(30000));
      expect(a.closingPosition, rupees(80000));

      final b = lineFor(outcome, ownerB);
      expect(b.openingPosition, -rupees(10000));
      expect(b.closingPosition, rupees(40000));
    });

    test('there is no opening-balance field anywhere — it is a movement (§10)', () {
      // Asserted structurally as well, in the guard suite. Here: the same figure is
      // reachable only by supplying a movement, so a caller cannot set an opening
      // position without one.
      final withoutMovement = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
      );
      expect(lineFor(withoutMovement, ownerA).openingPosition, Money.zero);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§37 · the odd paisa belongs to neither owner', () {
    test('10001 paise splits 5000 / 5000 with 1 undistributed', () {
      final split = CumulativeEntitlement.of(Money.fromPaise(10001));
      expect(split.perOwner.paise, 5000);
      expect(split.undistributedRemainder.paise, 1);
      expect(split.reconciles, isTrue);
      expect(split.remainderIsMinimal, isTrue);
    });

    test('10002 paise resolves the remainder on its own', () {
      final split = CumulativeEntitlement.of(Money.fromPaise(10002));
      expect(split.perOwner.paise, 5001);
      expect(split.undistributedRemainder.paise, 0);
      expect(split.reconciles, isTrue);
    });

    test(
      'a negative odd amount is symmetric — no owner is favoured either way',
      () {
        final split = CumulativeEntitlement.of(Money.fromPaise(-10001));
        expect(split.perOwner.paise, -5000);
        expect(
          split.undistributedRemainder.paise,
          -1,
          reason:
              'the remainder carries the sign of the profit; rounding away from zero '
              'would hand one owner an extra paisa of loss',
        );
        expect(split.reconciles, isTrue);
      },
    );

    test('the invariant holds across a sweep, positive and negative', () {
      for (var paise = -1000; paise <= 1000; paise++) {
        final split = CumulativeEntitlement.of(Money.fromPaise(paise));
        expect(
          split.reconciles,
          isTrue,
          reason: '$paise must reconcile exactly',
        );
        expect(split.remainderIsMinimal, isTrue, reason: '$paise');
        // And the oracle agrees, computed a different way.
        final reference = referenceSplit(paise);
        expect(split.perOwner.paise, reference.each, reason: '$paise');
        expect(
          split.undistributedRemainder.paise,
          reference.remainder,
          reason: '$paise',
        );
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§38 · period entitlement is a difference of cumulatives', () {
    test(
      'two months of one paisa allocate both paise, which a monthly floor loses',
      () {
        // Month 1: cumulative 1 paisa.
        final month1 = PeriodEntitlement(
          cumulativeBefore: CumulativeEntitlement.of(Money.zero),
          cumulativeAtEnd: CumulativeEntitlement.of(Money.fromPaise(1)),
        );
        expect(month1.perOwner.paise, 0);
        expect(month1.undistributedRemainder.paise, 1);

        // Month 2: cumulative 2 paise.
        final month2 = PeriodEntitlement(
          cumulativeBefore: CumulativeEntitlement.of(Money.fromPaise(1)),
          cumulativeAtEnd: CumulativeEntitlement.of(Money.fromPaise(2)),
        );
        expect(month2.perOwner.paise, 1);
        expect(month2.undistributedRemainder.paise, 0);

        final allocated =
            (month1.perOwner.paise + month2.perOwner.paise) * v1OwnerCount;
        expect(
          allocated,
          2,
          reason:
              'both paise reach an owner. The naive floor(profit / 2) each month would '
              'allocate 0 and 0 and lose them permanently (§38)',
        );
      },
    );

    test(
      'and the naive method is demonstrably worse, stated rather than asserted',
      () {
        // The comparison is the point of the control: it shows what the rule prevents.
        const monthlyProfits = [1, 1, 1, 1, 1];
        var naive = 0;
        for (final profit in monthlyProfits) {
          naive += (profit ~/ 2) * v1OwnerCount;
        }

        var cumulative = 0;
        var cumulativeAllocated = 0;
        var previousPerOwner = 0;
        for (final profit in monthlyProfits) {
          cumulative += profit;
          final perOwner = CumulativeEntitlement.of(
            Money.fromPaise(cumulative),
          ).perOwner.paise;
          cumulativeAllocated += (perOwner - previousPerOwner) * v1OwnerCount;
          previousPerOwner = perOwner;
        }

        expect(naive, 0, reason: 'five paise, none of them allocated');
        expect(
          cumulativeAllocated,
          4,
          reason: 'four of the five, and the fifth is pending',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§39 · every movement type, proven individually', () {
    Money closingWith(OwnerMovementType type, OwnerLedgerDirection direction) {
      final outcome = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
        movements: [
          movement(
            ownerId: ownerA,
            type: type,
            direction: direction,
            amount: rupees(10000),
          ),
        ],
      );
      return lineFor(outcome, ownerA).closingPosition;
    }

    test('a withdrawal reduces the position', () {
      expect(
        closingWith(OwnerMovementType.withdrawal, OwnerLedgerDirection.debit),
        rupees(40000),
      );
    });

    test('non-chargeable consumption reduces the position', () {
      expect(
        closingWith(
          OwnerMovementType.ncConsumption,
          OwnerLedgerDirection.debit,
        ),
        rupees(40000),
      );
    });

    test('a settlement payment reduces the position', () {
      expect(
        closingWith(
          OwnerMovementType.settlementPaid,
          OwnerLedgerDirection.debit,
        ),
        rupees(40000),
      );
    });

    test('an adjustment credit increases it, and a debit decreases it', () {
      expect(
        closingWith(
          OwnerMovementType.manualAdjustment,
          OwnerLedgerDirection.credit,
        ),
        rupees(60000),
      );
      expect(
        closingWith(
          OwnerMovementType.manualAdjustment,
          OwnerLedgerDirection.debit,
        ),
        rupees(40000),
      );
    });

    test('withdrawal and settlement paid stay separate figures (§13)', () {
      // Same amount, same direction, same effect on the position — and they must remain
      // separately answerable, because "what did the owner take out?" and "what have we
      // formally settled?" are different questions.
      final outcome = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
        movements: [
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.withdrawal,
            direction: OwnerLedgerDirection.debit,
            amount: rupees(10000),
          ),
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.settlementPaid,
            direction: OwnerLedgerDirection.debit,
            amount: rupees(10000),
          ),
        ],
      );
      final a = lineFor(outcome, ownerA);
      expect(a.withdrawals, rupees(10000));
      expect(a.settlementPaid, rupees(10000));
      expect(a.closingPosition, rupees(30000));
    });

    test('a voided movement contributes zero, and stays in the input', () {
      final voided = movement(
        ownerId: ownerA,
        type: OwnerMovementType.withdrawal,
        direction: OwnerLedgerDirection.debit,
        amount: rupees(10000),
        voided: true,
      );
      final outcome = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
        movements: [voided],
      );
      expect(lineFor(outcome, ownerA).closingPosition, rupees(50000));
      expect(lineFor(outcome, ownerA).withdrawals, Money.zero);
      expect(voided.isVoided, isTrue, reason: 'history is not destroyed (§28)');
    });

    test('an unaccepted attempt contributes zero (§16, §17)', () {
      final outcome = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
        movements: [
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.withdrawal,
            direction: OwnerLedgerDirection.debit,
            amount: rupees(10000),
            accepted: false,
          ),
        ],
      );
      expect(
        lineFor(outcome, ownerA).closingPosition,
        rupees(50000),
        reason:
            'a locally recorded attempt the server has not accepted is intent, not a '
            'movement. There is no provisional settlement in V1',
      );
    });

    test('a corrected movement contributes its corrected value only', () {
      // A correction rewrites the movement in place — OA-1 keeps one row and advances
      // its version — so settlement sees the corrected amount and nothing else.
      final corrected = movement(
        ownerId: ownerA,
        type: OwnerMovementType.withdrawal,
        direction: OwnerLedgerDirection.debit,
        amount: rupees(7000),
      );
      final outcome = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
        movements: [corrected],
      );
      expect(lineFor(outcome, ownerA).withdrawals, rupees(7000));
      expect(lineFor(outcome, ownerA).closingPosition, rupees(43000));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§40 · family attribution debits the resolved owner', () {
    test(
      'a family member of Owner A consuming NC debits A, and leaves B alone',
      () {
        final outcome = settleJune(
          cumulativeBefore: Money.zero,
          cumulativeAtEnd: rupees(100000),
          movements: [
            movement(
              ownerId: ownerA,
              type: OwnerMovementType.ncConsumption,
              direction: OwnerLedgerDirection.debit,
              amount: rupees(5000),
              familyMemberId: 'family-a1',
            ),
          ],
        );

        expect(lineFor(outcome, ownerA).ncConsumption, rupees(5000));
        expect(lineFor(outcome, ownerA).closingPosition, rupees(45000));

        final b = lineFor(outcome, ownerB);
        expect(b.ncConsumption, Money.zero);
        expect(
          b.closingPosition,
          rupees(50000),
          reason: 'the other owner is untouched by who consumed',
        );
      },
    );

    test(
      'who consumed is metadata; the owner on the movement decides the debit',
      () {
        // Changing the family member on a movement whose resolved owner is unchanged
        // cannot move the debit — settlement reads `ownerId`, which the server resolved
        // and snapshotted, and never re-derives it from the family link.
        final withOneMember = settleJune(
          cumulativeBefore: Money.zero,
          cumulativeAtEnd: rupees(100000),
          movements: [
            movement(
              ownerId: ownerA,
              type: OwnerMovementType.ncConsumption,
              direction: OwnerLedgerDirection.debit,
              amount: rupees(5000),
              familyMemberId: 'family-a1',
            ),
          ],
        );
        final withAnother = settleJune(
          cumulativeBefore: Money.zero,
          cumulativeAtEnd: rupees(100000),
          movements: [
            movement(
              ownerId: ownerA,
              type: OwnerMovementType.ncConsumption,
              direction: OwnerLedgerDirection.debit,
              amount: rupees(5000),
              familyMemberId: 'family-a2',
            ),
          ],
        );

        expect(
          lineFor(withOneMember, ownerA).closingPosition,
          lineFor(withAnother, ownerA).closingPosition,
        );
        expect(
          lineFor(withOneMember, ownerB).closingPosition,
          lineFor(withAnother, ownerB).closingPosition,
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§41, §42 · payment and overpayment', () {
    test(
      'calculating a position writes nothing; paying it is a separate act',
      () {
        final before = settleJune(
          cumulativeBefore: Money.zero,
          cumulativeAtEnd: rupees(150000),
        );
        expect(lineFor(before, ownerA).closingPosition, rupees(75000));

        // The payment happens through OA-1's ledger, as a movement. Only then does the
        // position change — nothing about calculating it created a payment.
        final after = settleJune(
          cumulativeBefore: Money.zero,
          cumulativeAtEnd: rupees(150000),
          movements: [
            movement(
              ownerId: ownerA,
              type: OwnerMovementType.settlementPaid,
              direction: OwnerLedgerDirection.debit,
              amount: rupees(50000),
            ),
          ],
        );
        expect(lineFor(after, ownerA).closingPosition, rupees(25000));
      },
    );

    test(
      'overpayment produces a negative position rather than a clamped zero',
      () {
        final outcome = settleJune(
          cumulativeBefore: Money.zero,
          cumulativeAtEnd: rupees(40000),
          movements: [
            movement(
              ownerId: ownerA,
              type: OwnerMovementType.settlementPaid,
              direction: OwnerLedgerDirection.debit,
              amount: rupees(30000),
            ),
          ],
        );
        expect(
          lineFor(outcome, ownerA).closingPosition,
          -rupees(10000),
          reason:
              'position ₹20,000 less a ₹30,000 payment is −₹10,000: the owner has '
              'overdrawn, and saying zero would hide it (§2, §42)',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group(
    '§43 · the reconciliation that holds, and the one that must not be expected',
    () {
      test(
        'cumulative entitlements plus the remainder are cumulative Operating Profit',
        () {
          final outcome =
              settleJune(
                    cumulativeBefore: rupees(50000),
                    cumulativeAtEnd: Money.fromPaise(15000001),
                  )
                  as OwnerSettlementComputed;

          expect(outcome.entitlementReconciles, isTrue);
          expect(
            outcome.totalEntitlementAllocated + outcome.undistributedRemainder,
            outcome.cumulativeOperatingProfit,
          );
          expect(outcome.undistributedRemainder.paise, 1);
        },
      );

      test(
        'closing positions do NOT sum to Operating Profit, and that is correct',
        () {
          // Prior openings and owner movements legitimately change that relationship. A
          // reconciliation expecting it would make a correct statement look broken (§43).
          final outcome =
              settleJune(
                    cumulativeBefore: Money.zero,
                    cumulativeAtEnd: rupees(100000),
                    movements: [
                      movement(
                        ownerId: ownerA,
                        type: OwnerMovementType.openingBalance,
                        direction: OwnerLedgerDirection.credit,
                        amount: rupees(30000),
                        on: d(2026, 1, 1),
                      ),
                      movement(
                        ownerId: ownerA,
                        type: OwnerMovementType.withdrawal,
                        direction: OwnerLedgerDirection.debit,
                        amount: rupees(20000),
                      ),
                    ],
                  )
                  as OwnerSettlementComputed;

          final closings = Money.sum(
            outcome.lines.map((l) => l.closingPosition),
          );
          expect(closings, rupees(110000));
          expect(outcome.operatingProfit, rupees(100000));
          expect(
            closings == outcome.operatingProfit,
            isFalse,
            reason:
                'the difference is exactly the opening credit less the withdrawal',
          );
          expect(closings - outcome.operatingProfit, rupees(10000));
          expect(outcome.linesReconcile, isTrue);
        },
      );
    },
  );

  // ═══════════════════════════════════════════════════════════════════════════
  group('§21, §22, §18 · when a settlement is refused', () {
    test('a period beginning before inception is refused, never assumed', () {
      final outcome = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
        inception: d(2026, 7, 1),
      );
      expect(
        (outcome as OwnerSettlementRefused).refusal,
        OwnerSettlementRefusal.beforeInception,
      );
      expect(outcome.detail, contains('2026-07-01'));
    });

    test(
      'incomplete canonical ledger coverage refuses before anything is added up',
      () {
        final outcome = settleJune(
          cumulativeBefore: Money.zero,
          cumulativeAtEnd: rupees(100000),
          coverage: false,
        );
        expect(
          (outcome as OwnerSettlementRefused).refusal,
          OwnerSettlementRefusal.ledgerCoverageIncomplete,
        );
      },
    );

    test('an ownership vector that is not the V1 pair refuses', () {
      final sixtyForty = OwnershipShareSet([
        OwnershipShare(
          id: 'a',
          ownerId: ownerA,
          shareBasisPoints: 6000,
          effectiveFrom: d(2026, 1, 1),
        ),
        OwnershipShare(
          id: 'b',
          ownerId: ownerB,
          shareBasisPoints: 4000,
          effectiveFrom: d(2026, 1, 1),
        ),
      ]).resolveV1For(d(2026, 6, 1), d(2026, 6, 30));

      final outcome = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
        ownership: sixtyForty,
      );
      expect(
        (outcome as OwnerSettlementRefused).refusal,
        OwnerSettlementRefusal.ownershipUnavailable,
      );
    });

    test('the period is a calendar month, and is carried as YYYY-MM', () {
      final outcome =
          settleJune(
                cumulativeBefore: Money.zero,
                cumulativeAtEnd: rupees(100000),
              )
              as OwnerSettlementComputed;
      expect(outcome.periodKey, '2026-06');
      expect(outcome.periodStart, d(2026, 6, 1));
      expect(outcome.periodEnd, d(2026, 6, 30));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§25 · a per-property breakdown never moves the consolidated entitlement', () {
    test('two properties with odd profits still split the consolidated figure', () {
      // 5000001 + 5000001 = 10000002, which halves exactly. Rounding each property
      // separately would give 2500000 + 2500000 = 5000000 per owner and strand two
      // paise — the failure §25 forbids.
      final outcome =
          settleJune(
                cumulativeBefore: Money.zero,
                cumulativeAtEnd: Money.fromPaise(10000002),
                byUnit: {
                  'ccr': Money.fromPaise(5000001),
                  'hki': Money.fromPaise(5000001),
                },
              )
              as OwnerSettlementComputed;

      expect(outcome.lines.first.profitEntitlement.paise, 5000001);
      expect(outcome.undistributedRemainder, Money.zero);

      final perUnitRounded = outcome.operatingProfitByBusinessUnit.values
          .map((m) => m.paise ~/ 2)
          .fold(0, (a, b) => a + b);
      expect(
        perUnitRounded,
        5000000,
        reason:
            'independently rounding each property loses two paise — stated here so the '
            'difference is a recorded fact rather than a discovery',
      );
      expect(
        outcome.lines.first.profitEntitlement.paise,
        isNot(perUnitRounded),
      );
    });

    test('the breakdown is carried but is not an input to any entitlement', () {
      final withBreakdown = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
        byUnit: {'ccr': rupees(70000), 'hki': rupees(30000)},
      );
      final without = settleJune(
        cumulativeBefore: Money.zero,
        cumulativeAtEnd: rupees(100000),
      );
      expect(
        lineFor(withBreakdown, ownerA).closingPosition,
        lineFor(without, ownerA).closingPosition,
      );
      expect(
        (withBreakdown as OwnerSettlementComputed)
            .operatingProfitByBusinessUnit
            .keys,
        ['ccr', 'hki'],
      );
    });
  });
}
