/// Starting the application, and what happens when it cannot start.
///
/// Kept out of `main()` so it can be tested: a start that fails shows the classified
/// failure screen; "Try again" — and a completed reset — simply start again, so a reset
/// is never reported as a success on its own. Only the start that follows decides what a
/// person sees next (Phase 8 Slice 7, D-329, D-330).
library;

import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:krishna_mis/app/bootstrap.dart';
import 'package:krishna_mis/app/startup/startup_failure.dart';
import 'package:krishna_mis/app/startup/startup_failure_app.dart';

class StartupRunner {
  StartupRunner({
    required this.boot,
    required this.run,
    required this.appFor,
    required this.recoveryFor,
    void Function(Object error, StackTrace stackTrace)? log,
  }) : _log = log ?? _developerLog;

  /// Starts everything: `bootstrap()` in production.
  final Future<BootstrapResult> Function() boot;

  /// Shows a root widget: `runApp` in production.
  final void Function(Widget app) run;

  /// The application for a successful start.
  final Widget Function(BootstrapResult result) appFor;

  /// The recovery actions for this installation. Asked for only when the failure
  /// permits a reset; if it cannot be built, no reset is offered.
  final Future<StartupRecoveryActions> Function(StartupFailure failure)
  recoveryFor;

  final void Function(Object error, StackTrace stackTrace) _log;

  /// Starts the application, or shows why it could not start.
  Future<void> start() async {
    try {
      final result = await boot();
      run(appFor(result));
    } on Object catch (error, stackTrace) {
      // The full technical detail — message, path, stack — goes to the developer log
      // and nowhere a person reads it.
      _log(error, stackTrace);
      final failure = StartupFailure.classify(error);
      StartupRecoveryActions? recovery;
      if (failure.permitsReset) {
        try {
          recovery = await recoveryFor(failure);
        } on Object catch (recoveryError, recoveryStack) {
          _log(recoveryError, recoveryStack);
        }
      }
      run(
        StartupFailureApp(
          // A new identity every time, so a failure after "Try again" or after a reset
          // replaces the whole screen — including a reset page still on top of it —
          // instead of updating a root the person can no longer see.
          key: ObjectKey(Object()),
          failure: failure,
          onTryAgain: start,
          configurationMessage: error is ConfigurationRefused
              ? error.problem.toString()
              : null,
          recovery: recovery,
        ),
      );
    }
  }

  static void _developerLog(Object error, StackTrace stackTrace) =>
      developer.log(
        'Start-up failed',
        name: 'krishna_mis.startup',
        error: error,
        stackTrace: stackTrace,
      );
}
