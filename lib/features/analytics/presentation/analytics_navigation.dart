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
/// ## Drill-down intents, for Slice 9
///
/// Full analytics drill-down is Slice 9. What Slice 8 fixes now is **what a row means**: an
/// [AnalyticsDrillIntent] for each prepared line, built in the domain's own order, with the
/// exact Others remainder mapping to none — because Others is a remainder, not a line
/// anybody can open. Nothing here navigates, and no detail screen is invented.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:meta/meta.dart';

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

// ── What a row means, for Slice 9 ───────────────────────────────────────────

@immutable
sealed class AnalyticsDrillIntent {
  const AnalyticsDrillIntent(this.businessUnitId);

  final String businessUnitId;
}

/// One revenue category of one property.
final class AnalyticsRevenueCategoryIntent extends AnalyticsDrillIntent {
  const AnalyticsRevenueCategoryIntent(
    super.businessUnitId,
    this.revenueCategoryId,
  );

  final String revenueCategoryId;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsRevenueCategoryIntent &&
      other.businessUnitId == businessUnitId &&
      other.revenueCategoryId == revenueCategoryId;

  @override
  int get hashCode => Object.hash(businessUnitId, revenueCategoryId);
}

/// One Department + Section + Category bucket of one property — the grain the P&L
/// drill-down already opens at (Slice 10).
final class AnalyticsExpenseCategoryIntent extends AnalyticsDrillIntent {
  const AnalyticsExpenseCategoryIntent(
    super.businessUnitId, {
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
  });

  final String? departmentId;
  final String? sectionId;
  final String? categoryId;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsExpenseCategoryIntent &&
      other.businessUnitId == businessUnitId &&
      other.departmentId == departmentId &&
      other.sectionId == sectionId &&
      other.categoryId == categoryId;

  @override
  int get hashCode =>
      Object.hash(businessUnitId, departmentId, sectionId, categoryId);
}

/// One department of one property.
final class AnalyticsDepartmentIntent extends AnalyticsDrillIntent {
  const AnalyticsDepartmentIntent(super.businessUnitId, this.departmentId);

  final String? departmentId;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsDepartmentIntent &&
      other.businessUnitId == businessUnitId &&
      other.departmentId == departmentId;

  @override
  int get hashCode => Object.hash(businessUnitId, departmentId);
}

/// One property's figures inside a consolidated report.
final class AnalyticsPropertyIntent extends AnalyticsDrillIntent {
  const AnalyticsPropertyIntent(super.businessUnitId);

  @override
  bool operator ==(Object other) =>
      other is AnalyticsPropertyIntent &&
      other.businessUnitId == businessUnitId;

  @override
  int get hashCode => businessUnitId.hashCode;
}

/// The intents for a ranked outcome's rows, in the domain's order, Others last as null.
///
/// Empty for a refusal: a set that did not reconcile draws no rows, so there is nothing to
/// open (D-258).
List<AnalyticsDrillIntent?> analyticsRankedIntents<L>(
  TopNOutcome<L> outcome,
  AnalyticsDrillIntent Function(L line) intent,
) => switch (outcome) {
  TopNRefused<L>() => const [],
  TopNGrouped<L>(:final top, :final others) => [
    for (final line in top) intent(line.line),
    if (others != null) null,
  ],
};

AnalyticsDrillIntent analyticsRevenueIntent(RevenueCategoryLine line) =>
    AnalyticsRevenueCategoryIntent(line.businessUnitId, line.revenueCategoryId);

AnalyticsDrillIntent analyticsExpenseIntent(ExpenseHierarchyLine line) =>
    AnalyticsExpenseCategoryIntent(
      line.businessUnitId,
      departmentId: line.departmentId,
      sectionId: line.sectionId,
      categoryId: line.categoryId,
    );

AnalyticsDrillIntent analyticsDepartmentIntent(ExpenseHierarchyLine line) =>
    AnalyticsDepartmentIntent(line.businessUnitId, line.departmentId);

/// One intent per property, in the domain's id order — never figure order.
List<AnalyticsDrillIntent> analyticsPropertyIntents(
  PropertyComparisonReady split,
) => [
  for (final property in split.properties)
    AnalyticsPropertyIntent(property.businessUnitId),
];
