/// Masters, routed to the right experience for the platform.
///
/// Three sections live here — the hierarchy, vendors and tax rules — because that is how
/// the master spec groups them (§19). Windows switches between them with a segmented
/// control above a persistent workspace; Android picks one first, then drills in, so a
/// phone never has to render three surfaces at once.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/features/masters/presentation/android_masters_view.dart';
import 'package:krishna_mis/features/masters/presentation/windows_masters_view.dart';
import 'package:krishna_mis/features/tax/presentation/tax_rates_view.dart';
import 'package:krishna_mis/features/vendors/presentation/vendors_view.dart';

enum MastersSection {
  hierarchy(
    'Hierarchy',
    Icons.account_tree_outlined,
    'Business units, departments, sections and categories',
  ),
  vendors('Vendors', Icons.storefront_outlined, 'Suppliers you buy from'),
  taxRates(
    'Tax rules',
    Icons.percent_outlined,
    'Date-effective rates for each revenue category',
  );

  const MastersSection(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;
}

final mastersSectionProvider =
    NotifierProvider<MastersSectionState, MastersSection?>(
      MastersSectionState.new,
    );

class MastersSectionState extends Notifier<MastersSection?> {
  /// Windows opens on the hierarchy; Android starts with nothing chosen so the phone
  /// shows its section list first. The view sets the initial value it wants.
  @override
  MastersSection? build() => null;

  void select(MastersSection? section) => state = section;
}

class MastersPage extends ConsumerWidget {
  const MastersPage({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      shellKind == AppShellKind.desktop
      ? const _WindowsMasters()
      : const _AndroidMasters();
}

class _WindowsMasters extends ConsumerWidget {
  const _WindowsMasters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section =
        ref.watch(mastersSectionProvider) ?? MastersSection.hierarchy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              SegmentedButton<MastersSection>(
                segments: [
                  for (final s in MastersSection.values)
                    ButtonSegment(
                      value: s,
                      icon: Icon(s.icon, size: 16),
                      label: Text(s.label),
                    ),
                ],
                selected: {section},
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  selectedBackgroundColor: AppColors.brassWash,
                  selectedForegroundColor: AppColors.ink,
                  foregroundColor: AppColors.inkMuted,
                  side: const BorderSide(color: AppColors.hairlineStrong),
                  textStyle: AppTypography.body,
                ),
                onSelectionChanged: (values) => ref
                    .read(mastersSectionProvider.notifier)
                    .select(values.first),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  section.description,
                  style: AppTypography.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (section) {
            MastersSection.hierarchy => const WindowsMastersView(),
            MastersSection.vendors => const VendorsView(isDesktop: true),
            MastersSection.taxRates => const TaxRatesView(isDesktop: true),
          },
        ),
      ],
    );
  }
}

class _AndroidMasters extends ConsumerWidget {
  const _AndroidMasters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(mastersSectionProvider);

    if (section == null) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MASTERS', style: AppTypography.overline),
                const SizedBox(height: AppSpacing.xxs),
                Text('Set-up', style: AppTypography.subheading),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final s in MastersSection.values)
            InkWell(
              focusColor: AppColors.brassWash,
              onTap: () => ref.read(mastersSectionProvider.notifier).select(s),
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.hairline)),
                ),
                child: Row(
                  children: [
                    Icon(s.icon, size: 20, color: AppColors.brass),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            s.label,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            s.description,
                            style: AppTypography.caption,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.inkFaint,
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(mastersSectionProvider.notifier).select(null);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (section != MastersSection.hierarchy)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    tooltip: 'Back to set-up',
                    onPressed: () =>
                        ref.read(mastersSectionProvider.notifier).select(null),
                  ),
                  Text(section.label, style: AppTypography.subheading),
                ],
              ),
            ),
          if (section != MastersSection.hierarchy) const Divider(height: 1),
          Expanded(
            child: switch (section) {
              MastersSection.hierarchy => const _AndroidHierarchyWithBack(),
              MastersSection.vendors => const VendorsView(isDesktop: false),
              MastersSection.taxRates => const TaxRatesView(isDesktop: false),
            },
          ),
        ],
      ),
    );
  }
}

/// The hierarchy drill-down, with an extra step back out to the section list once the
/// user is at its own top level.
class _AndroidHierarchyWithBack extends ConsumerWidget {
  const _AndroidHierarchyWithBack();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(androidMasterPathProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (path.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  tooltip: 'Back to set-up',
                  onPressed: () =>
                      ref.read(mastersSectionProvider.notifier).select(null),
                ),
                Text('Hierarchy', style: AppTypography.subheading),
              ],
            ),
          ),
        const Expanded(child: AndroidMastersView()),
      ],
    );
  }
}
