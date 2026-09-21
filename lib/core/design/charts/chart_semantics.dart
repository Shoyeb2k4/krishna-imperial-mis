/// What a chart says when nobody can see it (Phase 6 Slice 5, D-268).
///
/// Every chart in this product carries a description sufficient to understand it without
/// looking: what it is, which period it covers, which series it plots, what each figure
/// is, and where a figure is missing. That is an accessibility requirement and it is also
/// the plainest possible statement of the rule in spec §20 — **profit and loss are never
/// communicated by colour alone**. A screen reader gets the word "loss"; so does anyone
/// reading a printed page in black and white.
///
/// The figures here are the prepared [ChartAmount.label] strings, so a description can
/// never disagree with what is drawn beside it, and a missing point states that it is
/// missing rather than contributing a figure of its own.
library;

import 'package:krishna_mis/core/design/charts/chart_series.dart';
import 'package:krishna_mis/core/design/charts/chart_values.dart';

abstract final class ChartSemantics {
  /// A trend — the Net Sales line, or the Operating Profit bars.
  static String trend({
    required String title,
    required String periodLabel,
    required TrendChartData data,
  }) => switch (data) {
    TrendChartRefused(:final reason) => _sentences([
      title,
      periodLabel,
      reason,
    ]),
    TrendChartReady(
      :final measure,
      :final grain,
      :final points,
      :final hasGap,
    ) =>
      _sentences([
        title,
        periodLabel,
        '${measure.chartLabel}, ${grain.chartLabel}',
        '${points.length} points',
        for (final point in points) _point(point, spansZero: measure.spansZero),
        if (hasGap)
          '${points.whereType<ChartAbsent>().length} of ${points.length} '
              'points are not available and are shown as gaps',
      ]),
  };

  /// A ranked horizontal bar chart — revenue mix, top expense categories, departments.
  static String ranked({
    required String title,
    required String periodLabel,
    required RankedBarChartData data,
  }) => switch (data) {
    RankedBarChartRefused(:final reason) => _sentences([
      title,
      periodLabel,
      reason,
    ]),
    RankedBarChartReady(:final lines, :final total) => _sentences([
      title,
      periodLabel,
      '${lines.length} lines',
      for (final line in lines) '${line.label}: ${line.amount.label}',
      'Total: ${total.label}',
    ]),
  };

  /// Properties side by side.
  static String comparison({
    required String title,
    required String periodLabel,
    required ComparisonChartData data,
  }) => _sentences([
    title,
    periodLabel,
    'Series: ${data.seriesNames.join(', ')}',
    for (final group in data.groups)
      '${group.label}: ${[for (var i = 0; i < data.seriesNames.length; i++) '${data.seriesNames[i]} ${group.values[i]?.label ?? 'not available'}'].join(', ')}',
  ]);

  /// What a selected point announces — the same prepared figure the readout prints.
  static String selection(ChartPoint point, {required bool spansZero}) =>
      _point(point, spansZero: spansZero);

  /// The note under a plot: how many positions have no figure, and how many cover a
  /// shortened period. Both are stated rather than left to be inferred from the drawing,
  /// because neither is visible in a mark that simply is not there (D-263).
  static String? footnote(List<ChartPoint> points) {
    final gaps = points.whereType<ChartAbsent>().length;
    final partial = points.where((p) => p.partial).length;
    final notes = [
      if (gaps > 0)
        '$gaps of ${points.length} '
            '${gaps == 1 ? 'point is' : 'points are'} not available, and '
            '${gaps == 1 ? 'is' : 'are'} shown as a gap rather than as zero.',
      if (partial > 0)
        '$partial ${partial == 1 ? 'point covers' : 'points cover'} a partial '
            'period, shown as recorded and not scaled up to a whole one.',
    ];
    return notes.isEmpty ? null : notes.join(' ');
  }

  static String _point(
    ChartPoint point, {
    required bool spansZero,
  }) => switch (point) {
    ChartPlotted(:final label, :final amount, :final partial) => [
      '$label: ${amount.label}',
      // Never colour alone: the sign is stated in words for a measure that can be
      // either (spec §20). A zero is neither, and is said so.
      if (spansZero)
        amount.isZero
            ? 'break-even'
            : amount.isNegative
            ? 'loss'
            : 'profit',
      if (partial) 'partial period',
    ].join(', '),
    ChartAbsent(:final label, :final partial) => [
      '$label: not available',
      if (partial) 'partial period',
    ].join(', '),
  };

  static String _sentences(List<String> parts) =>
      parts.where((p) => p.trim().isNotEmpty).map((p) => '$p.').join(' ');
}
