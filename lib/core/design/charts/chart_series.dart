/// What each approved chart family is handed (Phase 6 Slice 5, D-268).
///
/// One adapter per family, each turning a **decided** domain result into positions and
/// prepared labels. None of them ranks, groups, sums, reconciles, or decides a period or a
/// grain: every one of those already happened in `domain/finance`, and a second answer
/// here would be a second answer to a financial question (D-255, D-258, D-263).
///
/// The adapters do exactly three things:
///
/// * carry a figure through, exactly, with the label the application's formatter produced;
/// * carry a refusal through, so a refused domain result draws **nothing** rather than an
///   empty chart that reads as ₹0;
/// * derive the plotted geometry — an axis anchored at zero, and a bar's share of the
///   widest line — which is presentation and nothing else.
///
/// **Dates are not formatted here.** A bucket's name arrives as a `bucketLabel` callback
/// from the surface, which already owns the application's date wording. The guard asserts
/// this layer contains no month table and no date arithmetic, so it cannot grow a second
/// date format.
library;

import 'package:krishna_mis/core/design/charts/chart_values.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// The name of a trended measure, as every other surface prints it.
///
/// A guard asserts each of these appears verbatim on both P&L surfaces, so a chart and a
/// figure table can never call the same measure two different things.
extension ChartMeasureLabel on TrendMeasure {
  String get chartLabel => switch (this) {
    TrendMeasure.netSales => 'Net Sales',
    TrendMeasure.expenses => 'Expenses',
    TrendMeasure.operatingProfit => 'Operating Profit',
  };

  /// Whether a value of this measure may legitimately fall below zero. Only Operating
  /// Profit does, and it is the one measure a chart draws on both sides of a baseline.
  bool get spansZero => this == TrendMeasure.operatingProfit;
}

extension ChartGrainLabel on TrendGrain {
  String get chartLabel => switch (this) {
    TrendGrain.daily => 'daily',
    TrendGrain.weekly => 'weekly',
    TrendGrain.monthly => 'monthly',
  };
}

// ── A trend: the Net Sales line, and the Operating Profit bars ──────────────

/// A trend, ready to draw — or the statement that there is nothing to draw.
sealed class TrendChartData {
  const TrendChartData();

  /// Adapts a [TrendSeries] the dashboard engine produced.
  ///
  /// Every [TrendGap] becomes a [ChartAbsent], which carries no amount at all. A series
  /// with no figure anywhere is **refused**: a chart of nothing but gaps is an empty plot
  /// area, and an empty plot area reads as a flat zero.
  static TrendChartData from(
    TrendSeries series, {
    required String Function(TrendBucket) bucketLabel,
    MoneyFormatter formatter = MoneyFormatter.standard,
    String absentReason = 'Not available — not yet synchronised',
  }) {
    final points = <ChartPoint>[
      for (final point in series.points)
        switch (point) {
          TrendValue(:final bucket, :final amount) => ChartPlotted(
            label: bucketLabel(bucket),
            partial: bucket.partial,
            amount: ChartAmount.money(amount, formatter: formatter),
          ),
          TrendGap(:final bucket) => ChartAbsent(
            label: bucketLabel(bucket),
            partial: bucket.partial,
            reason: absentReason,
          ),
        },
    ];

    final plotted = points.whereType<ChartPlotted>().toList(growable: false);
    if (plotted.isEmpty) {
      return TrendChartRefused(
        measure: series.measure,
        reason: 'No figure is available for this period.',
      );
    }

    return TrendChartReady._(
      measure: series.measure,
      grain: series.grain,
      points: List.unmodifiable(points),
      axis: ChartAxis.forAmounts(plotted.map((p) => p.amount.source)),
    );
  }
}

/// Nothing to draw, and a reason a reader can act on. Never an empty plot area.
final class TrendChartRefused extends TrendChartData {
  const TrendChartRefused({required this.measure, required this.reason});

  final TrendMeasure measure;
  final String reason;
}

final class TrendChartReady extends TrendChartData {
  const TrendChartReady._({
    required this.measure,
    required this.grain,
    required this.points,
    required this.axis,
  });

  final TrendMeasure measure;
  final TrendGrain grain;

  /// In range order, gaps included **in place**, so a break stays where it happened.
  final List<ChartPoint> points;

  final ChartAxis axis;

  bool get hasGap => points.any((p) => p is ChartAbsent);
  bool get hasPartial => points.any((p) => p.partial);

  Iterable<ChartPlotted> get plotted => points.whereType<ChartPlotted>();

  /// Whether any plotted figure is a loss, so a surface can say so in words.
  bool get hasNegative => plotted.any((p) => p.amount.isNegative);
  bool get hasPositive => plotted.any((p) => p.amount.source.isPositive);
}

// ── Ranked horizontal bars: revenue mix, top expenses, departments ──────────

/// One ranked line, its exact figure, and its share of the widest bar.
final class RankedBarLine {
  const RankedBarLine({
    required this.label,
    required this.amount,
    required this.fractionOfWidest,
    required this.isOthers,
  });

  final String label;
  final ChartAmount amount;

  /// `|amount| ÷ |widest|`, in `0..1`. **Geometry only.** It is never read back as a
  /// figure: what this line prints is [amount].label, which came from the exact source.
  final double fractionOfWidest;

  /// The exact remainder the domain computed, not a line of its own (D-258).
  final bool isOthers;
}

sealed class RankedBarChartData {
  const RankedBarChartData();

  /// Adapts a [TopNOutcome] the domain already ranked, grouped and reconciled.
  ///
  /// A refusal is carried through: if the complete set did not add up to its headline
  /// figure, the domain refuses and **no financial chart data is produced** — because a
  /// chart drawn from lines that do not reconcile silently hides whatever is missing
  /// (D-258).
  ///
  /// Nothing here re-ranks, re-slices or re-sums. The order is the domain's order, the
  /// membership is the domain's membership, and Others is the domain's figure.
  static RankedBarChartData fromTopN<L>(
    TopNOutcome<L> outcome, {
    required String Function(L) label,
    MoneyFormatter formatter = MoneyFormatter.standard,
  }) => switch (outcome) {
    TopNRefused<L>() => const RankedBarChartRefused(
      reason:
          'Categories not shown — they do not add up to the total exactly. Refresh.',
    ),
    TopNGrouped<L>(
      :final top,
      :final others,
      :final othersCount,
      :final total,
    ) =>
      _grouped(
        names: [for (final l in top) label(l.line)],
        amounts: [for (final l in top) l.amount],
        others: others,
        othersCount: othersCount,
        total: total,
        formatter: formatter,
      ),
  };

  static RankedBarChartData _grouped({
    required List<String> names,
    required List<Money> amounts,
    required Money? others,
    required int othersCount,
    required Money total,
    required MoneyFormatter formatter,
  }) {
    final all = <Money>[...amounts, ?others];
    var widest = 0;
    for (final amount in all) {
      final magnitude = amount.absolute.paise;
      if (magnitude > widest) widest = magnitude;
    }
    double fraction(Money amount) =>
        widest == 0 ? 0 : amount.absolute.paise / widest;

    return RankedBarChartReady._(
      lines: List.unmodifiable([
        for (var i = 0; i < names.length; i++)
          RankedBarLine(
            label: names[i],
            amount: ChartAmount.money(amounts[i], formatter: formatter),
            fractionOfWidest: fraction(amounts[i]),
            isOthers: false,
          ),
        if (others != null)
          RankedBarLine(
            label: othersCount == 1
                ? 'Others (1 category)'
                : 'Others ($othersCount categories)',
            amount: ChartAmount.money(others, formatter: formatter),
            fractionOfWidest: fraction(others),
            isOthers: true,
          ),
      ]),
      othersCount: othersCount,
      total: ChartAmount.money(total, formatter: formatter),
    );
  }
}

final class RankedBarChartRefused extends RankedBarChartData {
  const RankedBarChartRefused({required this.reason});
  final String reason;
}

final class RankedBarChartReady extends RankedBarChartData {
  const RankedBarChartReady._({
    required this.lines,
    required this.othersCount,
    required this.total,
  });

  /// In the domain's order: its top lines, then Others last where there is one.
  final List<RankedBarLine> lines;

  /// How many lines Others stands for, as the domain counted them.
  final int othersCount;

  /// The headline figure the complete set reconciled to.
  final ChartAmount total;
}

// ── Grouped bars: property comparison ───────────────────────────────────────

/// One group — a property — and one figure per series.
final class ComparisonGroup {
  const ComparisonGroup({required this.label, required this.values});

  final String label;

  /// Parallel to [ComparisonChartData.seriesNames]; a null entry is a figure that could
  /// not be established, and draws no bar rather than a zero-height one.
  final List<ChartAmount?> values;
}

/// Properties side by side, one bar per series in each group.
final class ComparisonChartData {
  ComparisonChartData({
    required this.seriesNames,
    required List<ComparisonGroup> groups,
  }) : groups = List.unmodifiable(groups),
       axis = ChartAxis.forAmounts([
         for (final group in groups)
           for (final value in group.values)
             if (value != null) value.source,
       ]) {
    for (final group in this.groups) {
      if (group.values.length != seriesNames.length) {
        throw ArgumentError(
          'group "${group.label}" has ${group.values.length} values for '
          '${seriesNames.length} series',
        );
      }
    }
  }

  final List<String> seriesNames;
  final List<ComparisonGroup> groups;
  final ChartAxis axis;

  bool get isEmpty => groups.isEmpty;
  bool get hasAbsent => groups.any((g) => g.values.any((v) => v == null));
}
