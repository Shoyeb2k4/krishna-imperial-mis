/// An in-memory snapshot of the master hierarchy.
///
/// The master set is small — a handful of units, departments, sections and categories —
/// so the whole graph is loaded once and reasoned over synchronously. That is what lets
/// [MasterHierarchyView] be a plain synchronous interface, which in turn lets the
/// validator be pure and exhaustively testable.
///
/// Lookups are **typed by level**: a department id passed where a section is expected
/// resolves to null rather than quietly matching. A single flat map would make
/// "section belongs to the wrong level" invisible, which is precisely the class of
/// mistake this file exists to catch.
library;

import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/masters/master_reference.dart';

final class MasterGraph implements MasterHierarchyView {
  MasterGraph({
    required Iterable<MasterNode> businessUnits,
    required Iterable<MasterNode> departments,
    required Iterable<MasterNode> sections,
    required Iterable<MasterNode> expenseCategories,
    Iterable<MasterNode> revenueCategories = const [],
  }) : _businessUnits = {for (final n in businessUnits) n.id: n},
       _departments = {for (final n in departments) n.id: n},
       _sections = {for (final n in sections) n.id: n},
       _expenseCategories = {for (final n in expenseCategories) n.id: n},
       _revenueCategories = {for (final n in revenueCategories) n.id: n};

  static MasterGraph empty() => MasterGraph(
    businessUnits: const [],
    departments: const [],
    sections: const [],
    expenseCategories: const [],
  );

  final Map<String, MasterNode> _businessUnits;
  final Map<String, MasterNode> _departments;
  final Map<String, MasterNode> _sections;
  final Map<String, MasterNode> _expenseCategories;
  final Map<String, MasterNode> _revenueCategories;

  @override
  MasterNode? businessUnit(String id) => _businessUnits[id];
  @override
  MasterNode? department(String id) => _departments[id];
  @override
  MasterNode? section(String id) => _sections[id];
  @override
  MasterNode? expenseCategory(String id) => _expenseCategories[id];

  MasterNode? revenueCategory(String id) => _revenueCategories[id];

  /// Children of a node, optionally including archived ones.
  ///
  /// Pickers pass `includeArchived: false` so an archived master is never offered for a
  /// new entry; administration screens pass true so it can still be seen and reopened.
  List<MasterNode> departmentsOf(
    String businessUnitId, {
    bool includeArchived = false,
  }) => _childrenOf(_departments, businessUnitId, includeArchived);

  List<MasterNode> sectionsOf(
    String departmentId, {
    bool includeArchived = false,
  }) => _childrenOf(_sections, departmentId, includeArchived);

  List<MasterNode> categoriesOf(
    String sectionId, {
    bool includeArchived = false,
  }) => _childrenOf(_expenseCategories, sectionId, includeArchived);

  List<MasterNode> revenueCategoriesOf(
    String businessUnitId, {
    bool includeArchived = false,
  }) => _childrenOf(_revenueCategories, businessUnitId, includeArchived);

  List<MasterNode> businessUnits({bool includeArchived = false}) => [
    for (final n in _businessUnits.values)
      if (includeArchived || !n.isArchived) n,
  ]..sort((a, b) => a.code.compareTo(b.code));

  /// Live children directly beneath a node, across every level it can parent.
  ///
  /// Drives [ArchivePolicy]: archiving a section while a live category still hangs off
  /// it would leave the category orphaned in every picker.
  int activeChildCount(String id) =>
      _countActive(_departments, id) +
      _countActive(_sections, id) +
      _countActive(_expenseCategories, id) +
      _countActive(_revenueCategories, id);

  /// A reference suitable for stamping onto a transaction: stable id, immutable code,
  /// and the label as it reads *now* (master spec §12).
  MasterReference? referenceTo(String id) {
    final node =
        _expenseCategories[id] ??
        _revenueCategories[id] ??
        _sections[id] ??
        _departments[id] ??
        _businessUnits[id];
    return node == null
        ? null
        : MasterReference(
            id: node.id,
            code: node.code,
            labelSnapshot: node.name,
          );
  }

  /// Validates an allocation line's classification against this snapshot.
  HierarchyValidation validate(
    HierarchyPath path, {
    required bool forNewEntry,
  }) => HierarchyValidator.validate(path, this, forNewEntry: forNewEntry);

  /// The full chain above a category, for pre-filling the entry form.
  HierarchyPath? pathForCategory(String categoryId) =>
      HierarchyValidator.pathForCategory(categoryId, this);

  static List<MasterNode> _childrenOf(
    Map<String, MasterNode> pool,
    String parentId,
    bool includeArchived,
  ) =>
      [
        for (final n in pool.values)
          if (n.parentId == parentId && (includeArchived || !n.isArchived)) n,
      ]..sort((a, b) {
        final byOrder = a.code.compareTo(b.code);
        return byOrder;
      });

  static int _countActive(Map<String, MasterNode> pool, String parentId) =>
      pool.values.where((n) => n.parentId == parentId && !n.isArchived).length;
}
