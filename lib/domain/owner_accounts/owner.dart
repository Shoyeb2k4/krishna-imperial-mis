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

/// **The V1 ownership model: exactly two owners, 5000 basis points each.**
///
/// Ruled by the project lead on 2026-09-10 (OA-D12, D-204). V1 does not implement
/// variable ownership: the authoritative configured vector for any settlement period must
/// resolve to exactly `[5000, 5000]`, and 60/40, 70/30, a third owner, a single owner
/// holding everything, a partial total and a total above 100% are all **refused** rather
/// than allocated.
///
/// It is a business rule and not a schema limitation, which is why it lives here as a
/// named constant pair and as [OwnershipShareSet.resolveV1For] rather than as a narrowed
/// column. The date-effective schema is unchanged and still expresses any ratio; an
/// authorised future 60/40 lifts this rule deliberately, in one place, with a decision
/// behind it — it does not require a migration of history.
const int v1OwnerCount = 2;

/// Each V1 owner's share. Half of [totalOwnershipBasisPoints], stated rather than
/// computed, so a future change is a change to a value somebody chose.
const int v1ShareBasisPoints = 5000;

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

  /// **V1:** the resolved vector does not hold exactly two owners (D-204).
  ///
  /// Covers both directions — one owner missing, and a third arriving — because both
  /// mean the same thing to the person reading it: the configured ownership is not the
  /// two-owner model V1 implements, and somebody has to look at the configuration
  /// before a settlement can be produced.
  notExactlyTwoOwners,

  /// **V1:** an owner holds a share other than 5000 basis points (D-204).
  ///
  /// Distinct from [sharesDoNotTotalOneHundredPercent] on purpose: 60/40 totals exactly
  /// 10000 and is still refused, so a refusal that only said "the shares do not add up"
  /// would be false as well as unhelpful.
  shareIsNotHalf,

  /// **V1:** a resolved share belongs to an owner who is not active (D-204).
  ///
  /// Only checked when the caller supplies the active owner ids — the share set alone
  /// does not know which owners are archived, and inferring it would be guessing.
  shareBelongsToInactiveOwner,
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

  /// Resolves the range **and** requires it to be the V1 50:50 vector (D-204).
  ///
  /// This is the call a settlement makes. [resolveFor] stays the general date-effective
  /// rule — it is what makes historical records readable, and history legitimately
  /// contains ratios V1 no longer configures — and this adds the V1 business ruling on
  /// top of it, in one place, so lifting the ruling later is one deliberate change
  /// rather than an audit of every caller.
  ///
  /// Refuses, in this order and for these separate reasons:
  ///
  /// * everything [resolveFor] refuses — nothing configured, overlapping shares, a
  ///   ratio that moves inside the range, a total that is not 10000;
  /// * a vector that is not exactly two owners — one missing, or a third arriving;
  /// * any share that is not exactly 5000 basis points, **including one that totals
  ///   10000**, which is the case a total-only check cannot see;
  /// * a share belonging to an owner the caller says is not active, when it says.
  ///
  /// [activeOwnerIds] is optional because the share set does not know the owner masters.
  /// A caller that does know them should pass them: the ruling says *two active owners*,
  /// and an open share left behind on an archived owner is exactly the configuration
  /// that would otherwise satisfy a count.
  OwnershipResolution resolveV1For(
    BusinessDate from,
    BusinessDate to, {
    Set<String>? activeOwnerIds,
  }) {
    final general = resolveFor(from, to);
    if (general is! OwnershipResolved) return general;

    final shares = general.shares;

    if (shares.length != v1OwnerCount) {
      return OwnershipRefused(
        OwnershipRefusal.notExactlyTwoOwners,
        detail:
            ' (${shares.length} of $v1OwnerCount on ${from.iso}: '
            '${shares.map((s) => s.ownerId).join(', ')})',
      );
    }

    for (final share in shares) {
      if (share.shareBasisPoints != v1ShareBasisPoints) {
        return OwnershipRefused(
          OwnershipRefusal.shareIsNotHalf,
          detail:
              ' (${share.ownerId} holds ${share.shareBasisPoints} bp, '
              'not $v1ShareBasisPoints, on ${from.iso})',
        );
      }
    }

    if (activeOwnerIds != null) {
      for (final share in shares) {
        if (!activeOwnerIds.contains(share.ownerId)) {
          return OwnershipRefused(
            OwnershipRefusal.shareBelongsToInactiveOwner,
            detail: ' (${share.ownerId} on ${from.iso})',
          );
        }
      }
    }

    return general;
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
