/// The detail view for one master, shared by both platforms.
///
/// Windows shows it in a side panel beside the hierarchy — context stays visible, which
/// a modal would destroy. Android shows the same content as its own page at the end of a
/// drill-down.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/repositories/master_repository.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/masters/master_reference.dart';
import 'package:krishna_mis/features/masters/presentation/masters_model.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/master_chrome.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/rename_master_dialog.dart';

class MasterDetailPanel extends ConsumerWidget {
  const MasterDetailPanel({
    required this.entry,
    super.key,
    this.showHeaderRule = true,
  });

  final MasterEntry entry;
  final bool showHeaderRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usageAsync = ref.watch(masterUsageProvider(entry.node.id));
    final principal = ref.watch(principalProvider);
    final canManage = principal.canAnywhere(Capability.mastersManage);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.level.label.toUpperCase(), style: AppTypography.overline),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(entry.node.name, style: AppTypography.heading),
              ),
              const SizedBox(width: AppSpacing.md),
              MasterStatusChip(isArchived: entry.node.isArchived),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CodeBadge(entry.node.code),
          if (showHeaderRule) ...[
            const SizedBox(height: AppSpacing.xl),
            const Divider(height: 1),
          ],
          const SizedBox(height: AppSpacing.xl),

          if (entry.ancestors.isNotEmpty)
            DetailField(
              label: 'Belongs to',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final ancestor in entry.ancestors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                      // Expanded + ellipsis: on a 390pt phone a long unit name plus its
                      // level label overflows the row, which a widget test caught at
                      // 155px. The label is fixed-width; the name is what must give.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 108,
                            child: Text(
                              ancestor.level.label,
                              style: AppTypography.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              ancestor.node.name,
                              style: AppTypography.body,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          DetailField(
            label: 'Historical usage',
            child: usageAsync.when(
              data: UsageNote.new,
              loading: () =>
                  const Text('Checking…', style: AppTypography.bodyMuted),
              error: (e, _) => Text(
                'Could not check usage.',
                style: AppTypography.bodyMuted,
              ),
            ),
          ),

          if (entry.node.isArchived)
            DetailField(
              label: 'Archived',
              child: Text(
                'Not offered for new entries. Existing transactions keep it, and past '
                'reports are unchanged.',
                style: AppTypography.bodyMuted,
              ),
            ),

          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

          if (!canManage)
            Text(
              'You have read access to master data. Changing it requires the '
              '"manage masters" permission.',
              style: AppTypography.bodyMuted,
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _rename(context, ref),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Rename'),
                ),
                if (entry.node.isArchived)
                  OutlinedButton.icon(
                    onPressed: () => _unarchive(context, ref),
                    icon: const Icon(Icons.unarchive_outlined, size: 16),
                    label: const Text('Restore'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _archive(context, ref),
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: const Text('Archive'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final usage = await ref
        .read(masterUsageReaderProvider)
        .usageForMaster(entry.node.id);
    if (!context.mounted) return;

    final newName = await RenameMasterDialog.show(
      context,
      currentName: entry.node.name,
      code: entry.node.code,
      usage: usage,
      kindLabel: entry.level.label,
    );
    if (newName == null || !context.mounted) return;

    await _run(
      context,
      ref,
      () async {
        await ref
            .read(masterRepositoryProvider)
            .rename(
              kind: entry.level.kind,
              id: entry.node.id,
              name: newName,
              now: DateTime.now().toUtc(),
            );
      },
      success:
          'Renamed to "$newName". The code ${entry.node.code} is unchanged.',
    );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    await _run(
      context,
      ref,
      () async {
        final decision = await ref
            .read(masterRepositoryProvider)
            .archive(
              kind: entry.level.kind,
              id: entry.node.id,
              now: DateTime.now().toUtc(),
            );
        if (!decision.isAllowed) {
          throw _Refused(decision.message ?? 'This cannot be archived.');
        }
      },
      success: '${entry.node.name} archived. Existing history is untouched.',
    );
  }

  Future<void> _unarchive(BuildContext context, WidgetRef ref) async {
    await _run(context, ref, () async {
      await ref
          .read(masterRepositoryProvider)
          .unarchive(
            kind: entry.level.kind,
            id: entry.node.id,
            now: DateTime.now().toUtc(),
          );
    }, success: '${entry.node.name} restored.');
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action, {
    required String success,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
      ref.invalidate(masterGraphProvider);
      ref.invalidate(masterUsageProvider(entry.node.id));
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(success)));
    } on _Refused catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } on MasterWriteRefused catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } on HierarchyIntegrityFailure catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(error.violations.map((v) => v.message).join(' ')),
          ),
        );
    }
  }
}

class _Refused implements Exception {
  const _Refused(this.message);
  final String message;
}

/// Explains the archive rule when a parent cannot be archived yet.
class ArchiveBlockedNotice extends StatelessWidget {
  const ArchiveBlockedNotice({required this.childCount, super.key});

  final int childCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brassWash,
        borderRadius: AppRadius.allSmall,
      ),
      child: Text(
        'Archive the $childCount active ${childCount == 1 ? 'record' : 'records'} '
        'underneath this one first. Nothing is archived automatically, so a live '
        'category is never left hanging off an archived parent.',
        style: AppTypography.caption,
      ),
    );
  }
}

/// Extension point used by the panel to map a display level onto the repository's kind.
extension on MasterLevel {
  MasterKind get kind => switch (this) {
    MasterLevel.businessUnit => MasterKind.businessUnit,
    MasterLevel.department => MasterKind.department,
    MasterLevel.section => MasterKind.section,
    MasterLevel.expenseCategory => MasterKind.expenseCategory,
    MasterLevel.revenueCategory => MasterKind.revenueCategory,
  };
}

/// Unused here but kept close to the panel: a reference is what a transaction stores.
typedef MasterReferenceBuilder = MasterReference Function(MasterNode node);
