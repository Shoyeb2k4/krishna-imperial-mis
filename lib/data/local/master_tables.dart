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

  /// Optional. Pre-selects a category when this vendor is chosen during entry.
  ///
  /// Deliberately **not** a foreign key (D-049). A vendor is an organisation-global
  /// master; these two columns are operational conveniences, not ownership, visibility
  /// or authorisation. A foreign key would assert "the target must exist in this
  /// database", and on a per-user cache that is simply false: a manager scoped to one
  /// property legitimately holds vendors whose usual category belongs to the other. It
  /// also made the revoked-scope purge impossible without rewriting canonical vendor
  /// data, which D-049 §2 forbids.
  ///
  /// A dangling pointer here is therefore expected and harmless. It is resolved at the
  /// point of use by `Vendor.effectiveDefaultBusinessUnitId`, which filters through the
  /// caller's current authoritative scope and owns nothing.
  TextColumn get defaultCategoryId => text().nullable()();

  /// Optional. Pre-selects the property when this vendor is chosen during entry. Soft
  /// pointer, for the reasons above.
  TextColumn get defaultBusinessUnitId => text().nullable()();
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

/// Date-effective tax configuration for revenue categories (D-017).
///
/// A rate change is a **new row for a new period**, never an edit to the old one, so a
/// rate set next April cannot restate last year's Net Sales. The period is half-open —
/// `[effective_from, effective_to)` — so a rule ending the day another starts is not an
/// overlap and exactly one rule applies to any date.
///
/// Postgres enforces non-overlap with an exclusion constraint over a `daterange`. SQLite
/// has none, so the repository enforces the same rule inside a transaction and the
/// database keeps a unique index on `(category, effective_from)` as a backstop against
/// the most obvious duplicate.
@DataClassName('RevenueTaxRateRow')
class RevenueTaxRates extends Table {
  TextColumn get id => text()();
  TextColumn get orgId => text()();
  TextColumn get revenueCategoryId =>
      text().references(RevenueCategories, #id, onDelete: KeyAction.restrict)();

  /// Basis points: 1% = 100. Integers only — a rate never arrives as a float.
  IntColumn get rateBasisPoints => integer()();

  /// `inclusive` | `exclusive` | `none`
  TextColumn get treatment => text()();

  /// `YYYY-MM-DD`, inclusive lower bound.
  TextColumn get effectiveFrom => text()();

  /// `YYYY-MM-DD`, **exclusive** upper bound. Null means still in force.
  TextColumn get effectiveTo => text().nullable()();

  /// Which figure the operator types under this rule: `inclusive_total` | `pre_tax`
  /// (D-080, D-097).
  ///
  /// **Nullable, and deliberately not backfilled.** Rules cached before v11 predate the
  /// concept and carry no authoritative answer; giving them one would be inventing a
  /// business fact about whether a recorded figure includes tax. A rule with no basis is
  /// *visibly incomplete* and the resolver refuses it (`RevenueTaxIncompleteRule`), which
  /// is the honest outcome.
  TextColumn get inputBasis => text().nullable()();

  // ── Bounded conditional discriminators (D-079) ───────────────────────────
  // Null means "this rule does not depend on that dimension" — which means it matches
  // every value of it, so a null and a specific rule over the same dates collide rather
  // than the specific one winning (D-094). None is backfilled by the v11 migration.
  //
  // Soft pointers: the bands and subtypes they name are reference cache that a scope
  // revocation may purge, and a rule row must not block that purge.
  TextColumn get valueBandId => text().nullable()();
  TextColumn get supplySubtypeId => text().nullable()();
  TextColumn get premisesStatusCode => text().nullable()();

  TextColumn get note => text().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get rowVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (input_basis IS NULL OR input_basis IN ('inclusive_total','pre_tax'))",
  ];

  // No plain uniqueKeys here. A unique index over (category, effective_from) would also
  // count archived rows, so archiving a rule would permanently block its period from
  // being reused — which is exactly what archiving is supposed to allow. The backstop is
  // a *partial* unique index over live rows only, created in the migration.
}
