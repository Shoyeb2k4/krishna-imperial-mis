/// Canonical monetary representation for the entire application.
///
/// Money is stored and computed as **integer minor units (paise)**. Binary floating
/// point never touches a currency amount — see docs/DECISIONS.md D-002.
///
/// Division only happens through the explicit, tested helpers in this file, each of
/// which states its rounding policy. Nothing else in the codebase may divide money.
library;

import 'package:meta/meta.dart';

/// How a division that does not come out exactly is resolved.
///
/// Only one policy exists today. It is named explicitly rather than left implicit so
/// that any future addition is a deliberate, reviewed change.
enum MoneyRounding {
  /// Round to the nearest paisa; exact halves round **away from zero**.
  ///
  /// `2.5 → 3`, `-2.5 → -3`. This matches ordinary Indian invoicing convention and is
  /// symmetric about zero, so reversing the sign of an input reverses the sign of the
  /// output and nothing else.
  halfUpAwayFromZero,
}

/// An exact monetary amount held as integer paise.
///
/// 100 paise = ₹1. All arithmetic is exact; there is no rounding anywhere except in
/// the explicitly named operations [multiplyByRatio], [percentage] and [allocate].
@immutable
final class Money implements Comparable<Money> {
  /// The amount in paise. Negative values are legitimate (a reversal, a loss).
  final int paise;

  const Money.fromPaise(this.paise);

  /// Convenience for whole rupees. `Money.fromRupees(1200)` is ₹1,200.00.
  const Money.fromRupees(int rupees) : paise = rupees * 100;

  static const Money zero = Money.fromPaise(0);

  /// Parses user input such as `1,23,456.78`, `123456.7`, `1200`, `-450.05`.
  ///
  /// Accepts an optional leading `₹`, digit-group separators, and at most two decimal
  /// places. Returns `null` for anything it cannot read exactly — it never guesses, and
  /// it never silently truncates a third decimal place.
  static Money? tryParse(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;

    s = s.replaceAll('₹', '').replaceAll(',', '').replaceAll(' ', '').trim();

    var negative = false;
    if (s.startsWith('(') && s.endsWith(')')) {
      negative = true;
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.startsWith('-')) {
      negative = !negative;
      s = s.substring(1).trim();
    } else if (s.startsWith('+')) {
      s = s.substring(1).trim();
    }
    if (s.isEmpty) return null;

    final parts = s.split('.');
    if (parts.length > 2) return null;

    final whole = parts[0].isEmpty ? '0' : parts[0];
    if (!_isAllDigits(whole)) return null;

    var fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.isNotEmpty && !_isAllDigits(fraction)) return null;
    if (fraction.length > 2) return null;
    fraction = fraction.padRight(2, '0');

    final rupees = int.tryParse(whole);
    final paisePart = int.tryParse(fraction.isEmpty ? '0' : fraction);
    if (rupees == null || paisePart == null) return null;

    final total = rupees * 100 + paisePart;
    return Money.fromPaise(negative ? -total : total);
  }

  static bool _isAllDigits(String s) {
    if (s.isEmpty) return false;
    for (final unit in s.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return false;
    }
    return true;
  }

  bool get isZero => paise == 0;
  bool get isNegative => paise < 0;
  bool get isPositive => paise > 0;

  /// Whole rupees, truncated toward zero. For display use the formatter, not this.
  int get wholeRupees => paise ~/ 100;

  /// The paise remainder, carrying the same sign as [paise].
  int get paiseRemainder => paise.remainder(100);

  Money operator +(Money other) => Money.fromPaise(paise + other.paise);
  Money operator -(Money other) => Money.fromPaise(paise - other.paise);
  Money operator -() => Money.fromPaise(-paise);

  /// Exact scaling by a whole number — no rounding is possible, so none is named.
  Money operator *(int factor) => Money.fromPaise(paise * factor);

  Money get absolute => paise < 0 ? Money.fromPaise(-paise) : this;

  bool operator >(Money other) => paise > other.paise;
  bool operator >=(Money other) => paise >= other.paise;
  bool operator <(Money other) => paise < other.paise;
  bool operator <=(Money other) => paise <= other.paise;

  /// Multiplies by the ratio `numerator / denominator`, rounding once, explicitly.
  ///
  /// This is the only multiplication that can lose exactness, which is why it demands
  /// the rounding policy be visible at the call site.
  Money multiplyByRatio(
    int numerator,
    int denominator, {
    MoneyRounding rounding = MoneyRounding.halfUpAwayFromZero,
  }) {
    if (denominator == 0) {
      throw ArgumentError.value(denominator, 'denominator', 'must not be zero');
    }
    return Money.fromPaise(
      _divideRounded(paise * numerator, denominator, rounding),
    );
  }

  /// A percentage expressed in **basis points** (1% = 100 bp), rounded once.
  ///
  /// Basis points keep rate configuration in integers, so a 5% rate is 500 and no
  /// floating point is ever involved in tax or share calculations.
  Money percentage(
    int basisPoints, {
    MoneyRounding rounding = MoneyRounding.halfUpAwayFromZero,
  }) => multiplyByRatio(basisPoints, 10000, rounding: rounding);

  /// Splits this amount across [weights] so the parts **always sum back exactly**.
  ///
  /// Uses largest-remainder distribution: every part gets its floor share, then the
  /// leftover paise go one each to the parts with the largest remainders, ties broken
  /// by position so the result is deterministic. This is what lets a shared electricity
  /// bill be split three ways without a stray paisa appearing or vanishing
  /// (docs/DECISIONS.md D-003).
  ///
  /// [weights] must be non-empty and non-negative, with a positive total.
  List<Money> allocate(List<int> weights) {
    if (weights.isEmpty) {
      throw ArgumentError.value(weights, 'weights', 'must not be empty');
    }
    var totalWeight = 0;
    for (final w in weights) {
      if (w < 0) {
        throw ArgumentError.value(
          weights,
          'weights',
          'must not contain negative values',
        );
      }
      totalWeight += w;
    }
    if (totalWeight == 0) {
      throw ArgumentError.value(
        weights,
        'weights',
        'must have a positive total',
      );
    }

    // Work on the magnitude and re-apply the sign, so a negative total splits into
    // negative parts that still reconcile exactly.
    final sign = paise < 0 ? -1 : 1;
    final magnitude = paise.abs();

    final shares = List<int>.filled(weights.length, 0);
    final remainders = List<int>.filled(weights.length, 0);
    var distributed = 0;

    for (var i = 0; i < weights.length; i++) {
      final numerator = magnitude * weights[i];
      shares[i] = numerator ~/ totalWeight;
      remainders[i] = numerator.remainder(totalWeight);
      distributed += shares[i];
    }

    var leftover = magnitude - distributed;
    final order = List<int>.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = remainders[b].compareTo(remainders[a]);
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });

    for (var i = 0; leftover > 0; i = (i + 1) % order.length) {
      // A zero-weight part is entitled to nothing and never receives a leftover paisa.
      if (weights[order[i]] == 0) continue;
      shares[order[i]] += 1;
      leftover -= 1;
    }

    return [for (final share in shares) Money.fromPaise(sign * share)];
  }

  /// Splits this amount by basis-point shares that must total exactly 10000 (100%).
  List<Money> allocateByBasisPoints(List<int> basisPoints) {
    final total = basisPoints.fold<int>(0, (a, b) => a + b);
    if (total != 10000) {
      throw ArgumentError.value(
        basisPoints,
        'basisPoints',
        'must total exactly 10000 basis points (100%), got $total',
      );
    }
    return allocate(basisPoints);
  }

  static int _divideRounded(
    int numerator,
    int denominator,
    MoneyRounding rounding,
  ) {
    switch (rounding) {
      case MoneyRounding.halfUpAwayFromZero:
        final negative = (numerator < 0) != (denominator < 0);
        final n = numerator.abs();
        final d = denominator.abs();
        final quotient = n ~/ d;
        final remainder = n.remainder(d);
        final roundUp = remainder * 2 >= d;
        final magnitude = roundUp ? quotient + 1 : quotient;
        return negative ? -magnitude : magnitude;
    }
  }

  /// Sums a collection exactly. Empty sums to [zero], never to null.
  static Money sum(Iterable<Money> amounts) {
    var total = 0;
    for (final amount in amounts) {
      total += amount.paise;
    }
    return Money.fromPaise(total);
  }

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;

  /// Debug representation only. **Never** show this to a user — user-facing text comes
  /// from the single MoneyFormatter in core/formatting.
  @override
  String toString() => 'Money($paise paise)';
}
