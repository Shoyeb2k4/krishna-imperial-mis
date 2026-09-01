/// Date-effective tax configuration (master spec §8.1, D-017).
///
/// **No rate is hard-coded anywhere.** A rate belongs to a revenue category over a period
/// of time, and a change is a *new* period rather than an edit to the old one — so last
/// year's Net Sales can never be restated by this year's rate.
///
/// This file computes tax; it does not file it. There is no GST return, no input tax
/// credit and no statutory accounting here (spec §29).
library;

import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:meta/meta.dart';

/// How the recorded figure relates to tax.
enum TaxTreatment {
  /// The figure recorded is what the guest paid, tax included. Tax is extracted from it.
  /// This is the normal case for both properties.
  inclusive,

  /// The figure recorded is net; tax is added on top.
  exclusive,

  /// No tax applies to this category in this period.
  none;

  static TaxTreatment fromName(String value) => TaxTreatment.values.firstWhere(
    (t) => t.name == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'unknown tax treatment'),
  );

  String get label => switch (this) {
    TaxTreatment.inclusive => 'Inclusive',
    TaxTreatment.exclusive => 'Exclusive',
    TaxTreatment.none => 'No tax',
  };

  /// What the person entering the figure is actually typing.
  String get entryHint => switch (this) {
    TaxTreatment.inclusive => 'Enter the total collected, tax included',
    TaxTreatment.exclusive => 'Enter the amount before tax',
    TaxTreatment.none => 'Enter the amount',
  };
}

/// Which number the management operator types, for a rule that governs it.
///
/// **Related to [TaxTreatment] and not the same thing** (D-080, D-088). The treatment says
/// what tax applies; the basis says which figure the operator was asked for. A
/// point-of-sale bill may print `subtotal + tax = total` while the management figure
/// recorded here is the tax-inclusive total, so the basis is never inferred from how a
/// source document presents its arithmetic — it comes from the configured rule.
///
/// All four V1 categories happen to use [inclusiveTotal] today. The enum is not collapsed
/// to match, because the rules are date-effective and a convention can change from a date
/// (D-090).
enum EnteredBasis {
  /// The final customer-billed total. Tax, where any applies, is inside this figure.
  inclusiveTotal,

  /// The amount before tax.
  preTax;

  // There is deliberately no third `none` value (D-097). Every revenue figure a manager
  // records is money billed to a customer; where no tax applies, that figure is
  // simultaneously the customer total and the pre-tax amount, so it is already fully
  // described by one of the two above. A third label would add no information and would
  // invite recording Banquet as "none" — which D-091 argued against, because
  // `inclusiveTotal` states what the number *is* and stays true if tax is ever introduced.

  /// How this value is written to both databases.
  ///
  /// Stated explicitly rather than taken from [name]. The two schemas store
  /// `inclusive_total`, and a Dart enum name is `inclusiveTotal` — relying on the
  /// coincidence of the two agreeing is how a rule becomes unreadable the moment somebody
  /// renames a constant. Writing a revenue figure under the wrong basis decides whether a
  /// recorded amount includes tax, so this mapping is pinned by a test.
  String get wireName => switch (this) {
    EnteredBasis.inclusiveTotal => 'inclusive_total',
    EnteredBasis.preTax => 'pre_tax',
  };

  /// Parses the stored form. Accepts nothing else — an unknown basis throws rather than
  /// defaulting, because there is no safe default for "which amount is this".
  static EnteredBasis fromName(String value) => EnteredBasis.values.firstWhere(
    (b) => b.wireName == value,
    orElse: () => throw ArgumentError.value(value, 'value', 'unknown basis'),
  );

  /// What to put above the amount field, for a rule with this basis and [treatment].
  ///
  /// **Takes the treatment**, because the basis alone cannot produce an honest label
  /// (D-097). Banquet is `inclusiveTotal` with treatment `none`: labelling its field
  /// "Customer total (incl. GST)" would tell an operator that GST is inside a figure that
  /// carries none. Never universally "Gross" either (D-080).
  String fieldLabelFor(TaxTreatment treatment) {
    if (treatment == TaxTreatment.none) {
      return switch (this) {
        EnteredBasis.inclusiveTotal => 'Amount billed to the customer',
        EnteredBasis.preTax => 'Amount',
      };
    }
    return switch (this) {
      EnteredBasis.inclusiveTotal => 'Customer total (incl. GST)',
      EnteredBasis.preTax => 'Amount before GST',
    };
  }

  /// Whether this basis can truthfully accompany [treatment].
  ///
  /// The two answer different questions — *which number did the operator type* and *how is
  /// tax treated* — so they are **not** coupled one-to-one (D-097):
  ///
  /// * `inclusive` extracts tax from a total, so the operator must have typed the total;
  /// * `exclusive` adds tax to a net figure, so they must have typed the net figure;
  /// * `none` applies no tax, and **either basis is truthful**. With tax at zero the
  ///   customer total and the pre-tax amount are the same number, so the basis records
  ///   which one the source figure *is* rather than changing what is computed. Forcing it
  ///   to some third value would discard that truth to satisfy a symmetry that does not
  ///   exist.
  ///
  /// The refused pairings are the contradictory ones: "type the pre-tax amount, and the
  /// tax is already inside it" is not a thing, and neither is its mirror.
  bool coherentWith(TaxTreatment treatment) => switch (treatment) {
    TaxTreatment.none => true,
    TaxTreatment.inclusive => this == EnteredBasis.inclusiveTotal,
    TaxTreatment.exclusive => this == EnteredBasis.preTax,
  };
}

/// The result of applying a rule. Every component is stored on the revenue record, so a
/// later rate change cannot alter it.
@immutable
final class TaxComputation {
  const TaxComputation({
    required this.gross,
    required this.tax,
    required this.net,
    required this.rateBasisPoints,
    required this.treatment,
    this.ruleId,
  });

  /// What the guest paid, tax included.
  final Money gross;
  final Money tax;

  /// `gross − tax`. This is what reaches the P&L as Net Sales.
  final Money net;

  final int rateBasisPoints;
  final TaxTreatment treatment;

  /// The configuration row that produced this, snapshotted for explainability.
  final String? ruleId;

  /// The invariant every revenue row must satisfy.
  bool get reconciles => net + tax == gross;

  @override
  String toString() =>
      'TaxComputation(gross: $gross, tax: $tax, net: $net, '
      '${rateBasisPoints / 100}% ${treatment.name})';
}

/// One rate, for one revenue category, over one period of time.
///
/// The period is **half-open**: `[effectiveFrom, effectiveTo)`. A rule ending on the same
/// date another begins is therefore not an overlap — the boundary belongs to the new
/// rule, and exactly one rule applies to any date.
@immutable
final class TaxRule {
  const TaxRule({
    required this.id,
    required this.revenueCategoryId,
    required this.rateBasisPoints,
    required this.treatment,
    required this.effectiveFrom,
    this.effectiveTo,
    this.archivedAt,
    this.note,
    this.inputBasis,
    this.valueBandId,
    this.valueBandLabel,
    this.valueBandFloor,
    this.valueBandCeiling,
    this.supplySubtypeId,
    this.premisesStatusCode,
  });

  final String id;
  final String revenueCategoryId;

  /// Which figure the operator types under this rule (D-080).
  ///
  /// Nullable because rules configured before the concept existed do not carry one. A rule
  /// with no basis is **incomplete configuration**, and the revenue resolver refuses it
  /// rather than assuming `inclusiveTotal` — a default here is exactly the wrong-but-
  /// harmless-looking kind that D-090 rejects.
  final EnteredBasis? inputBasis;

  /// The configured value band this rule governs, or null for "does not depend on a band".
  ///
  /// **An identity, never a computation.** The band a room figure belongs to is *chosen*
  /// from configuration, not derived from the amount: a day's aggregate room revenue of
  /// ₹42,000 says nothing about the per-room-per-night tariff that decides the treatment
  /// (D-094). [valueBandFloor] and [valueBandCeiling] are carried for **display and
  /// snapshot explanation only** and are never compared against a revenue amount.
  final String? valueBandId;
  final String? valueBandLabel;
  final Money? valueBandFloor;
  final Money? valueBandCeiling;

  /// The supply subtype this rule governs, or null for "does not depend on one".
  final String? supplySubtypeId;

  /// The business-unit premises tax status this rule requires, or null.
  final String? premisesStatusCode;

  /// The discriminators, in a fixed order, for conflict detection and explanation.
  ///
  /// A list rather than ad-hoc field access so adding a dimension is one edit and cannot
  /// be half-applied — D-079 bounds the set deliberately, and the bound is only real if
  /// every consumer sees the same list.
  List<Object?> get discriminators => [
    valueBandId,
    supplySubtypeId,
    premisesStatusCode,
  ];

  /// Basis points: 1% = 100. A 5% rate is 500. Integers throughout, so no rate ever
  /// arrives as a float.
  final int rateBasisPoints;

  final TaxTreatment treatment;
  final BusinessDate effectiveFrom;

  /// Exclusive upper bound. Null means "still in force".
  final BusinessDate? effectiveTo;

  final DateTime? archivedAt;
  final String? note;

  bool get isArchived => archivedAt != null;
  bool get isOpenEnded => effectiveTo == null;

  /// Rate as a percentage string for display: `5%`, `12.5%`.
  String get ratePercent {
    final whole = rateBasisPoints ~/ 100;
    final fraction = rateBasisPoints % 100;
    if (fraction == 0) return '$whole%';
    final trimmed = fraction % 10 == 0 ? '${fraction ~/ 10}' : '$fraction';
    return '$whole.$trimmed%';
  }

  /// Whether this rule governs [date]. Half-open, so `effectiveTo` is not included.
  bool coversDate(BusinessDate date) {
    if (isArchived) return false;
    if (date < effectiveFrom) return false;
    final end = effectiveTo;
    return end == null || date < end;
  }

  /// Whether two rules for the same category would both claim some date.
  bool overlaps(TaxRule other) {
    if (other.revenueCategoryId != revenueCategoryId) return false;
    if (isArchived || other.isArchived) return false;
    if (other.id == id) return false;

    final aEnd = effectiveTo;
    final bEnd = other.effectiveTo;
    final aStartsBeforeBEnds = bEnd == null || effectiveFrom < bEnd;
    final bStartsBeforeAEnds = aEnd == null || other.effectiveFrom < aEnd;
    return aStartsBeforeBEnds && bStartsBeforeAEnds;
  }

  /// Applies this rule to the figure the user typed.
  ///
  /// Rounding happens **once, here, at the record** — half-up away from zero — and the
  /// result is stored. Aggregates later sum stored paise; they never re-apply a rate to
  /// a total, which is how a report stays reconcilable to its rows.
  TaxComputation compute(Money entered) {
    if (entered.isNegative) {
      throw ArgumentError.value(
        entered,
        'entered',
        'revenue must not be negative',
      );
    }

    switch (treatment) {
      case TaxTreatment.none:
        return TaxComputation(
          gross: entered,
          tax: Money.zero,
          net: entered,
          rateBasisPoints: 0,
          treatment: TaxTreatment.none,
          ruleId: id,
        );

      case TaxTreatment.inclusive:
        // tax = gross × rate ÷ (10000 + rate)
        final tax = entered.multiplyByRatio(
          rateBasisPoints,
          10000 + rateBasisPoints,
        );
        return TaxComputation(
          gross: entered,
          tax: tax,
          net: entered - tax,
          rateBasisPoints: rateBasisPoints,
          treatment: treatment,
          ruleId: id,
        );

      case TaxTreatment.exclusive:
        final tax = entered.percentage(rateBasisPoints);
        return TaxComputation(
          gross: entered + tax,
          tax: tax,
          net: entered,
          rateBasisPoints: rateBasisPoints,
          treatment: treatment,
          ruleId: id,
        );
    }
  }

  TaxRule copyWith({BusinessDate? effectiveTo, DateTime? archivedAt}) =>
      TaxRule(
        id: id,
        revenueCategoryId: revenueCategoryId,
        rateBasisPoints: rateBasisPoints,
        treatment: treatment,
        effectiveFrom: effectiveFrom,
        effectiveTo: effectiveTo ?? this.effectiveTo,
        archivedAt: archivedAt ?? this.archivedAt,
        note: note,
      );

  @override
  String toString() =>
      'TaxRule($ratePercent ${treatment.name}, '
      '${effectiveFrom.iso} → ${effectiveTo?.iso ?? 'open'})';
}

/// Why a proposed rule was refused.
enum TaxRuleRefusal {
  overlapsExistingPeriod,
  endsBeforeItStarts,
  rateOutOfRange,
  categoryMissing;

  String get message => switch (this) {
    TaxRuleRefusal.overlapsExistingPeriod =>
      'Another tax rule already covers part of that period for this category. '
          'Close the existing period first, or choose different dates.',
    TaxRuleRefusal.endsBeforeItStarts =>
      'The end date must be after the start date.',
    TaxRuleRefusal.rateOutOfRange => 'The rate must be between 0% and 100%.',
    TaxRuleRefusal.categoryMissing => 'That revenue category does not exist.',
  };
}

class TaxRuleRejected implements Exception {
  const TaxRuleRejected(this.refusal);
  final TaxRuleRefusal refusal;

  @override
  String toString() => 'TaxRuleRejected: ${refusal.message}';
}

/// All rules for one revenue category, with the rules about the rules.
@immutable
final class TaxRuleSet {
  TaxRuleSet(Iterable<TaxRule> rules) : rules = List.unmodifiable(rules);

  final List<TaxRule> rules;

  /// Active rules, oldest first.
  List<TaxRule> get active => [
    for (final r in rules)
      if (!r.isArchived) r,
  ]..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));

  /// The rule governing a business date, or null when none is configured.
  ///
  /// Returning null rather than defaulting to zero is deliberate: a missing rule is a
  /// configuration gap the user must see, not a silent "no tax" that quietly overstates
  /// Net Sales.
  TaxRule? ruleFor(BusinessDate date) {
    for (final rule in active) {
      if (rule.coversDate(date)) return rule;
    }
    return null;
  }

  /// Whether [candidate] can be added without colliding with what is already there.
  TaxRuleRefusal? refusalFor(TaxRule candidate) {
    if (candidate.rateBasisPoints < 0 || candidate.rateBasisPoints > 10000) {
      return TaxRuleRefusal.rateOutOfRange;
    }
    final end = candidate.effectiveTo;
    if (end != null && end <= candidate.effectiveFrom) {
      return TaxRuleRefusal.endsBeforeItStarts;
    }
    for (final existing in active) {
      if (existing.overlaps(candidate)) {
        return TaxRuleRefusal.overlapsExistingPeriod;
      }
    }
    return null;
  }

  /// Dates in this set's span that no active rule covers.
  ///
  /// Surfaced in the UI so a gap is visible before somebody records revenue into it.
  List<({BusinessDate from, BusinessDate? to})> gaps() {
    final ordered = active;
    if (ordered.isEmpty) return const [];

    final result = <({BusinessDate from, BusinessDate? to})>[];
    for (var i = 0; i < ordered.length - 1; i++) {
      final end = ordered[i].effectiveTo;
      if (end == null) break; // an open-ended rule cannot be followed by a gap
      final nextStart = ordered[i + 1].effectiveFrom;
      if (end < nextStart) result.add((from: end, to: nextStart));
    }
    if (ordered.last.effectiveTo != null) {
      result.add((from: ordered.last.effectiveTo!, to: null));
    }
    return result;
  }
}
