/// Reads the canonical owner cache, and hands it to the settlement calculator.
///
/// Phase 5 OA-2. The join between the synchronised facts and the pure domain, and
/// deliberately nothing more: it performs **no arithmetic of its own**. Every figure comes
/// from `OwnerSettlement.compute`, and the canonical Operating Profit is supplied by the
/// caller from the existing P&L (§33) rather than derived here.
///
/// ## Why it reads the canonical cache and not `owner_ledger_entries`
///
/// The OA-1 ledger holds this actor's own attempt state — pending, rejected, conflicted,
/// quarantined — and only what this device recorded. The canonical cache holds
/// server-accepted facts from every device, owned by the signed-in person (D-171, D-074).
/// A settlement reads the second and never the first, which is what makes "official" mean
/// something (§17).
library;

import 'package:drift/drift.dart';

import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/owner_accounts/owner.dart';
import 'package:krishna_mis/domain/owner_accounts/owner_ledger.dart';
import 'package:krishna_mis/domain/owner_accounts/settlement/owner_settlement.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// What this device has established about canonical owner history.
class OwnerSettlementCoverageState {
  const OwnerSettlementCoverageState({
    required this.snapshotId,
    required this.serverConfirmedAt,
    required this.movementCount,
  });

  final String snapshotId;
  final DateTime serverConfirmedAt;
  final int movementCount;
}

class OwnerSettlementRepository {
  OwnerSettlementRepository(this._db, {required this.ownerUserId});

  final AppDatabase _db;

  /// The signed-in person whose cache this reads (D-074).
  final String ownerUserId;

  /// The coverage row, or null when this device has never synchronised.
  ///
  /// Null is **not** "there is nothing to settle": it is "this device does not know", and
  /// a settlement refuses on it. The distinction D-106 and D-108 exist for, in a third
  /// domain.
  Future<OwnerSettlementCoverageState?> coverage() async {
    final row = await (_db.select(
      _db.ownerSettlementCoverage,
    )..where((t) => t.ownerUserId.equals(ownerUserId))).getSingleOrNull();
    if (row == null) return null;
    return OwnerSettlementCoverageState(
      snapshotId: row.snapshotId,
      serverConfirmedAt: DateTime.parse(row.serverConfirmedAt),
      movementCount: row.movementCount,
    );
  }

  /// Every canonical movement this person's cache holds, through [through] inclusive.
  ///
  /// Voided rows are returned rather than filtered: `isCanonical` is the one rule and it
  /// lives in the domain, so a query that filtered here would be a second place the rule
  /// could be forgotten (D-168).
  Future<List<OwnerLedgerEntry>> canonicalMovements({
    required BusinessDate through,
  }) async {
    final rows =
        await (_db.select(_db.canonicalOwnerMovements)
              ..where((t) => t.ownerUserId.equals(ownerUserId))
              ..where(
                (t) => t.businessDate.isSmallerOrEqual(Variable(through.iso)),
              ))
            .get();

    return [
      for (final row in rows)
        OwnerLedgerEntry(
          id: row.id,
          orgId: row.orgId,
          businessUnitId: row.businessUnitId,
          businessDate: BusinessDate.tryParse(row.businessDate)!,
          businessDateSource: BusinessDateSource.fromWire(
            row.businessDateSource,
          ),
          movementType: OwnerMovementType.fromWire(row.movementType),
          direction: OwnerLedgerDirection.fromWire(row.direction),
          amount: Money.fromPaise(row.amountMinor),
          ownerId: row.ownerId,
          txnNumber: row.txnNumber,
          financialYear: row.financialYear,
          familyMemberId: row.familyMemberId,
          collectedByFamilyMemberId: row.collectedByFamilyMemberId,
          ncBillReference: row.ncBillReference,
          referenceNumber: row.referenceNumber,
          remarks: row.remarks,
          reason: row.reason,
          createdByUserId: row.createdBy,
          capturedAt: DateTime.parse(row.capturedAt),
          rowVersion: row.rowVersion,
          voidedAt: row.voidedAt == null ? null : DateTime.parse(row.voidedAt!),
          voidReason: row.voidReason,
        ),
    ];
  }

  /// The ownership vector the canonical cache holds.
  Future<OwnershipShareSet> ownershipShares() async {
    final rows = await (_db.select(
      _db.canonicalOwnershipShares,
    )..where((t) => t.ownerUserId.equals(ownerUserId))).get();
    return OwnershipShareSet([
      for (final row in rows)
        OwnershipShare(
          id: row.id,
          ownerId: row.ownerId,
          shareBasisPoints: row.shareBasisPoints,
          effectiveFrom: BusinessDate.tryParse(row.effectiveFrom)!,
          effectiveTo: row.effectiveTo == null
              ? null
              : BusinessDate.tryParse(row.effectiveTo!),
        ),
    ]);
  }

  /// The ids of owners the cache says are active.
  ///
  /// Passed to the V1 resolver so the ruling's word *active* means something: an open
  /// share left behind on an archived owner then fails the count rather than satisfying
  /// it (D-204).
  Future<Set<String>> activeOwnerIds() async {
    final rows =
        await (_db.select(_db.canonicalOwners)
              ..where((t) => t.ownerUserId.equals(ownerUserId))
              ..where((t) => t.active.equals(true)))
            .get();
    return {for (final row in rows) row.id};
  }

  /// Computes one month's settlement from canonical facts.
  ///
  /// [operatingProfit] comes from the existing canonical P&L — two cumulative figures, one
  /// to the day before the period and one to its end. **This repository derives neither**:
  /// `Net Sales − Expenses` lives once, in `domain/finance` (§33, D-020).
  ///
  /// Refuses, rather than computing over what it happens to hold, when this device has
  /// never established coverage (§18).
  Future<OwnerSettlementOutcome> settle({
    required String periodKey,
    required BusinessDate periodStart,
    required BusinessDate periodEnd,
    required BusinessDate inception,
    required CanonicalOperatingProfit operatingProfit,
  }) async {
    final established = await coverage();

    final vector = (await ownershipShares()).resolveV1For(
      periodStart,
      periodEnd,
      activeOwnerIds: await activeOwnerIds(),
    );

    return OwnerSettlement.compute(
      periodKey: periodKey,
      periodStart: periodStart,
      periodEnd: periodEnd,
      inception: inception,
      ownership: vector,
      operatingProfit: operatingProfit,
      canonicalMovements: await canonicalMovements(through: periodEnd),
      ledgerCoverageComplete: established != null,
    );
  }
}
