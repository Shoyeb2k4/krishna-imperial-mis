/// What the application shows for each session state.
///
/// One gate, so no screen has to decide for itself whether it may render. The states that
/// look alike are kept apart here for the same reason they are kept apart in the domain:
/// signed-in-but-unverified is not signed-in, and showing the shell for it would hand
/// somebody navigation the server has never agreed to.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/features/auth/presentation/sign_in_screen.dart';

class SessionGate extends ConsumerWidget {
  const SessionGate({required this.shellKind, required this.child, super.key});

  final AppShellKind shellKind;

  /// The application proper. Built only for a session the server has vouched for.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    if (session is SessionReady) return child;

    // The gate's own screens are built by `MaterialApp.builder`, which sits *above* the
    // router's Navigator — so there is no Overlay in scope. Without one, a tooltip and a
    // text field's selection handles both throw rather than render, which is precisely
    // what an on-device run caught and a widget test wrapped in its own MaterialApp did
    // not. One Overlay here restores the ancestor those widgets need, without giving the
    // pre-session screens a Navigator and the back-button behaviour that comes with it.
    return Overlay(
      initialEntries: [
        OverlayEntry(builder: (context) => _screenFor(context, ref, session)),
      ],
    );
  }

  Widget _screenFor(BuildContext context, WidgetRef ref, SessionState session) {
    return switch (session) {
      Unauthenticated() ||
      Authenticating() => SignInScreen(shellKind: shellKind),

      VerifyingAuthority() => const _Waiting(
        message: 'Checking what you have access to…',
      ),

      // Authenticated, and this device has never been told what they may do. Nothing is
      // offered — not a reduced menu, not a read-only view. Guessing here is the whole
      // failure mode the fail-closed rule exists to prevent (§8).
      AuthorityUnverified(:final message) => _Blocked(
        title: 'Access not yet verified',
        message: message,
        actionLabel: 'Try again',
        onAction: () => ref.read(sessionProvider.notifier).refreshAuthority(),
        onSignOut: () => ref.read(sessionProvider.notifier).signOut(),
      ),

      SessionExpired(:final message) => _Blocked(
        title: 'Session expired',
        message: message,
        actionLabel: 'Sign in again',
        onAction: () => ref.read(sessionProvider.notifier).signOut(),
      ),

      // Handled above, before the Overlay is built.
      SessionReady() => child,
    };
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.brass,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(message, style: AppTypography.bodyMuted),
        ],
      ),
    ),
  );
}

/// Signed in, but going no further. Says why, and offers the two things that can help.
class _Blocked extends StatelessWidget {
  const _Blocked({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.onSignOut,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline, color: AppColors.caution),
              const SizedBox(height: AppSpacing.lg),
              Text(title, style: AppTypography.heading),
              const SizedBox(height: AppSpacing.sm),
              Text(message, style: AppTypography.bodyMuted),
              const SizedBox(height: AppSpacing.xxl),
              Row(
                children: [
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      foregroundColor: AppColors.inkInverse,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.allSmall,
                      ),
                    ),
                    child: Text(actionLabel),
                  ),
                  if (onSignOut != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    TextButton(
                      onPressed: onSignOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A quiet, always-available statement of how current the permission state is.
///
/// Not a banner across every page. It sits in the shell's chrome and says something only
/// when there is something to say — which is what makes it worth reading when it does
/// (§10).
class AuthorityFreshnessChip extends ConsumerWidget {
  const AuthorityFreshnessChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (session is! SessionReady || !session.isStale) {
      return const SizedBox.shrink();
    }

    return Tooltip(
      message:
          'Your access was last confirmed on '
          '${session.authority.resolvedAt.toLocal()}. Administrative changes stay '
          'pending until the server can be reached.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.allSmall,
          border: Border.all(color: AppColors.caution.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 12,
              color: AppColors.caution,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Using last verified access',
              style: AppTypography.caption.copyWith(color: AppColors.caution),
            ),
          ],
        ),
      ),
    );
  }
}
