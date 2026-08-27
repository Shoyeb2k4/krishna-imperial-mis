/// The local encrypted database.
///
/// This is the app's read model and its write buffer. Every user-visible save lands
/// here first, with no network involved (docs/ARCHITECTURE.md §4).
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/master_tables.dart';
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// v1 — Phase 1 foundation: `app_meta`, `sync_outbox`.
  /// v2 — Phase 2 masters and period locks.
  ///
  /// Financial tables raise this number as they land, each with a migration step and a
  /// migration test (docs/RELEASE_CHECKLIST.md §C).
  @override
  int get schemaVersion => 2;

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
  Future<void> _createPeriodLockUniqueIndex() => customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS ux_period_locks_scope '
    "ON period_locks (org_id, COALESCE(business_unit_id, ''), period_key)",
  );
}
