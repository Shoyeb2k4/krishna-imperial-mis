/// The single place in the application where a monetary amount becomes text.
///
/// No widget, report, export or log may format money itself. Indian digit grouping
/// (₹12,36,420 — never ₹1,236,420) is implemented once, here, and unit tested across
/// lakh and crore boundaries, negatives and zero.
library;

import 'package:krishna_mis/domain/value_objects/money.dart';

/// Whether the paise part is shown.
enum MoneyDecimals {
  /// Always two decimal places: `₹12,36,420.00`.
  always,

  /// Never shown. The amount is rounded half-up-away-from-zero to whole rupees for
  /// display only. Use for headline figures, never for a column that must foot.
  never,

  /// Two places only when the amount is not a whole number of rupees.
  whenPresent,
}

/// How a negative amount is marked.
///
/// Profit and loss are never distinguished by colour alone (master spec §20), so a
/// negative always carries a visible mark of its own.
enum MoneySignStyle {
  /// `-₹1,200.00`
  minus,

  /// `(₹1,200.00)` — conventional in financial statements.
  parentheses,

  /// `+₹1,200.00` / `-₹1,200.00`, and no sign at all on zero.
  ///
  /// For a **movement** rather than a balance: period-over-period change, where the
  /// direction is the point and an unsigned rise reads as a total (Phase 6 Slice 6).
  explicit,
}

/// Formats [Money] for display. Stateless and pure; safe to use anywhere.
final class MoneyFormatter {
  const MoneyFormatter({
    this.decimals = MoneyDecimals.always,
    this.signStyle = MoneySignStyle.minus,
    this.symbol = '₹',
    this.showSymbol = true,
  });

  final MoneyDecimals decimals;
  final MoneySignStyle signStyle;
  final String symbol;
  final bool showSymbol;

  /// Two-decimal money, the default for tables and any column that must add up.
  static const MoneyFormatter standard = MoneyFormatter();

  /// Whole-rupee money for headline metrics. Rounds for display only.
  static const MoneyFormatter wholeRupees = MoneyFormatter(
    decimals: MoneyDecimals.never,
  );

  /// Accounting style: negatives in parentheses.
  static const MoneyFormatter accounting = MoneyFormatter(
    signStyle: MoneySignStyle.parentheses,
  );

  /// A period-over-period movement: `+₹1,200.00`, `-₹1,200.00`, `₹0.00`.
  static const MoneyFormatter movement = MoneyFormatter(
    signStyle: MoneySignStyle.explicit,
  );

  /// Bare digits with no currency symbol, for spreadsheet cells that carry their own
  /// currency formatting.
  static const MoneyFormatter plain = MoneyFormatter(showSymbol: false);

  /// Confirmation of what somebody just typed: paise only when they typed paise.
  ///
  /// `12500` reads back as `₹12,500` and `12500.50` as `₹12,500.50`. Padding the first
  /// to `₹12,500.00` invites the reader to check whether the two zeros were theirs.
  static const MoneyFormatter entry = MoneyFormatter(
    decimals: MoneyDecimals.whenPresent,
  );

  String format(Money money) {
    final negative = money.isNegative;
    final magnitude = money.absolute;

    final String digits;
    switch (decimals) {
      case MoneyDecimals.never:
        // Round to whole rupees using the same explicit policy as the domain layer.
        final rupees = magnitude.multiplyByRatio(1, 100).paise;
        digits = _groupIndian(rupees.toString());
      case MoneyDecimals.always:
        digits = _withPaise(magnitude);
      case MoneyDecimals.whenPresent:
        digits = magnitude.paiseRemainder == 0
            ? _groupIndian(magnitude.wholeRupees.toString())
            : _withPaise(magnitude);
    }

    final body = showSymbol ? '$symbol$digits' : digits;
    if (!negative) {
      // A zero movement has no direction, so it carries no sign.
      return signStyle == MoneySignStyle.explicit && !money.isZero
          ? '+$body'
          : body;
    }

    return switch (signStyle) {
      MoneySignStyle.minus || MoneySignStyle.explicit => '-$body',
      MoneySignStyle.parentheses => '($body)',
    };
  }

  String _withPaise(Money magnitude) {
    final rupees = _groupIndian(magnitude.wholeRupees.toString());
    final paise = magnitude.paiseRemainder.toString().padLeft(2, '0');
    return '$rupees.$paise';
  }

  /// Indian digit grouping: the last three digits, then groups of two.
  ///
  /// `1236420` → `12,36,420`   (twelve lakh thirty-six thousand four hundred twenty)
  /// `10000000` → `1,00,00,000` (one crore)
  static String _groupIndian(String digits) {
    if (digits.length <= 3) return digits;

    final lastThree = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);

    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);

    return '${groups.join(',')},$lastThree';
  }
}
