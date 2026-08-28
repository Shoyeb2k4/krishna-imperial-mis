/// Shows a record's synchronisation state.
///
/// Visible but not intrusive on Android; explicit on the Windows sync-health surface.
/// Never colour alone — every state carries its own glyph and its own words.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';

class SyncStateChip extends StatelessWidget {
  const SyncStateChip(this.state, {super.key, this.compact = false});

  final SyncState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (state) {
      SyncState.synced => (AppColors.syncSynced, Icons.check_circle_outline),
      SyncState.pendingSync => (AppColors.syncPending, Icons.schedule),
      SyncState.syncing => (AppColors.neutral, Icons.sync),
      SyncState.syncFailed => (AppColors.syncFailed, Icons.error_outline),
      SyncState.conflict => (AppColors.syncConflict, Icons.priority_high),
      // Refused outright rather than contested. A distinct glyph, because a user who
      // has lost a permission is not being asked to choose between two versions.
      SyncState.rejected => (AppColors.syncConflict, Icons.block_outlined),
    };

    return Semantics(
      label: 'Sync status: ${state.label}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.allSmall,
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 12 : 14, color: color),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                state.label,
                style: AppTypography.caption.copyWith(
                  color: color,
                  fontWeight: state.needsAttention
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
