/// Section heading with an optional eyebrow and trailing action.
///
/// Hierarchy comes from type and space, not from boxes and shadows.
library;

import 'package:flutter/widgets.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    super.key,
    this.eyebrow,
    this.subtitle,
    this.trailing,
  });

  final String title;

  /// Small tracked uppercase label above the title, e.g. `CRYSTAL CANOPY ROOFTOP`.
  final String? eyebrow;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(eyebrow!.toUpperCase(), style: AppTypography.overline),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(title, style: AppTypography.heading),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: AppTypography.bodyMuted),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.lg),
            trailing!,
          ],
        ],
      ),
    );
  }
}
