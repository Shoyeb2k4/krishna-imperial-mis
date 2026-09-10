/// The Owner Settlement calculation: an owner's position for a month, from canonical
/// history.
///
/// Phase 5 OA-2. Pure domain: no Drift, no Supabase, no Flutter, no `double`.
///
/// ## What this is, and what it is emphatically not
///
/// It computes an **economic entitlement position** — what the business owes an owner, or
/// what an owner has overdrawn against the business — from canonical Operating Profit and
/// canonical owner movements. It says nothing about cash (§15): a position of ₹5,00,000
/// does not claim ₹5,00,000 is sitting in a bank account, and there is no treasury model
/// anywhere in this file.
///
/// It also **does not compute Operating Profit**. `Net Sales − Expenses` lives once, in
/// `domain/finance` (D-020), and this consumes the result. A structural guard fails the
/// build if this directory ever recreates the P&L formula (§33).
///
/// ## Sign convention (§2), which is binding and is not to be reversed
///
/// ```
///         positive position  ->  the business owes the owner
///         negative position  ->  the owner has drawn more than their entitlement
/// ```
///
/// ## The formula (§3)
///
/// ```
///         closing = opening
///                 + profit entitlement for the period      (signed; a loss reduces it)
///                 - withdrawals
///                 - non-chargeable consumption
///                 - settlement paid
///                 + manual adjustment credits
///                 - manual adjustment debits
/// ```
///
/// which is one statement in code, because every movement already knows its own direction:
/// the position is the cumulative entitlement plus the signed effect of every canonical
/// movement up to the cutoff. Written that way, a movement type added later cannot be
/// forgotten by an arm of a `switch`.
///
/// ## Nothing here is stored (OA-D2, §26)
///
/// There is no balance column and no settlement table. The opening position for a month is
/// **derived from history before it** (§23), so a correction anywhere in the past
/// recomputes everything downstream on its own and no stored figure can drift from the
/// facts. That is D-190's argument, and it is the reason corrections (§27) and voids (§28)
/// need no propagation machinery at all.
library;

import 'package:meta/meta.dart';

import 'package:krishna_mis/domain/owner_accounts/owner.dart';
import 'package:krishna_mis/domain/owner_accounts/owner_ledger.dart';
import 'package:krishna_mis/domain/owner_accounts/settlement/owner_entitlement.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// Why a settlement could not be produced.
///
/// Structured, and each names a different thing to do about it — the discipline D-113
/// established for revenue. A settlement that refused with one generic reason would send
/// somebody to look at the configuration when the real answer is "this device has not
/// synchronised".
enum OwnerSettlementRefusal {
  /// The period begins before settlement inception (§22).
  ///
  /// Inception is a production input nobody has supplied, and is never guessed — in
  /// particular it is **not** assumed to be 2026-04-01 because the tax model uses that
  /// date.
  beforeInception,

  /// The ownership vector could not be resolved, or is not the V1 `[5000, 5000]` (D-204).
  ownershipUnavailable,

  /// The canonical Operating Profit for a required range could not be established —
  /// a side unavailable, coverage not downloaded, or authority missing (D-163, D-183).
  operatingProfitUnavailable,

  /// This device does not hold complete canonical owner-ledger history for the range.
  ///
  /// The refusal §18 exists for. A settlement over partial local history reconciles
  /// against itself perfectly and is wrong by exactly the movements it never saw.
  ledgerCoverageIncomplete,
}

/// The outcome of a settlement calculation.
sealed class OwnerSettlementOutcome {
  const OwnerSettlementOutcome();
}

/// It could not be produced, and here is which condition failed.
final class OwnerSettlementRefused extends OwnerSettlementOutcome {
  const OwnerSettlementRefused(this.refusal, {this.detail});

  final OwnerSettlementRefusal refusal;

  /// A specific for the sentence a person eventually reads. Never a code, never an
  /// exception name.
  final String? detail;

  @override
  String toString() => 'OwnerSettlementRefused(${refusal.name}${detail ?? ''})';
}

/// One owner's settlement line for one period (§24).
///
/// Every field is exact minor units and every field is signed where it can legitimately be
/// negative. No display strings: formatting belongs to whatever renders this, and OA-2
/// renders nothing (§45).
@immutable
final class OwnerSettlementLine {
  const OwnerSettlementLine({
    required this.ownerId,
    required this.openingPosition,
    required this.profitEntitlement,
    required this.withdrawals,
    required this.ncConsumption,
    required this.settlementPaid,
    required this.adjustmentCredits,
    required this.adjustmentDebits,
    required this.closingPosition,
  });

  final String ownerId;

  /// Derived from every canonical fact before the period (§23), never read from a stored
  /// closing balance.
  final Money openingPosition;

  /// This period's share of canonical Operating Profit. Signed — a loss reduces it (§7).
  final Money profitEntitlement;

  /// Positive magnitudes; each is subtracted by the formula rather than carrying a sign,
  /// so a reader cannot mistake "withdrawals: -20,000" for a refund.
  final Money withdrawals;
  final Money ncConsumption;
  final Money settlementPaid;

  final Money adjustmentCredits;
  final Money adjustmentDebits;

  /// Positive: the business owes the owner. Negative: the owner has overdrawn (§2, §42).
  final Money closingPosition;

  /// The movements' net effect on the position during the period.
  Money get netMovements =>
      adjustmentCredits -
      withdrawals -
      ncConsumption -
      settlementPaid -
      adjustmentDebits;

  /// §3, restated as a check rather than as a comment: the line adds up.
  bool get reconciles =>
      openingPosition + profitEntitlement + netMovements == closingPosition;

  @override
  String toString() =>
      'OwnerSettlementLine($ownerId, opening ${openingPosition.paise}p, '
      'closing ${closingPosition.paise}p)';
}

/// The organisation-level settlement statement for one period.
final class OwnerSettlementComputed extends OwnerSettlementOutcome {
  const OwnerSettlementComputed({
    required this.periodKey,
    required this.periodStart,
    required this.periodEnd,
    required this.operatingProfit,
    required this.cumulativeOperatingProfit,
    required this.totalEntitlementAllocated,
    required this.undistributedRemainder,
    required this.lines,
    required this.operatingProfitByBusinessUnit,
  });

  /// `YYYY-MM` — the canonical monthly settlement period (§21), the same grain
  /// `pnl_period_key` already uses everywhere else.
  final String periodKey;
  final BusinessDate periodStart;
  final BusinessDate periodEnd;

  /// This period's canonical **consolidated** Operating Profit (§5). One figure for the
  /// organisation, never two independently rounded per-property figures added together.
  final Money operatingProfit;

  /// Cumulative from inception through the period end — the basis the entitlement split
  /// actually uses (§8).
  final Money cumulativeOperatingProfit;

  /// What the owners were allocated cumulatively, together.
  final Money totalEntitlementAllocated;

  /// The organisation-level paisa that cannot yet be divided (§9).
  final Money undistributedRemainder;

  /// One per owner, ordered by owner id.
  final List<OwnerSettlementLine> lines;

  /// **Informational only** (§25). Per-property Operating Profit for a breakdown a
  /// surface may show. Entitlement is never computed from these — rounding each property
  /// separately and adding would not equal the consolidated split.
  final Map<String, Money> operatingProfitByBusinessUnit;

  /// §43's reconciliation: cumulative entitlements plus the remainder are cumulative
  /// Operating Profit, exactly.
  ///
  /// Deliberately **not** `A closing + B closing == operating profit`: prior openings and
  /// owner movements legitimately change that relationship, and expecting it would make a
  /// correct statement look broken.
  bool get entitlementReconciles =>
      totalEntitlementAllocated + undistributedRemainder ==
      cumulativeOperatingProfit;

  /// Every line adds up on its own terms.
  bool get linesReconcile => lines.every((l) => l.reconciles);

  @override
  String toString() =>
      'OwnerSettlementComputed($periodKey, ${lines.length} owners, '
      'OP ${operatingProfit.paise}p)';
}

/// The canonical Operating Profit figures a settlement needs, supplied by the caller.
///
/// **Two cumulative figures, not a period figure**, because that is what the cumulative
/// entitlement rule consumes (§38). The caller obtains both from the existing canonical
/// P&L — one range from inception to the day before the period, one from inception to the
/// period end — so this domain never sees a revenue or an expense.
@immutable
final class CanonicalOperatingProfit {
  const CanonicalOperatingProfit({
    required this.cumulativeBeforePeriod,
    required this.cumulativeAtPeriodEnd,
    this.byBusinessUnitForPeriod = const {},
  });

  final Money cumulativeBeforePeriod;
  final Money cumulativeAtPeriodEnd;

  /// Informational per-property breakdown **of the period** (§25).
  final Map<String, Money> byBusinessUnitForPeriod;
}

/// The Owner Settlement calculator.
///
/// Stateless and pure. It is handed canonical facts and returns a result; it reads no
/// database, consults no clock, and holds nothing between calls.
abstract final class OwnerSettlement {
  /// Computes one month's settlement for the V1 two-owner vector.
  ///
  /// [canonicalMovements] must be **every** canonical owner movement from inception
  /// through [periodEnd] — the calculator derives the opening position from the ones
  /// before the period (§23) rather than trusting a stored balance. Non-canonical
  /// entries are filtered here as well as by the caller, because §17 is a rule about the
  /// figure rather than about who remembered to apply it.
  static OwnerSettlementOutcome compute({
    required String periodKey,
    required BusinessDate periodStart,
    required BusinessDate periodEnd,
    required BusinessDate inception,
    required OwnershipResolution ownership,
    required CanonicalOperatingProfit operatingProfit,
    required List<OwnerLedgerEntry> canonicalMovements,
    bool ledgerCoverageComplete = false,
  }) {
    if (periodStart < inception) {
      return OwnerSettlementRefused(
        OwnerSettlementRefusal.beforeInception,
        detail:
            ' ($periodKey begins before settlement inception ${inception.iso})',
      );
    }

    // Before anything is added up. A settlement over partial local history is wrong by
    // exactly the movements this device never saw, and it reconciles against itself
    // perfectly while being wrong (§18).
    if (!ledgerCoverageComplete) {
      return const OwnerSettlementRefused(
        OwnerSettlementRefusal.ledgerCoverageIncomplete,
        detail:
            ' (this device has not established complete canonical owner-ledger history)',
      );
    }

    if (ownership is! OwnershipResolved) {
      return OwnerSettlementRefused(
        OwnerSettlementRefusal.ownershipUnavailable,
        detail: ' ($ownership)',
      );
    }

    final entitlement = PeriodEntitlement(
      cumulativeBefore: CumulativeEntitlement.of(
        operatingProfit.cumulativeBeforePeriod,
      ),
      cumulativeAtEnd: CumulativeEntitlement.of(
        operatingProfit.cumulativeAtPeriodEnd,
      ),
    );

    final canonical = [
      for (final entry in canonicalMovements)
        if (entry.isCanonical) entry,
    ];

    final lines = <OwnerSettlementLine>[];
    for (final share in ownership.shares) {
      final ownerId = share.ownerId;

      final before = [
        for (final e in canonical)
          if (e.ownerId == ownerId && e.businessDate < periodStart) e,
      ];
      final inPeriod = [
        for (final e in canonical)
          if (e.ownerId == ownerId &&
              e.businessDate >= periodStart &&
              e.businessDate <= periodEnd)
            e,
      ];

      // The opening position is history, recomputed: cumulative entitlement earned before
      // the period, plus the signed effect of every movement before it (§23).
      final opening =
          entitlement.cumulativeBefore.perOwner +
          Money.sum(before.map((e) => e.signedEffect));

      final totals = OwnerLedgerTotals.of(ownerId, inPeriod);
      final adjustments = _adjustmentSplit(inPeriod);

      lines.add(
        OwnerSettlementLine(
          ownerId: ownerId,
          openingPosition: opening,
          profitEntitlement: entitlement.perOwner,
          withdrawals: totals.withdrawals,
          ncConsumption: totals.ncConsumption,
          settlementPaid: totals.settlementPaid,
          adjustmentCredits: adjustments.credits,
          adjustmentDebits: adjustments.debits,
          closingPosition:
              opening +
              entitlement.perOwner +
              Money.sum(inPeriod.map((e) => e.signedEffect)),
        ),
      );
    }

    lines.sort((a, b) => a.ownerId.compareTo(b.ownerId));

    return OwnerSettlementComputed(
      periodKey: periodKey,
      periodStart: periodStart,
      periodEnd: periodEnd,
      operatingProfit: entitlement.operatingProfit,
      cumulativeOperatingProfit: operatingProfit.cumulativeAtPeriodEnd,
      totalEntitlementAllocated: entitlement.cumulativeAtEnd.totalAllocated,
      undistributedRemainder: entitlement.undistributedRemainder,
      lines: List.unmodifiable(lines),
      operatingProfitByBusinessUnit: Map.unmodifiable(
        operatingProfit.byBusinessUnitForPeriod,
      ),
    );
  }

  /// Manual adjustments, split by the direction OA-1 stores explicitly (§14).
  ///
  /// Never inferred from a signed amount: OA-1 models the direction, and re-deriving it
  /// from arithmetic would be a second answer to a question already answered.
  static ({Money credits, Money debits}) _adjustmentSplit(
    List<OwnerLedgerEntry> entries,
  ) {
    var credits = Money.zero;
    var debits = Money.zero;
    for (final entry in entries) {
      if (entry.movementType != OwnerMovementType.manualAdjustment) continue;
      switch (entry.direction) {
        case OwnerLedgerDirection.credit:
          credits += entry.amount;
        case OwnerLedgerDirection.debit:
          debits += entry.amount;
      }
    }
    return (credits: credits, debits: debits);
  }
}
