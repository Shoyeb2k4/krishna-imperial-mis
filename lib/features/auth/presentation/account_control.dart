/// Who is signed in, how current their access is, and how to leave.
///
/// This exists because both shells previously had no way out of a session at all. On a
/// shared back-office workstation that is not a missing convenience — it is the reason a
/// second person ends up entering their day's takings under somebody else's account. The
/// signed-in identity is therefore stated permanently in the chrome, not hidden behind a
/// menu, and signing out is one deliberate action away from it.
///
/// Signing out ends the session and clears the cached authority. It does **not** delete
/// the local database or the outbox: queued entries belong to whoever queued them and
/// exist nowhere else yet (`ARCHITECTURE.md` §8.2, D-050).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/features/auth/presentation/session_gate.dart';

class AccountControl extends ConsumerWidget {
  const AccountControl({this.dense = false, super.key});

  /// Compact enough for a phone's list header; the sidebar footer uses the full form.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session is! SessionReady) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.all(dense ? AppSpacing.md : AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('SIGNED IN', style: AppTypography.overline),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            session.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(_scopeSummary(session), style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          const AuthorityFreshnessChip(),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _confirmSignOut(context, ref),
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Sign out'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.inkMuted,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// States the scope in the same language the permission model uses, so a manager can
  /// see at a glance whether they are looking at one property or the company.
  static String _scopeSummary(SessionReady session) {
    if (session.authority.holdsOrgWideGrant) return 'All business units';
    final count = session.authority.scopedUnits.length;
    return switch (count) {
      0 => 'No business unit',
      1 => '1 business unit',
      _ => '$count business units',
    };
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final pending = await ref.read(outboxProvider).unsyncedCount();
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('Sign out?'),
        content: Text(
          pending == 0
              ? 'Your access will need to be verified again the next time you sign in.'
              : 'There ${pending == 1 ? 'is' : 'are'} $pending '
                    '${pending == 1 ? 'entry' : 'entries'} still waiting to reach the '
                    'server. Signing out keeps them — nothing queued is deleted — but '
                    'they stay yours and are only sent when you sign in again.',
          style: AppTypography.bodyMuted,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ink,
              foregroundColor: AppColors.inkInverse,
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(sessionProvider.notifier).signOut();
    }
  }
}
