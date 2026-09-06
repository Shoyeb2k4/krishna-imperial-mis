/// The evidence attached to a recorded sale, and how another file is added to it.
///
/// Three things this surface is careful about, and each is a rule rather than a layout
/// choice.
///
/// **Attaching is not editing.** A till report added the morning after a sale was
/// recorded corrects nothing: no amount, no tax figure, no business date and no KI-REV
/// number changes, no `base_row_version` is carried and no outbox intent is queued. So it
/// is its own control rather than a trip through the correction form, which would put a
/// financial mutation behind an act that is not one (Slice 11, §20).
///
/// **A file's state is its own.** A sale that has reached the server is `Synced` whatever
/// its evidence is doing, and evidence that will not upload says so on its own row. The
/// correct response to a failed upload is to retry the upload, never to re-enter the
/// figures.
///
/// **Nothing here exposes a storage key.** A person is shown the file name, its size and
/// what is happening to it. The object path and the bucket are implementation, and a
/// predictable path is not a secret but it is also not information (spec §15.2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/features/attachments/presentation/attachment_strip.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_providers.dart';

class RevenueEvidence extends ConsumerStatefulWidget {
  const RevenueEvidence({required this.entry, super.key});

  final RevenueEntry entry;

  @override
  ConsumerState<RevenueEvidence> createState() => _RevenueEvidenceState();
}

class _RevenueEvidenceState extends ConsumerState<RevenueEvidence> {
  String? _refusal;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;

    // A voided sale keeps the evidence it has and gains none (D-006). The list is still
    // shown, because that is exactly what an audit question asks for; the control that
    // would add to it is absent, and the reason is stated rather than left as a missing
    // button.
    if (entry.isVoided) {
      return Column(
        key: const Key('revenue-evidence'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EVIDENCE', style: AppTypography.overline),
          const SizedBox(height: AppSpacing.sm),
          if (entry.attachments.isEmpty)
            Text(
              'No attachments.',
              key: const Key('revenue-evidence-none'),
              style: AppTypography.caption,
            )
          else
            for (final attachment in entry.attachments)
              _EvidenceRow(attachment: attachment),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This sale has been voided. Its attachments remain on the record '
            'and nothing further can be added.',
            key: const Key('revenue-evidence-voided'),
            style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
          ),
        ],
      );
    }

    return Column(
      key: const Key('revenue-evidence'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The strip owns the list, the picker and the staging refusals; this widget owns
        // what happens to a file once it is staged against an already-recorded sale.
        AttachmentStrip(
          owner: AttachmentOwnerKind.sale,
          ownerId: entry.id,
          title: 'EVIDENCE',
          attachments: entry.attachments,
          onChanged: _attach,
        ),
        if (_refusal case final message?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            key: const Key('revenue-evidence-refusal'),
            style: AppTypography.caption.copyWith(color: AppColors.caution),
          ),
        ],
      ],
    );
  }

  Future<void> _attach(List<DocumentAttachment> attachments) async {
    setState(() => _refusal = null);
    final refusal = await ref
        .read(revenueEntryControllerProvider)
        .attach(entryId: widget.entry.id, staged: attachments);
    if (!mounted) return;
    // A refusal is an answer, and the sale is untouched by it either way — which is what
    // the message says, because "could not attach" alone reads like something went wrong
    // with the money.
    if (refusal != null) setState(() => _refusal = refusal.message);
  }
}

/// One file on a voided sale: what it is and where it got to, with no control beside it.
class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.attachment});

  final DocumentAttachment attachment;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      children: [
        Icon(
          attachment.isImage
              ? Icons.image_outlined
              : Icons.description_outlined,
          size: 16,
          color: AppColors.inkFaint,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            attachment.fileName,
            style: AppTypography.body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          // From the state itself, so the words and the persisted lifecycle cannot
          // disagree (D-073 §3, D-119).
          attachment.uploadState.labelFor(AttachmentOwnerKind.sale),
          style: AppTypography.caption.copyWith(
            color: attachment.uploadState.needsAttention
                ? AppColors.syncFailed
                : AppColors.inkMuted,
          ),
        ),
      ],
    ),
  );
}
