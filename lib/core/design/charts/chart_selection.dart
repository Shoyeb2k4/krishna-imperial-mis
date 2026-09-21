/// What a reader is looking at, and where the plot area ends (Phase 6 Slice 5, D-268).
///
/// [ChartSelection] is the one place a touched or hovered position becomes a figure, and
/// it does so by **index**: the renderer says *which* mark was touched, and the exact
/// figure is looked up in the points the domain supplied. Nothing here reads a coordinate,
/// a bar height or a pixel, which is what makes it impossible for a tooltip and a table to
/// disagree about the same amount.
///
/// One mechanism serves both platforms. fl_chart reports a mouse hover on Windows and a
/// touch on Android through the same callback, so there is no second interaction model to
/// keep in step — the discipline D-232 settled for the P&L wording, applied to gestures.
/// Arrow keys move the same selection, so the chart is usable from the keyboard on the
/// finance workstation.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:krishna_mis/core/design/charts/chart_values.dart';

@immutable
final class ChartSelection {
  const ChartSelection(this.index);

  /// Nothing selected.
  static const ChartSelection none = ChartSelection(null);

  final int? index;

  /// The last position that has a figure, so a dashboard opens showing its most recent
  /// point rather than an empty readout. A series of nothing but gaps selects nothing.
  static ChartSelection initialFor(List<ChartPoint> points) {
    for (var i = points.length - 1; i >= 0; i--) {
      if (points[i] is ChartPlotted) return ChartSelection(i);
    }
    return none;
  }

  ChartPoint? pointIn(List<ChartPoint> points) {
    final at = index;
    if (at == null || at < 0 || at >= points.length) return null;
    return points[at];
  }

  /// A selection clamped to [points]; out of range selects nothing.
  ChartSelection movedTo(int? next, List<ChartPoint> points) {
    if (next == null || next < 0 || next >= points.length) return none;
    return ChartSelection(next);
  }

  /// Left and right step through the positions; home and end jump to the ends.
  ///
  /// Gaps are stepped onto deliberately: a reader moving along the series should be told
  /// a point is missing, not have it skipped as though the series were shorter.
  KeyEventResult handleKey(
    KeyEvent event,
    List<ChartPoint> points, {
    required void Function(int?) onChange,
  }) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (points.isEmpty) return KeyEventResult.ignored;
    final at = index ?? 0;
    final next = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => at - 1,
      LogicalKeyboardKey.arrowRight => at + 1,
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => points.length - 1,
      _ => null,
    };
    if (next == null) return KeyEventResult.ignored;
    if (next < 0 || next >= points.length) return KeyEventResult.handled;
    onChange(next);
    return KeyEventResult.handled;
  }

  /// The category a horizontal position names.
  ///
  /// This is the **only** conversion from a coordinate in the whole layer, and it is a
  /// conversion to an *index* — the position along the category axis, which carries no
  /// money. A figure is never obtained this way: the index is looked up in the points the
  /// domain supplied, and what is printed is the label that arrived with them.
  static int indexAt(double position) => position.round();

  /// What a tooltip prints for the mark at [index]: the position's name and its
  /// **prepared** figure. Never a formatted coordinate.
  static String tooltipTextFor(List<ChartPoint> points, int index) {
    if (index < 0 || index >= points.length) return '';
    return switch (points[index]) {
      ChartPlotted(:final label, :final amount) => '$label\n${amount.label}',
      ChartAbsent(:final label) => '$label\nNot available',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ChartSelection && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => 'ChartSelection($index)';
}

/// The plotted extent of a value axis, and the step its ticks fall on.
///
/// The step is a **quarter of the data span**, which is what makes an axis label
/// resolvable at all: fl_chart asks for a label at `minY + i × interval`, so the ticks
/// [ChartAxis] computed are only ever printed if those are the positions it generates.
/// A quarter-span step places the data's own minimum and maximum exactly on generated
/// positions, and the arithmetic is exact — every value is a quarter-multiple of an
/// integer, well inside a double's range.
///
/// The zero end is never padded, so a baseline sits exactly on zero and a bar drawn to it
/// measures what it should. The other end gets one step of headroom so the largest mark is
/// not welded to the frame. A flat series still gets a height, because a chart with no
/// extent cannot be drawn at all.
@immutable
final class ChartBounds {
  const ChartBounds({
    required this.minY,
    required this.maxY,
    required this.interval,
  });

  final double minY;
  final double maxY;

  /// The spacing of generated grid lines and axis labels.
  final double interval;

  static ChartBounds of(ChartAxis axis) {
    final min = axis.minPaise;
    final max = axis.maxPaise;
    final span = axis.spanPaise;
    final step = span == 0 ? 1.0 : span / 4;

    return ChartBounds(
      minY: min < 0 ? min - step : 0.0,
      maxY: max > 0
          ? max + step
          : min < 0
          ? 0.0
          : 1.0,
      interval: step,
    );
  }
}
