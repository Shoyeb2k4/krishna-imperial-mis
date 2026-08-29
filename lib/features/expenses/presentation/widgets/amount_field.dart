/// Indian money, typed.
///
/// One job, done exactly: read what somebody types into integer paise, or refuse it.
/// There is no `double` anywhere in this file, and none in the value it produces — a
/// rupee amount that has been through a binary float is no longer the amount that was
/// typed, and this is where that would happen if it happened anywhere.
///
/// The confirmation line underneath is the point of the widget. `12500` is ambiguous
/// until it reads back as `₹12,500`, and `12500.50` is ambiguous until it reads back as
/// `₹12,500.50`. Indian grouping, so a lakh looks like a lakh.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

class AmountField extends StatefulWidget {
  const AmountField({
    required this.onChanged,
    super.key,
    this.initial,
    this.label = 'Amount',
    this.autofocus = false,
    this.compact = false,
    this.enabled = true,
  });

  /// Null means "not a readable amount". Deliberately not zero: an empty box and a
  /// deliberate nought are different statements.
  final ValueChanged<Money?> onChanged;

  final Money? initial;
  final String label;
  final bool autofocus;
  final bool compact;
  final bool enabled;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final TextEditingController _controller;
  Money? _parsed;
  bool _malformed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial == null
          ? ''
          : MoneyFormatter.plain.format(widget.initial!),
    );
    _parsed = widget.initial;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handle(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _parsed = null;
        _malformed = false;
      });
      widget.onChanged(null);
      return;
    }
    final money = Money.tryParse(trimmed);
    setState(() {
      _parsed = money;
      // Anything unreadable is *said* to be unreadable. Three decimal places are not
      // quietly rounded to two — the user is told the figure was not understood.
      _malformed = money == null;
    });
    widget.onChanged(money);
  }

  @override
  Widget build(BuildContext context) {
    final confirmation = switch ((_parsed, _malformed)) {
      (final Money money, _) when money.isPositive => (
        MoneyFormatter.entry.format(money),
        AppColors.inkMuted,
      ),
      (final Money money, _) when !money.isPositive => (
        'An expense must be more than zero',
        AppColors.negative,
      ),
      (_, true) => ('That is not an amount this can read', AppColors.negative),
      _ => ('', AppColors.inkMuted),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label.toUpperCase(), style: AppTypography.overline),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _controller,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          inputFormatters: [
            // Digits, one decimal point, and the separators a user may paste. Everything
            // else is rejected at the keystroke rather than at Save.
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,₹ ]')),
          ],
          style: (widget.compact ? AppTypography.body : AppTypography.display)
              .copyWith(fontFeatures: AppTypography.tabular),
          decoration: InputDecoration(
            prefixText: '₹ ',
            prefixStyle:
                (widget.compact ? AppTypography.body : AppTypography.display)
                    .copyWith(color: AppColors.inkFaint),
            hintText: '0',
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: widget.compact ? AppSpacing.sm : AppSpacing.md,
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: AppRadius.allSmall,
              borderSide: BorderSide(color: AppColors.hairline),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: AppRadius.allSmall,
              borderSide: BorderSide(color: AppColors.brass, width: 1.5),
            ),
            errorBorder: const OutlineInputBorder(
              borderRadius: AppRadius.allSmall,
              borderSide: BorderSide(color: AppColors.negative),
            ),
          ),
          onChanged: _handle,
        ),
        if (confirmation.$1.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            confirmation.$1,
            key: const Key('amount-confirmation'),
            style: AppTypography.caption.copyWith(color: confirmation.$2),
          ),
        ],
      ],
    );
  }
}
