/// Splitting an expense: between properties, and across accounting periods.
///
/// Both editors follow the same rule, and it is the only rule that matters here:
/// **the software never balances the money for you.** `Remaining` is shown, Save stays
/// disabled until it is exactly zero, and no adjustment line, rounding row or hidden
/// correction is ever added. If ₹25,000 and ₹32,000 are entered against ₹58,000, the
/// answer is "₹1,000 remaining" — a fact for the user to resolve, not a gap for the
/// application to paper over.
///
/// The period helper may *propose* an even division, because staring at ₹60,000 and two
/// months is tedious. It proposes with largest-remainder so the suggestion already
/// reconciles to the paisa, it shows every figure before anything is saved, and every
/// figure remains editable. Nothing is applied silently (D-034).
library;

import 'package:flutter/material.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_draft.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/amount_field.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/classification_picker.dart';

/// The reconciliation line. The single most important thing on a split form.
class RemainingBanner extends StatelessWidget {
  const RemainingBanner({
    required this.allocated,
    required this.remaining,
    super.key,
    this.label = 'Allocated',
  });

  final Money allocated;
  final Money remaining;
  final String label;

  @override
  Widget build(BuildContext context) {
    final balanced = remaining.isZero;
    final over = remaining.isNegative;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: balanced ? AppColors.brassWash : AppColors.surfaceMuted,
        borderRadius: AppRadius.allSmall,
        border: Border.all(
          color: balanced ? AppColors.brassMuted : AppColors.hairlineStrong,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: AppTypography.overline),
                const SizedBox(height: AppSpacing.xxs),
                MoneyText(allocated, align: TextAlign.left),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                balanced
                    ? 'BALANCED'
                    : over
                    ? 'OVER BY'
                    : 'REMAINING',
                style: AppTypography.overline.copyWith(
                  color: balanced ? AppColors.positive : AppColors.caution,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              // Never colour alone: the label above says which way it is out.
              MoneyText(
                balanced ? Money.zero : (over ? -remaining : remaining),
                key: const Key('remaining-amount'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The split-between-properties editor.
class AllocationEditor extends StatelessWidget {
  const AllocationEditor({
    required this.draft,
    required this.graph,
    required this.principal,
    required this.onChanged,
    super.key,
  });

  final ExpenseDraft draft;
  final MasterGraph graph;
  final Principal principal;

  /// Describes a change rather than handing over a finished draft, so a callback
  /// that outlives one build cannot apply it to a stale value.
  final void Function(ExpenseDraft Function(ExpenseDraft)) onChanged;

  /// A user who may charge exactly one property has that property fixed on every line,
  /// so the situation where they choose one they cannot use never arises.
  String? get _lockedUnit {
    final units = ExpenseDraft.selectableUnits(graph, principal);
    return units.length == 1 ? units.single.id : null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RemainingBanner(allocated: draft.allocated, remaining: draft.remaining),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < draft.allocations.length; i++) ...[
          _AllocationCard(
            index: i,
            line: draft.allocations[i],
            graph: graph,
            principal: principal,
            canRemove: draft.allocations.length > 1,
            lockedBusinessUnitId: _lockedUnit,
            onClassification:
                ({
                  String? businessUnitId,
                  String? departmentId,
                  String? sectionId,
                  String? categoryId,
                }) => onChanged(
                  (current) => current.withClassification(
                    draft.allocations[i].id,
                    businessUnitId: businessUnitId,
                    departmentId: departmentId,
                    sectionId: sectionId,
                    categoryId: categoryId,
                  ),
                ),
            onAmount: (amount) => onChanged(
              (current) =>
                  current.withAllocationAmount(draft.allocations[i].id, amount),
            ),
            onRemove: () => onChanged(
              (current) => current.removeAllocation(draft.allocations[i].id),
            ),
            onPeriodsChanged: onChanged,
            draft: draft,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        // Wrap, not Row: on a phone the two labels do not fit side by side, and an
        // overflow here would obscure the remaining-amount banner above it.
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            TextButton.icon(
              key: const Key('add-allocation'),
              onPressed: () => onChanged((current) => current.addAllocation()),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add allocation'),
            ),
            TextButton.icon(
              onPressed: () => onChanged(
                (current) => current.addAllocation(copyClassification: true),
              ),
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              label: const Text('Same classification'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AllocationCard extends StatelessWidget {
  const _AllocationCard({
    required this.index,
    required this.line,
    required this.graph,
    required this.principal,
    required this.canRemove,
    required this.onClassification,
    required this.onAmount,
    required this.onRemove,
    required this.onPeriodsChanged,
    required this.draft,
    this.lockedBusinessUnitId,
  });

  final int index;
  final AllocationDraft line;
  final MasterGraph graph;
  final Principal principal;
  final bool canRemove;
  final ClassificationChange onClassification;
  final ValueChanged<Money?> onAmount;
  final VoidCallback onRemove;
  final void Function(ExpenseDraft Function(ExpenseDraft)) onPeriodsChanged;
  final ExpenseDraft draft;
  final String? lockedBusinessUnitId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: AppRadius.allSmall,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('ALLOCATION ${index + 1}', style: AppTypography.overline),
              const Spacer(),
              if (canRemove)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Remove this allocation',
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClassificationRow(
            line: line,
            graph: graph,
            principal: principal,
            lockedBusinessUnitId: lockedBusinessUnitId,
            onChanged: onClassification,
          ),
          const SizedBox(height: AppSpacing.md),
          AmountField(
            key: Key('allocation-amount-${line.id}'),
            label: 'Amount for this allocation',
            initial: line.amount,
            compact: true,
            onChanged: onAmount,
          ),
          if (ExpenseDraft.mayUsePeriodSplit(principal)) ...[
            const SizedBox(height: AppSpacing.md),
            PeriodSplitEditor(
              draft: draft,
              line: line,
              onChanged: onPeriodsChanged,
            ),
          ],
        ],
      ),
    );
  }
}

/// The split-across-accounting-periods editor for one allocation line.
///
/// Deliberately closed by default and entirely out of the routine path: an ordinary
/// expense never sees it, and the ordinary default rule applies to it silently.
class PeriodSplitEditor extends StatelessWidget {
  const PeriodSplitEditor({
    required this.draft,
    required this.line,
    required this.onChanged,
    super.key,
  });

  final ExpenseDraft draft;
  final AllocationDraft line;

  /// Describes a change rather than handing over a finished draft, so a callback
  /// that outlives one build cannot apply it to a stale value.
  final void Function(ExpenseDraft Function(ExpenseDraft)) onChanged;

  @override
  Widget build(BuildContext context) {
    if (!line.hasPeriodSplit) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: Key('open-period-split-${line.id}'),
          onPressed: line.amount == null
              ? null
              : () => onChanged((current) => _propose(current, line)),
          icon: const Icon(Icons.date_range_outlined, size: 16),
          label: const Text('Split across accounting periods'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Text('ACCOUNTING PERIODS', style: AppTypography.overline),
            const Spacer(),
            TextButton(
              key: Key('clear-period-split-${line.id}'),
              onPressed: () =>
                  onChanged((current) => current.clearPeriodSplit(line.id)),
              child: const Text('Remove split'),
            ),
          ],
        ),
        Text(
          'Proposed evenly. Change any figure — the split must add up to the '
          'line exactly.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final split in line.periodSplits)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_monthLabel(split.end), style: AppTypography.body),
                      Text(
                        '${split.start.iso} – ${split.end.iso}',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 3,
                  child: AmountField(
                    key: Key('period-amount-${split.id}'),
                    label: '',
                    initial: split.amount,
                    compact: true,
                    onChanged: (amount) => onChanged(
                      (current) =>
                          current.withPeriodAmount(line.id, split.id, amount),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (line.splitRemaining case final remaining?)
          RemainingBanner(
            key: Key('period-remaining-${line.id}'),
            label: 'Split across periods',
            allocated: line.splitTotal,
            remaining: remaining,
          ),
      ],
    );
  }

  /// Two months around the business date, as a starting suggestion.
  ///
  /// The commonest real case is a utility bill spanning a month boundary. The user edits
  /// the dates and the figures; nothing here is a rule.
  static ExpenseDraft _propose(ExpenseDraft draft, AllocationDraft line) {
    final anchor = draft.accountingPeriodEnd ?? draft.businessDate;
    final previousMonthEnd = BusinessDate.of(
      anchor.year,
      anchor.month,
      1,
    ).addDays(-1);
    return draft.proposePeriodSplit(line.id, [
      (
        start: BusinessDate.of(
          previousMonthEnd.year,
          previousMonthEnd.month,
          1,
        ),
        end: previousMonthEnd,
      ),
      (start: BusinessDate.of(anchor.year, anchor.month, 1), end: anchor),
    ]);
  }

  static String _monthLabel(BusinessDate date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}
