/// Application start-up.
///
/// Order matters and is deliberate:
///  1. timezone database — business-date derivation depends on it (D-019)
///  2. encrypted local database — the app's read model and write buffer
///  3. outbox crash recovery — reclaim anything stranded in flight (D-004)
///
/// Nothing here touches the network. The app must start, and be fully usable for entry
/// and local reporting, with no connectivity at all.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:krishna_mis/app/env/app_environment.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// What a successful start-up produced.
class BootstrapResult {
  const BootstrapResult({
    required this.config,
    required this.shellKind,
    required this.database,
    required this.outbox,
    required this.recoveredInFlightEntries,
  });

  final AppConfig config;
  final AppShellKind shellKind;
  final AppDatabase database;
  final OutboxRepository outbox;

  /// How many queued mutations were reclaimed from a previous crash. Reported rather
  /// than hidden — it is a useful signal in sync health.
  final int recoveredInFlightEntries;
}

Future<BootstrapResult> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  if (config.looksLikeServiceRoleKey) {
    // A service-role key in a client binary is a security incident, not a warning.
    // Failing loudly at start-up is the only responsible behaviour.
    throw StateError(
      'Refusing to start: the configured key looks like a service-role key. '
      'Only the publishable/anon key may ship in a client binary.',
    );
  }

  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

  final database = await openEncryptedDatabase();
  final outbox = OutboxRepository(database);
  final recovered = await outbox.recoverStaleInFlight(now: DateTime.now());

  return BootstrapResult(
    config: config,
    shellKind: resolveShellKind(),
    database: database,
    outbox: outbox,
    recoveredInFlightEntries: recovered,
  );
}

/// Windows gets the workstation shell; Android gets the phone shell.
AppShellKind resolveShellKind() {
  if (kIsWeb) {
    // No web target is built for this product (master spec §2). If one ever appears,
    // it is a mistake to be caught here rather than a layout to be guessed at.
    throw UnsupportedError('Krishna Imperial MIS does not target the web.');
  }
  return Platform.isWindows ? AppShellKind.desktop : AppShellKind.mobile;
}
