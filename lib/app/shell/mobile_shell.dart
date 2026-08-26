/// Android shell: Home · Transactions · [ + ] · Reports · More.
///
/// The operational entry device. The central action opens a fast sheet rather than
/// navigating away, because recording a bill must never cost the user their place
/// (master spec §18).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

class MobileShell extends StatelessWidget {
  const MobileShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openQuickAdd(context),
        backgroundColor: AppColors.brass,
        foregroundColor: AppColors.inkInverse,
        elevation: AppElevation.raised,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.allLarge),
        tooltip: 'Add expense or sale',
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        elevation: AppElevation.flat,
        height: 64,
        padding: EdgeInsets.zero,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: Row(
            // Stretch so each tab fills the bar's height rather than guessing at it.
            // A fixed height here overflows as soon as the user raises their system
            // font scale, which is common on the phones these are used on.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tab(
                context,
                index: 0,
                icon: Icons.dashboard_outlined,
                label: 'Home',
              ),
              _tab(
                context,
                index: 1,
                icon: Icons.receipt_long_outlined,
                label: 'Transactions',
              ),
              const Spacer(), // reserved for the docked [ + ]
              _tab(
                context,
                index: 2,
                icon: Icons.insert_chart_outlined,
                label: 'Reports',
              ),
              _tab(context, index: 3, icon: Icons.more_horiz, label: 'More'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = navigationShell.currentIndex == index;
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: label,
        child: InkWell(
          onTap: () =>
              navigationShell.goBranch(index, initialLocation: selected),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.brass : AppColors.inkFaint,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontSize: 10,
                  color: selected ? AppColors.ink : AppColors.inkFaint,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openQuickAdd(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadius.large),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: const BoxDecoration(
                color: AppColors.hairlineStrong,
                borderRadius: AppRadius.allSmall,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: const Text('Add Expense'),
              subtitle: const Text('Phase 3 — Expense Engine'),
              enabled: false,
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.point_of_sale_outlined),
              title: const Text('Add Sale'),
              subtitle: const Text('Phase 4 — Revenue Engine'),
              enabled: false,
              onTap: () {},
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
