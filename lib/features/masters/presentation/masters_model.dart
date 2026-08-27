/// View-model for the master-management surfaces.
///
/// Flattens the hierarchy into something both platforms can render — a tree on Windows,
/// a drill-down on Android — without either of them re-deriving parentage.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:meta/meta.dart';

/// Which rung of the hierarchy a record sits on.
enum MasterLevel {
  businessUnit('Business unit', 'Business units'),
  department('Department', 'Departments'),
  section('Section', 'Sections'),
  expenseCategory('Expense category', 'Expense categories'),
  revenueCategory('Revenue category', 'Revenue categories');

  const MasterLevel(this.label, this.plural);

  final String label;
  final String plural;

  /// The rung beneath this one in the expense hierarchy, if any.
  MasterLevel? get child => switch (this) {
    MasterLevel.businessUnit => MasterLevel.department,
    MasterLevel.department => MasterLevel.section,
    MasterLevel.section => MasterLevel.expenseCategory,
    MasterLevel.expenseCategory => null,
    MasterLevel.revenueCategory => null,
  };
}

/// One record, with the chain above it already resolved.
@immutable
final class MasterEntry {
  const MasterEntry({
    required this.level,
    required this.node,
    this.ancestors = const [],
  });

  final MasterLevel level;
  final MasterNode node;

  /// Outermost first: business unit, then department, then section.
  final List<MasterEntry> ancestors;

  /// `Crystal Canopy Rooftop › F&B / Kitchen › Food Production`
  String get ancestorPath => ancestors.map((a) => a.node.name).join(' › ');

  MasterEntry withAncestor(MasterEntry ancestor) => MasterEntry(
    level: level,
    node: node,
    ancestors: [...ancestors, ancestor],
  );

  @override
  bool operator ==(Object other) =>
      other is MasterEntry && other.node.id == node.id && other.level == level;

  @override
  int get hashCode => Object.hash(node.id, level);
}

/// The whole tree, pre-walked once per graph load.
@immutable
final class MasterTree {
  const MasterTree({required this.units, required this.childrenOf});

  /// Business units, in code order.
  final List<MasterEntry> units;

  /// Children keyed by parent node id, already carrying their ancestor chain.
  final Map<String, List<MasterEntry>> childrenOf;

  static MasterTree from(MasterGraph graph, {required bool includeArchived}) {
    final children = <String, List<MasterEntry>>{};

    final units = [
      for (final unit in graph.businessUnits(includeArchived: includeArchived))
        MasterEntry(level: MasterLevel.businessUnit, node: unit),
    ];

    for (final unit in units) {
      final departments = [
        for (final d in graph.departmentsOf(
          unit.node.id,
          includeArchived: includeArchived,
        ))
          MasterEntry(
            level: MasterLevel.department,
            node: d,
            ancestors: [unit],
          ),
      ];
      final revenue = [
        for (final r in graph.revenueCategoriesOf(
          unit.node.id,
          includeArchived: includeArchived,
        ))
          MasterEntry(
            level: MasterLevel.revenueCategory,
            node: r,
            ancestors: [unit],
          ),
      ];
      children[unit.node.id] = [...departments, ...revenue];

      for (final department in departments) {
        final sections = [
          for (final s in graph.sectionsOf(
            department.node.id,
            includeArchived: includeArchived,
          ))
            MasterEntry(
              level: MasterLevel.section,
              node: s,
              ancestors: [...department.ancestors, department],
            ),
        ];
        children[department.node.id] = sections;

        for (final section in sections) {
          children[section.node.id] = [
            for (final c in graph.categoriesOf(
              section.node.id,
              includeArchived: includeArchived,
            ))
              MasterEntry(
                level: MasterLevel.expenseCategory,
                node: c,
                ancestors: [...section.ancestors, section],
              ),
          ];
        }
      }
    }

    return MasterTree(units: units, childrenOf: children);
  }

  List<MasterEntry> children(String parentId) =>
      childrenOf[parentId] ?? const [];

  /// Every record in the tree, depth-first. Used by search.
  List<MasterEntry> get all => [
    for (final unit in units) ...[unit, ..._descend(unit)],
  ];

  List<MasterEntry> _descend(MasterEntry parent) => [
    for (final child in children(parent.node.id)) ...[
      child,
      ..._descend(child),
    ],
  ];

  /// Matches on name **and** code, because the code is what appears in exports and the
  /// owner may well search for it.
  List<MasterEntry> search(String term) {
    final needle = term.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return [
      for (final entry in all)
        if (entry.node.name.toLowerCase().contains(needle) ||
            entry.node.code.toLowerCase().contains(needle))
          entry,
    ];
  }
}

/// Whether archived records are shown. Off by default — the everyday view is live data.
final showArchivedMastersProvider = NotifierProvider<ShowArchivedMasters, bool>(
  ShowArchivedMasters.new,
);

class ShowArchivedMasters extends Notifier<bool> {
  @override
  bool build() => false;

  void set({required bool value}) => state = value;
  void toggle() => state = !state;
}

/// The current search term on the masters surface.
final masterSearchProvider = NotifierProvider<MasterSearchTerm, String>(
  MasterSearchTerm.new,
);

class MasterSearchTerm extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

/// The record selected in the Windows detail panel.
final selectedMasterProvider = NotifierProvider<SelectedMaster, MasterEntry?>(
  SelectedMaster.new,
);

class SelectedMaster extends Notifier<MasterEntry?> {
  @override
  MasterEntry? build() => null;

  void select(MasterEntry? entry) => state = entry;
}

/// Nodes expanded in the Windows tree.
final expandedMastersProvider = NotifierProvider<ExpandedMasters, Set<String>>(
  ExpandedMasters.new,
);

class ExpandedMasters extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
  }
}
