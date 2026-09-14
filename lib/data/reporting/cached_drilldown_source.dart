/// Document rows beneath a P&L, from the canonical reporting cache (Phase 5 Slice 10).
///
/// The drill-down's read of the cache, gated exactly as the headline read is gated
/// ([CachedReportingSource]): the D2 intersection for a property, all three unscoped for a
/// consolidated report, and coverage certified by a marker rather than inferred from rows.
/// `expense.view.own` never qualifies, and no role name is consulted (D-164, D-187).
///
/// A property outside the report's scope is refused, never read — a click on a row cannot
/// widen a report to a property the reader did not open.
///
/// It performs no arithmetic and derives no date: the sums come from the cache in SQL, and
/// the range arrives normalised.
library;

import 'package:krishna_mis/data/reporting/drift_reporting_source.dart'
    show ReportingCoverageOracle;
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/domain/finance/pnl_drilldown.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';

final class CachedDrilldownSource {
  const CachedDrilldownSource({
    required this.cache,
    required this.principal,
    required this.coverage,
  });

  final ReportingCache cache;

  /// Supplies both the cache owner and the authority, so the two cannot drift apart.
  final Principal principal;

  final ReportingCoverageOracle coverage;

  /// Revenue documents in one property's revenue category over [range].
  Future<DrilldownRows<RevenueDocumentLine>> revenueDocuments({
    required ReportingScope scope,
    required ReportRange range,
    required String businessUnitId,
    required String revenueCategoryId,
  }) async {
    final gate = _gate(
      scope: scope,
      range: range,
      businessUnitId: businessUnitId,
      side: ReportingDatasetSide.revenue,
    );
    if (gate != ReportingCoverage.complete) {
      return DrilldownRowsUnavailable(gate);
    }
    return DrilldownRowsAvailable(
      await cache.revenueDocuments(
        ownerUserId: principal.userId,
        businessUnitId: businessUnitId,
        revenueCategoryId: revenueCategoryId,
        range: range,
      ),
    );
  }

  /// Expense documents in one exact Department + Section + Category bucket over [range].
  Future<DrilldownRows<ExpenseDocumentLine>> expenseDocuments({
    required ReportingScope scope,
    required ReportRange range,
    required String businessUnitId,
    required String departmentId,
    required String sectionId,
    required String categoryId,
  }) async {
    final gate = _gate(
      scope: scope,
      range: range,
      businessUnitId: businessUnitId,
      side: ReportingDatasetSide.expenses,
    );
    if (gate != ReportingCoverage.complete) {
      return DrilldownRowsUnavailable(gate);
    }
    return DrilldownRowsAvailable(
      await cache.expenseDocuments(
        ownerUserId: principal.userId,
        businessUnitId: businessUnitId,
        departmentId: departmentId,
        sectionId: sectionId,
        categoryId: categoryId,
        range: range,
      ),
    );
  }

  /// Authority first, then coverage. Nothing is read unless both say yes.
  ReportingCoverage _gate({
    required ReportingScope scope,
    required ReportRange range,
    required String businessUnitId,
    required ReportingDatasetSide side,
  }) {
    if (scope.isEmpty || !scope.businessUnitIds.contains(businessUnitId)) {
      return ReportingCoverage.notAuthorised;
    }
    final authorised = scope.isConsolidated
        ? PnlAuthority.mayReadConsolidated(principal)
        : PnlAuthority.mayReadUnit(principal, businessUnitId);
    if (!authorised) return ReportingCoverage.notAuthorised;
    return coverage.coverageFor(
      businessUnitId: businessUnitId,
      range: range,
      side: side,
    );
  }
}
