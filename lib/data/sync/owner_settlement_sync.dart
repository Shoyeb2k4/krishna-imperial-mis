/// Canonical owner data synchronisation, for settlement.
///
/// Phase 5 OA-2 §19. The OA-2 completeness audit proved that a device held only the owner
/// movements it had recorded itself, and none of the ownership masters at all — so a
/// settlement computed there would reconcile against itself perfectly and be wrong by
/// exactly the facts it never saw. This is what closes that.
///
/// ## Why a full replace rather than a delta
///
/// The owner ledger is **small**: a handful of movements a month, a few hundred a year.
/// Against that, a delta buys nothing and costs the entire apparatus the reporting
/// synchroniser needs — a watermark, a safety overlap, document-grain replacement, and the
/// lowest-watermark rule that took two attempts to control (D-178, D-180).
///
/// A full read makes a correction and a void propagate **by themselves**: the row comes
/// back changed, or it comes back carrying `voided_at`, or it is simply not in the answer
/// and the replace removes it. There is no case where a stale row can survive, because
/// nothing is preserved across a run.
///
/// OA-2 §19 asks for the *simplest correct* option and says not to copy the reporting
/// cache mechanically. This is that: option A, the full canonical ledger pull.
///
/// ## Why the movements are not written into `owner_ledger_entries`
///
/// Different authority class. That table is this actor's own attempt state, with an outbox
/// pointer and a D-070 retention stamp; these are server-owned facts that may belong to
/// another actor entirely (D-171). Mixing them is what §19 warns makes official settlement
/// ambiguous.
///
/// ## The commit order is part of the rule
///
/// One transaction, evidence **last**:
///
/// ```
///         receive the whole snapshot
///           -> begin
///               -> replace this owner's canonical movements
///               -> replace this owner's ownership shares and owner masters
///               -> write the coverage row            <- LAST
///           -> commit
/// ```
///
/// A run that fails anywhere leaves no coverage row and no half-replaced history, so
/// *complete or nothing* is true by construction rather than by intention — the discipline
/// D-108 established for the configuration marker and D-188 restated for reporting.
library;

import 'package:drift/drift.dart';

import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/cache_authority_generation.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// What a synchronisation run established, or why it established nothing.
sealed class OwnerSettlementSyncResult {
  const OwnerSettlementSyncResult();
}

/// The device now holds complete canonical owner history as at one server snapshot.
final class OwnerSettlementSynchronised extends OwnerSettlementSyncResult {
  const OwnerSettlementSynchronised({
    required this.movements,
    required this.owners,
    required this.shares,
    required this.snapshotId,
    required this.serverConfirmedAt,
  });

  final int movements;
  final int owners;
  final int shares;
  final String snapshotId;
  final DateTime serverConfirmedAt;

  @override
  String toString() =>
      'OwnerSettlementSynchronised($movements movements, $owners owners, '
      '$shares shares, as at $serverConfirmedAt)';
}

/// Nothing was established, and **nothing was withdrawn**.
///
/// A failed run leaves the previously committed coverage exactly as it was: an answer that
/// did not arrive is not an answer that said no, which is D-048's rule applied to a third
/// kind of cache. A device that synchronised yesterday can still settle yesterday's data
/// offline today.
final class OwnerSettlementSyncUnavailable extends OwnerSettlementSyncResult {
  const OwnerSettlementSyncUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'OwnerSettlementSyncUnavailable($reason)';
}

/// The server answered, and said this person may not read a settlement (OA-3).
///
/// **An answer that arrived, not one that did not.** Since OA-3 the transport states the
/// caller's settlement authority in the same statement as the facts, and withholds every
/// dataset — as null, never as an empty list — from anybody without it. So this is
/// confirmed authority loss, and it withdraws this person's canonical owner cache, the
/// coverage row first: a device must not go on settling from history its reader has just
/// been told they may not read (D-070).
///
/// Distinct from [OwnerSettlementSyncUnavailable], which withdraws nothing, because the two
/// are different facts about the world and treating one as the other is either a leak or a
/// wiped cache over a flaky network (D-048 section 1).
final class OwnerSettlementSyncNotAuthorised extends OwnerSettlementSyncResult {
  const OwnerSettlementSyncNotAuthorised();

  @override
  String toString() => 'OwnerSettlementSyncNotAuthorised()';
}

/// The refusal a settlement gets when the snapshot itself is malformed.
///
/// Fail closed rather than repair: replacing working coverage with unusable coverage is
/// strictly worse than keeping yesterday's, because the device would then refuse every
/// settlement *while claiming to be synchronised* (D-108 §19.5's rule, in a second domain).
/// The session or authority this run was started under ended before its answer could be
/// applied (D-231). Nothing was written.
final class OwnerSettlementSyncAbandoned extends OwnerSettlementSyncResult {
  const OwnerSettlementSyncAbandoned();

  @override
  String toString() => 'OwnerSettlementSyncAbandoned()';
}

final class OwnerSettlementSyncRefused extends OwnerSettlementSyncResult {
  const OwnerSettlementSyncRefused(this.reason);
  final String reason;

  @override
  String toString() => 'OwnerSettlementSyncRefused($reason)';
}

/// Pulls canonical owner data and replaces this person's cache with it.
class OwnerSettlementSync {
  OwnerSettlementSync({
    required AppDatabase database,
    required this.gateway,
    required this.ownerUserId,
  }) : _db = database;

  final AppDatabase _db;
  final OwnerSnapshotSource gateway;

  /// The **signed-in person**, not a business owner. Every row written carries it, so a
  /// second person on the same installation can never read this one's cache (D-074).
  final String ownerUserId;

  Future<OwnerSettlementSyncResult> synchronise() async {
    // D-231: the generation this run belongs to, re-checked inside the writing transaction.
    final startedUnder = await CacheAuthorityGeneration(_db).read();
    final outcome = await gateway.fetchSettlementSnapshot();

    switch (outcome) {
      case RemoteUnreachable():
        return const OwnerSettlementSyncUnavailable(
          'the server could not be reached',
        );
      case RemoteRefused(refusal: final refusal):
        return OwnerSettlementSyncUnavailable(refusal.message);
      case RemoteOk(value: final snapshot):
        try {
          return await _apply(snapshot, startedUnder);
        } on StaleCacheGeneration {
          return const OwnerSettlementSyncAbandoned();
        }
    }
  }

  Future<OwnerSettlementSyncResult> _apply(
    Map<String, dynamic> snapshot,
    CacheGeneration? startedUnder,
  ) async {
    final snapshotId = snapshot['snapshot_id'];
    final serverTime = snapshot['server_time'];
    if (snapshotId is! String || snapshotId.isEmpty || serverTime is! String) {
      return const OwnerSettlementSyncRefused(
        'the snapshot carried no server-issued identity or time',
      );
    }
    final confirmedAt = DateTime.tryParse(serverTime);
    if (confirmedAt == null) {
      return const OwnerSettlementSyncRefused(
        'the snapshot carried an unreadable server time',
      );
    }

    // OA-3: the caller's settlement authority is **stated**, never inferred from the shape
    // of the answer. A snapshot that does not say is refused rather than read as "yes" —
    // guessing in the permissive direction is how a device would certify a settlement to
    // somebody the server has closed it to.
    final authorised = snapshot['settlement_authorised'];
    if (authorised is! bool) {
      return const OwnerSettlementSyncRefused(
        'the snapshot did not state whether this reader may see a settlement',
      );
    }
    if (!authorised) {
      await _withdraw();
      return const OwnerSettlementSyncNotAuthorised();
    }

    // The start date: a first-of-month date, or null for "not configured". Anything else
    // is a boundary defect to surface, not a value to repair.
    final startRaw = snapshot['ownership_start_date'];
    String? ownershipStartDate;
    if (startRaw != null) {
      final start = startRaw is String ? BusinessDate.tryParse(startRaw) : null;
      if (start == null || start.day != 1) {
        return const OwnerSettlementSyncRefused(
          'the snapshot carried a settlement start date that is not the first of a month',
        );
      }
      ownershipStartDate = start.iso;
    }

    final movements = _rows(snapshot['movements']);
    final owners = _rows(snapshot['owners']);
    final shares = _rows(snapshot['ownership_shares']);
    if (movements == null || owners == null || shares == null) {
      return const OwnerSettlementSyncRefused(
        'the snapshot was malformed; the previous coverage is retained unchanged',
      );
    }

    // A movement without a transaction number is not canonical and the server should never
    // have sent one. Refuse the whole snapshot rather than filter it: a boundary that
    // started returning attempts is a defect to surface, not to work around.
    for (final row in movements) {
      final txn = row['txn_number'];
      if (txn is! String || txn.isEmpty) {
        return const OwnerSettlementSyncRefused(
          'the snapshot contained a movement the server has not accepted',
        );
      }
    }

    await _db.transaction(() async {
      await CacheAuthorityGeneration(_db).ensureStillCurrent(
        startedUnder: startedUnder,
        ownerUserId: ownerUserId,
      );
      // Replace, wholly. Nothing is preserved across a run, so a corrected movement
      // arrives corrected, a voided one arrives voided, and one that is no longer
      // returned simply ceases to exist here.
      await (_db.delete(
        _db.canonicalOwnerMovements,
      )..where((t) => t.ownerUserId.equals(ownerUserId))).go();
      await (_db.delete(
        _db.canonicalOwnershipShares,
      )..where((t) => t.ownerUserId.equals(ownerUserId))).go();
      await (_db.delete(
        _db.canonicalOwners,
      )..where((t) => t.ownerUserId.equals(ownerUserId))).go();

      for (final row in movements) {
        await _db
            .into(_db.canonicalOwnerMovements)
            .insert(
              CanonicalOwnerMovementsCompanion.insert(
                ownerUserId: ownerUserId,
                id: row['id'] as String,
                orgId: row['org_id'] as String,
                businessUnitId: row['business_unit_id'] as String,
                ownerId: row['owner_id'] as String,
                txnNumber: row['txn_number'] as String,
                financialYear: Value(row['financial_year'] as String?),
                businessDate: row['business_date'] as String,
                businessDateSource: row['business_date_source'] as String,
                pnlPeriodKey: row['pnl_period_key'] as String,
                movementType: row['movement_type'] as String,
                direction: row['direction'] as String,
                amountMinor: (row['amount_minor'] as num).toInt(),
                familyMemberId: Value(row['family_member_id'] as String?),
                collectedByFamilyMemberId: Value(
                  row['collected_by_family_member_id'] as String?,
                ),
                ncBillReference: Value(row['nc_bill_reference'] as String?),
                referenceNumber: Value(row['reference_number'] as String?),
                remarks: Value(row['remarks'] as String?),
                reason: Value(row['reason'] as String?),
                createdBy: row['created_by'] as String,
                capturedAt: row['captured_at'] as String,
                rowVersion: (row['row_version'] as num).toInt(),
                changeSeq: (row['change_seq'] as num).toInt(),
                voidedAt: Value(row['voided_at'] as String?),
                voidReason: Value(row['void_reason'] as String?),
              ),
            );
      }

      for (final row in shares) {
        await _db
            .into(_db.canonicalOwnershipShares)
            .insert(
              CanonicalOwnershipSharesCompanion.insert(
                ownerUserId: ownerUserId,
                id: row['id'] as String,
                orgId: row['org_id'] as String,
                ownerId: row['owner_id'] as String,
                shareBasisPoints: (row['share_basis_points'] as num).toInt(),
                effectiveFrom: row['effective_from'] as String,
                effectiveTo: Value(row['effective_to'] as String?),
                note: Value(row['note'] as String?),
                rowVersion: (row['row_version'] as num).toInt(),
                changeSeq: (row['change_seq'] as num).toInt(),
              ),
            );
      }

      for (final row in owners) {
        await _db
            .into(_db.canonicalOwners)
            .insert(
              CanonicalOwnersCompanion.insert(
                ownerUserId: ownerUserId,
                id: row['id'] as String,
                orgId: row['org_id'] as String,
                code: row['code'] as String,
                displayName: row['display_name'] as String,
                active: row['active'] as bool,
                archivedAt: Value(row['archived_at'] as String?),
                rowVersion: (row['row_version'] as num).toInt(),
                changeSeq: (row['change_seq'] as num).toInt(),
              ),
            );
      }

      // **Last, inside the same transaction.** A run that fails anywhere above rolls the
      // claim back with the data, so the device never says it holds complete history when
      // it holds part of one.
      await _db
          .into(_db.ownerSettlementCoverage)
          .insertOnConflictUpdate(
            OwnerSettlementCoverageCompanion.insert(
              ownerUserId: ownerUserId,
              snapshotId: snapshotId,
              serverConfirmedAt: confirmedAt.toUtc().toIso8601String(),
              movementCount: movements.length,
              ownershipStartDate: Value(ownershipStartDate),
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );
    });

    return OwnerSettlementSynchronised(
      movements: movements.length,
      owners: owners.length,
      shares: shares.length,
      snapshotId: snapshotId,
      serverConfirmedAt: confirmedAt,
    );
  }

  /// Removes this person's canonical owner cache, the coverage row first.
  ///
  /// One transaction, and only **this** person's rows: a second person on the same
  /// installation keeps what their own authority established (D-074). The coverage row
  /// goes before the facts it certifies, because a claim of complete history standing over
  /// rows that are being removed is worse than no claim (D-171).
  Future<void> _withdraw() => _db.transaction(() async {
    await (_db.delete(
      _db.ownerSettlementCoverage,
    )..where((t) => t.ownerUserId.equals(ownerUserId))).go();
    await (_db.delete(
      _db.canonicalOwnerMovements,
    )..where((t) => t.ownerUserId.equals(ownerUserId))).go();
    await (_db.delete(
      _db.canonicalOwnershipShares,
    )..where((t) => t.ownerUserId.equals(ownerUserId))).go();
    await (_db.delete(
      _db.canonicalOwners,
    )..where((t) => t.ownerUserId.equals(ownerUserId))).go();
  });

  static List<Map<String, dynamic>>? _rows(Object? value) {
    if (value is! List) return null;
    final rows = <Map<String, dynamic>>[];
    for (final entry in value) {
      if (entry is! Map) return null;
      rows.add(entry.cast<String, dynamic>());
    }
    return rows;
  }
}
