/// The canonical reporting source: the P&L a device can stand behind.
///
/// Phase 5 Slice 4. This is what a reporting screen reads, and it is a different thing
/// from [DriftReportingSource] beside it, which reads the transactions *this device*
/// recorded (D-171).
///
/// ## Why the device's own ledger is not a reporting source
///
/// Both engines lack a reporting pull (D-173), so the local projections hold only what
/// this installation entered. A manager's second device, a fresh installation, or a
/// property whose sales somebody else records all produce the same thing: a query that
/// returns rows, sums them exactly, and reports a figure that is not the hotel's. The
/// figure is not detectably wrong — it is a correct sum of the wrong set.
///
/// So the canonical source reads the synchronised cache, and its coverage comes from a
/// **marker** rather than from the presence of rows. `notDownloaded` is the answer until
/// something has actually asked the server and been told, in full, what a scope's year
/// contains.
///
/// ## Coverage is a conjunction, and every term is load-bearing
///
/// A range is covered only when **both datasets** are certified for **every financial
/// year the range touches**, for **this owner** and **this property**. Weaken any one of
/// them and the engine reports a half-figure:
///
///   * one dataset — revenue without expenses is not a profit, it is a number that looks
///     like one (D-163);
///   * one year — a range crossing 1 April needs both sides, and the far side is exactly
///     the one retention may have pruned (§15);
///   * one owner — a colleague's synchronisation is not this person's authority (D-074).
library;

import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/reporting/drift_reporting_source.dart'
    show ReportingCoverageOracle;
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';

/// Coverage decided by what the synchroniser certified, never by what happens to be here.
final class MarkerCoverage implements ReportingCoverageOracle {
  const MarkerCoverage(this._markers);

  /// Every marker this owner holds, loaded once per report so one page does not issue a
  /// query per property per year.
  final List<ReportingCoverageMarker> _markers;

  /// Reads the markers for [ownerUserId] and returns an oracle over them.
  static Future<MarkerCoverage> load(
    ReportingCache cache,
    String ownerUserId,
  ) async => MarkerCoverage(await cache.markersFor(ownerUserId));

  @override
  ReportingCoverage coverageFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingDatasetSide side,
  }) {
    // One side, and every financial year the range touches. The markers were always
    // stored per dataset; until D-183 they were read as a conjunction over both, which
    // turned "revenue has not synchronised" into "neither side is available".
    final dataset = side == ReportingDatasetSide.revenue
        ? ReportingDataset.revenue
        : ReportingDataset.expense;
    for (final year in financialYearsCovering(range)) {
      final certified = _markers.any(
        (m) =>
            m.businessUnitId == businessUnitId &&
            m.dataset == dataset &&
            m.financialYear == year.openingYear,
      );
      if (!certified) return ReportingCoverage.notDownloaded;
    }
    return ReportingCoverage.complete;
  }

  /// The one authoritative snapshot every required segment shares, or null.
  ///
  /// Required segments are every property in [businessUnitIds], **both** datasets, and
  /// every financial year [range] touches. They must all carry snapshot evidence and it
  /// must be the same evidence — which is exactly the property Slice 4 could not express
  /// and the corrective installs (D-188).
  ///
  /// Null is returned rather than a best guess in three cases, and each is a real one:
  ///
  ///   * a segment has no marker at all — there is nothing to be current;
  ///   * a segment was certified before snapshot evidence existed, so it genuinely cannot
  ///     be shown to belong to any snapshot;
  ///   * segments were certified by **different** runs. Their figures are all canonical,
  ///     but they are canonical at different moments, and a consolidated total assembled
  ///     from two moments is not a report of either. The stronger freshness claim is
  ///     withheld; the figures are not.
  ReportingSnapshotEvidence? snapshotEvidence({
    required Set<String> businessUnitIds,
    required ReportRange range,
  }) {
    final years = financialYearsCovering(range);
    ReportingSnapshotEvidence? shared;

    for (final unit in businessUnitIds) {
      for (final dataset in ReportingDataset.values) {
        for (final year in years) {
          ReportingCoverageMarker? marker;
          for (final candidate in _markers) {
            if (candidate.businessUnitId == unit &&
                candidate.dataset == dataset &&
                candidate.financialYear == year.openingYear) {
              marker = candidate;
              break;
            }
          }
          if (marker == null || !marker.hasSnapshotEvidence) return null;

          final evidence = ReportingSnapshotEvidence(
            snapshotId: marker.snapshotId!,
            serverConfirmedAt: marker.serverConfirmedAt!.toUtc(),
          );
          if (shared == null) {
            shared = evidence;
          } else if (shared != evidence) {
            // Two runs. Deliberately **not** resolved by taking the earlier of them: the
            // cache stores latest canonical state and holds no history, so an older
            // timestamp would name a moment it cannot reproduce. `min(generation)` fails
            // for the same reason and is prohibited for it.
            return null;
          }
        }
      }
    }
    return shared;
  }
}

/// Reads the canonical reporting cache. Performs no business arithmetic (spec §21.2).
final class CachedReportingSource
    with PerUnitReportingFacts
    implements ReportingFactsSource {
  const CachedReportingSource({
    required this.cache,
    required this.principal,
    required this.coverage,
  });

  final ReportingCache cache;

  /// The authority that owns this source. It supplies both the cache owner and the
  /// capability boundary, so those two identities cannot drift apart on a user switch.
  final Principal principal;

  /// Whose cache is being read. A constructor field rather than a call argument, because
  /// a source belongs to a signed-in session — the same shape `SyncEngine.actorUserId`
  /// takes, and for the same reason: there is no signature by which a caller can read
  /// somebody else's figures by forgetting to say whose they are (D-050, D-074).
  String get ownerUserId => principal.userId;

  final ReportingCoverageOracle coverage;

  @override
  Future<UnitReportingFacts> factsFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingScope scope,
  }) async {
    // A property outside the requested scope contributes nothing and is not queried. The
    // engine already refuses a scope it was not given; this is the second place, at the
    // read itself, so no caller can widen a report by asking for a unit directly.
    if (!scope.businessUnitIds.contains(businessUnitId)) {
      return UnitReportingFacts.uncovered(
        businessUnitId: businessUnitId,
        coverage: ReportingCoverage.notDownloaded,
      );
    }

    final authority = _authorityFor(
      businessUnitId: businessUnitId,
      scope: scope,
    );
    if (!authority.reports) {
      return UnitReportingFacts.uncovered(
        businessUnitId: businessUnitId,
        coverage: ReportingCoverage.notAuthorised,
      );
    }

    final revenueCoverage = authority.revenue
        ? coverage.coverageFor(
            businessUnitId: businessUnitId,
            range: range,
            side: ReportingDatasetSide.revenue,
          )
        : ReportingCoverage.notAuthorised;
    final expenseCoverage = authority.expenses
        ? coverage.coverageFor(
            businessUnitId: businessUnitId,
            range: range,
            side: ReportingDatasetSide.expenses,
          )
        : ReportingCoverage.notAuthorised;

    return UnitReportingFacts(
      businessUnitId: businessUnitId,
      revenueCoverage: revenueCoverage,
      expenseCoverage: expenseCoverage,
      revenue: authority.revenue
          ? await cache.revenueTotals(
              ownerUserId: ownerUserId,
              businessUnitId: businessUnitId,
              range: range,
            )
          : RevenueTotals.zero,
      expenses: authority.expenses
          ? await cache.expenseTotals(
              ownerUserId: ownerUserId,
              businessUnitId: businessUnitId,
              range: range,
            )
          : ExpenseTotals.zero,
      revenueByCategory: authority.revenue
          ? await cache.revenueByCategory(
              ownerUserId: ownerUserId,
              businessUnitId: businessUnitId,
              range: range,
            )
          : const [],
      expensesByCategory: authority.expenses
          ? await cache.expensesByCategory(
              ownerUserId: ownerUserId,
              businessUnitId: businessUnitId,
              range: range,
            )
          : const [],
    );
  }

  @override
  Future<ReportingSnapshotEvidence?> snapshotEvidenceFor({
    required ReportRange range,
    required ReportingScope scope,
  }) async {
    if (scope.isEmpty ||
        scope.ordered.any(
          (unit) =>
              !_authorityFor(businessUnitId: unit, scope: scope).fullyReadable,
        )) {
      return null;
    }
    final oracle = coverage;
    if (oracle is! MarkerCoverage) return null;
    return oracle.snapshotEvidence(
      businessUnitIds: scope.businessUnitIds,
      range: range,
    );
  }

  ({bool reports, bool revenue, bool expenses, bool fullyReadable})
  _authorityFor({
    required String businessUnitId,
    required ReportingScope scope,
  }) {
    if (scope.isConsolidated) {
      final allowed =
          _hasUnscoped(Capability.reportsView) &&
          _hasUnscoped(Capability.revenueView) &&
          _hasUnscoped(Capability.expenseViewAll);
      return (
        reports: allowed,
        revenue: allowed,
        expenses: allowed,
        fullyReadable: allowed,
      );
    }

    final reports = principal.can(
      Capability.reportsView,
      businessUnitId: businessUnitId,
    );
    final revenue =
        reports &&
        principal.can(Capability.revenueView, businessUnitId: businessUnitId);
    final expenses =
        reports &&
        principal.can(
          Capability.expenseViewAll,
          businessUnitId: businessUnitId,
        );
    return (
      reports: reports,
      revenue: revenue,
      expenses: expenses,
      fullyReadable: reports && revenue && expenses,
    );
  }

  bool _hasUnscoped(Capability capability) =>
      principal.canAnywhere(capability) &&
      principal.scopedUnitsFor(capability) == null;
}
