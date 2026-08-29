/// Everything that is not the fast path.
///
/// Closed by default, and a routine ₹500 vegetable purchase never opens it. That is the
/// whole design intent of spec §18: distinguish the fields required for integrity from
/// the useful optional metadata, and never present a wall of fifteen boxes to somebody
/// recording their fortieth entry of the day.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_draft.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/attachment_strip.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/vendor_picker.dart';

class ExpenseOptionalDetails extends ConsumerWidget {
  const ExpenseOptionalDetails({
    required this.draft,
    required this.onChanged,
    super.key,
  });

  final ExpenseDraft draft;
  final void Function(ExpenseDraft Function(ExpenseDraft)) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      // The divider an ExpansionTile draws by default competes with the hairline rules
      // used everywhere else in the design.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('more-details'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
        title: Text('More details', style: AppTypography.subheading),
        subtitle: Text(
          'Vendor, payment, reference, notes and attachments',
          style: AppTypography.caption,
        ),
        children: [
          VendorPicker(
            selectedVendorId: draft.vendorId,
            businessUnitIds: draft.businessUnitIds,
            onChanged: (vendorId) => onChanged(
              (current) => current.copyWith(
                vendorId: vendorId,
                clearVendor: vendorId == null,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _PaymentSection(draft: draft, onChanged: onChanged),
          const SizedBox(height: AppSpacing.lg),
          _TextRow(
            fieldKey: const Key('expense-reference'),
            label: 'Invoice / reference number',
            initial: draft.referenceNumber,
            onChanged: (value) => onChanged(
              (current) => current.copyWith(referenceNumber: value),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _TextRow(
            fieldKey: const Key('expense-notes'),
            label: 'Notes',
            initial: draft.notes,
            maxLines: 3,
            onChanged: (value) =>
                onChanged((current) => current.copyWith(notes: value)),
          ),
          const SizedBox(height: AppSpacing.lg),
          AttachmentStrip(
            expenseId: draft.id,
            attachments: draft.attachments,
            onChanged: (attachments) => onChanged(
              (current) => current.copyWith(attachments: attachments),
            ),
          ),
        ],
      ),
    );
  }
}

/// Unpaid or paid, and what paid needs.
///
/// The accounting period is not here and is not affected by anything here: June salary
/// paid on 5 July is a June cost and a July payment, and the two never move each other
/// (D-016).
class _PaymentSection extends ConsumerWidget {
  const _PaymentSection({required this.draft, required this.onChanged});

  final ExpenseDraft draft;
  final void Function(ExpenseDraft Function(ExpenseDraft)) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paid = draft.paymentStatus == PaymentStatus.paid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PAYMENT', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<PaymentStatus>(
          segments: const [
            ButtonSegment(value: PaymentStatus.unpaid, label: Text('Unpaid')),
            ButtonSegment(value: PaymentStatus.paid, label: Text('Paid')),
          ],
          selected: {draft.paymentStatus},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            final status = selection.first;
            onChanged(
              (current) => current.copyWith(
                paymentStatus: status,
                // Unpaid carries neither a date nor a method — the database refuses the
                // half-state, and so does the form.
                clearPayment: status == PaymentStatus.unpaid,
              ),
            );
          },
        ),
        if (paid) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _DateRow(
                  label: 'Paid on',
                  date: draft.paymentDate,
                  onChanged: (date) => onChanged(
                    (current) => current.copyWith(paymentDate: date),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _PaymentMethodRow(
                  selected: draft.paymentMethodId,
                  onChanged: (id) => onChanged(
                    (current) => current.copyWith(paymentMethodId: id),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'When it was paid. Which period it belongs to is unchanged.',
            style: AppTypography.caption,
          ),
        ],
      ],
    );
  }
}

class _PaymentMethodRow extends ConsumerWidget {
  const _PaymentMethodRow({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(paymentMethodsProvider);
    return methods.when(
      loading: () => const SizedBox(height: 48),
      error: (_, _) => const SizedBox(height: 48),
      data: (rows) => DropdownButtonFormField<String>(
        key: const Key('payment-method'),
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'How',
          border: OutlineInputBorder(borderRadius: AppRadius.allSmall),
        ),
        items: [
          for (final method in rows)
            DropdownMenuItem(value: method.id, child: Text(method.name)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.date,
    required this.onChanged,
  });

  final String label;
  final BusinessDate? date;
  final ValueChanged<BusinessDate> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const Key('payment-date'),
    onTap: () async {
      final now = DateTime.now();
      final initial = date ?? BusinessDate.of(now.year, now.month, now.day);
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.utc(initial.year, initial.month, initial.day),
        firstDate: DateTime.utc(2020),
        lastDate: DateTime.utc(2100),
        helpText: label,
      );
      if (picked != null) {
        onChanged(BusinessDate.of(picked.year, picked.month, picked.day));
      }
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(borderRadius: AppRadius.allSmall),
      ),
      child: Text(date?.iso ?? 'Choose', style: AppTypography.body),
    ),
  );
}

class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.label,
    required this.onChanged,
    this.initial,
    this.maxLines = 1,
    this.fieldKey,
  });

  final String label;
  final String? initial;
  final int maxLines;
  final ValueChanged<String> onChanged;

  /// Addresses this field by name rather than by position.
  ///
  /// The optional-details section is progressive disclosure whose contents grow, so a
  /// test that reached the notes field by index would silently start editing something
  /// else the day a field is inserted above it.
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    initialValue: initial,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(borderRadius: AppRadius.allSmall),
    ),
    onChanged: onChanged,
  );
}
