/// Phase 1 placeholder destination.
///
/// The objective of Phase 1 is to prove the navigation architecture on both platforms,
/// not to fake finished features. Each destination states plainly which phase will
/// build it, so nobody — owner or engineer — mistakes scaffolding for a working module.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/components/section_header.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    required this.title,
    required this.arrivesIn,
    super.key,
    this.eyebrow,
    this.summary,
  });

  final String title;

  /// e.g. `Phase 3 — Expense Engine`.
  final String arrivesIn;
  final String? eyebrow;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final density = MediaQuery.sizeOf(context).width >= 900
        ? AppDensity.compact
        : AppDensity.comfortable;

    return Padding(
      padding: EdgeInsets.all(density.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(eyebrow: eyebrow, title: title, subtitle: summary),
          const Divider(),
          const SizedBox(height: AppSpacing.xl),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.brassWash,
              borderRadius: AppRadius.allMedium,
              border: Border.all(color: AppColors.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.construction,
                    size: 18,
                    color: AppColors.brass,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Not built yet', style: AppTypography.subheading),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'This destination exists so the navigation architecture can '
                          'be verified on both Android and Windows. It will be built '
                          'in $arrivesIn.',
                          style: AppTypography.bodyMuted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
