/// The local reporting engine: canonical facts in, `PnlResult` out.
///
/// Phase 5 Slice 3, and the first of the two engines `ARCHITECTURE.md` §6.1 draws. Its
/// entire job is:
///
/// ```
///     normalise the period once   ->  ReportRange
///     ask the source per property ->  primitive summed paise + coverage
///     hand them to Pnl.compute    ->  PnlResult
///     hand those to Pnl.consolidate for the organisation
/// ```
///
/// **It computes nothing.** No Net Sales, no Operating Profit, no margin, no tax
/// extraction, no rate, no business-date derivation, no financial-year derivation. Every
/// one of those lives once, in `domain/finance`, and a structural guard asserts this file
/// has not quietly acquired any of them — because two engines that each derive the P&L
/// agree only until somebody edits one, which is exactly the divergence spec §21 exists to
/// prevent (D-020).
///
/// It holds **no state**. Every call carries its own scope and its own range, and there is
/// no cached "latest P&L" anywhere — a process-level cache of a financial figure is how a
/// user switch or a revocation ends up showing one person another's numbers (D-074).
///
/// ## What Slice 3 cannot yet do
///
/// This device holds only the transactions it recorded itself: there is no reporting pull
/// on either engine (D-173). So the production source reports its coverage as
/// [ReportingCoverage.notDownloaded] and **the engine refuses**, rather than presenting one
/// device's share of the trade as the hotel's P&L. Slice 4 supplies the canonical reporting
/// cache and the coverage marker that makes a complete answer possible; nothing here
/// pretends to have it early.
library;

import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';

/// A computed report, with room for the metadata Slice 6 will attach.
///
/// A thin envelope rather than fields on [PnlResult]: freshness and as-of are a statement
/// about *how the figures were obtained*, not about the money, and putting network state
/// inside a financial result is how it ends up being compared, summed or serialised as
/// though it were part of the figure.
final class ReportEnvelope {
  const ReportEnvelope({
    required this.outcome,
    required this.range,
    required this.scope,
    required this.coverage,
  });

  final PnlOutcome outcome;

  /// The normalised range the report covers, or **null** when the period could not be
  /// resolved at all. Deliberately nullable rather than filled with a placeholder: there
  /// is no range for a reversed custom range, and inventing one would put a date in the
  /// envelope that nobody asked for.
  final ReportRange? range;

  final ReportingScope scope;

  /// The weakest coverage across every property in [scope]. One property that cannot be
  /// stood behind makes the consolidated figure unreportable, because the reader would
  /// have no way to see which part was missing.
  final ReportingCoverage coverage;

  bool get isComputed => outcome is PnlComputed;

  /// The result, or null when the report was refused.
  PnlResult? get resultOrNull =>
      outcome is PnlComputed ? (outcome as PnlComputed).result : null;
}

/// Reads this device's canonical projections and produces a P&L.
final class LocalReportingEngine {
  const LocalReportingEngine(this._source);

  final LocalReportingSource _source;

  /// A P&L for one property.
  Future<ReportEnvelope> reportForUnit({
    required ReportingPeriod period,
    required String businessUnitId,
    required ReportingScope scope,
  }) async {
    final resolved = period.resolve();
    if (resolved is ReportRangeRejected) {
      return _rejectedRange(scope);
    }
    final range = (resolved as ReportRangeResolved).range;

    final facts = await _source.factsFor(
      businessUnitId: businessUnitId,
      range: range,
      scope: scope,
    );

    return ReportEnvelope(
      outcome: _outcomeFor(period: period, facts: facts),
      range: range,
      scope: scope,
      coverage: facts.coverage,
    );
  }

  /// A P&L across every property in [scope], consolidated.
  ///
  /// Each property is computed on its own and then added by [Pnl.consolidate], rather than
  /// summed here — there is one consolidation formula in this project and it is not in an
  /// engine.
  Future<ReportEnvelope> report(ReportRequest request) async {
    final resolved = request.period.resolve();
    if (resolved is ReportRangeRejected) {
      return _rejectedRange(request.scope);
    }
    final range = (resolved as ReportRangeResolved).range;

    if (request.scope.isEmpty) {
      return ReportEnvelope(
        outcome: const PnlRefused(PnlRefusal.noPermittedBusinessUnit),
        range: range,
        scope: request.scope,
        coverage: ReportingCoverage.notDownloaded,
      );
    }

    // Ordered so a consolidated total is reproducible run to run. Sums of integers do not
    // care, but a breakdown list that shuffled would make two identical reports look
    // different to anybody diffing them.
    final units = request.scope.businessUnitIds.toList()..sort();

    final facts = <UnitReportingFacts>[];
    for (final unit in units) {
      facts.add(
        await _source.factsFor(
          businessUnitId: unit,
          range: range,
          scope: request.scope,
        ),
      );
    }

    final coverage =
        facts.any((f) => f.coverage == ReportingCoverage.notDownloaded)
        ? ReportingCoverage.notDownloaded
        : ReportingCoverage.complete;

    // Refuse the whole report if any property's side cannot be stood behind. A
    // consolidated figure assembled from a complete property and an unproven one is not a
    // narrower report; it is a wrong one (D-163).
    final perUnit = <PnlResult>[];
    for (final unitFacts in facts) {
      final outcome = _outcomeFor(period: request.period, facts: unitFacts);
      if (outcome is PnlRefused) {
        return ReportEnvelope(
          outcome: outcome,
          range: range,
          scope: request.scope,
          coverage: coverage,
        );
      }
      perUnit.add((outcome as PnlComputed).result);
    }

    return ReportEnvelope(
      outcome: PnlComputed(
        perUnit.length == 1 ? perUnit.single : Pnl.consolidate(perUnit),
      ),
      range: range,
      scope: request.scope,
      coverage: coverage,
    );
  }

  /// Turns one property's facts into an outcome.
  ///
  /// The only decision here is coverage → side. The arithmetic is entirely [Pnl.compute]'s,
  /// including the refusal rules, so there is no second place where a half-P&L could be
  /// assembled.
  PnlOutcome _outcomeFor({
    required ReportingPeriod period,
    required UnitReportingFacts facts,
  }) {
    final complete = facts.coverage == ReportingCoverage.complete;
    return Pnl.compute(
      period: period,
      revenue: complete
          ? SideAvailable(facts.revenue)
          : const SideUnavailable(ReportingSideUnavailable.notDownloaded),
      expenses: complete
          ? SideAvailable(facts.expenses)
          : const SideUnavailable(ReportingSideUnavailable.notDownloaded),
      businessUnitId: facts.businessUnitId,
      revenueByCategory: [
        for (final line in facts.revenueByCategory)
          RevenueCategoryLine(
            businessUnitId: line.businessUnitId,
            revenueCategoryId: line.revenueCategoryId,
            totals: line.totals,
          ),
      ],
      expenseByHierarchy: [
        for (final line in facts.expensesByCategory)
          ExpenseHierarchyLine(
            businessUnitId: line.businessUnitId,
            departmentId: line.departmentId,
            sectionId: line.sectionId,
            categoryId: line.categoryId,
            totals: line.totals,
          ),
      ],
    );
  }

  /// The period did not describe a range, so nothing is queried and nothing is invented.
  ReportEnvelope _rejectedRange(ReportingScope scope) => ReportEnvelope(
    outcome: const PnlRefused(PnlRefusal.invalidDateRange),
    range: null,
    scope: scope,
    coverage: ReportingCoverage.notDownloaded,
  );
}
