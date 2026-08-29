/// The local expense read model.
///
/// This is **not** a mirror of the Postgres tables, and the difference is deliberate.
/// Postgres holds the whole document and decides per caller how much of it to hand over;
/// this database holds only what one particular user was entitled to receive. The two
/// schemas are therefore siblings, not copies, and the places they diverge are the
/// security-relevant places.
///
/// ## Why a scoped header is a different thing from a complete one
///
///     Invoice          ₹58,000
///       Crystal Canopy ₹25,000
///       Hotel Krishna  ₹33,000
///
/// A Crystal Canopy manager may know that this is a shared bill and that their share is
/// ₹25,000. They may **not** learn ₹33,000 — and ₹58,000 − ₹25,000 *is* ₹33,000. So the
/// header total is not a field to hide in the interface; on a scoped record it is a value
/// this device must never hold at all.
///
/// The model says so in the schema rather than in a convention:
///
/// | Column | Complete | Scoped |
/// |---|---|---|
/// | `visibility` | `complete` | `scoped` |
/// | `documentTotalMinor` | the real total | **null, by check constraint** |
/// | `visibleAmountMinor` | the real total | the sum of the lines this user may see |
/// | `isShared` | spans >1 unit | spans >1 unit |
///
/// `documentTotalMinor` is nullable *and* constrained: SQLite itself refuses a scoped row
/// that carries a total. A future writer cannot reintroduce the leak by forgetting, and a
/// reader cannot mistake ₹25,000 for the invoice, because the two live in differently
/// named columns and the honest one is null.
///
/// Allocation lines and period contributions are stored **only where visible**. A scoped
/// device holds no row at all for the other property's share, so there is nothing to hide
/// and nothing to leak — including through a raw SQLite dump.
///
/// ## What else differs from Postgres, and why
///
/// * `txnNumber` is nullable here for a second reason: locally created expenses have no
///   number until the server issues one. In Postgres it is nullable only between the
///   insert and the allocation in the same transaction.
/// * There is no `expenses.total_amount_minor NOT NULL`. See above.
/// * `pendingMutationId` exists only on the client: it links a row to the queued intent
///   that will deliver it, so sync state is derived from the outbox rather than
///   duplicated into a column that could disagree with it.
/// * Attachments carry staging columns (`localPath`, `uploadState`, `attempt…`) that have
///   no server counterpart, because staging is a client concern by definition.
/// * The deferred `SUM(lines) = total` constraint is **not** reproduced. It cannot be:
///   on a scoped record the lines deliberately do not sum to the document. The invariant
///   that does hold locally — `SUM(visible lines) = visibleAmountMinor` — is asserted by
///   the repository and by tests, and by the server for the real one.
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/master_tables.dart';

/// How much of a document this device was given.
///
/// Stored as text rather than an int so a raw database dump reads as what it is.
enum ExpenseVisibility {
  /// Every line is present, and [Expenses.documentTotalMinor] is the real invoice total.
  complete,

  /// Lines belonging to units outside this user's scope were withheld by the server and
  /// are absent here. The document total is unknown to this device, and null.
  scoped,
}

/// The expense document, as this user is entitled to see it.
@DataClassName('ExpenseRow')
class Expenses extends Table {
  /// Client-generated UUID v7, assigned before the server ever sees the row (D-008).
  /// This is the identity offline, and it never changes.
  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// `KI-EXP-26-27-000001`, issued by the server after it accepts the write.
  ///
  /// **Null until then, and never fabricated locally.** Two devices offline for a week
  /// would both invent `000042`. The interface shows a pending state instead.
  TextColumn get txnNumber => text().nullable()();
  IntColumn get financialYear => integer().nullable()();

  TextColumn get businessDate => text()();
  TextColumn get businessDateSource =>
      text().withDefault(const Constant('derived'))();

  TextColumn get accountingPeriodStart => text().nullable()();
  TextColumn get accountingPeriodEnd => text().nullable()();

  // ── Visibility ───────────────────────────────────────────────────────────
  /// `complete` | `scoped`. See the library comment; this is the security model.
  TextColumn get visibility => text().withDefault(const Constant('complete'))();

  /// The real invoice total — **only** on a complete record. Null on a scoped one, by
  /// check constraint, because it would give away the other property's share.
  IntColumn get documentTotalMinor => integer().nullable()();

  /// What the lines this device holds add up to. On a complete record this equals
  /// [documentTotalMinor]; on a scoped one it is this user's share and is never
  /// presented as the invoice.
  IntColumn get visibleAmountMinor => integer()();

  /// Whether the document charges more than one business unit. Knowing that a bill is
  /// shared is authorised; knowing the other share is not.
  BoolColumn get isShared => boolean().withDefault(const Constant(false))();

  // ── Document fields ──────────────────────────────────────────────────────
  TextColumn get vendorId => text().nullable()();
  TextColumn get paymentStatus =>
      text().withDefault(const Constant('unpaid'))();
  TextColumn get paymentDate => text().nullable()();
  TextColumn get paymentMethodId => text().nullable()();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// Informational only (D-018). Never enters a calculation.
  IntColumn get taxAmountMinor => integer().nullable()();

  TextColumn get createdBy => text()();
  DateTimeColumn get capturedAt => dateTime()();

  DateTimeColumn get voidedAt => dateTime().nullable()();
  TextColumn get voidedBy => text().nullable()();
  TextColumn get voidReason => text().nullable()();

  // ── Sync ─────────────────────────────────────────────────────────────────
  /// The queued intent that will deliver this row, if one is outstanding.
  ///
  /// Sync state is *derived* from the outbox through this link rather than copied into a
  /// column of its own, so the two can never disagree about whether something has been
  /// sent. Cleared in the same transaction that reconciles the server's answer.
  TextColumn get pendingMutationId => text().nullable()();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    // The security model, enforced by SQLite rather than by discipline. A scoped record
    // physically cannot carry the document total.
    "CHECK ((visibility = 'complete' AND document_total_minor IS NOT NULL) "
        "OR (visibility = 'scoped' AND document_total_minor IS NULL))",
    "CHECK (visibility IN ('complete','scoped'))",
    'CHECK (visible_amount_minor > 0)',
    'CHECK (document_total_minor IS NULL OR document_total_minor > 0)',
    "CHECK (payment_status IN ('unpaid','paid'))",
    // Paid states when and by what means; unpaid states neither (spec §5.4).
    "CHECK ((payment_status = 'paid' AND payment_date IS NOT NULL "
        'AND payment_method_id IS NOT NULL) '
        "OR (payment_status = 'unpaid' AND payment_date IS NULL "
        'AND payment_method_id IS NULL))',
    // A void always states why (spec §14).
    'CHECK (voided_at IS NULL OR (voided_by IS NOT NULL '
        "AND length(trim(coalesce(void_reason,''))) > 0))",
    // Issued together or not at all.
    'CHECK ((txn_number IS NULL) = (financial_year IS NULL))',
  ];
}

/// One allocation line, present only if this user may see it.
@DataClassName('ExpenseAllocationRow')
class ExpenseAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get expenseId =>
      text().references(Expenses, #id, onDelete: KeyAction.cascade)();

  TextColumn get businessUnitId =>
      text().references(BusinessUnits, #id, onDelete: KeyAction.restrict)();
  TextColumn get departmentId => text()();
  TextColumn get sectionId => text()();

  /// Deliberately **not** a foreign key to `expense_categories`.
  ///
  /// The full hierarchy is a per-user cache, and a category can legitimately be absent
  /// from it — a scope purge (D-048) removes the masters of a revoked unit while an
  /// expense line that was already synced remains as history. A real foreign key would
  /// make the purge impossible or the history deletable, and both are worse than a soft
  /// pointer. The server holds the real key; this is the same reasoning as D-049.
  TextColumn get categoryId => text()();

  IntColumn get amountMinor => integer()();

  /// What the category was called when this was recorded (D-035). Reports show the
  /// current name; the document and the audit trail can show what was on screen.
  TextColumn get categoryLabel => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (amount_minor > 0)'];
}

/// One accounting period's share of one allocation line.
///
/// Always at least one per line (D-060). Reporting reads these and never the line
/// amount, so a split cannot be counted twice and an unsplit line cannot be missed.
@DataClassName('ExpensePeriodAllocationRow')
class ExpensePeriodAllocations extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get expenseId =>
      text().references(Expenses, #id, onDelete: KeyAction.cascade)();
  TextColumn get allocationId =>
      text().references(ExpenseAllocations, #id, onDelete: KeyAction.cascade)();
  TextColumn get businessUnitId => text()();

  TextColumn get accountingPeriodStart => text()();
  TextColumn get accountingPeriodEnd => text()();
  IntColumn get amountMinor => integer()();

  /// Computed once and stored, never re-derived at read time (D-019).
  TextColumn get pnlDate => text()();
  TextColumn get pnlPeriodKey => text()();

  /// Whether the default rule produced this, or a person chose it. Drives the
  /// `expense.allocate_periods` capability check and what the audit trail says.
  BoolColumn get isDerived => boolean().withDefault(const Constant(true))();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (amount_minor > 0)',
    'CHECK (accounting_period_start <= accounting_period_end)',
    'CHECK (pnl_date = accounting_period_end)',
    "CHECK (pnl_period_key = substr(pnl_date, 1, 7))",
  ];
}

/// Where an attachment's bytes are, on this device and on the server.
///
/// The staging columns have no server counterpart, because staging is a client concern:
/// a photo is copied into app-private storage before the expense is even saved, and the
/// upload happens afterwards, out of band, without the financial record waiting for it.
@DataClassName('ExpenseAttachmentRow')
class ExpenseAttachments extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get expenseId =>
      text().references(Expenses, #id, onDelete: KeyAction.cascade)();

  TextColumn get fileName => text()();
  TextColumn get contentType => text()();
  IntColumn get byteSize => integer()();

  /// SHA-256 of the staged bytes, computed before upload and compared afterwards.
  TextColumn get contentHash => text()();

  /// The app-private staging copy. Never a gallery or Downloads path: those can be
  /// moved, renamed or revoked by the OS between capture and upload.
  TextColumn get localPath => text().nullable()();

  /// `pending` | `uploaded` | `stagingReclaimed` | `failed`.
  TextColumn get uploadState => text().withDefault(const Constant('pending'))();
  TextColumn get storagePath => text().nullable()();

  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  DateTimeColumn get uploadedAt => dateTime().nullable()();

  /// When the verified staging copy becomes eligible for reclamation — seven days after
  /// the server confirmed *and* the hash matched (AttachmentPolicy.stagingRetention).
  DateTimeColumn get reclaimableAfter => dateTime().nullable()();

  TextColumn get uploadedBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (byte_size > 0)',
    "CHECK (upload_state IN ('pending','uploaded','stagingReclaimed','failed'))",
    // Confirmed means the server has it *and* the bytes matched.
    "CHECK (upload_state <> 'uploaded' OR (storage_path IS NOT NULL "
        'AND uploaded_at IS NOT NULL))',
  ];
}
