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
import 'package:krishna_mis/data/attachments/attachment_staging.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/local/authority_store.dart';
import 'package:krishna_mis/data/remote/auth_gateway.dart';
import 'package:krishna_mis/data/remote/authority_gateway.dart';
import 'package:krishna_mis/data/remote/master_gateway.dart';
import 'package:krishna_mis/data/remote/vendor_tax_period_gateways.dart';
import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/sync/expense_mutation_endpoint.dart';
import 'package:krishna_mis/data/sync/master_mutation_endpoint.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/data/sync/expense_pull.dart';
import 'package:krishna_mis/data/sync/reference_sync.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/app/session/session_controller.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Start-up refused because the compiled-in configuration is unsafe or incomplete.
///
/// Separate from every other start-up failure so the user is told the real cause: a
/// rejected key is a build/configuration mistake, not a damaged database.
class ConfigurationRefused implements Exception {
  const ConfigurationRefused(this.problem);

  final ConfigurationProblem problem;

  @override
  String toString() => problem.toString();
}

/// What a successful start-up produced.
class BootstrapResult {
  const BootstrapResult({
    required this.config,
    required this.shellKind,
    required this.database,
    required this.outbox,
    required this.recoveredInFlightEntries,
    required this.session,
    required this.mutationEndpoint,
    required this.mutationReconciler,
    required this.expensePull,
  });

  final AppConfig config;
  final AppShellKind shellKind;
  final AppDatabase database;
  final OutboxRepository outbox;

  /// How many queued mutations were reclaimed from a previous crash. Reported rather
  /// than hidden — it is a useful signal in sync health.
  final int recoveredInFlightEntries;

  /// Everything the session state machine needs. Null only when no backend is
  /// configured, in which case the application cannot authenticate at all — and says so
  /// rather than inventing a user.
  final SessionDependencies? session;

  /// How queued work reaches the server. Null when no backend is configured, in which
  /// case there is nothing to reach and the queue simply waits.
  final RemoteMutationEndpoint? mutationEndpoint;

  /// Writes an accepted server answer back into the local read model. Null when there is
  /// no backend, in which case nothing is ever accepted.
  final MutationReconciler? mutationReconciler;

  /// Re-reads one expense through the projection the server is willing to show. Used by
  /// the conflict flow, where the point is to see what the record says *now*.
  final ExpensePull? expensePull;
}

/// Starts the application.
///
/// [transport] exists for **acceptance only**, and is deliberately a parameter rather
/// than a switch. There is no environment variable, no global registry, no debug menu and
/// no compiled-in flag that can turn it on: the only way to supply one is to call
/// `bootstrap` with an argument, and the only caller that does is
/// `integration_test/device_acceptance_test.dart`. `main()` calls `bootstrap()` with no
/// arguments, so a shipped binary has no reachable path to it — which is what makes this
/// an injection point and not a backdoor. `test/app/no_hardcoded_authority_test.dart`
/// asserts that nothing in `lib/` ever passes one.
///
/// It exists because the Windows offline behaviour cannot otherwise be proven on the real
/// executable: removing the build machine's network would break the tooling driving the
/// run, and a firewall rule is a machine security setting this project will not change
/// unattended. Injecting the transport exercises the genuine path instead — real request
/// construction, a real `SocketException`, the real classification in `SupabaseGateway`
/// and the real session and sync decisions that follow from it.
Future<BootstrapResult> bootstrap({http.Client? transport}) async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();
  final problem = config.problem;
  if (problem != null) {
    // A privileged credential in a client binary is a security incident, not a warning,
    // and a half-configured backend is a confusing failure deferred to later. Both stop
    // start-up here, loudly, naming the fix and never echoing the value.
    throw ConfigurationRefused(problem);
  }

  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

  final database = await openEncryptedDatabase();

  // The shipped seed exists so the application is usable with no backend at all — the
  // state Phase 1 shipped in. **It must not run once a backend is configured.** The seed
  // contains both properties, and writing it locally would hand every installation a
  // browsable Hotel Krishna Imperial hierarchy before anybody had signed in, and leave it
  // there for a Crystal Canopy-scoped Manager who signs in afterwards. Caught on a real
  // device: the Manager's own pull was correctly scoped, and the seed was sitting
  // underneath it.
  //
  // With a backend, the server is the source of master data and RLS decides what this
  // user may cache. With no backend, nothing can authenticate anyway, so seeded masters
  // are development scaffolding rather than somebody else's property (D-027).
  if (!config.hasBackend) {
    await seedMasterData(database, now: DateTime.now().toUtc());
  }

  final outbox = OutboxRepository(database);
  final recovered = await outbox.recoverStaleInFlight(now: DateTime.now());

  // The backend is initialised only when it is actually configured. Session tokens go to
  // the platform-secure store rather than shared preferences: a refresh token is a bearer
  // credential for company financial data (D-022).
  SessionDependencies? session;
  RemoteMutationEndpoint? mutationEndpoint;
  MutationReconciler? mutationReconciler;
  ExpensePull? expensePull;
  if (config.hasBackend) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabaseAnonKey,
      httpClient: transport,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(),
        authFlowType: AuthFlowType.pkce,
      ),
    );
    final client = Supabase.instance.client;
    final authorityGateway = AuthorityGateway(client);
    final masterGateway = MasterGateway(client);
    final expenseGateway = ExpenseGateway(client);
    mutationEndpoint = RoutingMutationEndpoint(
      masters: MasterMutationEndpoint(
        masters: masterGateway,
        vendors: VendorGateway(client),
      ),
      expenses: ExpenseMutationEndpoint(expenseGateway),
    );
    mutationReconciler = ExpenseReconciler(
      ExpenseRepository(database),
      expenseGateway,
    );
    expensePull = ExpensePull(db: database, gateway: expenseGateway);
    // One purge, shared by the session lifecycle and by reference sync, so a revocation
    // and a sign-out remove the same things by the same code. It can reclaim staged
    // attachment bytes: since D-068 a revoked document's original bill goes with it, and
    // deleting the row while leaving the JPEG in app-private storage would retain
    // precisely the thing D-063 says a scoped user may not have.
    final purge = ScopeCachePurge(
      database,
      reclaimStaging: (expenseId) => AttachmentStagingService(
        resolveStagingDirectory: resolveAttachmentStagingDirectory,
      ).discardExpense(expenseId),
    );
    session = SessionDependencies(
      auth: AuthGateway(client),
      authority: authorityGateway,
      store: AuthorityStore(database),
      purge: purge,
      referenceSync: ReferenceSync(
        db: database,
        authorityGateway: authorityGateway,
        masterGateway: masterGateway,
        purge: purge,
      ),
    );
  }

  return BootstrapResult(
    config: config,
    shellKind: resolveShellKind(),
    database: database,
    outbox: outbox,
    mutationEndpoint: mutationEndpoint,
    mutationReconciler: mutationReconciler,
    expensePull: expensePull,
    recoveredInFlightEntries: recovered,
    session: session,
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
