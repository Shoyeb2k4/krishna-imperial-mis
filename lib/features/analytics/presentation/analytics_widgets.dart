/// The ruled financial summary the analysis sections open with (Phase 6 Slice 8).
///
/// A workspace is read, not glanced at, so its summary is a ruled statement — measure,
/// exact figure, movement — rather than another row of hero numbers. Every figure is
/// handed in: the amount is a field of the canonical result and the movement is the one
/// `domain/finance` decided (D-253, D-256), worded by the dashboard's shared presentation.
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';

/// One line of a ruled summary.
@immutable
final class AnalyticsSummaryLine {
  const AnalyticsSummaryLine({
    required this.keyName,
    required this.label,
    required this.amount,
    required this.movement,
    this.strong = false,
  });

  /// Keys are `analytics-$keyName-value`, `analytics-$keyName-movement` and
  /// `analytics-$keyName-movement-note`.
  final String keyName;
  final String label;
  final Money amount;
  final DashboardMovement movement;

  /// The line the others lead to — Net Sales under Gross Sales and GST.
  final bool strong;
}

class AnalyticsRuledSummary extends StatelessWidget {
  const AnalyticsRuledSummary({
    required this.lines,
    required this.comparedWith,
    super.key,
  });

  final List<AnalyticsSummaryLine> lines;

  /// `Compared with 1 Aug 2026 – 19 Aug 2026`, stated once above the movements.
  final String comparedWith;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          children: [
            const Expanded(
              flex: 3,
              child: Text('MEASURE', style: AppTypography.overline),
            ),
            const Expanded(
              flex: 3,
              child: Text(
                'THIS PERIOD',
                style: AppTypography.overline,
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              flex: 5,
              child: Text(
                comparedWith.toUpperCase(),
                key: const Key('analytics-compared-with'),
                style: AppTypography.overline,
              ),
            ),
          ],
        ),
      ),
      for (final line in lines) _SummaryRow(line: line),
    ],
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.line});

  final AnalyticsSummaryLine line;

  @override
  Widget build(BuildContext context) {
    final movement = line.movement;
    return Semantics(
      key: Key('analytics-${line.keyName}'),
      label: dashboardMetricSemantics(
        label: line.label,
        amount: line.amount,
        movement: movement,
        comparedWith: 'the previous period',
      ),
      container: true,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: line.strong
                    ? AppColors.hairlineStrong
                    : AppColors.hairline,
                width: line.strong ? 1.5 : 1,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    line.label,
                    style: line.strong
                        ? AppTypography.subheading
                        : AppTypography.body,
                  ),
                ),
                Expanded(
                  flex: 3,
                  // Money is never truncated or wrapped: at a narrow width the figure
                  // scales down rather than losing a digit (D-269).
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: MoneyText(
                        line.amount,
                        key: Key('analytics-${line.keyName}-value'),
                        style: line.strong
                            ? AppTypography.moneyStrong
                            : AppTypography.money,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movement.text,
                        key: Key('analytics-${line.keyName}-movement'),
                        style: movement.available
                            ? AppTypography.caption.copyWith(
                                color: AppColors.ink,
                              )
                            : AppTypography.caption,
                      ),
                      if (movement.note case final String note)
                        Text(
                          note,
                          key: Key('analytics-${line.keyName}-movement-note'),
                          style: AppTypography.caption,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A statement where a chart is not drawn, saying why. Never an empty plot, which a
/// reader cannot tell apart from a flat zero (D-163).
class AnalyticsNote extends StatelessWidget {
  const AnalyticsNote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.info_outline, size: 16, color: AppColors.inkFaint),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(text, style: AppTypography.bodyMuted)),
    ],
  );
}
