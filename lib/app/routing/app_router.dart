/// Routing, built per platform.
///
/// Android and Windows get different navigation branches because they are different
/// products over one domain. Building the router from a [AppShellKind] keeps that
/// difference in one declarative place instead of scattering platform checks through
/// the widget tree — and lets a test build either shell on any host.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:krishna_mis/app/routing/app_routes.dart';
import 'package:krishna_mis/app/shell/desktop_shell.dart';
import 'package:krishna_mis/app/shell/mobile_shell.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_page.dart';
import 'package:krishna_mis/features/dashboard/presentation/mobile_home_page.dart';
import 'package:krishna_mis/features/dashboard/presentation/overview_page.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_ledger_page.dart';
import 'package:krishna_mis/features/export/export_centre_page.dart';
import 'package:krishna_mis/features/transactions/presentation/transactions_page.dart';
import 'package:krishna_mis/features/masters/presentation/masters_page.dart';
import 'package:krishna_mis/features/owner_settlement/presentation/owner_settlement_page.dart';
import 'package:krishna_mis/features/placeholder/placeholder_page.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_profit_and_loss_page.dart';

enum AppShellKind { mobile, desktop }

abstract final class AppRouter {
  /// Where Reports sits among the Android shell's branches.
  ///
  /// Named so a surface that sends somebody to the full profit & loss states the
  /// destination rather than a number, and so the number lives beside the branch list it
  /// describes. A guard asserts the two agree (Phase 6 Slice 7).
  static const int mobileReportsBranch = 2;

  static GoRouter create({
    required AppShellKind shellKind,
    String? initialLocation,
  }) => switch (shellKind) {
    AppShellKind.mobile => _mobileRouter(initialLocation),
    AppShellKind.desktop => _desktopRouter(initialLocation),
  };

  static GoRouter _mobileRouter(String? initialLocation) => GoRouter(
    initialLocation: initialLocation ?? AppRoutes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MobileShell(navigationShell: navigationShell),
        branches: [
          _branch(
            AppRoutes.home,
            // The management dashboard on a phone (Phase 6 Slice 7). The tab is for
            // everyone; the page and its providers decide P&L authority themselves and
            // show a reader without it the approved neutral state (D-259, D-260, D-267).
            const MobileHomePage(),
          ),
          _branch(
            AppRoutes.transactions,
            const ExpenseLedgerPage(shellKind: AppShellKind.mobile),
          ),
          _branch(
            AppRoutes.reports,
            // Reports opens directly to Profit & Loss (Phase 5 Slice 9): V1 has one standard
            // reporting surface, so there is no menu in front of it. The page and its
            // providers decide P&L authority themselves; the tab is a convenience, not a gate.
            const MobileProfitAndLossPage(),
          ),
          _branch(
            AppRoutes.more,
            const MastersPage(shellKind: AppShellKind.mobile),
          ),
        ],
      ),
    ],
  );

  static GoRouter _desktopRouter(String? initialLocation) => GoRouter(
    initialLocation: initialLocation ?? AppRoutes.overview,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            DesktopShell(navigationShell: navigationShell),
        branches: [
          _branch(
            AppRoutes.overview,
            // The management dashboard (Phase 6 Slice 6). The shell shows the destination
            // to everyone; the page and its providers decide P&L authority themselves and
            // show a reader without it the approved neutral state (D-259, D-267).
            const OverviewPage(shellKind: AppShellKind.desktop),
          ),
          _branch(
            AppRoutes.transactions,
            // Expenses and Sales under one destination, as spec §19 lays the desktop
            // information architecture out. A separate top-level entry for Sales would
            // split a finance user's day across two places answering one question.
            const TransactionsPage(shellKind: AppShellKind.desktop),
          ),
          _branch(
            AppRoutes.analytics,
            // The Analytics workspace, as spec §19 lays it out (Phase 6 Slice 8): the
            // existing Profit & Loss page embedded unchanged, beside Revenue Analysis,
            // Expense & Department Analysis and Business Comparison. The sidebar shows the
            // destination to holders of reports.view; every section decides P&L authority
            // itself, and refuses if reached otherwise.
            const AnalyticsPage(shellKind: AppShellKind.desktop),
          ),
          _branch(
            AppRoutes.reports,
            // The Export Centre (Phase 7 Slice 6, D-297): export and print actions for the
            // four canonical reports, each made from the report its own screen holds. It
            // shows no figure and holds no report state; every action decides export or
            // print authority itself (D-291).
            const ExportCentrePage(),
          ),
          // The branch order matches the sidebar's destinations exactly, so a filtered
          // sidebar can never navigate somebody to the wrong screen.
          _branch(
            AppRoutes.ownerSettlement,
            const OwnerSettlementPage(shellKind: AppShellKind.desktop),
          ),
          _branch(
            AppRoutes.masters,
            const MastersPage(shellKind: AppShellKind.desktop),
          ),
          _branch(
            AppRoutes.administration,
            // V1 builds no administration screens; the destination says who handles
            // these acts instead of promising a phase (D-343, D-348).
            const PlaceholderPage(
              title: 'Administration',
              notice: administrationNotice,
            ),
          ),
        ],
      ),
    ],
  );

  static StatefulShellBranch _branch(String path, Widget child) =>
      StatefulShellBranch(
        routes: [GoRoute(path: path, builder: (context, state) => child)],
      );
}
