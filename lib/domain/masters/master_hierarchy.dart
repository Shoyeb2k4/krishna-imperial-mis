/// Master-data hierarchy integrity.
///
/// ```
/// Business Unit → Department → Section → Expense Category
/// ```
///
/// Structurally impossible relationships must not exist. A Section belonging to Hotel
/// Krishna Imperial must never be selectable under a Crystal Canopy Department, and an
/// expense allocation line must never claim a category that does not sit under its
/// stated section.
///
/// The rule is written once, here, and enforced in three places for three different
/// reasons: **the database** is authoritative and stops a bad row existing at all; the
/// **domain/repository layer** stops a bad write being attempted and gives a usable
/// error; the **UI** never offers an impossible choice in the first place. The first is
/// the guarantee; the other two are courtesy.
library;

import 'package:meta/meta.dart';

/// One node of the hierarchy, as the validator needs to see it.
@immutable
final class MasterNode {
  const MasterNode({
    required this.id,
    required this.code,
    required this.name,
    this.parentId,
    this.archivedAt,
  });

  final String id;

  /// Immutable for the life of the record. History keys on it, so it is never edited —
  /// re-purposing means archive and create anew (master spec §12).
  final String code;

  /// Editable, for a rename that preserves meaning.
  final String name;

  /// Business unit for a department, department for a section, section for a category.
  /// Null for a business unit.
  final String? parentId;

  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;
}

/// Read access to the master graph. Implemented over the local database, and mirrored by
/// the equivalent server-side check.
abstract interface class MasterHierarchyView {
  MasterNode? businessUnit(String id);
  MasterNode? department(String id);
  MasterNode? section(String id);
  MasterNode? expenseCategory(String id);
}

enum HierarchyViolation {
  unknownBusinessUnit,
  unknownDepartment,
  unknownSection,
  unknownCategory,

  /// The department exists but belongs to a different business unit.
  departmentNotInBusinessUnit,

  /// The section exists but belongs to a different department.
  sectionNotInDepartment,

  /// The category exists but belongs to a different section.
  categoryNotInSection,

  archivedBusinessUnit,
  archivedDepartment,
  archivedSection,
  archivedCategory;

  String get message => switch (this) {
    HierarchyViolation.unknownBusinessUnit =>
      'That business unit does not exist.',
    HierarchyViolation.unknownDepartment => 'That department does not exist.',
    HierarchyViolation.unknownSection => 'That section does not exist.',
    HierarchyViolation.unknownCategory => 'That category does not exist.',
    HierarchyViolation.departmentNotInBusinessUnit =>
      'That department does not belong to the selected business unit.',
    HierarchyViolation.sectionNotInDepartment =>
      'That section does not belong to the selected department.',
    HierarchyViolation.categoryNotInSection =>
      'That category does not belong to the selected section.',
    HierarchyViolation.archivedBusinessUnit =>
      'That business unit has been archived and cannot be used for new entries.',
    HierarchyViolation.archivedDepartment =>
      'That department has been archived and cannot be used for new entries.',
    HierarchyViolation.archivedSection =>
      'That section has been archived and cannot be used for new entries.',
    HierarchyViolation.archivedCategory =>
      'That category has been archived and cannot be used for new entries.',
  };
}

/// The classification carried by one expense allocation line.
@immutable
final class HierarchyPath {
  const HierarchyPath({
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
  });

  final String businessUnitId;
  final String departmentId;
  final String sectionId;
  final String categoryId;

  @override
  bool operator ==(Object other) =>
      other is HierarchyPath &&
      other.businessUnitId == businessUnitId &&
      other.departmentId == departmentId &&
      other.sectionId == sectionId &&
      other.categoryId == categoryId;

  @override
  int get hashCode =>
      Object.hash(businessUnitId, departmentId, sectionId, categoryId);

  @override
  String toString() =>
      'HierarchyPath($businessUnitId/$departmentId/$sectionId/$categoryId)';
}

@immutable
final class HierarchyValidation {
  const HierarchyValidation(this.violations);

  static const HierarchyValidation valid = HierarchyValidation([]);

  final List<HierarchyViolation> violations;

  bool get isValid => violations.isEmpty;

  String get message => violations.map((v) => v.message).join(' ');

  void enforce() {
    if (!isValid) throw HierarchyIntegrityFailure(violations);
  }

  @override
  String toString() => isValid
      ? 'HierarchyValidation.valid'
      : 'HierarchyValidation($violations)';
}

class HierarchyIntegrityFailure implements Exception {
  const HierarchyIntegrityFailure(this.violations);
  final List<HierarchyViolation> violations;

  @override
  String toString() =>
      'HierarchyIntegrityFailure(${violations.map((v) => v.name).join(', ')})';
}

abstract final class HierarchyValidator {
  /// Validates a full path against the master graph.
  ///
  /// [forNewEntry] distinguishes the two cases that must behave differently: a **new**
  /// entry may not use an archived master, while an **existing** historical transaction
  /// keeps its references intact forever — archiving a category must never retroactively
  /// invalidate the ₹1,50,181 of Kirana already booked against it.
  static HierarchyValidation validate(
    HierarchyPath path,
    MasterHierarchyView view, {
    required bool forNewEntry,
  }) {
    final violations = <HierarchyViolation>[];

    final unit = view.businessUnit(path.businessUnitId);
    final department = view.department(path.departmentId);
    final section = view.section(path.sectionId);
    final category = view.expenseCategory(path.categoryId);

    if (unit == null) {
      violations.add(HierarchyViolation.unknownBusinessUnit);
    }
    if (department == null) {
      violations.add(HierarchyViolation.unknownDepartment);
    }
    if (section == null) {
      violations.add(HierarchyViolation.unknownSection);
    }
    if (category == null) {
      violations.add(HierarchyViolation.unknownCategory);
    }

    // Only check parentage for links whose endpoints both exist; otherwise the report
    // would be a cascade of noise from one typo.
    if (department != null && unit != null && department.parentId != unit.id) {
      violations.add(HierarchyViolation.departmentNotInBusinessUnit);
    }
    if (section != null &&
        department != null &&
        section.parentId != department.id) {
      violations.add(HierarchyViolation.sectionNotInDepartment);
    }
    if (category != null &&
        section != null &&
        category.parentId != section.id) {
      violations.add(HierarchyViolation.categoryNotInSection);
    }

    if (forNewEntry) {
      if (unit?.isArchived ?? false) {
        violations.add(HierarchyViolation.archivedBusinessUnit);
      }
      if (department?.isArchived ?? false) {
        violations.add(HierarchyViolation.archivedDepartment);
      }
      if (section?.isArchived ?? false) {
        violations.add(HierarchyViolation.archivedSection);
      }
      if (category?.isArchived ?? false) {
        violations.add(HierarchyViolation.archivedCategory);
      }
    }

    return violations.isEmpty
        ? HierarchyValidation.valid
        : HierarchyValidation(List.unmodifiable(violations));
  }

  /// Derives the full path upward from a category, so the UI can pre-fill the chain and
  /// an importer never has to guess the parents.
  static HierarchyPath? pathForCategory(
    String categoryId,
    MasterHierarchyView view,
  ) {
    final category = view.expenseCategory(categoryId);
    final section = category == null
        ? null
        : view.section(category.parentId ?? '');
    final department = section == null
        ? null
        : view.department(section.parentId ?? '');
    final unit = department == null
        ? null
        : view.businessUnit(department.parentId ?? '');
    if (category == null ||
        section == null ||
        department == null ||
        unit == null) {
      return null;
    }
    return HierarchyPath(
      businessUnitId: unit.id,
      departmentId: department.id,
      sectionId: section.id,
      categoryId: category.id,
    );
  }
}
