/// Small shared pieces for the master-management surfaces.
///
/// Both platforms use these, so status, usage provenance and empty states read the same
/// whether the manager is at the workstation or on their phone.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/masters/master_usage.dart';

/// Active or archived. Never colour alone — the word is always present.
class MasterStatusChip extends StatelessWidget {
  const MasterStatusChip({
    required this.isArchived,
    super.key,
    this.compact = false,
  });

  final bool isArchived;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = isArchived ? AppColors.inkFaint : AppColors.positive;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: isArchived ? AppColors.surfaceSunken : AppColors.surface,
        borderRadius: AppRadius.allSmall,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        isArchived ? 'Archived' : 'Active',
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 10 : 12,
        ),
      ),
    );
  }
}

/// The immutable code, shown as the identifier it is.
///
/// This is not an implementation id — it is the stable business code the owner will see
/// in exports and audit trails, and the thing that does *not* move when a label is
/// corrected. Database ids are never shown.
class CodeBadge extends StatelessWidget {
  const CodeBadge(this.code, {super.key});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'Permanent code. It never changes, even if the name is corrected.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: AppRadius.allSmall,
        ),
        child: Text(
          code,
          style: AppTypography.caption.copyWith(
            color: AppColors.inkMuted,
            fontFeatures: AppTypography.tabular,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// Historical usage, **with its provenance stated**.
///
/// A cached count is never dressed up as the whole truth. When the figure is a local
/// lower bound the widget says so, because someone is about to decide whether renaming
/// or archiving is safe (owner requirement §6).
class UsageNote extends StatelessWidget {
  const UsageNote(this.usage, {super.key});

  final MasterUsage usage;

  @override
  Widget build(BuildContext context) {
    final authoritative = usage.isAuthoritative;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          authoritative ? Icons.verified_outlined : Icons.cloud_off_outlined,
          size: 14,
          color: authoritative ? AppColors.positive : AppColors.caution,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(usage.summary, style: AppTypography.body),
              if (!authoritative) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'This device holds only part of the history. The server is the '
                  'authority on how much a record is used.',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.caution,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A labelled value in a detail panel. Absent values are omitted, not shown blank.
class DetailField extends StatelessWidget {
  const DetailField({required this.label, super.key, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (value == null && child == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppTypography.overline),
          const SizedBox(height: AppSpacing.xs),
          child ?? Text(value!, style: AppTypography.body),
        ],
      ),
    );
  }
}

/// Empty and placeholder states, kept deliberate rather than blank.
class MasterEmptyState extends StatelessWidget {
  const MasterEmptyState({
    required this.title,
    required this.message,
    super.key,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: AppColors.inkFaint),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: AppTypography.subheading,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: AppTypography.bodyMuted,
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet inline error. Financial software should explain, not shout.
class MasterErrorState extends StatelessWidget {
  const MasterErrorState(this.message, {super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.negative,
                size: 20,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Could not load this', style: AppTypography.subheading),
              const SizedBox(height: AppSpacing.sm),
              SelectableText(message, style: AppTypography.bodyMuted),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.lg),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet loading placeholder.
///
/// Deliberately **not** a spinner. These screens read a local encrypted database and are
/// usually ready within a frame or two; a spinning indicator would flash and draw the eye
/// for no reason. A calm line of text also keeps the surface static, which matters more
/// than it sounds — an indeterminate animation never stops scheduling frames, which makes
/// the screen impossible to settle in a test and keeps a timer alive after teardown.
class QuietLoading extends StatelessWidget {
  const QuietLoading({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Text(label, style: AppTypography.bodyMuted),
    ),
  );
}
