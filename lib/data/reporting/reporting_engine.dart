/// The reporting engine: canonical facts in, `PnlResult` out.
///
/// Phase 5 Slice 3 built this for the local cache; Slice 5 lifts it so the remote engine is
/// the same orchestration over a different source. Its entire job is:
///
/// ```
///     normalise the period once   ->  ReportRange
///     ask the source per property ->  primitive summed paise + per-side coverage
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
/// ## Why the two engines share this and it is not a fiction
///
/// Spec §21.2 says an engine's whole contract is *"select and sum the right rows"* and that
/// it *"performs no business arithmetic"*. Taken seriously, that leaves an engine with
/// nothing to differ about except its source — so the honest implementation is one
/// orchestration over two adapters, and the D-020 parity suite is then genuinely a test of
/// the two **sources**: does the synchronised cache mean the same thing as the authoritative
/// server?
///
/// Writing the orchestration twice so the parity suite had two copies to compare would be
/// testing a duplication this design exists to avoid, and it would compare them on the one
/// axis that cannot go wrong while leaving the axis that can — the rows — untested.
/// [LocalReportingEngine] and [RemoteReportingEngine] are named subclasses so a call site
/// still says which facts it is standing on.
///
/// It holds **no state**. Every call carries its own scope and its own range, and there is
/// no cached "latest P&L" anywhere — a process-level cache of a financial figure is how a
/// user switch or a revocation ends up showing one person another's numbers (D-074).
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
    required this.revenueCoverage,
    required this.expenseCoverage,
    this.freshness,
  });

  final PnlOutcome outcome;

  /// The normalised range the report covers, or **null** when the period could not be
  /// resolved at all. Deliberately nullable rather than filled with a placeholder: there
  /// is no range for a reversed custom range, and inventing one would put a date in the
  /// envelope that nobody asked for.
  final ReportRange? range;

  final ReportingScope scope;

  /// The weakest revenue coverage across every property in [scope], and the same for
  /// expenses. **Reported separately** (D-183): a report whose expenses are complete and
  /// whose revenue has never been synchronised says so, rather than saying that neither
  /// side is available.
  final ReportingCoverage revenueCoverage;
  final ReportingCoverage expenseCoverage;

  /// How current the figures are, or **null** when that cannot be said.
  ///
  /// Availability and freshness are separate questions and are answered separately.
  /// [revenueCoverage] and [expenseCoverage] say whether there is a figure at all; this
  /// says how current the figure there is happens to be, and it is present only when
  /// every required segment of the report provably belongs to one authoritative snapshot
  /// (D-188).
  ///
  /// Null is not a third freshness state and must never be rendered as one. It means the
  /// stronger claim is unavailable — segments from more than one synchronisation run,
  /// evidence predating the corrective, or a source that holds no server evidence at all.
  /// The figures are canonical regardless.
  final ReportingFreshness? freshness;

  /// The same report, now known to be behind the server.
  ///
  /// Separated from [report] on purpose: an engine performs no network call, so a
  /// currentness confirmation is somebody else's round trip and its result is folded in
  /// here. **The figures do not move** — they stay the canonical facts of the snapshot
  /// they came from until a synchronisation replaces them.
  ReportEnvelope asServerHasNewer() {
    final current = freshness;
    if (current == null) return this;
    return ReportEnvelope(
      outcome: outcome,
      range: range,
      scope: scope,
      revenueCoverage: revenueCoverage,
      expenseCoverage: expenseCoverage,
      freshness: current.asServerHasNewer(),
    );
  }

  /// One badge's worth, for a caller that shows a single indicator. Lossy on purpose, and
  /// never consulted to decide a refusal — the refusal is already in [outcome], per side.
  ReportingCoverage get coverage =>
      revenueCoverage == ReportingCoverage.complete
      ? expenseCoverage
      : revenueCoverage;

  bool get isComputed => outcome is PnlComputed;

  /// The result, or null when the report was refused.
  PnlResult? get resultOrNull =>
      outcome is PnlComputed ? (outcome as PnlComputed).result : null;

  /// The refusal, or null when the report computed.
  PnlRefusal? get refusalOrNull =>
      outcome is PnlRefused ? (outcome as PnlRefused).refusal : null;

  @override
  String toString() =>
      'ReportEnvelope($scope $range revenue: ${revenueCoverage.name}, '
      'expenses: ${expenseCoverage.name}, outcome: '
      '${resultOrNull ?? refusalOrNull})';
}

/// Reads canonical reporting facts from one source and produces a P&L.
base class ReportingEngine {
  const ReportingEngine(this.source);

  final ReportingFactsSource source;

  /// A P&L for one property.
  Future<ReportEnvelope> reportForUnit({
    required ReportingPeriod period,
    required String businessUnitId,
    required ReportingScope scope,
  }) async {
    final resolved = period.resolve();
    if (resolved is ReportRangeRejected) return _rejectedRange(scope);
    final range = (resolved as ReportRangeResolved).range;

    // A property outside the requested scope is refused before anything is read; the
    // sources refuse it again at the read, and the server a third time. Scope is
    // authority, not a filter.
    if (!scope.businessUnitIds.contains(businessUnitId)) {
      final facts = await source.factsFor(
        businessUnitId: businessUnitId,
        range: range,
        scope: scope,
      );
      return ReportEnvelope(
        outcome: _outcomeFor(period: period, facts: facts),
        range: range,
        scope: scope,
        revenueCoverage: facts.revenueCoverage,
        expenseCoverage: facts.expenseCoverage,
      );
    }

    // **One read**, so the figures and the evidence that dates them come from the same
    // answer. Asking a second time would describe a different moment on the remote source
    // and would be the substitution the coherence corrective exists to prevent (D-188).
    final scopeFacts = await source.factsForScope(
      range: range,
      scope: ReportingScope.unit(businessUnitId),
    );
    final facts = scopeFacts.units.single;
    final outcome = _outcomeFor(period: period, facts: facts);

    return ReportEnvelope(
      outcome: outcome,
      range: range,
      scope: scope,
      revenueCoverage: facts.revenueCoverage,
      expenseCoverage: facts.expenseCoverage,
      freshness: _freshnessFrom(
        outcome: outcome,
        evidence: scopeFacts.snapshot,
      ),
    );
  }

  /// A P&L across every property in [scope], consolidated.
  ///
  /// Each property is computed on its own and then added by [Pnl.consolidate], rather than
  /// summed here — there is one consolidation formula in this project and it is not in an
  /// engine.
  Future<ReportEnvelope> report(ReportRequest request) async {
    final resolved = request.period.resolve();
    if (resolved is ReportRangeRejected) return _rejectedRange(request.scope);
    final range = (resolved as ReportRangeResolved).range;

    if (request.scope.isEmpty) {
      return ReportEnvelope(
        outcome: const PnlRefused(PnlRefusal.noPermittedBusinessUnit),
        range: range,
        scope: request.scope,
        revenueCoverage: ReportingCoverage.notDownloaded,
        expenseCoverage: ReportingCoverage.notDownloaded,
      );
    }

    // One call for the whole scope, so a source that can read every property at one
    // snapshot does — and so a consolidated total is never assembled from figures taken at
    // two different moments (§4). Ordered, because a breakdown list that shuffled would
    // make two identical reports look different to anybody diffing them.
    final scopeFacts = await source.factsForScope(
      range: range,
      scope: request.scope,
    );
    final facts = scopeFacts.units;

    final revenueCoverage = _weakest(facts.map((f) => f.revenueCoverage));
    final expenseCoverage = _weakest(facts.map((f) => f.expenseCoverage));

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
          revenueCoverage: revenueCoverage,
          expenseCoverage: expenseCoverage,
        );
      }
      perUnit.add((outcome as PnlComputed).result);
    }

    final outcome = PnlComputed(
      perUnit.length == 1 ? perUnit.single : Pnl.consolidate(perUnit),
    );

    return ReportEnvelope(
      outcome: outcome,
      range: range,
      scope: request.scope,
      revenueCoverage: revenueCoverage,
      expenseCoverage: expenseCoverage,
      freshness: _freshnessFrom(
        outcome: outcome,
        evidence: scopeFacts.snapshot,
      ),
    );
  }

  /// Freshness for a report, or null when the stronger claim is unavailable.
  ///
  /// Two conditions gate it, and both are deliberate:
  ///
  ///   * a **refused** report has no freshness. There is no figure, so there is nothing
  ///     for a currentness claim to be about — availability already said so, per side;
  ///   * evidence must exist. A consolidated set assembled from two synchronisation runs,
  ///     or markers written before snapshot evidence existed, cannot name one moment, and
  ///     naming the earlier of the two would date a state the cache cannot reproduce.
  ///
  /// Nothing here consults a clock, a network or an age. A report stays readable and
  /// truthfully labelled however long ago it was synchronised: there is no reporting TTL,
  /// and D-112's revenue-configuration window governs creating new offline revenue rather
  /// than reading an existing P&L (D-170).
  ReportingFreshness? _freshnessFrom({
    required PnlOutcome outcome,
    required ReportingSnapshotEvidence? evidence,
  }) {
    if (outcome is! PnlComputed || evidence == null) return null;
    return ReportingFreshness.synchronised(evidence);
  }

  /// Turns one property's facts into an outcome.
  ///
  /// The only decision here is coverage → side, **per side**. The arithmetic is entirely
  /// [Pnl.compute]'s, including the refusal rules, so there is no second place where a
  /// half-P&L could be assembled.
  PnlOutcome _outcomeFor({
    required ReportingPeriod period,
    required UnitReportingFacts facts,
  }) {
    final revenueReason = facts.revenueCoverage.sideReason;
    final expenseReason = facts.expenseCoverage.sideReason;
    return Pnl.compute(
      period: period,
      revenue: revenueReason == null
          ? SideAvailable(facts.revenue)
          : SideUnavailable(revenueReason),
      expenses: expenseReason == null
          ? SideAvailable(facts.expenses)
          : SideUnavailable(expenseReason),
      businessUnitId: facts.businessUnitId,
      revenueByCategory: [
        for (final line in facts.revenueByCategory)
          RevenueCategoryLine(
            businessUnitId: line.businessUnitId,
            revenueCategoryId: line.revenueCategoryId,
            totals: line.totals,
            treatment: line.treatment,
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

  /// Anything short of complete makes the consolidated side unreportable; the first
  /// non-complete value is kept so the reason survives rather than becoming a boolean.
  static ReportingCoverage _weakest(Iterable<ReportingCoverage> values) {
    for (final value in values) {
      if (value != ReportingCoverage.complete) return value;
    }
    return ReportingCoverage.complete;
  }

  /// The period did not describe a range, so nothing is queried and nothing is invented.
  ReportEnvelope _rejectedRange(ReportingScope scope) => ReportEnvelope(
    outcome: const PnlRefused(PnlRefusal.invalidDateRange),
    range: null,
    scope: scope,
    revenueCoverage: ReportingCoverage.notDownloaded,
    expenseCoverage: ReportingCoverage.notDownloaded,
  );
}
