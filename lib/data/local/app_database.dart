/// The local encrypted database.
///
/// This is the app's read model and its write buffer. Every user-visible save lands
/// here first, with no network involved (docs/ARCHITECTURE.md §4).
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/expense_tables.dart';
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
  /// v9 — `expenses.scope_revoked_at`. A confirmed revocation now purges synced financial
  ///      cache for the revoked unit rather than retaining it, so the one thing that must
  ///      survive — a document still carrying the actor's own unsent, rejected or
  ///      conflicted intent — needs somewhere to say it is being kept for that reason and
  ///      is not browsable financial data (D-068).
  ///
  /// Financial tables raise this number as they land, each with a migration step and a
  /// migration test (docs/RELEASE_CHECKLIST.md §C).
  @override
  int get schemaVersion => 9;

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
      await _createTaxRateUniqueIndex();
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
