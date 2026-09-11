/// The two synchronisations a settlement preview needs, started together and reported
/// separately.
///
/// Phase 5 OA-3. The project lead's ruling makes OA-3 own initiating both:
///
///  1. the canonical owner history and masters (OA-2's full-replace pull), and
///  2. the canonical P&L reporting cache (Slice 4's delta),
///
/// and forbids certifying a settlement complete unless both are complete for what the
/// month needs. This does the initiating; **certifying is not its job** — the preview reads
/// the coverage each run left behind and refuses on whatever is missing, so a failed pull
/// can never become a valid zero by passing through here.
///
/// ## Why it lives here and not in `ReferenceSync`
///
/// `ReferenceSync` runs for every signed-in person on every authority refresh. The owner
/// pull is for the one surface that holds `owner_settlement.view`, and OA-2 recorded that
/// running it for everybody would certify owner history to readers entitled to none of it.
/// The server now withholds the datasets from those readers (OA-3), and the trigger still
/// stays with the surface: there is no reason to fetch the owners' private position for a
/// person who is not looking at it.
///
/// ## Order, and what each result means
///
/// The owner pull goes first because it carries the start date, and the start date decides
/// which financial years of P&L the settlement needs. A not-authorised owner answer stops
/// there: there is nothing to allocate for a reader who may not see the allocation.
///
/// **Two runs, two snapshots.** The P&L and the owner history are distinct authoritative
/// snapshots, and nothing here pretends otherwise: each result keeps its own evidence, and
/// no combined "as of" is manufactured (D-188).
library;

import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// What one refresh did, per dataset. Either may be null when it was not attempted.
final class OwnerSettlementRefreshReport {
  const OwnerSettlementRefreshReport({required this.owner, this.reporting});

  final OwnerSettlementSyncResult owner;

  /// Null when the P&L pull was not attempted — the owner pull said this reader may not
  /// see a settlement, or it did not arrive and there is no date to size the pull by.
  final List<ReportingSyncReport>? reporting;

  bool get ownerSucceeded => owner is OwnerSettlementSynchronised;

  bool get reportingSucceeded =>
      reporting != null && reporting!.every((r) => r.isComplete);

  /// Both arrived. A surface uses this to say "refreshed", never to decide a figure — the
  /// preview decides from the coverage on disk.
  bool get succeeded => ownerSucceeded && reportingSucceeded;
}

final class OwnerSettlementRefresher {
  const OwnerSettlementRefresher({
    required this.ownerSync,
    required this.reportingSync,
    required this.repository,
  });

  final OwnerSettlementSync ownerSync;
  final ReportingSync reportingSync;
  final OwnerSettlementRepository repository;

  /// Refreshes what a preview of the month ending [periodEnd] needs.
  ///
  /// [today] is the business date retention is measured from, so a year normal retention
  /// would prune is fetched **on demand** rather than silently dropped again (D-170).
  Future<OwnerSettlementRefreshReport> refresh({
    required Set<String> businessUnitIds,
    required BusinessDate periodEnd,
    required BusinessDate today,
  }) async {
    final owner = await ownerSync.synchronise();
    if (owner is OwnerSettlementSyncNotAuthorised) {
      return OwnerSettlementRefreshReport(owner: owner);
    }

    // The date that sizes the P&L pull comes from coverage **on disk**: this run's if it
    // arrived, the last committed one if it did not. With none, only the month's own year
    // is fetched; the preview will refuse for want of a start date either way.
    final start = (await repository.coverage())?.ownershipStartDate;
    final from = start != null && start <= periodEnd
        ? start
        : BusinessDate.of(periodEnd.year, periodEnd.month, 1);
    final range =
        (CustomRangePeriod(from: from, to: periodEnd).resolve()
                as ReportRangeResolved)
            .range;

    final retained = {
      for (final year in ReportingRetention.retainedAt(today)) year.openingYear,
    };
    final needed = financialYearsCovering(range);
    final normal = [
      for (final y in needed)
        if (retained.contains(y.openingYear)) y,
    ];
    final older = <FinancialYear>[
      for (final y in needed)
        if (!retained.contains(y.openingYear)) y,
    ];

    final reports = <ReportingSyncReport>[
      if (normal.isNotEmpty)
        await reportingSync.synchronise(
          businessUnitIds: businessUnitIds,
          years: normal,
        ),
      if (older.isNotEmpty)
        await reportingSync.synchronise(
          businessUnitIds: businessUnitIds,
          years: older,
          onDemand: true,
        ),
    ];

    return OwnerSettlementRefreshReport(owner: owner, reporting: reports);
  }
}
