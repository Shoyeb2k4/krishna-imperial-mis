/// Choosing where an expense is charged.
///
/// One control, four rungs, drilled through in order: property → department → section →
/// category. Presented as a single summary row that opens a sheet, because on a phone the
/// routine expense is "the same place as last time" and the fast path is one tap to
/// confirm rather than four dropdowns to re-open.
///
/// What it will not do:
///
/// * offer a property this user may not charge;
/// * offer an archived master for a new entry — archived stays valid for history and is
///   refused for anything new (D-035);
/// * keep a child selected after its parent changed. The cascade lives in [ExpenseDraft]
///   and this widget simply reports the change.
///
/// Everything comes from the local master cache, so the picker works with no network.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_draft.dart';

/// What the user picked, at whichever rung they picked it.
typedef ClassificationChange =
    void Function({
      String? businessUnitId,
      String? departmentId,
      String? sectionId,
      String? categoryId,
    });

class ClassificationRow extends StatelessWidget {
  const ClassificationRow({
    required this.line,
    required this.graph,
    required this.principal,
    required this.onChanged,
    super.key,
    this.enabled = true,
    this.lockedBusinessUnitId,
  });

  final AllocationDraft line;
  final MasterGraph graph;
  final Principal principal;
  final ClassificationChange onChanged;
  final bool enabled;

  /// When set, the property is fixed and only the rungs below it may be chosen. Used by
  /// the split editor for a user who may charge only one property.
  final String? lockedBusinessUnitId;

  /// `Crystal Canopy Rooftop › Kitchen › Food Production › Vegetables & Fruits`
  String get _summary {
    final parts = [
      graph.businessUnit(line.businessUnitId ?? '')?.name,
      graph.department(line.departmentId ?? '')?.name,
      graph.section(line.sectionId ?? '')?.name,
      graph.expenseCategory(line.categoryId ?? '')?.name,
    ].whereType<String>();
    return parts.isEmpty ? 'Choose where this is charged' : parts.join(' › ');
  }

  @override
  Widget build(BuildContext context) {
    final complete = line.isClassified;
    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      focusColor: AppColors.brassWash,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.allSmall,
          border: Border.all(
            color: complete ? AppColors.hairline : AppColors.hairlineStrong,
          ),
        ),
        child: Row(
          children: [
            Icon(
              complete ? Icons.account_tree_outlined : Icons.add_circle_outline,
              size: 18,
              color: complete ? AppColors.brass : AppColors.inkFaint,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CHARGED TO', style: AppTypography.overline),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _summary,
                    key: const Key('classification-summary'),
                    style: AppTypography.body.copyWith(
                      color: complete ? AppColors.ink : AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.inkFaint,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadius.large),
      ),
      builder: (sheetContext) => _ClassificationSheet(
        line: line,
        graph: graph,
        principal: principal,
        lockedBusinessUnitId: lockedBusinessUnitId,
        onChanged: onChanged,
      ),
    );
  }
}

/// The drill-down. Shows one rung at a time, with a breadcrumb back.
class _ClassificationSheet extends StatefulWidget {
  const _ClassificationSheet({
    required this.line,
    required this.graph,
    required this.principal,
    required this.onChanged,
    this.lockedBusinessUnitId,
  });

  final AllocationDraft line;
  final MasterGraph graph;
  final Principal principal;
  final ClassificationChange onChanged;
  final String? lockedBusinessUnitId;

  @override
  State<_ClassificationSheet> createState() => _ClassificationSheetState();
}

class _ClassificationSheetState extends State<_ClassificationSheet> {
  String? _unit;
  String? _department;
  String? _section;

  @override
  void initState() {
    super.initState();
    _unit = widget.lockedBusinessUnitId ?? widget.line.businessUnitId;
    _department = widget.line.departmentId;
    _section = widget.line.sectionId;
    // Only one property to choose from, and it is already chosen: start a rung in.
    final units = ExpenseDraft.selectableUnits(widget.graph, widget.principal);
    if (_unit == null && units.length == 1) _unit = units.single.id;
  }

  @override
  Widget build(BuildContext context) {
    final (title, nodes, onSelect) = _currentRung();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  if (_canGoBack)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20),
                      tooltip: 'Back',
                      onPressed: _goBack,
                    )
                  else
                    const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_breadcrumb.isNotEmpty)
                          Text(
                            _breadcrumb.toUpperCase(),
                            style: AppTypography.overline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text(title, style: AppTypography.subheading),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: nodes.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      child: Text(
                        'Nothing here yet. Ask an administrator to add one.',
                        style: AppTypography.bodyMuted,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: nodes.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: AppSpacing.lg),
                      itemBuilder: (context, index) {
                        final node = nodes[index];
                        return ListTile(
                          title: Text(node.name, style: AppTypography.body),
                          trailing: const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppColors.inkFaint,
                          ),
                          onTap: () => onSelect(node.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canGoBack =>
      _section != null ||
      _department != null ||
      (_unit != null && widget.lockedBusinessUnitId == null);

  void _goBack() => setState(() {
    if (_section != null) {
      _section = null;
    } else if (_department != null) {
      _department = null;
    } else {
      _unit = null;
    }
  });

  String get _breadcrumb => [
    widget.graph.businessUnit(_unit ?? '')?.name,
    widget.graph.department(_department ?? '')?.name,
    widget.graph.section(_section ?? '')?.name,
  ].whereType<String>().join(' › ');

  /// The rung being shown, its options, and what selecting one does.
  ///
  /// `includeArchived` is never passed: an archived master is not offered for a new
  /// entry, and the graph's default is exactly that.
  (String, List<MasterNode>, void Function(String)) _currentRung() {
    if (_unit == null) {
      return (
        'Business unit',
        ExpenseDraft.selectableUnits(widget.graph, widget.principal),
        (id) {
          widget.onChanged(businessUnitId: id);
          setState(() {
            _unit = id;
            _department = null;
            _section = null;
          });
        },
      );
    }
    if (_department == null) {
      return (
        'Department',
        widget.graph.departmentsOf(_unit!),
        (id) {
          widget.onChanged(departmentId: id);
          setState(() {
            _department = id;
            _section = null;
          });
        },
      );
    }
    if (_section == null) {
      return (
        'Section',
        widget.graph.sectionsOf(_department!),
        (id) {
          widget.onChanged(sectionId: id);
          setState(() => _section = id);
        },
      );
    }
    return (
      'Category',
      widget.graph.categoriesOf(_section!),
      (id) {
        widget.onChanged(categoryId: id);
        Navigator.of(context).pop();
      },
    );
  }
}
