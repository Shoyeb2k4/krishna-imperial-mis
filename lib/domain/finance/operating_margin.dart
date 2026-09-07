/// Operating profit margin, kept exact and left unrounded.
///
/// Spec §10 defines it as `Operating Profit ÷ Net Sales × 100`, and that is the only
/// division anywhere in the financial model. Two rules govern how it is represented here.
///
/// **No `double`.** A margin is a presentation figure, but the moment it is computed as a
/// binary float somebody will add two of them, or average them across properties, and the
/// result will be a financial figure that is off in the last place with no audit trail
/// explaining why. The margin is therefore carried as the **exact rational** it is —
/// numerator and denominator in paise — and reduced to a decimal only at the point of
/// display, by a caller who states the precision it wants.
///
/// **The display precision is not settled, so it is not chosen here.** The binding spec
/// says the margin is reported; it does not say to how many places. Baking one in would be
/// deciding a presentation question in the calculation layer and then having to unpick it
/// from every export. [MarginRatio.percentageScaled] defers it: ask for the precision you
/// are about to print.
///
/// **Zero net sales is not a zero margin.** Spec §10 requires "not applicable", never
/// `0%`, never `NaN`, never `Infinity`. That is a separate case in the type, so a caller
/// cannot print a number that does not exist.
library;

/// The margin of a P&L, or the statement that there is not one.
sealed class OperatingMargin {
  const OperatingMargin();
}

/// Net sales were zero, so the margin is undefined (spec §10).
///
/// Distinct from a margin of zero, which means profit was exactly nil against real sales.
/// A break-even month and a month with no trade are different facts.
final class MarginNotApplicable extends OperatingMargin {
  const MarginNotApplicable();

  @override
  bool operator ==(Object other) => other is MarginNotApplicable;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'MarginNotApplicable()';
}

/// An exact margin, held as the ratio it is.
final class MarginRatio extends OperatingMargin {
  const MarginRatio({
    required this.operatingProfitPaise,
    required this.netSalesPaise,
  }) : assert(netSalesPaise != 0, 'zero net sales is MarginNotApplicable');

  /// The numerator and denominator, in paise, exactly as they were summed. Nothing has
  /// been divided yet, so nothing has been lost yet.
  final int operatingProfitPaise;
  final int netSalesPaise;

  /// Negative when the property made a loss. Not clamped: a management P&L reports what
  /// happened.
  bool get isNegative => operatingProfitPaise.sign * netSalesPaise.sign < 0;

  /// The percentage, multiplied by `10^scale`, as an exact integer.
  ///
  /// `scale: 0` gives whole percent, `scale: 2` gives hundredths. The division happens
  /// once, here, on integers, and rounds **half away from zero** so that a loss of
  /// −12.345% and a profit of +12.345% round symmetrically rather than one of them
  /// drifting toward zero.
  ///
  /// ```
  ///   profit 5852381, net 10352381, scale 2  ->  5653  ->  56.53%
  /// ```
  int percentageScaled(int scale) {
    assert(scale >= 0, 'a negative scale is not a precision');
    var multiplier = 100;
    for (var i = 0; i < scale; i++) {
      multiplier *= 10;
    }
    final numerator = operatingProfitPaise * multiplier;
    final quotient = numerator ~/ netSalesPaise;
    final remainder = numerator.remainder(netSalesPaise);
    if (remainder == 0) return quotient;
    // Half away from zero, in integers: compare twice the remainder against the divisor.
    final roundsUp = (remainder.abs() * 2) >= netSalesPaise.abs();
    if (!roundsUp) return quotient;
    final sign = (operatingProfitPaise.sign * netSalesPaise.sign) < 0 ? -1 : 1;
    return quotient + sign;
  }

  @override
  bool operator ==(Object other) =>
      other is MarginRatio &&
      other.operatingProfitPaise == operatingProfitPaise &&
      other.netSalesPaise == netSalesPaise;

  @override
  int get hashCode => Object.hash(operatingProfitPaise, netSalesPaise);

  @override
  String toString() => 'MarginRatio($operatingProfitPaise/$netSalesPaise)';
}
