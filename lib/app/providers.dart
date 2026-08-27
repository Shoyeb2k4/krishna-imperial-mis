/// Application-wide providers.
///
/// Everything the feature layer needs is reached from here, so no screen constructs a
/// repository or reaches for a singleton. The database and outbox are overridden in
/// `main()` with the instances bootstrap produced.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/local_master_usage_reader.dart';
import 'package:krishna_mis/data/repositories/master_repository.dart';
import 'package:krishna_mis/data/repositories/tax_repository.dart';
import 'package:krishna_mis/data/repositories/vendor_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/auth/authorizer.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
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

/// The signed-in user.
///
/// **Phase 2 placeholder.** No authentication exists yet, so development runs as an
/// Owner holding every capability org-wide. Authentication replaces this override in
/// Phase 2's backend slice; nothing downstream changes, because every screen already
/// asks the [Authorizer] rather than assuming.
final principalProvider = Provider<Principal>(
  (ref) => Principal(
    userId: 'dev-owner',
    grants: [for (final c in RoleTemplates.owner) CapabilityGrant(c)],
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
final masterGraphProvider = FutureProvider<MasterGraph>(
  (ref) => ref.watch(masterRepositoryProvider).loadGraph(),
);

/// Vendors and tax rules are read as explicit snapshots and refreshed after a write,
/// rather than as live query streams.
///
/// The repositories still expose `watch()` for whoever needs live updates — sync will —
/// but a screen that changes only when *this* user changes it does not need a permanently
/// open query stream, and each one carries a keep-alive timer that makes the surface
/// impossible to settle deterministically.
final vendorListProvider = FutureProvider.family<List<Vendor>, bool>(
  (ref, includeArchived) => ref
      .watch(vendorRepositoryProvider)
      .list(includeArchived: includeArchived),
);

final taxRulesProvider = FutureProvider<Map<String, TaxRuleSet>>(
  (ref) => ref.watch(taxRepositoryProvider).allRules(),
);

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
