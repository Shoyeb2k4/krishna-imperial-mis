/// Counts how much history a master carries **on this device**.
///
/// Every figure this class produces is a **lower bound** and is labelled
/// [UsageSource.localCache] accordingly. The local database is a cache — current and
/// previous financial year by default, and only what has synced — so a master with no
/// local usage may still carry years of transactions on the server.
///
/// Nothing here decides archive eligibility. That is the server's answer (owner
/// requirement §6, D-037); this exists so the interface can say something useful while
/// offline, honestly qualified.
library;

import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/masters/master_usage.dart';

class LocalMasterUsageReader implements MasterUsageReader {
  LocalMasterUsageReader(this._db);

  final AppDatabase _db;

  @override
  Future<MasterUsage> usageForMaster(String masterId) =>
      _countReferences(masterId: masterId);

  @override
  Future<MasterUsage> usageForVendor(String vendorId) =>
      _countReferences(vendorId: vendorId);

  /// Counts local transactional references.
  ///
  /// The transactional tables arrive in Phase 3. Until then there are genuinely no
  /// transactions on any device, so the honest local answer is zero — rendered by the UI
  /// as *"None on this device — the server has not been checked"*, never as "unused".
  /// When `expense_allocations` and `revenue_entries` land, the counting SQL goes here
  /// and every caller keeps working unchanged.
  Future<MasterUsage> _countReferences({
    String? masterId,
    String? vendorId,
  }) async {
    if (!await _transactionalTablesExist()) {
      return const MasterUsage.local(transactionCount: 0);
    }

    // Phase 3: replace with a UNION over expense_allocations (business_unit_id,
    // department_id, section_id, category_id) and revenue_entries
    // (business_unit_id, revenue_category_id), or expenses.vendor_id for a vendor.
    return const MasterUsage.local(transactionCount: 0);
  }

  Future<bool> _transactionalTablesExist() async {
    final row = await _db
        .customSelect(
          "SELECT COUNT(*) AS c FROM sqlite_master "
          "WHERE type = 'table' AND name IN ('expense_allocations', 'revenue_entries')",
        )
        .getSingle();
    return row.read<int>('c') > 0;
  }
}

/// A usage reader that answers from the server.
///
/// Deliberately a separate implementation rather than a flag on the local one, so a
/// caller can never accidentally treat a cached figure as authoritative: the type it
/// receives already says which it is. Wired up when the backend lands.
class UnavailableServerUsageReader implements MasterUsageReader {
  const UnavailableServerUsageReader({
    this.reason = 'no backend is configured yet',
  });

  final String reason;

  @override
  Future<MasterUsage> usageForMaster(String masterId) async =>
      MasterUsage.unknown(reason: reason);

  @override
  Future<MasterUsage> usageForVendor(String vendorId) async =>
      MasterUsage.unknown(reason: reason);
}

/// Prefers the authoritative answer and falls back to the local one, **keeping the label
/// intact** either way.
///
/// This is what the UI binds to. It never upgrades a cached count to authoritative, and
/// the screen renders the difference rather than hiding it.
class LayeredMasterUsageReader implements MasterUsageReader {
  const LayeredMasterUsageReader({required this.server, required this.local});

  final MasterUsageReader server;
  final MasterUsageReader local;

  @override
  Future<MasterUsage> usageForMaster(String masterId) => _preferServer(
    () => server.usageForMaster(masterId),
    () => local.usageForMaster(masterId),
  );

  @override
  Future<MasterUsage> usageForVendor(String vendorId) => _preferServer(
    () => server.usageForVendor(vendorId),
    () => local.usageForVendor(vendorId),
  );

  Future<MasterUsage> _preferServer(
    Future<MasterUsage> Function() fromServer,
    Future<MasterUsage> Function() fromLocal,
  ) async {
    try {
      final authoritative = await fromServer();
      if (authoritative.isAuthoritative) return authoritative;
    } on Object {
      // Offline or the backend refused. Fall through to the cached figure, which the
      // caller can still show — labelled as what it is.
    }
    return fromLocal();
  }
}
