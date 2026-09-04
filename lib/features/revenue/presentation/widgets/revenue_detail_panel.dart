/// How one sale's tax was calculated, read from the sale itself.
///
/// **Nothing here consults today's tax configuration.** Every figure, rate, treatment,
/// basis and band comes from the component's own snapshot, which is exactly why that
/// snapshot exists: a sale recorded in June under a 5% rule must still explain itself in
/// December after the rule has been superseded, and a panel that re-resolved the rule
/// would quietly restate history as though the new rate had always applied (D-080).
///
/// The distinction the panel is most careful about is `none` versus a configured `0%`.
/// Both produce ₹0 of tax and they are not the same statement: one is a treatment
/// somebody chose, the other is a rate somebody set. Showing "0% GST" for Banquet would
/// describe a rule that does not exist (D-091).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/components/sync_state_chip.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_filters.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_providers.dart';

/// One sale, loaded with its components.
final revenueDetailProvider = FutureProvider.family<RevenueEntry?, String>((
  ref,
  id,
) {
  // Depending on the principal is what makes a user switch re-read rather than serve the
  // previous person's cached projection — the defect D-072a found one layer above the
  // expense read model, arriving here before it can happen again.
  ref.watch(principalProvider);
  return ref.watch(revenueRepositoryProvider).load(id);
});

class RevenueDetailPanel extends ConsumerWidget {
  const RevenueDetailPanel({required this.entryId, super.key});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(revenueDetailProvider(entryId));
    final graph = switch (ref.watch(masterGraphProvider)) {
      AsyncData(:final value) => value,
      _ => MasterGraph.empty(),
    };
    final ledgerRow = switch (ref.watch(filteredRevenueProvider)) {
      AsyncData(:final value) =>
        value.where((r) => r.id == entryId).firstOrNull,
      _ => null,
    };

    return switch (entry) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError() => const _Message(
        key: Key('revenue-detail-error'),
        text: 'This sale could not be read.',
      ),
      AsyncData(value: null) => const _Message(
        key: Key('revenue-detail-missing'),
        text: 'This sale is no longer in the local ledger.',
      ),
      AsyncData(:final value) => _Detail(
        entry: value!,
        graph: graph,
        syncState: ledgerRow?.syncState,
      ),
    };
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.entry,
    required this.graph,
    required this.syncState,
  });

  final RevenueEntry entry;
  final MasterGraph graph;
  final SyncState? syncState;

  @override
  Widget build(BuildContext context) {
    final voided = entry.voidedAt != null;

    return ListView(
      key: const Key('revenue-detail-panel'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
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
            if (syncState != null) SyncStateChip(syncState!),
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
        if (voided && entry.voidReason != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            entry.voidReason!,
            style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
          ),
        ],

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
        // state a rate that was never applied to anything (§14).
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

        const SizedBox(height: AppSpacing.lg),
        Text('Record', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        _Field(label: 'Entered by', value: entry.createdBy ?? '—', dim: true),
        _Field(label: 'Version', value: '${entry.rowVersion}', dim: true),
        // The identity, shown last and marked as what it is. An operator never needs it;
        // somebody diagnosing a sync problem does.
        _Field(label: 'Reference id', value: entry.id, dim: true),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
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

          // The distinction this panel exists to keep. `none` is a treatment somebody
          // chose; `0%` is a rate somebody set. Both give ₹0 and they say different
          // things about the configuration (D-091).
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
            // The rule as it was, not as it is. Re-reading today's configuration here
            // would restate history the moment a rate changed.
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
  final dynamic amount;
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

class _Message extends StatelessWidget {
  const _Message({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.body.copyWith(color: AppColors.inkMuted),
      ),
    ),
  );
}

/// `500` basis points as `5%`, and `250` as `2.5%`.
///
/// Integer arithmetic. A rate that has been through a binary float is no longer the rate
/// that was configured — even in a label, where being approximately right looks exactly
/// like being right.
String _ratePercent(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final fraction = basisPoints % 100;
  if (fraction == 0) return '$whole%';
  final trimmed = fraction % 10 == 0 ? '${fraction ~/ 10}' : '$fraction';
  return '$whole.$trimmed%';
}
