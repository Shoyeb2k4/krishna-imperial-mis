/// The local encrypted database.
///
/// This is the app's read model and its write buffer. Every user-visible save lands
/// here first, with no network involved (docs/ARCHITECTURE.md §4).
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [AppMeta, SyncOutbox])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Phase 1 foundation schema. Financial tables raise this number as they land, each
  /// with a migration step and a migration test (docs/RELEASE_CHECKLIST.md §C).
  @override
  int get schemaVersion => 1;

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
    },
    beforeOpen: (details) async {
      // Referential integrity is not optional in a financial database.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
