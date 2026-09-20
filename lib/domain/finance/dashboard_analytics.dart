/// Dashboard analytics rules over canonical P&L results (Phase 6, D-255, D-258).
///
/// Three things live here, all of them arithmetic or selection a chart must never do:
///
/// * **Trend buckets** — the ranges a trend is made of. Each bucket is reported by the
///   ordinary reporting engine, so a trend point is exactly the P&L of its range.
/// * **Best and worst day** — ranking daily Net Sales, and nothing else.
/// * **Top N + Others** — presentation grouping over a category set that must reconcile
///   exactly before anything is grouped, with Others as the exact sum of the rest.
///
/// ## Trend grain (D-255)
///
/// A single day's Expenses and Operating Profit are distorted by accrual placement — a
/// month's salary lands on its last day — so **daily and weekly points carry Net Sales
/// only**. Expenses and Operating Profit are trended by month, and a financial year to date
/// is trended by month. The permission is a property of the grain, checked when buckets are
/// built, so a chart cannot ask for a daily profit series by accident.
///
/// ## Custom ranges (D-263)
///
/// A custom range can be three days or three years, so its Net Sales grain comes from its
/// own inclusive P&L-date span:
///
/// ```
///     1 … 31 days     daily     Net Sales
///     32 … 180 days   weekly    Net Sales
///     181+ days       monthly   Net Sales
/// ```
///
/// Expenses and Operating Profit stay **monthly only**, and are offered only where a
/// monthly trend is a trend at all — a range lying inside one calendar month produces one
/// point, and one point does not show a direction, so nothing is shown rather than a
/// single bar labelled as a trend.
///
/// Weeks are Monday–Sunday and months are calendar months. The first and last bucket of a
/// custom range are routinely clipped; they are marked [TrendBucket.partial] and are
/// **never extrapolated** to a notional whole week or month.
///
/// **Choosing a grain changes nothing about the period.** Buckets are derived from a range
/// that is already fixed; neither the selected custom period nor its comparison period is
/// touched by which grain a chart happens to plot.
///
/// ## A bucket with no figure is a gap
///
/// A bucket whose P&L could not be established is a [TrendGap] carrying the refusal. It is
/// never zero, never interpolated from its neighbours and never estimated — a flat segment
/// drawn across missing data is indistinguishable from a real trading lull, and the reader
/// has no way to tell.
library;

import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_drilldown.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

// ── Trends ──────────────────────────────────────────────────────────────────

/// What a trend plots.
enum TrendMeasure { netSales, expenses, operatingProfit }

/// How wide a trend point is.
enum TrendGrain {
  daily,
  weekly,
  monthly;

  /// Whether a point of this width may carry [measure] (D-255).
  bool permits(TrendMeasure measure) =>
      this == TrendGrain.monthly || measure == TrendMeasure.netSales;
}

/// One point's range, and whether it is shorter than a whole week or month.
final class TrendBucket {
  const TrendBucket({required this.range, required this.partial});

  final ReportRange range;

  /// A clipped week or month — the first or last point of a range that does not start or
  /// end on its boundary, including the week or month still in progress. A surface labels
  /// it so an unfinished point never looks like a finished one.
  final bool partial;

  @override
  String toString() => 'TrendBucket($range${partial ? ', partial' : ''})';
}

abstract final class DashboardTrends {
  /// The span at which a custom Net Sales trend stops being daily (D-263), inclusive.
  static const customDailyMaximumDays = 31;

  /// The span at which it stops being weekly (D-263), inclusive.
  static const customWeeklyMaximumDays = 180;

  /// The grain a custom range's **Net Sales** trend uses, from its inclusive day span.
  static TrendGrain netSalesGrainForCustom(ReportRange range) =>
      range.days <= customDailyMaximumDays
      ? TrendGrain.daily
      : range.days <= customWeeklyMaximumDays
      ? TrendGrain.weekly
      : TrendGrain.monthly;

  /// Whether a monthly Expenses or Operating Profit trend is worth drawing over [range].
  ///
  /// It needs at least two monthly buckets. One point is not a trend — it shows no
  /// direction and no movement — and drawing it as one would be the chart making a claim
  /// its data cannot support. Partial first and last buckets count: they are real figures
  /// for real, shorter periods, labelled as such, and the alternative would be inventing a
  /// completeness rule nobody has set.
  static bool offersMonthlyCostTrend(ReportRange range) =>
      buckets(
        range,
        TrendGrain.monthly,
        measure: TrendMeasure.expenses,
      ).length >
      1;

  /// The trend grains [kind] offers for [measure].
  ///
  /// [range] is required for [DashboardPeriodKind.custom], whose grain is a property of
  /// its span, and is ignored for every relative kind.
  static List<TrendGrain> grainsFor(
    DashboardPeriodKind kind, {
    required TrendMeasure measure,
    ReportRange? range,
  }) {
    if (kind == DashboardPeriodKind.custom) {
      if (range == null) {
        throw ArgumentError.value(
          range,
          'range',
          'a custom range chooses its grain by its own span (D-263)',
        );
      }
      return switch (measure) {
        TrendMeasure.netSales => [netSalesGrainForCustom(range)],
        TrendMeasure.expenses || TrendMeasure.operatingProfit =>
          offersMonthlyCostTrend(range) ? const [TrendGrain.monthly] : const [],
      };
    }
    final offered = switch (kind) {
      DashboardPeriodKind.today => const <TrendGrain>[],
      DashboardPeriodKind.weekToDate => const [TrendGrain.daily],
      DashboardPeriodKind.monthToDate => const [
        TrendGrain.daily,
        TrendGrain.weekly,
      ],
      DashboardPeriodKind.financialYearToDate => const [TrendGrain.monthly],
      DashboardPeriodKind.custom => const <TrendGrain>[],
    };
    // Expenses and Operating Profit are monthly only, so a week-to-date or month-to-date
    // period offers them no grain at all rather than a daily one (D-255).
    return [
      for (final grain in offered)
        if (grain.permits(measure)) grain,
    ];
  }

  /// The buckets tiling [range] at [grain], for a trend of [measure].
  ///
  /// Throws if [grain] does not permit [measure] — a daily profit trend is not a thing this
  /// product draws.
  static List<TrendBucket> buckets(
    ReportRange range,
    TrendGrain grain, {
    required TrendMeasure measure,
  }) {
    if (!grain.permits(measure)) {
      throw ArgumentError.value(
        measure,
        'measure',
        'is not trended at ${grain.name} grain (D-255)',
      );
    }
    final result = <TrendBucket>[];
    var from = range.from;
    while (from <= range.to) {
      final (naturalStart, naturalEnd) = switch (grain) {
        TrendGrain.daily => (from, from),
        TrendGrain.weekly => (
          from.addDays(1 - weekdayOf(from)),
          from.addDays(7 - weekdayOf(from)),
        ),
        TrendGrain.monthly => (
          BusinessDate.of(from.year, from.month, 1),
          BusinessDate.of(from.year, from.month + 1, 1).addDays(-1),
        ),
      };
      final to = naturalEnd > range.to ? range.to : naturalEnd;
      result.add(
        TrendBucket(
          range: _range(from, to),
          partial: from != naturalStart || to != naturalEnd,
        ),
      );
      from = to.addDays(1);
    }
    return List.unmodifiable(result);
  }

  /// A plotted series: one point per bucket, each either a figure or a gap.
  ///
  /// [outcomes] is parallel to [buckets] and each computed result must be the P&L of
  /// exactly the bucket it is filed under, for one scope. Filing a P&L under the wrong
  /// bucket would plot a real figure in the wrong place, so it throws rather than being
  /// tolerated.
  static TrendSeries series({
    required TrendMeasure measure,
    required TrendGrain grain,
    required List<TrendBucket> buckets,
    required List<PnlOutcome> outcomes,
  }) {
    if (!grain.permits(measure)) {
      throw ArgumentError.value(
        measure,
        'measure',
        'is not trended at ${grain.name} grain (D-255)',
      );
    }
    if (buckets.length != outcomes.length) {
      throw ArgumentError(
        'a trend needs one outcome per bucket: ${buckets.length} buckets, '
        '${outcomes.length} outcomes',
      );
    }
    final points = <TrendPoint>[];
    String? scope;
    var seenResult = false;
    for (var i = 0; i < buckets.length; i++) {
      final bucket = buckets[i];
      switch (outcomes[i]) {
        case PnlRefused(:final refusal):
          // Never zero, never interpolated, never estimated (D-263).
          points.add(TrendGap(bucket: bucket, refusal: refusal));
        case PnlComputed(:final result):
          if (result.range != bucket.range) {
            throw ArgumentError.value(
              result.range,
              'outcomes[$i]',
              'is not the P&L of bucket ${bucket.range}',
            );
          }
          if (seenResult && result.businessUnitId != scope) {
            throw ArgumentError('trend points from different scopes');
          }
          scope = result.businessUnitId;
          seenResult = true;
          points.add(
            TrendValue(
              bucket: bucket,
              amount: switch (measure) {
                TrendMeasure.netSales => result.netSales,
                TrendMeasure.expenses => result.expenses,
                TrendMeasure.operatingProfit => result.operatingProfit,
              },
            ),
          );
      }
    }
    return TrendSeries._(
      measure: measure,
      grain: grain,
      points: List.unmodifiable(points),
    );
  }
}

/// One plotted point: a figure for its bucket, or the statement that there is none.
sealed class TrendPoint {
  const TrendPoint({required this.bucket});
  final TrendBucket bucket;
}

/// A real figure for a real bucket. A clipped bucket is still real — see
/// [TrendBucket.partial] — and its figure is what that shorter period actually was.
final class TrendValue extends TrendPoint {
  const TrendValue({required super.bucket, required this.amount});
  final Money amount;

  @override
  String toString() => 'TrendValue(${bucket.range}: $amount)';
}

/// No figure for this bucket, and none invented for it.
final class TrendGap extends TrendPoint {
  const TrendGap({required super.bucket, required this.refusal});
  final PnlRefusal refusal;

  @override
  String toString() => 'TrendGap(${bucket.range}: ${refusal.name})';
}

/// A trend, ready to plot.
final class TrendSeries {
  const TrendSeries._({
    required this.measure,
    required this.grain,
    required this.points,
  });

  final TrendMeasure measure;
  final TrendGrain grain;

  /// In range order, one per bucket, gaps included in place.
  final List<TrendPoint> points;

  bool get hasGap => points.any((p) => p is TrendGap);

  /// The buckets that could not be established, in order.
  List<TrendBucket> get gaps => [
    for (final p in points)
      if (p is TrendGap) p.bucket,
  ];

  @override
  String toString() =>
      'TrendSeries(${measure.name} by ${grain.name}, ${points.length} points'
      '${hasGap ? ', ${gaps.length} gaps' : ''})';
}

// ── Best and worst day ──────────────────────────────────────────────────────

enum DailyRankingRefusal {
  /// No days were given.
  noDays,

  /// At least one day's P&L is unavailable, so no day can be called best or worst.
  dayUnavailable,
}

sealed class DailyRanking {
  const DailyRanking();
}

final class DailyRankingUnavailable extends DailyRanking {
  const DailyRankingUnavailable(this.reason, {this.unavailableDays = const []});
  final DailyRankingRefusal reason;
  final List<BusinessDate> unavailableDays;
}

final class DailyRanked extends DailyRanking {
  const DailyRanked({
    required this.best,
    required this.bestDays,
    required this.worst,
    required this.worstDays,
  });

  final Money best;
  final Money worst;

  /// Every day that reached the figure, in date order. A tie is reported, never broken.
  final List<BusinessDate> bestDays;
  final List<BusinessDate> worstDays;

  /// Every day had the same Net Sales, so there is no best or worst to single out.
  bool get allEqual => best == worst;
}

abstract final class DailyNetSalesRanking {
  /// Ranks the days in [days] by **Net Sales** — the only figure a day may be ranked on.
  ///
  /// Each value must be the P&L of exactly the single day it is filed under, and all of
  /// them must be for one scope; otherwise this throws.
  static DailyRanking rank(Map<BusinessDate, PnlOutcome> days) {
    if (days.isEmpty) {
      return const DailyRankingUnavailable(DailyRankingRefusal.noDays);
    }
    final dates = days.keys.toList()..sort();
    final unavailable = <BusinessDate>[];
    final net = <BusinessDate, Money>{};
    String? scope;
    var first = true;
    for (final date in dates) {
      switch (days[date]!) {
        case PnlRefused():
          unavailable.add(date);
        case PnlComputed(:final result):
          if (result.range.from != date || result.range.to != date) {
            throw ArgumentError.value(
              result.range,
              'days[$date]',
              'is not the single day it is filed under',
            );
          }
          if (!first && result.businessUnitId != scope) {
            throw ArgumentError('days from different scopes');
          }
          scope = result.businessUnitId;
          first = false;
          net[date] = result.netSales;
      }
    }
    if (unavailable.isNotEmpty) {
      return DailyRankingUnavailable(
        DailyRankingRefusal.dayUnavailable,
        unavailableDays: List.unmodifiable(unavailable),
      );
    }
    var best = net.values.first;
    var worst = best;
    for (final amount in net.values) {
      if (amount > best) best = amount;
      if (amount < worst) worst = amount;
    }
    return DailyRanked(
      best: best,
      worst: worst,
      bestDays: List.unmodifiable([
        for (final d in dates)
          if (net[d] == best) d,
      ]),
      worstDays: List.unmodifiable([
        for (final d in dates)
          if (net[d] == worst) d,
      ]),
    );
  }
}

// ── Top N + Others ──────────────────────────────────────────────────────────

enum TopNRefusal {
  /// The complete set does not add up exactly to its headline figure. Nothing is drawn.
  doesNotReconcile,
}

/// One ranked line, its amount under the ranking measure, and a stable identity.
final class RankedLine<L> {
  const RankedLine({
    required this.key,
    required this.amount,
    required this.line,
  });

  /// The line's full identity. Used to order equal amounts, so the result never
  /// changes between two readings of the same data.
  final String key;
  final Money amount;
  final L line;
}

sealed class TopNOutcome<L> {
  const TopNOutcome();
}

final class TopNRefused<L> extends TopNOutcome<L> {
  const TopNRefused(this.reason);
  final TopNRefusal reason;
}

final class TopNGrouped<L> extends TopNOutcome<L> {
  const TopNGrouped({
    required this.top,
    required this.others,
    required this.othersCount,
    required this.total,
  });

  /// Largest first; equal amounts in key order.
  final List<RankedLine<L>> top;

  /// The exact sum of every line not in [top], or null when there are none.
  final Money? others;
  final int othersCount;

  /// The headline figure the complete set reconciled to.
  final Money total;
}

abstract final class TopN {
  /// The largest expense categories — each Department + Section + Category bucket, per
  /// property — against headline Expenses. Categories of different properties stay
  /// separate lines: nothing here decides that two categories are "the same".
  static TopNOutcome<ExpenseHierarchyLine> expenseCategories(
    PnlResult result, {
    required int n,
  }) => group(
    [
      for (final l in result.expenseByHierarchy)
        RankedLine(key: _expenseKey(l), amount: l.totals.amount, line: l),
    ],
    total: result.expenses,
    n: n,
  );

  /// The largest departments, each grouped exactly from its categories, per property.
  static TopNOutcome<ExpenseHierarchyLine> departments(
    PnlResult result, {
    required int n,
  }) => group(
    [
      for (final l in PnlDrilldown.departments(result.expenseByHierarchy))
        RankedLine(key: _expenseKey(l), amount: l.totals.amount, line: l),
    ],
    total: result.expenses,
    n: n,
  );

  /// The largest revenue categories by **Net Sales**, against headline Net Sales.
  static TopNOutcome<RevenueCategoryLine> revenueCategories(
    PnlResult result, {
    required int n,
  }) => group(
    [
      for (final l in result.revenueByCategory)
        RankedLine(
          key: '${l.businessUnitId}/${l.revenueCategoryId}',
          amount: l.totals.net,
          line: l,
        ),
    ],
    total: result.netSales,
    n: n,
  );

  /// Groups [lines] into the top [n] and Others, after checking they sum to [total].
  static TopNOutcome<L> group<L>(
    List<RankedLine<L>> lines, {
    required Money total,
    required int n,
  }) {
    if (n < 1) {
      throw ArgumentError.value(n, 'n', 'must be at least one');
    }
    if (lines.map((l) => l.key).toSet().length != lines.length) {
      throw ArgumentError('the same line appears twice');
    }
    if (Money.sum(lines.map((l) => l.amount)) != total) {
      return TopNRefused<L>(TopNRefusal.doesNotReconcile);
    }
    final ordered = [...lines]
      ..sort((a, b) {
        final byAmount = b.amount.paise.compareTo(a.amount.paise);
        return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
      });
    final top = ordered.take(n).toList();
    final rest = ordered.skip(n).toList();
    return TopNGrouped<L>(
      top: List.unmodifiable(top),
      others: rest.isEmpty ? null : Money.sum(rest.map((l) => l.amount)),
      othersCount: rest.length,
      total: total,
    );
  }

  static String _expenseKey(ExpenseHierarchyLine l) =>
      '${l.businessUnitId}/${l.departmentId ?? ''}/${l.sectionId ?? ''}/'
      '${l.categoryId ?? ''}';
}

ReportRange _range(BusinessDate from, BusinessDate to) =>
    switch (CustomRangePeriod(from: from, to: to).resolve()) {
      ReportRangeResolved(:final range) => range,
      ReportRangeRejected() => throw StateError('bucket $from .. $to'),
    };
