/// Signing in to Krishna Imperial MIS.
///
/// The first thing anybody sees, so it carries the product's identity rather than a
/// framework's: off-white paper, charcoal ink, a restrained brass rule, and type that
/// belongs to serious financial software rather than a starter template.
///
/// The two platforms get genuinely different layouts, not one layout at two widths. On a
/// phone the form fills the screen, sits above the keyboard and scrolls; on the desktop
/// it is a constrained card on a quiet ground, with the field widths a form deserves
/// rather than stretched across a 1920-pixel monitor.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({required this.shellKind, super.key});

  final AppShellKind shellKind;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscured = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(sessionProvider.notifier)
        .signIn(email: _email.text, password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final busy = session is Authenticating || session is VerifyingAuthority;
    final failure = session is Unauthenticated ? session.failure : null;
    final isDesktop = widget.shellKind == AppShellKind.desktop;

    final form = _SignInForm(
      formKey: _formKey,
      email: _email,
      password: _password,
      emailFocus: _emailFocus,
      passwordFocus: _passwordFocus,
      obscured: _obscured,
      busy: busy,
      failure: failure,
      isDesktop: isDesktop,
      onToggleObscured: () => setState(() => _obscured = !_obscured),
      onSubmit: busy ? null : _submit,
    );

    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: isDesktop
            ? _DesktopFrame(child: form)
            : _PhoneFrame(child: form),
      ),
    );
  }
}

/// Phone: the form owns the screen, scrolls above the keyboard, and never overflows on a
/// small device.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      // `viewInsets` is what keeps the submit button reachable when the keyboard is up.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: constraints.maxHeight - AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [child],
        ),
      ),
    ),
  );
}

/// Desktop: a constrained sign-in surface on a quiet ground. Nothing stretches.
class _DesktopFrame extends StatelessWidget {
  const _DesktopFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.allLarge,
            border: Border.all(color: AppColors.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: child,
          ),
        ),
      ),
    ),
  );
}

class _SignInForm extends StatelessWidget {
  const _SignInForm({
    required this.formKey,
    required this.email,
    required this.password,
    required this.emailFocus,
    required this.passwordFocus,
    required this.obscured,
    required this.busy,
    required this.failure,
    required this.isDesktop,
    required this.onToggleObscured,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController email;
  final TextEditingController password;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final bool obscured;
  final bool busy;
  final SignInFailure? failure;
  final bool isDesktop;
  final VoidCallback onToggleObscured;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Krishna Imperial MIS', style: AppTypography.display),
        const SizedBox(height: AppSpacing.xs),
        Container(width: 44, height: 2, color: AppColors.brass),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Management and profitability for Crystal Canopy Rooftop and '
          'Hotel Krishna Imperial.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.xxl),

        _Field(
          label: 'Email',
          controller: email,
          focusNode: emailFocus,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          onSubmitted: (_) => passwordFocus.requestFocus(),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'Enter your email address'
              : null,
        ),
        const SizedBox(height: AppSpacing.lg),

        _Field(
          label: 'Password',
          controller: password,
          focusNode: passwordFocus,
          enabled: !busy,
          obscureText: obscured,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => onSubmit?.call(),
          validator: (value) =>
              (value == null || value.isEmpty) ? 'Enter your password' : null,
          suffix: IconButton(
            onPressed: busy ? null : onToggleObscured,
            icon: Icon(
              obscured
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
              color: AppColors.inkFaint,
            ),
            tooltip: obscured ? 'Show password' : 'Hide password',
          ),
        ),

        if (failure != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _FailureNotice(failure: failure!),
        ],

        const SizedBox(height: AppSpacing.xxl),
        _SubmitButton(busy: busy, onPressed: onSubmit),
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.validator,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.onSubmitted,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTypography.overline),
      const SizedBox(height: AppSpacing.xs),
      TextFormField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        style: AppTypography.body,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            // A comfortable touch target on a phone; tighter on a desktop form.
            vertical: AppSpacing.md,
          ),
          suffixIcon: suffix,
          border: const OutlineInputBorder(
            borderRadius: AppRadius.allSmall,
            borderSide: BorderSide(color: AppColors.hairlineStrong),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: AppRadius.allSmall,
            borderSide: BorderSide(color: AppColors.hairlineStrong),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: AppRadius.allSmall,
            borderSide: BorderSide(color: AppColors.brass, width: 2),
          ),
        ),
      ),
    ],
  );
}

/// The failure notice.
///
/// Never a raw Supabase or Postgres message: the user is told what happened and what to
/// do, and the sign of the problem is carried by an icon and words, not by colour alone.
class _FailureNotice extends StatelessWidget {
  const _FailureNotice({required this.failure});
  final SignInFailure failure;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.negative.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 16, color: AppColors.negative),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            failure.message,
            style: AppTypography.caption.copyWith(color: AppColors.ink),
          ),
        ),
      ],
    ),
  );
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.ink,
      foregroundColor: AppColors.inkInverse,
      disabledBackgroundColor: AppColors.hairlineStrong,
      // Comfortable on a phone, unremarkable on a desktop.
      minimumSize: const Size.fromHeight(48),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.allSmall),
      textStyle: AppTypography.subheading,
    ),
    child: busy
        ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.inkInverse,
            ),
          )
        : const Text('Sign in'),
  );
}

/// Wraps the sign-in surface so Enter submits from anywhere on the desktop, where there
/// is no on-screen keyboard action to rely on.
class SignInShortcuts extends StatelessWidget {
  const SignInShortcuts({
    required this.onSubmit,
    required this.child,
    super.key,
  });

  final VoidCallback onSubmit;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.enter): onSubmit},
    child: child,
  );
}
