/// Revenue mix, top expense categories and department spending — three approved chart
/// families, one shape (Phase 6 Slice 5, D-268).
///
/// A ranked horizontal bar chart is a **list with a bar**: each line names a category and
/// states an exact figure, and the bar shows how the figures compare. So it is composed
/// from the design system's own text and a proportional fill rather than plotted on a
/// rotated cartesian axis, and the reason is a requirement rather than a preference:
///
/// * a category reads *Crystal Canopy Rooftop · Kirana & Pulses*, which as an axis tick at
///   360dp either truncates the name or takes a third of the plot away from the bars;
/// * **money must never be truncated or wrapped** — a truncated amount is a wrong amount
///   (the rule `MoneyText` has carried since Phase 1) — so a figure needs a real text slot
///   that is measured, not an axis label that is clipped to a reserved size.
///
/// fl_chart can draw horizontal bars, so nothing here is a workaround for something the
/// package cannot do; it is the right primitive for a ranked list, and the same models,
/// formatters, selection and description serve it as serve the cartesian charts.
///
/// ## What it never does
///
/// It does not rank, group, slice or sum. The order is the domain's order, the membership
/// is the domain's membership, and **Others is the domain's figure**, carried verbatim
/// (D-258). A [RankedBarChartRefused] — a set that did not reconcile — draws no financial
/// data at all, because a bar chart missing a category silently understates the rest.
library;

import 'package:flutter/widgets.dart';
import 'package:krishna_mis/core/design/components/figure_reflow.dart';
import 'package:krishna_mis/core/design/charts/chart_frame.dart';
import 'package:krishna_mis/core/design/charts/chart_selection.dart';
import 'package:krishna_mis/core/design/charts/chart_semantics.dart';
import 'package:krishna_mis/core/design/charts/chart_series.dart';
import 'package:krishna_mis/core/design/charts/chart_theme.dart';
import 'package:krishna_mis/core/design/charts/chart_values.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

class RankedBarChart extends StatefulWidget {
  const RankedBarChart({
    required this.title,
    required this.periodLabel,
    required this.data,
    super.key,
    this.onSelectionChanged,
    this.onActivated,
  });

  /// Keys a surface or a test finds a line by.
  static Key labelKey(int index) => Key('chart-ranked-label-$index');
  static Key valueKey(int index) => Key('chart-ranked-value-$index');
  static Key rowKey(int index) => Key('chart-ranked-row-$index');
  static Key barKey(int index) => Key('chart-ranked-bar-$index');

  final String title;
  final String periodLabel;
  final RankedBarChartData data;
  final ValueChanged<ChartPoint?>? onSelectionChanged;

  /// The row a reader opened — by tap, Enter or Space — never by hovering. Null when the
  /// surface opens nothing (Phase 6 Slice 9). Whether a row can be opened at all is the
  /// surface's answer: an Others remainder is not a line anybody can open.
  final ValueChanged<int>? onActivated;

  @override
  State<RankedBarChart> createState() => _RankedBarChartState();
}

class _RankedBarChartState extends State<RankedBarChart> {
  ChartSelection _selection = ChartSelection.none;

  @override
  void didUpdateWidget(RankedBarChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.data, widget.data)) {
      _selection = ChartSelection.none;
    }
  }

  List<ChartPoint> get _points => switch (widget.data) {
    RankedBarChartReady(:final lines) => [
      for (final line in lines)
        ChartPlotted(label: line.label, amount: line.amount),
    ],
    RankedBarChartRefused() => const [],
  };

  void _select(int? index) {
    final points = _points;
    final next = _selection.movedTo(index, points);
    if (next == _selection) return;
    setState(() => _selection = next);
    widget.onSelectionChanged?.call(next.pointIn(points));
  }

  void _activate(int? index) {
    final open = widget.onActivated;
    if (open == null || index == null) return;
    if (index < 0 || index >= _points.length) return;
    open(index);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final semantics = ChartSemantics.ranked(
      title: widget.title,
      periodLabel: widget.periodLabel,
      data: data,
    );

    if (data is RankedBarChartRefused) {
      return ChartUnavailable(
        title: widget.title,
        periodLabel: widget.periodLabel,
        reason: data.reason,
        semanticsLabel: semantics,
      );
    }

    final ready = data as RankedBarChartReady;
    final points = _points;

    return ChartFrame(
      title: widget.title,
      periodLabel: widget.periodLabel,
      semanticsLabel: semantics,
      readout: ChartReadout(point: _selection.pointIn(points)),
      footnote: 'Total: ${ready.total.label}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < ChartTheme.narrowWidth;
          return Focus(
            onKeyEvent: (node, event) {
              if (ChartSelection.isActivation(event) &&
                  widget.onActivated != null) {
                _activate(_selection.index);
                return KeyEventResult.handled;
              }
              return _selection.handleKey(event, points, onChange: _select);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < ready.lines.length; i++)
                  _RankedRow(
                    index: i,
                    line: ready.lines[i],
                    narrow: narrow,
                    selected: _selection.index == i,
                    onSelect: () => _select(i),
                    onOpen: widget.onActivated == null
                        ? null
                        : () {
                            _select(i);
                            _activate(i);
                          },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The narrowest a proportional bar is drawn beside its figure, so the figure always
/// leaves the bar some room to show proportion. Narrower than that, the figure moves to
/// its own line (D-286).
const double _minimumBarWidth = 24;

class _RankedRow extends StatelessWidget {
  const _RankedRow({
    required this.index,
    required this.line,
    required this.narrow,
    required this.selected,
    required this.onSelect,
    this.onOpen,
  });

  final int index;
  final RankedBarLine line;
  final bool narrow;
  final bool selected;
  final VoidCallback onSelect;

  /// A tap opens the row when the surface can open it; hovering only ever selects.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      line.label,
      key: RankedBarChart.labelKey(index),
      style: line.isOthers ? AppTypography.bodyMuted : AppTypography.body,
      // The whole name, wrapping onto a second line rather than being cut short
      // (D-269, D-286).
    );

    // The exact prepared figure. Never wrapped, never ellipsised, never abbreviated: a
    // truncated amount is a wrong amount.
    final value = Text(
      line.amount.label,
      key: RankedBarChart.valueKey(index),
      style: AppTypography.money,
      textAlign: TextAlign.right,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );

    final bar = _Bar(
      key: RankedBarChart.barKey(index),
      fraction: line.fractionOfWidest,
      isOthers: line.isOthers,
      negative: line.amount.isNegative,
    );

    return MouseRegion(
      onEnter: (_) => onSelect(),
      child: GestureDetector(
        key: RankedBarChart.rowKey(index),
        behavior: HitTestBehavior.opaque,
        onTap: onOpen ?? onSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? AppColors.brassWash : null,
            border: const Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          child: narrow
              // Stacked: the name on its own line, so it can never collide with the
              // figure however long the category is.
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    label,
                    const SizedBox(height: AppSpacing.xs),
                    // The bar and the figure share a line while the whole figure
                    // fits. At a large system font it does not: the figure then takes
                    // its own line at full size and the bar sits below it (D-286).
                    FigureReflow(
                      lead: bar,
                      figure: value,
                      minLeadWidth: _minimumBarWidth,
                      order: FigureReflowOrder.figureFirst,
                      runGap: AppSpacing.xs,
                    ),
                  ],
                )
              // Dense: name, bar and figure on one line, each in its own slot.
              // Where the whole figure does not fit beside them, it moves to a line
              // of its own at full size, never shrunk (D-286).
              : FigureReflow(
                  lead: Row(
                    children: [
                      SizedBox(width: 200, child: label),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: bar),
                    ],
                  ),
                  figure: value,
                  gap: AppSpacing.md,
                  minLeadWidth: 200 + AppSpacing.md + _minimumBarWidth,
                  stackedFigureAtEnd: true,
                ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.isOthers,
    required this.negative,
    super.key,
  });

  /// Geometry only. The figure beside it comes from the exact source, never from this.
  final double fraction;
  final bool isOthers;
  final bool negative;

  @override
  Widget build(BuildContext context) => Container(
    height: 10,
    decoration: const BoxDecoration(
      color: ChartTheme.rankedTrack,
      borderRadius: AppRadius.allSmall,
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: negative
                ? AppColors.negative
                : isOthers
                ? ChartTheme.othersBar
                : ChartTheme.rankedBar,
            borderRadius: AppRadius.allSmall,
            // A negative line is hatched as well as tinted, so its sign does not depend
            // on colour (spec §20). The figure beside it carries the minus regardless.
            border: negative
                ? const Border(
                    left: BorderSide(color: AppColors.negative, width: 3),
                  )
                : null,
          ),
        ),
      ),
    ),
  );
}
