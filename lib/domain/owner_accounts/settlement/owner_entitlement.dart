/// The V1 profit entitlement split, and the paisa that cannot yet be divided.
///
/// Phase 5 OA-2. Pure domain: no Drift, no Supabase, no Flutter, no `double`.
///
/// ## Why this is cumulative rather than per month
///
/// Splitting each month's Operating Profit in half strands a paisa **every month it is
/// odd**, and those paise are gone for good — they belong to neither owner and appear
/// nowhere. Over a year that is a small, permanent, unexplainable discrepancy, and the
/// only place it could ever be noticed is a reconciliation nobody runs.
///
/// So entitlement is computed **cumulatively from settlement inception**, and a period's
/// entitlement is the difference between two cumulative figures (§8, §38):
///
/// ```
///         month 1 profit = 1 paisa      cumulative 1   -> each 0, remainder 1
///         month 2 profit = 1 paisa      cumulative 2   -> each 1, remainder 0
///
///         month 1 entitlement = 0 - 0 = 0
///         month 2 entitlement = 1 - 0 = 1
///         allocated in total  = 1 each = 2 paise, exactly
/// ```
///
/// The naive monthly floor allocates 0 and 0 and loses both paise. The remainder is never
/// *given* to anybody: it sits undistributed at organisation level until later profit
/// makes it divisible, and then it resolves on its own.
///
/// ## Why there is no owner bias, in either direction
///
/// The split is Dart's truncating division, which rounds **toward zero** — so a positive
/// odd amount leaves a positive remainder and a negative odd amount leaves a negative one,
/// and neither owner is ever the one who happens to get the extra paisa. That symmetry is
/// the whole of §8's "no owner bias" requirement, and it is asserted rather than assumed.
library;

import 'package:meta/meta.dart';

import 'package:krishna_mis/domain/owner_accounts/owner.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// One cumulative split of Operating Profit under the fixed V1 vector.
///
/// Holds no owner identity, deliberately: under V1 both owners receive the same figure
/// (D-204), and attaching a name to it would invite a future reader to look for the
/// asymmetry that does not exist.
@immutable
final class CumulativeEntitlement {
  const CumulativeEntitlement._({
    required this.cumulativeOperatingProfit,
    required this.perOwner,
    required this.undistributedRemainder,
  });

  /// Splits a cumulative Operating Profit between the two V1 owners.
  ///
  /// [cumulativeOperatingProfit] is the canonical figure from `domain/finance` — a loss
  /// is negative and is **shared**, never clamped to zero (§7).
  factory CumulativeEntitlement.of(Money cumulativeOperatingProfit) {
    // Truncating division: toward zero, so the remainder carries the sign of the profit
    // and neither owner is favoured in either direction.
    final each = cumulativeOperatingProfit.paise ~/ v1OwnerCount;
    return CumulativeEntitlement._(
      cumulativeOperatingProfit: cumulativeOperatingProfit,
      perOwner: Money.fromPaise(each),
      undistributedRemainder: Money.fromPaise(
        cumulativeOperatingProfit.paise - each * v1OwnerCount,
      ),
    );
  }

  /// The cumulative canonical Operating Profit this splits.
  final Money cumulativeOperatingProfit;

  /// Each owner's cumulative entitlement. The same figure for both, under V1.
  final Money perOwner;

  /// The part that cannot yet be divided equally.
  ///
  /// **Never allocated to an owner and never persisted as a ledger movement** (§9). It is
  /// an organisation-level fact about the arithmetic, and it resolves by itself the moment
  /// cumulative profit becomes divisible.
  final Money undistributedRemainder;

  /// Everything allocated to owners, together.
  Money get totalAllocated => perOwner * v1OwnerCount;

  /// §9's invariant: the two entitlements and the remainder are the profit, exactly.
  ///
  /// Checked rather than trusted, because it is the one property that makes the remainder
  /// an honest figure rather than a rounding excuse.
  bool get reconciles =>
      totalAllocated + undistributedRemainder == cumulativeOperatingProfit;

  /// The remainder is bounded to the minimum unavoidable amount: one paisa, at most, in
  /// the direction of the profit (§9).
  bool get remainderIsMinimal =>
      undistributedRemainder.absolute.paise < v1OwnerCount;

  @override
  bool operator ==(Object other) =>
      other is CumulativeEntitlement &&
      other.cumulativeOperatingProfit == cumulativeOperatingProfit;

  @override
  int get hashCode => cumulativeOperatingProfit.hashCode;

  @override
  String toString() =>
      'CumulativeEntitlement(${cumulativeOperatingProfit.paise}p -> '
      '${perOwner.paise}p each, remainder ${undistributedRemainder.paise}p)';
}

/// One owner's entitlement **for a period**, as the difference of two cumulative figures.
///
/// This is the only sanctioned way to obtain a period entitlement. Halving a single
/// period's profit is the thing §38 forbids, and a named function is harder to reach past
/// than a comment.
@immutable
final class PeriodEntitlement {
  const PeriodEntitlement({
    required this.cumulativeBefore,
    required this.cumulativeAtEnd,
  });

  /// Cumulative entitlement immediately **before** the period begins.
  final CumulativeEntitlement cumulativeBefore;

  /// Cumulative entitlement at the period's end.
  final CumulativeEntitlement cumulativeAtEnd;

  /// Each owner's entitlement arising in the period. Signed: a loss reduces it.
  Money get perOwner => cumulativeAtEnd.perOwner - cumulativeBefore.perOwner;

  /// The period's own canonical Operating Profit, as the two cumulative figures imply it.
  Money get operatingProfit =>
      cumulativeAtEnd.cumulativeOperatingProfit -
      cumulativeBefore.cumulativeOperatingProfit;

  /// What is still undivided at the end of the period.
  Money get undistributedRemainder => cumulativeAtEnd.undistributedRemainder;

  @override
  String toString() =>
      'PeriodEntitlement(${perOwner.paise}p each on ${operatingProfit.paise}p)';
}
