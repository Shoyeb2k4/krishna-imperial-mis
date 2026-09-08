/// What a reporting engine needs from wherever the canonical facts live.
///
/// Phase 5 Slice 3, extended in Slice 5. This is a **port**: pure domain, no Drift, no
/// network. The cached local adapter reads this device's synchronised reporting cache; the
/// remote adapter reads the authoritative server. Both hand the same three things to the
/// same calculator, which is what makes the parity suite §21.3 requires possible at all.
///
/// ## Coverage is a first-class answer, not an inference
///
/// The one thing a reporting source must not do is let a caller mistake *"I have no rows"*
/// for *"there was no trade"*. A device holds only what has been synchronised to it, so an
/// empty result is very often the first thing and very rarely the second.
///
/// So a source states its coverage separately from its figures, and the engine refuses
/// rather than reporting a number it cannot stand behind. That is D-163 and D-176 applied
/// one layer down: **zero is not unavailable**, and the difference has to be carried, not
/// reconstructed.
///
/// ## And it is stated per side (D-183)
///
/// Revenue and expense coverage are established independently — different markers locally,
/// different capabilities remotely — so they are reported independently. Folding them into
/// one value per property loses exactly the fact a reader needs: *which* half is missing.
library;

import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/pnl.dart'
    show ReportingSideUnavailable;
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';

/// Whether a source can stand behind a figure for one **dataset**, scope and range.
///
/// ## Why there is a third value now
///
/// Slice 3 wrote this enum with two values and said so in as many words: an `unavailable`
/// beside `notDownloaded` had no producer, and a value no code constructs is the gap D-108
/// had to reopen — a distinction living in the type and never in the behaviour.
///
/// Slice 5 gives it one. The remote source reads an authoritative server that always holds
/// the canonical facts, so it can never answer `notDownloaded`; what it *can* answer is
/// that this caller holds no authority over a side (D-164's data half). Those are different
/// facts and they send a reader to different places — one to a synchronisation, the other
/// to whoever grants capabilities — so they are kept apart rather than collapsed.
enum ReportingCoverage {
  /// A proven complete canonical dataset for this scope, range and side.
  complete,

  /// Not proven. The range may be partly present, wholly present or absent — the point is
  /// that nothing has established which, so no figure derived from it is reportable.
  notDownloaded,

  /// The caller holds no authority to read this side for this property. Not merely absent
  /// from this device: not theirs to see.
  notAuthorised;

  /// How this coverage travels into the calculator's own vocabulary.
  ///
  /// `null` for [complete], because a covered side is not unavailable at all.
  ReportingSideUnavailable? get sideReason => switch (this) {
    complete => null,
    notDownloaded => ReportingSideUnavailable.notDownloaded,
    notAuthorised => ReportingSideUnavailable.notAuthorised,
  };
}

/// Which side of the P&L a coverage question is about.
///
/// Coverage is **per dataset**, and that is the whole of the Slice 5 correction. Slice 4
/// stored revenue and expense markers independently and then collapsed them into one value
/// per property — so a scope whose revenue had never synchronised and whose expenses were
/// complete refused as `bothSidesUnavailable`, naming neither the side that was missing nor
/// the one that was fine (D-183).
enum ReportingDatasetSide {
  revenue,
  expenses;

  /// The dataset's stored vocabulary, shared with the coverage markers.
  String get wireName => switch (this) {
    revenue => 'revenue',
    expenses => 'expense',
  };
}

/// Which authoritative snapshot a set of canonical facts jointly represents (D-188).
///
/// The identity is opaque and server-issued; the time is the server's own, taken from the
/// same statement that supplied the facts. Neither is derived on the device, because a
/// device clock is not evidence about a server's state and a client cannot mint an
/// authoritative moment.
///
/// This is deliberately **not** the delta cursor. The cursor says where the next pull
/// resumes and is a `change_seq`; a sequence value is allocated when a row is written and
/// becomes visible only when its transaction commits, so it orders work and does not date
/// a snapshot (ARCHITECTURE §5.2). Asking one to be the other is what let two independent
/// per-dataset queries look like one moment.
final class ReportingSnapshotEvidence {
  const ReportingSnapshotEvidence({
    required this.snapshotId,
    required this.serverConfirmedAt,
  });

  final String snapshotId;

  /// The server's own transaction time for this snapshot. Always UTC.
  final DateTime serverConfirmedAt;

  @override
  bool operator ==(Object other) =>
      other is ReportingSnapshotEvidence &&
      other.snapshotId == snapshotId &&
      other.serverConfirmedAt == serverConfirmedAt;

  @override
  int get hashCode => Object.hash(snapshotId, serverConfirmedAt);

  @override
  String toString() =>
      'ReportingSnapshotEvidence($snapshotId at '
      '${serverConfirmedAt.toIso8601String()})';
}

/// How current an **available** report is.
///
/// Spec §21.4 and `ARCHITECTURE.md` §6.4 named three states, and the first of them —
/// *"Local — current, includes N unsynced entries"* — was superseded for P&L by D-167:
/// canonical P&L contains only server-accepted facts, so an unsynced attempt contributes
/// nothing and there is no figure for it to be *included in*. The arm is not preserved,
/// because a state no valid report can construct is the gap D-108 had to reopen.
///
/// Unsynced work remains real and remains visible — on the transaction surfaces, as
/// operational sync status. It is not a P&L freshness state and must never imply that
/// those transactions moved a reported figure.
///
/// Availability is a different question and is answered by [ReportingCoverage]. *Not
/// downloaded* and *not authorised* say there is no figure; these two say how current the
/// figure there is happens to be.
enum ReportingFreshnessState {
  /// Synchronised as of the evidence's server-confirmed time.
  ///
  /// It means: *the cache represents the complete authoritative snapshot successfully
  /// synchronised at T*. It does **not** claim that nothing has changed since. An offline
  /// device may truthfully stay here — being unable to ask is not evidence of staleness,
  /// and a report is never gated on the network to be read (spec §21.4).
  synchronised,

  /// The server has confirmed that canonical reporting facts in this scope have moved
  /// past what the device holds.
  ///
  /// Only ever set from an authoritative answer about **reporting** data. A vendor
  /// rename, a tax-rule change or an audit row moves the global sequence and changes no
  /// contribution, and must never land a report here.
  serverHasNewer,
}

/// The freshness of an available report, and the evidence behind it.
final class ReportingFreshness {
  const ReportingFreshness({required this.state, required this.evidence});

  const ReportingFreshness.synchronised(ReportingSnapshotEvidence evidence)
    : this(state: ReportingFreshnessState.synchronised, evidence: evidence);

  final ReportingFreshnessState state;

  /// What the claim rests on. Always present: a freshness state without evidence would be
  /// an assertion about a server nobody asked.
  final ReportingSnapshotEvidence evidence;

  /// The same report, now known to be behind the server.
  ///
  /// The figures do not move — they are the canonical facts of [evidence]'s snapshot, and
  /// they stay exactly that until a synchronisation replaces them.
  ReportingFreshness asServerHasNewer() => ReportingFreshness(
    state: ReportingFreshnessState.serverHasNewer,
    evidence: evidence,
  );

  DateTime get synchronisedAt => evidence.serverConfirmedAt;

  @override
  String toString() => 'ReportingFreshness(${state.name}, $evidence)';
}

/// The business units a report covers.
///
/// Always explicit and always non-empty. There is deliberately no "null means everything"
/// convention: a null scope reading as the whole organisation is how an engine ends up
/// aggregating a property the reader was never granted (§16). Authority itself is Slice
/// 7's; this type only makes the set impossible to omit.
final class ReportingScope {
  ReportingScope(Iterable<String> businessUnitIds)
    : businessUnitIds = Set.unmodifiable(businessUnitIds);

  /// One property.
  ReportingScope.unit(String businessUnitId)
    : businessUnitIds = Set.unmodifiable({businessUnitId});

  final Set<String> businessUnitIds;

  bool get isEmpty => businessUnitIds.isEmpty;

  /// True when the report covers more than one property and is therefore consolidated.
  bool get isConsolidated => businessUnitIds.length > 1;

  /// Deterministic order, so two identical reports are identical to anybody diffing them.
  List<String> get ordered => businessUnitIds.toList()..sort();

  @override
  String toString() => 'ReportingScope(${businessUnitIds.join(', ')})';
}

/// What is being asked for.
final class ReportRequest {
  const ReportRequest({required this.period, required this.scope});

  final ReportingPeriod period;
  final ReportingScope scope;
}

/// One property's canonical facts for one range, as a source reports them.
///
/// The coverage travels **with** the figures rather than beside them, so a caller cannot
/// pick up the totals and leave the caveat behind.
final class UnitReportingFacts {
  const UnitReportingFacts({
    required this.businessUnitId,
    required this.revenueCoverage,
    required this.expenseCoverage,
    required this.revenue,
    required this.expenses,
    this.revenueByCategory = const [],
    this.expensesByCategory = const [],
  });

  /// Both sides unreadable for the same reason. The ordinary shape of a refusal.
  const UnitReportingFacts.uncovered({
    required this.businessUnitId,
    required ReportingCoverage coverage,
  }) : revenueCoverage = coverage,
       expenseCoverage = coverage,
       revenue = RevenueTotals.zero,
       expenses = ExpenseTotals.zero,
       revenueByCategory = const [],
       expensesByCategory = const [];

  final String businessUnitId;

  /// Established independently, and never folded together here. A caller that needs one
  /// value has [weakestCoverage] and can see what it gave up.
  final ReportingCoverage revenueCoverage;
  final ReportingCoverage expenseCoverage;

  /// Primitive summed paise. Nothing derived: a source sums, the domain computes.
  final RevenueTotals revenue;
  final ExpenseTotals expenses;

  /// Cheap groupings the repositories already return. Slice 10 owns real drill-down.
  final List<RevenueCategoryTotals> revenueByCategory;
  final List<ExpenseCategoryTotals> expensesByCategory;

  /// Coverage for one side by name, for a caller iterating the two.
  ReportingCoverage coverageOf(ReportingDatasetSide side) =>
      side == ReportingDatasetSide.revenue ? revenueCoverage : expenseCoverage;

  /// The weaker of the two, for an envelope that shows one badge.
  ///
  /// **Lossy on purpose, and never used to decide a refusal** — the refusal is decided per
  /// side, so a missing revenue side is reported as a missing revenue side. This is
  /// presentation shorthand and Slice 6 owns what is done with it.
  ReportingCoverage get weakestCoverage =>
      revenueCoverage == ReportingCoverage.complete
      ? expenseCoverage
      : revenueCoverage;

  bool get isFullyCovered =>
      revenueCoverage == ReportingCoverage.complete &&
      expenseCoverage == ReportingCoverage.complete;
}

/// Where canonical reporting facts come from.
///
/// **One port, two adapters.** The cached local adapter and the remote adapter implement
/// exactly this, so `ReportRequest`, `ReportingScope`, `ReportRange` and `PnlResult` are
/// one contract rather than two DTO families that agree by coincidence (§16). The whole
/// divergence surface between the two engines is therefore *"did you sum the right rows"*,
/// which is small enough for the D-020 parity suite to pin down completely.
///
/// Implementations perform **no business arithmetic**: they select and sum the right rows
/// and say whether they can stand behind each side. Net Sales, Operating Profit and margin
/// are computed once, in `domain/finance`, from what comes back (spec §21.2, D-020).
abstract interface class ReportingFactsSource {
  /// The canonical facts for one property over one range.
  ///
  /// [range] is already normalised, so a source never interprets a week, a month or a
  /// financial year — it receives two inclusive P&L dates and nothing else (§6).
  Future<UnitReportingFacts> factsFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingScope scope,
  });

  /// Every property in [scope], in [ReportingScope.ordered] order.
  ///
  /// A consolidated report reads its properties through **one** call so a source that can
  /// answer them together does. That matters for the remote adapter: a consolidated total
  /// assembled from one request per property would read each at its own snapshot, and a
  /// correction committing between two of them would produce a consolidated figure that
  /// never existed. The local adapter reads a single SQLite database and implements this as
  /// the obvious loop.
  Future<ReportingScopeFacts> factsForScope({
    required ReportRange range,
    required ReportingScope scope,
  });
}

/// One scope's facts and the snapshot evidence behind them, from one read.
///
/// The two travel together deliberately. The remote adapter learns both from the same
/// statement, and asking it a second time would describe a different moment — which is
/// the very substitution the coherence corrective exists to prevent (D-188).
final class ReportingScopeFacts {
  const ReportingScopeFacts({required this.units, this.snapshot});

  final List<UnitReportingFacts> units;

  /// The authoritative snapshot every required segment jointly represents, or **null**
  /// when they cannot be shown to represent one — a set assembled from more than one
  /// synchronisation run, a segment certified before snapshot evidence existed, or a
  /// device's own ledger, which is nobody's snapshot. The figures are canonical either
  /// way; what is unavailable is the stronger claim about *when* they were current.
  final ReportingSnapshotEvidence? snapshot;
}

/// The loop, for a source whose store answers one property as cheaply as several.
///
/// Written once so the two local adapters cannot drift, and deliberately not the default on
/// the interface: a source that *can* read a whole scope at one snapshot should be made to
/// say so rather than inherit a per-property fallback by silence.
base mixin PerUnitReportingFacts implements ReportingFactsSource {
  @override
  Future<ReportingScopeFacts> factsForScope({
    required ReportRange range,
    required ReportingScope scope,
  }) async => ReportingScopeFacts(
    units: [
      for (final unit in scope.ordered)
        await factsFor(businessUnitId: unit, range: range, scope: scope),
    ],
    snapshot: await snapshotEvidenceFor(range: range, scope: scope),
  );

  /// What snapshot, if any, this source's facts belong to.
  ///
  /// Defaults to **null**, which is the truthful answer for a store that holds no
  /// server-issued evidence — a device's own transaction projections are not a snapshot
  /// of the hotel and must never be described as one. An adapter that does hold evidence
  /// overrides this.
  Future<ReportingSnapshotEvidence?> snapshotEvidenceFor({
    required ReportRange range,
    required ReportingScope scope,
  }) async => null;
}
