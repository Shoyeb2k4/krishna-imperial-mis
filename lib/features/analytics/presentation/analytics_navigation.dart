/// Which Analytics section is open, and which period rules it runs under (Phase 6 Slice 8).
///
/// ## Two period models, stated rather than implied
///
/// Spec §19 puts four sections under Analytics, and they do not share one calendar:
///
/// ```
///     Profit & Loss                  the Phase 5 presets — This Month is the whole month,
///                                    Financial Year the whole year (D-225)
///     Revenue · Expense · Business   the Phase 6 dashboard periods — Today so far, Week to
///                                    date, Month to date, Financial year to date, Custom,
///                                    each compared with the same stretch before (D-251, D-252)
/// ```
///
/// [AnalyticsSection.periodModel] says which one a section runs under, so the difference is
/// a property of the navigation state rather than something a reader of two widgets has to
/// notice. The P&L section is the existing Phase 5 page and keeps its own selection
/// (`pnlSelectionProvider`); the three analysis sections share the dashboard's selection
/// (`dashboardSelectionProvider`), which is how switching between them costs no second read
/// of a result that is still valid (D-277).
///
/// ## What a figure opens
///
/// Slice 8 fixed what a row means here, as `AnalyticsDrillIntent`. Slice 9 made it the one
/// shared dashboard adapter (`dashboard_drill.dart`), used by the Overview, the analysis
/// sections and the Android Home alike, so the Slice 8 types are gone rather than kept as a
/// second vocabulary for the same thing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';

/// The calendar a section's periods follow.
enum AnalyticsPeriodModel {
  /// The Phase 5 P&L presets, unchanged: whole calendar months and whole financial years.
  pnlPresets,

  /// The Phase 6 dashboard periods: to date, compared with the same stretch before.
  dashboardToDate,
}

enum AnalyticsSection {
  profitAndLoss('Profit & Loss', AnalyticsPeriodModel.pnlPresets),
  revenue('Revenue Analysis', AnalyticsPeriodModel.dashboardToDate),
  expenses(
    'Expense & Department Analysis',
    AnalyticsPeriodModel.dashboardToDate,
  ),
  businessComparison(
    'Business Comparison',
    AnalyticsPeriodModel.dashboardToDate,
  );

  const AnalyticsSection(this.label, this.periodModel);

  final String label;
  final AnalyticsPeriodModel periodModel;

  /// A shorter name for the section selector, where four names share one line.
  String get selectorLabel => switch (this) {
    AnalyticsSection.expenses => 'Expense & Department',
    _ => label,
  };
}

final analyticsSectionProvider =
    NotifierProvider<AnalyticsSectionController, AnalyticsSection>(
      AnalyticsSectionController.new,
    );

class AnalyticsSectionController extends Notifier<AnalyticsSection> {
  @override
  AnalyticsSection build() {
    // Keyed on the authority, like every other piece of reporting state (D-267): a new
    // person, or the same person whose qualifying capabilities have moved, opens on the
    // Profit & Loss rather than on whatever section the previous authority left open.
    ref.watch(sessionProvider.select((s) => PnlAuthority.readKey(s.principal)));
    return AnalyticsSection.profitAndLoss;
  }

  void select(AnalyticsSection section) => state = section;
}
