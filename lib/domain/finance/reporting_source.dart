/// What a reporting engine needs from wherever the canonical facts live.
///
/// Phase 5 Slice 3. This is a **port**: pure domain, no Drift, no network. The local
/// adapter reads this device's projections; the remote adapter will read the server's.
/// Both hand the same three things to the same calculator, which is what makes the parity
/// suite §21.3 requires possible at all.
///
/// ## Coverage is a first-class answer, not an inference
///
/// The one thing a reporting source must not do is let a caller mistake *"I have no rows"*
/// for *"there was no trade"*. Today a device holds only the transactions it recorded
/// itself — there is no reporting pull on either engine (D-173) — so an empty result is
/// almost always the first thing and almost never the second.
///
/// So a source states its coverage separately from its figures, and the engine refuses
/// rather than reporting a number it cannot stand behind. That is D-163 and D-176 applied
/// one layer down: **zero is not unavailable**, and the difference has to be carried, not
/// reconstructed.
library;

import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';

/// Whether a source can stand behind a figure for one scope and range.
///
/// **Two values, and deliberately not three.** An earlier draft had `unavailable` beside
/// `notDownloaded`, and nothing in the system could produce it: every path that fails to
/// establish coverage today fails for the same reason, which is that nothing has ever
/// synchronised canonical reporting data to this device. A value no code constructs is the
/// gap D-108 had to reopen — the distinction lived in the type and never in the behaviour.
///
/// Slice 4 adds whatever finer distinctions its markers can actually support, and Slice 6
/// owns freshness. Neither is guessed at here.
enum ReportingCoverage {
  /// A proven complete canonical dataset for this scope and range.
  complete,

  /// Not proven. The range may be partly present, wholly present or absent — the point is
  /// that nothing has established which, so no figure derived from it is reportable.
  notDownloaded,
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
    required this.coverage,
    required this.revenue,
    required this.expenses,
    this.revenueByCategory = const [],
    this.expensesByCategory = const [],
  });

  final String businessUnitId;
  final ReportingCoverage coverage;

  /// Primitive summed paise. Nothing derived: an engine sums, the domain computes.
  final RevenueTotals revenue;
  final ExpenseTotals expenses;

  /// Cheap groupings the repositories already return. Slice 10 owns real drill-down.
  final List<RevenueCategoryTotals> revenueByCategory;
  final List<ExpenseCategoryTotals> expensesByCategory;
}

/// Where canonical reporting facts come from.
///
/// Implementations perform **no business arithmetic**: they select and sum the right rows
/// and say whether they can stand behind the answer. Net Sales, Operating Profit and
/// margin are computed once, in `domain/finance`, from what comes back (spec §21.2,
/// D-020).
abstract interface class LocalReportingSource {
  /// The canonical facts for one property over one range.
  ///
  /// [range] is already normalised, so a source never interprets a week, a month or a
  /// financial year — it receives two inclusive P&L dates and nothing else (§6).
  Future<UnitReportingFacts> factsFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingScope scope,
  });
}
