/// Where a dashboard or analytics figure opens (Phase 6 Slice 9).
///
/// ## One adapter, for both platforms
///
/// Every figure a dashboard surface can open — on the Windows Overview, in the three
/// Analytics sections, or on the Android Home — is turned into a [DashboardDrillTarget]
/// **here**, by [DashboardDrillTargets], and opened **here**, by [openDashboardTarget]. A
/// surface builds no location, decides no destination and routes nowhere itself, so the
/// two platforms cannot come to disagree about what a figure means. What differs between
/// them is only how a level is shown: a pane on Windows, a pushed page on the phone.
///
/// ## A target is navigation intent, and nothing more
///
/// It carries canonical ids — a business unit, a department, a section, a category — the
/// scope, and the **resolved** P&L date range the clicked figure represents. It carries no
/// display name and no figure. A bucket's range is the bucket's own, clipped exactly as the
/// planner clipped it; a period's is the pair's own. Nothing here reads a clock, a calendar
/// or a business-day rule, so a boundary passing between the click and the destination
/// cannot move what is opened.
///
/// The destination is the existing Phase 5 read-only drill-down. It decides again, for the
/// person signed in now, whether they may read the scope, and it reads the report and the
/// document rows itself. A target that outlives a user switch or a capability change opens
/// nothing (D-074, D-231).
///
/// ## Two kinds of destination
///
/// Net Sales, Expenses, the categories, the departments and a Net Sales or expense trend
/// point have transactions beneath them and open the drill-down. Operating Profit, the
/// margin, Gross Sales and GST, a profit trend point and a property have no transactions of
/// their own — there is no "profit document" — so they open the **existing** P&L, handed the
/// exact range as an explicit Custom period through the P&L's own contract. The P&L's
/// presets are not touched, and it does not follow the dashboard's period afterwards.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/app/routing/app_routes.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_navigation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_pnl_drilldown_pages.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

/// The surface a figure was opened from — where Back returns to.
enum DashboardDrillOrigin {
  overview('Overview'),
  revenueAnalysis('Revenue Analysis'),
  expenseAnalysis('Expense & Department Analysis'),
  businessComparison('Business Comparison'),
  home('Home');

  const DashboardDrillOrigin(this.label);

  /// What the drill-down calls the place it returns to.
  final String label;

  /// The Analytics section that is this origin, or null for the Overview and Home.
  AnalyticsSection? get section => switch (this) {
    DashboardDrillOrigin.revenueAnalysis => AnalyticsSection.revenue,
    DashboardDrillOrigin.expenseAnalysis => AnalyticsSection.expenses,
    DashboardDrillOrigin.businessComparison =>
      AnalyticsSection.businessComparison,
    _ => null,
  };

  /// The origin an Analytics section opens from, or null for the Profit & Loss — which
  /// keeps its own Phase 5 drill-down and opens nothing through this adapter.
  static DashboardDrillOrigin? ofSection(AnalyticsSection section) =>
      switch (section) {
        AnalyticsSection.revenue => DashboardDrillOrigin.revenueAnalysis,
        AnalyticsSection.expenses => DashboardDrillOrigin.expenseAnalysis,
        AnalyticsSection.businessComparison =>
          DashboardDrillOrigin.businessComparison,
        AnalyticsSection.profitAndLoss => null,
      };
}

// ── Targets ─────────────────────────────────────────────────────────────────

/// What a dashboard figure opens.
@immutable
sealed class DashboardDrillTarget {
  const DashboardDrillTarget();
}

/// A level of the existing Phase 5 drill-down, anchored to a resolved range and a scope.
final class DashboardDrillLevel extends DashboardDrillTarget {
  const DashboardDrillLevel(this.location);

  final PnlDrillLocation location;

  @override
  bool operator ==(Object other) =>
      other is DashboardDrillLevel && other.location == location;

  @override
  int get hashCode => location.hashCode;
}

/// The existing P&L, for [scope] over exactly [range].
final class DashboardPnlHandoff extends DashboardDrillTarget {
  const DashboardPnlHandoff({required this.scope, required this.range});

  final PnlScopeChoice scope;
  final ReportRange range;

  @override
  bool operator ==(Object other) =>
      other is DashboardPnlHandoff &&
      other.scope == scope &&
      other.range.from == range.from &&
      other.range.to == range.to;

  @override
  int get hashCode => Object.hash(scope, range.from, range.to);
}

/// The targets one dashboard, as shown to one person, can open.
///
/// Built only from a [DashboardReady] the surface was allowed to show, and only from the
/// canonical ids and ranges it carries: a line outside the dashboard's own scope opens
/// nothing, so a figure can never be turned into another property's target.
final class DashboardDrillTargets {
  const DashboardDrillTargets._(this._viewerUserId, this._ready);

  factory DashboardDrillTargets.of(DashboardReady ready, Principal principal) =>
      DashboardDrillTargets._(principal.userId, ready);

  final String _viewerUserId;
  final DashboardReady _ready;

  /// The period the headline figures represent, exactly as the planner resolved it.
  ReportRange get _current => _ready.pair.current;

  PnlDrillAnchor _anchor(ReportRange range) => PnlDrillAnchor.dashboard(
    viewerUserId: _viewerUserId,
    scope: _ready.view.scope,
    range: range,
  );

  bool _inScope(String businessUnitId) =>
      _ready.view.scope.ordered.contains(businessUnitId);

  /// Net Sales → the revenue categories for the period.
  DashboardDrillTarget netSales() =>
      DashboardDrillLevel(PnlRevenueCategoriesAt(_anchor(_current)));

  /// Operating Expenses → the departments for the period.
  DashboardDrillTarget expenses() =>
      DashboardDrillLevel(PnlExpenseDepartmentsAt(_anchor(_current)));

  /// Operating Profit, the margin, Gross Sales and GST → the P&L for the same scope and
  /// period. None of them has transactions of its own to list.
  DashboardDrillTarget pnl() =>
      DashboardPnlHandoff(scope: _ready.scope, range: _current);

  /// A trend point → the same kind of level, over exactly that bucket's clipped range. A
  /// profit point opens the P&L for the bucket; a gap opens nothing, because no figure was
  /// established for it (D-263).
  DashboardDrillTarget? trendPoint(TrendSeries series, int index) {
    if (index < 0 || index >= series.points.length) return null;
    final point = series.points[index];
    if (point is! TrendValue) return null;
    final range = point.bucket.range;
    return switch (series.measure) {
      TrendMeasure.netSales => DashboardDrillLevel(
        PnlRevenueCategoriesAt(_anchor(range)),
      ),
      TrendMeasure.expenses => DashboardDrillLevel(
        PnlExpenseDepartmentsAt(_anchor(range)),
      ),
      TrendMeasure.operatingProfit => DashboardPnlHandoff(
        scope: _ready.scope,
        range: range,
      ),
    };
  }

  /// A revenue category line → that category's documents.
  DashboardDrillTarget? revenueCategory(RevenueCategoryLine line) =>
      _inScope(line.businessUnitId)
      ? DashboardDrillLevel(
          PnlRevenueDocumentsAt(
            _anchor(_current),
            businessUnitId: line.businessUnitId,
            revenueCategoryId: line.revenueCategoryId,
          ),
        )
      : null;

  /// An expense category line → its Department + Section + Category bucket's documents.
  /// The full canonical path is carried, because the Phase 5 drill-down opens a bucket by
  /// all four ids and a category alone does not name one.
  DashboardDrillTarget? expenseCategory(ExpenseHierarchyLine line) {
    final department = line.departmentId;
    final section = line.sectionId;
    final category = line.categoryId;
    if (!_inScope(line.businessUnitId) ||
        department == null ||
        section == null ||
        category == null) {
      return null;
    }
    return DashboardDrillLevel(
      PnlExpenseDocumentsAt(
        _anchor(_current),
        businessUnitId: line.businessUnitId,
        departmentId: department,
        sectionId: section,
        categoryId: category,
      ),
    );
  }

  /// A department line → that department's sections.
  DashboardDrillTarget? department(ExpenseHierarchyLine line) {
    final department = line.departmentId;
    if (!_inScope(line.businessUnitId) || department == null) return null;
    return DashboardDrillLevel(
      PnlExpenseSectionsAt(
        _anchor(_current),
        businessUnitId: line.businessUnitId,
        departmentId: department,
      ),
    );
  }

  /// A property inside a consolidated dashboard → the P&L for that property over the same
  /// period. Only a property the dashboard itself covers; never a winner, never a rank.
  DashboardDrillTarget? property(String businessUnitId) =>
      _ready.view.scope.ordered.length > 1 && _inScope(businessUnitId)
      ? DashboardPnlHandoff(
          scope: PnlUnitScope(businessUnitId),
          range: _current,
        )
      : null;

  /// One target per ranked row, in the domain's order, with the exact Others remainder
  /// opening nothing — it is a remainder, not a line. Empty for a refusal: a set that did
  /// not reconcile draws no rows, so there is nothing to open (D-258).
  static List<DashboardDrillTarget?> ranked<L>(
    TopNOutcome<L> outcome,
    DashboardDrillTarget? Function(L line) target,
  ) => switch (outcome) {
    TopNRefused<L>() => const [],
    TopNGrouped<L>(:final top, :final others) => [
      for (final line in top) target(line.line),
      if (others != null) null,
    ],
  };
}

/// Opens [index] of a list of targets a chart handed back, when there is one.
void openDashboardTargetAt(
  BuildContext context,
  WidgetRef ref,
  List<DashboardDrillTarget?> targets,
  int index, {
  required DashboardDrillOrigin origin,
}) {
  if (index < 0 || index >= targets.length) return;
  if (targets[index] case final DashboardDrillTarget target) {
    openDashboardTarget(context, ref, target, origin: origin);
  }
}

// ── Opening ─────────────────────────────────────────────────────────────────

/// Opens [target] from [origin]. The only place a dashboard or analytics surface navigates.
void openDashboardTarget(
  BuildContext context,
  WidgetRef ref,
  DashboardDrillTarget target, {
  required DashboardDrillOrigin origin,
}) {
  switch (target) {
    case DashboardDrillLevel(:final location):
      if (origin == DashboardDrillOrigin.home) {
        // A page per level on the Home branch: Android back walks up one level at a time
        // and the bottom bar stays where it is.
        final container = ProviderScope.containerOf(context, listen: false);
        pushPnlDrillLevel(
          context,
          location,
          reportLabel: origin.label,
          onRefresh: () =>
              container.read(dashboardSyncProvider.notifier).refresh(),
        );
      } else {
        ref.read(dashboardDrillProvider.notifier).open(origin, location);
      }

    case DashboardPnlHandoff(:final scope, :final range):
      // Through the P&L's own contract: an explicit Custom period of exactly these dates.
      // Its presets are untouched, and it does not follow the dashboard afterwards.
      ref.read(pnlSelectionProvider.notifier)
        ..selectScope(scope)
        ..selectCustom(range.from, range.to);
      if (origin == DashboardDrillOrigin.home) {
        StatefulNavigationShell.maybeOf(
          context,
        )?.goBranch(AppRouter.mobileReportsBranch);
      } else {
        ref
            .read(analyticsSectionProvider.notifier)
            .select(AnalyticsSection.profitAndLoss);
        if (origin == DashboardDrillOrigin.overview) {
          GoRouter.maybeOf(context)?.go(AppRoutes.analytics);
        }
      }
  }
}

// ── The Windows drill-down state ────────────────────────────────────────────

@immutable
final class DashboardDrillState {
  const DashboardDrillState({
    required this.origin,
    required this.location,
    this.selected,
  });

  final DashboardDrillOrigin origin;
  final PnlDrillLocation location;
  final PnlDocumentRequest? selected;
}

/// The drill-down a Windows dashboard or analytics figure opened, and the document
/// selected in it. Keyed on the authority: a different person, or the same person whose
/// P&L read grants have moved, closes it (D-231, D-242).
final dashboardDrillProvider =
    NotifierProvider<DashboardDrillController, DashboardDrillState?>(
      DashboardDrillController.new,
    );

class DashboardDrillController extends Notifier<DashboardDrillState?> {
  @override
  DashboardDrillState? build() {
    ref.watch(sessionProvider.select((s) => PnlAuthority.readKey(s.principal)));
    return null;
  }

  void open(DashboardDrillOrigin origin, PnlDrillLocation location) =>
      state = DashboardDrillState(origin: origin, location: location);

  /// Another level of the drill-down that is open.
  void openLevel(PnlDrillLocation location) {
    final current = state;
    if (current == null) return;
    state = DashboardDrillState(origin: current.origin, location: location);
  }

  void select(PnlDocumentRequest request) {
    final current = state;
    if (current == null) return;
    // Opening a row always asks the server again. A copy still held from the last time
    // this row was open is never shown in its place (D-239).
    ref.invalidate(pnlDocumentDetailProvider(request));
    state = DashboardDrillState(
      origin: current.origin,
      location: request.location,
      selected: request,
    );
  }

  void closeDocument() {
    final current = state;
    if (current != null) {
      state = DashboardDrillState(
        origin: current.origin,
        location: current.location,
      );
    }
  }

  /// Back to the surface it was opened from, with its section, scope, period and place
  /// on the page as they were.
  void close() => state = null;
}
