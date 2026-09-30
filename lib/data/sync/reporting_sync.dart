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

import 'dart:convert';

import 'package:krishna_mis/data/local/cache_authority_generation.dart';
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

/// The session or authority this run was started under ended before its answer could be
/// applied (D-231). Nothing was written — not a row, not a marker, not snapshot evidence —
/// and it is neither a failure to report nor a success to certify.
final class DatasetAbandoned extends DatasetSyncOutcome {
  const DatasetAbandoned(super.dataset);
}

/// The server declined. A person is told; nothing is retried blindly.
final class DatasetRefused extends DatasetSyncOutcome {
  const DatasetRefused(super.dataset, this.refusal);
  final ServerRefusal refusal;
}

/// What a freshness confirmation established, if anything.
///
/// [confirmed] is the load-bearing field: a transport failure answers *unknown*, never
/// *up to date* and never *newer*. Not being able to ask is not an answer, and treating it
/// as one is how a report starts making claims about a server nobody reached.
final class ReportingHeadCheck {
  const ReportingHeadCheck({
    required this.confirmed,
    required this.serverHasNewer,
    this.serverTime,
  });

  const ReportingHeadCheck.unknown()
    : confirmed = false,
      serverHasNewer = false,
      serverTime = null;

  /// Whether the server actually answered.
  final bool confirmed;

  /// Whether canonical reporting facts in scope have moved past what this device holds.
  /// Meaningless unless [confirmed].
  final bool serverHasNewer;

  final DateTime? serverTime;
}

/// One synchronisation run, over both datasets.
final class ReportingSyncReport {
  const ReportingSyncReport(
    this.outcomes, {
    this.snapshotId,
    this.serverConfirmedAt,
    this.pages = 1,
  });

  final List<DatasetSyncOutcome> outcomes;

  /// How many bounded pages the run read (D-320). One for an ordinary delta.
  final int pages;

  /// The authoritative snapshot every segment of this run was certified from, and the
  /// server's own time for it. Null when nothing was certified — a run that failed
  /// carries no evidence rather than weak evidence.
  final String? snapshotId;
  final DateTime? serverConfirmedAt;

  /// True only when **both** sides landed. A P&L needs both, so a caller that treats a
  /// half-run as success is the D-163 defect one layer up.
  bool get isComplete => outcomes.every((o) => o.isApplied);

  /// True when the run was superseded by a session or authority transition and wrote
  /// nothing (D-231).
  bool get abandoned => outcomes.any((o) => o is DatasetAbandoned);

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
    this.pageDocuments = ReportingPageCursor.defaultPageDocuments,
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

  /// How many documents per dataset one page carries (D-320). The server clamps it to
  /// 1 … 2,000; a page never splits a document.
  final int pageDocuments;
  final DateTime Function() _clock;

  /// Synchronises both datasets for [businessUnitIds] over [years].
  ///
  /// **Bounded pages, one publication** (D-188, D-320). Each page is one server statement
  /// over one MVCC snapshot; the pages of a run are staged and published together, with
  /// the final page's snapshot as the run's evidence, so the cache never holds a
  /// half-published run and never holds revenue from one run beside expenses from another.
  ///
  /// [onDemand] marks the coverage as fetched outside normal retention, so pruning can
  /// tell a year somebody deliberately asked for from one that is merely current.
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

    // D-231: the generation this run belongs to, taken before anything is asked. The write
    // re-checks it inside its own transaction.
    final startedUnder = await CacheAuthorityGeneration(cache.database).read();

    final markers = await cache.markersFor(ownerUserId);
    final held = <ReportingDataset, Map<String, int>>{
      for (final dataset in ReportingDataset.values)
        dataset: {
          for (final marker in markers)
            if (marker.dataset == dataset)
              '${marker.businessUnitId}/${marker.financialYear}':
                  marker.generation,
        },
    };

    // The watermark is the **lowest** any requested scope has reached, and a scope with no
    // marker takes it to zero. Anything higher would ask the server for changes since a
    // point this scope never reached, and the rows in between would never be delivered —
    // a gap that no later run can notice, because the watermark says they arrived.
    final askFrom = <ReportingDataset, int>{};
    for (final dataset in ReportingDataset.values) {
      var since = 1 << 62;
      for (final unit in businessUnitIds) {
        for (final year in years) {
          since = _min(since, held[dataset]!['$unit/${year.openingYear}'] ?? 0);
        }
      }
      askFrom[dataset] = since - safetyOverlap < 0 ? 0 : since - safetyOverlap;
    }

    return _runPages(
      businessUnitIds: businessUnitIds,
      years: years,
      held: held,
      askFrom: askFrom,
      onDemand: onDemand,
      startedUnder: startedUnder,
    );
  }

  /// Asks whether canonical reporting facts have moved past what this device holds.
  ///
  /// Scope-relevant by construction: it compares against the two contribution
  /// projections, so a master, tax-configuration or audit-only mutation cannot make a P&L
  /// look outdated. A transport failure answers *unknown* and never *newer* — a network
  /// that could not be reached has proven nothing about the server's state.
  Future<ReportingHeadCheck> checkForNewer({
    required Set<String> businessUnitIds,
    required List<FinancialYear> years,
  }) async {
    if (businessUnitIds.isEmpty || years.isEmpty) {
      return const ReportingHeadCheck.unknown();
    }
    final markers = await cache.markersFor(ownerUserId);
    final cursors = <ReportingDataset, int>{};
    for (final dataset in ReportingDataset.values) {
      var since = 1 << 62;
      for (final unit in businessUnitIds) {
        for (final year in years) {
          final held = markers
              .where(
                (m) =>
                    m.dataset == dataset &&
                    m.businessUnitId == unit &&
                    m.financialYear == year.openingYear,
              )
              .map((m) => m.generation)
              .toList();
          since = _min(since, held.isEmpty ? 0 : held.first);
        }
      }
      cursors[dataset] = since == 1 << 62 ? 0 : since;
    }

    final outcome = await gateway.newerThan(
      businessUnitIds: businessUnitIds.toList(),
      revenueSince: cursors[ReportingDataset.revenue]!,
      expenseSince: cursors[ReportingDataset.expense]!,
    );
    return switch (outcome) {
      RemoteOk(:final value) => ReportingHeadCheck(
        confirmed: true,
        serverHasNewer:
            (value['revenue_newer'] as bool? ?? false) ||
            (value['expense_newer'] as bool? ?? false),
        serverTime: _serverTime(value['server_time']),
      ),
      _ => const ReportingHeadCheck.unknown(),
    };
  }

  /// Walks the answer in bounded pages (D-320) and publishes it whole.
  ///
  /// Every page but the last is **staged** — under a key no reader asks for — and the
  /// last one publishes everything in one transaction, carrying the final page's snapshot
  /// evidence. So the cache moves from one coherent snapshot to the next or not at all:
  /// an interrupted run publishes nothing, and the next run resumes from its cursor when
  /// the scope, the owner and the authority generation are all unchanged, and otherwise
  /// discards what it staged and starts again.
  Future<ReportingSyncReport> _runPages({
    required Set<String> businessUnitIds,
    required List<FinancialYear> years,
    required Map<ReportingDataset, Map<String, int>> held,
    required Map<ReportingDataset, int> askFrom,
    required bool onDemand,
    required CacheGeneration? startedUnder,
  }) async {
    final unitList = businessUnitIds.toList()..sort();
    final yearList = [for (final year in years) year.openingYear]..sort();
    // A dataset asked from zero is a first synchronisation of its segment: the server lists
    // only documents with a row in the requested years, so the segment is replaced whole.
    final bootstrap = {
      for (final dataset in ReportingDataset.values)
        if (askFrom[dataset] == 0) dataset,
    };
    final scope = <String, dynamic>{
      'units': unitList,
      'years': yearList,
      'on_demand': onDemand,
      'revenue_since': askFrom[ReportingDataset.revenue],
      'expense_since': askFrom[ReportingDataset.expense],
      'page_documents': pageDocuments,
      'epoch': startedUnder?.epoch,
      'user': startedUnder?.userId,
    };

    var run = _PageRun(scope);
    final saved = await cache.readResume(ownerUserId);
    if (saved != null) {
      final resumed = _PageRun.resume(saved, scope);
      if (resumed != null) {
        run = resumed;
      } else {
        // Staged for a different scope, owner or authority: none of it may be published.
        await cache.discardStaged(ownerUserId);
      }
    }

    Future<void> stillCurrent() => CacheAuthorityGeneration(
      cache.database,
    ).ensureStillCurrent(startedUnder: startedUnder, ownerUserId: ownerUserId);

    while (true) {
      final outcome = await gateway.snapshot(
        businessUnitIds: unitList,
        revenueSince: askFrom[ReportingDataset.revenue]!,
        expenseSince: askFrom[ReportingDataset.expense]!,
        financialYears: yearList,
        after: run.cursor,
        pageDocuments: pageDocuments,
      );

      final Map<String, dynamic> response;
      switch (outcome) {
        case RemoteUnreachable(:final failure):
          // Unknown is not revoked (D-048 section 1). Nothing published, nothing withdrawn;
          // what was staged stays staged so the next run resumes rather than restarts.
          return ReportingSyncReport([
            for (final dataset in ReportingDataset.values)
              DatasetUnreachable(dataset, failure),
          ]);
        case RemoteRefused(:final refusal):
          await cache.discardStaged(ownerUserId);
          return ReportingSyncReport([
            for (final dataset in ReportingDataset.values)
              DatasetRefused(dataset, refusal),
          ]);
        case RemoteOk(:final value):
          response = value;
      }

      final page = _parsePage(response, businessUnitIds, years);

      // The authority the server applied must not move between the pages of one run: rows
      // staged under the earlier answer may belong to a property this caller has since
      // lost, and publishing them would certify what the server no longer grants.
      if (run.authorised != null &&
          !_sameSet(run.authorised!, page.authorised)) {
        await cache.discardStaged(ownerUserId);
        return ReportingSyncReport([
          for (final dataset in ReportingDataset.values)
            DatasetAbandoned(dataset),
        ]);
      }
      run.authorised ??= page.authorised;

      if (page.authorised.isEmpty) {
        await cache.discardStaged(ownerUserId);
        return ReportingSyncReport([
          for (final dataset in ReportingDataset.values)
            DatasetSynchronised(
              dataset,
              sinceGeneration: askFrom[dataset]!,
              generation: 0,
              documentsReplaced: 0,
              rowsStored: 0,
              rowsDropped: 0,
              years: const [],
            ),
        ], pages: run.pages + 1);
      }

      run.absorb(page, bootstrap);

      if (page.hasMore) {
        final next = page.nextCursor(run.cursor);
        if (_sameCursor(next, run.cursor)) {
          // A page that says there is more but does not advance would loop for ever.
          throw StateError(
            'reporting snapshot page reported more documents without advancing its '
            'cursor (D-320)',
          );
        }
        run.cursor = next;
        run.pages++;
        try {
          await cache.stagePage(
            ownerUserId: ownerUserId,
            orgId: orgId,
            financialYears: yearList,
            datasets: page.applications,
            resumeState: run.toJson(),
            now: _clock(),
            stillCurrent: stillCurrent,
          );
        } on StaleCacheGeneration {
          await cache.discardStaged(ownerUserId);
          return _abandoned();
        }
        continue;
      }

      // The final page: every year certified to the highest document generation the run
      // saw, or to what this scope already held if that is higher — one run is one
      // authoritative boundary, so a quiet property is certified with a busy one.
      final finalPage = <ReportingDataset, DatasetApplication>{
        for (final dataset in ReportingDataset.values)
          dataset: DatasetApplication(
            documentIds: page.applications[dataset]!.documentIds,
            rowsByYear: {
              for (final year in yearList)
                year: page.applications[dataset]!.rowsFor(year),
            },
            generationByYear: {
              for (final year in yearList)
                year: _max(
                  run.maxSeq[dataset]!,
                  _maxHeldFor(held[dataset]!, page.authorised, year),
                ),
            },
          ),
      };

      try {
        if (run.pages == 0) {
          await cache.applySnapshot(
            ownerUserId: ownerUserId,
            orgId: orgId,
            snapshotId: page.snapshotId,
            serverConfirmedAt: page.serverTime,
            businessUnitIds: page.authorised,
            financialYears: yearList,
            datasets: finalPage,
            onDemand: onDemand,
            now: _clock(),
            stillCurrent: stillCurrent,
            bootstrapDatasets: bootstrap,
          );
        } else {
          await cache.publishRun(
            ownerUserId: ownerUserId,
            orgId: orgId,
            snapshotId: page.snapshotId,
            serverConfirmedAt: page.serverTime,
            businessUnitIds: page.authorised,
            financialYears: yearList,
            finalPage: finalPage,
            bootstrapDatasets: bootstrap,
            clearedDocuments: {
              for (final dataset in ReportingDataset.values)
                dataset: run.cleared[dataset]!.toList(),
            },
            onDemand: onDemand,
            now: _clock(),
            stillCurrent: stillCurrent,
          );
        }
      } on StaleCacheGeneration {
        await cache.discardStaged(ownerUserId);
        return _abandoned();
      }

      return ReportingSyncReport(
        [
          for (final dataset in ReportingDataset.values)
            DatasetSynchronised(
              dataset,
              sinceGeneration: askFrom[dataset]!,
              generation: run.maxSeq[dataset]!,
              documentsReplaced: run.documents[dataset]!,
              rowsStored: run.rowsStored[dataset]!,
              rowsDropped: run.rowsDropped[dataset]!,
              years: yearList,
            ),
        ],
        snapshotId: page.snapshotId,
        serverConfirmedAt: page.serverTime,
        pages: run.pages + 1,
      );
    }
  }

  static ReportingSyncReport _abandoned() => ReportingSyncReport([
    for (final dataset in ReportingDataset.values) DatasetAbandoned(dataset),
  ]);

  _Page _parsePage(
    Map<String, dynamic> response,
    Set<String> businessUnitIds,
    List<FinancialYear> years,
  ) {
    final snapshotId = response['snapshot_id'] as String?;
    final serverTime = _serverTime(response['server_time']);
    if (snapshotId == null || serverTime == null) {
      // Without both, nothing downstream could honestly say what moment these facts are.
      // Refusing to certify is the fail-closed answer, and the previous snapshot survives.
      throw StateError(
        'reporting snapshot carried no snapshot identity or no server time - a '
        'synchronised-as-of claim cannot be built from a device clock (D-188)',
      );
    }

    // Only properties the server itself said are reporting-authorised may be certified.
    // Certifying a unit whose rows were withheld would claim complete coverage over an
    // empty set, which is the false-completeness failure the marker exists to prevent.
    final authorised = <String>{
      for (final entry in (response['units'] as List? ?? const []))
        if ((entry as Map)['reporting_authorised'] == true)
          entry['business_unit_id'] as String,
    }..retainAll(businessUnitIds);

    final applications = <ReportingDataset, DatasetApplication>{};
    final listed = <ReportingDataset, List<({String id, int seq})>>{};
    final withRows = <ReportingDataset, Set<String>>{};
    final dropped = <ReportingDataset, int>{};
    final hasMore = <ReportingDataset, bool>{};

    for (final dataset in ReportingDataset.values) {
      final rows = [
        for (final row in (response[dataset.wireName] as List? ?? const []))
          Map<String, dynamic>.from(row as Map),
      ];

      // The documents this page speaks for, in cursor order. A server that lists them
      // lets a document with no row left in the requested years be cleared; an older
      // answer without the list speaks for exactly the documents its rows name.
      final documents = <({String id, int seq})>[];
      final named = <String>{};
      final declared = response['${dataset.wireName}_documents'];
      if (declared is List) {
        for (final entry in declared) {
          final map = entry as Map;
          final id = map['id'] as String;
          if (named.add(id)) {
            documents.add((id: id, seq: (map['seq'] as num?)?.toInt() ?? 0));
          }
        }
      }

      final keep = <int, List<ReportingRowValues>>{};
      final kept = <String>{};
      final requestedYears = {for (final year in years) year.openingYear};
      var droppedHere = 0;

      for (final row in rows) {
        final documentId = row[dataset.documentColumn] as String;
        final seq = _documentSeqOf(row);
        if (named.add(documentId)) documents.add((id: documentId, seq: seq));

        // A voided document contributes nothing and is not stored. It is still listed,
        // which is the whole point: the document is replaced by nothing.
        if (row['voided_at'] != null) {
          droppedHere++;
          continue;
        }

        final pnlDate = row['pnl_date'] as String;
        final date = BusinessDate.tryParse(pnlDate);
        if (date == null) {
          // A projection that cannot state a P&L date cannot be attributed to a period,
          // and guessing one would decide which month a figure lands in. Refused, not
          // repaired - the discipline D-043 sets for configuration, applied to money.
          throw StateError(
            'reporting snapshot carried an unparseable pnl_date "$pnlDate" for '
            '${dataset.wireName} document $documentId',
          );
        }
        final year = FinancialYear.of(date).openingYear;
        (keep[year] ??= []).add(_valuesFor(dataset, row, pnlDate));
        if (requestedYears.contains(year)) kept.add(documentId);
      }

      applications[dataset] = DatasetApplication(
        documentIds: [for (final document in documents) document.id],
        rowsByYear: {
          for (final year in years)
            year.openingYear:
                keep[year.openingYear] ?? const <ReportingRowValues>[],
        },
        generationByYear: const {},
      );
      listed[dataset] = documents;
      withRows[dataset] = kept;
      dropped[dataset] = droppedHere;
      hasMore[dataset] = response['${dataset.wireName}_has_more'] == true;
    }

    return _Page(
      snapshotId: snapshotId,
      serverTime: serverTime,
      authorised: authorised,
      applications: applications,
      listed: listed,
      withRows: withRows,
      dropped: dropped,
      hasMoreByDataset: hasMore,
    );
  }

  static int _documentSeqOf(Map<String, dynamic> row) =>
      (row['document_change_seq'] as num?)?.toInt() ??
      (row['change_seq'] as num?)?.toInt() ??
      0;

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  static bool _sameCursor(ReportingPageCursor a, ReportingPageCursor b) =>
      a.revenueSeq == b.revenueSeq &&
      a.revenueId == b.revenueId &&
      a.expenseSeq == b.expenseSeq &&
      a.expenseId == b.expenseId;

  static DateTime? _serverTime(Object? value) => switch (value) {
    String text => DateTime.tryParse(text)?.toUtc(),
    DateTime time => time.toUtc(),
    _ => null,
  };

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
      documentGeneration: _documentSeqOf(row),
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
      documentGeneration: _documentSeqOf(row),
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

/// One parsed page of a paged snapshot (D-320).
final class _Page {
  _Page({
    required this.snapshotId,
    required this.serverTime,
    required this.authorised,
    required this.applications,
    required this.listed,
    required this.withRows,
    required this.dropped,
    required this.hasMoreByDataset,
  });

  final String snapshotId;
  final DateTime serverTime;
  final Set<String> authorised;
  final Map<ReportingDataset, DatasetApplication> applications;

  /// The documents this page speaks for, per dataset, in cursor order.
  final Map<ReportingDataset, List<({String id, int seq})>> listed;

  /// The documents with at least one active row in the requested years.
  final Map<ReportingDataset, Set<String>> withRows;
  final Map<ReportingDataset, int> dropped;
  final Map<ReportingDataset, bool> hasMoreByDataset;

  bool get hasMore => hasMoreByDataset.values.any((more) => more);

  /// Where the next page starts: after the last document this page listed, per dataset.
  /// A dataset this page listed nothing for keeps its cursor.
  ReportingPageCursor nextCursor(ReportingPageCursor current) {
    final revenue = listed[ReportingDataset.revenue]!;
    final expense = listed[ReportingDataset.expense]!;
    return ReportingPageCursor(
      revenueSeq: revenue.isEmpty ? current.revenueSeq : revenue.last.seq,
      revenueId: revenue.isEmpty ? current.revenueId : revenue.last.id,
      expenseSeq: expense.isEmpty ? current.expenseSeq : expense.last.seq,
      expenseId: expense.isEmpty ? current.expenseId : expense.last.id,
    );
  }
}

/// The state of one run across its pages, and what it resumes from (D-320).
///
/// It carries cursors, scope and document identities — never a figure. Figures live in
/// the staged rows, under the same encryption and purge rules as every other cache row.
final class _PageRun {
  _PageRun(this.scope);

  final Map<String, dynamic> scope;
  ReportingPageCursor cursor = const ReportingPageCursor.start();
  Set<String>? authorised;
  int pages = 0;

  final Map<ReportingDataset, int> maxSeq = {
    for (final dataset in ReportingDataset.values) dataset: 0,
  };
  final Map<ReportingDataset, int> documents = {
    for (final dataset in ReportingDataset.values) dataset: 0,
  };
  final Map<ReportingDataset, int> rowsStored = {
    for (final dataset in ReportingDataset.values) dataset: 0,
  };
  final Map<ReportingDataset, int> rowsDropped = {
    for (final dataset in ReportingDataset.values) dataset: 0,
  };

  /// Documents a delta listed with no active row left in the requested years: their held
  /// rows must go at publication, because nothing staged will name them.
  final Map<ReportingDataset, Set<String>> cleared = {
    for (final dataset in ReportingDataset.values) dataset: <String>{},
  };

  void absorb(_Page page, Set<ReportingDataset> bootstrap) {
    for (final dataset in ReportingDataset.values) {
      for (final document in page.listed[dataset]!) {
        if (document.seq > maxSeq[dataset]!) maxSeq[dataset] = document.seq;
      }
      documents[dataset] = documents[dataset]! + page.listed[dataset]!.length;
      rowsStored[dataset] =
          rowsStored[dataset]! +
          page.applications[dataset]!.rowsByYear.values.fold<int>(
            0,
            (total, rows) => total + rows.length,
          );
      rowsDropped[dataset] = rowsDropped[dataset]! + page.dropped[dataset]!;
      if (!bootstrap.contains(dataset)) {
        for (final document in page.listed[dataset]!) {
          if (!page.withRows[dataset]!.contains(document.id)) {
            cleared[dataset]!.add(document.id);
          }
        }
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'scope': scope,
    'cursor': {
      'revenue_seq': cursor.revenueSeq,
      'revenue_id': cursor.revenueId,
      'expense_seq': cursor.expenseSeq,
      'expense_id': cursor.expenseId,
    },
    'authorised': authorised?.toList(),
    'pages': pages,
    for (final dataset in ReportingDataset.values)
      dataset.wireName: {
        'max_seq': maxSeq[dataset],
        'documents': documents[dataset],
        'rows_stored': rowsStored[dataset],
        'rows_dropped': rowsDropped[dataset],
        'cleared': cleared[dataset]!.toList(),
      },
  };

  /// The run [saved] describes, if it was started for exactly [scope] — the same owner's
  /// units, years, watermarks, page size and authority generation. Anything else answers
  /// null and the caller discards what was staged.
  static _PageRun? resume(
    Map<String, dynamic> saved,
    Map<String, dynamic> scope,
  ) {
    try {
      if (jsonEncode(saved['scope']) != jsonEncode(scope)) return null;
      final run = _PageRun(scope);
      final cursor = saved['cursor'] as Map;
      run.cursor = ReportingPageCursor(
        revenueSeq: (cursor['revenue_seq'] as num?)?.toInt(),
        revenueId: cursor['revenue_id'] as String?,
        expenseSeq: (cursor['expense_seq'] as num?)?.toInt(),
        expenseId: cursor['expense_id'] as String?,
      );
      final authorised = saved['authorised'];
      run.authorised = authorised is List
          ? {for (final unit in authorised) unit as String}
          : null;
      run.pages = (saved['pages'] as num).toInt();
      if (run.pages < 1 || run.authorised == null) return null;
      for (final dataset in ReportingDataset.values) {
        final state = saved[dataset.wireName] as Map;
        run.maxSeq[dataset] = (state['max_seq'] as num).toInt();
        run.documents[dataset] = (state['documents'] as num).toInt();
        run.rowsStored[dataset] = (state['rows_stored'] as num).toInt();
        run.rowsDropped[dataset] = (state['rows_dropped'] as num).toInt();
        run.cleared[dataset]!.addAll([
          for (final id in state['cleared'] as List) id as String,
        ]);
      }
      return run;
    } on Object {
      // A resume record that cannot be read is not a resume record.
      return null;
    }
  }
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
