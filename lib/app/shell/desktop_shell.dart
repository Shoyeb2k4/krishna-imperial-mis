/// Windows shell: the management, finance and reporting workstation.
///
/// Persistent sidebar, dense tables, keyboard and mouse (master spec §19). Not the
/// phone UI stretched across a monitor.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const List<({IconData icon, String label})> _destinations = [
    (icon: Icons.dashboard_outlined, label: 'Overview'),
    (icon: Icons.receipt_long_outlined, label: 'Transactions'),
    (icon: Icons.analytics_outlined, label: 'Analytics'),
    (icon: Icons.description_outlined, label: 'Reports'),
    (icon: Icons.inventory_2_outlined, label: 'Masters'),
    (icon: Icons.admin_panel_settings_outlined, label: 'Administration'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
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
  const _Sidebar({required this.selectedIndex, required this.onSelect});

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
                itemCount: DesktopShell._destinations.length,
                itemBuilder: (context, index) {
                  final destination = DesktopShell._destinations[index];
                  final selected = index == selectedIndex;
                  return Semantics(
                    selected: selected,
                    button: true,
                    child: InkWell(
                      onTap: () => onSelect(index),
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
