/// The dashboard engine: several reports, one span, one claim (Phase 6 Slice 3).
///
/// A dashboard is a P&L for the period so far, the same P&L for the stretch it is compared
/// with, a trend made of one report per bucket, and — where asked for — a report per day of
/// the current period. This assembles those reads and hands the results to the rules that
/// already exist.
///
/// ```
///     plan       every distinct range the view needs
///     read       one report per distinct range, through the Phase 5 engine
///     assemble   PnlComparison · DashboardTrends · DailyNetSalesRanking · TopN
/// ```
///
/// **It derives nothing**, exactly as the reporting engine beneath it derives nothing
/// (spec §21.2). It performs no comparison arithmetic, builds no bucket boundaries, ranks
/// nothing and groups nothing: every one of those lives once, in `domain/finance`, and the
/// structural guard over this directory asserts this file has not acquired any of them.
/// What it adds is the reading strategy, and one honest answer about what the whole view
/// jointly represents.
///
/// ## Every distinct range is read once
///
/// A month-to-date dashboard wants a daily Net Sales trend and a best/worst day, and both
/// are the same thirty-one single-day reports. The plan is therefore a **set** of ranges,
/// read once each, and every part of the view is assembled from that one map. Reading them
/// twice would double the cost of the busiest dashboard there is, for no second answer.
///
/// ## One lock span, therefore one moment
///
/// All of it runs inside a single [CanonicalCacheLock] span. A dashboard is a great many
/// more reads than a P&L screen, so it is a great deal more exposed to a synchronisation
/// landing in the middle of it — and a trend whose first half is one snapshot and whose
/// second half is another reconciles perfectly and is a picture of no moment that existed
/// (D-188, D-241).
///
/// ## And one freshness claim, or none
///
/// The view claims a snapshot only when **every** read carried snapshot evidence and all of
/// it was the same evidence. A part that could not be established has no evidence, so it
/// withholds the claim for the whole view rather than for itself: *synchronised as of T*
/// printed above a chart with a hole in it would be claiming a completeness the view does
/// not have. The figures are canonical either way; what is withheld is the stronger claim.
library;

import 'package:krishna_mis/data/reporting/reporting_engine.dart';
import 'package:krishna_mis/data/sync/canonical_cache_lock.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

// ── What is asked for ───────────────────────────────────────────────────────

/// One trend the view wants: a measure at a grain.
///
/// The pairing is checked by `domain/finance` when the buckets are built, so a daily
/// Operating Profit series cannot be requested by accident (D-255).
final class DashboardTrendRequest {
  const DashboardTrendRequest({required this.measure, required this.grain});

  final TrendMeasure measure;
  final TrendGrain grain;

  @override
  bool operator ==(Object other) =>
      other is DashboardTrendRequest &&
      other.measure == measure &&
      other.grain == grain;

  @override
  int get hashCode => Object.hash(measure, grain);

  @override
  String toString() => 'DashboardTrendRequest(${measure.name}/${grain.name})';
}

/// A whole dashboard, as one request.
final class DashboardRequest {
  const DashboardRequest({
    required this.pair,
    required this.scope,
    this.trends = const [],
    this.rankDailyNetSales = false,
    this.topN = 0,
    this.compareProperties = false,
  });

  /// The period and its comparator, already resolved by `domain/finance` from each
  /// property's own business date. **Nothing here derives a date** (D-225, D-252).
  final DashboardPeriodPair pair;

  final ReportingScope scope;

  /// Which series to plot. Which ones a period may offer is
  /// [DashboardTrends.grainsFor]'s answer, not this layer's.
  final List<DashboardTrendRequest> trends;

  /// Rank the days of the current period by Net Sales (D-255). Costs one read per day,
  /// shared with a daily trend over the same period when there is one.
  final bool rankDailyNetSales;

  /// How many lines a Top N grouping keeps; zero asks for none (D-258).
  final int topN;

  /// Split the headline into its properties (Slice 6).
  ///
  /// Costs **no read**: it is a grouping of the category lines the headline result
  /// already carries, and it refuses by itself when the report covers one property.
  final bool compareProperties;
}

// ── What comes back ─────────────────────────────────────────────────────────

/// What the view cost to produce.
///
/// Carried on the result rather than measured beside it, so the performance gate measures
/// the shipped path and a later regression is visible from production rather than only
/// from a harness.
final class DashboardReadStats {
  const DashboardReadStats({
    required this.rangesRead,
    required this.trendPoints,
  });

  /// Distinct ranges actually read. The number of reports the view cost.
  final int rangesRead;

  /// Points across every series, gaps included.
  final int trendPoints;

  @override
  String toString() =>
      'DashboardReadStats($rangesRead reads, $trendPoints points)';
}

/// One dashboard, assembled.
final class DashboardView {
  const DashboardView({
    required this.pair,
    required this.scope,
    required this.current,
    required this.previous,
    required this.comparison,
    required this.trends,
    required this.revenueCoverage,
    required this.expenseCoverage,
    required this.stats,
    this.ranking,
    this.topExpenseCategories,
    this.topRevenueCategories,
    this.departmentSpending,
    this.propertyComparison,
    this.freshness,
  });

  final DashboardPeriodPair pair;
  final ReportingScope scope;

  /// The headline report for the period so far, and the one it is compared with.
  final ReportEnvelope current;
  final ReportEnvelope previous;

  /// Every comparison figure, decided by `domain/finance` (D-253, D-256).
  final PnlComparison comparison;

  /// In request order. Empty when the headline was refused.
  final List<TrendSeries> trends;

  /// Best and worst day by Net Sales, when asked for (D-255).
  final DailyRanking? ranking;

  final TopNOutcome<ExpenseHierarchyLine>? topExpenseCategories;
  final TopNOutcome<RevenueCategoryLine>? topRevenueCategories;

  /// The largest departments, grouped exactly from the same category lines (D-258).
  final TopNOutcome<ExpenseHierarchyLine>? departmentSpending;

  /// Each property's own figures inside a consolidated headline, or the refusal that
  /// explains why there are none. Null when none was asked for.
  final PropertyComparisonOutcome? propertyComparison;

  /// The weakest coverage of each side across **every** read, so a view whose oldest trend
  /// bucket is not downloaded says so rather than reporting the headline's coverage.
  final ReportingCoverage revenueCoverage;
  final ReportingCoverage expenseCoverage;

  /// What the whole view jointly represents, or null when it cannot be shown to represent
  /// one moment. Null is not a third state and must never be rendered as one (D-188).
  final ReportingFreshness? freshness;

  final DashboardReadStats stats;

  bool get isComputed => current.isComputed;

  /// The headline result, or null when the period was refused.
  PnlResult? get resultOrNull => current.resultOrNull;

  /// Why the headline was refused, or null when it computed.
  PnlRefusal? get refusalOrNull => current.refusalOrNull;

  @override
  String toString() =>
      'DashboardView(${pair.kind.name} $scope, ${stats.rangesRead} reads, '
      '${trends.length} series)';
}

// ── The engine ──────────────────────────────────────────────────────────────

/// Reads a dashboard's several reports and assembles them.
final class DashboardEngine {
  const DashboardEngine({required this.reports, required this.lock});

  /// The Phase 5 engine, used exactly as a P&L screen uses it. There is one reporting
  /// path in this product and a dashboard does not get a second one.
  final ReportingEngine reports;

  final CanonicalCacheLock lock;

  Future<DashboardView> build(DashboardRequest request) async {
    final plan = _plan(request);

    final envelopes = <ReportRange, ReportEnvelope>{};
    await lock.run(() async {
      // The headline first. A refused period is refused for the whole view: every bucket
      // lies inside it and under the same authority, so reading thirty more ranges would
      // spend the cost to arrive at the same refusal thirty more times — and a trend
      // drawn under a refused headline is the half-report D-163 forbids.
      envelopes[plan.current] = await _read(plan.current, request.scope);
      if (envelopes[plan.current]!.isComputed) {
        for (final range in plan.ranges.skip(1)) {
          envelopes[range] = await _read(range, request.scope);
        }
      } else {
        envelopes[plan.comparison] = await _read(
          plan.comparison,
          request.scope,
        );
      }
    });

    final current = envelopes[plan.current]!;
    final previous = envelopes[plan.comparison]!;
    final headline = current.resultOrNull;

    final series = <TrendSeries>[];
    var points = 0;
    if (headline != null) {
      for (final plotted in plan.trends) {
        final built = DashboardTrends.series(
          measure: plotted.request.measure,
          grain: plotted.request.grain,
          buckets: plotted.buckets,
          outcomes: [
            for (final bucket in plotted.buckets)
              envelopes[bucket.range]!.outcome,
          ],
        );
        series.add(built);
        points += built.points.length;
      }
    }

    return DashboardView(
      pair: request.pair,
      scope: request.scope,
      current: current,
      previous: previous,
      comparison: PnlComparison.compare(
        pair: request.pair,
        current: current.outcome,
        previous: previous.outcome,
      ),
      trends: List.unmodifiable(series),
      ranking: headline == null || !request.rankDailyNetSales
          ? null
          : DailyNetSalesRanking.rank({
              for (final day in plan.rankedDays)
                day: envelopes[_dayRange(plan, day)]!.outcome,
            }),
      topExpenseCategories: headline == null || request.topN < 1
          ? null
          : TopN.expenseCategories(headline, n: request.topN),
      topRevenueCategories: headline == null || request.topN < 1
          ? null
          : TopN.revenueCategories(headline, n: request.topN),
      departmentSpending: headline == null || request.topN < 1
          ? null
          : TopN.departments(headline, n: request.topN),
      propertyComparison: headline == null || !request.compareProperties
          ? null
          : PropertyComparison.of(headline),
      revenueCoverage: _weakest(envelopes.values.map((e) => e.revenueCoverage)),
      expenseCoverage: _weakest(envelopes.values.map((e) => e.expenseCoverage)),
      freshness: _sharedFreshness(envelopes.values),
      stats: DashboardReadStats(
        rangesRead: envelopes.length,
        trendPoints: points,
      ),
    );
  }

  Future<ReportEnvelope> _read(
    ReportRange range,
    ReportingScope scope,
  ) => reports.report(
    ReportRequest(
      // Every read is the same shape: two inclusive P&L dates through the one
      // validated period. A whole calendar month resolves to the indexed path by
      // itself, because that is a property of the range rather than a caller's choice.
      period: CustomRangePeriod(from: range.from, to: range.to),
      scope: scope,
    ),
  );

  /// One freshness claim for the whole view, or none.
  ///
  /// Every read must carry evidence and all of it must agree. Deliberately **not** the
  /// headline's evidence alone: a trend bucket in an older financial year may have been
  /// certified by a different run, and a badge taken from the headline would date the
  /// chart beside it to a moment that chart does not belong to.
  ReportingFreshness? _sharedFreshness(Iterable<ReportEnvelope> envelopes) {
    ReportingFreshness? shared;
    for (final envelope in envelopes) {
      final freshness = envelope.freshness;
      if (freshness == null) return null;
      if (shared == null) {
        shared = freshness;
      } else if (shared.evidence != freshness.evidence ||
          shared.state != freshness.state) {
        return null;
      }
    }
    return shared;
  }

  static ReportingCoverage _weakest(Iterable<ReportingCoverage> values) {
    for (final value in values) {
      if (value != ReportingCoverage.complete) return value;
    }
    return ReportingCoverage.complete;
  }

  /// The distinct ranges a view needs, headline first.
  static _DashboardPlan _plan(DashboardRequest request) {
    final trends = [
      for (final requested in request.trends)
        (
          request: requested,
          buckets: DashboardTrends.buckets(
            request.pair.current,
            requested.grain,
            measure: requested.measure,
          ),
        ),
    ];

    final days = request.rankDailyNetSales
        ? DashboardTrends.buckets(
            request.pair.current,
            TrendGrain.daily,
            measure: TrendMeasure.netSales,
          )
        : const <TrendBucket>[];

    // A set, in insertion order: a daily trend and a daily ranking over the same period
    // are the same reads, and the busiest dashboard there is must not pay for them twice.
    final ranges = <ReportRange>{
      request.pair.current,
      request.pair.comparison,
      for (final plotted in trends)
        for (final bucket in plotted.buckets) bucket.range,
      for (final day in days) day.range,
    };

    return _DashboardPlan(
      current: request.pair.current,
      comparison: request.pair.comparison,
      ranges: ranges.toList(growable: false),
      trends: trends,
      rankedDays: [for (final day in days) day.range.from],
      dayRanges: {for (final day in days) day.range.from: day.range},
    );
  }

  static ReportRange _dayRange(_DashboardPlan plan, BusinessDate day) =>
      plan.dayRanges[day]!;
}

typedef _PlottedTrend = ({
  DashboardTrendRequest request,
  List<TrendBucket> buckets,
});

final class _DashboardPlan {
  const _DashboardPlan({
    required this.current,
    required this.comparison,
    required this.ranges,
    required this.trends,
    required this.rankedDays,
    required this.dayRanges,
  });

  final ReportRange current;
  final ReportRange comparison;

  /// Distinct, headline first.
  final List<ReportRange> ranges;
  final List<_PlottedTrend> trends;
  final List<BusinessDate> rankedDays;
  final Map<BusinessDate, ReportRange> dayRanges;
}
