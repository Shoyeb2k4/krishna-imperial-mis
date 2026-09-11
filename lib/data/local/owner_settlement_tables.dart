/// The canonical owner-account cache: server-owned facts a settlement is computed from.
///
/// Phase 5 OA-2, local schema **v20**. A **different authority class** from
/// `owner_ledger_entries` beside it, and that is the whole reason it is separate storage
/// (D-171, and OA-2 §19's warning against making official settlement ambiguous).
///
/// ## Why these are not rows in `owner_ledger_entries`
///
/// That table holds *this actor's* work, in every state a person's work can be in:
/// pending, in flight, rejected, conflicted, quarantined, or recorded here and never sent.
/// It carries an outbox pointer, a row version and a D-070 revocation stamp, and its
/// lifecycle is keyed to the actor who queued each row.
///
/// A canonical movement is none of those. It is a server-accepted fact that may belong to
/// **another actor entirely**, no local edit may touch it, and it arrives and departs with
/// a synchronisation rather than with somebody's intent. Writing one into the actor-owned
/// table would put another person's movement under this person's retention rules, and
/// would make every settlement query re-derive which rows count — which is exactly the
/// arrangement that produced the E2 defect Slice 1 had to correct (D-168).
///
/// Kept apart, the settlement query has **nothing to filter**: every row here is canonical
/// by construction, because only the synchroniser writes it.
///
/// ## Owned by a user, not merely present on a device
///
/// Every row carries `owner_user_id` — the *signed-in person*, not the business owner the
/// movement belongs to. A back-office workstation is shared (D-054, D-074), so "the
/// canonical owner ledger" is a fact about a person's authority at a moment rather than
/// about the installation. Keying by it makes User B inheriting User A's cache
/// structurally unavailable rather than something a query has to remember.
///
/// ## What is deliberately absent
///
/// **No balance, no position, no entitlement and no settlement statement.** The position
/// is derived from these movements every time it is asked for (OA-D2, D-190), so there is
/// no stored figure a correction or a void could leave wrong. A guard asserts no column
/// here is named for one.
library;

import 'package:drift/drift.dart';

/// One canonical owner movement, as the settlement synchroniser received it.
///
/// `voided_at` is carried rather than filtered on the way in — unlike the reporting cache,
/// which drops voided rows — because a settlement statement legitimately shows that a
/// movement existed and was reversed, and because keeping it makes "this device saw the
/// void" answerable. The arithmetic excludes it: `isCanonical` is the one rule, stated in
/// the domain (D-168, D-179).
@DataClassName('CanonicalOwnerMovementRow')
class CanonicalOwnerMovements extends Table {
  /// The signed-in person this cache belongs to (D-074).
  TextColumn get ownerUserId => text()();

  /// The movement's own id, as the server holds it.
  TextColumn get id => text()();

  TextColumn get orgId => text()();
  TextColumn get businessUnitId => text()();

  /// The business owner the movement debits or credits — the owner the **server**
  /// resolved and snapshotted, never re-derived here from the family link (§40).
  TextColumn get ownerId => text()();

  /// `KI-OWN-…`. Never null in this table: only server-accepted movements are cached, and
  /// the column is kept so a statement can name the movement a figure came from.
  TextColumn get txnNumber => text()();
  TextColumn get financialYear => text().nullable()();

  /// Derived under the property's timezone and cut-off, then persisted (D-019, D-067).
  TextColumn get businessDate => text()();
  TextColumn get businessDateSource => text()();

  /// `YYYY-MM`, tied to [businessDate] by a server CHECK — the same grain every other
  /// reporting period uses (§21).
  TextColumn get pnlPeriodKey => text()();

  TextColumn get movementType => text()();
  TextColumn get direction => text()();

  /// Always positive; the movement type decides the sign (§43 of OA-1).
  IntColumn get amountMinor => integer()();

  TextColumn get familyMemberId => text().nullable()();
  TextColumn get collectedByFamilyMemberId => text().nullable()();
  TextColumn get ncBillReference => text().nullable()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get remarks => text().nullable()();
  TextColumn get reason => text().nullable()();

  TextColumn get createdBy => text()();
  TextColumn get capturedAt => text()();
  IntColumn get rowVersion => integer()();
  IntColumn get changeSeq => integer()();

  TextColumn get voidedAt => text().nullable()();
  TextColumn get voidReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {ownerUserId, id};

  @override
  List<String> get customConstraints => [
    'CHECK (amount_minor > 0)',
    "CHECK (length(trim(txn_number)) > 0)",
  ];
}

/// What this device has established about canonical owner data, and when.
///
/// One row per signed-in person. A settlement **refuses** unless one exists (§18): a
/// device that has never synchronised holds only what it recorded itself, and a settlement
/// over that reconciles against itself perfectly while being wrong by exactly the movements
/// it never saw.
///
/// [snapshotId] and [serverConfirmedAt] come from the **same SQL statement** that returned
/// the facts, so everything this row certifies belongs to one authoritative moment — the
/// property D-188 had to correct for reporting, applied here from the start rather than
/// after the fact.
@DataClassName('OwnerSettlementCoverageRow')
class OwnerSettlementCoverage extends Table {
  TextColumn get ownerUserId => text()();

  /// The server's opaque MVCC snapshot identity. Meaningful under equality: two reads that
  /// saw the same view really do describe one moment.
  TextColumn get snapshotId => text()();

  /// The server's own transaction timestamp, from that same statement. Never a device
  /// clock reading, which is not evidence about a server (spec §9).
  TextColumn get serverConfirmedAt => text()();

  /// How many canonical movements the snapshot carried. Stored so "synchronised and there
  /// are none" stays distinguishable from "never asked" without counting rows — the
  /// distinction D-106 and D-108 exist for.
  IntColumn get movementCount => integer()();

  /// The date from which 50:50 ownership and owner settlement begin, as the **same**
  /// snapshot stated it (OA-3 Q1). `YYYY-MM-DD`, always the first of a month.
  ///
  /// **Null means not configured**, and a settlement refuses on it — never "the start of
  /// the financial year", never the tax configuration's date, never the earliest share.
  /// The production date is outstanding and a device does not get to guess it (D-043).
  ///
  /// It lives on the coverage row rather than in a table of its own because it came from
  /// the statement that certified the rest: one snapshot, one row (D-188).
  TextColumn get ownershipStartDate => text().nullable()();

  /// Device clock, diagnostics only. Decides nothing.
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {ownerUserId};
}

/// The ownership vector, as the settlement synchroniser received it.
///
/// ## Why this is not the OA-1 `ownership_shares` table
///
/// That table is classified `organizationGlobal`, which means it **survives a user
/// switch** — the treatment business units, departments and vendors get, and the right
/// treatment for data that is not sensitive. A profit-sharing ratio is not that.
///
/// OA-1 could classify it that way safely because **nothing ever wrote it**: it shipped
/// empty and stayed empty, which the OA-2 completeness audit is what established. The
/// moment a synchroniser fills it, a shared back-office workstation where the Owner
/// synchronised first would leave the ownership ratio readable by the Manager who signs in
/// next — and OA-1 section 31 is explicit that operational recording authority must not
/// carry profit-share visibility.
///
/// So the settlement reads an **owner-keyed** copy instead, purged on a confirmed
/// revocation and isolated per signed-in person exactly as the movements are (D-074).
@DataClassName('CanonicalOwnershipShareRow')
class CanonicalOwnershipShares extends Table {
  /// The signed-in person this cache belongs to (D-074).
  TextColumn get ownerUserId => text()();

  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// The business owner the share belongs to.
  TextColumn get ownerId => text()();

  /// 1..10000. Not narrowed to the V1 5000 here: the ruling is a business rule enforced
  /// at the boundary and in the domain, and encoding it in a cache would make an
  /// authorised future ratio unable to synchronise at all (D-204).
  IntColumn get shareBasisPoints => integer()();

  TextColumn get effectiveFrom => text()();
  TextColumn get effectiveTo => text().nullable()();
  TextColumn get note => text().nullable()();

  IntColumn get rowVersion => integer()();
  IntColumn get changeSeq => integer()();

  @override
  Set<Column> get primaryKey => {ownerUserId, id};

  @override
  List<String> get customConstraints => [
    'CHECK (share_basis_points BETWEEN 1 AND 10000)',
  ];
}

/// The owner masters, owner-keyed for the same reason the shares are.
///
/// Carried so the V1 rule's word **active** means something: `resolveV1For` can be told
/// which owners are active, and an open share left behind on an archived owner then fails
/// the count instead of satisfying it (D-204).
@DataClassName('CanonicalOwnerRow')
class CanonicalOwners extends Table {
  TextColumn get ownerUserId => text()();

  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get code => text()();
  TextColumn get displayName => text()();
  BoolColumn get active => boolean()();
  TextColumn get archivedAt => text().nullable()();

  IntColumn get rowVersion => integer()();
  IntColumn get changeSeq => integer()();

  @override
  Set<Column> get primaryKey => {ownerUserId, id};
}
