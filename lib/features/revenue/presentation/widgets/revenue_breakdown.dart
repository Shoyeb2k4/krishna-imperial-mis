/// What the entered figure actually means, shown before it is saved.
///
/// The point of this widget is that nobody has to trust it. `₹1,00,000` of restaurant
/// sales is not ₹1,00,000 of revenue — it is ₹95,238.10 of net sales and ₹4,761.90 of GST
/// already inside the customer's bill — and an operator who cannot see that will
/// eventually assume the wrong one. So the three figures are shown plainly, before Save,
/// and they are the figures that will be stored.
///
/// **No arithmetic happens here.** Every number arrives already computed by
/// `TaxRule.compute`, which is the canonical specification and is proven equal to
/// `app.revenue_compute` to the paise (D-105). This file formats; it does not calculate.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_draft.dart';

class RevenueBreakdown extends StatelessWidget {
  const RevenueBreakdown({required this.preview, super.key});

  final RevenuePreview preview;

  @override
  Widget build(BuildContext context) {
    if (!preview.isResolved) return const SizedBox.shrink();

    // Nothing typed yet. Showing three zeroes would be a claim about a day nobody has
    // described, so the space stays quiet until there is something to say.
    if (!preview.isComplete) {
      return Container(
        key: const Key('revenue-breakdown-empty'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: AppRadius.allSmall,
        ),
        child: Text(
          preview.lines.length > 1
              ? 'Enter each amount to see the sales breakdown.'
              : 'Enter the amount to see the sales breakdown.',
          style: AppTypography.caption.copyWith(color: AppColors.inkMuted),
        ),
      );
    }

    final taxed = preview.carriesTax;

    return Container(
      key: const Key('revenue-breakdown'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.allSmall,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          _Line(
            keyName: 'revenue-preview-gross',
            label: 'Sales total',
            amount: preview.gross,
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.hairline),

          // An untaxed category says so in words. "GST ₹0" reads like an amount that
          // happened to come out at nothing; "No GST" is the statement the configuration
          // actually makes (D-091).
          if (taxed)
            _Line(
              keyName: 'revenue-preview-tax',
              label: 'GST included',
              amount: preview.tax,
              muted: true,
            )
          else
            Row(
              key: const Key('revenue-preview-no-gst'),
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'GST',
                  style: AppTypography.body.copyWith(color: AppColors.inkMuted),
                ),
                Text(
                  'No GST',
                  style: AppTypography.body.copyWith(color: AppColors.inkMuted),
                ),
              ],
            ),

          const Divider(height: AppSpacing.lg, color: AppColors.hairline),
          _Line(
            keyName: 'revenue-preview-net',
            label: 'Net sales',
            amount: preview.net,
            emphasised: true,
          ),

          // Per-band detail, only where there is more than one figure to explain. With a
          // single component the totals above already say everything.
          if (preview.lines.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: AppSpacing.sm),
            for (final line in preview.lines)
              if (line.computed != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${line.rule.valueBandLabel ?? 'Amount'} · '
                          '${_ratePercent(line.rule.rateBasisPoints)}',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                      MoneyText(
                        line.computed!.net,
                        formatter: MoneyFormatter.standard,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }

  /// `500` basis points as `5%`, and `250` as `2.5%`.
  ///
  /// Integer arithmetic, because a rate that has been through a binary float is no longer
  /// the rate that was configured — even in a label, where being approximately right
  /// looks exactly like being right.
  static String _ratePercent(int basisPoints) {
    final whole = basisPoints ~/ 100;
    final fraction = basisPoints % 100;
    if (fraction == 0) return '$whole%';
    final trimmed = fraction % 10 == 0 ? '${fraction ~/ 10}' : '$fraction';
    return '$whole.$trimmed%';
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.keyName,
    required this.label,
    required this.amount,
    this.muted = false,
    this.emphasised = false,
  });

  final String keyName;
  final String label;
  final dynamic amount;
  final bool muted;
  final bool emphasised;

  @override
  Widget build(BuildContext context) => Row(
    key: Key(keyName),
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: AppTypography.body.copyWith(
          color: muted ? AppColors.inkMuted : AppColors.ink,
        ),
      ),
      MoneyText(
        amount,
        formatter: MoneyFormatter.standard,
        style: (emphasised ? AppTypography.subheading : AppTypography.body)
            .copyWith(color: muted ? AppColors.inkMuted : AppColors.ink),
      ),
    ],
  );
}
