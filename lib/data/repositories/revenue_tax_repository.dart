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

/// The datasets a revenue configuration snapshot must contain to be complete.
///
/// **All four, or none.** Slice 5's resolver consults every one of them: a rule may name a
/// value band, a supply subtype and a premises status, and a rule that names one the
/// device never received resolves to `missingFact` — which reads as *"choose a band"* to
/// an operator who has no band to choose. Tax rules arriving therefore proves nothing
/// about the other three, and a snapshot that stopped after the first is not a
/// synchronised configuration; it is a half-synchronised one wearing the same label.
///
/// Zero rows in a dataset is a perfectly good synchronised answer (the verified baseline
/// has no bands, no subtypes and no statuses). *Never having asked* is not.
enum RevenueConfigDataset {
  taxRules('rules'),
  valueBands('bands'),
  supplySubtypes('subtypes'),
  premisesStatuses('statuses');

  const RevenueConfigDataset(this.code);

  final String code;

  /// Sorted and comma-joined, so the stored form is canonical and comparable.
  static String encode(Set<RevenueConfigDataset> datasets) =>
      (datasets.map((d) => d.code).toList()..sort()).join(',');

  static Set<RevenueConfigDataset> decode(String stored) => {
    for (final code in stored.split(','))
      for (final d in RevenueConfigDataset.values)
        if (d.code == code) d,
  };

  static Set<RevenueConfigDataset> get all =>
      RevenueConfigDataset.values.toSet();
}

/// What this device can honestly say about one user's configuration for one unit.
sealed class RevenueConfigCompleteness {
  const RevenueConfigCompleteness();
}

/// Every required dataset was received for this scope, in one logical snapshot.
final class RevenueConfigComplete extends RevenueConfigCompleteness {
  const RevenueConfigComplete({
    required this.generation,
    required this.confirmedAt,
  });

  /// The server generation the snapshot came from, so two runs cannot be mistaken for one.
  final String? generation;

  /// Server time, from the confirmed authority — never the device clock.
  final DateTime? confirmedAt;
}

/// Nothing authoritative has ever been received here for this scope.
final class RevenueConfigNeverSynchronised extends RevenueConfigCompleteness {
  const RevenueConfigNeverSynchronised();
}

/// It was received, and the authority to hold it has since been withdrawn (D-070).
final class RevenueConfigRevoked extends RevenueConfigCompleteness {
  const RevenueConfigRevoked();
}

/// Some datasets arrived and others did not, so the snapshot is not one snapshot.
///
/// Slice 6 never writes this state — the marker is written last, inside the transaction,
/// only when everything succeeded. It exists because a device can be *read* in it after a
/// crash between writes on some future code path, and the honest answer then is that the
/// configuration is unavailable rather than that the Owner configured nothing.
final class RevenueConfigIncomplete extends RevenueConfigCompleteness {
  const RevenueConfigIncomplete(this.missing);

  final Set<RevenueConfigDataset> missing;
}

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

  /// What this device can honestly claim for one user and one business unit.
  ///
  /// Read from the completeness record rather than inferred from row counts: a confirmed
  /// revocation legitimately empties the rule cache (D-070), and "no rows" must never be
  /// promoted to "no rules exist in the organisation".
  Future<RevenueConfigCompleteness> completenessFor({
    required String userId,
    required String businessUnitId,
  }) async {
    final row =
        await (db.select(db.revenueConfigSnapshots)..where(
              (r) =>
                  r.userId.equals(userId) &
                  r.businessUnitId.equals(businessUnitId),
            ))
            .getSingleOrNull();

    if (row == null) return const RevenueConfigNeverSynchronised();
    if (row.status == 'revoked') return const RevenueConfigRevoked();

    final held = RevenueConfigDataset.decode(row.datasets);
    final missing = RevenueConfigDataset.all.difference(held);
    if (missing.isNotEmpty) return RevenueConfigIncomplete(missing);

    return RevenueConfigComplete(
      generation: row.generation,
      confirmedAt: row.confirmedAt,
    );
  }

  /// The business unit a cached revenue category belongs to, or null if unknown here.
  ///
  /// Resolution is scoped by unit, and the facts name a category, so this hop is how the
  /// two meet. A category the device does not hold is itself evidence that this scope was
  /// never synchronised — it is not an excuse to answer for the whole organisation.
  Future<String?> unitForCategory(String revenueCategoryId) async {
    final row = await (db.select(
      db.revenueCategories,
    )..where((c) => c.id.equals(revenueCategoryId))).getSingleOrNull();
    return row?.businessUnitId;
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

  /// Turns a completeness state into the resolution outcome it implies, or null when the
  /// device may proceed to consult the cache.
  ///
  /// Every non-complete state stops the entry, and each says something different. Only
  /// `complete` means the silence that follows — no matching rule — is a statement about
  /// the organisation's configuration rather than about this device (D-106).
  RevenueTaxResolution? _blockedBy(RevenueConfigCompleteness state) =>
      switch (state) {
        RevenueConfigComplete() => null,
        RevenueConfigRevoked() => const RevenueConfigurationUnavailable(
          RevenueConfigurationGap.revoked,
        ),
        RevenueConfigNeverSynchronised() ||
        RevenueConfigIncomplete() => const RevenueConfigurationUnavailable(
          RevenueConfigurationGap.neverSynchronised,
        ),
      };

  /// Resolve one component's facts against the cached configuration.
  ///
  /// [userId] and [businessUnitId] are both required, and neither is derived.
  ///
  /// Authority is per person on a shared workstation (D-051, D-074), so a signature that
  /// let the user be omitted would be one that lets somebody else's successful sync vouch
  /// for this scope. And the unit is **passed rather than looked up from the category**:
  /// a confirmed revocation legitimately deletes the category row (D-070), so deriving
  /// the scope from the cache would turn a revocation into "never synchronised" — losing
  /// the one distinction this whole path exists to preserve. Every caller picks a
  /// property before a category, so the fact is already in hand.
  Future<RevenueTaxResolution> resolve(
    RevenueTaxFacts facts, {
    required String userId,
    required String businessUnitId,
  }) async {
    final blocked = _blockedBy(
      await completenessFor(userId: userId, businessUnitId: businessUnitId),
    );
    if (blocked != null) return blocked;

    final rules = await rulesFor(facts.revenueCategoryId);
    return rules.resolve(facts);
  }

  /// Whether a new revenue entry may be created offline, and the resolutions if so (B12).
  ///
  /// Slice 5 stops here deliberately: this returns a decision and **creates no outbox
  /// mutation**. Slice 7 consumes it.
  Future<RevenueCreateEligibility> eligibilityFor({
    required String userId,
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

    final blocked = _blockedBy(
      await completenessFor(userId: userId, businessUnitId: businessUnitId),
    );
    if (blocked != null) return RevenueCreateEligibility.refused(blocked);

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
