/// The day's sales being typed, and everything that decides whether it can be saved.
///
/// Pure Dart over a [MasterGraph], an [AuthoritySnapshot] and the resolved tax rules. No
/// Flutter, no database, no network — so the rules a user experiences as "why is Save
/// greyed out" are unit-testable, and are the same rules the repository will apply again
/// before it writes anything.
///
/// Three things it is careful about, and they are the same three the expense draft is
/// careful about, for the same reasons.
///
/// **A changed parent invalidates its children.** Switching business unit while a Crystal
/// Canopy category is selected must not leave that category selected — the server's
/// composite ladder would refuse it (D-040), and a client that offered it would be
/// offering something that cannot exist. Changing the category likewise clears the band,
/// the subtype and every other conditional fact, because those are properties of the
/// rules for *that* category and mean nothing under another.
///
/// **No arithmetic happens here.** The figures come from `TaxRule.compute` — the same
/// code the local repository, the parity vectors and `app.revenue_compute` are all proven
/// equal to (D-105). A second implementation in a widget is precisely what
/// `CLAUDE.md` forbids, and the reason the preview and the saved record cannot disagree
/// is that they are the same function called twice, not two functions that agree today.
///
/// **The form shape follows the configuration, not the code.** How many amount fields
/// there are, what each is labelled, and whether a band must be chosen are all read from
/// the resolved rules. Room shows one field today because one generic rule is configured;
/// it will show two the day two bands are, with no release (D-081).
library;

import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

/// One amount the operator is being asked for, and what it is attributable to.
///
/// A component in the domain sense, but the word does not reach the screen: to somebody
/// entering a day's takings this is "the amount", or "the amount for this tariff band".
@immutable
final class RevenueComponentEntry {
  const RevenueComponentEntry({
    required this.id,
    this.amount,
    this.valueBandId,
    this.valueBandLabel,
    this.supplySubtypeId,
    this.supplySubtypeLabel,
    this.premisesStatusCode,
  });

  final String id;

  /// Null while the field is empty or unreadable. Deliberately not zero: an empty box and
  /// a deliberate nought are different statements, and only one of them is a mistake.
  final Money? amount;

  /// The configured band this amount is attributable to.
  ///
  /// **Selected, never derived from [amount]** (D-094). A day's aggregate room revenue is
  /// not a per-room-per-night tariff, and choosing a rate by comparing the two would be
  /// arithmetic that means nothing and happens to compile.
  final String? valueBandId;
  final String? valueBandLabel;

  final String? supplySubtypeId;
  final String? supplySubtypeLabel;
  final String? premisesStatusCode;

  RevenueComponentEntry copyWith({Money? amount, bool clearAmount = false}) =>
      RevenueComponentEntry(
        id: id,
        amount: clearAmount ? null : (amount ?? this.amount),
        valueBandId: valueBandId,
        valueBandLabel: valueBandLabel,
        supplySubtypeId: supplySubtypeId,
        supplySubtypeLabel: supplySubtypeLabel,
        premisesStatusCode: premisesStatusCode,
      );

  RevenueTaxFacts factsFor({
    required String revenueCategoryId,
    required BusinessDate businessDate,
  }) => RevenueTaxFacts(
    revenueCategoryId: revenueCategoryId,
    businessDate: businessDate,
    valueBandId: valueBandId,
    supplySubtypeId: supplySubtypeId,
    premisesStatusCode: premisesStatusCode,
  );
}

/// What one line of the live breakdown says, once a rule has resolved.
@immutable
final class RevenueLinePreview {
  const RevenueLinePreview({
    required this.componentId,
    required this.label,
    required this.rule,
    this.computed,
  });

  final String componentId;

  /// What to put above the amount field.
  ///
  /// Takes the **treatment as well as the basis** (D-097). Banquet is `inclusive_total`
  /// with a treatment of `none`, and labelling its field "Customer total (incl. GST)"
  /// would tell an operator that GST is inside a figure that carries none — a real defect
  /// the Slice 2 review caught before it reached a screen.
  final String label;

  final TaxRule rule;

  /// Null while the amount field is empty. There is nothing to preview about nothing.
  final TaxComputation? computed;
}

/// The whole breakdown, or the reason there isn't one.
@immutable
final class RevenuePreview {
  const RevenuePreview({
    this.lines = const [],
    this.blockedBy,
    this.requiresBandChoice = false,
  });

  final List<RevenueLinePreview> lines;

  /// Why no figures can be shown: the configuration is unavailable, stale, absent for
  /// these facts, ambiguous, or incomplete. Never a raw exception (D-113).
  final RevenueTaxResolution? blockedBy;

  /// Whether the configured rules require the operator to state a band before anything
  /// can be resolved. Distinct from [blockedBy] because it is an instruction, not a fault.
  final bool requiresBandChoice;

  bool get isResolved => blockedBy == null && lines.isNotEmpty;

  /// True once every line the form is showing has a readable amount.
  bool get isComplete =>
      isResolved && lines.every((line) => line.computed != null);

  Money get gross => Money.sum([
    for (final line in lines)
      if (line.computed != null) line.computed!.gross,
  ]);

  Money get tax => Money.sum([
    for (final line in lines)
      if (line.computed != null) line.computed!.tax,
  ]);

  Money get net => Money.sum([
    for (final line in lines)
      if (line.computed != null) line.computed!.net,
  ]);

  /// Whether any configured rule actually applies tax.
  ///
  /// Drives the wording of the breakdown: an untaxed category says "No GST" rather than
  /// "GST ₹0", because the first is a statement about the treatment and the second reads
  /// like an amount that happened to come out at nothing.
  bool get carriesTax =>
      lines.any((line) => line.rule.treatment != TaxTreatment.none);
}

/// The sale being recorded.
@immutable
final class RevenueDraft {
  const RevenueDraft({
    required this.id,
    required this.businessDate,
    required this.components,
    this.businessUnitId,
    this.revenueCategoryId,
    this.entryKind = RevenueEntryKind.dailySummary,
    this.sourceReference,
    this.notes,
    this.baseRowVersion,
    this.txnNumber,
    this.attachments = const [],
  });

  /// A blank sale, with the unit preselected when the user holds exactly one.
  ///
  /// [businessDate] comes from the unit's cut-off, never the raw device clock (D-019).
  /// The caller derives it; this type does not know what time it is.
  factory RevenueDraft.blank({
    required BusinessDate businessDate,
    String? id,
    String? businessUnitId,
  }) => RevenueDraft(
    id: id ?? const Uuid().v7(),
    businessDate: businessDate,
    businessUnitId: businessUnitId,
    components: [RevenueComponentEntry(id: const Uuid().v4())],
  );

  final String id;
  final BusinessDate businessDate;
  final String? businessUnitId;
  final String? revenueCategoryId;
  final List<RevenueComponentEntry> components;
  final RevenueEntryKind entryKind;
  final String? sourceReference;
  final String? notes;

  /// The version this correction is based on, captured when the form opened.
  ///
  /// **Every mutator below carries it through unchanged, and none of them can set it.**
  /// That is the point: the form rebuilds on every keystroke, so a `copyWith` that
  /// accepted a new version would be precisely how a background pull silently re-bases
  /// somebody's correction onto a row they never saw (D-072a, §4).
  ///
  /// Null for a new sale, which establishes a new identity and cannot conflict (D-021).
  final int? baseRowVersion;

  /// The server-issued number, carried so the edit screen can show which document is
  /// being corrected. Never sent as an instruction: the number belongs to the document's
  /// identity and no correction changes it.
  final String? txnNumber;

  /// Supporting evidence, staged on this device and not yet — or already — recorded.
  ///
  /// **It is not part of the sale's financial identity and nothing here treats it as
  /// such.** No validation reads it, no total is derived from it, and `problems` cannot
  /// name it: a photograph that will not upload is the attachment's problem, never a
  /// reason a correct figure may not be saved. On an edit it starts as what the document
  /// already carries, so the form shows the whole collection rather than only what was
  /// added in this sitting; writing it back is idempotent on the attachment id.
  final List<DocumentAttachment> attachments;

  /// The same draft with a different evidence collection. Deliberately its own mutator,
  /// so nothing that changes money can change evidence by accident, or the reverse.
  RevenueDraft withAttachments(List<DocumentAttachment> attachments) =>
      _copy(attachments: attachments);

  /// The one place every field is carried forward.
  ///
  /// `baseRowVersion` travels through unchanged and is deliberately not a parameter, for
  /// the reason its own doc comment gives.
  RevenueDraft _copy({
    BusinessDate? businessDate,
    String? businessUnitId,
    String? revenueCategoryId,
    List<RevenueComponentEntry>? components,
    RevenueEntryKind? entryKind,
    String? sourceReference,
    String? notes,
    List<DocumentAttachment>? attachments,
  }) => RevenueDraft(
    id: id,
    businessDate: businessDate ?? this.businessDate,
    businessUnitId: businessUnitId ?? this.businessUnitId,
    revenueCategoryId: revenueCategoryId ?? this.revenueCategoryId,
    components: components ?? this.components,
    entryKind: entryKind ?? this.entryKind,
    sourceReference: sourceReference ?? this.sourceReference,
    notes: notes ?? this.notes,
    baseRowVersion: baseRowVersion,
    txnNumber: txnNumber,
    attachments: attachments ?? this.attachments,
  );

  bool get isEditing => baseRowVersion != null;

  /// The same sale, loaded for correction.
  ///
  /// The business unit and the category come from the document and are not offered for
  /// change: nothing in the binding specification authorises moving recorded revenue
  /// between properties, and an edit that could would be a scope transfer wearing a
  /// correction's clothes. Correcting those is void and re-enter (spec §14).
  factory RevenueDraft.fromEntry(RevenueEntry entry) => RevenueDraft(
    id: entry.id,
    businessDate: entry.businessDate,
    businessUnitId: entry.businessUnitId,
    revenueCategoryId: entry.revenueCategoryId,
    entryKind: entry.entryKind,
    sourceReference: entry.sourceReference,
    notes: entry.notes,
    baseRowVersion: entry.rowVersion,
    txnNumber: entry.txnNumber,
    attachments: entry.attachments,
    components: [
      for (final component in entry.components)
        RevenueComponentEntry(
          id: component.id,
          amount: component.enteredAmount,
          valueBandId: component.valueBandId,
          valueBandLabel: component.valueBandLabel,
          supplySubtypeId: component.supplySubtypeId,
          premisesStatusCode: component.premisesStatusCode,
        ),
    ],
  );

  /// The business units this user may record revenue for.
  ///
  /// An org-wide grant covers every unit by construction (D-025), so the two cases are
  /// asked as one question rather than branched on a role name.
  static List<MasterNode> permittedUnits(
    MasterGraph graph,
    AuthoritySnapshot? authority,
  ) {
    if (authority == null) return const [];
    return [
      for (final unit in graph.businessUnits())
        if (authority.grants.any(
          (g) => g.covers(Capability.revenueCreate, unit.id),
        ))
          unit,
    ];
  }

  /// The categories offered for the selected unit.
  ///
  /// Only that unit's, and only live ones: a category that has been archived stays valid
  /// for entries already recorded against it and is refused for new ones (D-035).
  List<MasterNode> categoriesFor(MasterGraph graph) {
    final unit = businessUnitId;
    if (unit == null) return const [];
    return graph.revenueCategoriesOf(unit);
  }

  /// Changing the property clears everything that belonged to the old one.
  ///
  /// The cascade is the point. A Crystal Canopy category left selected under Hotel
  /// Krishna would be refused by the server's composite key — or, worse, quietly accepted
  /// somewhere it does not belong.
  RevenueDraft withBusinessUnit(String? unitId) {
    if (unitId == businessUnitId) return this;
    return RevenueDraft(
      id: id,
      businessDate: businessDate,
      businessUnitId: unitId,
      // Category, band, subtype and premises status are all properties of the previous
      // unit's configuration. None of them survives.
      components: [RevenueComponentEntry(id: const Uuid().v4())],
      entryKind: entryKind,
      sourceReference: sourceReference,
      notes: notes,
      baseRowVersion: baseRowVersion,
      txnNumber: txnNumber,
      attachments: attachments,
    );
  }

  /// Changing the category clears the conditional facts and the amounts with them.
  ///
  /// The amounts go too, and deliberately: the fields under a new category may be a
  /// different set entirely, and carrying a figure across from a band that no longer
  /// exists would attribute money to something nobody chose.
  RevenueDraft withCategory(String? categoryId) {
    if (categoryId == revenueCategoryId) return this;
    return RevenueDraft(
      id: id,
      businessDate: businessDate,
      businessUnitId: businessUnitId,
      revenueCategoryId: categoryId,
      components: [RevenueComponentEntry(id: const Uuid().v4())],
      entryKind: entryKind,
      sourceReference: sourceReference,
      notes: notes,
      baseRowVersion: baseRowVersion,
      txnNumber: txnNumber,
      attachments: attachments,
    );
  }

  RevenueDraft withAmount(String componentId, Money? amount) => RevenueDraft(
    id: id,
    businessDate: businessDate,
    businessUnitId: businessUnitId,
    revenueCategoryId: revenueCategoryId,
    components: [
      for (final component in components)
        if (component.id == componentId)
          component.copyWith(amount: amount, clearAmount: amount == null)
        else
          component,
    ],
    entryKind: entryKind,
    sourceReference: sourceReference,
    notes: notes,
    baseRowVersion: baseRowVersion,
    txnNumber: txnNumber,
    attachments: attachments,
  );

  RevenueDraft withDetails({
    RevenueEntryKind? entryKind,
    String? sourceReference,
    String? notes,
  }) => RevenueDraft(
    id: id,
    businessDate: businessDate,
    businessUnitId: businessUnitId,
    revenueCategoryId: revenueCategoryId,
    components: components,
    entryKind: entryKind ?? this.entryKind,
    sourceReference: sourceReference ?? this.sourceReference,
    notes: notes ?? this.notes,
    baseRowVersion: baseRowVersion,
    txnNumber: txnNumber,
    attachments: attachments,
  );

  /// Rebuilds the components to match the configured rules for this category.
  ///
  /// **This is what makes a second Room band a configuration change rather than a
  /// release** (D-081). The form asks the rule set what applies on this business date: one
  /// applicable rule gives one amount field, two banded rules give two, each carrying the
  /// band identity the operator is stating. No threshold is a constant in this file, and
  /// nothing here compares an amount against a band's bounds.
  ///
  /// Existing amounts are preserved where the same band is still offered, so re-resolving
  /// after a configuration refresh does not silently empty a form somebody is typing in.
  RevenueDraft withComponentsFor(RevenueTaxRuleSet rules) {
    final category = revenueCategoryId;
    if (category == null) return this;

    final applicable = rules.liveBandsFor(
      revenueCategoryId: category,
      businessDate: businessDate,
    );

    // No banded rules: one plain amount, which is every configured category today.
    if (applicable.isEmpty) {
      if (components.length == 1 && components.single.valueBandId == null) {
        return this;
      }
      return RevenueDraft(
        id: id,
        businessDate: businessDate,
        businessUnitId: businessUnitId,
        revenueCategoryId: revenueCategoryId,
        components: [RevenueComponentEntry(id: const Uuid().v4())],
        entryKind: entryKind,
        sourceReference: sourceReference,
        notes: notes,
        baseRowVersion: baseRowVersion,
        txnNumber: txnNumber,
        attachments: attachments,
      );
    }

    // Already the right shape: return the same instance.
    //
    // Not an optimisation. The entry screen re-shapes on every build and applies the
    // result with `setState`, so a method that returned a fresh object each time would
    // rebuild for ever — which is precisely what happened, and what the widget suite
    // caught as a `pumpAndSettle` timeout rather than as anything a reader would spot.
    final current = [for (final c in components) c.valueBandId];
    if (current.length == applicable.length) {
      var matches = true;
      for (var i = 0; i < current.length; i++) {
        if (current[i] != applicable[i].id) {
          matches = false;
          break;
        }
      }
      if (matches) return this;
    }

    final existing = {
      for (final component in components)
        if (component.valueBandId != null) component.valueBandId!: component,
    };

    return RevenueDraft(
      id: id,
      businessDate: businessDate,
      businessUnitId: businessUnitId,
      revenueCategoryId: revenueCategoryId,
      components: [
        for (final band in applicable)
          existing[band.id] ??
              RevenueComponentEntry(
                id: const Uuid().v4(),
                valueBandId: band.id,
                valueBandLabel: band.label,
              ),
      ],
      entryKind: entryKind,
      sourceReference: sourceReference,
      notes: notes,
      baseRowVersion: baseRowVersion,
      txnNumber: txnNumber,
      attachments: attachments,
    );
  }

  /// Resolves every component and computes the breakdown, or says why it cannot.
  ///
  /// [unavailable] is passed in rather than discovered here: whether this device holds an
  /// authoritative, fresh snapshot for this scope is a question about the *cache*, and
  /// the draft has no business asking it. The repository decides it and hands the answer
  /// down, so the screen and the save path cannot disagree about it.
  RevenuePreview previewWith(
    RevenueTaxRuleSet rules, {
    RevenueTaxResolution? unavailable,
  }) {
    if (unavailable != null) return RevenuePreview(blockedBy: unavailable);

    final category = revenueCategoryId;
    if (category == null || components.isEmpty) return const RevenuePreview();

    final lines = <RevenueLinePreview>[];
    for (final component in components) {
      final outcome = rules.resolve(
        component.factsFor(
          revenueCategoryId: category,
          businessDate: businessDate,
        ),
      );

      if (outcome is! RevenueTaxResolved) {
        return RevenuePreview(
          blockedBy: outcome,
          requiresBandChoice:
              outcome is RevenueTaxMissingFact &&
              outcome.dimension == RevenueTaxDimension.valueBand,
        );
      }

      lines.add(
        RevenueLinePreview(
          componentId: component.id,
          label:
              outcome.rule.inputBasis?.fieldLabelFor(outcome.rule.treatment) ??
              'Amount',
          rule: outcome.rule,
          // The one arithmetic call, and it is the canonical one.
          computed: component.amount == null
              ? null
              : outcome.rule.compute(component.amount!),
        ),
      );
    }

    return RevenuePreview(lines: lines);
  }

  /// Whether Save may be offered.
  ///
  /// Deliberately conservative: everything must be chosen, every field must be readable,
  /// and every rule must have resolved. The repository checks all of it again before it
  /// writes, and the server again after that — this exists so the button is honest, not
  /// so the check happens only once (D-037).
  bool canSave(RevenuePreview preview) =>
      businessUnitId != null &&
      revenueCategoryId != null &&
      components.isNotEmpty &&
      preview.isComplete;

  /// The draft in the shape the Slice 7 create path takes.
  RevenueEntryDraft toEntryDraft({required DateTime capturedAt}) =>
      RevenueEntryDraft(
        id: id,
        businessUnitId: businessUnitId!,
        revenueCategoryId: revenueCategoryId!,
        businessDate: businessDate,
        capturedAt: capturedAt,
        entryKind: entryKind,
        sourceReference: sourceReference,
        notes: notes,
        components: [
          for (final component in components)
            RevenueComponentDraft(
              id: component.id,
              enteredAmount: component.amount!,
              valueBandId: component.valueBandId,
              valueBandLabel: component.valueBandLabel,
              supplySubtypeId: component.supplySubtypeId,
              premisesStatusCode: component.premisesStatusCode,
            ),
        ],
      );
}
