/// The only widget that renders a monetary amount.
///
/// Money is right-aligned with tabular figures so columns line up, and a negative is
/// always marked by its sign or by parentheses — never by colour alone (master spec
/// §20). Colour is an additional cue, not the message.
library;

import 'package:flutter/widgets.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// Whether the amount is tinted by sign.
enum MoneyEmphasis {
  /// Charcoal ink regardless of sign — the default for ordinary amounts, where a
  /// negative is unremarkable.
  neutral,

  /// Tint by sign *in addition to* the sign glyph. For profit and variance figures.
  bySign,
}

class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.formatter = MoneyFormatter.standard,
    this.style,
    this.emphasis = MoneyEmphasis.neutral,
    this.align = TextAlign.right,
    this.semanticPrefix,
  });

  /// A headline figure: larger, whole rupees, tinted by sign.
  const MoneyText.metric(
    this.amount, {
    super.key,
    this.semanticPrefix,
    this.align = TextAlign.right,
  }) : formatter = MoneyFormatter.wholeRupees,
       style = AppTypography.metric,
       emphasis = MoneyEmphasis.bySign;

  final Money amount;
  final MoneyFormatter formatter;
  final TextStyle? style;
  final MoneyEmphasis emphasis;
  final TextAlign align;

  /// Prepended in the accessibility label, e.g. "Operating profit". Screen readers then
  /// announce the figure with its meaning instead of a bare number.
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context) {
    final text = formatter.format(amount);
    final base = style ?? AppTypography.money;

    final resolved = switch (emphasis) {
      MoneyEmphasis.neutral => base,
      MoneyEmphasis.bySign => base.copyWith(
        color: amount.isNegative
            ? AppColors.negative
            : amount.isZero
            ? AppColors.inkMuted
            : AppColors.positive,
      ),
    };

    final label = semanticPrefix == null ? text : '$semanticPrefix: $text';

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Text(
        text,
        style: resolved,
        textAlign: align,
        // Money must never be abbreviated or wrapped: a truncated amount is a wrong
        // amount. Constrain the column instead.
        softWrap: false,
        overflow: TextOverflow.visible,
        maxLines: 1,
      ),
    );
  }
}
