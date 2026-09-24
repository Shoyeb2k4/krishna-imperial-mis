/// A label, bar or title beside an exact figure — and below it when they do not fit.
///
/// Money is never shrunk to fit, ellipsised, clipped or truncated (D-269, D-286). At a
/// large system font the figure can be wider than a row leaves it, and the layout gives
/// way instead: the figure moves to its own full-width line and the row grows taller.
/// At an ordinary text size the compact side-by-side composition is kept.
///
/// The choice is made from the figure's own one-line width, measured as the text it is,
/// at the reader's text size — never from a guess about how wide a figure "usually" is.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

/// Which child comes first when the two are stacked.
enum FigureReflowOrder {
  /// The lead (a label or title) above, the figure below it.
  leadFirst,

  /// The figure above, the lead (a proportional bar) below it.
  figureFirst,
}

class FigureReflow extends MultiChildRenderObjectWidget {
  FigureReflow({
    required Widget lead,
    required Widget figure,
    super.key,
    this.gap = AppSpacing.sm,
    this.runGap = AppSpacing.xxs,
    this.minLeadWidth = 0,
    this.leadFills = true,
    this.order = FigureReflowOrder.leadFirst,
    this.stackedFigureAtEnd = false,
    this.rowAlignment = CrossAxisAlignment.center,
    this.leadKeepsWords = true,
  }) : super(children: [lead, figure]);

  /// The space between the lead and the figure when they share a row.
  final double gap;

  /// The space between them when they are stacked.
  final double runGap;

  /// The narrowest the lead may be made beside the figure. A title that would be
  /// squeezed below this moves the figure to its own line instead.
  final double minLeadWidth;

  /// Whether the lead takes all the width the figure leaves it — a proportional bar
  /// does; a label need not.
  final bool leadFills;

  final FigureReflowOrder order;

  /// Whether a stacked figure sits at the end (right) of its line rather than the start.
  final bool stackedFigureAtEnd;

  /// How the two line up when they share a row: start, center or end.
  final CrossAxisAlignment rowAlignment;

  /// Whether the lead must be left room for its longest word. A title that shortens
  /// itself with an ellipsis reports its whole line as that word, so it opts out and
  /// relies on [minLeadWidth] alone.
  final bool leadKeepsWords;

  @override
  RenderFigureReflow createRenderObject(BuildContext context) =>
      RenderFigureReflow(
        gap: gap,
        runGap: runGap,
        minLeadWidth: minLeadWidth,
        leadFills: leadFills,
        order: order,
        stackedFigureAtEnd: stackedFigureAtEnd,
        rowAlignment: rowAlignment,
        leadKeepsWords: leadKeepsWords,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderFigureReflow renderObject,
  ) {
    renderObject
      ..gap = gap
      ..runGap = runGap
      ..minLeadWidth = minLeadWidth
      ..leadFills = leadFills
      ..order = order
      ..stackedFigureAtEnd = stackedFigureAtEnd
      ..rowAlignment = rowAlignment
      ..leadKeepsWords = leadKeepsWords;
  }
}

class _ReflowParentData extends ContainerBoxParentData<RenderBox> {}

typedef _Measure = Size Function(RenderBox child, BoxConstraints constraints);

class RenderFigureReflow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ReflowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ReflowParentData> {
  RenderFigureReflow({
    required this._gap,
    required this._runGap,
    required this._minLeadWidth,
    required this._leadFills,
    required this._order,
    required this._stackedFigureAtEnd,
    required this._rowAlignment,
    required this._leadKeepsWords,
  });

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double _runGap;
  set runGap(double value) {
    if (value == _runGap) return;
    _runGap = value;
    markNeedsLayout();
  }

  double _minLeadWidth;
  set minLeadWidth(double value) {
    if (value == _minLeadWidth) return;
    _minLeadWidth = value;
    markNeedsLayout();
  }

  bool _leadFills;
  set leadFills(bool value) {
    if (value == _leadFills) return;
    _leadFills = value;
    markNeedsLayout();
  }

  FigureReflowOrder _order;
  set order(FigureReflowOrder value) {
    if (value == _order) return;
    _order = value;
    markNeedsLayout();
  }

  bool _stackedFigureAtEnd;
  set stackedFigureAtEnd(bool value) {
    if (value == _stackedFigureAtEnd) return;
    _stackedFigureAtEnd = value;
    markNeedsLayout();
  }

  CrossAxisAlignment _rowAlignment;
  set rowAlignment(CrossAxisAlignment value) {
    if (value == _rowAlignment) return;
    _rowAlignment = value;
    markNeedsLayout();
  }

  bool _leadKeepsWords;
  set leadKeepsWords(bool value) {
    if (value == _leadKeepsWords) return;
    _leadKeepsWords = value;
    markNeedsLayout();
  }

  /// Whether the last layout put the two side by side. For tests and diagnostics.
  bool get isSideBySide => _sideBySide;
  bool _sideBySide = true;

  RenderBox get _lead => firstChild!;
  RenderBox get _figure => childAfter(firstChild!)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ReflowParentData) {
      child.parentData = _ReflowParentData();
    }
  }

  double get _figureWidth => _figure.getMaxIntrinsicWidth(double.infinity);

  double get _leadNeed => _leadKeepsWords
      ? math.max(_minLeadWidth, _lead.getMinIntrinsicWidth(double.infinity))
      : _minLeadWidth;

  /// The figure at its whole one-line width, beside a lead at least as wide as it needs.
  bool _fitsSideBySide(double maxWidth) =>
      !maxWidth.isFinite || _figureWidth + _gap + _leadNeed <= maxWidth + 0.01;

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(_lead.getMinIntrinsicWidth(height), _figureWidth);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _lead.getMaxIntrinsicWidth(height) + _gap + _figureWidth;

  double _intrinsicHeight(double width, bool max) {
    double of(RenderBox child, double w) =>
        max ? child.getMaxIntrinsicHeight(w) : child.getMinIntrinsicHeight(w);
    if (_fitsSideBySide(width)) {
      final figure = _figureWidth;
      return math.max(
        of(_lead, width.isFinite ? width - figure - _gap : double.infinity),
        of(_figure, figure),
      );
    }
    return of(_lead, width) + _runGap + of(_figure, width);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, false);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, true);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  ({Size size, Offset lead, Offset figure, bool sideBySide}) _arrange(
    BoxConstraints constraints,
    _Measure measure,
  ) {
    final maxWidth = constraints.maxWidth;
    if (_fitsSideBySide(maxWidth)) {
      final figureSize = measure(
        _figure,
        BoxConstraints(
          maxWidth: maxWidth.isFinite
              ? math.max(0, maxWidth - _gap - _leadNeed)
              : double.infinity,
        ),
      );
      final leadRoom = maxWidth.isFinite
          ? math.max(0.0, maxWidth - figureSize.width - _gap)
          : double.infinity;
      final leadSize = measure(
        _lead,
        _leadFills && leadRoom.isFinite
            ? BoxConstraints.tightFor(width: leadRoom)
            : BoxConstraints(maxWidth: leadRoom),
      );
      final height = math.max(leadSize.height, figureSize.height);
      final width = maxWidth.isFinite
          ? maxWidth
          : leadSize.width + _gap + figureSize.width;
      double top(Size child) => switch (_rowAlignment) {
        CrossAxisAlignment.start => 0,
        CrossAxisAlignment.end => height - child.height,
        _ => (height - child.height) / 2,
      };
      return (
        size: constraints.constrain(Size(width, height)),
        lead: Offset(0, top(leadSize)),
        figure: Offset(width - figureSize.width, top(figureSize)),
        sideBySide: true,
      );
    }
    // Not enough room: the figure takes a whole line of its own, at full size.
    final leadSize = measure(
      _lead,
      _leadFills
          ? BoxConstraints.tightFor(width: maxWidth)
          : BoxConstraints(maxWidth: maxWidth),
    );
    final figureSize = measure(_figure, BoxConstraints(maxWidth: maxWidth));
    final figureX = _stackedFigureAtEnd ? maxWidth - figureSize.width : 0.0;
    final leadFirst = _order == FigureReflowOrder.leadFirst;
    final firstHeight = leadFirst ? leadSize.height : figureSize.height;
    return (
      size: constraints.constrain(
        Size(maxWidth, leadSize.height + _runGap + figureSize.height),
      ),
      lead: Offset(0, leadFirst ? 0 : firstHeight + _runGap),
      figure: Offset(figureX, leadFirst ? firstHeight + _runGap : 0),
      sideBySide: false,
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _arrange(constraints, (child, c) => child.getDryLayout(c)).size;

  @override
  void performLayout() {
    final arranged = _arrange(constraints, (child, c) {
      child.layout(c, parentUsesSize: true);
      return child.size;
    });
    size = arranged.size;
    _sideBySide = arranged.sideBySide;
    (_lead.parentData! as _ReflowParentData).offset = arranged.lead;
    (_figure.parentData! as _ReflowParentData).offset = arranged.figure;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
