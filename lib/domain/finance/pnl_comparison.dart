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
/// * **Operating Profit with a negative side → no percentage.** A sign change is stated in
///   words — *Moved from loss to profit* — beside the exact rupee movement.
/// * **Operating Margin moves in percentage points**, exactly: 12.30% → 14.10% is
///   +1.80 pp, never "14.63% growth".
///
/// ## Ordinary money figures, and negative values (D-256, final)
///
/// Gross Sales, GST, Net Sales and Operating Expenses show a percentage change **only
/// when**:
///
/// ```
///     previous > 0   AND   current >= 0
/// ```
///
/// so `previous == 0` gives N/A, `previous < 0` gives no percentage, and `current < 0`
/// gives no percentage. Whenever either side is negative the exact rupee movement is still
/// shown and a surface may word the direction; what it must not show is a conventional
/// growth percentage, because a percentage measured against a negative base reads backwards
/// — −₹100 → +₹100 would print "−200%" for an improvement.
///
/// Operating Profit keeps its own, stricter rules above; it is the one figure whose
/// negatives are ordinary.
///
/// ## Exact arithmetic, and what is displayed
///
/// Percentages and percentage points are exact rationals over paise, rounded once, half
/// away from zero, at the precision the caller prints. The margin movement compares two
/// ratios, so its cross product can pass 2^63 at crore scale; it is computed in [BigInt].
///
/// The **canonical** margin movement stays that exact figure. What a surface *prints*
/// beside two printed margins is [MarginMovement.displayedPointsScaled], the difference of
/// the two rounded margins, so the three figures on screen reconcile (D-264). The exact
/// value is not replaced by it.
library;

import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// Which side of a comparison could not be established.
enum ComparisonSide { current, previous, both }

/// Why a percentage change is not shown.
///
/// The first three are the ordinary-figure rule (D-256), reported in the order they are
/// tested, so a comparison whose two sides are both negative names the base — which is the
/// condition a reader can do something about.
enum PercentNotApplicableReason {
  /// The previous figure was zero. There is no base to measure against.
  previousZero,

  /// An ordinary figure's previous value was negative (D-256).
  previousNegative,

  /// An ordinary figure's current value is negative (D-256).
  currentNegative,

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

  /// `current − previous`, exactly. Always shown, whatever the percentage does (D-256).
  Money get change => current - previous;

  /// Either figure is below zero, so no conventional growth percentage is shown.
  ///
  /// Derived here rather than by each surface, so wording that depends on it cannot be
  /// written against a different test from the one that suppressed the percentage.
  bool get eitherSideNegative => current.isNegative || previous.isNegative;
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

/// The change between two margins, in percentage points — exactly, and as displayed.
///
/// **The canonical figure is [pointsScaled]**, taken from the two exact ratios:
///
/// ```
///   pp = (p1/n1 − p0/n0) × 100 = (p1·n0 − p0·n1) × 100 ÷ (n1·n0)
/// ```
///
/// **What a surface prints is [displayedPointsScaled]** — the difference of the two
/// *rounded* margins, at the same precision those margins are printed to (D-264). The two
/// answer different questions and both are kept:
///
/// ```
///   exact current  1/3        printed  33.33%
///   exact previous 1/6        printed  16.67%
///
///   pointsScaled(2)           1667     +16.67 pp   the exact movement
///   displayedPointsScaled(2)  1666     +16.66 pp   what reconciles on screen
/// ```
///
/// Showing the exact movement beside two rounded margins leaves a visible 0.01 pp that a
/// reader cannot account for, and a management report whose three printed figures do not
/// add up invites exactly the wrong kind of doubt. This is presentation reconciliation
/// only: the exact value is still here, and nothing downstream computes from the rounded
/// one. Each rounding moves a figure by at most half a unit, so the two can never differ by
/// more than one unit at the display precision — asserted, not assumed.
final class MarginMovement extends MarginComparison {
  const MarginMovement({required this.current, required this.previous});

  final MarginRatio current;
  final MarginRatio previous;

  /// The **exact** movement in percentage points × 10^[scale], rounded once, half away
  /// from zero. The canonical figure; not what a surface prints.
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

  /// The movement **as displayed**: the difference of the two margins each rounded to
  /// [scale], so `displayed = displayCurrent − displayPrevious` by construction.
  int displayedPointsScaled(int scale) =>
      current.percentageScaled(scale) - previous.percentageScaled(scale);

  /// What a surface prints beside the two printed margins. Reconciles with them exactly.
  @override
  String get displayTwoDecimals =>
      '${_signedTwoDecimals(displayedPointsScaled(2))} pp';

  /// The exact movement, formatted. Available for a diagnostic or an export that states
  /// the unrounded figure; never the one shown beside two rounded margins.
  String get exactDisplayTwoDecimals =>
      '${_signedTwoDecimals(pointsScaled(2))} pp';
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

  /// Gross Sales, GST, Net Sales and Operating Expenses (D-256, final).
  ///
  /// A percentage only when `previous > 0 && current >= 0`. The rupee movement is carried
  /// in every case.
  static MoneyComparison _ordinary(Money current, Money previous) {
    final PercentChange percent;
    if (previous.isZero) {
      percent = const PercentChangeNotApplicable(
        PercentNotApplicableReason.previousZero,
      );
    } else if (previous.isNegative) {
      percent = const PercentChangeNotApplicable(
        PercentNotApplicableReason.previousNegative,
      );
    } else if (current.isNegative) {
      percent = const PercentChangeNotApplicable(
        PercentNotApplicableReason.currentNegative,
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
    );
  }

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
