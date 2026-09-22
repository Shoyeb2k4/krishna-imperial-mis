/// How a chart looks, in tokens (Phase 6 Slice 5, D-268).
///
/// Every colour, size and weight here is an [AppColors] / [AppTypography] token. No chart
/// hard-codes a colour, and none of them introduces a palette of its own — spec §20 is
/// explicit that the identity comes from the project's tokens, and that this must not read
/// as a neon fintech dashboard or a gradient SaaS product. So: hairlines, a restrained
/// brass accent, charcoal ink, no gradients, no shadows, no rounded-card chrome.
///
/// **A series is never identified by colour alone.** Each [ChartSeriesStyle] carries a
/// colour *and* a second cue — a dash pattern and a marker shape — and every series has a
/// visible name in the legend. Profit and loss carry the word as well (spec §20).
library;

import 'package:flutter/widgets.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

/// The shape drawn at a plotted point, so two series differ without colour.
enum ChartMarker { circle, square, diamond }

/// One series' visual identity: a colour, a second cue, and a name.
@immutable
final class ChartSeriesStyle {
  const ChartSeriesStyle({
    required this.name,
    required this.color,
    required this.marker,
    this.dashed = false,
  });

  final String name;
  final Color color;
  final ChartMarker marker;

  /// A dashed stroke, so a printed or colour-blind reading still separates two lines.
  final bool dashed;

  /// The dash pattern a dashed series uses, or null for a solid one.
  List<int>? get dashArray => dashed ? const [5, 4] : null;
}

/// Chart styling, entirely from tokens.
abstract final class ChartTheme {
  /// Below this width a value axis is not labelled: a `₹12,36,420` tick eats a third of a
  /// phone and pushes the plot into the gutter. The figures a reader acts on come from the
  /// readout and the headline metric, which are exact; an axis is a scale, not a statement.
  static const double narrowWidth = 480;

  /// The plot's own height, excluding the title, legend and readout around it.
  static const double plotHeight = 180;
  static const double compactPlotHeight = 140;

  static const Color grid = AppColors.hairline;
  static const Color baseline = AppColors.hairlineStrong;
  static const Color border = AppColors.hairline;

  static const double lineWidth = 2;
  static const double markerRadius = 3;
  static const double gridWidth = 1;

  /// The zero line on a chart that spans it — drawn stronger than the grid, because a
  /// reader must be able to see at a glance which bars are below it.
  static const double baselineWidth = 1.5;

  static const TextStyle axisLabel = AppTypography.caption;
  static const TextStyle seriesName = AppTypography.caption;
  static const TextStyle pointLabel = AppTypography.caption;

  /// Tabular figures, so a readout does not twitch as the selection moves.
  static const TextStyle readoutValue = AppTypography.moneyStrong;
  static const TextStyle readoutLabel = AppTypography.caption;

  /// Animation is off. A financial chart gains nothing from motion, and a running
  /// animation makes an acceptance assertion read a figure that is on its way somewhere
  /// (the lesson D-152 records about waiting for a condition rather than for frames).
  static const Duration motion = Duration.zero;

  // ── Series identities ─────────────────────────────────────────────────────

  static const ChartSeriesStyle netSales = ChartSeriesStyle(
    name: 'Net Sales',
    color: AppColors.brass,
    marker: ChartMarker.circle,
  );

  static const ChartSeriesStyle expenses = ChartSeriesStyle(
    name: 'Expenses',
    color: AppColors.inkMuted,
    marker: ChartMarker.square,
    dashed: true,
  );

  /// Operating Profit as one series among others — the property comparison. A profit
  /// chart drawn on its own colours each bar by sign instead (see [bySign]).
  static const ChartSeriesStyle operatingProfit = ChartSeriesStyle(
    name: 'Operating Profit',
    color: AppColors.brassMuted,
    marker: ChartMarker.diamond,
  );

  static const ChartSeriesStyle comparison = ChartSeriesStyle(
    name: 'Previous period',
    color: AppColors.inkFaint,
    marker: ChartMarker.diamond,
    dashed: true,
  );

  /// A bar's colour by sign. **Always accompanied by the sign on the figure and by the
  /// word in the description** — never the only cue (spec §20).
  static Color bySign({required bool negative, required bool zero}) => zero
      ? AppColors.inkFaint
      : negative
      ? AppColors.negative
      : AppColors.positive;

  /// A ranked bar. One accent, because a ranked list is one series.
  static const Color rankedBar = AppColors.brassMuted;

  /// The Others bar, quieter than the lines it stands for, so it never reads as the
  /// largest category.
  static const Color othersBar = AppColors.hairlineStrong;

  /// The track a ranked bar is drawn in, so a small bar is still legible as a proportion.
  static const Color rankedTrack = AppColors.surfaceSunken;
}
