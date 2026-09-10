/// The local Owner Accounts read model (schema v19, Phase 5 OA-1).
///
/// Three reference masters and one financial document table, built on the shapes the
/// revenue and expense engines already proved rather than a second lifecycle: the same
/// client-generated UUID identity, the same nullable server-issued number, the same
/// `pendingMutationId` link that derives sync state from the outbox instead of copying it,
/// the same `scopeRevokedAt` quarantine stamp, and the same actor ownership that keeps one
/// person's unsent work out of another's ledger (D-050, D-068, D-070, D-074).
///
/// ## What is *not* here, and why that is the design
///
/// **No balance column, anywhere.** An owner's closing balance is derived from the
/// movements and the entitlement, every time it is asked for (OA-D2). Storing one would
/// be a second writable copy of a derivable fact, needing a writer on every mutation path
/// — a correction that moves a period, an edit that changes an amount, a void, a replay —
/// and it would be wrong the first time somebody forgot one. That is D-157's argument for
/// deriving revenue contributions, and it applies here with more force, because a balance
/// depends on the P&L as well as on this table.
///
/// **No reporting cache.** OA-3 owns the canonical Owner Ledger reporting dataset and the
/// coherent third-dataset snapshot. These tables are this device's own transactional read
/// model — the same authority class as `revenue_entries`, and deliberately not the same
/// one as `reporting_*` (D-171).
///
/// ## Amounts are positive, and the database says so
///
/// `amount_minor` carries a `>= 0` check and the direction lives in its own column, so the
/// two possible representations of one withdrawal never both exist (§43). A movement whose
/// type has a fixed direction is held to it by a check constraint rather than by the
/// repository remembering.
library;

import 'package:drift/drift.dart';

/// A business owner: somebody profit is allocated to.
///
/// **Not a user.** There is no `userId` here and no foreign key to any identity table:
/// an owner is a business subject, and whether they hold an MIS login is an unrelated and
/// optional fact (OA-1 §3). Tying the two would mean provisioning a login granted a share
/// of the business.
@DataClassName('OwnerRow')
class Owners extends Table {
  /// Client-generated UUID (D-008).
  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// Immutable once created, like every master's code (D-035).
  TextColumn get code => text()();

  /// Renameable where meaning is preserved (D-038).
  TextColumn get displayName => text().named('display_name')();

  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get archivedAt => dateTime().named('archived_at').nullable()();

  IntColumn get rowVersion =>
      integer().named('row_version').withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {orgId, code},
  ];
}

/// One owner's profit share over one interval.
///
/// A separate table rather than a column on [Owners], because a share is a fact about a
/// **period**. On the owner it would make every historical settlement depend on today's
/// value, so a ratio changed in 2027 would silently restate every 2026 statement — the
/// harm the date-effective tax model exists to prevent (D-017), applied to ownership.
@DataClassName('OwnershipShareRow')
class OwnershipShares extends Table {
  @override
  String get tableName => 'ownership_shares';

  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// Soft pointer, for the reason every cached financial pointer here is soft: a purge
  /// legitimately removes a master while rows naming it remain (D-049, D-068).
  TextColumn get ownerId => text().named('owner_id')();

  /// 1..10000. A valid applicable set totals exactly 10000 (OA-D1).
  IntColumn get shareBasisPoints => integer().named('share_basis_points')();

  /// `YYYY-MM-DD`. Constrained to the first day of a month: an ownership change takes
  /// effect only at a settlement-period boundary (OA-1 §5).
  TextColumn get effectiveFrom => text().named('effective_from')();

  /// Inclusive, and null is open-ended. Constrained to the last day of a month, so one
  /// share ends the day before the next begins with no gap and no overlap.
  TextColumn get effectiveTo => text().named('effective_to').nullable()();

  IntColumn get rowVersion =>
      integer().named('row_version').withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (share_basis_points BETWEEN 1 AND 10000)',
    "CHECK (effective_from LIKE '____-__-01')",
    "CHECK (effective_to IS NULL OR effective_to LIKE '____-__-__')",
  ];
}

/// A person who may consume against an owner's account.
///
/// Includes the owner's own self-record, so an NC surface offers exactly one kind of
/// person-reference and the mapping resolves uniformly whether the diner was the owner or
/// their daughter.
///
/// **Not a user** (§7). No `userId`, no login, no automatic account.
@DataClassName('OwnerFamilyMemberRow')
class OwnerFamilyMembers extends Table {
  @override
  String get tableName => 'owner_family_members';

  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// The owner this person's consumption is attributed to **for this interval**. Soft
  /// pointer.
  TextColumn get ownerId => text().named('owner_id')();

  TextColumn get displayName => text().named('display_name')();

  /// A label. Nothing branches on it, and a guard asserts as much — a relationship that
  /// decided an amount would be business logic nobody configured.
  TextColumn get relationshipLabel =>
      text().named('relationship_label').nullable()();

  BoolColumn get isSelf =>
      boolean().named('is_self').withDefault(const Constant(false))();

  BoolColumn get mayUseNc =>
      boolean().named('may_use_nc').withDefault(const Constant(true))();

  TextColumn get effectiveFrom => text().named('effective_from')();
  TextColumn get effectiveTo => text().named('effective_to').nullable()();

  BoolColumn get active => boolean().withDefault(const Constant(true))();

  IntColumn get rowVersion =>
      integer().named('row_version').withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (effective_from LIKE '____-__-__')",
    "CHECK (effective_to IS NULL OR effective_to LIKE '____-__-__')",
  ];
}

/// One movement on an owner's current account.
///
/// The financial document of this domain, and it follows the revenue document's shape
/// exactly where the shape is about being a financial document rather than about being
/// revenue.
@DataClassName('OwnerLedgerRow')
class OwnerLedgerEntries extends Table {
  @override
  String get tableName => 'owner_ledger_entries';

  /// Client-generated UUID v7 (D-008).
  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// `KI-OWN-26-27-000001`, issued by the server on acceptance.
  ///
  /// **Null until then, and never fabricated locally** — two devices offline for a week
  /// would both invent the same number. Its own sequence, shared with neither the expense
  /// nor the revenue one.
  TextColumn get txnNumber => text().named('txn_number').nullable()();
  TextColumn get financialYear => text().named('financial_year').nullable()();

  /// The owner this movement debits or credits.
  ///
  /// **Resolved at acceptance and stored**, never re-derived through the family mapping at
  /// read time. That is the whole of the guarantee that reassigning a family member later
  /// cannot restate an accepted attribution (§12), and it is the same discipline that keeps
  /// a revenue component explainable after its tax rule is superseded (D-080).
  TextColumn get ownerId => text().named('owner_id')();

  /// Where the movement happened (§10). Source attribution for audit and reporting; it
  /// does **not** decide the profit share, which is organisation-wide.
  TextColumn get businessUnitId => text().named('business_unit_id')();

  /// Derived under the property's timezone and cut-off, then persisted (D-019, D-067).
  TextColumn get businessDate => text().named('business_date')();

  /// `YYYY-MM` of [businessDate]. Period lookups and reporting read this.
  TextColumn get pnlPeriodKey => text().named('pnl_period_key')();

  /// `derived` | `corrected`. Server-owned, exactly as revenue's is (D-143). There is no
  /// `manual`: no owner surface offers a trading day at entry, so the value has no
  /// producer and the CHECK does not admit it.
  TextColumn get businessDateSource => text()
      .named('business_date_source')
      .withDefault(const Constant('derived'))();

  /// `opening_balance` | `withdrawal` | `nc_consumption` | `settlement_paid` |
  /// `manual_adjustment`.
  TextColumn get movementType => text().named('movement_type')();

  /// `credit` | `debit`. Held to the type's fixed direction by a check constraint below,
  /// so a withdrawal cannot be stored as a credit even by a direct write.
  TextColumn get direction => text()();

  /// **Always positive.** The direction decides the effect (§43).
  IntColumn get amountMinor => integer().named('amount_minor')();

  /// Who consumed, for an NC movement.
  TextColumn get familyMemberId =>
      text().named('family_member_id').nullable()();

  /// Who physically collected a withdrawal. **Metadata, never an attribution** — the
  /// financial debit stays with [ownerId] and no aggregate groups by this (§13).
  TextColumn get collectedByFamilyMemberId =>
      text().named('collected_by_family_member_id').nullable()();

  TextColumn get ncBillReference =>
      text().named('nc_bill_reference').nullable()();
  TextColumn get paymentMethodId =>
      text().named('payment_method_id').nullable()();
  TextColumn get referenceNumber =>
      text().named('reference_number').nullable()();
  TextColumn get remarks => text().nullable()();

  /// Mandatory for a manual adjustment; optional otherwise.
  TextColumn get reason => text().nullable()();

  TextColumn get createdBy => text().named('created_by')();

  /// The device instant. Forensic metadata; never authoritative (spec §9).
  DateTimeColumn get capturedAt => dateTime().named('captured_at')();

  DateTimeColumn get voidedAt => dateTime().named('voided_at').nullable()();
  TextColumn get voidedBy => text().named('voided_by').nullable()();
  TextColumn get voidReason => text().named('void_reason').nullable()();

  // ── Sync ─────────────────────────────────────────────────────────────────
  /// The queued intent that will deliver this row, if one is outstanding. Sync state is
  /// **derived** through this link rather than copied into a column that could disagree
  /// with the outbox — the duplication D-131 had to remove from the revenue surfaces.
  TextColumn get pendingMutationId =>
      text().named('pending_mutation_id').nullable()();

  IntColumn get rowVersion =>
      integer().named('row_version').withDefault(const Constant(1))();
  DateTimeColumn get serverUpdatedAt =>
      dateTime().named('server_updated_at').nullable()();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  /// Set when a confirmed revocation kept this row because it still carries the actor's
  /// own unsent work (D-070, D-074). Null on everything browsable.
  DateTimeColumn get scopeRevokedAt =>
      dateTime().named('scope_revoked_at').nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (movement_type IN ('opening_balance','withdrawal','nc_consumption',"
        "'settlement_paid','manual_adjustment'))",
    "CHECK (direction IN ('credit','debit'))",
    "CHECK (business_date_source IN ('derived','corrected'))",
    // Positive magnitudes only. One event, one representation (§43).
    'CHECK (amount_minor >= 0)',
    // The three fixed-direction types are held to their direction here, so the rule is
    // structural rather than something the repository has to remember on every path.
    "CHECK (movement_type NOT IN ('withdrawal','nc_consumption','settlement_paid') "
        "OR direction = 'debit')",
    // Only a consumption names a consumer. A collector is a different fact.
    "CHECK (movement_type = 'nc_consumption' OR family_member_id IS NULL)",
    // An adjustment always states why, and **whitespace of any kind is not a reason**
    // (spec §14.1).
    //
    // `char(32,9,10,13)` is load-bearing rather than decorative. SQLite's one-argument
    // `trim()` strips **spaces only**, so `trim(<tab>)` is a tab and the plain form would
    // have accepted a single keypress as the justification for moving an owner's account.
    // That is D-138 and D-142 exactly — one-argument `btrim` on the server had the same
    // hole, and two documents were permanently voided with a tab as the record of why.
    //
    // Caught here by a test that tried a tab and expected a refusal, which is the only
    // way this class of defect is ever found.
    "CHECK (movement_type <> 'manual_adjustment' "
        "OR length(trim(coalesce(reason,''), char(32,9,10,13))) > 0)",
    // A void always states who and why (spec §14), under the same rule.
    'CHECK (voided_at IS NULL OR (voided_by IS NOT NULL '
        "AND length(trim(coalesce(void_reason,''), char(32,9,10,13))) > 0))",
    // Issued together or not at all.
    'CHECK ((txn_number IS NULL) = (financial_year IS NULL))',
    "CHECK (business_date LIKE '____-__-__')",
    "CHECK (pnl_period_key LIKE '____-__')",
  ];
}
