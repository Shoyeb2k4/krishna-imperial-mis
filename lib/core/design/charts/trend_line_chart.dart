/// The Net Sales trend — an approved chart family (Phase 6 Slice 5, D-268).
///
/// A line over one [TrendChartData]. It plots the figures it was handed and computes
/// nothing: no total, no average, no smoothing, no interpolation across a missing point.
///
/// ## A gap is a break in the line
///
/// A [ChartAbsent] becomes [FlSpot.nullSpot], which fl_chart renders as an actual break.
/// It is not zero, not the neighbours' average and not carried forward — a continuous line
/// drawn across missing data is indistinguishable from a real trading lull, and the reader
/// has no way to tell (D-263).
///
/// ## A figure is never read back from a coordinate
///
/// Both the tooltip and the readout take the touched **index** — `spotIndex`, which
/// fl_chart hands back — and look up `points[index]`, printing its prepared
/// [ChartAmount.label]. Nothing formats `spot.y`. That is what keeps a chart's figure the
/// same object as the P&L's: the coordinate positions a mark, and the label states a fact.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/widgets.dart';
import 'package:krishna_mis/core/design/charts/chart_frame.dart';
import 'package:krishna_mis/core/design/charts/chart_selection.dart';
import 'package:krishna_mis/core/design/charts/chart_semantics.dart';
import 'package:krishna_mis/core/design/charts/chart_series.dart';
import 'package:krishna_mis/core/design/charts/chart_theme.dart';
import 'package:krishna_mis/core/design/charts/chart_values.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

class TrendLineChart extends StatefulWidget {
  const TrendLineChart({
    required this.title,
    required this.periodLabel,
    required this.data,
    super.key,
    this.style = ChartTheme.netSales,
    this.height,
    this.onSelectionChanged,
    this.onActivated,
  });

  final String title;
  final String periodLabel;
  final TrendChartData data;
  final ChartSeriesStyle style;
  final double? height;

  /// The point a reader is looking at, for a surface that wants to mirror it elsewhere.
  final ValueChanged<ChartPoint?>? onSelectionChanged;

  /// The position a reader opened — by tap, Enter, Space or the Open action — never by
  /// hovering. Null when the surface opens nothing (Phase 6 Slice 9).
  final ValueChanged<int>? onActivated;

  @override
  State<TrendLineChart> createState() => _TrendLineChartState();
}

class _TrendLineChartState extends State<TrendLineChart> {
  late ChartSelection _selection;

  @override
  void initState() {
    super.initState();
    _selection = ChartSelection.initialFor(_points);
  }

  @override
  void didUpdateWidget(TrendLineChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.data, widget.data)) {
      _selection = ChartSelection.initialFor(_points);
    }
  }

  List<ChartPoint> get _points => switch (widget.data) {
    TrendChartReady(:final points) => points,
    TrendChartRefused() => const [],
  };

  void _select(int? index) {
    final next = _selection.movedTo(index, _points);
    if (next == _selection) return;
    setState(() => _selection = next);
    widget.onSelectionChanged?.call(next.pointIn(_points));
  }

  void _activate(int? index) {
    final open = widget.onActivated;
    if (open == null || index == null) return;
    if (_selection.movedTo(index, _points).pointIn(_points) is! ChartPlotted) {
      return;
    }
    open(index);
  }

  /// Owned here so a chart is reachable from the keyboard on the finance
  /// workstation, and so a test can drive the same selection a pointer drives.
  final FocusNode focusNode = FocusNode(debugLabel: 'chart');

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final semantics = ChartSemantics.trend(
      title: widget.title,
      periodLabel: widget.periodLabel,
      data: data,
    );

    if (data is TrendChartRefused) {
      return ChartUnavailable(
        title: widget.title,
        periodLabel: widget.periodLabel,
        reason: data.reason,
        semanticsLabel: semantics,
        height: widget.height ?? ChartTheme.plotHeight,
      );
    }

    final ready = data as TrendChartReady;
    final points = ready.points;
    final spansZero = ready.measure.spansZero;

    return ChartFrame(
      title: widget.title,
      periodLabel: widget.periodLabel,
      semanticsLabel: semantics,
      series: [widget.style],
      readout: ChartReadout(
        point: _selection.pointIn(points),
        spansZero: spansZero,
      ),
      footnote: _footnote(ready),
      action: widget.onActivated == null
          ? null
          : ChartOpenAction(
              point: _selection.pointIn(points),
              onOpen: () => _activate(_selection.index),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < ChartTheme.narrowWidth;
          return Focus(
            focusNode: focusNode,
            onKeyEvent: (node, event) {
              if (ChartSelection.isActivation(event) &&
                  widget.onActivated != null) {
                _activate(_selection.index);
                return KeyEventResult.handled;
              }
              return _selection.handleKey(event, points, onChange: _select);
            },
            child: SizedBox(
              height:
                  widget.height ??
                  (narrow
                      ? ChartTheme.compactPlotHeight
                      : ChartTheme.plotHeight),
              child: LineChart(
                _chartData(ready, narrow: narrow),
                duration: ChartTheme.motion,
              ),
            ),
          );
        },
      ),
    );
  }

  String? _footnote(TrendChartReady ready) =>
      ChartSemantics.footnote(ready.points);

  LineChartData _chartData(TrendChartReady ready, {required bool narrow}) {
    final points = ready.points;
    final bounds = ChartBounds.of(ready.axis);

    return LineChartData(
      minX: -0.5,
      maxX: points.length - 0.5,
      minY: bounds.minY,
      maxY: bounds.maxY,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        drawVerticalLine: false,
        getDrawingHorizontalLine: (value) => const FlLine(
          color: ChartTheme.grid,
          strokeWidth: ChartTheme.gridWidth,
        ),
        horizontalInterval: bounds.interval,
      ),
      // The zero baseline is a deliberate reference line, not whichever grid line
      // happens to land on zero. A generated grid does not promise to include zero at
      // all, and a reader has to be able to see which figures fell below it.
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: 0,
            color: ChartTheme.baseline,
            strokeWidth: ChartTheme.baselineWidth,
          ),
        ],
      ),
      borderData: FlBorderData(
        show: true,
        border: const Border(
          bottom: BorderSide(color: ChartTheme.border),
          left: BorderSide(color: ChartTheme.border),
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: !narrow,
            reservedSize: 72,
            interval: bounds.interval,
            getTitlesWidget: (value, meta) => _axisLabel(ready, value),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 1,
            getTitlesWidget: (value, meta) =>
                _bottomLabel(points, value, narrow: narrow),
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < points.length; i++)
              switch (points[i]) {
                // A break in the line, not a zero (D-263).
                ChartAbsent() => FlSpot.nullSpot,
                ChartPlotted(:final amount) => FlSpot(
                  i.toDouble(),
                  amount.plotted,
                ),
              },
          ],
          color: widget.style.color,
          barWidth: ChartTheme.lineWidth,
          dashArray: widget.style.dashArray,
          isStrokeCapRound: false,
          dotData: FlDotData(
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: ChartTheme.markerRadius,
              color: widget.style.color,
              strokeWidth: 0,
            ),
          ),
          belowBarData: BarAreaData(),
        ),
      ],
      lineTouchData: LineTouchData(
        touchCallback: (event, response) {
          final spots = response?.lineBarSpots;
          if (!event.isInterestedForInteractions ||
              spots == null ||
              spots.isEmpty) {
            return;
          }
          _select(spots.first.spotIndex);
          if (event is FlTapUpEvent) _activate(spots.first.spotIndex);
        },
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColors.ink,
          getTooltipItems: (spots) => [
            for (final spot in spots)
              // The exact prepared figure, looked up by index. Never `spot.y`.
              LineTooltipItem(
                ChartSelection.tooltipTextFor(points, spot.spotIndex),
                AppTypography.caption.copyWith(color: AppColors.inkInverse),
              ),
          ],
        ),
      ),
    );
  }

  Widget _axisLabel(TrendChartReady ready, double value) {
    final label = ready.axis.labelFor(value);
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Text(
        label,
        style: ChartTheme.axisLabel,
        textAlign: TextAlign.right,
        maxLines: 1,
      ),
    );
  }

  /// The first and last position only. Labelling every day of a month would overlap at
  /// any width, and an overlapping axis is worse than an unlabelled one.
  Widget _bottomLabel(
    List<ChartPoint> points,
    double value, {
    required bool narrow,
  }) {
    final index = ChartSelection.indexAt(value);
    if (index < 0 || index >= points.length) return const SizedBox.shrink();
    final isEdge = index == 0 || index == points.length - 1;
    if (!isEdge) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        points[index].label,
        style: ChartTheme.axisLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
