/// Period-over-period comparison of two canonical P&L results (Phase 6, D-253).
///
/// Every comparison figure a dashboard shows is decided here, once, from two
/// [PnlOutcome]s the reporting engine produced. Nothing re-sums a transaction and nothing
/// re-derives Net Sales or Operating Profit: the figures compared are the fields of the two
/// results, and the only new arithmetic is the change between them.
///
/// ## The rules, as the project lead set them
///
/// * **Either side unavailable → no numbers.** Not authorised, not downloaded, one side of
///   the P&L missing — whatever the reason, the comparison is [MoneyComparisonUnavailable]
///   and carries no change, no previous figure and no percentage. Nothing becomes zero.
/// * **Previous figure zero → percentage N/A**, the rupee change kept.
/// * **Operating Profit with a negative side → no percentage.** A sign change is stated in
///   words — *Moved from loss to profit* — beside the exact rupee movement.
/// * **Operating Margin moves in percentage points**, exactly: 12.30% → 14.10% is
///   +1.80 pp, never "14.63% growth".
///
/// One rule is this layer's own and is recorded as such (D-256): an ordinary figure whose
/// previous value is **negative** also gets no percentage. A percentage of a negative base
/// reads backwards, and it is the conservative reading of the profit rule.
///
/// ## Exact arithmetic
///
/// Percentages and percentage points are exact rationals over paise, rounded once, half
/// away from zero, at the precision the caller prints. The margin movement compares two
/// ratios, so its cross product can pass 2^63 at crore scale; it is computed in [BigInt].
library;

import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// Which side of a comparison could not be established.
enum ComparisonSide { current, previous, both }

/// Why a percentage change is not shown.
enum PercentNotApplicableReason {
  /// The previous figure was zero. There is no base to measure against.
  previousZero,

  /// An ordinary figure's previous value was negative (D-256).
  previousNegative,

  /// Operating Profit: at least one side was a loss.
  negativeSide,

  /// Operating Profit: one side was a loss and the other a profit.
  signChanged,
}

/// A profit that crossed zero, in words.
enum ProfitTransition {
  none(null),
  lossToProfit('Moved from loss to profit'),
  profitToLoss('Moved from profit to loss');

  const ProfitTransition(this.wording);

  final String? wording;
}

// ── Percentage change ───────────────────────────────────────────────────────

sealed class PercentChange {
  const PercentChange();

  /// `+12.34%`, `-3.00%`, `0.00%`, or `N/A`.
  String get displayTwoDecimals;
}

final class PercentChangeNotApplicable extends PercentChange {
  const PercentChangeNotApplicable(this.reason);
  final PercentNotApplicableReason reason;

  @override
  String get displayTwoDecimals => 'N/A';
}

/// `change ÷ previous × 100`, held exactly. [previousPaise] is always positive.
final class PercentChangeRatio extends PercentChange {
  const PercentChangeRatio({
    required this.changePaise,
    required this.previousPaise,
  }) : assert(previousPaise > 0, 'a percentage needs a positive base');

  final int changePaise;
  final int previousPaise;

  /// The percentage × 10^[scale], rounded once, half away from zero.
  int percentageScaled(int scale) => _roundedQuotient(
    BigInt.from(changePaise) * _scaledHundred(scale),
    BigInt.from(previousPaise),
  );

  @override
  String get displayTwoDecimals =>
      '${_signedTwoDecimals(percentageScaled(2))}%';

  @override
  bool operator ==(Object other) =>
      other is PercentChangeRatio &&
      other.changePaise == changePaise &&
      other.previousPaise == previousPaise;

  @override
  int get hashCode => Object.hash(changePaise, previousPaise);
}

// ── A money figure compared ─────────────────────────────────────────────────

sealed class MoneyComparison {
  const MoneyComparison();
}

/// No numerical comparison, because a side is missing.
final class MoneyComparisonUnavailable extends MoneyComparison {
  const MoneyComparisonUnavailable({
    required this.side,
    this.currentRefusal,
    this.previousRefusal,
  });

  final ComparisonSide side;

  /// The refusal behind each unavailable side, carried rather than flattened.
  final PnlRefusal? currentRefusal;
  final PnlRefusal? previousRefusal;
}

final class MoneyComparisonAvailable extends MoneyComparison {
  const MoneyComparisonAvailable({
    required this.current,
    required this.previous,
    required this.percentChange,
    this.transition = ProfitTransition.none,
  });

  final Money current;
  final Money previous;
  final PercentChange percentChange;

  /// Only Operating Profit ever carries anything but [ProfitTransition.none].
  final ProfitTransition transition;

  /// `current − previous`, exactly.
  Money get change => current - previous;
}

// ── The margin compared ─────────────────────────────────────────────────────

enum MarginComparisonUnavailableReason {
  /// A side of the comparison is not available.
  sideUnavailable,

  /// A side had no net sales, so it has no margin to compare.
  marginNotApplicable,
}

sealed class MarginComparison {
  const MarginComparison();

  /// `+1.80 pp`, `-0.50 pp`, `0.00 pp`, or `N/A`.
  String get displayTwoDecimals;
}

final class MarginComparisonUnavailable extends MarginComparison {
  const MarginComparisonUnavailable(this.reason);
  final MarginComparisonUnavailableReason reason;

  @override
  String get displayTwoDecimals => 'N/A';
}

/// The exact change between two margins, in percentage points.
///
/// ```
///   pp = (p1/n1 − p0/n0) × 100 = (p1·n0 − p0·n1) × 100 ÷ (n1·n0)
/// ```
///
/// Taken from the two exact ratios, never from their rounded displays — so 1/3 against 1/6
/// moves +16.67 pp, even though 33.33% − 16.67% would print 16.66.
final class MarginMovement extends MarginComparison {
  const MarginMovement({required this.current, required this.previous});

  final MarginRatio current;
  final MarginRatio previous;

  /// Percentage points × 10^[scale], rounded once, half away from zero.
  int pointsScaled(int scale) {
    final p1 = BigInt.from(current.operatingProfitPaise);
    final n1 = BigInt.from(current.netSalesPaise);
    final p0 = BigInt.from(previous.operatingProfitPaise);
    final n0 = BigInt.from(previous.netSalesPaise);
    return _roundedQuotient(
      (p1 * n0 - p0 * n1) * _scaledHundred(scale),
      n1 * n0,
    );
  }

  @override
  String get displayTwoDecimals => '${_signedTwoDecimals(pointsScaled(2))} pp';
}

// ── The comparison of two P&L results ───────────────────────────────────────

final class PnlComparison {
  const PnlComparison._({
    required this.pair,
    required this.grossSales,
    required this.gst,
    required this.netSales,
    required this.expenses,
    required this.operatingProfit,
    required this.margin,
  });

  /// The two ranges compared, including whether the comparator was capped.
  final DashboardPeriodPair pair;

  final MoneyComparison grossSales;
  final MoneyComparison gst;
  final MoneyComparison netSales;
  final MoneyComparison expenses;
  final MoneyComparison operatingProfit;
  final MarginComparison margin;

  /// Compares [current] with [previous] for [pair].
  ///
  /// A computed result for a range other than the one [pair] names, or two results for
  /// different scopes, is a programming error and throws: comparing the wrong things
  /// would produce a plausible figure nobody could detect as wrong.
  static PnlComparison compare({
    required DashboardPeriodPair pair,
    required PnlOutcome current,
    required PnlOutcome previous,
  }) {
    if (current case PnlComputed(
      :final result,
    ) when result.range != pair.current) {
      throw ArgumentError.value(
        result.range,
        'current',
        'is not the current range ${pair.current}',
      );
    }
    if (previous case PnlComputed(
      :final result,
    ) when result.range != pair.comparison) {
      throw ArgumentError.value(
        result.range,
        'previous',
        'is not the comparison range ${pair.comparison}',
      );
    }

    switch ((current, previous)) {
      case (PnlComputed(result: final now), PnlComputed(result: final then)):
        if (now.businessUnitId != then.businessUnitId) {
          throw ArgumentError(
            'cannot compare ${now.businessUnitId ?? 'consolidated'} with '
            '${then.businessUnitId ?? 'consolidated'}',
          );
        }
        return PnlComparison._(
          pair: pair,
          grossSales: _ordinary(now.grossSales, then.grossSales),
          gst: _ordinary(now.gst, then.gst),
          netSales: _ordinary(now.netSales, then.netSales),
          expenses: _ordinary(now.expenses, then.expenses),
          operatingProfit: _profit(now.operatingProfit, then.operatingProfit),
          margin: _margin(now.margin, then.margin),
        );
      default:
        final side = switch ((current, previous)) {
          (PnlRefused(), PnlRefused()) => ComparisonSide.both,
          (PnlRefused(), _) => ComparisonSide.current,
          _ => ComparisonSide.previous,
        };
        final unavailable = MoneyComparisonUnavailable(
          side: side,
          currentRefusal: switch (current) {
            PnlRefused(:final refusal) => refusal,
            PnlComputed() => null,
          },
          previousRefusal: switch (previous) {
            PnlRefused(:final refusal) => refusal,
            PnlComputed() => null,
          },
        );
        return PnlComparison._(
          pair: pair,
          grossSales: unavailable,
          gst: unavailable,
          netSales: unavailable,
          expenses: unavailable,
          operatingProfit: unavailable,
          margin: const MarginComparisonUnavailable(
            MarginComparisonUnavailableReason.sideUnavailable,
          ),
        );
    }
  }

  static MoneyComparison _ordinary(Money current, Money previous) =>
      MoneyComparisonAvailable(
        current: current,
        previous: previous,
        percentChange: previous.isZero
            ? const PercentChangeNotApplicable(
                PercentNotApplicableReason.previousZero,
              )
            : previous.isNegative
            ? const PercentChangeNotApplicable(
                PercentNotApplicableReason.previousNegative,
              )
            : PercentChangeRatio(
                changePaise: (current - previous).paise,
                previousPaise: previous.paise,
              ),
      );

  static MoneyComparison _profit(Money current, Money previous) {
    final transition = previous.isNegative && current.isPositive
        ? ProfitTransition.lossToProfit
        : previous.isPositive && current.isNegative
        ? ProfitTransition.profitToLoss
        : ProfitTransition.none;
    final PercentChange percent;
    if (transition != ProfitTransition.none) {
      percent = const PercentChangeNotApplicable(
        PercentNotApplicableReason.signChanged,
      );
    } else if (current.isNegative || previous.isNegative) {
      percent = const PercentChangeNotApplicable(
        PercentNotApplicableReason.negativeSide,
      );
    } else if (previous.isZero) {
      percent = const PercentChangeNotApplicable(
        PercentNotApplicableReason.previousZero,
      );
    } else {
      percent = PercentChangeRatio(
        changePaise: (current - previous).paise,
        previousPaise: previous.paise,
      );
    }
    return MoneyComparisonAvailable(
      current: current,
      previous: previous,
      percentChange: percent,
      transition: transition,
    );
  }

  static MarginComparison _margin(
    OperatingMargin current,
    OperatingMargin previous,
  ) => switch ((current, previous)) {
    (final MarginRatio now, final MarginRatio then) => MarginMovement(
      current: now,
      previous: then,
    ),
    _ => const MarginComparisonUnavailable(
      MarginComparisonUnavailableReason.marginNotApplicable,
    ),
  };
}

// ── Integer helpers ─────────────────────────────────────────────────────────

/// `100 × 10^scale`.
BigInt _scaledHundred(int scale) {
  if (scale < 0) {
    throw ArgumentError.value(scale, 'scale', 'is not a precision');
  }
  return BigInt.from(100) * BigInt.from(10).pow(scale);
}

/// `numerator ÷ denominator`, rounded half away from zero, as an int.
int _roundedQuotient(BigInt numerator, BigInt denominator) {
  var n = numerator;
  var d = denominator;
  if (d.isNegative) {
    n = -n;
    d = -d;
  }
  final quotient = n ~/ d;
  final remainder = n.remainder(d);
  if (remainder == BigInt.zero) return quotient.toInt();
  final roundsAway = remainder.abs() * BigInt.two >= d;
  if (!roundsAway) return quotient.toInt();
  return (n.isNegative ? quotient - BigInt.one : quotient + BigInt.one).toInt();
}

/// `+12.34`, `-0.01`, `0.00` from hundredths.
String _signedTwoDecimals(int hundredths) {
  final sign = hundredths > 0 ? '+' : (hundredths < 0 ? '-' : '');
  final magnitude = hundredths.abs();
  final fraction = (magnitude % 100).toString().padLeft(2, '0');
  return '$sign${magnitude ~/ 100}.$fraction';
}
