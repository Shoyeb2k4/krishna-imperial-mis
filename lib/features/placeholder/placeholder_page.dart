/// A destination that holds no working module in this version.
///
/// Phase 1 used it for every destination, to prove the navigation architecture without
/// faking finished features. In V1 only Administration remains, and it states plainly
/// who handles those acts rather than promising a future phase (D-343, D-348).
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/components/section_header.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

/// The approved V1 wording for the Administration destination (D-343, D-348).
const administrationNotice =
    'Users, roles, period close and audit review are handled by the project '
    'administrator in this version.';

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    required this.title,
    required this.notice,
    super.key,
    this.eyebrow,
    this.summary,
  });

  final String title;

  /// One plain sentence saying what this destination offers in this version.
  final String notice;
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
                    Icons.info_outline,
                    size: 18,
                    color: AppColors.brass,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      notice,
                      key: const Key('placeholder-notice'),
                      style: AppTypography.bodyMuted,
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
