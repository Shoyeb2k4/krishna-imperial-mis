/// The local revenue read model (schema v11, Phase 4 Slice 3).
///
/// Built on the expense model's proven shape rather than a second lifecycle: the same
/// client-generated UUID identity, the same nullable server-issued number, the same
/// `pendingMutationId` link that derives sync state from the outbox instead of duplicating
/// it, the same `scopeRevokedAt` quarantine stamp, and the same actor ownership that keeps
/// one person's unsent work out of another's ledger (D-050, D-068, D-070, D-074).
///
/// ## Header totals are derived, not stored
///
/// A revenue entry's gross, tax and net are the **exact integer sums of its components**
/// (D-078), and this schema carries no header total columns at all. That is a deliberate
/// choice over the alternative of storing them and holding them equal by trigger.
///
/// SQLite has no deferred constraint triggers, so a validating trigger would fire between
/// the statements of a legitimate multi-row write and reject work that is correct by the
/// time it commits. A *maintaining* trigger avoids that, and leaves a header column that
/// some future writer can still `UPDATE` directly. Deriving removes the failure mode
/// instead of guarding it: there is no second copy to disagree, so "the header reconciles
/// to its components" is not an invariant to be enforced but a statement with nothing to
/// falsify.
///
/// `revenue_entry_totals` is the view that does the summing. Postgres holds the
/// authoritative version of this invariant in Slice 4, where a deferred trigger genuinely
/// is available.
///
/// ## Why there is no scoped/complete split here
///
/// The expense header hides `documentTotalMinor` from a unit-scoped user because
/// `total − own share` is the other property's share. **Revenue has no such channel**: an
/// entry belongs to exactly one business unit and one revenue category (spec §8), so a
/// user who may see the entry at all may see all of it. Reproducing the expense
/// visibility columns would be cargo cult — the security property they exist for does not
/// arise.
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/master_tables.dart';

/// A revenue document.
@DataClassName('RevenueEntryRow')
class RevenueEntries extends Table {
  /// Client-generated UUID v7, assigned before the server sees the row (D-008).
  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// `KI-REV-26-27-000001`, issued by the server after it accepts the write (spec §8.4).
  ///
  /// **Null until then, and never fabricated locally** — two devices offline for a week
  /// would both invent the same number. Its own sequence, never the expense one.
  TextColumn get txnNumber => text().nullable()();
  TextColumn get financialYear => text().nullable()();

  /// Soft pointers, for the reason v5 and v8 made their expense counterparts soft: a
  /// per-user cache legitimately outlives the masters it names, and a foreign key with
  /// `ON DELETE RESTRICT` made sign-out throw on a device holding financial rows (D-068).
  TextColumn get businessUnitId => text()();
  TextColumn get revenueCategoryId => text()();

  /// Derived under the unit's timezone and cut-off, then persisted (D-067). `YYYY-MM-DD`.
  TextColumn get businessDate => text()();

  /// `YYYY-MM` of [businessDate], for period lookups and reporting.
  TextColumn get pnlPeriodKey => text()();

  /// The device instant. Forensic metadata; never authoritative (spec §9).
  DateTimeColumn get capturedAt => dateTime()();

  /// `daily_summary` | `shift` | `import` | `correction` (spec §8.2).
  TextColumn get entryKind =>
      text().withDefault(const Constant('daily_summary'))();

  TextColumn get sourceReference => text().nullable()();
  TextColumn get notes => text().nullable()();

  TextColumn get createdBy => text()();

  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidedBy => text().nullable()();
  TextColumn get voidReason => text().nullable()();

  // ── Sync ─────────────────────────────────────────────────────────────────
  /// The queued intent that will deliver this row, if one is outstanding. Sync state is
  /// *derived* through this link rather than copied into a column that could disagree.
  TextColumn get pendingMutationId => text().nullable()();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  /// When a confirmed revocation removed this user's authority over this entry's business
  /// unit and the row was kept anyway (D-070).
  ///
  /// Null on everything a user may browse. Non-null on exactly one kind of row: an entry
  /// still carrying **its own unsent work** — a queued, failed, rejected or conflicted
  /// intent — at the moment its unit was revoked. Synced rows are purged; an unsent
  /// attempt exists nowhere else, so it is kept, stamped, and excluded from every
  /// canonical revenue read.
  ///
  /// A timestamp rather than a flag, so the retention is dateable.
  DateTimeColumn get scopeRevokedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (entry_kind IN ('daily_summary','shift','import','correction'))",
    // A void always states who and why (spec §14).
    'CHECK (voided_at IS NULL OR (voided_by IS NOT NULL '
        "AND length(trim(coalesce(void_reason,''))) > 0))",
    // Issued together or not at all.
    'CHECK ((txn_number IS NULL) = (financial_year IS NULL))',
    "CHECK (business_date LIKE '____-__-__')",
    "CHECK (pnl_period_key LIKE '____-__')",
  ];
}

/// One taxed slice of a revenue entry, carrying the rule that produced its figures.
///
/// Everything derived is stored, beside the facts that selected the rule, so a figure
/// stays explainable years later without consulting a rule table that may since have
/// changed — and so a retained entry survives a reference-cache purge with its own
/// explanation intact (D-070, spec §8.1).
@DataClassName('RevenueComponentRow')
class RevenueComponents extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// Cascade is scoped to local cache maintenance: the purge and the reconciler delete
  /// **entries**, and their components go with them. Nothing in the product deletes a
  /// revenue document — correction is by void plus audit (D-006) — so this cascade can
  /// never become a business-level destructive delete.
  TextColumn get revenueEntryId =>
      text().references(RevenueEntries, #id, onDelete: KeyAction.cascade)();

  /// What the operator actually typed, and as what (D-080, D-097).
  IntColumn get enteredAmountMinor => integer()();

  /// `inclusive_total` | `pre_tax`. There is no third value (D-097).
  TextColumn get enteredBasis => text()();

  /// Derived once, half-up, at the record.
  IntColumn get grossAmountMinor => integer()();
  IntColumn get taxAmountMinor => integer()();
  IntColumn get netAmountMinor => integer()();

  // ── The rule that produced them, snapshotted ─────────────────────────────
  /// A **soft pointer**. The rule cache is server-owned reference data and may legitimately
  /// be purged when a scope is revoked, while this component must remain explainable from
  /// its own snapshot columns (D-070 §11). A foreign key here would either block that
  /// purge or destroy the retained work it is meant to spare.
  TextColumn get taxRuleId => text()();
  IntColumn get taxRateBasisPoints => integer()();

  /// `inclusive` | `exclusive` | `none`.
  TextColumn get taxTreatment => text()();

  // ── The facts that selected that rule, snapshotted ───────────────────────
  /// The configured band this amount was attributed to, **selected by the operator**.
  ///
  /// Soft pointer, for the same reason as [taxRuleId]. [valueBandFloorMinor] and
  /// [valueBandCeilingMinor] are the band's tariff boundaries, carried for **historical
  /// explanation only**: nothing compares them against [enteredAmountMinor] or any
  /// revenue total, because a day's aggregate attributable to a band is not a
  /// per-room-per-night tariff (D-094).
  TextColumn get valueBandId => text().nullable()();
  TextColumn get valueBandLabel => text().nullable()();
  IntColumn get valueBandFloorMinor => integer().nullable()();
  IntColumn get valueBandCeilingMinor => integer().nullable()();

  TextColumn get supplySubtypeId => text().nullable()();
  TextColumn get supplySubtypeLabel => text().nullable()();

  TextColumn get premisesStatusCode => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (entered_basis IN ('inclusive_total','pre_tax'))",
    "CHECK (tax_treatment IN ('inclusive','exclusive','none'))",
    'CHECK (entered_amount_minor >= 0)',
    'CHECK (gross_amount_minor >= 0)',
    'CHECK (tax_amount_minor >= 0)',
    'CHECK (tax_rate_basis_points BETWEEN 0 AND 10000)',
    // The invariant every component must satisfy, in the database rather than in a
    // convention.
    'CHECK (net_amount_minor = gross_amount_minor - tax_amount_minor)',
    'CHECK (tax_amount_minor <= gross_amount_minor)',
    // An untaxed component carries no rate, and a taxed one is not free.
    "CHECK ((tax_treatment = 'none' AND tax_amount_minor = 0) "
        "OR tax_treatment <> 'none')",
    // Band bounds explain a band; without one they are a number nothing selects on,
    // which is the shape D-094 warns about.
    'CHECK (value_band_id IS NOT NULL '
        'OR (value_band_floor_minor IS NULL AND value_band_ceiling_minor IS NULL))',
  ];
}

/// A configured value band — the stable identity an operator selects for a component.
///
/// **This master exists because rule identity cannot serve as band identity** (D-098).
/// Rules are date-effective and superseded: when a rate changes, new rows with new ids
/// take over. A band is the opposite — the lower tariff band is the same business concept
/// before and after a rate change. Using a rule id as the band would mean the same band
/// had different identities in different periods, which breaks reporting grouped by band
/// across a rate change (D-087), and would offer the entry form choices that vanish when
/// a rule is end-dated.
///
/// **Ships empty.** No band is created until a real tariff boundary is verified (D-096).
@DataClassName('RevenueValueBandRow')
class RevenueValueBands extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get revenueCategoryId =>
      text().references(RevenueCategories, #id, onDelete: KeyAction.restrict)();

  /// Immutable, like every master code (D-035).
  TextColumn get code => text()();

  /// Editable, for a rename that preserves meaning — the D-038 distinction, unchanged.
  TextColumn get label => text()();

  /// The tariff boundaries this band describes, per unit per day.
  ///
  /// **Write-once** (D-100). Editing a boundary in place would retroactively redefine
  /// what every effective-dated rule referencing this band applied to — including for
  /// dates already recorded — with nothing saying it had changed. A boundary change is a
  /// *different band*: create a new one and point [supersededByBandId] at it.
  ///
  /// Displayed and snapshotted; **never compared against a revenue amount** (D-094).
  IntColumn get floorMinor => integer().nullable()();
  IntColumn get ceilingMinor => integer().nullable()();

  /// The band that replaced this one, when its boundaries changed.
  ///
  /// Makes the lineage explicit, so a later reader can tell "this band replaced that one"
  /// from "an unrelated band appeared". Soft pointer, like every other cache reference.
  TextColumn get supersededByBandId => text().nullable()();

  DateTimeColumn get archivedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (floor_minor IS NULL OR floor_minor >= 0)',
    'CHECK (ceiling_minor IS NULL OR floor_minor IS NULL '
        'OR ceiling_minor > floor_minor)',
    // A band that describes no range at all is a label pretending to be a discriminator.
    'CHECK (floor_minor IS NOT NULL OR ceiling_minor IS NOT NULL)',
  ];
}

/// A configured supply subtype, where a category invoices more than one kind of supply.
///
/// **Ships empty** (D-083). No subtype configured for a category means no subtype field on
/// the form and rules with a null subtype match; the hinge exists without inventing what
/// Hotel Krishna Imperial actually invoices.
@DataClassName('RevenueSupplySubtypeRow')
class RevenueSupplySubtypes extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get revenueCategoryId =>
      text().references(RevenueCategories, #id, onDelete: KeyAction.restrict)();

  TextColumn get code => text()();
  TextColumn get label => text()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// A business unit's premises tax status over time (D-082).
///
/// Configured business data, entered from what the accountant states. **The application
/// never derives, infers or defaults it**, and a rule that requires a status with none
/// configured refuses the save rather than guessing.
///
/// **Ships empty.**
@DataClassName('BusinessUnitTaxStatusRow')
class BusinessUnitTaxStatuses extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// Soft pointer: this row outlives a purged unit exactly as expense history does.
  TextColumn get businessUnitId => text()();

  /// `YYYY-MM-DD`, inclusive lower bound. Open-ended until superseded.
  TextColumn get effectiveFrom => text()();
  TextColumn get statusCode => text()();
  TextColumn get note => text().nullable()();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (effective_from LIKE '____-__-__')",
    'CHECK (length(trim(status_code)) > 0)',
  ];
}
