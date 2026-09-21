/// The values a chart plots (Phase 6 Slice 5, D-268).
///
/// A chart is handed figures that `domain/finance` has already decided. What this file
/// adds is the one thing a renderer needs and a domain figure does not have: a `double`
/// coordinate. The whole design turns on the direction of that conversion.
///
/// ```
///     exact Money  ──derive──▶  double coordinate      allowed, one way
///     double coordinate  ──▶  Money                    does not exist here
/// ```
///
/// [ChartAmount] has **no constructor that takes a coordinate**. Its [ChartAmount.plotted]
/// is a getter over [ChartAmount.source], and its [ChartAmount.label] is the string the
/// production formatter produced from that same source. So a tooltip, an axis tick or a
/// readout is never a number a renderer handed back — it is the figure the engine
/// computed, printed the way every other surface prints it. This is the move D-094 made
/// for `RevenueTaxFacts` and D-150 for the revenue attachment schema: make the mistake
/// unavailable rather than discouraged.
///
/// Coordinates are in **paise**, so they stay whole. A `double` holds every integer below
/// 2^53 exactly — about ₹90,07,19,92,54,740 — so no figure this business will ever record
/// loses a paisa on the way to the screen. Axis labels never come from a coordinate: they
/// are computed from the integer paise of the tick that produced it.
library;

import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// An exact amount, its printed form, and the coordinate derived from it.
final class ChartAmount {
  const ChartAmount._({required this.source, required this.label});

  /// The amount, formatted by the application's own formatter.
  ///
  /// [formatter] defaults to the same one a table cell uses, so a figure reads identically
  /// wherever it appears. A caller may pass [MoneyFormatter.wholeRupees] for a headline,
  /// and may not pass anything that is not one of the application's formatters — there is
  /// no chart-specific money formatting in this project.
  factory ChartAmount.money(
    Money source, {
    MoneyFormatter formatter = MoneyFormatter.standard,
  }) => ChartAmount._(source: source, label: formatter.format(source));

  /// The canonical figure. Everything else here is derived from it.
  final Money source;

  /// What is printed — in a tooltip, a readout or beside a bar.
  final String label;

  /// The plotted coordinate, in paise. Derived, never supplied.
  double get plotted => source.paise.toDouble();

  bool get isNegative => source.isNegative;
  bool get isZero => source.isZero;

  @override
  String toString() => 'ChartAmount($label)';
}

/// A prepared percentage or percentage-point figure.
///
/// [scaled] is the exact figure × 10^[scale], as `domain/finance` produces it —
/// `MarginMovement.displayedPointsScaled(2)` gives `120` for `+1.20 pp`. [label] is the
/// text that domain layer already prepared; nothing here re-derives a sign, a suffix or a
/// precision, which is why no coordinate can reproduce it.
final class ChartPercent {
  const ChartPercent({
    required this.scaled,
    required this.scale,
    required this.label,
  });

  final int scaled;
  final int scale;
  final String label;

  double get plotted {
    var divisor = 1;
    for (var i = 0; i < scale; i++) {
      divisor *= 10;
    }
    return scaled / divisor;
  }

  bool get isNegative => scaled < 0;

  @override
  String toString() => 'ChartPercent($label)';
}

/// One position on a chart: a figure, or the statement that there is none.
sealed class ChartPoint {
  const ChartPoint({required this.label, required this.partial});

  /// What the position is called — a date, a bucket, a property. Supplied by the caller,
  /// because this layer formats money and nothing else (see the guard).
  final String label;

  /// A clipped week or month, so a surface never shows an unfinished point as finished
  /// and never stretches it to a notional whole one (D-263).
  final bool partial;
}

/// A real figure for a real position. A zero here is a real zero.
final class ChartPlotted extends ChartPoint {
  const ChartPlotted({
    required super.label,
    required this.amount,
    super.partial = false,
  });

  final ChartAmount amount;

  @override
  String toString() => 'ChartPlotted($label: ${amount.label})';
}

/// No figure for this position, and none invented for it.
///
/// It is not zero, not the neighbours' average and not carried forward: a flat segment
/// drawn across missing data is indistinguishable from a real trading lull, and the reader
/// has no way to tell (D-263). It carries **no amount at all**, so nothing downstream can
/// accidentally plot one.
final class ChartAbsent extends ChartPoint {
  const ChartAbsent({
    required super.label,
    required this.reason,
    super.partial = false,
  });

  /// Why there is no figure, in words a reader can act on.
  final String reason;

  @override
  String toString() => 'ChartAbsent($label: $reason)';
}

// ── The axis ────────────────────────────────────────────────────────────────

/// One tick: an exact figure, and the coordinate that positions it.
final class ChartAxisTick {
  const ChartAxisTick({required this.paise, required this.label});

  final int paise;
  final String label;

  double get plotted => paise.toDouble();

  @override
  String toString() => 'ChartAxisTick($label)';
}

/// The plotted range, and the ticks that annotate it.
///
/// **The range always includes zero.** A truncated value axis exaggerates variation — a
/// month of Net Sales between ₹70,000 and ₹80,000 drawn from ₹70,000 looks like a collapse
/// — and this is a management report, not a pitch (spec §20). Anchoring at zero is also
/// what gives an Operating Profit chart a baseline to draw a loss beneath.
final class ChartAxis {
  const ChartAxis._({
    required this.minPaise,
    required this.maxPaise,
    required this.ticks,
  });

  final int minPaise;
  final int maxPaise;

  /// In ascending order. Every label is formatted from that tick's own integer paise.
  final List<ChartAxisTick> ticks;

  /// Always true: the range is anchored at zero.
  bool get includesZero => minPaise <= 0 && maxPaise >= 0;

  /// The full plotted span, never zero — a flat series still needs a height to draw in.
  int get spanPaise => maxPaise - minPaise;

  /// The label for a coordinate this axis itself produced, or null.
  ///
  /// Matched against the coordinates the ticks derived, so a coordinate that is not a tick
  /// is never turned into a figure.
  String? labelFor(double plotted) {
    for (final tick in ticks) {
      if (tick.plotted == plotted) return tick.label;
    }
    return null;
  }

  /// The axis for [amounts], anchored at zero.
  static ChartAxis forAmounts(Iterable<Money> amounts) {
    var min = 0;
    var max = 0;
    for (final amount in amounts) {
      if (amount.paise < min) min = amount.paise;
      if (amount.paise > max) max = amount.paise;
    }
    // Already ascending by construction — the range is anchored at zero, so
    // `min <= 0 <= max` — and a set keeps insertion order, so nothing is sorted here.
    final at = <int>{min, if (min < 0 && max > 0) 0, max}.toList();
    return ChartAxis._(
      minPaise: min,
      maxPaise: max,
      ticks: List.unmodifiable([
        for (final paise in at)
          ChartAxisTick(
            paise: paise,
            label: MoneyFormatter.wholeRupees.format(Money.fromPaise(paise)),
          ),
      ]),
    );
  }

  @override
  String toString() =>
      'ChartAxis($minPaise … $maxPaise, ${ticks.length} ticks)';
}
