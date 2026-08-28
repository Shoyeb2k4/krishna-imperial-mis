/// The local encrypted database.
///
/// This is the app's read model and its write buffer. Every user-visible save lands
/// here first, with no network involved (docs/ARCHITECTURE.md §4).
library;

import 'package:drift/drift.dart';
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
  ///
  /// Financial tables raise this number as they land, each with a migration step and a
  /// migration test (docs/RELEASE_CHECKLIST.md §C).
  @override
  int get schemaVersion => 6;

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
    },
    beforeOpen: (details) async {
      // Referential integrity is not optional in a financial database. Without this,
      // SQLite silently ignores every foreign key declared above.
      await customStatement('PRAGMA foreign_keys = ON');
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
