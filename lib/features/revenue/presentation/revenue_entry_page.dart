/// Recording a day's sales.
///
/// Built for the thing that happens every evening: pick the property, pick the category,
/// type one figure, check the breakdown, Save. Four taps and a number. Entry kind, source
/// reference and notes are behind **More details**, closed, and a routine user never
/// opens them.
///
/// Two things about this screen are not cosmetic.
///
/// **The form's shape comes from the configuration.** How many amount fields there are,
/// and what each is labelled, is read from the rules that resolve for this category on
/// this business date. Room shows one field today because one generic rule is configured;
/// the day two tariff bands are configured it shows two, correctly labelled, with no
/// release (D-081). Nothing here knows a threshold, and nothing here decides a rate.
///
/// **The preview is the record.** The figures under the amount field come from
/// `TaxRule.compute` — the same call the repository makes when it writes, and the same
/// arithmetic `app.revenue_compute` is proven equal to (D-105). They cannot disagree,
/// because they are one function called twice rather than two that happen to agree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/tokens/app_tokens.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/amount_field.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_draft.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_providers.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_breakdown.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_optional_details.dart';

class RevenueEntryPage extends ConsumerStatefulWidget {
  const RevenueEntryPage({super.key}) : editingDraft = null;

  /// The same form, opened on an existing sale.
  ///
  /// One form, two modes — deliberately, and for the reason D-072a gives for expenses: a
  /// second screen would be a second implementation of the arithmetic behind company
  /// revenue, and the two would agree until the day they did not. The tax preview, the
  /// band fields, the reconciliation and the refusals are the ones that already decide
  /// what a new sale may be.
  ///
  /// [draft] carries the row version it was opened on, and nothing in this screen can
  /// move it (§4).
  const RevenueEntryPage.editing(RevenueDraft draft, {super.key})
    : editingDraft = draft;

  final RevenueDraft? editingDraft;

  bool get isEditing => editingDraft != null;

  @override
  ConsumerState<RevenueEntryPage> createState() => _RevenueEntryPageState();
}

class _RevenueEntryPageState extends ConsumerState<RevenueEntryPage> {
  RevenueDraft? _draft;

  /// True from the moment Save is pressed until the local transaction has committed and
  /// the screen has decided what to do next.
  ///
  /// This is the whole of the double-submission defence, and deliberately so: there is no
  /// second deduplication algorithm here. The identity is the draft's own UUID and the
  /// idempotency key is the mutation id, both generated once — so even if two saves
  /// somehow raced, the server would replay rather than record twice (D-004). This flag
  /// exists to stop the *interface* doing something confusing, not to stop the database
  /// doing something wrong.
  bool _saving = false;

  String? _refusalMessage;
  bool _refusalCanRefresh = false;

  RevenueDraft _ensureDraft(MasterGraph graph) {
    final existing = _draft;
    if (existing != null) return existing;

    // Editing starts from the document as it was read, version and all.
    final editing = widget.editingDraft;
    if (editing != null) {
      _draft = editing;
      return editing;
    }

    final authority = ref.read(revenueAuthorityProvider);
    final units = RevenueDraft.permittedUnits(graph, authority);

    // One property: preselect it and skip a choice that has only one answer. Several:
    // ask, because guessing which property a figure belongs to is not a convenience.
    final created = RevenueDraft.blank(
      businessDate: ref.read(currentBusinessDateProvider),
      businessUnitId: units.length == 1 ? units.single.id : null,
    );
    _draft = created;
    return created;
  }

  void _update(RevenueDraft next) {
    setState(() {
      _draft = next;
      // Any change to the form invalidates a refusal that was about the old one.
      _refusalMessage = null;
      _refusalCanRefresh = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final graphAsync = ref.watch(masterGraphProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Correct this sale' : 'Record sales'),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: graphAsync.when(
        loading: () => const _Centered(child: CircularProgressIndicator()),
        error: (_, _) => const _Centered(
          child: _Message(
            key: Key('revenue-entry-masters-error'),
            icon: Icons.cloud_off_outlined,
            title: 'Cannot load your properties',
            body:
                'Connect to the internet and try again. Nothing has been lost.',
          ),
        ),
        data: (graph) => _form(graph),
      ),
    );
  }

  Widget _form(MasterGraph graph) {
    final authority = ref.watch(revenueAuthorityProvider);
    final units = RevenueDraft.permittedUnits(graph, authority);

    if (units.isEmpty) {
      return const _Centered(
        child: _Message(
          key: Key('revenue-entry-no-scope'),
          icon: Icons.lock_outline,
          title: 'No properties available',
          body:
              'You do not have permission to record sales for any property. '
              'Ask the Owner to grant access.',
        ),
      );
    }

    final draft = _ensureDraft(graph);
    final categories = draft.categoriesFor(graph);
    final unitId = draft.businessUnitId;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _BusinessDateLine(date: draft.businessDate),
        const SizedBox(height: AppSpacing.lg),

        if (units.length > 1) ...[
          _UnitPicker(
            units: units,
            selected: unitId,
            onChanged: (id) => _update(draft.withBusinessUnit(id)),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        if (unitId != null) ...[
          _CategoryPicker(
            categories: categories,
            selected: draft.revenueCategoryId,
            onChanged: (id) => _update(draft.withCategory(id)),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],

        if (unitId != null && draft.revenueCategoryId != null)
          _AmountsAndBreakdown(
            draft: draft,
            unitId: unitId,
            onAmountChanged: (componentId, amount) =>
                _update(draft.withAmount(componentId, amount)),
            onComponentsResolved: (next) {
              // Re-shaping the form is a build-time consequence of the configuration, so
              // it is applied after the frame rather than during it.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !identical(next, _draft)) {
                  setState(() => _draft = next);
                }
              });
            },
            onSaveable: (canSave, preview) => _saveBar(draft, canSave, preview),
          ),
      ],
    );
  }

  Widget _saveBar(RevenueDraft draft, bool canSave, RevenuePreview preview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        RevenueOptionalDetails(
          draft: draft,
          onChanged: (next) => _update(next),
        ),
        const SizedBox(height: AppSpacing.lg),

        if (_refusalMessage != null) ...[
          _RefusalBanner(
            message: _refusalMessage!,
            onRefresh: _refusalCanRefresh ? _refresh : null,
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        FilledButton(
          key: const Key('revenue-save'),
          // Disabled while the transaction runs. A second press cannot start a second
          // save, and cannot start a second document either — see [_saving].
          onPressed: canSave && !_saving ? () => _save(draft) : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.inkInverse,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          ),
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.inkInverse,
                  ),
                )
              : Text(widget.isEditing ? 'Save changes' : 'Save sales'),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Future<void> _refresh() async {
    final unitId = _draft?.businessUnitId;
    if (unitId == null) return;

    setState(() => _saving = true);
    final usable = await ref
        .read(revenueEntryControllerProvider)
        .refreshConfiguration(unitId);
    if (!mounted) return;

    setState(() {
      _saving = false;
      if (usable) {
        _refusalMessage = null;
        _refusalCanRefresh = false;
      } else {
        _refusalMessage =
            'The tax configuration still could not be refreshed. Check your '
            'internet connection and try again.';
      }
    });
  }

  Future<void> _save(RevenueDraft draft) async {
    setState(() {
      _saving = true;
      _refusalMessage = null;
    });

    final controller = ref.read(revenueEntryControllerProvider);
    final (outcome, refusal) = widget.isEditing
        ? await controller.applyEdit(draft)
        : await controller.save(draft);
    if (!mounted) return;

    if (refusal != null) {
      setState(() {
        _saving = false;
        _refusalMessage = refusal.message;
        _refusalCanRefresh = refusal.refreshMayResolve;
      });
      return;
    }

    // Saved locally and queued. Not "sent": the entry is durable either way, and saying
    // anything about the server before it has answered would be a claim this screen
    // cannot support.
    //
    // The messenger is taken *before* popping, because after the pop this screen's own
    // context is gone and the confirmation would have nowhere to land.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Only when there is somewhere to go back to. The page is pushed in production, and
    // popping unconditionally would assume that — which is exactly the kind of assumption
    // that holds until the day somebody makes it a tab.
    if (navigator.canPop()) {
      navigator.pop(outcome!.entryId);
    } else {
      setState(() {
        _saving = false;
        // A fresh form, so a second sale can be recorded straight away rather than
        // re-editing the one just saved.
        _draft = null;
      });
    }

    messenger.showSnackBar(
      SnackBar(
        key: const Key('revenue-saved'),
        content: Text(
          widget.isEditing
              ? 'Correction recorded · Pending Sync'
              : 'Sales recorded · Pending Sync',
        ),
      ),
    );
  }
}

/// The trading day this entry belongs to, in words rather than in a rule.
///
/// Derived under the property's cut-off, never the raw device calendar date (D-067), so a
/// figure entered at 01:00 belongs to the evening that produced it. The explanation is
/// shown only when the two differ, because on an ordinary afternoon it would be noise.
class _BusinessDateLine extends StatelessWidget {
  const _BusinessDateLine({required this.date});

  final BusinessDate date;

  static const _months = [
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

  @override
  Widget build(BuildContext context) {
    // Written out, not an ISO string and certainly not a debug `toString`. Somebody
    // checking that a figure landed on the right trading day should not have to parse
    // `2026-06-15` to do it.
    final readable = '${date.day} ${_months[date.month - 1]} ${date.year}';
    final iso = date.iso;
    final deviceToday = DateTime.now();
    final deviceIso =
        '${deviceToday.year.toString().padLeft(4, '0')}-'
        '${deviceToday.month.toString().padLeft(2, '0')}-'
        '${deviceToday.day.toString().padLeft(2, '0')}';

    return Container(
      key: const Key('revenue-business-date'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.allSmall,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Business date', style: AppTypography.overline),
                const SizedBox(height: AppSpacing.xxs),
                Text(readable, style: AppTypography.body),
                if (iso != deviceIso) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'This is the trading day these sales belong to.',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitPicker extends StatelessWidget {
  const _UnitPicker({
    required this.units,
    required this.selected,
    required this.onChanged,
  });

  final List<MasterNode> units;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Property', style: AppTypography.overline),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final unit in units)
            ChoiceChip(
              key: Key('revenue-unit-${unit.code}'),
              label: Text(unit.name),
              selected: selected == unit.id,
              onSelected: (_) => onChanged(unit.id),
            ),
        ],
      ),
    ],
  );
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  final List<MasterNode> categories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const _Message(
        key: Key('revenue-entry-no-categories'),
        icon: Icons.category_outlined,
        title: 'No sales categories',
        body:
            'This property has no revenue categories available. '
            'Ask the Owner to configure one.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sales category', style: AppTypography.overline),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final category in categories)
              ChoiceChip(
                key: Key('revenue-category-${category.code}'),
                label: Text(category.name),
                selected: selected == category.id,
                onSelected: (_) => onChanged(category.id),
              ),
          ],
        ),
      ],
    );
  }
}

/// The amount field or fields, and the live breakdown under them.
class _AmountsAndBreakdown extends ConsumerWidget {
  const _AmountsAndBreakdown({
    required this.draft,
    required this.unitId,
    required this.onAmountChanged,
    required this.onComponentsResolved,
    required this.onSaveable,
  });

  final RevenueDraft draft;
  final String unitId;
  final void Function(String componentId, dynamic amount) onAmountChanged;
  final ValueChanged<RevenueDraft> onComponentsResolved;
  final Widget Function(bool canSave, RevenuePreview preview) onSaveable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockAsync = ref.watch(revenueConfigurationBlockProvider(unitId));
    final rulesAsync = ref.watch(
      revenueRulesProvider(draft.revenueCategoryId!),
    );

    if (blockAsync.isLoading || rulesAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // An error reading either is treated as "nothing usable", which the preview then
    // reports as a configuration problem rather than as a crash. A screen that threw here
    // would tell an operator nothing they could act on.
    final rules = switch (rulesAsync) {
      AsyncData(:final value) => value,
      _ => RevenueTaxRuleSet(const []),
    };
    final block = switch (blockAsync) {
      AsyncData(:final value) => value,
      _ => const RevenueConfigurationUnavailable(
        RevenueConfigurationGap.neverSynchronised,
      ),
    };

    // Re-shape the form from the configuration before previewing against it.
    final shaped = draft.withComponentsFor(rules);
    if (!identical(shaped, draft)) onComponentsResolved(shaped);

    final preview = shaped.previewWith(rules, unavailable: block);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preview.blockedBy != null)
          _RefusalBanner(message: preview.blockedBy!.message, onRefresh: null)
        else ...[
          for (final line in preview.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _AmountLine(
                line: line,
                component: shaped.components.firstWhere(
                  (c) => c.id == line.componentId,
                ),
                onChanged: (amount) =>
                    onAmountChanged(line.componentId, amount),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          RevenueBreakdown(preview: preview),
        ],
        onSaveable(shaped.canSave(preview), preview),
      ],
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.line,
    required this.component,
    required this.onChanged,
  });

  final RevenueLinePreview line;
  final RevenueComponentEntry component;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    // The band's own label, where one applies. Shown above the field rather than inside
    // it so two bands read as two separate figures rather than as one split control.
    final band = component.valueBandLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (band != null) ...[
          Text(
            band,
            key: Key('revenue-band-label-${component.valueBandId}'),
            style: AppTypography.overline,
          ),
          const SizedBox(height: AppSpacing.xxs),
        ],
        AmountField(
          key: Key('revenue-amount-${component.id}'),
          // The label follows the basis **and** the treatment (D-097), so an untaxed
          // category is never told that GST is inside its figure.
          label: line.label,
          initial: component.amount,
          autofocus: band == null,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RefusalBanner extends StatelessWidget {
  const _RefusalBanner({required this.message, this.onRefresh});

  final String message;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('revenue-refusal'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: AppRadius.allSmall,
      border: Border.all(color: AppColors.caution),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.caution),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message, style: AppTypography.body)),
          ],
        ),
        if (onRefresh != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('revenue-refresh-configuration'),
              onPressed: onRefresh,
              child: const Text('Refresh now'),
            ),
          ),
        ],
      ],
    ),
  );
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(AppSpacing.xxl), child: child),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 32, color: AppColors.inkFaint),
      const SizedBox(height: AppSpacing.md),
      Text(title, style: AppTypography.subheading, textAlign: TextAlign.center),
      const SizedBox(height: AppSpacing.xs),
      Text(
        body,
        style: AppTypography.body.copyWith(color: AppColors.inkMuted),
        textAlign: TextAlign.center,
      ),
    ],
  );
}
