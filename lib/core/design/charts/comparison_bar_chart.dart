/// Property comparison — an approved chart family (Phase 6 Slice 5, D-268).
///
/// Grouped bars: one group per property, one bar per series. It is the only chart family
/// that plots more than one series at a time, so it is the one where "never colour alone"
/// has to be built in rather than assumed: each series is named in the legend, carries its
/// own marker shape there, and is announced by name in the description.
///
/// A figure a property could not supply is **absent** — no bar is drawn and the group says
/// so. A zero-height bar would read as "this property earned nothing", which is a
/// different statement from "this could not be established" (D-163).
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

class ComparisonBarChart extends StatefulWidget {
  const ComparisonBarChart({
    required this.title,
    required this.periodLabel,
    required this.data,
    required this.styles,
    super.key,
    this.height,
    this.onSelectionChanged,
    this.onActivated,
  });

  final String title;
  final String periodLabel;
  final ComparisonChartData data;

  /// One style per series, parallel to [ComparisonChartData.seriesNames].
  final List<ChartSeriesStyle> styles;

  final double? height;
  final ValueChanged<ChartPoint?>? onSelectionChanged;

  /// The **group** a reader opened — by tap, Enter, Space or the Open action — never by
  /// hovering. Null when the surface opens nothing (Phase 6 Slice 9).
  final ValueChanged<int>? onActivated;

  @override
  State<ComparisonBarChart> createState() => _ComparisonBarChartState();
}

class _ComparisonBarChartState extends State<ComparisonBarChart> {
  ChartSelection _selection = ChartSelection.none;

  @override
  void didUpdateWidget(ComparisonBarChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.data, widget.data)) _selection = ChartSelection.none;
  }

  /// One point per group, carrying that property's first available figure, so the readout
  /// states an exact amount rather than a coordinate.
  List<ChartPoint> _pointsFor(int seriesIndex) => [
    for (final group in widget.data.groups)
      switch (group.values[seriesIndex]) {
        null => ChartAbsent(label: group.label, reason: 'Not available'),
        final amount => ChartPlotted(label: group.label, amount: amount),
      },
  ];

  int _series = 0;

  void _select(int groupIndex, int seriesIndex) {
    final points = _pointsFor(seriesIndex);
    final next = _selection.movedTo(groupIndex, points);
    if (next == _selection && seriesIndex == _series) return;
    setState(() {
      _selection = next;
      _series = seriesIndex;
    });
    widget.onSelectionChanged?.call(next.pointIn(points));
  }

  void _activate(int? groupIndex) {
    final open = widget.onActivated;
    if (open == null || groupIndex == null) return;
    if (groupIndex < 0 || groupIndex >= widget.data.groups.length) return;
    open(groupIndex);
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
    final semantics = ChartSemantics.comparison(
      title: widget.title,
      periodLabel: widget.periodLabel,
      data: data,
    );

    if (data.isEmpty) {
      return ChartUnavailable(
        title: widget.title,
        periodLabel: widget.periodLabel,
        reason: 'No property is available to compare for this period.',
        semanticsLabel: semantics,
        height: widget.height ?? ChartTheme.plotHeight,
      );
    }

    final points = _pointsFor(_series);

    return ChartFrame(
      title: widget.title,
      periodLabel: widget.periodLabel,
      semanticsLabel: semantics,
      series: widget.styles,
      readout: ChartReadout(point: _selection.pointIn(points)),
      footnote: data.hasAbsent
          ? 'A property with no figure for this period draws no bar, and is not '
                'shown as zero.'
          : null,
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
              return _selection.handleKey(
                event,
                points,
                onChange: (index) => _select(index ?? 0, _series),
              );
            },
            child: SizedBox(
              height:
                  widget.height ??
                  (narrow
                      ? ChartTheme.compactPlotHeight
                      : ChartTheme.plotHeight),
              child: BarChart(
                _chartData(narrow: narrow),
                duration: ChartTheme.motion,
              ),
            ),
          );
        },
      ),
    );
  }

  BarChartData _chartData({required bool narrow}) {
    final data = widget.data;
    final bounds = ChartBounds.of(data.axis);

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
              final label = data.axis.labelFor(value);
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
            reservedSize: 28,
            getTitlesWidget: (value, meta) {
              final index = ChartSelection.indexAt(value);
              if (index < 0 || index >= data.groups.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  data.groups[index].label,
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
        for (var g = 0; g < data.groups.length; g++)
          BarChartGroupData(
            x: g,
            barsSpace: AppSpacing.xs,
            barRods: [
              for (var s = 0; s < data.seriesNames.length; s++)
                if (data.groups[g].values[s] case final amount?)
                  BarChartRodData(
                    fromY: 0,
                    toY: amount.plotted,
                    width: narrow ? 10 : 16,
                    borderRadius: BorderRadius.zero,
                    color: widget.styles[s].color,
                  ),
            ],
          ),
      ],
      barTouchData: BarTouchData(
        touchCallback: (event, response) {
          final spot = response?.spot;
          if (!event.isInterestedForInteractions || spot == null) return;
          _select(spot.touchedBarGroupIndex, spot.touchedRodDataIndex);
          if (event is FlTapUpEvent) _activate(spot.touchedBarGroupIndex);
        },
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => AppColors.ink,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            // The exact prepared figure, by index — never the rod's height.
            final points = _pointsFor(
              rodIndex.clamp(0, data.seriesNames.length - 1),
            );
            final name = data
                .seriesNames[rodIndex.clamp(0, data.seriesNames.length - 1)];
            return BarTooltipItem(
              '$name\n${ChartSelection.tooltipTextFor(points, groupIndex)}',
              AppTypography.caption.copyWith(color: AppColors.inkInverse),
            );
          },
        ),
      ),
    );
  }
}
