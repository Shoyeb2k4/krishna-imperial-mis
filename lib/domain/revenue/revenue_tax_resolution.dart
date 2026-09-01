/// Resolving which tax rule governs a revenue component.
///
/// The doctrine is one sentence, and everything here exists to enforce it:
///
/// > For any fact set at a business date, **zero or exactly one** rule may match.
///
/// Zero is a refusal. One resolves. **More than one is a configuration defect and is
/// refused** — there is no runtime specificity ranking and no tiebreak, because a
/// tiebreak silently applies a rate nobody approved (D-079, D-093).
///
/// That has a consequence worth stating plainly, because it is the part that is easy to
/// get wrong: a `null` discriminator means *"this rule does not depend on that
/// dimension"*, which means it matches **every** value of it. So a rule with a null band
/// and a rule with a specific band, over the same dates, both match a component carrying
/// that band — and are therefore a **conflict**, refused at configuration time. Wildcards
/// do not lose to specifics here; they collide with them. Configuration must be
/// partitioned so that one fact set cannot match two rules.
library;

import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// The bounded set of facts a revenue component presents for resolution.
///
/// **There is deliberately no monetary field on this class** (D-094). The value band a
/// room figure belongs to is a *configured identity the operator selected*, never
/// something derived from the amount: a daily aggregate of ₹42,000 attributable to the
/// lower tariff band says nothing about the per-room-per-night tariff that decides the
/// treatment, and comparing the two would be arithmetic nonsense that happens to compile.
///
/// Leaving money out of the fact set makes that mistake **unavailable** rather than
/// merely discouraged: the resolver cannot see an amount, so it cannot resolve from one.
final class RevenueTaxFacts {
  const RevenueTaxFacts({
    required this.revenueCategoryId,
    required this.businessDate,
    this.valueBandId,
    this.supplySubtypeId,
    this.premisesStatusCode,
  });

  final String revenueCategoryId;
  final BusinessDate businessDate;

  /// The configured band the operator chose for this component, where the category has
  /// bands configured. Null when it has none.
  final String? valueBandId;

  final String? supplySubtypeId;

  /// The unit's configured premises tax status on this business date, where one applies.
  final String? premisesStatusCode;

  /// In the same fixed order as [TaxRule.discriminators].
  List<Object?> get discriminators => [
    valueBandId,
    supplySubtypeId,
    premisesStatusCode,
  ];

  @override
  String toString() =>
      'RevenueTaxFacts(category: $revenueCategoryId, ${businessDate.iso}, '
      'band: ${valueBandId ?? '-'}, subtype: ${supplySubtypeId ?? '-'}, '
      'premises: ${premisesStatusCode ?? '-'})';
}

/// The five bounded dimensions (D-079). Named so a refusal can say which one failed.
enum RevenueTaxDimension {
  revenueCategory,
  effectiveDate,
  valueBand,
  supplySubtype,
  premisesStatus;

  String get label => switch (this) {
    RevenueTaxDimension.revenueCategory => 'revenue category',
    RevenueTaxDimension.effectiveDate => 'effective date',
    RevenueTaxDimension.valueBand => 'value band',
    RevenueTaxDimension.supplySubtype => 'supply subtype',
    RevenueTaxDimension.premisesStatus => 'premises tax status',
  };
}

/// The outcome of resolution.
///
/// An explicit result type rather than a nullable rule, because the failures are
/// financially different from one another and from success. In particular **"no rule
/// configured" is not "a configured 0%" and not "a configured `none`"**: the first is a
/// gap, the other two are decisions somebody made and can defend (D-084). Collapsing them
/// is how Net Sales gets silently overstated.
sealed class RevenueTaxResolution {
  const RevenueTaxResolution();

  /// The rule, when exactly one matched.
  TaxRule? get ruleOrNull => switch (this) {
    RevenueTaxResolved(:final rule) => rule,
    _ => null,
  };

  bool get isResolved => this is RevenueTaxResolved;

  /// Plain language for the person who hit it. Never a rate, never a SQLSTATE.
  String get message;
}

/// Exactly one rule matched.
final class RevenueTaxResolved extends RevenueTaxResolution {
  const RevenueTaxResolved(this.rule);

  final TaxRule rule;

  @override
  String get message => 'Tax rule ${rule.ratePercent} ${rule.treatment.name}';
}

/// Nothing matched, and nothing was missing — the configuration simply has no rule here.
final class RevenueTaxNoApplicableRule extends RevenueTaxResolution {
  const RevenueTaxNoApplicableRule(this.facts);

  final RevenueTaxFacts facts;

  @override
  String get message => 'No tax rule configured for this revenue entry.';
}

/// More than one rule matched. A configuration defect, never resolved by ranking.
final class RevenueTaxAmbiguous extends RevenueTaxResolution {
  const RevenueTaxAmbiguous(this.candidates);

  final List<TaxRule> candidates;

  @override
  String get message =>
      'More than one tax rule applies to this revenue entry '
      '(${candidates.length}). The tax configuration must be corrected before this '
      'can be recorded.';
}

/// A rule exists that could have matched, but the component did not state a fact it needs.
///
/// Distinguished from [RevenueTaxNoApplicableRule] because the remedy is different: this
/// one is answered by choosing a band or a subtype on the entry, not by configuring a rule.
final class RevenueTaxMissingFact extends RevenueTaxResolution {
  const RevenueTaxMissingFact(this.dimension);

  final RevenueTaxDimension dimension;

  @override
  String get message =>
      'This revenue entry needs a ${dimension.label} before its tax can be determined.';
}

/// One rule matched and is not usable as configured.
///
/// Today that means a rule with no [TaxRule.inputBasis], or one whose basis contradicts
/// its treatment. Refusing is deliberate: assuming a basis would decide, silently, whether
/// a figure includes tax or not (D-080).
final class RevenueTaxIncompleteRule extends RevenueTaxResolution {
  const RevenueTaxIncompleteRule(this.rule, this.reason);

  final TaxRule rule;
  final String reason;

  @override
  String get message =>
      'The tax rule that applies here is incomplete: $reason. '
      'It must be corrected before revenue can be recorded against it.';
}

/// Why the device cannot resolve at all — a statement about this device, not about the
/// organisation's configuration.
enum RevenueConfigurationGap {
  /// No authoritative reference snapshot has ever been received here.
  neverSynchronised,

  /// The snapshot was purged by a confirmed scope revocation (D-070). Stale configuration
  /// must not be used to create new revenue.
  revoked,
}

/// The device has no authoritative configuration to resolve against.
///
/// **Deliberately not [RevenueTaxNoApplicableRule].** An empty cache and a genuinely
/// empty configuration produce the same query result and mean entirely different things:
/// one is a message for the Owner, the other is a message about this device. Collapsing
/// them is how a device that has never synchronised starts telling a manager that their
/// tax is not configured.
///
/// Both stop a revenue entry. They stop it for different reasons and say so.
final class RevenueConfigurationUnavailable extends RevenueTaxResolution {
  const RevenueConfigurationUnavailable(this.gap);

  final RevenueConfigurationGap gap;

  @override
  String get message => switch (gap) {
    RevenueConfigurationGap.neverSynchronised =>
      'This device has not yet received the tax configuration. Connect to the internet '
          'and try again.',
    RevenueConfigurationGap.revoked =>
      'Your access to this property changed. Reconnect so the current tax configuration '
          'can be loaded before recording revenue.',
  };
}

/// Why two rules cannot both be active.
enum RevenueRuleConflict {
  /// Their dates overlap and no discriminator separates them — including the case where
  /// one is a wildcard and the other is specific.
  overlappingApplicability,

  ratePercentOutOfRange,

  endsBeforeItStarts,

  /// The basis and the treatment contradict each other.
  incoherentBasis,

  /// A rule that governs a band must say which band.
  bandWithoutIdentity;

  String get message => switch (this) {
    RevenueRuleConflict.overlappingApplicability =>
      'Another rule already applies to the same revenue for the same dates. Two rules '
          'that could both match one entry would make its tax ambiguous.',
    RevenueRuleConflict.ratePercentOutOfRange =>
      'A tax rate must be between 0% and 100%.',
    RevenueRuleConflict.endsBeforeItStarts =>
      'A rule cannot end before it begins.',
    RevenueRuleConflict.incoherentBasis =>
      'The amount basis contradicts the tax treatment.',
    RevenueRuleConflict.bandWithoutIdentity =>
      'A rule limited to a value band must name that band.',
  };
}

/// The rules for one organisation, and the doctrine applied to them.
///
/// Pure domain: no Drift, no Supabase, no Flutter. The same instance semantics run against
/// locally cached rules offline and against server fixtures in parity tests (D-086), which
/// is the point — the offline answer and the online answer are the same code, not two
/// implementations that agree today.
final class RevenueTaxRuleSet {
  RevenueTaxRuleSet(Iterable<TaxRule> rules) : rules = List.unmodifiable(rules);

  final List<TaxRule> rules;

  /// Active rules, oldest first.
  List<TaxRule> get active => [
    for (final r in rules)
      if (!r.isArchived) r,
  ]..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));

  /// Every rule that matches [facts] — which must be zero or one for the configuration
  /// to be valid.
  List<TaxRule> matching(RevenueTaxFacts facts) => [
    for (final rule in active)
      if (_matches(rule, facts)) rule,
  ];

  /// Resolve [facts] to exactly one rule, or explain why not.
  RevenueTaxResolution resolve(RevenueTaxFacts facts) {
    final candidates = matching(facts);

    if (candidates.length > 1) return RevenueTaxAmbiguous(candidates);

    if (candidates.isEmpty) {
      // Distinguish "no rule exists" from "a rule exists but you have not told it which
      // band this is". The remedies are different and so are the messages.
      final missing = _missingDimension(facts);
      if (missing != null) return RevenueTaxMissingFact(missing);
      return RevenueTaxNoApplicableRule(facts);
    }

    final rule = candidates.single;
    final basis = rule.inputBasis;
    if (basis == null) {
      return RevenueTaxIncompleteRule(
        rule,
        'it does not say which amount is entered',
      );
    }
    if (!basis.coherentWith(rule.treatment)) {
      return RevenueTaxIncompleteRule(
        rule,
        'its amount basis (${basis.name}) contradicts its treatment '
        '(${rule.treatment.name})',
      );
    }
    return RevenueTaxResolved(rule);
  }

  /// Whether [candidate] can be added without making any fact set ambiguous.
  ///
  /// Returns null when it is safe. This is the **client-side** half; Slice 4 makes the
  /// database authoritative, because two concurrent writes can each pass this check and
  /// still create an ambiguous pair (D-095).
  RevenueRuleConflict? conflictFor(TaxRule candidate) {
    if (candidate.rateBasisPoints < 0 || candidate.rateBasisPoints > 10000) {
      return RevenueRuleConflict.ratePercentOutOfRange;
    }
    final end = candidate.effectiveTo;
    if (end != null && end <= candidate.effectiveFrom) {
      return RevenueRuleConflict.endsBeforeItStarts;
    }
    final basis = candidate.inputBasis;
    if (basis != null && !basis.coherentWith(candidate.treatment)) {
      return RevenueRuleConflict.incoherentBasis;
    }
    if (candidate.valueBandId == null &&
        (candidate.valueBandFloor != null ||
            candidate.valueBandCeiling != null)) {
      return RevenueRuleConflict.bandWithoutIdentity;
    }
    for (final existing in active) {
      if (existing.id == candidate.id) continue;
      if (existing.revenueCategoryId != candidate.revenueCategoryId) continue;
      if (!_datesOverlap(existing, candidate)) continue;
      if (_couldBothMatch(existing, candidate)) {
        return RevenueRuleConflict.overlappingApplicability;
      }
    }
    return null;
  }

  /// A rule matches when its category and dates cover the facts, and every discriminator
  /// either does not care or agrees.
  static bool _matches(TaxRule rule, RevenueTaxFacts facts) {
    if (rule.revenueCategoryId != facts.revenueCategoryId) return false;
    if (!rule.coversDate(facts.businessDate)) return false;

    final ruleValues = rule.discriminators;
    final factValues = facts.discriminators;
    for (var i = 0; i < ruleValues.length; i++) {
      final required = ruleValues[i];
      // Null on the rule is a wildcard: it matches whatever the facts carry, including
      // nothing. Null on the *facts* against a specific rule is not a match — the entry
      // has not stated the thing the rule is about.
      if (required != null && required != factValues[i]) return false;
    }
    return true;
  }

  /// Two rules can both match some fact set when, on every dimension, either is a
  /// wildcard or they agree.
  ///
  /// This is what makes `null` collide with a specific value rather than lose to it.
  static bool _couldBothMatch(TaxRule a, TaxRule b) {
    final left = a.discriminators;
    final right = b.discriminators;
    for (var i = 0; i < left.length; i++) {
      final x = left[i];
      final y = right[i];
      if (x != null && y != null && x != y) return false;
    }
    return true;
  }

  static bool _datesOverlap(TaxRule a, TaxRule b) => a.overlaps(b);

  /// The dimension a same-category, same-date rule requires and the facts did not supply.
  RevenueTaxDimension? _missingDimension(RevenueTaxFacts facts) {
    for (final rule in active) {
      if (rule.revenueCategoryId != facts.revenueCategoryId) continue;
      if (!rule.coversDate(facts.businessDate)) continue;
      if (rule.valueBandId != null && facts.valueBandId == null) {
        return RevenueTaxDimension.valueBand;
      }
      if (rule.supplySubtypeId != null && facts.supplySubtypeId == null) {
        return RevenueTaxDimension.supplySubtype;
      }
      if (rule.premisesStatusCode != null && facts.premisesStatusCode == null) {
        return RevenueTaxDimension.premisesStatus;
      }
    }
    return null;
  }
}
