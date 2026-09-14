/// One sale, rendered from a value and nothing else (Phase 5 Slice 10).
///
/// **Nothing here consults today's tax configuration.** Every figure, rate, treatment,
/// basis and band comes from the component's own snapshot, which is exactly why that
/// snapshot exists: a sale recorded in June under a 5% rule must still explain itself in
/// December after the rule has been superseded (D-080). `none` and a configured `0%` both
/// produce ₹0 of tax and are shown differently — one is a treatment somebody chose, the
/// other a rate somebody set (D-091).
///
/// ## An immutable body, not a panel with its buttons hidden
///
/// This widget owns no action of any kind: no correction, void, Review latest, attachment
/// control, sync chip or outbox read. It imports none of them, and a structural guard holds
/// that. A surface that may act on a sale composes its own controls into [status],
/// [attention] and [evidence]; the P&L drill-down composes none, so there is nothing on its
/// path to hide.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

class RevenueDocumentBody extends StatelessWidget {
  const RevenueDocumentBody({
    required this.entry,
    required this.graph,
    this.leading,
    this.status,
    this.attention,
    this.evidence,
    this.listKey = const Key('revenue-detail-panel'),
    super.key,
  });

  final RevenueEntry entry;
  final MasterGraph graph;

  /// Shown above the reference — the drill-down's statement of which bucket this explains.
  final Widget? leading;

  /// Shown beside the voided label — a composing surface's sync status.
  final Widget? status;

  /// Shown under the header — a composing surface's banners and controls.
  final Widget? attention;

  /// The evidence section. When absent, the attached files are listed read-only.
  final Widget? evidence;

  final Key listKey;

  @override
  Widget build(BuildContext context) {
    final voided = entry.voidedAt != null;

    return ListView(
      key: listKey,
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (leading case final leading?) ...[
          leading,
          const SizedBox(height: AppSpacing.md),
        ],
        Text(
          entry.txnNumber ?? 'Pending number',
          key: const Key('revenue-detail-reference'),
          style: AppTypography.subheading.copyWith(
            color: entry.txnNumber == null ? AppColors.inkMuted : AppColors.ink,
          ),
        ),
        if (entry.txnNumber == null)
          Text(
            'The server assigns a number when this sale is accepted.',
            style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
          ),
        const SizedBox(height: AppSpacing.md),

        Row(
          children: [
            ?status,
            if (voided) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Voided',
                key: const Key('revenue-detail-voided'),
                style: AppTypography.caption.copyWith(
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ],
        ),
        if (voided) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            key: const Key('revenue-void-detail'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadius.allSmall,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.voidReason != null)
                  Text(entry.voidReason!, style: AppTypography.body),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  // The server time, because "when" is half of what an audit question
                  // asks. The actor is not shown: a raw user id is not an answer.
                  entry.voidedAt == null
                      ? 'Voided'
                      : 'Voided on ${entry.voidedAt!.toUtc().toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC',
                  key: const Key('revenue-void-when'),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],

        ?attention,

        const SizedBox(height: AppSpacing.lg),
        _Field(label: 'Business date', value: entry.businessDate.iso),
        _Field(
          label: 'Property',
          value: graph.businessUnit(entry.businessUnitId)?.name ?? '—',
        ),
        _Field(
          label: 'Category',
          value: graph.revenueCategory(entry.revenueCategoryId)?.name ?? '—',
        ),
        _Field(label: 'Entry type', value: entry.entryKind.label),
        if (entry.sourceReference != null)
          _Field(label: 'Source reference', value: entry.sourceReference!),
        if (entry.notes != null) _Field(label: 'Notes', value: entry.notes!),

        const SizedBox(height: AppSpacing.lg),
        Text('How this was calculated', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),

        // Every component, separately. Flattening two tariff bands into one rate would
        // state a rate that was never applied to anything.
        for (var i = 0; i < entry.components.length; i++)
          _ComponentCard(
            component: entry.components[i],
            index: i,
            showIndex: entry.components.length > 1,
          ),

        if (entry.components.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          _TotalsCard(entry: entry),
        ],

        // Supporting evidence, after the figures and before the provenance — it explains
        // the sale, it is not part of it.
        const SizedBox(height: AppSpacing.lg),
        evidence ?? _ReadOnlyEvidence(entry: entry),

        const SizedBox(height: AppSpacing.lg),
        Text('Record', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        _Field(label: 'Entered by', value: entry.createdBy ?? '—', dim: true),
        _Field(label: 'Version', value: '${entry.rowVersion}', dim: true),
        _Field(label: 'Reference id', value: entry.id, dim: true),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

/// The files attached to a sale, by name. No control of any kind.
class _ReadOnlyEvidence extends StatelessWidget {
  const _ReadOnlyEvidence({required this.entry});

  final RevenueEntry entry;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('revenue-evidence-read-only'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('EVIDENCE', style: AppTypography.overline),
      const SizedBox(height: AppSpacing.sm),
      if (entry.attachments.isEmpty)
        Text('No attachments.', style: AppTypography.caption)
      else
        for (final attachment in entry.attachments)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(
                  Icons.attachment,
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
              ],
            ),
          ),
    ],
  );
}

class _ComponentCard extends StatelessWidget {
  const _ComponentCard({
    required this.component,
    required this.index,
    required this.showIndex,
  });

  final RevenueComponent component;
  final int index;
  final bool showIndex;

  @override
  Widget build(BuildContext context) {
    final untaxed = component.taxTreatment == TaxTreatment.none;

    return Container(
      key: Key('revenue-component-$index'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.allSmall,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showIndex || component.valueBandLabel != null) ...[
            Text(
              component.valueBandLabel ?? 'Amount ${index + 1}',
              key: Key('revenue-component-band-$index'),
              style: AppTypography.body,
            ),
            if (component.valueBandFloor != null ||
                component.valueBandCeiling != null)
              Text(
                _bandRange(component),
                style: AppTypography.caption.copyWith(
                  color: AppColors.inkMuted,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],

          _MoneyLine(
            label: component.enteredBasis.fieldLabelFor(component.taxTreatment),
            amount: component.enteredAmount,
          ),
          const Divider(height: AppSpacing.md, color: AppColors.hairline),
          _MoneyLine(label: 'Sales total', amount: component.gross),

          if (untaxed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                key: Key('revenue-component-no-gst-$index'),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'GST',
                    style: AppTypography.body.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                  Text(
                    'No GST',
                    style: AppTypography.body.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            )
          else
            _MoneyLine(
              label: 'GST at ${_ratePercent(component.taxRateBasisPoints)}',
              amount: component.tax,
              muted: true,
            ),

          _MoneyLine(label: 'Net sales', amount: component.net, strong: true),

          const SizedBox(height: AppSpacing.sm),
          Text(
            // The rule as it was, not as it is.
            untaxed
                ? 'Recorded under a rule with no GST.'
                : 'Recorded under a ${_ratePercent(component.taxRateBasisPoints)} '
                      '${component.taxTreatment.name} rule.',
            key: Key('revenue-component-rule-$index'),
            style: AppTypography.caption.copyWith(color: AppColors.inkFaint),
          ),
          if (component.supplySubtypeId != null)
            Text(
              'Supply type recorded on this amount.',
              style: AppTypography.caption.copyWith(color: AppColors.inkFaint),
            ),
          if (component.premisesStatusCode != null)
            Text(
              'Premises status: ${component.premisesStatusCode}',
              style: AppTypography.caption.copyWith(color: AppColors.inkFaint),
            ),
        ],
      ),
    );
  }

  static String _bandRange(RevenueComponent component) {
    final floor = component.valueBandFloor;
    final ceiling = component.valueBandCeiling;
    if (floor != null && ceiling != null) {
      return '${MoneyFormatter.wholeRupees.format(floor)} – '
          '${MoneyFormatter.wholeRupees.format(ceiling)}';
    }
    if (ceiling != null) {
      return 'Up to ${MoneyFormatter.wholeRupees.format(ceiling)}';
    }
    return 'Above ${MoneyFormatter.wholeRupees.format(floor!)}';
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.entry});

  final RevenueEntry entry;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('revenue-detail-totals'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadius.allSmall,
    ),
    child: Column(
      children: [
        Text('Document total', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        _MoneyLine(label: 'Sales total', amount: entry.gross),
        _MoneyLine(label: 'GST', amount: entry.tax, muted: true),
        _MoneyLine(label: 'Net sales', amount: entry.net, strong: true),
      ],
    ),
  );
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({
    required this.label,
    required this.amount,
    this.muted = false,
    this.strong = false,
  });

  final String label;
  final Money amount;
  final bool muted;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.body.copyWith(
              color: muted ? AppColors.inkMuted : AppColors.ink,
            ),
          ),
        ),
        MoneyText(
          amount,
          formatter: MoneyFormatter.standard,
          style: (strong ? AppTypography.subheading : AppTypography.body)
              .copyWith(color: muted ? AppColors.inkMuted : AppColors.ink),
        ),
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.dim = false});

  final String label;
  final String value;
  final bool dim;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: AppTypography.body.copyWith(
              color: dim ? AppColors.inkFaint : AppColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

/// `500` basis points as `5%`, and `250` as `2.5%`. Integer arithmetic only.
String _ratePercent(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final fraction = basisPoints % 100;
  if (fraction == 0) return '$whole%';
  final trimmed = fraction % 10 == 0 ? '${fraction ~/ 10}' : '$fraction';
  return '$whole.$trimmed%';
}
