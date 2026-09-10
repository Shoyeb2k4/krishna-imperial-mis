/// Approved family members, and the mapping that attributes their consumption to an owner.
///
/// Phase 5 OA-1. Pure domain.
///
/// ## What a family member is, and what it is not
///
/// A family member is a **business subject**: somebody who may eat at Crystal Canopy on
/// the house and whose bill is debited to the owner they are linked to (OA-D7). They are
/// deliberately *not*:
///
/// * an owner — no profit share, ever;
/// * an account — there is no family current account, and a withdrawal collected by a
///   son debits the **owner**, not the son;
/// * an MIS user — this model carries no `userId` and creates no login (§7). If a family
///   member ever needs one, that is an explicit optional relation somebody decides on,
///   never an inference from the fact that a person exists in this table.
///
/// ## Reassignment must not rewrite history, and the mapping alone cannot promise that
///
/// This file resolves *"who does this person belong to today"*. That is a lookup at the
/// moment of entry. The guarantee that a later reassignment does not restate accepted
/// history lives one layer over: an accepted ledger movement **snapshots** the resolved
/// owner id onto itself, so reporting never re-joins through here (see `owner_ledger.dart`
/// and OA-1 §12).
///
/// This is exactly the discipline that keeps a revenue component explainable after its tax
/// rule is superseded (D-080, D-122). The mapping is reference data; the attribution is a
/// recorded fact.
library;

import 'package:meta/meta.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// A person who may consume against an owner's account.
///
/// The owner themselves is represented here too, as a self-member. That is deliberate:
/// it gives the NC entry surface exactly **one** kind of person-reference to offer and no
/// branch to get wrong, and it means the mapping resolves uniformly whether the diner was
/// the owner or their daughter.
@immutable
final class OwnerFamilyMember {
  const OwnerFamilyMember({
    required this.id,
    required this.orgId,
    required this.ownerId,
    required this.displayName,
    required this.effectiveFrom,
    this.relationshipLabel,
    this.isSelf = false,
    this.mayUseNc = true,
    this.effectiveTo,
    this.active = true,
  });

  final String id;
  final String orgId;

  /// The owner this person's consumption is attributed to, for this interval.
  final String ownerId;

  final String displayName;

  /// `spouse`, `son`, `daughter` — **a label, never a rule input.** Nothing in the
  /// system branches on it, and a test asserts as much: the moment a relationship label
  /// decided an amount it would become business logic that nobody configured.
  final String? relationshipLabel;

  /// True for the owner's own person-record.
  final bool isSelf;

  /// Whether this person is approved for non-chargeable consumption (§6).
  final bool mayUseNc;

  final BusinessDate effectiveFrom;

  /// Inclusive. Null is open-ended.
  final BusinessDate? effectiveTo;

  final bool active;

  bool appliesOn(BusinessDate date) =>
      active &&
      date >= effectiveFrom &&
      (effectiveTo == null || date <= effectiveTo!);

  @override
  bool operator ==(Object other) =>
      other is OwnerFamilyMember && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'OwnerFamilyMember($displayName → $ownerId'
      '${isSelf ? ', self' : ''}${mayUseNc ? '' : ', NC not permitted'})';
}

/// Why an owner could not be attributed to a person.
enum FamilyAttributionRefusal {
  /// No such person, or none active on that date.
  unknownPerson,

  /// The person exists but is not approved for non-chargeable consumption.
  notApprovedForNc,

  /// Two active links for one person on one date. Refused, never tiebroken — the same
  /// zero-or-exactly-one doctrine ownership and tax resolution both use (D-094).
  ambiguousMapping,

  /// The client named an owner, and it is not the one the mapping resolves to (§12).
  ///
  /// This is a **conflict of fact**, not a permission problem: somebody's screen showed
  /// one attribution and the canonical mapping says another, which is what D-114 refuses
  /// for a declared tax figure and refuses here for the same reason.
  declaredOwnerMismatch,
}

/// The outcome of asking who a consumption belongs to.
sealed class FamilyAttribution {
  const FamilyAttribution();
}

final class FamilyAttributed extends FamilyAttribution {
  const FamilyAttributed({required this.ownerId, required this.member});
  final String ownerId;
  final OwnerFamilyMember member;

  @override
  String toString() => 'FamilyAttributed(${member.displayName} → $ownerId)';
}

final class FamilyAttributionRefused extends FamilyAttribution {
  const FamilyAttributionRefused(this.refusal, {this.detail});
  final FamilyAttributionRefusal refusal;
  final String? detail;

  @override
  String toString() =>
      'FamilyAttributionRefused(${refusal.name}${detail ?? ''})';
}

/// The configured family links, and the rule for reading them.
@immutable
final class FamilyOwnerMapping {
  FamilyOwnerMapping(Iterable<OwnerFamilyMember> members)
    : members = List.unmodifiable(members);

  final List<OwnerFamilyMember> members;

  /// People who may be offered on an NC entry surface for [date], in display order.
  ///
  /// Only those approved for NC: offering somebody the form will refuse is a worse
  /// experience than not offering them, and it leaks that the person exists at all.
  List<OwnerFamilyMember> ncConsumersOn(BusinessDate date) => [
    for (final m in members)
      if (m.appliesOn(date) && m.mayUseNc) m,
  ]..sort((a, b) => a.displayName.compareTo(b.displayName));

  /// Resolves the owner a person's consumption is attributed to on [date].
  ///
  /// [declaredOwnerId] is what the client displayed to the operator, and is **compared,
  /// never used**. Where the two disagree the entry is refused rather than silently
  /// re-attributed, because the operator approved a statement about one owner and
  /// recording it against another would make the record say something nobody agreed to
  /// (§12, and D-114's contract for declared tax figures).
  FamilyAttribution attribute(
    String memberId,
    BusinessDate date, {
    String? declaredOwnerId,
    bool requireNcApproval = true,
  }) {
    final matching = [
      for (final m in members)
        if (m.id == memberId && m.appliesOn(date)) m,
    ];

    if (matching.isEmpty) {
      return FamilyAttributionRefused(
        FamilyAttributionRefusal.unknownPerson,
        detail: ' on ${date.iso}',
      );
    }
    if (matching.length > 1) {
      return FamilyAttributionRefused(
        FamilyAttributionRefusal.ambiguousMapping,
        detail: ' for $memberId on ${date.iso}',
      );
    }

    final member = matching.single;
    if (requireNcApproval && !member.mayUseNc) {
      return FamilyAttributionRefused(
        FamilyAttributionRefusal.notApprovedForNc,
        detail: ' (${member.displayName})',
      );
    }
    if (declaredOwnerId != null && declaredOwnerId != member.ownerId) {
      return FamilyAttributionRefused(
        FamilyAttributionRefusal.declaredOwnerMismatch,
        detail:
            ' (${member.displayName} is linked to ${member.ownerId}, '
            'not $declaredOwnerId)',
      );
    }

    return FamilyAttributed(ownerId: member.ownerId, member: member);
  }
}
