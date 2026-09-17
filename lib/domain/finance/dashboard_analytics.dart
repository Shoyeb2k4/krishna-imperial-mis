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
  /// The trend grains a dashboard period offers.
  ///
  /// Custom has none yet: which grain a custom range of arbitrary length should use has
  /// not been decided, and choosing one here would be deciding it (D-255).
  static List<TrendGrain> grainsFor(DashboardPeriodKind kind) => switch (kind) {
    DashboardPeriodKind.today => const [],
    DashboardPeriodKind.weekToDate => const [TrendGrain.daily],
    DashboardPeriodKind.monthToDate => const [
      TrendGrain.daily,
      TrendGrain.weekly,
    ],
    DashboardPeriodKind.financialYearToDate => const [TrendGrain.monthly],
    DashboardPeriodKind.custom => const [],
  };

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
