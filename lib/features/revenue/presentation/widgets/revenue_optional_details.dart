/// The fields a routine sales entry never touches.
///
/// Closed by default and closed for a reason: the evening figure is the workflow, and a
/// screen that opens with six fields makes the one that matters harder to find. Entry
/// kind, source reference and notes exist because the schema deliberately permits shift
/// summaries, imports and corrections (D-023) — not because anybody types them daily.
///
/// **Attaching evidence lives here too, and nowhere earlier.** A till report or a
/// banquet billing document is worth keeping and is never required — no configured
/// category demands one, and the fast path stays four taps and a number. So it sits
/// behind the same disclosure as the entry kind and the notes, using the shared strip the
/// expense form uses rather than a revenue copy of it (Slice 11).
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/features/attachments/presentation/attachment_strip.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_draft.dart';

class RevenueOptionalDetails extends StatelessWidget {
  const RevenueOptionalDetails({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final RevenueDraft draft;
  final ValueChanged<RevenueDraft> onChanged;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      key: const Key('revenue-more-details'),
      tilePadding: EdgeInsets.zero,
      title: Text('More details', style: AppTypography.body),
      subtitle: Text(
        'Entry type, reference, notes, attachments',
        style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
      ),
      children: [
        const SizedBox(height: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Entry type', style: AppTypography.overline),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final kind in RevenueEntryKind.values)
                  // `import` is deliberately absent from the picker. Historical import is
                  // a separate, controlled workflow that marks its own rows, and offering
                  // it here would let somebody label a hand-typed figure as imported —
                  // destroying the one distinction the audit trail keeps (spec §32).
                  if (kind != RevenueEntryKind.import)
                    ChoiceChip(
                      key: Key('revenue-kind-${kind.wireName}'),
                      label: Text(kind.label),
                      selected: draft.entryKind == kind,
                      onSelected: (_) =>
                          onChanged(draft.withDetails(entryKind: kind)),
                    ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              key: const Key('revenue-source-reference'),
              initialValue: draft.sourceReference,
              decoration: const InputDecoration(
                labelText: 'Source reference',
                helperText: 'A till report or shift number, if there is one',
              ),
              onChanged: (value) => onChanged(
                draft.withDetails(
                  sourceReference: value.trim().isEmpty ? null : value.trim(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('revenue-notes'),
              initialValue: draft.notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
              onChanged: (value) => onChanged(
                draft.withDetails(
                  notes: value.trim().isEmpty ? null : value.trim(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AttachmentStrip(
              owner: AttachmentOwnerKind.sale,
              ownerId: draft.id,
              attachments: draft.attachments,
              onChanged: (attachments) =>
                  onChanged(draft.withAttachments(attachments)),
            ),
          ],
        ),
      ],
    ),
  );
}
