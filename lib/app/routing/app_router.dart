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
import 'package:krishna_mis/features/expenses/presentation/expense_ledger_page.dart';
import 'package:krishna_mis/features/transactions/presentation/transactions_page.dart';
import 'package:krishna_mis/features/masters/presentation/masters_page.dart';
import 'package:krishna_mis/features/placeholder/placeholder_page.dart';

enum AppShellKind { mobile, desktop }

abstract final class AppRouter {
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
            const PlaceholderPage(
              eyebrow: 'Krishna Imperial MIS',
              title: 'Home',
              arrivesIn: 'Phase 6 — Dashboard & Analytics',
              summary:
                  'Net sales, operating expenses, operating profit and margin for the '
                  'selected period, each drilling down to its source transactions.',
            ),
          ),
          _branch(
            AppRoutes.transactions,
            const ExpenseLedgerPage(shellKind: AppShellKind.mobile),
          ),
          _branch(
            AppRoutes.reports,
            const PlaceholderPage(
              title: 'Reports',
              arrivesIn: 'Phase 5 — Ledger & Reporting Engine',
              summary:
                  'P&L and analysis for any period, computed locally and offline.',
            ),
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
            const PlaceholderPage(
              eyebrow: 'Krishna Imperial MIS',
              title: 'Overview',
              arrivesIn: 'Phase 6 — Dashboard & Analytics',
              summary:
                  'Business-unit comparison, trends and period-over-period movement '
                  'for Crystal Canopy Rooftop and Hotel Krishna Imperial.',
            ),
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
            const PlaceholderPage(
              title: 'Analytics',
              arrivesIn: 'Phase 5 — Ledger & Reporting Engine',
              summary:
                  'Profit & Loss, expense analysis, revenue analysis, department '
                  'performance and business comparison.',
            ),
          ),
          _branch(
            AppRoutes.reports,
            const PlaceholderPage(
              title: 'Reports',
              arrivesIn: 'Phase 7 — Export & Printing',
              summary:
                  'Generated reports, Excel and PDF export, Windows printing.',
            ),
          ),
          _branch(
            AppRoutes.masters,
            const MastersPage(shellKind: AppShellKind.desktop),
          ),
          _branch(
            AppRoutes.administration,
            const PlaceholderPage(
              title: 'Administration',
              arrivesIn: 'Phase 2 — Masters & Permissions',
              summary:
                  'Users, roles and capabilities, period close, audit log, settings '
                  'and sync health.',
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
