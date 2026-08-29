/// Voiding an expense.
///
/// Deliberate by construction. A confirmation, a reason that must be typed, and no
/// default text offered — a pre-filled "Correction" would be the reason on every void in
/// the system within a month, and the reason is the only part of a void that explains
/// anything later.
///
/// The document is not deleted. It stays in the ledger, marked VOIDED, out of every
/// aggregate and reachable through the "Include voided" filter, because financial history
/// is corrected by reversal and never by removal (D-006).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';

Future<void> showVoidDialog(
  BuildContext context,
  WidgetRef ref,
  LocalExpense expense,
) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => _VoidDialog(reference: expense.displayReference),
  );
  if (reason == null || reason.trim().isEmpty) return;

  final outcome = await ref
      .read(expenseVoidControllerProvider)
      .voidExpense(expense, reason: reason.trim());

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        outcome
            ? 'Voided · queued for the server'
            : 'Could not void this expense. Nothing has been changed.',
      ),
      backgroundColor: AppColors.ink,
    ),
  );
}

class _VoidDialog extends StatefulWidget {
  const _VoidDialog({required this.reference});
  final String reference;

  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasReason = _controller.text.trim().isNotEmpty;

    return AlertDialog(
      backgroundColor: AppColors.paper,
      title: Text('Void ${widget.reference}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The expense stays in the ledger, marked VOIDED, and leaves every '
            'report. It cannot be changed afterwards — a correction is a new '
            'expense.',
            style: AppTypography.bodyMuted,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            key: const Key('void-reason'),
            controller: _controller,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason (required)',
              // No hint that could become the reason on every void in the system.
              border: OutlineInputBorder(borderRadius: AppRadius.allSmall),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep it'),
        ),
        FilledButton(
          key: const Key('confirm-void'),
          onPressed: hasReason
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.negative,
            foregroundColor: AppColors.inkInverse,
          ),
          child: const Text('Void expense'),
        ),
      ],
    );
  }
}
