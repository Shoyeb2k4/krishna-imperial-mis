/// Monthly Operating Profit — an approved chart family (Phase 6 Slice 5, D-268).
///
/// Bars around a zero baseline. This is the one chart in the product whose figures are
/// routinely negative, and everything about it is shaped by that:
///
/// * **A loss is never clipped.** The axis is anchored at zero and spans whichever side
///   the figures reach, so a loss is drawn beneath the baseline at its real size.
/// * **Zero is visible.** The baseline is drawn stronger than the grid and labelled, so a
///   reader can see at a glance which months fell below it. A break-even month draws a
///   hairline at the baseline rather than nothing at all.
/// * **Profit and loss are never colour alone** (spec §20). The bar's side of the
///   baseline, the sign on the figure, the word in the readout and the word in the
///   description all say it; colour is the fourth cue, not the message.
///
/// A missing month is a **gap**: no rod is drawn and the position is labelled. It is never
/// a zero-height bar, which is exactly what a break-even month looks like.
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

class ProfitBarChart extends StatefulWidget {
  const ProfitBarChart({
    required this.title,
    required this.periodLabel,
    required this.data,
    super.key,
    this.height,
    this.onSelectionChanged,
    this.onActivated,
  });

  final String title;
  final String periodLabel;
  final TrendChartData data;
  final double? height;
  final ValueChanged<ChartPoint?>? onSelectionChanged;

  /// The position a reader opened — by tap, Enter, Space or the Open action — never by
  /// hovering. Null when the surface opens nothing (Phase 6 Slice 9).
  final ValueChanged<int>? onActivated;

  @override
  State<ProfitBarChart> createState() => _ProfitBarChartState();
}

class _ProfitBarChartState extends State<ProfitBarChart> {
  late ChartSelection _selection;

  @override
  void initState() {
    super.initState();
    _selection = ChartSelection.initialFor(_points);
  }

  @override
  void didUpdateWidget(ProfitBarChart old) {
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

    return ChartFrame(
      title: widget.title,
      periodLabel: widget.periodLabel,
      semanticsLabel: semantics,
      readout: ChartReadout(point: _selection.pointIn(points), spansZero: true),
      footnote: ChartSemantics.footnote(points),
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
              child: BarChart(
                _chartData(ready, narrow: narrow),
                duration: ChartTheme.motion,
              ),
            ),
          );
        },
      ),
    );
  }

  BarChartData _chartData(TrendChartReady ready, {required bool narrow}) {
    final points = ready.points;
    final bounds = ChartBounds.of(ready.axis);

    return BarChartData(
      minY: bounds.minY,
      maxY: bounds.maxY,
      alignment: BarChartAlignment.spaceAround,
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
            getTitlesWidget: (value, meta) {
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
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            getTitlesWidget: (value, meta) {
              final index = ChartSelection.indexAt(value);
              if (index < 0 || index >= points.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  points[index].label,
                  style: ChartTheme.axisLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < points.length; i++)
          BarChartGroupData(
            x: i,
            barRods: switch (points[i]) {
              // No rod at all. A zero-height rod is what break-even looks like, and a
              // month nobody could establish is not a month that broke even (D-263).
              ChartAbsent() => const [],
              ChartPlotted(:final amount) => [
                BarChartRodData(
                  fromY: 0,
                  toY: amount.plotted,
                  width: narrow ? 12 : 18,
                  borderRadius: BorderRadius.zero,
                  color: ChartTheme.bySign(
                    negative: amount.isNegative,
                    zero: amount.isZero,
                  ),
                ),
              ],
            },
          ),
      ],
      barTouchData: BarTouchData(
        touchCallback: (event, response) {
          final spot = response?.spot;
          if (!event.isInterestedForInteractions || spot == null) return;
          _select(spot.touchedBarGroupIndex);
          if (event is FlTapUpEvent) _activate(spot.touchedBarGroupIndex);
        },
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => AppColors.ink,
          // The exact prepared figure, looked up by the touched group's index.
          getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
            ChartSelection.tooltipTextFor(points, groupIndex),
            AppTypography.caption.copyWith(color: AppColors.inkInverse),
          ),
        ),
      ),
    );
  }
}
