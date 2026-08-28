/// Windows shell: the management, finance and reporting workstation.
///
/// Persistent sidebar, dense tables, keyboard and mouse (master spec §19). Not the
/// phone UI stretched across a monitor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/auth/capability.dart';

class DesktopShell extends ConsumerWidget {
  const DesktopShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// The sidebar, with the capability each destination needs to be worth showing.
  ///
  /// Gating is **UX only** — the backend refuses regardless, and hiding a control has
  /// never been security (`ARCHITECTURE.md` §8.4). What it buys is an interface that does
  /// not offer a Data Entry user an Administration section they will only be refused
  /// from. Note that these are capabilities, never role names: nothing anywhere asks
  /// `if (role == 'owner')`.
  static const List<({IconData icon, String label, Capability? requires})>
  _destinations = [
    (icon: Icons.dashboard_outlined, label: 'Overview', requires: null),
    (icon: Icons.receipt_long_outlined, label: 'Transactions', requires: null),
    (
      icon: Icons.analytics_outlined,
      label: 'Analytics',
      requires: Capability.reportsView,
    ),
    (
      icon: Icons.description_outlined,
      label: 'Reports',
      requires: Capability.reportsView,
    ),
    (
      icon: Icons.inventory_2_outlined,
      label: 'Masters',
      requires: Capability.mastersView,
    ),
    (
      icon: Icons.admin_panel_settings_outlined,
      label: 'Administration',
      requires: Capability.usersManage,
    ),
  ];

  /// Branch indices this principal may reach, in sidebar order.
  ///
  /// The visible list is filtered but the *branch* indices are preserved, so hiding a
  /// destination can never quietly navigate somebody to the wrong one — a bug that would
  /// be invisible in review and obvious only to whoever ended up on the wrong screen.
  static List<int> visibleBranches(Principal principal) => [
    for (var i = 0; i < _destinations.length; i++)
      if (_destinations[i].requires == null ||
          principal.canAnywhere(_destinations[i].requires!))
        i,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = visibleBranches(ref.watch(principalProvider));
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            branches: visible,
            selectedIndex: navigationShell.currentIndex,
            onSelect: (index) => navigationShell.goBranch(
              index,
              initialLocation: index == navigationShell.currentIndex,
            ),
          ),
          const VerticalDivider(width: 1, color: AppColors.hairline),
          Expanded(
            child: ColoredBox(color: AppColors.paper, child: navigationShell),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.branches,
    required this.selectedIndex,
    required this.onSelect,
  });

  /// Branch indices to show, in order. Filtered by capability; the indices themselves
  /// are the router's, so selection cannot drift.
  final List<int> branches;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 248,
      child: ColoredBox(
        color: AppColors.surfaceMuted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KRISHNA IMPERIAL', style: AppTypography.overline),
                  SizedBox(height: AppSpacing.xxs),
                  Text('Management MIS', style: AppTypography.subheading),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: branches.length,
                itemBuilder: (context, index) {
                  final branch = branches[index];
                  final destination = DesktopShell._destinations[branch];
                  final selected = branch == selectedIndex;
                  return Semantics(
                    selected: selected,
                    button: true,
                    child: InkWell(
                      onTap: () => onSelect(branch),
                      // A finance workstation is driven by keyboard as much as mouse,
                      // so focus must be *visible*. Without these the caret moves
                      // through the sidebar invisibly.
                      focusColor: AppColors.brassWash,
                      hoverColor: AppColors.surfaceSunken,
                      child: Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.brassWash : null,
                          border: Border(
                            left: BorderSide(
                              color: selected
                                  ? AppColors.brass
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              destination.icon,
                              size: 17,
                              color: selected
                                  ? AppColors.brass
                                  : AppColors.inkMuted,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            // Expanded + ellipsis: the selected item renders in a
                            // heavier weight, so a label that just fits unselected can
                            // otherwise overflow the instant it is chosen.
                            Expanded(
                              child: Text(
                                destination.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.body.copyWith(
                                  color: selected
                                      ? AppColors.ink
                                      : AppColors.inkMuted,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Phase 1 — Foundation\nNo financial data yet',
                style: AppTypography.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
