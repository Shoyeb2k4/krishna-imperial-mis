/// The chart presentation layer (Phase 6 Slice 5, D-268).
///
/// Charts render values `domain/finance` has already decided. Nothing here computes a
/// financial figure, reads a report, reaches a database, or judges authority or freshness
/// — a structural guard over this directory asserts each of those, and the money rule is
/// structural rather than remembered: a coordinate is derived from an exact figure and is
/// never read back into one.
///
/// Six approved families, and no more (D-257):
///
/// | | |
/// |---|---|
/// | Net Sales trend | [TrendLineChart] |
/// | Monthly Operating Profit | [ProfitBarChart] |
/// | Property comparison | [ComparisonBarChart] |
/// | Revenue mix · Top expense categories · Department spending | [RankedBarChart] |
///
/// Slice 5 builds the foundation and wires it into no screen. The Windows Overview and
/// the Android Home are Slices 6 and 7.
library;

export 'package:krishna_mis/core/design/charts/chart_frame.dart';
export 'package:krishna_mis/core/design/charts/chart_selection.dart';
export 'package:krishna_mis/core/design/charts/chart_semantics.dart';
export 'package:krishna_mis/core/design/charts/chart_series.dart';
export 'package:krishna_mis/core/design/charts/chart_theme.dart';
export 'package:krishna_mis/core/design/charts/chart_values.dart';
export 'package:krishna_mis/core/design/charts/comparison_bar_chart.dart';
export 'package:krishna_mis/core/design/charts/profit_bar_chart.dart';
export 'package:krishna_mis/core/design/charts/ranked_bar_chart.dart';
export 'package:krishna_mis/core/design/charts/trend_line_chart.dart';
