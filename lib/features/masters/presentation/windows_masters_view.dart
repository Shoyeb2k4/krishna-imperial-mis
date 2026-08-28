/// The Windows master-management surface.
///
/// A browsable hierarchy on the left, a detail panel on the right. Deliberately **not** a
/// stack of modal dialogs: selecting a category while still seeing where it sits in
/// Crystal Canopy is the whole point, and a modal would hide exactly that.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/features/masters/presentation/masters_model.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/master_chrome.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/master_detail_panel.dart';

class WindowsMastersView extends ConsumerWidget {
  const WindowsMastersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graphAsync = ref.watch(masterGraphProvider);

    return graphAsync.when(
      loading: () => const QuietLoading(),
      error: (error, _) => MasterErrorState(
        '$error',
        onRetry: () => ref.invalidate(masterGraphProvider),
      ),
      data: (graph) {
        final tree = MasterTree.from(
          graph,
          includeArchived: ref.watch(showArchivedMastersProvider),
        );
        final selected = ref.watch(selectedMasterProvider);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 380, child: _HierarchyColumn(tree: tree)),
            const VerticalDivider(width: 1, color: AppColors.hairline),
            Expanded(
              child: selected == null
                  ? const MasterEmptyState(
                      icon: Icons.account_tree_outlined,
                      title: 'Select a record',
                      message:
                          'Browse the hierarchy on the left to inspect a business unit, '
                          'department, section or category.',
                    )
                  : MasterDetailPanel(entry: selected),
            ),
          ],
        );
      },
    );
  }
}

class _HierarchyColumn extends ConsumerWidget {
  const _HierarchyColumn({required this.tree});

  final MasterTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final term = ref.watch(masterSearchProvider);
    final showArchived = ref.watch(showArchivedMastersProvider);
    final searching = term.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Masters', style: AppTypography.heading),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The structure every expense and sale is recorded against.',
                style: AppTypography.caption,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search name or code',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (value) =>
                    ref.read(masterSearchProvider.notifier).set(value),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Checkbox(
                    value: showArchived,
                    visualDensity: VisualDensity.compact,
                    activeColor: AppColors.brass,
                    onChanged: (v) => ref
                        .read(showArchivedMastersProvider.notifier)
                        .set(value: v ?? false),
                  ),
                  Text('Show archived', style: AppTypography.caption),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: searching
              ? _SearchResults(results: tree.search(term))
              : _HierarchyTree(tree: tree),
        ),
      ],
    );
  }
}

class _HierarchyTree extends ConsumerWidget {
  const _HierarchyTree({required this.tree});

  final MasterTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tree.units.isEmpty) {
      // Deliberately names no property. What is here depends entirely on what the
      // server has granted this user, and an empty list is far more likely to mean
      // "nothing has been synchronised yet" than "the company has no properties" —
      // naming one they may have no scope for would be both wrong and a small leak.
      return const MasterEmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Nothing to show yet',
        message:
            'Business units appear here once your access has been confirmed and the '
            'set-up data has been synchronised.',
      );
    }

    final expanded = ref.watch(expandedMastersProvider);
    final rows = <Widget>[];

    void addLevel(List<MasterEntry> entries, int depth) {
      for (final entry in entries) {
        final children = tree.children(entry.node.id);
        rows.add(
          _TreeRow(
            entry: entry,
            depth: depth,
            hasChildren: children.isNotEmpty,
            isExpanded: expanded.contains(entry.node.id),
          ),
        );
        if (expanded.contains(entry.node.id)) addLevel(children, depth + 1);
      }
    }

    addLevel(tree.units, 0);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: rows,
    );
  }
}

class _TreeRow extends ConsumerWidget {
  const _TreeRow({
    required this.entry,
    required this.depth,
    required this.hasChildren,
    required this.isExpanded,
  });

  final MasterEntry entry;
  final int depth;
  final bool hasChildren;
  final bool isExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected =
        ref.watch(selectedMasterProvider)?.node.id == entry.node.id;
    final archived = entry.node.isArchived;

    return InkWell(
      onTap: () {
        ref.read(selectedMasterProvider.notifier).select(entry);
        if (hasChildren) _toggle(ref);
      },
      focusColor: AppColors.brassWash,
      hoverColor: AppColors.surfaceSunken,
      child: Container(
        height: 32,
        padding: EdgeInsets.only(
          left: AppSpacing.md + depth * AppSpacing.lg,
          right: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.brassWash : null,
          border: Border(
            left: BorderSide(
              color: selected ? AppColors.brass : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: hasChildren
                  ? Semantics(
                      button: true,
                      label: isExpanded ? 'Collapse' : 'Expand',
                      child: GestureDetector(
                        onTap: () => _toggle(ref),
                        child: Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 16,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                entry.node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  color: archived ? AppColors.inkFaint : AppColors.ink,
                  fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.w400,
                  fontStyle: archived ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
            if (archived) ...[
              const SizedBox(width: AppSpacing.sm),
              const MasterStatusChip(isArchived: true, compact: true),
            ],
          ],
        ),
      ),
    );
  }

  void _toggle(WidgetRef ref) =>
      ref.read(expandedMastersProvider.notifier).toggle(entry.node.id);
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.results});

  final List<MasterEntry> results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (results.isEmpty) {
      return const MasterEmptyState(
        icon: Icons.search_off_outlined,
        title: 'Nothing matched',
        message: 'Try part of a name, or the permanent code such as KIRANA.',
      );
    }

    final selectedId = ref.watch(selectedMasterProvider)?.node.id;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: results.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: AppSpacing.lg),
      itemBuilder: (context, index) {
        final entry = results[index];
        final selected = entry.node.id == selectedId;
        return InkWell(
          onTap: () => ref.read(selectedMasterProvider.notifier).select(entry),
          focusColor: AppColors.brassWash,
          hoverColor: AppColors.surfaceSunken,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            color: selected ? AppColors.brassWash : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body,
                      ),
                    ),
                    if (entry.node.isArchived)
                      const MasterStatusChip(isArchived: true, compact: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  entry.ancestors.isEmpty
                      ? entry.level.label
                      : '${entry.level.label} · ${entry.ancestorPath}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Keyboard shortcut wrapper so the workstation stays keyboard-driven.
class MastersShortcuts extends StatelessWidget {
  const MastersShortcuts({
    required this.child,
    required this.onFocusSearch,
    super.key,
  });

  final Widget child;
  final VoidCallback onFocusSearch;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            onFocusSearch,
      },
      child: child,
    );
  }
}
