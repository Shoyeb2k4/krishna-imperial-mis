/// Evidence attached to a financial document, and what is happening to it.
///
/// One strip for both documents. It was written for expenses in Phase 3 and generalised
/// in Slice 11 by giving it the owner it is attaching to — the picker, the staging
/// service, the policy and the lifecycle were never expense-specific, and a second copy
/// for revenue would have been a second set of words for the same eight states.
///
/// The states are kept separate on purpose. A record that has reached the server is
/// **Synced** whatever its photograph is doing, and a photograph that will not upload
/// says so on its own row. Conflating the two would tell a manager their entry had
/// failed when it had not — and the correct response to a failed upload is to retry the
/// upload, never to re-enter the figures.
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
import 'package:krishna_mis/domain/attachments/document_attachment.dart';

class AttachmentStrip extends ConsumerStatefulWidget {
  const AttachmentStrip({
    required this.owner,
    required this.ownerId,
    required this.attachments,
    required this.onChanged,
    this.title = 'ATTACHMENTS',
    super.key,
  });

  /// Which document this evidence supports. Decides the wording and, downstream, the
  /// storage prefix and the registration endpoint.
  final AttachmentOwnerKind owner;

  /// The document's own id, which names the app-private staging directory.
  final String ownerId;

  final List<DocumentAttachment> attachments;
  final ValueChanged<List<DocumentAttachment>> onChanged;
  final String title;

  /// Whether a file already recorded may be dropped from the list.
  ///
  /// Always false in V1: there is no attachment removal, for either document (D-072a).
  /// A file staged in *this* sitting can still be taken back out before the record is
  /// saved, which is not removal — nothing has been recorded to remove.
  bool canDiscard(DocumentAttachment attachment) =>
      attachment.uploadState == AttachmentUploadState.staged;

  @override
  ConsumerState<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends ConsumerState<AttachmentStrip> {
  String? _refusal;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(attachmentSourceProvider);
    final full = widget.attachments.length >= AttachmentPolicy.maxPerDocument;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.title, style: AppTypography.overline),
            const Spacer(),
            Text(
              '${widget.attachments.length} of '
              '${AttachmentPolicy.maxPerDocument}',
              style: AppTypography.caption,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        for (final attachment in widget.attachments)
          _AttachmentRow(
            attachment: attachment,
            owner: widget.owner,
            // Only a file staged in this sitting can be taken back out, and doing so is
            // not removal: nothing has been recorded yet. Evidence already on the record
            // stays, because V1 ships no destructive attachment removal (D-072a).
            onRemove: widget.canDiscard(attachment)
                ? () => widget.onChanged([
                    for (final a in widget.attachments)
                      if (a.id != attachment.id) a,
                  ])
                : null,
          ),

        if (source.available.isEmpty)
          Text(
            'Attaching a file is not available on this device yet.',
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
            ownerId: widget.ownerId,
            fileName: picked.fileName,
            contentType: picked.contentType,
            alreadyAttached: widget.attachments,
          );
      widget.onChanged([...widget.attachments, staged.toDomain()]);
    } on AttachmentRefused catch (refusal) {
      setState(() => _refusal = refusal.reason.messageFor(widget.owner));
    } on Object {
      setState(
        () => _refusal =
            'That file could not be attached. The ${widget.owner.noun} is '
            'unaffected.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.owner,
    this.onRemove,
  });

  final DocumentAttachment attachment;
  final AttachmentOwnerKind owner;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    // The words come from the state itself, so the chip and the persisted lifecycle
    // cannot disagree (D-073 §3). Only the colour and the icon are the strip's business.
    final (colour, icon) = switch (attachment.uploadState) {
      AttachmentUploadState.staged => (AppColors.syncPending, Icons.attachment),
      AttachmentUploadState.waitingForExpense => (
        AppColors.syncPending,
        Icons.schedule,
      ),
      AttachmentUploadState.pendingUpload => (
        AppColors.syncPending,
        Icons.cloud_upload_outlined,
      ),
      AttachmentUploadState.uploading => (
        AppColors.syncPending,
        Icons.cloud_sync_outlined,
      ),
      AttachmentUploadState.uploaded => (
        AppColors.syncSynced,
        Icons.check_circle_outline,
      ),
      AttachmentUploadState.stagingReclaimed => (
        AppColors.syncSynced,
        Icons.cloud_done_outlined,
      ),
      AttachmentUploadState.retryNeeded => (
        AppColors.syncFailed,
        Icons.error_outline,
      ),
      AttachmentUploadState.rejected => (
        AppColors.negative,
        Icons.block_outlined,
      ),
    };
    final label = attachment.uploadState.labelFor(owner);

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
              tooltip: 'Take this file back out',
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
