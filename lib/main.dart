/// Krishna Imperial MIS — application entry point.
///
/// Targets Android and Windows only (master spec §2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/app.dart';
import 'package:krishna_mis/app/bootstrap.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/session/session_controller.dart';

Future<void> main() async {
  try {
    final boot = await bootstrap();
    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          mutationEndpointProvider.overrideWithValue(boot.mutationEndpoint),
          mutationReconcilerProvider.overrideWithValue(boot.mutationReconciler),
          expensePullProvider.overrideWithValue(boot.expensePull),
          if (boot.session case final session?)
            sessionProvider.overrideWith(() => SessionController(session)),
        ],
        child: KrishnaMisApp(shellKind: boot.shellKind),
      ),
    );
  } on Object catch (error) {
    // A start-up failure is usually the encrypted database refusing to open. Showing a
    // blank screen would be the worst possible response, so we say what happened.
    runApp(_StartupFailureApp(error: error));
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Krishna Imperial MIS',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lock_outline, color: AppColors.negative),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    error is ConfigurationRefused
                        ? 'This build is not configured safely'
                        : 'The application could not start',
                    style: AppTypography.heading,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    error is ConfigurationRefused
                        ? 'This build is configured incorrectly and has been stopped '
                              'before it could connect to anything. Nothing has been '
                              'changed or deleted. The message below says what to fix.'
                        : 'The secure local database could not be opened on this '
                              'device. Nothing has been changed or deleted. Please '
                              'report this message exactly as shown.',
                    style: AppTypography.bodyMuted,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SelectableText('$error', style: AppTypography.caption),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
