/// Owners, and the effective-dated shares by which profit is allocated between them.
///
/// Phase 5 OA-1. Pure domain: no Drift, no Supabase, no Flutter, no `double`.
///
/// ## An owner is not a user, and this file cannot confuse them
///
/// [Owner] carries no `userId` and no login. An owner is a **business subject** — the
/// person profit is allocated to — and whether they happen to hold an MIS account is a
/// separate, optional fact that nothing here depends on (OA-D7, §3). Making `owner_id`
/// and `user_id` the same value would tie a financial entitlement to an authentication
/// record, so that provisioning somebody a login would grant them a share of the
/// business, and deactivating one would orphan the other.
///
/// ## Shares are a fact about a period, not a column on an owner
///
/// A share lives in [OwnershipShare] with its own effective dates, because putting
/// `share_basis_points` on the owner would make every historical settlement depend on
/// today's value — so changing a ratio in 2027 would silently restate every 2026
/// statement. That is precisely the harm the date-effective tax model exists to prevent
/// (D-017, D-080), applied to ownership.
///
/// ## Basis points, because the project already speaks them
///
/// 50% is `5000`, and a valid set totals exactly `10000`. Integers throughout: a `double`
/// share of 0.5 is exact today and 1/3 is not, and there is no version of this arithmetic
/// where a floating-point share is safe (OA-D1, `CLAUDE.md` money constraints).
library;

import 'package:meta/meta.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// One hundred percent, in basis points. A valid share set totals exactly this.
const int totalOwnershipBasisPoints = 10000;

/// A business owner: someone profit is allocated to.
@immutable
final class Owner {
  const Owner({
    required this.id,
    required this.orgId,
    required this.code,
    required this.displayName,
    this.active = true,
    this.archivedAt,
  });

  /// Client-generated UUID (D-008). Never a user id, never a name (§3).
  final String id;
  final String orgId;

  /// Immutable once created, like every other master's code (D-035). History and share
  /// records key on the id; the code is what a human recognises across environments.
  final String code;

  /// Renameable under D-038's cosmetic-rename rule: a spelling correction preserves
  /// meaning. Re-purposing one owner record into a different person is prohibited —
  /// archive and create anew.
  final String displayName;

  final bool active;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;

  @override
  bool operator ==(Object other) => other is Owner && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Owner($code, $displayName)';
}

/// One owner's profit share over one interval.
///
/// [effectiveTo] is **inclusive** and null means open-ended, matching how the tax rules
/// and the premises statuses already express a date-effective interval.
@immutable
final class OwnershipShare {
  const OwnershipShare({
    required this.id,
    required this.ownerId,
    required this.shareBasisPoints,
    required this.effectiveFrom,
    this.effectiveTo,
  });

  final String id;
  final String ownerId;

  /// 1..10000. Zero is deliberately not a share: an owner entitled to nothing is not an
  /// owner for that period, and expressing it as `0 bp` would make them appear in an
  /// allocation that gives them nothing, which reads like a defect rather than a fact.
  final int shareBasisPoints;

  final BusinessDate effectiveFrom;

  /// Inclusive. Null is open-ended.
  final BusinessDate? effectiveTo;

  bool appliesOn(BusinessDate date) =>
      date >= effectiveFrom && (effectiveTo == null || date <= effectiveTo!);

  /// Whether this share covers every day of an inclusive range.
  bool coversWhole(BusinessDate from, BusinessDate to) =>
      effectiveFrom <= from && (effectiveTo == null || effectiveTo! >= to);

  @override
  String toString() =>
      'OwnershipShare($ownerId, $shareBasisPoints bp, '
      '${effectiveFrom.iso}..${effectiveTo?.iso ?? 'open'})';
}

// ── Mid-period change policy (OA-1 §5) ──────────────────────────────────────

/// Why an ownership share configuration was refused.
enum OwnershipRefusal {
  /// No share is configured for any owner on this date.
  noShareConfigured,

  /// The applicable shares do not total exactly 10000 basis points.
  ///
  /// Never normalised, never scaled to fit. A set that does not add up is a
  /// configuration defect somebody has to look at, and silently rescaling it would
  /// allocate profit by a ratio nobody approved.
  sharesDoNotTotalOneHundredPercent,

  /// Two share records for one owner apply on the same date.
  overlappingShares,

  /// The ratio changes part-way through the requested range (§5).
  ///
  /// Refused rather than apportioned. Splitting one month's entitlement by day would
  /// require assuming Operating Profit accrues evenly across the month, which is an
  /// assumption nobody can support and which no figure in this system establishes.
  ratioChangesWithinRange,

  /// An effective date that does not fall on a settlement-period boundary (§5).
  effectiveDateNotOnPeriodBoundary,
}

/// The outcome of resolving ownership for a range.
sealed class OwnershipResolution {
  const OwnershipResolution();
}

/// Exactly one share set applies to the whole range.
final class OwnershipResolved extends OwnershipResolution {
  const OwnershipResolved(this.shares);

  /// Ordered by owner id, so two identical resolutions are identical to anybody
  /// comparing them.
  final List<OwnershipShare> shares;

  int get totalBasisPoints =>
      shares.fold(0, (sum, s) => sum + s.shareBasisPoints);

  @override
  String toString() => 'OwnershipResolved(${shares.length} owners)';
}

/// It does not, and here is which condition failed.
final class OwnershipRefused extends OwnershipResolution {
  const OwnershipRefused(this.refusal, {this.detail});
  final OwnershipRefusal refusal;

  /// A human-readable specific — which date, which owner — for the message a person
  /// eventually reads. Never a code, never an exception name.
  final String? detail;

  @override
  String toString() => 'OwnershipRefused(${refusal.name}${detail ?? ''})';
}

/// The configured ownership shares, and the rule for reading them.
@immutable
final class OwnershipShareSet {
  OwnershipShareSet(Iterable<OwnershipShare> shares)
    : shares = List.unmodifiable(shares);

  final List<OwnershipShare> shares;

  /// The shares applying on one date, ordered by owner id.
  List<OwnershipShare> applicableOn(BusinessDate date) => [
    for (final s in shares)
      if (s.appliesOn(date)) s,
  ]..sort((a, b) => a.ownerId.compareTo(b.ownerId));

  /// Resolves the one share set that governs an entire inclusive range.
  ///
  /// **Zero-or-exactly-one, and ambiguity is refused rather than tiebroken.** This is
  /// deliberately the doctrine D-094 already establishes for tax rules, applied to
  /// ownership for the same reason: a ranking that picks between two applicable
  /// configurations would allocate profit by a rule nobody wrote down.
  OwnershipResolution resolveFor(BusinessDate from, BusinessDate to) {
    if (to < from) {
      return const OwnershipRefused(
        OwnershipRefusal.ratioChangesWithinRange,
        detail: ' (the range ends before it begins)',
      );
    }

    final atStart = applicableOn(from);
    if (atStart.isEmpty) {
      return OwnershipRefused(
        OwnershipRefusal.noShareConfigured,
        detail: ' on ${from.iso}',
      );
    }

    // One owner cannot hold two shares at once. Checked before the total, because a
    // duplicated owner can total 10000 by coincidence and still be a defect.
    final seen = <String>{};
    for (final share in atStart) {
      if (!seen.add(share.ownerId)) {
        return OwnershipRefused(
          OwnershipRefusal.overlappingShares,
          detail: ' for owner ${share.ownerId} on ${from.iso}',
        );
      }
    }

    // Every share must cover the whole range. A share that lapses or begins inside it
    // means the ratio moves part-way through, which §5 refuses rather than apportions.
    for (final share in atStart) {
      if (!share.coversWhole(from, to)) {
        return OwnershipRefused(
          OwnershipRefusal.ratioChangesWithinRange,
          detail:
              ' (${share.ownerId} changes between ${from.iso} and ${to.iso})',
        );
      }
    }

    // And nothing outside that set may begin inside the range either — a *third* owner
    // arriving mid-range moves the ratio just as surely as an existing one lapsing, and
    // checking only the start would miss it entirely.
    final startIds = {for (final s in atStart) s.ownerId};
    for (final share in shares) {
      if (startIds.contains(share.ownerId)) continue;
      if (share.effectiveFrom > from && share.effectiveFrom <= to) {
        return OwnershipRefused(
          OwnershipRefusal.ratioChangesWithinRange,
          detail:
              ' (${share.ownerId} begins on ${share.effectiveFrom.iso}, '
              'inside ${from.iso}..${to.iso})',
        );
      }
    }

    final total = atStart.fold(0, (sum, s) => sum + s.shareBasisPoints);
    if (total != totalOwnershipBasisPoints) {
      return OwnershipRefused(
        OwnershipRefusal.sharesDoNotTotalOneHundredPercent,
        detail: ' ($total of $totalOwnershipBasisPoints on ${from.iso})',
      );
    }

    return OwnershipResolved(atStart);
  }

  /// Whether a proposed effective date is legal under the §5 mid-period policy.
  ///
  /// **V1 rule, stated once and evaluated here:** an ownership change takes effect only
  /// at the **start of a settlement period**, which is the first day of a calendar month
  /// — the same grain `pnl_period_key` already uses everywhere else in the system. An
  /// end date, being inclusive, must therefore be the **last** day of a month, so that
  /// one share ends the day before the next begins with no gap and no overlap.
  ///
  /// Refusing is the honest answer, and it is also the cheap one: the alternative is
  /// apportioning a month's Operating Profit by day, which assumes profit accrues evenly
  /// through the month. Nothing in this system establishes that, and a settlement built
  /// on it would be exact arithmetic over an invented premise.
  static bool isLegalEffectiveFrom(BusinessDate date) => date.day == 1;

  /// The inclusive counterpart: the last day of a calendar month.
  static bool isLegalEffectiveTo(BusinessDate date) => date.addDays(1).day == 1;

  /// The next legal effective date at or after [date] — what an operator is offered when
  /// they propose a mid-month change, rather than a bare refusal.
  static BusinessDate nextLegalEffectiveFrom(BusinessDate date) {
    if (isLegalEffectiveFrom(date)) return date;
    final nextMonth = date.month == 12 ? 1 : date.month + 1;
    final year = date.month == 12 ? date.year + 1 : date.year;
    return BusinessDate.of(year, nextMonth, 1);
  }
}
