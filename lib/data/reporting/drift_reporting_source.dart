/// The local canonical facts, read out of this device's two contribution projections.
///
/// Phase 5 Slice 3. This is the only file in the reporting path that knows what a database
/// is, and it performs **no arithmetic** — it delegates to the two repositories, which
/// already aggregate in SQL over the one shared canonical predicate each of them owns.
///
/// ## Why it delegates rather than writing its own SQL
///
/// Slice 1 established one canonical reporting semantic and put it in one predicate builder
/// per engine: accepted, not voided, not scope-revoked (D-168). A second query written here
/// would be a second place for that rule to live, and the whole reason Slice 1 existed is
/// that the two engines had already drifted apart once. So the source assembles a
/// `RevenueContributionQuery` and an `ExpenseContributionQuery` and lets the repositories
/// answer — which also means the range predicate, the scope predicate and the aggregate are
/// all still decided in SQL (spec §27).
///
/// ## Coverage is told the truth
///
/// A device holds only the transactions it recorded itself: there is no reporting pull on
/// either engine (D-173). So [DriftReportingSource] does not decide coverage — it asks a
/// [ReportingCoverageOracle], and the one production wires today is
/// [NoCanonicalCoverage], which answers [ReportingCoverage.notDownloaded] for every range.
///
/// That is not a placeholder to be tidied away later; it is the honest answer to *"can this
/// device stand behind a hotel-wide figure for June?"* until Slice 4 builds the canonical
/// reporting cache and the marker that can say otherwise. Tests supply their own oracle to
/// exercise the engine against known-complete fixtures, which is the same shape D-108 used
/// for revenue configuration completeness.
library;

import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';

/// Decides whether this device can stand behind a figure for a scope and range.
///
/// Its own type because it is the one thing Slice 4 replaces. Everything else in this file
/// keeps working when the marker arrives.
abstract interface class ReportingCoverageOracle {
  ReportingCoverage coverageFor({
    required String businessUnitId,
    required ReportRange range,
  });
}

/// What production answers today: nothing is proven, because nothing has been pulled.
///
/// Deliberately not "complete when there happen to be rows". Rows are what this device
/// recorded; a hotel's P&L is what everybody recorded, and the difference is invisible in
/// the figure (D-173).
final class NoCanonicalCoverage implements ReportingCoverageOracle {
  const NoCanonicalCoverage();

  @override
  ReportingCoverage coverageFor({
    required String businessUnitId,
    required ReportRange range,
  }) => ReportingCoverage.notDownloaded;
}

/// Reads `revenue_period_contributions` and `expense_period_contributions`.
final class DriftReportingSource implements LocalReportingSource {
  const DriftReportingSource({
    required this.revenue,
    required this.expenses,
    this.coverage = const NoCanonicalCoverage(),
  });

  final RevenueRepository revenue;
  final ExpenseRepository expenses;
  final ReportingCoverageOracle coverage;

  @override
  Future<UnitReportingFacts> factsFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingScope scope,
  }) async {
    // One mapping from a range to query constraints, applied identically on both sides.
    // The caller does not choose it and cannot: whether a month is answered by the indexed
    // `pnl_period_key` or by a date range is a property of the range itself (§7).
    final periodKey = range.wholeMonthKey;
    final from = periodKey == null ? range.from : null;
    final to = periodKey == null ? range.to : null;

    final revenueQuery = RevenueContributionQuery(
      periodKey: periodKey,
      from: from,
      to: to,
      businessUnitId: businessUnitId,
      businessUnitIds: scope.businessUnitIds,
    );
    final expenseQuery = ExpenseContributionQuery(
      periodKey: periodKey,
      from: from,
      to: to,
      businessUnitId: businessUnitId,
      businessUnitIds: scope.businessUnitIds,
    );

    return UnitReportingFacts(
      businessUnitId: businessUnitId,
      coverage: coverage.coverageFor(
        businessUnitId: businessUnitId,
        range: range,
      ),
      revenue: await revenue.contributionTotals(revenueQuery),
      expenses: await expenses.contributionTotals(expenseQuery),
      revenueByCategory: await revenue.contributionTotalsByCategory(
        revenueQuery,
      ),
      expensesByCategory: await expenses.contributionTotalsByCategory(
        expenseQuery,
      ),
    );
  }
}
