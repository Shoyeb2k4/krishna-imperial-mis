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

  /// How the **current** [businessDate] came to be what it is: `derived` by the unit's
  /// cut-off rule, or `corrected` afterwards by a privileged user (spec §9, D-019).
  ///
  /// Server-owned. `revenue_create` takes no provenance argument and states `derived`
  /// itself; `revenue_update` writes `corrected` only on the branch where it has
  /// established, from canonical state, that the date moved. This column is a cache of
  /// that answer, and the pull and the reconciler copy it rather than deriving it.
  ///
  /// No `manual`: unlike an expense, no revenue surface offers a trading day at entry, so
  /// the value has no producer and the server's CHECK does not admit it.
  TextColumn get businessDateSource =>
      text().withDefault(const Constant('derived'))();

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

  /// `YYYY-MM-DD`, inclusive lower bound.
  TextColumn get effectiveFrom => text()();

  /// `YYYY-MM-DD`, **exclusive** upper bound. Null means still in force.
  ///
  /// Added by the A2 audit. Without it the cache could hold two open-ended statuses for
  /// one unit and the offline resolver would have to pick "the latest start" — a ranking,
  /// which is exactly what D-094 forbids for a tax fact. The server enforces
  /// non-overlap with an exclusion constraint; this column is what lets the cache
  /// represent that timeline faithfully rather than approximate it.
  TextColumn get effectiveTo => text().nullable()();

  DateTimeColumn get archivedAt => dateTime().nullable()();

  TextColumn get statusCode => text()();
  TextColumn get note => text().nullable()();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (effective_from LIKE '____-__-__')",
    "CHECK (effective_to IS NULL OR effective_to > effective_from)",
    'CHECK (length(trim(status_code)) > 0)',
  ];
}

/// What this device has authoritatively received, per user and per business unit.
///
/// **The reason this is a table and not a flag.** Slice 5 shipped a single global
/// `app_meta` key — `revenue.configuration.synced_at` — whose presence claimed the whole
/// organisation's revenue configuration was authoritative. That is too coarse in three
/// separate ways, and each of them is a way to tell a manager something false:
///
///  * **Scope.** Synchronising Crystal Canopy would have made Hotel Krishna's
///    configuration look authoritative, so a Room entry would resolve
///    `noApplicableRule` — *"the Owner has not configured a rule"* — on a device that had
///    simply never been told about Hotel Krishna.
///  * **User.** One person's successful sync would have vouched for a scope the next
///    person on a shared workstation does not hold (D-051, D-074).
///  * **Dataset.** Tax rules arriving proves nothing about bands, subtypes or premises
///    statuses, which the same resolution depends on. "Some of it arrived" is not a
///    synchronised configuration.
///
/// So completeness is recorded where it is actually true: for one user, for one business
/// unit, naming the datasets proven present and the server generation they came from.
class RevenueConfigSnapshots extends Table {
  @override
  String get tableName => 'revenue_config_snapshots';

  /// Whose sync this was. A snapshot vouches for nobody else (D-051 §9).
  TextColumn get userId => text()();

  TextColumn get orgId => text()();

  /// Soft pointer, like every other scoped cache row: the unit may be purged from
  /// underneath it, and this row is precisely what has to survive that to say so.
  TextColumn get businessUnitId => text()();

  /// `complete` or `revoked`.
  ///
  /// A revocation **downgrades** rather than deletes, so the device can still tell the
  /// two silences apart: no row at all means this scope was never synchronised here,
  /// while `revoked` means it was and the authority was withdrawn. Both refuse new
  /// offline revenue; only one of them is a statement about this user's access (D-106).
  TextColumn get status => text()();

  /// The dataset codes proven present, comma-separated and sorted.
  ///
  /// Stored as data rather than implied by row counts, because zero subtypes is a
  /// legitimate synchronised answer and is not the same fact as never having asked.
  TextColumn get datasets => text().withDefault(const Constant(''))();

  /// The server generation this snapshot came from — the greatest `change_seq` observed
  /// across the datasets, so two runs cannot be silently interleaved into one claim.
  TextColumn get generation => text().nullable()();

  /// **Server** time, taken from the confirmed authority. Never the device clock, which
  /// is forensic metadata only (spec §9).
  DateTimeColumn get confirmedAt => dateTime().nullable()();

  /// Device clock, kept for diagnostics and never used to decide anything.
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId, businessUnitId};

  @override
  List<String> get customConstraints => [
    "CHECK (status IN ('complete', 'revoked'))",
    // A complete snapshot that names no datasets is a claim with no evidence behind it.
    "CHECK (status <> 'complete' OR length(datasets) > 0)",
  ];
}

/// Supporting evidence attached to a revenue entry (schema v14, Phase 4 Slice 11).
///
/// Deliberately the same shape as `ExpenseAttachments`, column for column, with the
/// parent pointer changed. The two are not merged into one polymorphic table: a single
/// `owner_id` with a discriminator would give up the foreign key that makes an orphan
/// impossible, and a foreign key is precisely what a cascade and a purge rely on. Two
/// narrow tables with one shared *lifecycle* is the trade this project already made for
/// expenses and revenue themselves.
///
/// **The staging columns have no server counterpart**, because staging is a client
/// concern: a till report is copied into app-private storage before the sale is even
/// saved, and the upload happens afterwards, out of band, without the financial record
/// waiting for it (spec §15).
///
/// **Nothing here is a financial figure.** No amount, no tax, no contribution — an
/// attachment is evidence for a document and never a source of truth about it, and a
/// test asserts that attaching one moves no money.
@DataClassName('RevenueAttachmentRow')
class RevenueAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get revenueEntryId =>
      text().references(RevenueEntries, #id, onDelete: KeyAction.cascade)();

  TextColumn get fileName => text()();
  TextColumn get contentType => text()();
  IntColumn get byteSize => integer()();

  /// SHA-256 of the staged bytes, computed before upload and compared afterwards.
  TextColumn get contentHash => text()();

  /// The app-private staging copy. Never a gallery or Downloads path: those can be
  /// moved, renamed or revoked by the OS between capture and upload.
  TextColumn get localPath => text().nullable()();

  /// One of `AttachmentUploadState`. The lifecycle lives in that enum, not here, and it
  /// is the same enum the expense pipeline uses — including `waitingForExpense`, which
  /// means "the parent financial document has not been accepted yet" and keeps its name
  /// because it is a stored value on every device already in the field.
  TextColumn get uploadState => text().withDefault(const Constant('staged'))();
  TextColumn get storagePath => text().nullable()();

  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  DateTimeColumn get uploadedAt => dateTime().nullable()();

  /// When the verified staging copy becomes eligible for reclamation — seven days after
  /// the server confirmed *and* the hash matched (`AttachmentPolicy.stagingRetention`).
  DateTimeColumn get reclaimableAfter => dateTime().nullable()();

  TextColumn get uploadedBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (byte_size > 0)',
    "CHECK (upload_state IN ('staged','waitingForExpense','pendingUpload',"
        "'uploading','uploaded','stagingReclaimed','retryNeeded','rejected'))",
    // A terminal refusal carries no retry time. A null there was once read as "due now",
    // which retried a refusal for ever (D-073 §4).
    "CHECK (upload_state <> 'rejected' OR next_attempt_at IS NULL)",
    // Confirmed means the server has it *and* the bytes matched.
    "CHECK (upload_state <> 'uploaded' OR (storage_path IS NOT NULL "
        'AND uploaded_at IS NOT NULL))',
  ];
}
