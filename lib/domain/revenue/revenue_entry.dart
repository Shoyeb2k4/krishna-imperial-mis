/// The revenue document and its components (spec §8.0, D-078).
///
/// A revenue entry is a **document with one or more components**, mirroring the expense
/// model, because one day's revenue in one category can carry more than one tax treatment:
/// room tax may depend on accommodation value, and a category may invoice more than one
/// kind of supply. A routine day is one component and is no slower to enter for it.
///
/// The header holds **no money of its own**. Its gross, tax and net are the exact integer
/// sums of its components — not a stored second copy that could disagree with them. That
/// is the strongest available form of "header reconciles to components": there is nothing
/// to reconcile, because there is only one set of numbers. The database will still carry
/// header columns for indexing and projection, and Slice 4 keeps them equal by trigger;
/// this class is what defines what equal means.
library;

import 'package:meta/meta.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// How a revenue entry came to exist (spec §8.2).
enum RevenueEntryKind {
  dailySummary,
  shift,
  import,
  correction;

  /// How this value is written to both databases.
  ///
  /// Stated explicitly rather than taken from [name], for the reason D-104 records: the
  /// two schemas store `daily_summary` and a Dart enum name is `dailySummary`, and relying
  /// on the coincidence of the two agreeing is how a value becomes unwritable the moment
  /// somebody renames a constant. Here it is load-bearing twice over — a check constraint
  /// refuses the wrong form, and `entry_kind` is what permanently distinguishes an
  /// imported figure from one somebody typed (spec §32).
  String get wireName => switch (this) {
    RevenueEntryKind.dailySummary => 'daily_summary',
    RevenueEntryKind.shift => 'shift',
    RevenueEntryKind.import => 'import',
    RevenueEntryKind.correction => 'correction',
  };

  static RevenueEntryKind fromName(String value) =>
      RevenueEntryKind.values.firstWhere(
        (k) => k.wireName == value,
        orElse: () =>
            throw ArgumentError.value(value, 'value', 'unknown entry kind'),
      );

  String get label => switch (this) {
    RevenueEntryKind.dailySummary => 'Daily summary',
    RevenueEntryKind.shift => 'Shift',
    RevenueEntryKind.import => 'Imported',
    RevenueEntryKind.correction => 'Correction',
  };
}

/// One taxed slice of a revenue entry, with the rule that produced its figures frozen
/// onto it.
///
/// Every derived figure is stored rather than recomputed, and the facts that selected the
/// rule are stored beside them. That is what lets a figure be explained years later
/// without consulting a rule table that may since have changed — and it is why a later
/// configuration edit cannot restate history (spec §8.1).
@immutable
final class RevenueComponent {
  const RevenueComponent({
    required this.id,
    required this.enteredAmount,
    required this.enteredBasis,
    required this.gross,
    required this.tax,
    required this.net,
    required this.taxRuleId,
    required this.taxRateBasisPoints,
    required this.taxTreatment,
    this.valueBandId,
    this.valueBandLabel,
    this.valueBandFloor,
    this.valueBandCeiling,
    this.supplySubtypeId,
    this.premisesStatusCode,
  });

  final String id;

  /// What the operator actually typed, and as what (D-080).
  final Money enteredAmount;
  final EnteredBasis enteredBasis;

  /// Derived once, half-up, at the record.
  final Money gross;
  final Money tax;
  final Money net;

  /// The rule that produced the three figures above, snapshotted.
  final String taxRuleId;
  final int taxRateBasisPoints;
  final TaxTreatment taxTreatment;

  /// The facts that selected that rule, snapshotted so the choice is explainable.
  ///
  /// [valueBandFloor] and [valueBandCeiling] are **explanation only**. They are the
  /// tariff boundaries of the configured band; they are never compared against
  /// [enteredAmount], because a day's aggregate revenue attributable to a band is not a
  /// per-room-per-night tariff (D-094).
  final String? valueBandId;
  final String? valueBandLabel;
  final Money? valueBandFloor;
  final Money? valueBandCeiling;

  final String? supplySubtypeId;
  final String? premisesStatusCode;

  /// The invariant every component must satisfy.
  bool get reconciles => net + tax == gross;

  @override
  String toString() =>
      'RevenueComponent(entered: $enteredAmount ${enteredBasis.name}, '
      'gross: $gross, tax: $tax, net: $net'
      '${valueBandLabel == null ? '' : ', band: $valueBandLabel'})';
}

/// A revenue document.
@immutable
final class RevenueEntry {
  const RevenueEntry({
    required this.id,
    required this.businessUnitId,
    required this.revenueCategoryId,
    required this.businessDate,
    required this.capturedAt,
    required this.components,
    this.txnNumber,
    this.entryKind = RevenueEntryKind.dailySummary,
    this.sourceReference,
    this.notes,
    this.createdBy,
    this.rowVersion = 1,
    this.voidedAt,
    this.voidReason,
  }) : assert(
         components.length != 0,
         'a revenue entry has at least one component',
       );

  final String id;

  /// Server-issued on canonical acceptance; null while the entry is only local
  /// (spec §8.4).
  final String? txnNumber;

  final String businessUnitId;
  final String revenueCategoryId;

  /// Derived under the unit's timezone and cut-off, and persisted (D-067).
  final BusinessDate businessDate;

  /// The device instant. Forensic metadata; never authoritative.
  final DateTime capturedAt;

  final List<RevenueComponent> components;
  final RevenueEntryKind entryKind;
  final String? sourceReference;
  final String? notes;
  final String? createdBy;
  final int rowVersion;
  final DateTime? voidedAt;
  final String? voidReason;

  /// The header figures, as exact integer sums of the components.
  Money get gross => Money.sum(components.map((c) => c.gross));
  Money get tax => Money.sum(components.map((c) => c.tax));
  Money get net => Money.sum(components.map((c) => c.net));

  bool get isVoided => voidedAt != null;

  /// True when every component reconciles and the header does too.
  ///
  /// The header check is a tautology while the sums are derived, and it is written anyway:
  /// Slice 4 stores header columns for indexing, and this is the assertion those columns
  /// are held to.
  bool get reconciles =>
      components.every((c) => c.reconciles) && net + tax == gross;

  @override
  String toString() =>
      'RevenueEntry(${txnNumber ?? id}, ${businessDate.iso}, '
      '${components.length} component(s), gross: $gross, tax: $tax, net: $net)';
}

/// A component being built, before its tax has been resolved.
///
/// The draft carries the **selected** band, subtype and premises status — the facts the
/// resolver needs — and the amount. It does not carry a rate: the rate arrives only by
/// resolving a rule, and there is no path that sets one directly.
@immutable
final class RevenueComponentDraft {
  const RevenueComponentDraft({
    required this.id,
    required this.enteredAmount,
    this.valueBandId,
    this.valueBandLabel,
    this.supplySubtypeId,
    this.premisesStatusCode,
  });

  final String id;
  final Money enteredAmount;

  /// The configured band this amount is attributable to, chosen by the operator.
  ///
  /// **Not derived from [enteredAmount]** (D-094): the operator states which band the
  /// aggregate belongs to, and the band's own configuration carries the tariff boundary.
  final String? valueBandId;
  final String? valueBandLabel;

  final String? supplySubtypeId;
  final String? premisesStatusCode;

  RevenueComponentDraft copyWith({
    Money? enteredAmount,
    String? valueBandId,
    String? valueBandLabel,
    String? supplySubtypeId,
    String? premisesStatusCode,
  }) => RevenueComponentDraft(
    id: id,
    enteredAmount: enteredAmount ?? this.enteredAmount,
    valueBandId: valueBandId ?? this.valueBandId,
    valueBandLabel: valueBandLabel ?? this.valueBandLabel,
    supplySubtypeId: supplySubtypeId ?? this.supplySubtypeId,
    premisesStatusCode: premisesStatusCode ?? this.premisesStatusCode,
  );
}

/// A revenue entry being built.
@immutable
final class RevenueEntryDraft {
  const RevenueEntryDraft({
    required this.id,
    required this.businessUnitId,
    required this.revenueCategoryId,
    required this.businessDate,
    required this.capturedAt,
    required this.components,
    this.entryKind = RevenueEntryKind.dailySummary,
    this.sourceReference,
    this.notes,
  });

  final String id;
  final String businessUnitId;
  final String revenueCategoryId;
  final BusinessDate businessDate;
  final DateTime capturedAt;
  final List<RevenueComponentDraft> components;
  final RevenueEntryKind entryKind;
  final String? sourceReference;
  final String? notes;

  /// The facts one component presents for resolution.
  RevenueTaxFacts factsFor(RevenueComponentDraft component) => RevenueTaxFacts(
    revenueCategoryId: revenueCategoryId,
    businessDate: businessDate,
    valueBandId: component.valueBandId,
    supplySubtypeId: component.supplySubtypeId,
    premisesStatusCode: component.premisesStatusCode,
  );

  RevenueEntryDraft copyWith({
    List<RevenueComponentDraft>? components,
    RevenueEntryKind? entryKind,
    String? sourceReference,
    String? notes,
  }) => RevenueEntryDraft(
    id: id,
    businessUnitId: businessUnitId,
    revenueCategoryId: revenueCategoryId,
    businessDate: businessDate,
    capturedAt: capturedAt,
    components: components ?? this.components,
    entryKind: entryKind ?? this.entryKind,
    sourceReference: sourceReference ?? this.sourceReference,
    notes: notes ?? this.notes,
  );
}
