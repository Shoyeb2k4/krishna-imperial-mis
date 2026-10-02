/// The screen a person sees when the application cannot start, and the reset flow.
///
/// It shows **no raw technical text** — no SQLite or Drift message, no file path, no
/// secure-storage detail, no stack trace. Those go to the developer log (D-316, D-329).
/// It says what happened, that nothing was changed, and what will help; it offers
/// "Reset local data and download again" only when [StartupFailure.permitsReset], and
/// only behind an explanation of what would be lost and a typed confirmation (D-330).
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/app/startup/startup_failure.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/local/local_store_recovery.dart';

/// The word a person types to confirm a reset. Exact and in capitals, so it cannot be
/// typed by accident or satisfied by autocorrect.
const String resetConfirmationWord = 'RESET';

/// What the reset screen needs from recovery. A seam, so the flow is testable without
/// touching a real installation.
abstract interface class StartupRecoveryActions {
  /// What setting the local data aside would lose. Never throws.
  Future<UnsyncedWorkAssessment> assess();

  /// Sets the local data aside and leaves the installation ready to start empty.
  Future<void> reset();
}

/// [StartupRecoveryActions] over the real [LocalStoreRecovery].
class LocalStoreRecoveryActions implements StartupRecoveryActions {
  const LocalStoreRecoveryActions(this.recovery, {required this.reason});

  final LocalStoreRecovery recovery;
  final StartupFailureKind reason;

  @override
  Future<UnsyncedWorkAssessment> assess() => recovery.assess();

  @override
  Future<void> reset() => recovery.setAsideAndReset(reason: reason.name);
}

/// The whole application while it cannot start.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.failure,
    required this.onTryAgain,
    this.configurationMessage,
    this.recovery,
  });

  final StartupFailure failure;

  /// Starts the application again from the beginning. Also how a completed reset hands
  /// over: the next start opens the empty database, or — if that fails too — shows this
  /// screen again with that failure. A reset never claims success on its own.
  final Future<void> Function() onTryAgain;

  /// For a configuration failure only: the build's own curated explanation of what to fix
  /// (`ConfigurationProblem`), written to be shown and never containing key material.
  final String? configurationMessage;

  /// Present only when [StartupFailure.permitsReset]; the reset is never offered
  /// otherwise, whatever is passed.
  final StartupRecoveryActions? recovery;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Krishna Imperial MIS',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(density: AppDensity.comfortable),
    home: StartupFailureScreen(
      failure: failure,
      onTryAgain: onTryAgain,
      configurationMessage: configurationMessage,
      recovery: failure.permitsReset ? recovery : null,
    ),
  );
}

/// Plain words for each kind of failure.
({String title, String body}) startupFailureWording(
  StartupFailureKind kind,
) => switch (kind) {
  StartupFailureKind.configuration => (
    title: 'This build is not configured safely',
    body:
        'This build is configured incorrectly and has been stopped before it '
        'could connect to anything. Nothing has been changed or deleted.',
  ),
  StartupFailureKind.keyStoreUnavailable => (
    title: "The device's secure storage is not available",
    body:
        'The key that protects the data on this device could not be read from the '
        "device's secure storage. This can happen just after the device restarts. "
        'Nothing has been changed or deleted. Unlock the device if it is locked, '
        'then try again.',
  ),
  StartupFailureKind.localDataUnreadable => (
    title: 'Local data cannot be opened',
    body:
        'The data stored on this device could not be opened. Nothing has been '
        'changed or deleted. Try again first. If it still cannot be opened, you can '
        'set the local data aside and download your data from the server again.',
  ),
  StartupFailureKind.upgradeFailed => (
    title: 'Local data could not be updated for this version',
    body:
        'This version of the app could not update the data stored on this device. '
        'Nothing was changed: the data is exactly as it was before. Try again. If it '
        'still fails, an update to the app may fix it, or you can set the local data '
        'aside and download your data from the server again.',
  ),
  StartupFailureKind.inUse => (
    title: 'Local data is in use',
    body:
        'Another copy of Krishna Imperial MIS, or another program, is using the data '
        'on this device. Close any other copy of the app, then try again. Nothing '
        'has been changed or deleted.',
  ),
  StartupFailureKind.storage => (
    title: "The device's storage could not be used",
    body:
        'The app could not read or write its data on this device. There may not be '
        'enough free space. Free some space on this device, then try again. Nothing '
        'has been deleted.',
  ),
  StartupFailureKind.unexpected => (
    title: 'The application could not start',
    body:
        'Something unexpected stopped the app from starting. Nothing has been '
        'changed or deleted. Try again. If it keeps happening, tell your '
        'administrator and quote the reference below.',
  ),
};

class StartupFailureScreen extends StatefulWidget {
  const StartupFailureScreen({
    super.key,
    required this.failure,
    required this.onTryAgain,
    this.configurationMessage,
    this.recovery,
  });

  final StartupFailure failure;
  final Future<void> Function() onTryAgain;
  final String? configurationMessage;
  final StartupRecoveryActions? recovery;

  @override
  State<StartupFailureScreen> createState() => _StartupFailureScreenState();
}

class _StartupFailureScreenState extends State<StartupFailureScreen> {
  bool _retrying = false;

  Future<void> _tryAgain() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onTryAgain();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = startupFailureWording(widget.failure.kind);
    final recovery = widget.failure.permitsReset ? widget.recovery : null;
    return _Frame(
      icon: Icons.lock_outline,
      children: [
        Text(
          words.title,
          key: const Key('startup-failure-title'),
          style: AppTypography.heading,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(words.body, style: AppTypography.bodyMuted),
        if (widget.configurationMessage case final message?) ...[
          const SizedBox(height: AppSpacing.md),
          Text(message, style: AppTypography.body),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Reference: ${widget.failure.reference}',
          key: const Key('startup-failure-reference'),
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.xl),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton(
              key: const Key('startup-try-again'),
              onPressed: _retrying ? null : _tryAgain,
              child: Text(_retrying ? 'Starting…' : 'Try again'),
            ),
            if (recovery != null)
              OutlinedButton(
                key: const Key('startup-open-reset'),
                onPressed: _retrying
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ResetLocalDataScreen(
                            recovery: recovery,
                            onReset: widget.onTryAgain,
                          ),
                        ),
                      ),
                child: const Text('Reset local data and download again'),
              ),
          ],
        ),
      ],
    );
  }
}

/// The destructive step: explanation, what would be lost, typed confirmation.
class ResetLocalDataScreen extends StatefulWidget {
  const ResetLocalDataScreen({
    super.key,
    required this.recovery,
    required this.onReset,
  });

  final StartupRecoveryActions recovery;

  /// Called after a completed reset: starts the application again. Whatever that start
  /// produces — the app, or a new failure — replaces this screen.
  final Future<void> Function() onReset;

  @override
  State<ResetLocalDataScreen> createState() => _ResetLocalDataScreenState();
}

enum _ResetPhase { confirming, working, failed }

class _ResetLocalDataScreenState extends State<ResetLocalDataScreen> {
  final _confirmation = TextEditingController();
  late final Future<UnsyncedWorkAssessment> _assessment = _assess();
  _ResetPhase _phase = _ResetPhase.confirming;

  Future<UnsyncedWorkAssessment> _assess() async {
    try {
      return await widget.recovery.assess();
    } on Object {
      return const UnsyncedWorkUnknown(UnsyncedWorkUnknownReason.unreadable);
    }
  }

  bool get _confirmed => _confirmation.text.trim() == resetConfirmationWord;

  @override
  void initState() {
    super.initState();
    _confirmation.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (!_confirmed || _phase == _ResetPhase.working) return;
    setState(() => _phase = _ResetPhase.working);
    try {
      await widget.recovery.reset();
    } on Object {
      if (mounted) setState(() => _phase = _ResetPhase.failed);
      return;
    }
    // Not a success message: the next start decides what is shown.
    await widget.onReset();
  }

  @override
  Widget build(BuildContext context) {
    final working = _phase == _ResetPhase.working;
    return _Frame(
      icon: Icons.warning_amber_outlined,
      children: [
        const Text(
          'Reset local data and download again',
          style: AppTypography.heading,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'This sets aside the data stored on this device and starts again with empty '
          'local storage. After you sign in, the app downloads again everything you are '
          'allowed to see from the server.',
          style: AppTypography.body,
        ),
        const SizedBox(height: AppSpacing.md),
        FutureBuilder<UnsyncedWorkAssessment>(
          future: _assessment,
          builder: (context, snapshot) => Text(
            snapshot.hasData
                ? unsyncedWorkStatement(snapshot.requireData)
                : 'Checking the local data for entries that were never sent…',
            key: const Key('reset-unsynced-statement'),
            style: AppTypography.body.copyWith(
              color: snapshot.hasData && _isRisk(snapshot.requireData)
                  ? AppColors.negative
                  : AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'The local data is moved aside on this device, not erased, but this app will '
          'not open it again.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          key: const Key('reset-confirmation-field'),
          controller: _confirmation,
          enabled: !working,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Type $resetConfirmationWord to confirm',
          ),
        ),
        if (_phase == _ResetPhase.failed) ...[
          const SizedBox(height: AppSpacing.md),
          const Text(
            'The local data could not be set aside. Nothing was removed, and the data is '
            'where it was. Close any other copy of the app, make sure the device has free '
            'space, then try again.',
            key: Key('reset-failed'),
            style: TextStyle(color: AppColors.negative),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton(
              key: const Key('reset-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.negative,
              ),
              onPressed: _confirmed && !working ? _reset : null,
              child: Text(working ? 'Setting aside…' : 'Reset local data'),
            ),
            TextButton(
              key: const Key('reset-cancel'),
              onPressed: working ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}

bool _isRisk(UnsyncedWorkAssessment a) => switch (a) {
  NoLocalDataFound() => false,
  UnsyncedWorkCounted(:final nothingUnsent) => !nothingUnsent,
  UnsyncedWorkUnknown() => true,
};

/// What a person is told about unsent work before a reset. Never "everything is
/// synced" unless the local data was read and holds nothing unsent.
String unsyncedWorkStatement(
  UnsyncedWorkAssessment assessment,
) => switch (assessment) {
  NoLocalDataFound() => 'There is no local data on this device to set aside.',
  UnsyncedWorkUnknown() =>
    'The local data cannot be read, so it is not possible to check whether it '
        'holds entries that never reached the server. Anything recorded on this '
        'device and not yet sent may be lost.',
  UnsyncedWorkCounted(
    :final queued,
    :final needsAttention,
    :final billsNotUploaded,
  ) =>
    _counted(queued, needsAttention, billsNotUploaded),
};

String _counted(int queued, int needsAttention, int? bills) {
  String plural(int n, String one, String many) => n == 1 ? one : many;
  final parts = <String>[];
  if (queued > 0) {
    parts.add(
      '$queued ${plural(queued, 'entry', 'entries')} recorded on this device '
      "${plural(queued, 'has', 'have')} not reached the server",
    );
  }
  if (needsAttention > 0) {
    parts.add(
      '$needsAttention ${plural(needsAttention, 'entry needs', 'entries need')} '
      'attention after the server did not accept '
      "${plural(needsAttention, 'it', 'them')}",
    );
  }
  if (bills != null && bills > 0) {
    parts.add(
      '$bills attached ${plural(bills, 'bill has', 'bills have')} not been uploaded',
    );
  }
  final billsUnknown = bills == null
      ? ' Whether any attached bills were still waiting to upload could not be checked.'
      : '';
  if (parts.isEmpty) {
    return 'No entries waiting to be sent were found in the local data.$billsUnknown';
  }
  return '${parts.join('; ')}. They exist only on this device. If you reset, they will '
      'be set aside and never sent.$billsUnknown';
}

class _Frame extends StatelessWidget {
  const _Frame({required this.icon, required this.children});

  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.paper,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.negative),
                const SizedBox(height: AppSpacing.lg),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
