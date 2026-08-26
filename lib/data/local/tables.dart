/// Local database tables.
///
/// Phase 1 defines only the infrastructure tables the foundation needs: a key/value
/// metadata table and the synchronisation outbox. Financial tables arrive with their
/// own migrations in Phases 2–4, per docs/DATABASE_SCHEMA.md.
library;

import 'package:drift/drift.dart';

/// Small key/value store for bootstrap and diagnostic markers (schema provenance,
/// install id, last successful sync). Never used for financial data.
@DataClassName('AppMetaRow')
class AppMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// The local outbox: one row per user intent, durable across app restarts.
///
/// Written in the *same local transaction* as the domain rows it describes, so a save
/// can never succeed while its queue entry is lost (docs/ARCHITECTURE.md §5.1).
@DataClassName('SyncOutboxRow')
class SyncOutbox extends Table {
  /// Generated once per intent and reused for every retry. This is the primary key
  /// precisely so the same intent can never be enqueued twice.
  TextColumn get mutationId => text()();

  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  /// `create` | `update` | `void_` | `correctBusinessDate` | `archive`
  TextColumn get op => text()();

  /// The canonical document as JSON, including allocation lines.
  TextColumn get payload => text()();

  /// The row version this intent was based on. Null only for creates.
  IntColumn get baseRowVersion => integer().nullable()();

  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();

  /// See [OutboxStatus]: pending | inFlight | failed | conflict | blockedAuth | done.
  TextColumn get status => text()();

  TextColumn get lastError => text().nullable()();

  /// When the intent was captured on this device. Forensic only — server timestamps
  /// are authoritative.
  DateTimeColumn get createdAt => dateTime()();

  /// When the entry was handed to the transport. Used by crash recovery to reclaim
  /// entries that were in flight when the app died.
  DateTimeColumn get inFlightSince => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {mutationId};
}
