/// The reporting synchroniser: what fills the canonical cache, and the only thing that does.
///
/// Phase 5 Slice 4. It closes the gap D-173 recorded — **neither** engine had a reporting
/// pull, so a device could only ever report what it had itself recorded, and a manager's
/// second phone showed a hotel that had earned nothing.
///
/// ## The delta asks for changed documents, not for a period
///
/// The obvious query is *"changed rows inside the year I am refreshing"*, and it is wrong
/// in a way that never surfaces as an error. A business-date correction that moves a sale
/// out of June leaves **no row in June at all**, so a June-filtered delta returns nothing
/// for it and the stale June figure stays in the cache for ever — a number that is wrong,
/// stable, and reconciles against itself.
///
/// So the delta asks for every contribution the caller may see whose document generation
/// is above the watermark, in any period, and the **document** is the unit of replacement:
/// for each retained year, every changed document has its cached rows for that year
/// deleted and its current ones inserted. The correction then works without anything
/// knowing a correction happened — June loses the rows, July gains them.
///
/// Replacement is bounded by the year so refreshing one year cannot delete another's rows
/// for a document that contributes to both (§15).
///
/// ## A void arrives as a row, and is dropped on the way in
///
/// Both projections **carry** `voided_at` rather than filtering it: a voided document
/// stays inspectable and is excluded by every aggregate (D-006). That is what makes a void
/// visible to a delta at all — the row comes back, its document is replaced, and the
/// voided rows are not stored. Active effect: zero, with nothing to remember.
///
/// The cache therefore holds only rows that count, which is why no reporting query needs
/// the canonical-only predicate that Slice 1 had to correct on one engine and not the
/// other (D-168).
///
/// ## Failure is per dataset, and that is deliberate
///
/// Revenue may synchronise while expenses do not. Each writes its own marker, so a P&L
/// over a scope with one of the two missing **refuses** rather than presenting revenue as
/// though it were profit (D-163). A run that fails changes nothing and withdraws nothing:
/// unknown is not revoked (D-048 §1), and a network failure is not evidence about a
/// property's books.
library;

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// What one dataset's run did, or why it did nothing.
sealed class DatasetSyncOutcome {
  const DatasetSyncOutcome(this.dataset);
  final ReportingDataset dataset;

  bool get isApplied => this is DatasetSynchronised;
}

/// The cache now holds this dataset's certified figures for the requested scope.
final class DatasetSynchronised extends DatasetSyncOutcome {
  const DatasetSynchronised(
    super.dataset, {
    required this.sinceGeneration,
    required this.generation,
    required this.documentsReplaced,
    required this.rowsStored,
    required this.rowsDropped,
    required this.years,
  });

  /// The watermark the delta asked from, already reduced by the safety overlap.
  final int sinceGeneration;

  /// The watermark the markers now carry.
  final int generation;

  final int documentsReplaced;
  final int rowsStored;

  /// Voided contributions the server returned and the cache did not keep.
  final int rowsDropped;

  final List<int> years;
}

/// No answer arrived. Nothing was written and no claim was withdrawn.
final class DatasetUnreachable extends DatasetSyncOutcome {
  const DatasetUnreachable(super.dataset, this.failure);
  final RemoteFailure failure;
}

/// The server declined. A person is told; nothing is retried blindly.
final class DatasetRefused extends DatasetSyncOutcome {
  const DatasetRefused(super.dataset, this.refusal);
  final ServerRefusal refusal;
}

/// One synchronisation run, over both datasets.
final class ReportingSyncReport {
  const ReportingSyncReport(this.outcomes);
  final List<DatasetSyncOutcome> outcomes;

  /// True only when **both** sides landed. A P&L needs both, so a caller that treats a
  /// half-run as success is the D-163 defect one layer up.
  bool get isComplete => outcomes.every((o) => o.isApplied);

  DatasetSyncOutcome forDataset(ReportingDataset dataset) =>
      outcomes.firstWhere((o) => o.dataset == dataset);

  @override
  String toString() =>
      'ReportingSyncReport(${outcomes.map((o) => '${o.dataset.wireName}: '
          '${o.runtimeType}').join(', ')})';
}

/// Fills the canonical reporting cache from the two server projections.
final class ReportingSync {
  ReportingSync({
    required this.cache,
    required this.gateway,
    required this.ownerUserId,
    required this.orgId,
    this.safetyOverlap = defaultSafetyOverlap,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How far below the watermark each delta re-reads.
  ///
  /// A sequence value is allocated when a row is written and becomes visible only when its
  /// transaction commits, so a naive `> max(seen)` can step over a transaction that
  /// committed late (ARCHITECTURE §5.2). Re-reading is free of consequence because
  /// replacement is keyed on document identity: the same document delivered twice lands in
  /// exactly the same state.
  ///
  /// **This is a mitigation, not a fix**, and it is sized rather than tuned: at this write
  /// volume a few hundred sequence values is far more than a commit window's worth of
  /// concurrent financial writes. The documented upgrade is a snapshot cursor, and it is
  /// recorded as a known limitation rather than an unknown one.
  static const defaultSafetyOverlap = 500;

  final ReportingCache cache;
  final ReportingGateway gateway;
  final String ownerUserId;
  final String orgId;
  final int safetyOverlap;
  final DateTime Function() _clock;

  /// Synchronises both datasets for [businessUnitIds] over [years].
  ///
  /// [onDemand] marks the coverage as fetched outside normal retention, so pruning can
  /// tell a year somebody deliberately asked for from one that is merely current (§15).
  Future<ReportingSyncReport> synchronise({
    required Set<String> businessUnitIds,
    required List<FinancialYear> years,
    bool onDemand = false,
  }) async {
    if (businessUnitIds.isEmpty || years.isEmpty) {
      // Nothing to certify. Deliberately not an error and deliberately not a marker: a run
      // over no scope proves nothing about any scope.
      return ReportingSyncReport([
        for (final dataset in ReportingDataset.values)
          DatasetSynchronised(
            dataset,
            sinceGeneration: 0,
            generation: 0,
            documentsReplaced: 0,
            rowsStored: 0,
            rowsDropped: 0,
            years: const [],
          ),
      ]);
    }

    return ReportingSyncReport([
      for (final dataset in ReportingDataset.values)
        await _synchroniseDataset(
          dataset: dataset,
          businessUnitIds: businessUnitIds,
          years: years,
          onDemand: onDemand,
        ),
    ]);
  }

  Future<DatasetSyncOutcome> _synchroniseDataset({
    required ReportingDataset dataset,
    required Set<String> businessUnitIds,
    required List<FinancialYear> years,
    required bool onDemand,
  }) async {
    final markers = await cache.markersFor(ownerUserId);
    final held = <String, int>{
      for (final marker in markers)
        if (marker.dataset == dataset)
          '${marker.businessUnitId}/${marker.financialYear}': marker.generation,
    };

    // The watermark is the **lowest** any requested scope has reached, and a scope with no
    // marker takes it to zero. Anything higher would ask the server for changes since a
    // point this scope never reached, and the rows in between would never be delivered —
    // a gap that no later run can notice, because the watermark says they arrived.
    var since = 1 << 62;
    for (final unit in businessUnitIds) {
      for (final year in years) {
        since = _min(since, held['$unit/${year.openingYear}'] ?? 0);
      }
    }
    final askFrom = since - safetyOverlap < 0 ? 0 : since - safetyOverlap;

    final outcome = await gateway.changedContributions(
      dataset: dataset,
      sinceGeneration: askFrom,
    );
    switch (outcome) {
      case RemoteUnreachable(:final failure):
        return DatasetUnreachable(dataset, failure);
      case RemoteRefused(:final refusal):
        return DatasetRefused(dataset, refusal);
      case RemoteOk(:final value):
        return _apply(
          dataset: dataset,
          rows: value,
          businessUnitIds: businessUnitIds,
          years: years,
          held: held,
          askFrom: askFrom,
          onDemand: onDemand,
        );
    }
  }

  Future<DatasetSyncOutcome> _apply({
    required ReportingDataset dataset,
    required List<Map<String, dynamic>> rows,
    required Set<String> businessUnitIds,
    required List<FinancialYear> years,
    required Map<String, int> held,
    required int askFrom,
    required bool onDemand,
  }) async {
    // Every document the delta named, whatever period its rows landed in. This is the set
    // whose cached rows are replaced, and it deliberately includes documents that came
    // back **only** as voided rows and documents whose rows are now in a year this run is
    // not refreshing — both of which are how a stale figure would otherwise survive.
    final documents = <String>{};
    final keep = <int, List<ReportingRowValues>>{};
    var dropped = 0;
    var generation = 0;

    for (final row in rows) {
      final documentId = row[dataset.documentColumn] as String;
      documents.add(documentId);

      final seq = (row['change_seq'] as num?)?.toInt() ?? 0;
      if (seq > generation) generation = seq;

      // A voided document contributes nothing and is not stored. Its rows still counted
      // above, which is the whole point: the document is replaced by nothing.
      if (row['voided_at'] != null) {
        dropped++;
        continue;
      }

      final pnlDate = row['pnl_date'] as String;
      final date = BusinessDate.tryParse(pnlDate);
      if (date == null) {
        // A projection that cannot state a P&L date cannot be attributed to a period, and
        // guessing one would decide which month a figure lands in. Refused, not repaired
        // — the discipline D-043 and §19.5 both set for configuration, applied to money.
        throw StateError(
          'reporting delta carried an unparseable pnl_date "$pnlDate" for '
          '${dataset.wireName} document $documentId',
        );
      }
      final year = FinancialYear.of(date).openingYear;
      (keep[year] ??= []).add(_valuesFor(dataset, row, pnlDate));
    }

    var stored = 0;
    final applied = <int>[];
    final now = _clock();

    for (final year in years) {
      final forYear = keep[year.openingYear] ?? const <ReportingRowValues>[];

      // The generation every scope in this run is certified to. One run is one
      // authoritative boundary, so a unit that happened to have no changed document is
      // certified to the same point as one that did (§21) — otherwise a quiet property
      // would drift permanently behind a busy one and re-read the same delta for ever.
      final certified = _max(
        generation,
        _maxHeldFor(held, businessUnitIds, year.openingYear),
      );

      await cache.applyYear(
        ownerUserId: ownerUserId,
        orgId: orgId,
        dataset: dataset,
        financialYear: year.openingYear,
        businessUnitIds: businessUnitIds,
        documentIds: documents.toList(),
        rows: forYear,
        generation: certified,
        onDemand: onDemand,
        now: now,
      );

      stored += forYear.length;
      applied.add(year.openingYear);
    }

    return DatasetSynchronised(
      dataset,
      sinceGeneration: askFrom,
      generation: generation,
      documentsReplaced: documents.length,
      rowsStored: stored,
      rowsDropped: dropped,
      years: applied,
    );
  }

  ReportingRowValues _valuesFor(
    ReportingDataset dataset,
    Map<String, dynamic> row,
    String pnlDate,
  ) => switch (dataset) {
    ReportingDataset.revenue => RevenueRowValues(
      contributionId: row['id'] as String,
      revenueEntryId: row['revenue_entry_id'] as String,
      businessUnitId: row['business_unit_id'] as String,
      revenueCategoryId: row['revenue_category_id'] as String,
      pnlDate: pnlDate,
      pnlPeriodKey: row['pnl_period_key'] as String,
      grossMinor: (row['gross_minor'] as num).toInt(),
      taxMinor: (row['tax_minor'] as num).toInt(),
      netMinor: (row['net_minor'] as num).toInt(),
      taxTreatment: row['tax_treatment'] as String,
      taxRateBasisPoints: (row['tax_rate_bp'] as num?)?.toInt() ?? 0,
      enteredBasis: row['entered_basis'] as String,
      valueBandId: row['value_band_id'] as String?,
      supplySubtypeId: row['supply_subtype_id'] as String?,
      documentGeneration: (row['change_seq'] as num?)?.toInt() ?? 0,
    ),
    ReportingDataset.expense => ExpenseRowValues(
      contributionId: row['id'] as String,
      expenseId: row['expense_id'] as String,
      allocationId: row['allocation_id'] as String,
      businessUnitId: row['business_unit_id'] as String,
      departmentId: row['department_id'] as String,
      sectionId: row['section_id'] as String,
      categoryId: row['category_id'] as String,
      vendorId: row['vendor_id'] as String?,
      pnlDate: pnlDate,
      pnlPeriodKey: row['pnl_period_key'] as String,
      amountMinor: (row['amount_minor'] as num).toInt(),
      documentGeneration: (row['change_seq'] as num?)?.toInt() ?? 0,
    ),
  };

  static int _maxHeldFor(Map<String, int> held, Set<String> units, int year) {
    var highest = 0;
    for (final unit in units) {
      highest = _max(highest, held['$unit/$year'] ?? 0);
    }
    return highest;
  }

  static int _min(int a, int b) => a < b ? a : b;
  static int _max(int a, int b) => a > b ? a : b;
}

/// Retention: current and previous financial year, plus whatever was asked for on demand.
///
/// A separate object because pruning is a **different decision** from synchronising, taken
/// on a different clock. Folding it into a run would mean a device that synchronises on
/// 1 April silently loses the year it was reporting five minutes earlier, in the same call
/// that was supposed to refresh it.
final class ReportingRetention {
  const ReportingRetention(this.cache);

  final ReportingCache cache;

  /// The years normal retention keeps, given today's business date (§15, D8).
  static List<FinancialYear> retainedAt(BusinessDate today) {
    final current = FinancialYear.of(today);
    return [current.previous, current];
  }

  /// Removes every year this owner holds that retention does not keep and nobody asked
  /// for on demand.
  ///
  /// An on-demand year survives: somebody deliberately fetched it, and deleting it under
  /// them would make the older-range workflow useless in exactly the case it exists for.
  Future<List<int>> prune({
    required String ownerUserId,
    required BusinessDate today,
  }) async {
    final keep = {for (final year in retainedAt(today)) year.openingYear};
    final markers = await cache.markersFor(ownerUserId);

    final pruned = <int>[];
    for (final year in {for (final marker in markers) marker.financialYear}) {
      if (keep.contains(year)) continue;
      final requested = markers.any(
        (m) => m.financialYear == year && m.onDemand,
      );
      if (requested) continue;
      await cache.pruneYear(ownerUserId: ownerUserId, financialYear: year);
      pruned.add(year);
    }
    return pruned..sort();
  }
}
