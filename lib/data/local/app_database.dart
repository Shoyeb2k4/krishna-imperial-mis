/// The local encrypted database.
///
/// This is the app's read model and its write buffer. Every user-visible save lands
/// here first, with no network involved (docs/ARCHITECTURE.md §4).
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/expense_tables.dart';
import 'package:krishna_mis/data/local/revenue_tables.dart';
import 'package:krishna_mis/data/local/master_tables.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/local/tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    AppMeta,
    SyncOutbox,
    BusinessUnits,
    Departments,
    Sections,
    ExpenseCategories,
    RevenueCategories,
    Vendors,
    PaymentMethods,
    PeriodLocks,
    PeriodLockEvents,
    RevenueTaxRates,
    Expenses,
    ExpenseAllocations,
    ExpensePeriodAllocations,
    ExpenseAttachments,
    RevenueEntries,
    RevenueComponents,
    RevenueValueBands,
    RevenueSupplySubtypes,
    BusinessUnitTaxStatuses,
    RevenueConfigSnapshots,
    RevenueAttachments,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// v1 — Phase 1 foundation: `app_meta`, `sync_outbox`.
  /// v2 — Phase 2 masters and period locks.
  /// v3 — date-effective tax configuration; vendors gain a default business unit.
  /// v4 — seeded master ids move to the derived UUIDs the server also derives, so a
  ///      device that seeded itself offline agrees with Postgres on identity rather than
  ///      having to be reconciled by name.
  /// v5 — a vendor's default business unit and default category become soft pointers
  ///      rather than foreign keys (D-049): they are operational conveniences on an
  ///      organisation-global record, and a per-user cache legitimately holds vendors
  ///      whose default target it cannot see.
  /// v6 — the outbox records which user queued each intent, so a shared installation
  ///      never lets one person's device push another person's work (D-050).
  /// v7 — the expense read model: documents, allocation lines, period contributions and
  ///      attachment staging. Not a mirror of Postgres — a scoped record carries this
  ///      user's visible share and, by check constraint, **no** document total, because
  ///      total minus own share is the other property's share (see `expense_tables.dart`).
  ///
  /// v8 — `expense_allocations.business_unit_id` becomes a soft pointer, for the reason
  ///      v5 existed: a per-user cache legitimately outlives the masters it names, and
  ///      `ON DELETE RESTRICT` made sign-out throw on a device holding expenses (D-068).
  /// v10 — the attachment lifecycle becomes one durable state model (D-073): `staged`,
  ///       `waitingForExpense`, `pendingUpload`, `uploading`, `uploaded`,
  ///       `stagingReclaimed`, `retryNeeded`, `rejected`. A terminal refusal is
  ///       constrained to carry no retry time.
  /// v9 — `expenses.scope_revoked_at`. A confirmed revocation now purges synced financial
  ///      cache for the revoked unit rather than retaining it, so the one thing that must
  ///      survive — a document still carrying the actor's own unsent, rejected or
  ///      conflicted intent — needs somewhere to say it is being kept for that reason and
  ///      is not browsable financial data (D-068).
  ///
  /// v11 — the revenue read model (Phase 4 Slice 3): `revenue_entries`,
  ///       `revenue_components`, and the three reference caches the bounded conditional
  ///       tax model needs — `revenue_value_bands`, `revenue_supply_subtypes` and
  ///       `business_unit_tax_statuses`, all of which ship empty. `revenue_tax_rates`
  ///       gains `input_basis` and the three discriminators, **none of them backfilled**:
  ///       a pre-v11 rule has no authoritative answer for them and is left visibly
  ///       incomplete rather than given an invented one (D-079, D-096, D-097).
  ///
  ///       Revenue header totals are **not stored**. `revenue_entry_totals` derives them
  ///       from the components, so there is no second copy to drift (D-078).
  ///
  /// v15 — the revenue reporting interface (Phase 4 Slice 12): the
  ///       `revenue_period_contributions` view and the index a period report reads
  ///       through. **No table**: a revenue contribution carries no decision that is not
  ///       already stored on the entry and its components, so storing one would be a
  ///       second writable copy of facts that exist, with a maintenance lifecycle whose
  ///       every hazard — a correction moving a period, an edit replacing figures, a void
  ///       removing an effect, a replay applying twice — is a hazard of maintaining it
  ///       (D-157).
  ///
  /// Financial tables raise this number as they land, each with a migration step and a
  /// migration test (docs/RELEASE_CHECKLIST.md §C).
  @override
  int get schemaVersion => 15;

  /// Timestamps are stored as ISO-8601 **UTC text**, not as unix seconds.
  ///
  /// Drift's default returns timestamps in the device's local zone, which is exactly
  /// the ambiguity a financial system must not carry: the same row would read back
  /// differently on a laptop set to another timezone, and a value written as UTC would
  /// come back wearing a local label. Text storage keeps the zone explicit on disk and
  /// hands back UTC every time. Business *dates* are a separate concept entirely and
  /// carry no time at all (see BusinessDate).
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createPeriodLockUniqueIndex();
      // Deliberately **not** `_createTaxRateUniqueIndex()`. From v11 the conditional
      // model makes that index wrong — Room's two value bands are two live rules for one
      // category from the same date — so a fresh database must not be born with it. The
      // helper survives only for the historical upgrade paths below, which run against
      // schemas that predate conditional rules and then drop it at v11.
      await _createRevenueEntryTotalsView();
      await _createRevenuePeriodContributionsView();
      await _createRevenueIndexes();
      await _createImmutableBandTrigger();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(businessUnits);
        await m.createTable(departments);
        await m.createTable(sections);
        await m.createTable(expenseCategories);
        await m.createTable(revenueCategories);
        await m.createTable(vendors);
        await m.createTable(paymentMethods);
        await m.createTable(periodLocks);
        await m.createTable(periodLockEvents);
        await _createPeriodLockUniqueIndex();
      }
      if (from < 3) {
        await m.createTable(revenueTaxRates);
        await m.addColumn(vendors, vendors.defaultBusinessUnitId);
        await _createTaxRateUniqueIndex();
      }
      if (from < 4) {
        // Foreign keys are still off at this point — `PRAGMA foreign_keys = ON` is set in
        // `beforeOpen`, which runs after migrations — so parent ids and the columns that
        // reference them can be rewritten without SQLite rejecting the intermediate
        // state. `_masterIdColumns` lists every such column explicitly for that reason.
        await remapSeedIds(this);
      }
      if (from < 5) {
        // Recreating the table is the only way SQLite drops a foreign key. No data is
        // transformed: the same values are carried across, they simply stop being
        // structurally enforced.
        await m.alterTable(TableMigration(vendors));
      }
      if (from < 6) {
        await m.addColumn(syncOutbox, syncOutbox.actorUserId);
      }
      if (from < 7) {
        await m.createTable(expenses);
        await m.createTable(expenseAllocations);
        await m.createTable(expensePeriodAllocations);
        await m.createTable(expenseAttachments);
      }
      if (from < 8) {
        // `expense_allocations.business_unit_id` stops being a foreign key, for the
        // reason given on the column: the scope purge legitimately removes a business
        // unit while synced expense history stays, and `ON DELETE RESTRICT` made
        // sign-out throw on any device that had synced an expense. Recreating the table
        // is the only way SQLite drops a foreign key; no value is transformed.
        await m.alterTable(TableMigration(expenseAllocations));
      }
      if (from < 10) {
        // D-073 — the attachment lifecycle becomes one durable state model. The old four
        // values could not say "waiting for its expense" or tell a transient failure from
        // a terminal refusal, and the upload worker needs both.
        //
        // Existing rows are mapped conservatively: a `pending` attachment becomes
        // `waitingForExpense`, because this migration cannot know whether its expense has
        // been accepted and the worker will promote it as soon as one is. A `failed` row
        // splits on the one piece of evidence it carries — a retry time means it was
        // transient, its absence means it was refused.
        // The values are rewritten **during** the copy, not after it.
        //
        // Recreating the table first and updating afterwards cannot work, and the
        // Windows acceptance proved it on a device that actually had old rows: the new
        // table carries the new CHECK, so copying `pending` into it fails — while
        // rewriting beforehand would violate the *old* CHECK, which does not know the
        // new names. A column transformer is the only point at which neither constraint
        // is in the way.
        await m.alterTable(
          TableMigration(
            expenseAttachments,
            columnTransformer: {
              expenseAttachments.uploadState: const CustomExpression<String>(
                "CASE upload_state "
                "WHEN 'pending' THEN 'waitingForExpense' "
                "WHEN 'failed' THEN "
                '  (CASE WHEN next_attempt_at IS NOT NULL '
                "        THEN 'retryNeeded' ELSE 'rejected' END) "
                'ELSE upload_state END',
              ),
            },
          ),
        );
      }
      if (from < 11) {
        // Phase 4 Slice 3. New tables, and four nullable columns on the rule cache.
        //
        // Nothing is backfilled, and that is the whole of the migration's opinion: a rule
        // cached before v11 predates the concepts of an input basis and of conditional
        // discriminators, so it carries no authoritative answer for them. Writing
        // `inclusive_total` — even though every verified V1 category happens to use it —
        // would be inventing a business fact about whether a recorded figure includes
        // tax, which is the D-043 line the whole tax model is built behind. A rule with
        // no basis is visibly incomplete and the resolver refuses it, which is correct.
        await m.createTable(revenueEntries);
        await m.createTable(revenueComponents);
        await m.createTable(revenueValueBands);
        await m.createTable(revenueSupplySubtypes);
        await m.createTable(businessUnitTaxStatuses);
        await _createRevenueEntryTotalsView();
        await _createImmutableBandTrigger();
        await _replaceTaxRateUniqueIndex();
        await m.addColumn(revenueTaxRates, revenueTaxRates.inputBasis);
        await m.addColumn(revenueTaxRates, revenueTaxRates.valueBandId);
        await m.addColumn(revenueTaxRates, revenueTaxRates.supplySubtypeId);
        await m.addColumn(revenueTaxRates, revenueTaxRates.premisesStatusCode);
        await _createRevenueIndexes();
      }
      if (from < 12) {
        // Per-scope revenue configuration completeness (D-108).
        //
        // Replaces the single global `app_meta` key Slice 5 shipped. Nothing is
        // backfilled and the old key is removed rather than translated: it claimed
        // completeness for the whole organisation, and there is no honest way to decide
        // which user held which scope when it was written. A device that upgrades simply
        // has no proven snapshot and re-synchronises, which is the correct fail-closed
        // answer and costs one pull.
        await m.createTable(revenueConfigSnapshots);
        await customStatement(
          "DELETE FROM app_meta WHERE key = 'revenue.configuration.synced_at'",
        );
      }
      if (from >= 11 && from < 13) {
        // Revenue records how its current business date was established (spec §9, D-019).
        //
        // The column defaults to `derived`, so every row an upgrading device already
        // holds gets that — which is the honest answer and the only one available.
        // Nothing infers a past correction from `updated_at`, a row version, notes or a
        // date comparison: none of those is evidence, and inventing provenance is worse
        // than not having it. Where a row really was corrected, the server says so and
        // the next pull overwrites this value with the canonical one.
        //
        // **`from >= 11` is load-bearing, not defensive.** `revenue_entries` is created
        // at v11 from the *current* table definition, which now includes this column — so
        // a device coming from v10 or earlier already has it by the time this step is
        // reached, and adding it again fails with `duplicate column name`. Caught by the
        // v9 attachment-migration test, on the one fixture old enough to take that path.
        // Every column added to a table that is itself created by a later-than-v1 step
        // needs this guard, and the guard is a range rather than a floor so the intent
        // reads as "the versions that actually lack it".
        await m.addColumn(revenueEntries, revenueEntries.businessDateSource);
      }
      if (from < 14) {
        // Phase 4 Slice 11 — supporting evidence for a revenue entry.
        //
        // A new table, so no guard beyond the plain floor is needed: unlike the v13
        // column, this is not added to a table that a later-than-v1 step creates from
        // the current definition, so there is nothing for an upgrading device to
        // already have (D-144).
        //
        // Nothing is backfilled and nothing could be: no revenue attachment has ever
        // existed on any device.
        await m.createTable(revenueAttachments);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS ix_revenue_attachments_entry '
          'ON revenue_attachments (revenue_entry_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS ix_revenue_attachments_due '
          'ON revenue_attachments (upload_state, next_attempt_at)',
        );
      }
      if (from >= 11 && from < 15) {
        // Phase 4 Slice 12 — the revenue reporting interface (D-087, D-157).
        //
        // A view and an index, and deliberately nothing else. Everything a contribution
        // reports is already stored: its money on the component, its period on the entry
        // as `pnl_period_key`, under a server CHECK that ties that key to the business
        // date. A table here would be a second copy of those facts, and the only thing it
        // could add is the obligation to keep them in step through a correction, an edit,
        // a void and a replay.
        //
        // **`from >= 11` is the D-144 guard.** `revenue_entries` and `revenue_components`
        // are created at v11, so a device coming from v10 or earlier has neither when this
        // step is reached and the view would reference tables that do not exist yet. A
        // fresh database gets the view from `onCreate` instead.
        await _createRevenuePeriodContributionsView();
        await customStatement(
          'CREATE INDEX IF NOT EXISTS ix_revenue_entries_reporting '
          'ON revenue_entries (org_id, pnl_period_key, business_unit_id, '
          'revenue_category_id) WHERE voided_at IS NULL',
        );
      }
      if (from < 9) {
        // `expenses.scope_revoked_at` (D-068). Nothing is back-filled: every row that
        // exists at upgrade time is one this user could browse, and the column means
        // "kept through a revocation", which has not happened to any of them.
        await m.addColumn(expenses, expenses.scopeRevokedAt);
      }
    },
    beforeOpen: (details) async {
      // Referential integrity is not optional in a financial database. Without this,
      // SQLite silently ignores every foreign key declared above.
      await customStatement('PRAGMA foreign_keys = ON');

      // Deleted content is overwritten rather than left in the free list.
      //
      // This matters because of what the delete now means. Since D-068 a confirmed
      // revocation removes the revoked property's figures, and D-062's argument for the
      // scoped projection was explicitly about a raw database file being readable — not
      // about what a widget chooses to draw. Without this pragma the removed rows stay
      // legible in freed pages until something happens to overwrite them, so the purge
      // would be weaker than the projection it is protecting.
      //
      // Cheap at this write volume, and the alternative (VACUUM after every purge)
      // rewrites the entire database to solve a smaller problem.
      await customStatement('PRAGMA secure_delete = ON');
    },
  );

  /// SQLite treats NULLs as distinct in a unique index, so `(org, business_unit, period)`
  /// alone would permit two org-wide locks on the same period — and then a reopen of one
  /// while the other still closed it. Collapsing NULL to `''` makes the constraint mean
  /// what Postgres's `unique nulls not distinct` means.
  /// Partial, so it constrains only **live** rules.
  ///
  /// A rule that has been archived must not keep reserving its period — archiving exists
  /// precisely so a mistaken rate can be replaced. Postgres will express the full rule as
  /// an exclusion constraint over a `daterange`; this is SQLite's nearest backstop, and
  /// the repository enforces the complete non-overlap rule inside a transaction.
  /// Derived revenue totals. There are no header total columns to drift from these.
  ///
  /// Raw SQL rather than a Drift `View` class: the shape is a plain aggregate and keeping
  /// it out of code generation keeps the migration legible.
  Future<void> _createRevenueEntryTotalsView() => customStatement(
    'CREATE VIEW IF NOT EXISTS revenue_entry_totals AS '
    'SELECT e.id AS revenue_entry_id, '
    '       COALESCE(SUM(c.gross_amount_minor), 0) AS gross_minor, '
    '       COALESCE(SUM(c.tax_amount_minor), 0)   AS tax_minor, '
    '       COALESCE(SUM(c.net_amount_minor), 0)   AS net_minor, '
    '       COUNT(c.id) AS component_count '
    '  FROM revenue_entries e '
    '  LEFT JOIN revenue_components c ON c.revenue_entry_id = e.id '
    ' GROUP BY e.id',
  );

  /// The revenue reporting interface (D-087, D-157): one row per accepted component.
  ///
  /// The local half of `public.revenue_period_contributions`, column for column, so a
  /// report written against one runs against the other. Raw SQL for the same reason the
  /// totals view is — the shape is a plain projection, and keeping it out of code
  /// generation keeps the migration legible.
  ///
  /// **A view rather than a table, on both sides.** Nothing here is a fact that is not
  /// already stored: the money is the component's own snapshot and the period is the
  /// entry's own `pnl_period_key`. A stored copy would have to be maintained through
  /// every correction, edit, void and replayed mutation, and each of those is a way for
  /// two copies of one figure to disagree.
  ///
  /// It carries `voided_at` and does **not** filter on it, exactly as
  /// `expense_period_contributions` does: a voided sale's contributions stay inspectable
  /// for audit and are excluded by every aggregate (D-006). `scope_revoked_at` is carried
  /// for the same reason — a retained, unsent attempt over a property this user no longer
  /// holds is nobody's revenue (D-070).
  Future<void> _createRevenuePeriodContributionsView() => customStatement(
    'CREATE VIEW IF NOT EXISTS revenue_period_contributions AS '
    'SELECT c.id                       AS id, '
    '       c.org_id                   AS org_id, '
    '       c.revenue_entry_id         AS revenue_entry_id, '
    '       e.business_unit_id         AS business_unit_id, '
    '       e.revenue_category_id      AS revenue_category_id, '
    '       c.supply_subtype_id        AS supply_subtype_id, '
    '       c.value_band_id            AS value_band_id, '
    '       c.value_band_floor_minor   AS value_band_min_minor, '
    '       c.value_band_ceiling_minor AS value_band_max_minor, '
    '       c.premises_status_code     AS premises_status_code, '
    '       e.business_date            AS business_date, '
    '       e.business_date            AS pnl_date, '
    '       e.pnl_period_key           AS pnl_period_key, '
    '       c.gross_amount_minor       AS gross_minor, '
    '       c.tax_amount_minor         AS tax_minor, '
    '       c.net_amount_minor         AS net_minor, '
    '       c.tax_rule_id              AS tax_rule_id, '
    '       c.tax_rate_basis_points    AS tax_rate_bp, '
    '       c.tax_treatment            AS tax_treatment, '
    '       c.entered_basis            AS entered_basis, '
    '       e.entry_kind               AS entry_kind, '
    '       e.txn_number               AS txn_number, '
    '       e.business_date_source     AS business_date_source, '
    '       e.voided_at                AS voided_at, '
    '       e.scope_revoked_at         AS scope_revoked_at '
    '  FROM revenue_components c '
    '  JOIN revenue_entries e ON e.id = c.revenue_entry_id',
  );

  /// Refuses an in-place change to what a value band *means*.
  ///
  /// A band's tariff boundaries are write-once (D-100). Editing them would retroactively
  /// redefine what every effective-dated rule referencing the band applied to — for dates
  /// already recorded as well as future ones — and nothing would say it had happened. A
  /// boundary change is a different band; create one and set `superseded_by_band_id`.
  ///
  /// A trigger rather than a convention, because "do not edit this" in a comment is the
  /// class of rule this project has repeatedly found nobody evaluates (D-068, D-077).
  /// The label stays editable: a rename that preserves meaning is D-038's permitted case.
  Future<void> _createImmutableBandTrigger() => customStatement('''
    CREATE TRIGGER IF NOT EXISTS trg_value_band_bounds_immutable
    BEFORE UPDATE ON revenue_value_bands
    FOR EACH ROW WHEN
          OLD.floor_minor IS NOT NEW.floor_minor
       OR OLD.ceiling_minor IS NOT NEW.ceiling_minor
       OR OLD.code IS NOT NEW.code
       OR OLD.revenue_category_id IS NOT NEW.revenue_category_id
    BEGIN
      SELECT RAISE(ABORT,
        'a value band boundary is write-once: create a new band and supersede this one');
    END
  ''');

  /// Indexes for the queries the revenue surfaces actually run.
  Future<void> _createRevenueIndexes() async {
    for (final statement in const [
      // The ledger: a unit's entries for a date range, newest first.
      'CREATE INDEX IF NOT EXISTS ix_revenue_entries_ledger '
          'ON revenue_entries (org_id, business_unit_id, business_date)',
      // Period reporting and the period-lock check.
      'CREATE INDEX IF NOT EXISTS ix_revenue_entries_period '
          'ON revenue_entries (org_id, pnl_period_key)',
      // What a period report actually reads: a month, then a property, then a
      // category, and never a voided row (Slice 12).
      'CREATE INDEX IF NOT EXISTS ix_revenue_entries_reporting '
          'ON revenue_entries (org_id, pnl_period_key, business_unit_id, '
          'revenue_category_id) WHERE voided_at IS NULL',
      // The duplicate-day prompt: is there already an active entry for this
      // unit/category/date? Deliberately **not unique** (spec §8.2).
      'CREATE INDEX IF NOT EXISTS ix_revenue_entries_day '
          'ON revenue_entries (business_unit_id, revenue_category_id, '
          'business_date) WHERE voided_at IS NULL',
      // Sync: what is outstanding, and whose it is (D-050, D-074).
      'CREATE INDEX IF NOT EXISTS ix_revenue_entries_pending '
          'ON revenue_entries (pending_mutation_id) '
          'WHERE pending_mutation_id IS NOT NULL',
      'CREATE INDEX IF NOT EXISTS ix_revenue_entries_actor '
          'ON revenue_entries (created_by)',
      // Retained-after-revocation lookup (D-070).
      'CREATE INDEX IF NOT EXISTS ix_revenue_entries_revoked '
          'ON revenue_entries (scope_revoked_at) '
          'WHERE scope_revoked_at IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_revenue_entries_txn '
          'ON revenue_entries (org_id, txn_number) WHERE txn_number IS NOT NULL',
      // Components by parent — every read of an entry needs them.
      'CREATE INDEX IF NOT EXISTS ix_revenue_components_entry '
          'ON revenue_components (revenue_entry_id)',
      // Rule resolution, over the bounded dimensions.
      'CREATE INDEX IF NOT EXISTS ix_tax_rates_resolution '
          'ON revenue_tax_rates (revenue_category_id, effective_from) '
          'WHERE archived_at IS NULL',
      'CREATE INDEX IF NOT EXISTS ix_value_bands_category '
          'ON revenue_value_bands (revenue_category_id) '
          'WHERE archived_at IS NULL',
      'CREATE INDEX IF NOT EXISTS ix_supply_subtypes_category '
          'ON revenue_supply_subtypes (revenue_category_id) '
          'WHERE archived_at IS NULL',
      'CREATE INDEX IF NOT EXISTS ix_unit_tax_status_timeline '
          'ON business_unit_tax_statuses (business_unit_id, effective_from)',
    ]) {
      await customStatement(statement);
    }
  }

  /// Drops the pre-v11 unique index that conditional rules make wrong.
  ///
  /// `ux_tax_rates_live_period` was unique over `(revenue_category_id, effective_from)`
  /// among live rules. Under the conditional model that is **too strict**: Room's two
  /// value bands are by construction two live rules for one category from the same date,
  /// so the index would refuse configuration the server had legitimately accepted — and
  /// it would surface as a sync failure rather than as anything a person could act on.
  /// The same contradiction D-093 found in the Postgres exclusion constraint, mirrored
  /// here.
  ///
  /// It is **not replaced by a wider unique index**, because uniqueness cannot express
  /// the doctrine either: a null discriminator matches every value, so a wildcard rule and
  /// a specific one are distinct rows and a unique index would happily hold both, while
  /// the doctrine calls them a conflict (D-094). Ambiguity is decided where the facts are
  /// — by the resolver at read time, and authoritatively by the server (D-095). This is a
  /// cache; it stores what the server sent.
  Future<void> _replaceTaxRateUniqueIndex() async {
    await customStatement('DROP INDEX IF EXISTS ux_tax_rates_live_period');
  }

  Future<void> _createTaxRateUniqueIndex() => customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_rates_live_period '
    'ON revenue_tax_rates (revenue_category_id, effective_from) '
    'WHERE archived_at IS NULL',
  );

  Future<void> _createPeriodLockUniqueIndex() => customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS ux_period_locks_scope '
    "ON period_locks (org_id, COALESCE(business_unit_id, ''), period_key)",
  );
}
