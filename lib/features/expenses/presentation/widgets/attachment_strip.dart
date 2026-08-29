/// Bills attached to an expense, and what is happening to them.
///
/// The states are kept separate on purpose. An expense that has reached the server is
/// **Synced** whatever its photograph is doing, and a photograph that will not upload
/// says so on its own row. Conflating the two would tell a manager their expense had
/// failed when it had not — and the correct response to a failed upload is to retry the
/// upload, never to re-enter the expense.
///
/// Permission is asked for only when it is used. Somebody who attaches a PDF from Files
/// is never asked for the camera.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/attachments/attachment_source.dart';
import 'package:krishna_mis/data/attachments/attachment_staging.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';

class AttachmentStrip extends ConsumerStatefulWidget {
  const AttachmentStrip({
    required this.expenseId,
    required this.attachments,
    required this.onChanged,
    super.key,
  });

  final String expenseId;
  final List<ExpenseAttachment> attachments;
  final ValueChanged<List<ExpenseAttachment>> onChanged;

  @override
  ConsumerState<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends ConsumerState<AttachmentStrip> {
  String? _refusal;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(attachmentSourceProvider);
    final full = widget.attachments.length >= AttachmentPolicy.maxPerExpense;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('ATTACHMENTS', style: AppTypography.overline),
            const Spacer(),
            Text(
              '${widget.attachments.length} of '
              '${AttachmentPolicy.maxPerExpense}',
              style: AppTypography.caption,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        for (final attachment in widget.attachments)
          _AttachmentRow(
            attachment: attachment,
            onRemove: () => widget.onChanged([
              for (final a in widget.attachments)
                if (a.id != attachment.id) a,
            ]),
          ),

        if (source.available.isEmpty)
          Text(
            'Attaching a bill is not available on this device yet.',
            style: AppTypography.caption,
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final intake in source.available)
                OutlinedButton.icon(
                  key: Key('attach-${intake.name}'),
                  onPressed: full || _busy ? null : () => _add(source, intake),
                  icon: Icon(_iconFor(intake), size: 16),
                  label: Text(intake.label),
                ),
            ],
          ),

        if (_refusal case final message?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            key: const Key('attachment-refusal'),
            style: AppTypography.caption.copyWith(color: AppColors.caution),
          ),
        ],
      ],
    );
  }

  static IconData _iconFor(AttachmentIntake intake) => switch (intake) {
    AttachmentIntake.camera => Icons.photo_camera_outlined,
    AttachmentIntake.gallery => Icons.photo_library_outlined,
    AttachmentIntake.file => Icons.attach_file,
  };

  Future<void> _add(AttachmentSource source, AttachmentIntake intake) async {
    setState(() {
      _busy = true;
      _refusal = null;
    });
    try {
      final picked = await source.pick(intake);
      // Cancelling is ordinary, and a denied permission arrives here as the same null.
      // Neither is an error worth shouting about.
      if (picked == null) return;

      final staged = await ref
          .read(attachmentStagingProvider)
          .stage(
            source: picked.file,
            expenseId: widget.expenseId,
            fileName: picked.fileName,
            contentType: picked.contentType,
            alreadyAttached: widget.attachments,
          );
      widget.onChanged([...widget.attachments, staged.toDomain()]);
    } on AttachmentRefused catch (refusal) {
      setState(() => _refusal = refusal.reason.message);
    } on Object {
      setState(
        () => _refusal =
            'That file could not be attached. The expense is unaffected.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachment, this.onRemove});

  final ExpenseAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final (label, colour, icon) = switch (attachment.uploadState) {
      AttachmentUploadState.pending => (
        'Staged · will upload',
        AppColors.syncPending,
        Icons.schedule,
      ),
      AttachmentUploadState.uploaded => (
        'Uploaded',
        AppColors.syncSynced,
        Icons.check_circle_outline,
      ),
      AttachmentUploadState.stagingReclaimed => (
        'Uploaded',
        AppColors.syncSynced,
        Icons.cloud_done_outlined,
      ),
      AttachmentUploadState.failed => (
        'Upload failed · will retry',
        AppColors.syncFailed,
        Icons.error_outline,
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            attachment.isImage
                ? Icons.image_outlined
                : Icons.description_outlined,
            size: 18,
            color: AppColors.inkFaint,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body,
                ),
                Row(
                  children: [
                    Icon(icon, size: 12, color: colour),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      label,
                      style: AppTypography.caption.copyWith(color: colour),
                    ),
                    Text(
                      ' · ${_size(attachment.byteSize)}',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Remove',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).round()} KB';
}
