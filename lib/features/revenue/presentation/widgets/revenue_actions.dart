/// Correcting and voiding a sale, from either platform.
///
/// One set of controls, one set of rules, shared by the Android detail route and the
/// Windows detail panel. Desktop presentation may differ; financial behaviour may not.
///
/// **Availability is decided by capability, never by a role name.** A widget that read
/// `role == 'accountant'` would be a second authorisation model that the server does not
/// consult, and the first thing to drift. The server refuses regardless — this exists so
/// the interface does not offer what would be refused.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_draft.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_entry_page.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_providers.dart';

/// Whether this actor may correct this sale, on the client's reading.
///
/// Mirrors the server's own rule: `revenue.edit.all` for the property, or `revenue.edit`
/// plus having recorded it. The server decides for real (D-037) — including the edit
/// window and the period lock, which this cannot know without asking.
bool mayEditRevenue(Principal principal, RevenueEntry entry) {
  if (entry.voidedAt != null) return false;
  final unit = entry.businessUnitId;
  if (principal.can(Capability.revenueEditAll, businessUnitId: unit)) {
    return true;
  }
  return principal.can(Capability.revenueEdit, businessUnitId: unit) &&
      entry.createdBy == principal.userId;
}

/// Whether this actor may void this sale.
///
/// `revenue.void` is held by the Accountant and the Owner role and by nobody else, which
/// is the approved policy: recording a sale does not entitle somebody to erase it from
/// the books.
bool mayVoidRevenue(Principal principal, RevenueEntry entry) =>
    entry.voidedAt == null &&
    principal.can(Capability.revenueVoid, businessUnitId: entry.businessUnitId);

class RevenueActions extends ConsumerWidget {
  const RevenueActions({required this.entry, super.key});

  final RevenueEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final principal = ref.watch(principalProvider);
    final canEdit = mayEditRevenue(principal, entry);
    final canVoid = mayVoidRevenue(principal, entry);

    // A voided sale offers neither, and says so rather than showing two dead buttons.
    if (entry.voidedAt != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          'This sale has been voided. Corrections are made by recording a new one.',
          key: const Key('revenue-voided-note'),
          style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
        ),
      );
    }

    if (!canEdit && !canVoid) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          if (canEdit)
            OutlinedButton.icon(
              key: const Key('revenue-edit'),
              onPressed: () => _openEdit(context, ref),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            ),
          if (canEdit && canVoid) const SizedBox(width: AppSpacing.sm),
          if (canVoid)
            OutlinedButton.icon(
              key: const Key('revenue-void'),
              onPressed: () => _confirmVoid(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.negative,
              ),
              icon: const Icon(Icons.block_outlined, size: 16),
              label: const Text('Void'),
            ),
        ],
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, WidgetRef ref) async {
    // The version is captured here, from the document as it was read, and travels with
    // the draft unchanged. Nothing re-reads it before Save (§4).
    await Navigator.of(context).push(
      MaterialPageRoute<String>(
        builder: (_) => RevenueEntryPage.editing(RevenueDraft.fromEntry(entry)),
      ),
    );
    ref
      ..invalidate(revenueDetailProvider(entry.id))
      ..invalidate(recentRevenueProvider);
  }

  Future<void> _confirmVoid(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _VoidDialog(reference: entry.txnNumber),
    );
    if (reason == null || !context.mounted) return;

    final refusal = await ref
        .read(revenueEntryControllerProvider)
        .voidEntry(
          entryId: entry.id,
          baseRowVersion: entry.rowVersion,
          reason: reason,
        );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('revenue-void-result'),
        content: Text(refusal?.message ?? 'Void recorded · Pending Sync'),
      ),
    );
  }
}

/// Deliberate, and never one click.
///
/// A void is how financial history is corrected, so it asks for a sentence explaining
/// why — which is stored, shown beside the document for ever, and refused by the server
/// if it is blank (spec §14, §21).
class _VoidDialog extends StatefulWidget {
  const _VoidDialog({this.reference});

  final String? reference;

  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('revenue-void-dialog'),
    title: Text(
      widget.reference == null ? 'Void this sale' : 'Void ${widget.reference}',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The sale stays in the records as voided, with your reason. It is left '
          'out of ordinary reporting. To record the correct figure, enter a new '
          'sale afterwards.',
          style: AppTypography.body.copyWith(color: AppColors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('revenue-void-reason'),
          controller: _controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Why is this being voided?',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(
        key: const Key('revenue-void-cancel'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Keep it'),
      ),
      FilledButton(
        key: const Key('revenue-void-confirm'),
        // Whitespace is not a reason. Disabled rather than refused after the fact, so
        // the requirement is visible before somebody commits to the action.
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_controller.text.trim()),
        style: FilledButton.styleFrom(backgroundColor: AppColors.negative),
        child: const Text('Void sale'),
      ),
    ],
  );
}
