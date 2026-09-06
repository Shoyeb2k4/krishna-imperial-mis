/// What a person is shown when their correction was refused because the record moved.
///
/// Two refusals arrive here and they are different questions wearing one word:
///
///  * **A stale row version** (`KM003`) — somebody else corrected this sale after this
///    form was opened. Applying the correction would overwrite a change nobody has read.
///  * **A tax configuration mismatch** (`KM030`, D-114) — the server resolved a different
///    rate from the one the operator approved, because the configuration changed between
///    preparing the entry and delivering it.
///
/// Both are two defensible answers with nobody entitled to overwrite the other, which is
/// why both surface as a conflict rather than a rejection. **Nothing is merged and
/// nothing is auto-applied**: the figures are put side by side, and the only forward
/// action re-reads the record and reopens the form on it, after which the operator
/// decides with both numbers in front of them.
///
/// The conflicted intent is never deleted here. It is that person's work, it exists
/// nowhere else, and it stays inspectable (D-048 §2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_draft.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_entry_page.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_providers.dart';

/// Re-reads the sale from the server and shows it beside what was submitted.
///
/// The order is load-bearing. The local row still holds **the attempted values** — the
/// correction was applied locally and then refused on delivery — so it is captured before
/// the re-read replaces it. Reading first would leave nothing to compare against, and the
/// sheet would show the same figures twice.
Future<void> reviewLatestRevenue(
  BuildContext context,
  WidgetRef ref,
  RevenueEntry attempted,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final gateway = ref.read(revenueGatewayProvider);
  final authority = ref.read(revenueAuthorityProvider);

  if (gateway == null || authority == null) {
    messenger.showSnackBar(
      const SnackBar(
        key: Key('revenue-conflict-offline'),
        content: Text(
          'Connect to the internet to see what this sale says now. Nothing '
          'has been lost.',
        ),
      ),
    );
    return;
  }

  final header = await gateway.fetchDocument(attempted.id);
  final components = await gateway.fetchComponents(attempted.id);
  // Evidence too, so re-reading the sale re-reads all of it. Its absence is not a reason
  // to refuse the read: the conflict being resolved is about figures, and a file list
  // that could not be fetched is a gap in the display rather than in the decision.
  final attachments = await gateway.fetchAttachments(attempted.id);
  if (!context.mounted) return;

  if (header is! RemoteOk<Map<String, dynamic>?> ||
      header.value == null ||
      components is! RemoteOk<List<Map<String, dynamic>>>) {
    messenger.showSnackBar(
      const SnackBar(
        key: Key('revenue-conflict-unreadable'),
        content: Text(
          'This sale could not be read back just now. Your entry is kept '
          'exactly as it was.',
        ),
      ),
    );
    return;
  }

  await ref
      .read(revenueRepositoryProvider)
      .applyServerDocument(
        header: header.value!,
        components: components.value,
        orgId: authority.orgId,
        attachments: attachments is RemoteOk<List<Map<String, dynamic>>>
            ? attachments.value
            : const [],
      );
  ref.invalidate(revenueDetailProvider(attempted.id));

  final current = await ref.read(revenueRepositoryProvider).load(attempted.id);
  if (!context.mounted) return;

  final reapply = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.paper,
    builder: (_) =>
        RevenueConflictSheet(attempted: attempted, current: current),
  );

  if (reapply != true || current == null || !context.mounted) return;

  // Reopened on the **current** record, so the correction is re-entered against what the
  // sale now says and carries the version it now holds. Re-submitting the old draft with
  // a refreshed version number would be the silent overwrite this whole path exists to
  // prevent.
  await Navigator.of(context).push(
    MaterialPageRoute<String>(
      builder: (_) => RevenueEntryPage.editing(RevenueDraft.fromEntry(current)),
    ),
  );
  ref.invalidate(revenueDetailProvider(attempted.id));
}

class RevenueConflictSheet extends StatelessWidget {
  const RevenueConflictSheet({
    required this.attempted,
    required this.current,
    super.key,
  });

  /// The sale as the operator submitted it.
  final RevenueEntry attempted;

  /// The sale as the server now holds it.
  final RevenueEntry? current;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This sale changed while you were correcting it',
            key: const Key('revenue-conflict-title'),
            style: AppTypography.heading,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your correction has not been applied. Applying it now would '
            'replace a change you have not seen.',
            style: AppTypography.body,
          ),
          const SizedBox(height: AppSpacing.lg),
          _Side(
            label: 'WHAT YOU ENTERED',
            entry: attempted,
            sideKey: const Key('revenue-conflict-attempted'),
          ),
          const SizedBox(height: AppSpacing.md),
          _Side(
            label: 'WHAT THE SALE SAYS NOW',
            entry: current,
            sideKey: const Key('revenue-conflict-current'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('revenue-conflict-reapply'),
                  onPressed: current == null
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: const Text('Correct it again'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton(
                  key: const Key('revenue-conflict-dismiss'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Leave it for now'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.entry,
    required this.sideKey,
  });

  final String label;
  final RevenueEntry? entry;
  final Key sideKey;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    return Container(
      key: sideKey,
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.hairline),
        borderRadius: AppRadius.allSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.overline),
          const SizedBox(height: AppSpacing.sm),
          if (e == null)
            Text(
              'This sale could not be read back.',
              style: AppTypography.body.copyWith(color: AppColors.inkMuted),
            )
          else ...[
            _Line(label: 'Business date', value: Text(e.businessDate.iso)),
            _Line(label: 'Gross', value: MoneyText(e.gross)),
            _Line(label: 'GST', value: MoneyText(e.tax)),
            _Line(label: 'Net', value: MoneyText(e.net)),
            _Line(label: 'Components', value: Text('${e.components.length}')),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
        ),
        value,
      ],
    ),
  );
}
