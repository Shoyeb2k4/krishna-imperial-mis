/// The chrome every chart shares (Phase 6 Slice 5, D-268).
///
/// A title, the period it covers, a legend that names each series in words, a readout that
/// prints the selected figure **exactly**, and one [Semantics] node carrying the whole
/// description. Composed once so Windows and Android cannot describe the same chart
/// differently — the rule D-232 settled for the P&L surfaces, applied to charts.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/charts/chart_theme.dart';
import 'package:krishna_mis/core/design/charts/chart_values.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

/// Wraps a plot with its title, legend, readout and accessibility description.
class ChartFrame extends StatelessWidget {
  const ChartFrame({
    required this.title,
    required this.periodLabel,
    required this.semanticsLabel,
    required this.child,
    super.key,
    this.series = const [],
    this.readout,
    this.footnote,
    this.action,
  });

  final String title;
  final String periodLabel;

  /// The whole chart in words, from `ChartSemantics`. The plot itself is excluded from
  /// the tree's semantics, because a scatter of unlabelled coordinates is worse than
  /// silence for anyone not looking at it.
  final String semanticsLabel;

  final List<ChartSeriesStyle> series;

  /// The selected figure, printed exactly. See [ChartReadout].
  final Widget? readout;

  /// A note under the plot — a gap count, a partial-bucket caveat.
  final String? footnote;

  /// A control under the chart that opens the selected point, when a surface can open one
  /// (Phase 6 Slice 9). Kept outside the plot's excluded semantics, so it is announced and
  /// reachable like any other button.
  final Widget? action;

  final Widget child;

  /// The node carrying [semanticsLabel]. Keyed so a surface or a test can assert the
  /// description a chart actually publishes, rather than the nearest Semantics above it.
  static const Key semanticsKey = Key('chart-semantics');

  /// The key of [ChartOpenAction], for a surface or a test.
  static const Key openKey = Key('chart-open');

  @override
  Widget build(BuildContext context) {
    final framed = _framed();
    final open = action;
    if (open == null) return framed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        framed,
        Align(alignment: Alignment.centerRight, child: open),
      ],
    );
  }

  Widget _framed() => Semantics(
    key: semanticsKey,
    label: semanticsLabel,
    container: true,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.subheading,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      periodLabel,
                      style: AppTypography.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (readout != null) ...[
                const SizedBox(width: AppSpacing.md),
                readout!,
              ],
            ],
          ),
          if (series.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ChartLegend(series: series),
          ],
          const SizedBox(height: AppSpacing.md),
          child,
          if (footnote != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(footnote!, style: AppTypography.caption),
          ],
        ],
      ),
    ),
  );
}

/// Opens the point a reader has selected. Offered only for a point that has a figure: a
/// gap has nothing beneath it to open (D-263).
class ChartOpenAction extends StatelessWidget {
  const ChartOpenAction({required this.point, required this.onOpen, super.key});

  final ChartPoint? point;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => switch (point) {
    ChartPlotted(:final label) => TextButton.icon(
      key: ChartFrame.openKey,
      onPressed: onOpen,
      icon: const Icon(Icons.open_in_new, size: 16),
      label: Text('Open $label'),
    ),
    _ => const SizedBox.shrink(),
  };
}

/// Names each series in words, with its non-colour cue beside it.
class ChartLegend extends StatelessWidget {
  const ChartLegend({required this.series, super.key});

  final List<ChartSeriesStyle> series;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.lg,
    runSpacing: AppSpacing.xs,
    children: [
      for (final style in series)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(18, 10),
              painter: _LegendKeyPainter(style),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(style.name, style: ChartTheme.seriesName),
          ],
        ),
    ],
  );
}

class _LegendKeyPainter extends CustomPainter {
  const _LegendKeyPainter(this.style);

  final ChartSeriesStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = style.color
      ..strokeWidth = ChartTheme.lineWidth
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    if (style.dashed) {
      var x = 0.0;
      const dash = 4.0;
      const gap = 3.0;
      while (x < size.width) {
        canvas.drawLine(
          Offset(x, y),
          Offset((x + dash).clamp(0, size.width), y),
          paint,
        );
        x += dash + gap;
      }
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final centre = Offset(size.width / 2, y);
    final fill = Paint()..color = style.color;
    switch (style.marker) {
      case ChartMarker.circle:
        canvas.drawCircle(centre, ChartTheme.markerRadius, fill);
      case ChartMarker.square:
        canvas.drawRect(
          Rect.fromCenter(center: centre, width: 6, height: 6),
          fill,
        );
      case ChartMarker.diamond:
        final path = Path()
          ..moveTo(centre.dx, centre.dy - 4)
          ..lineTo(centre.dx + 4, centre.dy)
          ..lineTo(centre.dx, centre.dy + 4)
          ..lineTo(centre.dx - 4, centre.dy)
          ..close();
        canvas.drawPath(path, fill);
    }
  }

  @override
  bool shouldRepaint(_LegendKeyPainter old) => old.style != style;
}

/// The selected figure, printed from its exact source.
///
/// This is the only place a chart states a number, and the string it states is
/// [ChartAmount.label] — the figure the engine computed, formatted by the application's
/// own formatter. It is never derived from a coordinate, a bar height or a pixel.
class ChartReadout extends StatelessWidget {
  const ChartReadout({required this.point, super.key, this.spansZero = false});

  /// A key every surface and test can find one by.
  static const Key findKey = Key('chart-readout');

  final ChartPoint? point;

  /// Whether the measure can be either a profit or a loss, in which case the word is
  /// printed beside the figure (spec §20).
  final bool spansZero;

  @override
  Widget build(BuildContext context) {
    final current = point;
    return KeyedSubtree(
      key: findKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            current?.label ?? '',
            style: ChartTheme.readoutLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xxs),
          switch (current) {
            ChartPlotted(:final amount) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(amount.label, style: ChartTheme.readoutValue),
                if (spansZero) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    amount.isZero
                        ? 'break-even'
                        : amount.isNegative
                        ? 'loss'
                        : 'profit',
                    style: ChartTheme.readoutLabel,
                  ),
                ],
              ],
            ),
            ChartAbsent() => Text(
              'Not available',
              style: ChartTheme.readoutLabel,
            ),
            null => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }
}

/// Shown in place of a plot when the domain refused one. Never an empty plot area, which
/// a reader cannot tell apart from a flat zero (D-163).
class ChartUnavailable extends StatelessWidget {
  const ChartUnavailable({
    required this.title,
    required this.periodLabel,
    required this.reason,
    required this.semanticsLabel,
    super.key,
    this.height = ChartTheme.plotHeight,
  });

  static const Key findKey = Key('chart-unavailable');

  final String title;
  final String periodLabel;
  final String reason;
  final String semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) => ChartFrame(
    key: findKey,
    title: title,
    periodLabel: periodLabel,
    semanticsLabel: semanticsLabel,
    child: Container(
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.allMedium,
      ),
      child: Text(
        reason,
        style: AppTypography.bodyMuted,
        textAlign: TextAlign.center,
      ),
    ),
  );
}
