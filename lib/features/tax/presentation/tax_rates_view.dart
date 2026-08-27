/// Tax configuration.
///
/// Rates are shown as a **timeline per revenue category**, because that is what they
/// actually are: a rule that was in force from one date until another. Presenting a
/// single editable "rate" field would invite exactly the mistake the model exists to
/// prevent — overwriting last year's treatment and silently restating history.
///
/// Changing a rate therefore reads as *"from this date, charge this instead"*, and the
/// previous period stays visible and intact underneath.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/master_chrome.dart';
import 'package:uuid/uuid.dart';

class TaxRatesView extends ConsumerWidget {
  const TaxRatesView({required this.isDesktop, super.key});

  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graphAsync = ref.watch(masterGraphProvider);
    final rulesAsync = ref.watch(taxRulesProvider);

    if (graphAsync.isLoading || rulesAsync.isLoading) {
      return const QuietLoading(label: 'Loading tax rules…');
    }
    if (graphAsync.hasError) {
      return MasterErrorState('${graphAsync.error}');
    }
    if (rulesAsync.hasError) {
      return MasterErrorState('${rulesAsync.error}');
    }

    final graph = graphAsync.requireValue;
    final rules = rulesAsync.requireValue;
    final units = graph.businessUnits();

    if (units.isEmpty) {
      return const MasterEmptyState(
        icon: Icons.percent_outlined,
        title: 'No revenue categories yet',
        message:
            'Tax rules attach to revenue categories such as Restaurant or Room.',
      );
    }

    return ListView(
      padding: EdgeInsets.all(isDesktop ? AppSpacing.xxl : AppSpacing.lg),
      children: [
        Text('Tax rules', style: AppTypography.heading),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Each rule applies from a date until the next one begins. Changing a rate '
          'adds a new period — it never edits history.',
          style: AppTypography.bodyMuted,
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final unit in units) ...[
          Text(unit.name.toUpperCase(), style: AppTypography.overline),
          const SizedBox(height: AppSpacing.sm),
          for (final category in graph.revenueCategoriesOf(unit.id))
            _CategoryRules(
              category: category,
              ruleSet: rules[category.id] ?? TaxRuleSet(const []),
              isDesktop: isDesktop,
            ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ],
    );
  }
}

class _CategoryRules extends ConsumerWidget {
  const _CategoryRules({
    required this.category,
    required this.ruleSet,
    required this.isDesktop,
  });

  final MasterNode category;
  final TaxRuleSet ruleSet;
  final bool isDesktop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref
        .watch(principalProvider)
        .canAnywhere(Capability.taxManage);
    final active = ruleSet.active;
    final current = ruleSet.ruleFor(_today());

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.allMedium,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category.name, style: AppTypography.subheading),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        current == null
                            ? 'No rule in force today'
                            : 'Today: ${current.ratePercent} ${current.treatment.label.toLowerCase()}',
                        style: AppTypography.caption.copyWith(
                          color: current == null
                              ? AppColors.caution
                              : AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  TextButton.icon(
                    onPressed: () => _addRule(context, ref, current),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(current == null ? 'Set rate' : 'Change rate'),
                  ),
              ],
            ),
          ),
          if (active.isNotEmpty) const Divider(height: 1),
          for (final rule in active.reversed)
            _RuleRow(rule: rule, isCurrent: rule.id == current?.id),
          if (active.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Text(
                'No tax rule configured. Revenue recorded for this category will have '
                'no tax extracted until one is set.',
                style: AppTypography.caption.copyWith(color: AppColors.caution),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addRule(
    BuildContext context,
    WidgetRef ref,
    TaxRule? current,
  ) async {
    final draft = await TaxRuleEditor.show(
      context,
      categoryName: category.name,
      supersedes: current,
    );
    if (draft == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(taxRepositoryProvider);
    final now = DateTime.now().toUtc();

    try {
      if (current != null && current.isOpenEnded) {
        // Close the running period at the changeover and open the new one, in one
        // transaction — no gap, no overlap, history untouched.
        await repository.supersede(
          currentRuleId: current.id,
          newRuleId: const Uuid().v7(),
          orgId: seedOrgId,
          revenueCategoryId: category.id,
          newRateBasisPoints: draft.rateBasisPoints,
          newTreatment: draft.treatment,
          changeoverDate: draft.effectiveFrom,
          createdBy: ref.read(principalProvider).userId,
          now: now,
        );
      } else {
        await repository.addRule(
          id: const Uuid().v7(),
          orgId: seedOrgId,
          revenueCategoryId: category.id,
          rateBasisPoints: draft.rateBasisPoints,
          treatment: draft.treatment,
          effectiveFrom: draft.effectiveFrom,
          createdBy: ref.read(principalProvider).userId,
          now: now,
        );
      }
      ref.invalidate(taxRulesProvider);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${category.name}: ${draft.ratePercent} '
              '${draft.treatment.label.toLowerCase()} from ${draft.effectiveFrom.iso}.',
            ),
          ),
        );
    } on TaxRuleRejected catch (error) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.refusal.message)));
    }
  }

  static BusinessDate _today() {
    final now = DateTime.now();
    return BusinessDate.of(now.year, now.month, now.day);
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule, required this.isCurrent});

  final TaxRule rule;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: isCurrent ? AppColors.brassWash : null,
        border: const Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              rule.ratePercent,
              style: AppTypography.moneyStrong.copyWith(
                color: isCurrent ? AppColors.ink : AppColors.inkMuted,
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(rule.treatment.label, style: AppTypography.caption),
          ),
          Expanded(
            child: Text(
              rule.isOpenEnded
                  ? 'From ${rule.effectiveFrom.iso}'
                  : '${rule.effectiveFrom.iso} → ${rule.effectiveTo!.iso}',
              style: AppTypography.body.copyWith(
                fontFeatures: AppTypography.tabular,
              ),
            ),
          ),
          if (isCurrent)
            Text(
              'In force',
              style: AppTypography.caption.copyWith(
                color: AppColors.brass,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

/// What the editor returns.
class TaxRuleDraft {
  const TaxRuleDraft({
    required this.rateBasisPoints,
    required this.treatment,
    required this.effectiveFrom,
  });

  final int rateBasisPoints;
  final TaxTreatment treatment;
  final BusinessDate effectiveFrom;

  String get ratePercent => TaxRule(
    id: '',
    revenueCategoryId: '',
    rateBasisPoints: rateBasisPoints,
    treatment: treatment,
    effectiveFrom: effectiveFrom,
  ).ratePercent;
}

class TaxRuleEditor extends StatefulWidget {
  const TaxRuleEditor({required this.categoryName, super.key, this.supersedes});

  final String categoryName;
  final TaxRule? supersedes;

  static Future<TaxRuleDraft?> show(
    BuildContext context, {
    required String categoryName,
    TaxRule? supersedes,
  }) => showDialog<TaxRuleDraft>(
    context: context,
    builder: (_) =>
        TaxRuleEditor(categoryName: categoryName, supersedes: supersedes),
  );

  @override
  State<TaxRuleEditor> createState() => _TaxRuleEditorState();
}

class _TaxRuleEditorState extends State<TaxRuleEditor> {
  final _rate = TextEditingController();
  final _from = TextEditingController();
  TaxTreatment _treatment = TaxTreatment.inclusive;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from.text = BusinessDate.of(now.year, now.month, now.day).iso;
  }

  @override
  void dispose() {
    _rate.dispose();
    _from.dispose();
    super.dispose();
  }

  int? get _rateBasisPoints {
    final value = double.tryParse(_rate.text.trim());
    if (value == null || value < 0 || value > 100) return null;
    return (value * 100).round();
  }

  BusinessDate? get _effectiveFrom => BusinessDate.tryParse(_from.text.trim());

  bool get _canSave => _rateBasisPoints != null && _effectiveFrom != null;

  @override
  Widget build(BuildContext context) {
    final superseded = widget.supersedes;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.allMedium),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.categoryName.toUpperCase(),
            style: AppTypography.overline,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            superseded == null ? 'Set tax rate' : 'Change tax rate',
            style: AppTypography.heading,
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (superseded != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.brassWash,
                    borderRadius: AppRadius.allSmall,
                  ),
                  child: Text(
                    'The current rule (${superseded.ratePercent} '
                    '${superseded.treatment.label.toLowerCase()}, from '
                    '${superseded.effectiveFrom.iso}) will be closed on the date below. '
                    'Revenue already recorded keeps its original treatment.',
                    style: AppTypography.caption,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              TextField(
                controller: _rate,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Rate',
                  suffixText: '%',
                  helperText: 'For example 5, or 12.5',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('TREATMENT', style: AppTypography.overline),
              const SizedBox(height: AppSpacing.xs),
              RadioGroup<TaxTreatment>(
                groupValue: _treatment,
                onChanged: (v) => setState(() => _treatment = v ?? _treatment),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final treatment in TaxTreatment.values)
                      RadioListTile<TaxTreatment>(
                        value: treatment,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: AppColors.brass,
                        title: Text(treatment.label, style: AppTypography.body),
                        subtitle: Text(
                          treatment.entryHint,
                          style: AppTypography.caption,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _from,
                decoration: const InputDecoration(
                  labelText: 'Effective from',
                  helperText: 'YYYY-MM-DD',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brass,
            foregroundColor: AppColors.inkInverse,
          ),
          onPressed: _canSave
              ? () => Navigator.of(context).pop(
                  TaxRuleDraft(
                    rateBasisPoints: _rateBasisPoints!,
                    treatment: _treatment,
                    effectiveFrom: _effectiveFrom!,
                  ),
                )
              : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
