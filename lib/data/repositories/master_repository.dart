/// Master data reads and writes, with hierarchy integrity enforced on the way in.
///
/// Three layers guard the same rule for three different reasons (see
/// `master_hierarchy.dart`): foreign keys stop a bad row existing, this repository stops
/// a bad write being attempted and returns a usable error, and the UI never offers an
/// impossible choice. This file is the middle one — it is not the guarantee, and it does
/// not pretend to be.
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/masters/master_reference.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// Which master a generic operation applies to.
enum MasterKind {
  businessUnit,
  department,
  section,
  expenseCategory,
  revenueCategory,
}

/// Raised when a write would create a structurally impossible relationship or reuse a
/// code that is already taken.
class MasterWriteRefused implements Exception {
  const MasterWriteRefused(this.message);
  final String message;

  @override
  String toString() => 'MasterWriteRefused: $message';
}

class MasterRepository {
  MasterRepository(this._db);

  final AppDatabase _db;

  // ── Reads ─────────────────────────────────────────────────────────────────

  /// Loads the whole hierarchy as one snapshot.
  Future<MasterGraph> loadGraph() async {
    final results = await Future.wait([
      _db.select(_db.businessUnits).get(),
      _db.select(_db.departments).get(),
      _db.select(_db.sections).get(),
      _db.select(_db.expenseCategories).get(),
      _db.select(_db.revenueCategories).get(),
    ]);

    return MasterGraph(
      businessUnits: [
        for (final r in results[0] as List<BusinessUnitRow>)
          MasterNode(
            id: r.id,
            code: r.code,
            name: r.name,
            archivedAt: r.archivedAt,
          ),
      ],
      departments: [
        for (final r in results[1] as List<DepartmentRow>)
          MasterNode(
            id: r.id,
            code: r.code,
            name: r.name,
            parentId: r.businessUnitId,
            archivedAt: r.archivedAt,
          ),
      ],
      sections: [
        for (final r in results[2] as List<SectionRow>)
          MasterNode(
            id: r.id,
            code: r.code,
            name: r.name,
            parentId: r.departmentId,
            archivedAt: r.archivedAt,
          ),
      ],
      expenseCategories: [
        for (final r in results[3] as List<ExpenseCategoryRow>)
          MasterNode(
            id: r.id,
            code: r.code,
            name: r.name,
            parentId: r.sectionId,
            archivedAt: r.archivedAt,
          ),
      ],
      revenueCategories: [
        for (final r in results[4] as List<RevenueCategoryRow>)
          MasterNode(
            id: r.id,
            code: r.code,
            name: r.name,
            parentId: r.businessUnitId,
            archivedAt: r.archivedAt,
          ),
      ],
    );
  }

  /// Each cached property's business-date rules, keyed by business unit id.
  ///
  /// Phase 5 Slice 8: a relative report preset is resolved under every property's own
  /// timezone and cut-off (D-019). A property whose stored rules cannot be read is
  /// **absent** from the map rather than defaulted — the caller then refuses the preset for
  /// it instead of assuming the seeded `Asia/Kolkata` and 05:00.
  Future<Map<String, BusinessDayRule>> businessDayRules() async {
    final units = await _db.select(_db.businessUnits).get();
    return {
      for (final unit in units)
        unit.id: ?BusinessDayRule.tryParse(
          timeZoneId: unit.timezone,
          cutoff: unit.businessDayCutoff,
        ),
    };
  }

  /// Validates a classification against current masters.
  ///
  /// [forNewEntry] false keeps historical rows valid even when their masters have since
  /// been archived — archiving must never retroactively invalidate booked amounts.
  Future<HierarchyValidation> validatePath(
    HierarchyPath path, {
    required bool forNewEntry,
  }) async => (await loadGraph()).validate(path, forNewEntry: forNewEntry);

  // ── Writes ────────────────────────────────────────────────────────────────

  Future<void> createBusinessUnit({
    required String id,
    required String orgId,
    required String code,
    required String name,
    required String kind,
    required DateTime now,
    String timezone = 'Asia/Kolkata',
    String businessDayCutoff = '05:00',
    int sortOrder = 0,
  }) async {
    await _db
        .into(_db.businessUnits)
        .insert(
          BusinessUnitsCompanion.insert(
            id: id,
            orgId: orgId,
            code: code,
            name: name,
            kind: kind,
            timezone: Value(timezone),
            businessDayCutoff: Value(businessDayCutoff),
            sortOrder: Value(sortOrder),
            updatedAt: now,
          ),
        );
  }

  Future<void> createDepartment({
    required String id,
    required String orgId,
    required String businessUnitId,
    required String code,
    required String name,
    required DateTime now,
    int sortOrder = 0,
  }) async {
    await _requireActiveParent(MasterKind.businessUnit, businessUnitId);
    await _db
        .into(_db.departments)
        .insert(
          DepartmentsCompanion.insert(
            id: id,
            orgId: orgId,
            businessUnitId: businessUnitId,
            code: code,
            name: name,
            sortOrder: Value(sortOrder),
            updatedAt: now,
          ),
        );
  }

  Future<void> createSection({
    required String id,
    required String orgId,
    required String departmentId,
    required String code,
    required String name,
    required DateTime now,
    int sortOrder = 0,
  }) async {
    await _requireActiveParent(MasterKind.department, departmentId);
    await _db
        .into(_db.sections)
        .insert(
          SectionsCompanion.insert(
            id: id,
            orgId: orgId,
            departmentId: departmentId,
            code: code,
            name: name,
            sortOrder: Value(sortOrder),
            updatedAt: now,
          ),
        );
  }

  Future<void> createExpenseCategory({
    required String id,
    required String orgId,
    required String sectionId,
    required String code,
    required String name,
    required DateTime now,
    String nature = 'operating',
    bool isSharedByDefault = false,
    int sortOrder = 0,
  }) async {
    await _requireActiveParent(MasterKind.section, sectionId);
    await _db
        .into(_db.expenseCategories)
        .insert(
          ExpenseCategoriesCompanion.insert(
            id: id,
            orgId: orgId,
            sectionId: sectionId,
            code: code,
            name: name,
            nature: Value(nature),
            isSharedByDefault: Value(isSharedByDefault),
            sortOrder: Value(sortOrder),
            updatedAt: now,
          ),
        );
  }

  Future<void> createRevenueCategory({
    required String id,
    required String orgId,
    required String businessUnitId,
    required String code,
    required String name,
    required DateTime now,
    int sortOrder = 0,
  }) async {
    await _requireActiveParent(MasterKind.businessUnit, businessUnitId);
    await _db
        .into(_db.revenueCategories)
        .insert(
          RevenueCategoriesCompanion.insert(
            id: id,
            orgId: orgId,
            businessUnitId: businessUnitId,
            code: code,
            name: name,
            sortOrder: Value(sortOrder),
            updatedAt: now,
          ),
        );
  }

  /// Renames a master. The **code is never touched** — there is deliberately no method
  /// that changes it, because history and grants key on it.
  ///
  /// A rename that changes meaning (turning "Water" into "Diesel") is a policy breach no
  /// schema can detect. The system makes it survivable instead: transactions keep a
  /// snapshot of the label they were recorded under, and every rename is audited.
  Future<void> rename({
    required MasterKind kind,
    required String id,
    required String name,
    required DateTime now,
  }) async {
    if (name.trim().isEmpty) {
      throw const MasterWriteRefused('A name is required.');
    }
    final updated = await _updateRow(
      kind,
      id,
      (rowVersion) => {'name': name.trim(), 'row_version': rowVersion + 1},
      now,
    );
    if (!updated) throw MasterWriteRefused('That ${kind.name} does not exist.');
  }

  /// Archives a master. Never deletes.
  ///
  /// Returns the decision rather than throwing, so a UI can explain "archive the records
  /// underneath this one first" instead of showing an error.
  Future<ArchiveDecision> archive({
    required MasterKind kind,
    required String id,
    required DateTime now,
  }) async {
    final graph = await loadGraph();
    final node = _nodeIn(graph, kind, id);
    if (node == null) {
      throw MasterWriteRefused('That ${kind.name} does not exist.');
    }

    final decision = ArchivePolicy.evaluate(
      isArchived: node.isArchived,
      activeChildCount: graph.activeChildCount(id),
    );
    if (!decision.isAllowed) return decision;

    await _updateRow(
      kind,
      id,
      (rowVersion) => {
        'archived_at': now.toUtc().toIso8601String(),
        'row_version': rowVersion + 1,
      },
      now,
    );
    return decision;
  }

  /// Restores an archived master, so an archive made in error is recoverable.
  Future<void> unarchive({
    required MasterKind kind,
    required String id,
    required DateTime now,
  }) async {
    final updated = await _updateRow(
      kind,
      id,
      (rowVersion) => {'archived_at': null, 'row_version': rowVersion + 1},
      now,
    );
    if (!updated) throw MasterWriteRefused('That ${kind.name} does not exist.');
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _requireActiveParent(MasterKind kind, String id) async {
    final graph = await loadGraph();
    final parent = _nodeIn(graph, kind, id);
    if (parent == null) {
      throw MasterWriteRefused(
        'The selected ${_label(kind)} does not exist, so nothing can be created '
        'underneath it.',
      );
    }
    if (parent.isArchived) {
      throw MasterWriteRefused(
        'The selected ${_label(kind)} has been archived. Restore it first, or choose '
        'another.',
      );
    }
  }

  static MasterNode? _nodeIn(MasterGraph graph, MasterKind kind, String id) =>
      switch (kind) {
        MasterKind.businessUnit => graph.businessUnit(id),
        MasterKind.department => graph.department(id),
        MasterKind.section => graph.section(id),
        MasterKind.expenseCategory => graph.expenseCategory(id),
        MasterKind.revenueCategory => graph.revenueCategory(id),
      };

  static String _label(MasterKind kind) => switch (kind) {
    MasterKind.businessUnit => 'business unit',
    MasterKind.department => 'department',
    MasterKind.section => 'section',
    MasterKind.expenseCategory => 'expense category',
    MasterKind.revenueCategory => 'revenue category',
  };

  static String _table(MasterKind kind) => switch (kind) {
    MasterKind.businessUnit => 'business_units',
    MasterKind.department => 'departments',
    MasterKind.section => 'sections',
    MasterKind.expenseCategory => 'expense_categories',
    MasterKind.revenueCategory => 'revenue_categories',
  };

  /// Applies a field update by table name, bumping `row_version` and `updated_at`.
  ///
  /// Row version moves on every change so the same optimistic-concurrency rule that
  /// governs financial records governs masters too (D-021): archiving from a stale view
  /// is rejected by the server exactly like a stale void.
  Future<bool> _updateRow(
    MasterKind kind,
    String id,
    Map<String, Object?> Function(int rowVersion) fields,
    DateTime now,
  ) async {
    final table = _table(kind);
    final current = await _db
        .customSelect(
          'SELECT row_version FROM $table WHERE id = ?',
          variables: [Variable<String>(id)],
        )
        .getSingleOrNull();
    if (current == null) return false;

    final values = fields(current.read<int>('row_version'))
      ..['updated_at'] = now.toUtc().toIso8601String();

    final assignments = values.keys.map((k) => '$k = ?').join(', ');
    await _db.customUpdate(
      'UPDATE $table SET $assignments WHERE id = ?',
      variables: [
        for (final value in values.values)
          if (value == null)
            const Variable<String>(null)
          else if (value is int)
            Variable<int>(value)
          else
            Variable<String>(value as String),
        Variable<String>(id),
      ],
      updates: {},
    );
    return true;
  }
}
