/// Krishna Imperial MIS — application entry point.
///
/// Targets Android and Windows only (master spec §2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/app.dart';
import 'package:krishna_mis/app/bootstrap.dart';
import 'package:krishna_mis/app/startup/startup_failure_app.dart';
import 'package:krishna_mis/app/startup/startup_runner.dart';
import 'package:krishna_mis/app/env/app_environment.dart';
import 'package:krishna_mis/data/local/local_storage_location.dart';
import 'package:krishna_mis/data/local/local_store_recovery.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/session/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StartupRunner(
    // No arguments: nothing reserved for test runs is reachable from here (D-058).
    boot: () => bootstrap(),
    run: runApp,
    appFor: (boot) => ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(boot.database),
        outboxProvider.overrideWithValue(boot.outbox),
        mutationEndpointProvider.overrideWithValue(boot.mutationEndpoint),
        mutationReconcilerProvider.overrideWithValue(boot.mutationReconciler),
        expensePullProvider.overrideWithValue(boot.expensePull),
        expenseGatewayProvider.overrideWithValue(boot.expenseGateway),
        revenueGatewayProvider.overrideWithValue(boot.revenueGateway),
        reportingGatewayProvider.overrideWithValue(boot.reportingGateway),
        ownerLedgerGatewayProvider.overrideWithValue(boot.ownerLedgerGateway),
        attachmentUploadWorkerProvider.overrideWithValue(
          boot.attachmentUploads,
        ),
        localStorageLocationProvider.overrideWithValue(boot.storage),
        if (boot.session case final session?)
          sessionProvider.overrideWith(() => SessionController(session)),
      ],
      child: KrishnaMisApp(shellKind: boot.shellKind),
    ),
    // The same installation `bootstrap()` opened: its folder and its key, resolved from the
    // build exactly as bootstrap resolves them (D-249, D-346). A production build recovers
    // production's data and nothing else.
    recoveryFor: (failure) async {
      final storage = await resolveLocalStorage(
        production: AppConfig.fromEnvironment().isProduction,
      );
      return LocalStoreRecoveryActions(
        LocalStoreRecovery(
          directory: await storage.root(),
          keyManager: storage.keyManager(),
        ),
        reason: failure.kind,
      );
    },
  ).start();
}
