/// A single headline financial figure with its label and provenance.
///
/// Deliberately not a rounded stat card: a hairline rule, a tracked label, and a large
/// tabular number. Every metric states what it is and, where relevant, how fresh it is.
library;

import 'package:flutter/widgets.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

class MetricBlock extends StatelessWidget {
  const MetricBlock({
    required this.label,
    required this.amount,
    super.key,
    this.caption,
    this.emphasis = MoneyEmphasis.neutral,
    this.onTap,
  });

  final String label;
  final Money amount;

  /// Context under the figure — the period, the comparison, or the freshness state.
  final String? caption;
  final MoneyEmphasis emphasis;

  /// Every summarised figure should lead somewhere (master spec §11). A metric with no
  /// destination is the exception, not the rule.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        MoneyText(
          amount,
          style: AppTypography.metric,
          emphasis: emphasis,
          align: TextAlign.left,
          semanticPrefix: label,
        ),
        if (caption != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(caption!, style: AppTypography.caption),
        ],
      ],
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.hairlineStrong, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.md,
          bottom: AppSpacing.sm,
        ),
        child: onTap == null
            ? content
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: content,
              ),
      ),
    );
  }
}
