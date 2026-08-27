/// The Android master-management surface.
///
/// A drill-down, not a shrunk desktop tree:
///
/// ```
/// Masters → Crystal Canopy → Kitchen → Food Production → Kirana & Pulses
/// ```
///
/// Each level is a full-width, thumb-reachable list with a breadcrumb above it. Masters
/// are an occasional administrative task on a phone — transaction entry is the daily
/// workflow — so this favours clarity and large targets over density.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/features/masters/presentation/masters_model.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/master_chrome.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/master_detail_panel.dart';

/// The path currently drilled into. Empty means the top level.
final androidMasterPathProvider =
    NotifierProvider<AndroidMasterPath, List<MasterEntry>>(
      AndroidMasterPath.new,
    );

class AndroidMasterPath extends Notifier<List<MasterEntry>> {
  @override
  List<MasterEntry> build() => const [];

  void push(MasterEntry entry) => state = [...state, entry];
  void pop() =>
      state = state.isEmpty ? state : state.sublist(0, state.length - 1);
}

class AndroidMastersView extends ConsumerWidget {
  const AndroidMastersView({super.key});

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
        final path = ref.watch(androidMasterPathProvider);
        final current = path.isEmpty
            ? tree.units
            : tree.children(path.last.node.id);

        return PopScope(
          canPop: path.isEmpty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && path.isNotEmpty) _pop(ref);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Breadcrumb(path: path),
              const Divider(height: 1),
              Expanded(
                child: current.isEmpty
                    ? MasterEmptyState(
                        icon: Icons.folder_open_outlined,
                        title: 'Nothing here yet',
                        message: path.isEmpty
                            ? 'No business units have been set up.'
                            : 'No records under ${path.last.node.name}.',
                      )
                    : _LevelList(entries: current, tree: tree),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _pop(WidgetRef ref) =>
      ref.read(androidMasterPathProvider.notifier).pop();
}

class _Breadcrumb extends ConsumerWidget {
  const _Breadcrumb({required this.path});

  final List<MasterEntry> path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showArchived = ref.watch(showArchivedMastersProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          if (path.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              tooltip: 'Back',
              onPressed: () => AndroidMastersView._pop(ref),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  path.isEmpty
                      ? 'MASTERS'
                      : path.map((e) => e.node.name).join(' › ').toUpperCase(),
                  style: AppTypography.overline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  path.isEmpty ? 'Business units' : path.last.node.name,
                  style: AppTypography.subheading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              showArchived
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
            tooltip: showArchived ? 'Hide archived' : 'Show archived',
            onPressed: () =>
                ref.read(showArchivedMastersProvider.notifier).toggle(),
          ),
        ],
      ),
    );
  }
}

class _LevelList extends ConsumerWidget {
  const _LevelList({required this.entries, required this.tree});

  final List<MasterEntry> entries;
  final MasterTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: AppSpacing.lg),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final children = tree.children(entry.node.id);
        final archived = entry.node.isArchived;

        return InkWell(
          focusColor: AppColors.brassWash,
          onTap: () {
            if (children.isNotEmpty) {
              ref.read(androidMasterPathProvider.notifier).push(entry);
            } else {
              _openDetail(context, entry);
            }
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        entry.node.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          color: archived ? AppColors.inkFaint : AppColors.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          Text(entry.level.label, style: AppTypography.caption),
                          if (children.isNotEmpty) ...[
                            Text(' · ', style: AppTypography.caption),
                            Text(
                              '${children.length} inside',
                              style: AppTypography.caption,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (archived) ...[
                  const MasterStatusChip(isArchived: true, compact: true),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Icon(
                  children.isNotEmpty
                      ? Icons.chevron_right
                      : Icons.info_outline,
                  size: 18,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openDetail(BuildContext context, MasterEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(entry.node.name)),
          body: MasterDetailPanel(entry: entry, showHeaderRule: false),
        ),
      ),
    );
  }
}
