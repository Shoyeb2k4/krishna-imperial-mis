/// What the Windows Analytics sections say, decided once (Phase 6 Slice 8).
///
/// The dashboard's own wording (`dashboard_presentation.dart`) already states every
/// movement, freshness claim and refusal; this file adds only what an analysis section says
/// that the Overview does not — why a trend is not drawn, why a business comparison cannot
/// be shown for this scope, and the word beside an operating result.
///
/// ## What this file does not do
///
/// It computes no figure, decides no authority, derives no date and ranks nothing. A trend
/// that is absent is absent because `DashboardTrends.grainsFor` offered none; this file
/// says so in words. A property comparison that is refused was refused by
/// `PropertyComparison`; this file names the reason. The analytics surface guard holds it.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';

/// Said above the three analysis sections, so the two period models are never confused
/// (D-252, D-277).
const analyticsPeriodModelNote =
    'Revenue, expense and business comparison periods run to date and are compared with '
    'the same stretch before. The Profit & Loss section keeps its own whole-month and '
    'whole-year periods.';

// ── Trends that are not drawn ───────────────────────────────────────────────

/// Why there is no Net Sales trend for [kind]. The planner offers none only for a single
/// business date, which is one point and therefore not a trend (D-255).
String analyticsNoNetSalesTrend(DashboardPeriodKind kind) =>
    '${kind.label} is a single business date, and one point is not a trend. Choose a '
    'longer period to see how Net Sales moved.';

/// Why there is no monthly Operating Expenses trend for [kind].
///
/// Expenses are trended by month only: an expense's accrual date places its cost, so a
/// daily or weekly expense figure says more about when a bill was dated than about
/// spending (D-255). A period of fewer than two months has one monthly point, and one
/// point is not a trend (D-263).
String analyticsNoExpenseTrend(DashboardPeriodKind kind) =>
    'Operating Expenses are trended by month only, because accrual dating makes a daily '
    'or weekly expense figure misleading. ${kind.label} covers fewer than two months, so '
    'there is one monthly point and no trend to draw.';

// ── Business comparison ─────────────────────────────────────────────────────

/// The reader holds no consolidated authority, so there is nothing to compare. It names
/// no property: a reader who may not see both must not learn from this which exist.
const analyticsComparisonNotAuthorised = DashboardMessage(
  key: Key('analytics-comparison-not-authorised'),
  icon: Icons.compare_arrows_outlined,
  title: 'Business comparison is not available for your access.',
  message:
      'Comparing the properties needs report, revenue and full expense access for the '
      'whole organisation. Each property you can see is in Revenue Analysis and Expense '
      '& Department Analysis.',
);

/// The reader may compare, but has chosen one property.
const analyticsComparisonNeedsBoth = DashboardMessage(
  key: Key('analytics-comparison-needs-both'),
  icon: Icons.compare_arrows_outlined,
  title: 'Business comparison covers both properties',
  message:
      'One property is selected. Choose both properties to compare them side by side '
      'over the same period.',
);

const analyticsCompareBothLabel = 'Compare both properties';

/// Why the domain did not split this consolidated result.
DashboardMessage analyticsComparisonRefused(
  PropertyComparisonRefusal reason,
) => switch (reason) {
  PropertyComparisonRefusal.singleProperty => const DashboardMessage(
    key: Key('analytics-comparison-single-property'),
    icon: Icons.compare_arrows_outlined,
    title: 'Only one property has figures in this period',
    message:
        'There is nothing to compare it with. Choose a period in which both '
        'properties traded.',
  ),
  PropertyComparisonRefusal.doesNotReconcile => const DashboardMessage(
    key: Key('analytics-comparison-does-not-reconcile'),
    icon: Icons.report_gmailerrorred_outlined,
    title: 'Property figures not shown',
    message:
        'The category lines do not add up exactly to the combined total, so a '
        'per-property figure could understate one property. Refresh to bring this '
        'device up to date.',
    action: DashboardMessageAction.synchronise,
    actionKey: Key('analytics-comparison-synchronise'),
  ),
};

/// Said under the comparison, so a fixed order is never read as a ranking.
const analyticsComparisonOrderNote =
    'Properties are listed in a fixed order, not by result. The figures are stated side by '
    'side; neither property is placed above the other.';

/// What the combined column is called.
const analyticsComparisonTotalLabel = 'Both properties';

/// The word beside an operating result, so a loss is never told by colour alone
/// (spec §20). A sign test on a prepared figure — nothing is worked out.
String analyticsOperatingWord(PnlResult result) => result.operatingProfit.isZero
    ? 'Break-even'
    : result.operatingProfit.isNegative
    ? 'Loss'
    : 'Profit';

// ── Summary wording ─────────────────────────────────────────────────────────

/// `Compared with 1 Aug 2026 – 19 Aug 2026`.
String analyticsComparedWithLine(DashboardPeriodPair pair) =>
    'Compared with ${dashboardComparisonRangeLabel(pair)}';
