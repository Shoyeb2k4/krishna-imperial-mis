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

  /// Who queued this intent.
  ///
  /// A shared Windows workstation in a hotel back office will see several people sign
  /// in and out of one installation. Without this column the queue is anonymous, and
  /// one user's device could push work another user created under authority they no
  /// longer hold — or never held. Sync only ever sends entries belonging to the signed-in
  /// user, and one user's queued work is never shown to, retried by or attributed to
  /// another (D-050).
  ///
  /// Nullable only for rows written before this column existed. Those are treated as
  /// unattributed and are never sent by anyone; they are surfaced for a human instead of
  /// being guessed at or quietly discarded.
  TextColumn get actorUserId => text().nullable()();

  TextColumn get entityType => text()();
  TextColumn get entityId => text()();

  /// `create` | `update` | `void_` | `archive`
  ///
  /// A business-date correction is an `update`: one document, one write path, one
  /// contract (D-127).
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
