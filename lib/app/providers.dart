/// Application-wide providers.
///
/// Everything the feature layer needs is reached from here, so no screen constructs a
/// repository or reaches for a singleton. The database and outbox are overridden in
/// `main()` with the instances bootstrap produced.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/local_master_usage_reader.dart';
import 'package:krishna_mis/data/attachments/attachment_source.dart';
import 'package:krishna_mis/data/attachments/platform_attachment_source.dart';
import 'package:krishna_mis/data/attachments/attachment_staging.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/repositories/master_repository.dart';
import 'package:krishna_mis/data/repositories/tax_repository.dart';
import 'package:krishna_mis/data/repositories/vendor_repository.dart';
import 'package:krishna_mis/data/attachments/attachment_upload_worker.dart';
import 'package:krishna_mis/data/sync/expense_pull.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/data/sync/sync_engine.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/auth/authorizer.dart';
import 'package:krishna_mis/app/session/session_controller.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_preview.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/sync/owner_settlement_refresh.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/masters/master_usage.dart';
import 'package:krishna_mis/domain/period/period_state.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';

/// Overridden in `main()`; throwing here means a screen was built outside the app.
final databaseProvider = Provider<AppDatabase>(
  (ref) =>
      throw UnimplementedError('databaseProvider must be overridden in main()'),
);

final outboxProvider = Provider<OutboxRepository>(
  (ref) =>
      throw UnimplementedError('outboxProvider must be overridden in main()'),
);

/// How queued work reaches the server. Null when no backend is configured.
final mutationEndpointProvider = Provider<RemoteMutationEndpoint?>(
  (ref) => null,
);

/// How an accepted answer gets written back into the local read model.
final mutationReconcilerProvider = Provider<MutationReconciler?>((ref) => null);

/// Re-reading one expense from the server, as the server is willing to show it.
///
/// Null when no backend is configured, like every other remote capability here — an
/// offline-only build has nothing to re-read from, and the screens that use this treat
/// its absence as "cannot refresh right now" rather than as an error.
final expensePullProvider = Provider<ExpensePull?>((ref) => null);

/// Re-reading one sale from the server, through the authorised projection.
///
/// Null when no backend is configured. The conflict path treats its absence as "cannot
/// check right now" and says so, rather than as an error or as permission to guess.
///
/// It is overridden in `main()` from the same gateway the sync worker uses, and a test
/// asserts that — because D-077 is what happens when a null default is left standing and
/// every test supplies its own replacement.
final revenueGatewayProvider = Provider<RevenueGateway?>((ref) => null);

/// Uploads attached bills, independently of the expenses they belong to (D-073).
final attachmentUploadWorkerProvider = Provider<AttachmentUploadWorker?>(
  (ref) => null,
);

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => ExpenseRepository(ref.watch(databaseProvider)),
);

/// Copies a chosen bill into app-private storage and hashes it. Local work only — an
/// expense never waits for an attachment, and an attachment never waits for a network.
final attachmentStagingProvider = Provider<AttachmentStagingService>(
  (ref) => AttachmentStagingService(
    resolveStagingDirectory: resolveAttachmentStagingDirectory,
  ),
);

/// The platform's way of producing a file.
///
/// This **resolves the real adapter itself** rather than defaulting to "unavailable" and
/// relying on a bootstrap to replace it. The previous arrangement did the latter, the
/// replacement was never written, and the application shipped through a full acceptance
/// phase telling users that attaching a bill was not available on their device — while
/// every attachment test passed, because each one overrode this provider with a synthetic
/// source (D-077).
///
/// A default that is *wrong but harmless-looking* is worse than no default. Tests still
/// override this provider at the same boundary; nothing in production has to remember to.
final attachmentSourceProvider = Provider<AttachmentSource>(
  (ref) => attachmentSourceFor(Platform.operatingSystem),
);

/// The push worker, bound to whoever is signed in.
///
/// It is rebuilt whenever the session changes, and it carries that user's id, so a
/// second person signing in on the same installation gets an engine that can see only
/// their own queued work (D-050). Null when there is no session or no backend: there is
/// then nothing to push and nobody to attribute it to.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final session = ref.watch(sessionProvider);
  final endpoint = ref.watch(mutationEndpointProvider);
  final actor = session is SessionReady ? session.authority.userId : null;
  if (endpoint == null || actor == null) return null;
  return SyncEngine(
    outbox: ref.watch(outboxProvider),
    endpoint: endpoint,
    actorUserId: actor,
    reconciler: ref.watch(mutationReconcilerProvider),
  );
});

// ── Repositories ────────────────────────────────────────────────────────────

final masterRepositoryProvider = Provider<MasterRepository>(
  (ref) => MasterRepository(ref.watch(databaseProvider)),
);

final vendorRepositoryProvider = Provider<VendorRepository>(
  (ref) => VendorRepository(ref.watch(databaseProvider)),
);

final taxRepositoryProvider = Provider<TaxRepository>(
  (ref) => TaxRepository(ref.watch(databaseProvider)),
);

/// Usage figures, layered so the authoritative answer wins when one exists and the
/// cached answer is still *labelled as cached* when it does not (D-037, owner §6).
final masterUsageReaderProvider = Provider<MasterUsageReader>(
  (ref) => LayeredMasterUsageReader(
    server: const UnavailableServerUsageReader(),
    local: LocalMasterUsageReader(ref.watch(databaseProvider)),
  ),
);

// ── Authorisation ───────────────────────────────────────────────────────────

/// The signed-in user's authority, derived entirely from the server.
///
/// **There is no development fallback here, and there must never be one again.** The
/// Phase 1 placeholder returned an Owner holding every capability, which was correct
/// while no backend existed and is a security defect the moment one does. Every path
/// that cannot establish authority now yields [Principal.anonymous], which holds nothing:
///
///   * not signed in            → anonymous
///   * signing in               → anonymous
///   * authority never verified → anonymous  (fails closed — §8)
///   * session expired          → anonymous
///
/// Only [SessionReady] produces real grants, and those come from `my_authority()`. Owner
/// is never inferred from an email address, a display name, local configuration or any
/// other client-side signal.
final principalProvider = Provider<Principal>(
  (ref) => ref.watch(sessionProvider).principal,
);

/// The session state machine. Overridden in `main()` with the wired dependencies.
final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  () => throw UnimplementedError(
    'sessionProvider must be overridden in main() with real gateways. Constructing a '
    'session without them would mean inventing authority.',
  ),
);

/// Period locks. Backed by the local `period_locks` table once the close console lands;
/// until then nothing is closed, which is the correct starting state.
final periodRegistryProvider = Provider<PeriodRegistry>(
  (ref) => InMemoryPeriodRegistry.allOpen(),
);

final authorizerProvider = Provider<Authorizer>(
  (ref) => Authorizer(periodRegistry: ref.watch(periodRegistryProvider)),
);

// ── Master data ─────────────────────────────────────────────────────────────

/// The whole master hierarchy as one snapshot.
///
/// It watches the session deliberately. The reference sync runs as part of establishing
/// authority, so the rows this reads only exist *after* a session becomes ready — and
/// they are removed again when a scope is revoked or a user switches (D-048, D-051).
/// Without this dependency the hierarchy is whatever happened to be on disk the first
/// time a screen asked, which showed up as an empty Masters panel immediately after
/// signing in, and as a stale one immediately after a purge.
final masterGraphProvider = FutureProvider<MasterGraph>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(masterRepositoryProvider).loadGraph();
});

/// Vendors and tax rules are read as explicit snapshots and refreshed after a write,
/// rather than as live query streams.
///
/// The repositories still expose `watch()` for whoever needs live updates — sync will —
/// but a screen that changes only when *this* user changes it does not need a permanently
/// open query stream, and each one carries a keep-alive timer that makes the surface
/// impossible to settle deterministically.
final vendorListProvider = FutureProvider.family<List<Vendor>, bool>((
  ref,
  includeArchived,
) {
  ref.watch(sessionProvider);
  return ref
      .watch(vendorRepositoryProvider)
      .list(includeArchived: includeArchived);
});

/// The organisation's payment methods, for the expense form.
final paymentMethodsProvider = FutureProvider<List<PaymentMethodRow>>(
  (ref) => ref
      .watch(databaseProvider)
      .select(ref.watch(databaseProvider).paymentMethods)
      .get(),
);

final taxRulesProvider = FutureProvider<Map<String, TaxRuleSet>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(taxRepositoryProvider).allRules();
});

/// Usage for one master. Kept out of [masterGraphProvider] because it may reach the
/// network, and the hierarchy must render instantly and offline regardless.
final masterUsageProvider = FutureProvider.family<MasterUsage, String>(
  (ref, masterId) =>
      ref.watch(masterUsageReaderProvider).usageForMaster(masterId),
);

final vendorUsageProvider = FutureProvider.family<MasterUsage, String>(
  (ref, vendorId) =>
      ref.watch(masterUsageReaderProvider).usageForVendor(vendorId),
);

// ── Reporting (Phase 5) ─────────────────────────────────────────────────────

/// The canonical reporting cache: server-owned figures, synchronised for reporting.
final reportingCacheProvider = Provider<ReportingCache>(
  (ref) => ReportingCache(ref.watch(databaseProvider)),
);

/// Reads the two contribution projections for the reporting delta.
///
/// Null when no backend is configured, like every other remote capability here.
/// Overridden in `main()` from the same Supabase client the sync worker uses, and a test
/// asserts that — because D-077 is what happens when a null default is left standing and
/// every test supplies its own replacement.
final reportingGatewayProvider = Provider<ReportingGateway?>((ref) => null);

/// Fills the cache. Null offline, and **rebuilt on every session change**, because a
/// synchroniser holding the previous user's id would write this person's figures into
/// that person's cache (D-074).
final reportingSyncProvider = Provider<ReportingSync?>((ref) {
  final gateway = ref.watch(reportingGatewayProvider);
  final session = ref.watch(sessionProvider);
  if (gateway == null || session is! SessionReady) return null;
  return ReportingSync(
    cache: ref.watch(reportingCacheProvider),
    gateway: gateway,
    ownerUserId: session.authority.userId,
    orgId: session.authority.orgId,
  );
});

/// What a reporting screen reads.
///
/// The **cache**, never this device's own ledger. Both engines lack a reporting pull
/// (D-173), so the local projections hold only what this installation recorded — a set
/// that sums exactly and is not the hotel's. `DriftReportingSource` remains the adapter
/// over those projections and is deliberately not wired here.
///
/// A `FutureProvider` because coverage is loaded once per report rather than queried per
/// property per year, and it depends on the session: a user switch must not leave the
/// previous person's markers standing behind this person's figures (D-072a §3, D-074).
final localReportingSourceProvider = FutureProvider<ReportingFactsSource>((
  ref,
) async {
  final session = ref.watch(sessionProvider);
  final cache = ref.watch(reportingCacheProvider);
  final owner = session.principal.userId;
  return CachedReportingSource(
    cache: cache,
    ownerUserId: owner,
    coverage: await MarkerCoverage.load(cache, owner),
  );
});

/// The P&L engine over the canonical cache.
final localReportingEngineProvider = FutureProvider<LocalReportingEngine>(
  (ref) async => LocalReportingEngine(
    await ref.watch(localReportingSourceProvider.future),
  ),
);

// ── Owner settlement (Phase 5 OA-3) ─────────────────────────────────────────

/// The owner-accounts half of the remote boundary. Null with no backend.
///
/// Overridden in `main()` from the same Supabase client every other gateway uses, and a
/// test asserts that — because D-077 is what happens when a null default is left standing
/// and every test supplies its own replacement.
final ownerLedgerGatewayProvider = Provider<OwnerLedgerGateway?>((ref) => null);

/// The owner-keyed canonical cache, **for the signed-in person**.
///
/// Rebuilt on every session change. The repository reads only rows carrying this person's
/// id, so a user switch can never hand the previous person's owners, ownership ratio or
/// start date to the next one (D-074, D-208). Before sign-in it names the anonymous
/// principal, who owns no rows by construction.
final ownerSettlementRepositoryProvider = Provider<OwnerSettlementRepository>(
  (ref) => OwnerSettlementRepository(
    ref.watch(databaseProvider),
    ownerUserId: ref.watch(sessionProvider).principal.userId,
  ),
);

/// Starts the two pulls a settlement preview needs. Null offline, with no session, or for
/// a reader who may not see a settlement at all — there is no reason to fetch the owners'
/// private position for somebody who is not permitted to look at it (OA-3).
final ownerSettlementRefresherProvider = Provider<OwnerSettlementRefresher?>((
  ref,
) {
  final gateway = ref.watch(ownerLedgerGatewayProvider);
  final reportingSync = ref.watch(reportingSyncProvider);
  final session = ref.watch(sessionProvider);
  if (gateway == null || reportingSync == null || session is! SessionReady) {
    return null;
  }
  if (!OwnerSettlementPreviewService.mayReadSettlement(session.principal)) {
    return null;
  }
  return OwnerSettlementRefresher(
    ownerSync: OwnerSettlementSync(
      database: ref.watch(databaseProvider),
      gateway: gateway,
      ownerUserId: session.authority.userId,
    ),
    reportingSync: reportingSync,
    repository: ref.watch(ownerSettlementRepositoryProvider),
  );
});
