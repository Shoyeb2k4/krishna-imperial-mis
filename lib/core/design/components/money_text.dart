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
        breakableAtDigitGroups(text),
        style: resolved,
        textAlign: align,
        // Money is never abbreviated, ellipsised, clipped or shrunk: a truncated amount
        // is a wrong amount. Layouts give way instead — a figure moves to its own line
        // (D-286). Only when the whole figure is wider than that line may it break, and
        // then only between digit groups, at full size (the project lead's ruling on
        // D-286).
        softWrap: true,
        overflow: TextOverflow.visible,
      ),
    );
  }
}

/// A zero-width space: an invisible place a line may break.
const String _breakHere = '\u200B';

/// A word joiner: an invisible place a line may not break.
const String _neverBreakHere = '\u2060';

/// [figure] as it is printed, with the only line-break opportunities it may use placed
/// after the commas between digit groups: `₹1,66,` then `383.00`, never `₹1,66,38` then
/// `3.00`, and never between a sign and the rupee symbol. On one line it reads exactly
/// as [figure], because both marks are invisible.
String breakableAtDigitGroups(String figure) => figure
    .replaceAll(',', ',$_breakHere')
    .replaceAll('-', '-$_neverBreakHere')
    .replaceAll('+', '+$_neverBreakHere');

/// [shown] with the invisible break marks removed: the figure as a person reads it.
String withoutBreakMarks(String shown) =>
    shown.replaceAll(_breakHere, '').replaceAll(_neverBreakHere, '');
