/// Master data and period locks, as local tables.
///
/// These mirror `docs/DATABASE_SCHEMA.md` §3 and §7 by name, so the local schema and
/// Postgres stay legible as one design rather than two dialects that drift apart.
///
/// Two things are enforced here, in the database, rather than left to the layers above:
///
/// * **Hierarchy** — every child names its parent through a real foreign key, with
///   `PRAGMA foreign_keys = ON`. A section physically cannot hang off a department that
///   does not exist. The [HierarchyValidator] then covers what foreign keys cannot: that
///   the *combination* on an allocation line is internally consistent.
/// * **No deletion** — masters carry `archivedAt`. Nothing in the application deletes a
///   master row, and referencing rows use `ON DELETE RESTRICT` so history can never be
///   orphaned (master spec §12, D-006).
library;

import 'package:drift/drift.dart';

/// Columns shared by every master: identity, an immutable code, an editable name,
/// ordering, and archive rather than deletion.
mixin MasterColumns on Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// Immutable once created. History and capability grants key on it, so the repository
  /// offers no path that changes it — re-purposing means archive and create anew.
  TextColumn get code => text()();

  /// Editable, for a rename that preserves meaning. Every change is audited, and
  /// transactions keep a snapshot of what it said when they were recorded.
  TextColumn get name => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();
}

@DataClassName('BusinessUnitRow')
class BusinessUnits extends Table with MasterColumns {
  /// `restaurant` | `hotel` | `other`
  TextColumn get kind => text()();

  /// IANA zone for this property. Drives business-date derivation (D-019).
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Kolkata'))();

  /// `HH:mm`. Changing it affects future derivations only; persisted business dates on
  /// existing rows are never restated.
  TextColumn get businessDayCutoff =>
      text().withDefault(const Constant('05:00'))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {orgId, code},
  ];
}

@DataClassName('DepartmentRow')
class Departments extends Table with MasterColumns {
  TextColumn get businessUnitId =>
      text().references(BusinessUnits, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {businessUnitId, code},
  ];
}

@DataClassName('SectionRow')
class Sections extends Table with MasterColumns {
  TextColumn get departmentId =>
      text().references(Departments, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {departmentId, code},
  ];
}

@DataClassName('ExpenseCategoryRow')
class ExpenseCategories extends Table with MasterColumns {
  TextColumn get sectionId =>
      text().references(Sections, #id, onDelete: KeyAction.restrict)();

  /// `operating` | `payroll` | `utility` | `other`
  TextColumn get nature => text().withDefault(const Constant('operating'))();

  /// A hint for the entry screen — electricity is usually split between properties.
  /// Never a rule: the user always decides the actual allocation.
  BoolColumn get isSharedByDefault =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {sectionId, code},
  ];
}

@DataClassName('RevenueCategoryRow')
class RevenueCategories extends Table with MasterColumns {
  TextColumn get businessUnitId =>
      text().references(BusinessUnits, #id, onDelete: KeyAction.restrict)();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {businessUnitId, code},
  ];
}

// NOTE: no tax-rate column here. Tax is date-effective per category and lives in its own
// table (D-017), so a rate change next year cannot restate last year's Net Sales.

@DataClassName('VendorRow')
class Vendors extends Table with MasterColumns {
  TextColumn get gstin => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get defaultCategoryId => text().nullable().references(
    ExpenseCategories,
    #id,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {orgId, code},
  ];
}

@DataClassName('PaymentMethodRow')
class PaymentMethods extends Table with MasterColumns {
  BoolColumn get requiresReference =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {orgId, code},
  ];
}

/// A lock over one `YYYY-MM` period, for one business unit or for all of them.
///
/// Uniqueness across the nullable `businessUnitId` is enforced by an explicit index in
/// the migration, because SQLite treats NULLs as distinct and would otherwise allow two
/// org-wide locks for the same period.
@DataClassName('PeriodLockRow')
class PeriodLocks extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();

  /// Null means every business unit.
  TextColumn get businessUnitId => text().nullable().references(
    BusinessUnits,
    #id,
    onDelete: KeyAction.restrict,
  )();

  TextColumn get periodKey => text()(); // 'YYYY-MM'
  TextColumn get state => text()(); // 'open' | 'closed'

  TextColumn get closedBy => text().nullable()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get reopenedBy => text().nullable()();
  DateTimeColumn get reopenedAt => dateTime().nullable()();
  TextColumn get reopenReason => text().nullable()();

  IntColumn get rowVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Append-only history of closes and reopens.
///
/// A period may close and reopen repeatedly; each event stands on its own record with
/// its actor, timestamp and — for a reopen — its mandatory reason (master spec §13.4).
/// Nothing in the application updates or deletes a row here.
@DataClassName('PeriodLockEventRow')
class PeriodLockEvents extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get periodLockId =>
      text().references(PeriodLocks, #id, onDelete: KeyAction.restrict)();

  /// `close` | `reopen`
  TextColumn get action => text()();

  /// Mandatory for a reopen. Enforced by the repository, which refuses an empty one.
  TextColumn get reason => text().nullable()();

  TextColumn get actorId => text()();
  DateTimeColumn get occurredAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
