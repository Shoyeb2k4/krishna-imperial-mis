/// Resolving revenue tax from locally cached authoritative configuration (Slice 5).
///
/// The pure resolver in `domain/revenue/` remains the financial semantic engine. This
/// file is an **adapter**: it reads the Drift cache, reconstructs the domain model
/// faithfully, and hands the decision to the same code that will one day run against
/// server fixtures in a parity suite. No tax semantics are re-expressed in SQL, and no
/// default is ever invented on the way through.
///
/// ## The distinction this file exists for
///
/// An empty local result means one of two entirely different things:
///
/// * the configuration **is** synchronised and genuinely has no rule for these facts, or
/// * this device **has no authoritative snapshot at all**.
///
/// Both stop a revenue entry, and confusing them is how a device with an empty cache
/// starts telling a manager their tax is not configured. The first is a message for the
/// Owner; the second is a message about this device. `configurationUnavailable` is
/// therefore a first-class outcome, decided **before** the cache is queried rather than
/// inferred from its emptiness.
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// The `app_meta` key recording that reference configuration has been received.
///
/// Written by `ReferenceSync` when a pull completes (Slice 6). Its **absence** is what
/// makes [RevenueConfigurationUnavailable] decidable: a device that has never pulled has
/// no snapshot, and an empty rule table on such a device says nothing about the
/// organisation's tax configuration.
const revenueConfigurationSyncedKey = 'revenue.configuration.synced_at';

/// Whether new revenue may be created offline, and if not, why (B12).
final class RevenueCreateEligibility {
  const RevenueCreateEligibility._(this.resolutions, this.refusal);

  /// Every component resolved, in the order given.
  const RevenueCreateEligibility.allowed(List<RevenueTaxResolved> resolutions)
    : this._(resolutions, null);

  const RevenueCreateEligibility.refused(RevenueTaxResolution refusal)
    : this._(const [], refusal);

  final List<RevenueTaxResolved> resolutions;
  final RevenueTaxResolution? refusal;

  bool get isAllowed => refusal == null;

  /// Plain language for the person who hit it.
  String? get message => refusal?.message;
}

/// Reads the cached configuration and resolves against it.
class RevenueTaxRepository {
  RevenueTaxRepository(this.db);

  final AppDatabase db;

  /// Whether this device holds an authoritative reference snapshot.
  ///
  /// Read from `app_meta` rather than inferred from row counts: a purge legitimately
  /// empties the rule cache (D-070), and "no rows" must not be mistaken for "no rules
  /// exist in the organisation".
  Future<bool> hasAuthoritativeSnapshot() async {
    final row =
        await (db.select(db.appMeta)
              ..where((m) => m.key.equals(revenueConfigurationSyncedKey)))
            .getSingleOrNull();
    return row != null && row.value.isNotEmpty;
  }

  /// The rules cached for one category, as the domain model.
  ///
  /// Loads **every** candidate for the category rather than filtering to one in SQL.
  /// That is deliberate (B8): the doctrine needs to distinguish zero, one and many, and a
  /// query that returned the first match by ordering would silently reintroduce the
  /// ranking D-094 forbids — and would hide a corrupted or stale cache holding two
  /// matching rules, which is exactly when the local check earns its keep.
  Future<RevenueTaxRuleSet> rulesFor(String revenueCategoryId) async {
    final rows =
        await (db.select(db.revenueTaxRates)..where(
              (r) =>
                  r.revenueCategoryId.equals(revenueCategoryId) &
                  r.archivedAt.isNull(),
            ))
            .get();

    // Bands are needed for the snapshot the component will carry, and for explanation.
    final bands = {
      for (final b in await db.select(db.revenueValueBands).get()) b.id: b,
    };

    return RevenueTaxRuleSet([for (final row in rows) _toRule(row, bands)]);
  }

  /// Reconstructs one rule. **Nothing is defaulted.**
  ///
  /// A cached rule with no `input_basis` becomes a rule with a null basis, which the
  /// resolver classifies as [RevenueTaxIncompleteRule]. It is never silently promoted to
  /// `inclusive_total` because every verified category happens to use that today — the
  /// server now refuses to create such a rule (A1), but a cache can still hold one from
  /// before that, and the honest answer is to say so.
  TaxRule _toRule(
    RevenueTaxRateRow row,
    Map<String, RevenueValueBandRow> bands,
  ) {
    final band = row.valueBandId == null ? null : bands[row.valueBandId];
    return TaxRule(
      id: row.id,
      revenueCategoryId: row.revenueCategoryId,
      rateBasisPoints: row.rateBasisPoints,
      treatment: TaxTreatment.fromName(row.treatment),
      effectiveFrom: _date(row.effectiveFrom),
      effectiveTo: row.effectiveTo == null ? null : _date(row.effectiveTo!),
      archivedAt: row.archivedAt,
      note: row.note,
      inputBasis: row.inputBasis == null
          ? null
          : EnteredBasis.fromName(row.inputBasis!),
      valueBandId: row.valueBandId,
      valueBandLabel: band?.label,
      valueBandFloor: band?.floorMinor == null
          ? null
          : Money.fromPaise(band!.floorMinor!),
      valueBandCeiling: band?.ceilingMinor == null
          ? null
          : Money.fromPaise(band!.ceilingMinor!),
      supplySubtypeId: row.supplySubtypeId,
      premisesStatusCode: row.premisesStatusCode,
    );
  }

  /// The bands an operator may choose for a NEW entry.
  ///
  /// Excludes archived bands and any band that has been **superseded**: a superseded band
  /// still explains history and must remain resolvable for entries recorded against it
  /// (B5), but offering it for new revenue would let somebody record today's sales
  /// against a tariff boundary that no longer applies.
  Future<List<RevenueValueBandRow>> selectableBands(String revenueCategoryId) =>
      (db.select(db.revenueValueBands)..where(
            (b) =>
                b.revenueCategoryId.equals(revenueCategoryId) &
                b.archivedAt.isNull() &
                b.supersededByBandId.isNull(),
          ))
          .get();

  /// Any band, superseded or not — for explaining an existing component.
  Future<RevenueValueBandRow?> bandById(String id) => (db.select(
    db.revenueValueBands,
  )..where((b) => b.id.equals(id))).getSingleOrNull();

  /// The single premises status in force for a unit on a business date, or null.
  ///
  /// The server refuses overlapping statuses with an exclusion constraint (A2), so at
  /// most one row can match. This asks the timeline the same way — `from <= date < to` —
  /// rather than taking the latest start, which would be a ranking.
  Future<BusinessUnitTaxStatusRow?> premisesStatusFor({
    required String businessUnitId,
    required BusinessDate on,
  }) async {
    final iso = on.iso;
    final rows =
        await (db.select(db.businessUnitTaxStatuses)..where(
              (s) =>
                  s.businessUnitId.equals(businessUnitId) &
                  s.archivedAt.isNull() &
                  s.effectiveFrom.isSmallerOrEqualValue(iso),
            ))
            .get();
    final applicable = [
      for (final r in rows)
        if (r.effectiveTo == null || r.effectiveTo!.compareTo(iso) > 0) r,
    ];
    // More than one would mean a corrupted cache; the caller treats it as ambiguous
    // rather than choosing.
    return applicable.length == 1 ? applicable.single : null;
  }

  /// Resolve one component's facts against the cached configuration.
  Future<RevenueTaxResolution> resolve(RevenueTaxFacts facts) async {
    if (!await hasAuthoritativeSnapshot()) {
      return const RevenueConfigurationUnavailable(
        RevenueConfigurationGap.neverSynchronised,
      );
    }
    final rules = await rulesFor(facts.revenueCategoryId);
    return rules.resolve(facts);
  }

  /// Whether a new revenue entry may be created offline, and the resolutions if so (B12).
  ///
  /// Slice 5 stops here deliberately: this returns a decision and **creates no outbox
  /// mutation**. Slice 7 consumes it.
  Future<RevenueCreateEligibility> eligibilityFor({
    required String businessUnitId,
    required String revenueCategoryId,
    required BusinessDate businessDate,
    required List<RevenueTaxFacts> components,
  }) async {
    if (components.isEmpty) {
      return const RevenueCreateEligibility.refused(
        RevenueTaxMissingFact(RevenueTaxDimension.revenueCategory),
      );
    }
    if (!await hasAuthoritativeSnapshot()) {
      return const RevenueCreateEligibility.refused(
        RevenueConfigurationUnavailable(
          RevenueConfigurationGap.neverSynchronised,
        ),
      );
    }

    final rules = await rulesFor(revenueCategoryId);
    final resolved = <RevenueTaxResolved>[];
    for (final facts in components) {
      final outcome = rules.resolve(facts);
      // The first refusal is the answer. Reporting every component's problem would be
      // noise: an unusable configuration is unusable once.
      if (outcome is! RevenueTaxResolved) {
        return RevenueCreateEligibility.refused(outcome);
      }
      resolved.add(outcome);
    }
    return RevenueCreateEligibility.allowed(resolved);
  }

  static BusinessDate _date(String iso) {
    final parts = iso.split('-').map(int.parse).toList();
    return BusinessDate.of(parts[0], parts[1], parts[2]);
  }
}
