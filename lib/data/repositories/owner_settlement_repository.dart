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
import 'package:krishna_mis/domain/auth/capability.dart';
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
    this.ownershipStartDate,
  });

  final String snapshotId;
  final DateTime serverConfirmedAt;
  final int movementCount;

  /// The date 50:50 ownership and settlement begin, as that same snapshot stated it
  /// (OA-3 Q1). **Null is "not configured"**, and a settlement refuses on it.
  final BusinessDate? ownershipStartDate;
}

class OwnerSettlementRepository {
  OwnerSettlementRepository(this._db, {required this.principal});

  final AppDatabase _db;
  final Principal principal;

  /// The signed-in person whose cache this reads (D-074).
  String get ownerUserId => principal.userId;

  bool get _mayRead =>
      principal.canAnywhere(Capability.ownerSettlementView) &&
      principal.canAnywhere(Capability.ownerLedgerView) &&
      principal.canAnywhere(Capability.reportsView);

  /// The coverage row, or null when this device has never synchronised.
  ///
  /// Null is **not** "there is nothing to settle": it is "this device does not know", and
  /// a settlement refuses on it. The distinction D-106 and D-108 exist for, in a third
  /// domain.
  Future<OwnerSettlementCoverageState?> coverage() async {
    if (!_mayRead) return null;
    final row = await (_db.select(
      _db.ownerSettlementCoverage,
    )..where((t) => t.ownerUserId.equals(ownerUserId))).getSingleOrNull();
    if (row == null) return null;
    return OwnerSettlementCoverageState(
      snapshotId: row.snapshotId,
      serverConfirmedAt: DateTime.parse(row.serverConfirmedAt),
      movementCount: row.movementCount,
      ownershipStartDate: row.ownershipStartDate == null
          ? null
          : BusinessDate.tryParse(row.ownershipStartDate!),
    );
  }

  /// The display names of the owners the canonical cache holds, by owner id.
  ///
  /// From the **owner-keyed** copy and nowhere else (D-208): the OA-1 `owners` table
  /// survives a user switch, and a settlement surface must never name an owner out of it.
  Future<Map<String, String>> ownerNames() async {
    if (!_mayRead) return const {};
    final rows = await (_db.select(
      _db.canonicalOwners,
    )..where((t) => t.ownerUserId.equals(ownerUserId))).get();
    return {for (final row in rows) row.id: row.displayName};
  }

  /// Every canonical movement this person's cache holds, through [through] inclusive.
  ///
  /// Voided rows are returned rather than filtered: `isCanonical` is the one rule and it
  /// lives in the domain, so a query that filtered here would be a second place the rule
  /// could be forgotten (D-168).
  Future<List<OwnerLedgerEntry>> canonicalMovements({
    required BusinessDate through,
  }) async {
    if (!_mayRead) return const [];
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
    if (!_mayRead) return OwnershipShareSet(const []);
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
    if (!_mayRead) return const {};
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
