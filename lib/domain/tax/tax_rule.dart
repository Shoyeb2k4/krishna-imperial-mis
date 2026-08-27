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
  });

  final String id;
  final String revenueCategoryId;

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
