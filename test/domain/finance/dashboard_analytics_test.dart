/// Dashboard analytics rules (Phase 6 Slice 2, D-255, D-258).
///
/// * trend grain: daily and weekly points carry **Net Sales only**; Expenses and Operating
///   Profit are monthly; a financial year to date is monthly (D-255);
/// * best and worst day rank **daily Net Sales** only, and refuse when any day is missing;
/// * Top N + Others is presentation grouping over a set that must first reconcile exactly,
///   and Others is the exact sum of everything not in the top (D-258).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

BusinessDate _d(int y, int m, int d) => BusinessDate.of(y, m, d);
Money _p(int paise) => Money.fromPaise(paise);

ReportRange _range(BusinessDate from, BusinessDate to) =>
    (CustomRangePeriod(from: from, to: to).resolve() as ReportRangeResolved)
        .range;

PnlOutcome _day(BusinessDate day, int net, {String? unit = 'unit-ccr'}) =>
    PnlComputed(
      PnlResult(
        range: _range(day, day),
        businessUnitId: unit,
        grossSales: _p(net),
        gst: Money.zero,
        netSales: _p(net),
        expenses: _p(999999), // deliberately large: ranking must never read it
      ),
    );

ExpenseHierarchyLine _cat(String dept, String cat, int amount) =>
    ExpenseHierarchyLine(
      businessUnitId: 'unit-ccr',
      departmentId: dept,
      sectionId: 'sec-$dept',
      categoryId: cat,
      totals: ExpenseTotals(amount: _p(amount), contributions: 1),
    );

RevenueCategoryLine _rev(String cat, int net) => RevenueCategoryLine(
  businessUnitId: 'unit-ccr',
  revenueCategoryId: cat,
  totals: RevenueTotals(
    gross: _p(net),
    tax: Money.zero,
    net: _p(net),
    contributions: 1,
  ),
);

PnlResult _result({
  required List<ExpenseHierarchyLine> expenses,
  required int expenseTotal,
  List<RevenueCategoryLine> revenue = const [],
  int netTotal = 0,
}) => PnlResult(
  range: _range(_d(2026, 9, 1), _d(2026, 9, 17)),
  businessUnitId: 'unit-ccr',
  grossSales: _p(netTotal),
  gst: Money.zero,
  netSales: _p(netTotal),
  expenses: _p(expenseTotal),
  expenseContributions: expenses.length,
  revenueContributions: revenue.length,
  expenseByHierarchy: expenses,
  revenueByCategory: revenue,
);

void main() {
  group('trend grain (D-255)', () {
    test('daily and weekly points permit Net Sales only', () {
      for (final grain in const [TrendGrain.daily, TrendGrain.weekly]) {
        expect(grain.permits(TrendMeasure.netSales), isTrue);
        expect(grain.permits(TrendMeasure.expenses), isFalse);
        expect(grain.permits(TrendMeasure.operatingProfit), isFalse);
      }
    });

    test('monthly points permit all three measures', () {
      for (final m in TrendMeasure.values) {
        expect(TrendGrain.monthly.permits(m), isTrue);
      }
    });

    test('the Net Sales grains each relative period offers', () {
      List<TrendGrain> net(DashboardPeriodKind k) =>
          DashboardTrends.grainsFor(k, measure: TrendMeasure.netSales);
      expect(net(DashboardPeriodKind.today), isEmpty);
      expect(net(DashboardPeriodKind.weekToDate), [TrendGrain.daily]);
      expect(net(DashboardPeriodKind.monthToDate), [
        TrendGrain.daily,
        TrendGrain.weekly,
      ]);
      expect(net(DashboardPeriodKind.financialYearToDate), [
        TrendGrain.monthly,
      ]);
    });

    test('Expenses and Operating Profit are monthly only, so shorter periods '
        'offer them nothing', () {
      for (final measure in const [
        TrendMeasure.expenses,
        TrendMeasure.operatingProfit,
      ]) {
        for (final kind in const [
          DashboardPeriodKind.today,
          DashboardPeriodKind.weekToDate,
          DashboardPeriodKind.monthToDate,
        ]) {
          expect(
            DashboardTrends.grainsFor(kind, measure: measure),
            isEmpty,
            reason: '$kind must offer no $measure trend',
          );
        }
        expect(
          DashboardTrends.grainsFor(
            DashboardPeriodKind.financialYearToDate,
            measure: measure,
          ),
          [TrendGrain.monthly],
        );
      }
    });

    test('a series refuses a measure its grain does not permit', () {
      expect(
        () => DashboardTrends.buckets(
          _range(_d(2026, 9, 1), _d(2026, 9, 17)),
          TrendGrain.daily,
          measure: TrendMeasure.operatingProfit,
        ),
        throwsArgumentError,
      );
    });
  });

  group('trend buckets', () {
    test('daily: one bucket per P&L date, none partial', () {
      final b = DashboardTrends.buckets(
        _range(_d(2026, 9, 1), _d(2026, 9, 17)),
        TrendGrain.daily,
        measure: TrendMeasure.netSales,
      );
      expect(b, hasLength(17));
      expect(b.first.range.from, _d(2026, 9, 1));
      expect(b.last.range.to, _d(2026, 9, 17));
      expect(b.every((x) => x.range.days == 1 && !x.partial), isTrue);
    });

    test('weekly: Monday-to-Sunday weeks, clipped and marked partial', () {
      // 1 Sept 2026 is a Tuesday; 17 Sept is a Thursday.
      final b = DashboardTrends.buckets(
        _range(_d(2026, 9, 1), _d(2026, 9, 17)),
        TrendGrain.weekly,
        measure: TrendMeasure.netSales,
      );
      expect(b.map((x) => (x.range.from, x.range.to, x.partial)), [
        (_d(2026, 9, 1), _d(2026, 9, 6), true),
        (_d(2026, 9, 7), _d(2026, 9, 13), false),
        (_d(2026, 9, 14), _d(2026, 9, 17), true),
      ]);
    });

    test('monthly over a FYTD: whole months, the current one partial', () {
      final b = DashboardTrends.buckets(
        _range(_d(2026, 4, 1), _d(2026, 9, 17)),
        TrendGrain.monthly,
        measure: TrendMeasure.operatingProfit,
      );
      expect(b, hasLength(6));
      expect(b.first.range.from, _d(2026, 4, 1));
      expect(b.first.range.to, _d(2026, 4, 30));
      expect(b.take(5).every((x) => !x.partial), isTrue);
      expect(b.last.range.from, _d(2026, 9, 1));
      expect(b.last.range.to, _d(2026, 9, 17));
      expect(b.last.partial, isTrue);
    });

    test('buckets tile the range exactly: no gap, no overlap', () {
      final range = _range(_d(2026, 2, 17), _d(2027, 3, 3));
      for (final grain in TrendGrain.values) {
        final b = DashboardTrends.buckets(
          range,
          grain,
          measure: TrendMeasure.netSales,
        );
        expect(b.first.range.from, range.from);
        expect(b.last.range.to, range.to);
        for (var i = 1; i < b.length; i++) {
          expect(b[i].range.from, b[i - 1].range.to.addDays(1));
        }
        expect(b.fold<int>(0, (s, x) => s + x.range.days), range.days);
      }
    });
  });

  group('a Custom range chooses its Net Sales grain by span (D-263)', () {
    // The boundaries of the ruling's table, each side of each threshold.
    for (final (days, grain) in const [
      (1, TrendGrain.daily),
      (2, TrendGrain.daily),
      (31, TrendGrain.daily),
      (32, TrendGrain.weekly),
      (100, TrendGrain.weekly),
      (180, TrendGrain.weekly),
      (181, TrendGrain.monthly),
      (365, TrendGrain.monthly),
      (1000, TrendGrain.monthly),
    ]) {
      test('$days days -> ${grain.name}', () {
        final from = _d(2026, 4, 1);
        final range = _range(from, from.addDays(days - 1));
        expect(range.days, days);
        expect(DashboardTrends.netSalesGrainForCustom(range), grain);
        expect(
          DashboardTrends.grainsFor(
            DashboardPeriodKind.custom,
            measure: TrendMeasure.netSales,
            range: range,
          ),
          [grain],
        );
      });
    }

    test('a custom grain needs the range it is a property of', () {
      expect(
        () => DashboardTrends.grainsFor(
          DashboardPeriodKind.custom,
          measure: TrendMeasure.netSales,
        ),
        throwsArgumentError,
      );
    });

    test(
      'Expenses and Operating Profit stay monthly, however long the span',
      () {
        for (final days in const [40, 200, 800]) {
          final from = _d(2026, 4, 1);
          final range = _range(from, from.addDays(days - 1));
          for (final measure in const [
            TrendMeasure.expenses,
            TrendMeasure.operatingProfit,
          ]) {
            expect(
              DashboardTrends.grainsFor(
                DashboardPeriodKind.custom,
                measure: measure,
                range: range,
              ),
              [TrendGrain.monthly],
              reason: '$days days, $measure',
            );
          }
        }
      },
    );

    test('a range inside one calendar month offers no cost trend at all', () {
      // One monthly bucket is one point, and one point shows no direction.
      final inside = _range(_d(2026, 4, 3), _d(2026, 4, 28));
      expect(DashboardTrends.offersMonthlyCostTrend(inside), isFalse);
      for (final measure in const [
        TrendMeasure.expenses,
        TrendMeasure.operatingProfit,
      ]) {
        expect(
          DashboardTrends.grainsFor(
            DashboardPeriodKind.custom,
            measure: measure,
            range: inside,
          ),
          isEmpty,
        );
      }
      // Net Sales is unaffected: 26 days is a daily trend.
      expect(
        DashboardTrends.grainsFor(
          DashboardPeriodKind.custom,
          measure: TrendMeasure.netSales,
          range: inside,
        ),
        [TrendGrain.daily],
      );
    });

    test(
      'a whole calendar month alone is still one bucket, so still nothing',
      () {
        expect(
          DashboardTrends.offersMonthlyCostTrend(
            _range(_d(2026, 4, 1), _d(2026, 4, 30)),
          ),
          isFalse,
        );
      },
    );

    test('two days either side of a month boundary is two buckets', () {
      // Both partial, and both real. Partial is not a reason to withhold a trend; it is
      // a reason to label the point (D-263).
      final crossing = _range(_d(2026, 4, 29), _d(2026, 5, 2));
      expect(DashboardTrends.offersMonthlyCostTrend(crossing), isTrue);
      final b = DashboardTrends.buckets(
        crossing,
        TrendGrain.monthly,
        measure: TrendMeasure.expenses,
      );
      expect(b, hasLength(2));
      expect(b.every((x) => x.partial), isTrue);
    });

    test('choosing a grain does not move the period or its comparison', () {
      final outcome =
          DashboardPeriods.forCustom(from: _d(2026, 4, 1), to: _d(2027, 1, 15))
              as DashboardPairResolved;
      final before = outcome.pair;
      for (final measure in TrendMeasure.values) {
        final grains = DashboardTrends.grainsFor(
          DashboardPeriodKind.custom,
          measure: measure,
          range: before.current,
        );
        for (final grain in grains) {
          DashboardTrends.buckets(before.current, grain, measure: measure);
        }
      }
      expect(before.current, outcome.pair.current);
      expect(before.comparison, outcome.pair.comparison);
      expect(before.comparisonCapped, outcome.pair.comparisonCapped);
    });

    test('weekly buckets over a custom span are Monday-to-Sunday, clipped at '
        'both ends and never extrapolated', () {
      // 3 Sept 2026 is a Thursday; +60 days is 1 Nov 2026, a Sunday.
      final range = _range(_d(2026, 9, 3), _d(2026, 11, 1));
      expect(range.days, 60);
      expect(DashboardTrends.netSalesGrainForCustom(range), TrendGrain.weekly);
      final b = DashboardTrends.buckets(
        range,
        TrendGrain.weekly,
        measure: TrendMeasure.netSales,
      );
      expect(b.first.range.from, _d(2026, 9, 3));
      expect(b.first.range.to, _d(2026, 9, 6));
      expect(b.first.partial, isTrue, reason: 'a Thursday start is clipped');
      expect(b.last.range.to, _d(2026, 11, 1));
      expect(b.last.partial, isFalse, reason: 'it ends on a Sunday');
      // Nothing is stretched to a notional seven days.
      expect(b.first.range.days, 4);
      expect(b.fold<int>(0, (s, x) => s + x.range.days), range.days);
    });
  });

  group('a bucket with no figure is a gap, never a zero (D-263)', () {
    ReportRange bucketRange(int month) =>
        _range(_d(2026, month, 1), _d(2026, month + 1, 1).addDays(-1));

    PnlOutcome computed(int month, {required int net, required int expenses}) =>
        PnlComputed(
          PnlResult(
            range: bucketRange(month),
            businessUnitId: 'unit-ccr',
            grossSales: _p(net),
            gst: Money.zero,
            netSales: _p(net),
            expenses: _p(expenses),
          ),
        );

    List<TrendBucket> threeMonths() => DashboardTrends.buckets(
      _range(_d(2026, 4, 1), _d(2026, 6, 30)),
      TrendGrain.monthly,
      measure: TrendMeasure.expenses,
    );

    test('a refused bucket is a TrendGap carrying its refusal', () {
      final series = DashboardTrends.series(
        measure: TrendMeasure.expenses,
        grain: TrendGrain.monthly,
        buckets: threeMonths(),
        outcomes: [
          computed(4, net: 1000, expenses: 400),
          const PnlRefused(PnlRefusal.revenueUnavailable),
          computed(6, net: 3000, expenses: 900),
        ],
      );
      expect(series.points, hasLength(3));
      expect(series.hasGap, isTrue);
      expect(series.gaps.single.range, bucketRange(5));
      final gap = series.points[1] as TrendGap;
      expect(gap.refusal, PnlRefusal.revenueUnavailable);
      // The neighbours are untouched: nothing was interpolated across the hole.
      expect((series.points[0] as TrendValue).amount, _p(400));
      expect((series.points[2] as TrendValue).amount, _p(900));
    });

    test('a gap is not a zero, and nothing in the series pretends it is', () {
      final series = DashboardTrends.series(
        measure: TrendMeasure.netSales,
        grain: TrendGrain.monthly,
        buckets: threeMonths(),
        outcomes: [
          computed(4, net: 1000, expenses: 0),
          const PnlRefused(PnlRefusal.bothSidesUnavailable),
          computed(6, net: 3000, expenses: 0),
        ],
      );
      expect(
        series.points.whereType<TrendValue>().map((p) => p.amount),
        [_p(1000), _p(3000)],
        reason: 'a gap contributes no figure of any kind, not even zero',
      );
    });

    test('a real zero is a value, and stays distinct from a gap', () {
      final series = DashboardTrends.series(
        measure: TrendMeasure.netSales,
        grain: TrendGrain.monthly,
        buckets: threeMonths(),
        outcomes: [
          computed(4, net: 0, expenses: 0),
          computed(5, net: 0, expenses: 0),
          computed(6, net: 0, expenses: 0),
        ],
      );
      expect(series.hasGap, isFalse);
      expect(
        series.points.every((p) => p is TrendValue && p.amount == Money.zero),
        isTrue,
      );
    });

    test('each measure is read from its own field', () {
      final buckets = threeMonths();
      final outcomes = [
        computed(4, net: 1000, expenses: 400),
        computed(5, net: 2000, expenses: 500),
        computed(6, net: 3000, expenses: 900),
      ];
      for (final (measure, expected) in <(TrendMeasure, List<int>)>[
        (TrendMeasure.netSales, [1000, 2000, 3000]),
        (TrendMeasure.expenses, [400, 500, 900]),
        (TrendMeasure.operatingProfit, [600, 1500, 2100]),
      ]) {
        final series = DashboardTrends.series(
          measure: measure,
          grain: TrendGrain.monthly,
          buckets: buckets,
          outcomes: outcomes,
        );
        expect(
          series.points.map((p) => (p as TrendValue).amount.paise),
          expected,
          reason: measure.name,
        );
      }
    });

    test('a P&L filed under the wrong bucket is a programming error', () {
      expect(
        () => DashboardTrends.series(
          measure: TrendMeasure.netSales,
          grain: TrendGrain.monthly,
          buckets: threeMonths(),
          outcomes: [
            computed(4, net: 1, expenses: 0),
            computed(4, net: 1, expenses: 0), // April's P&L filed under May
            computed(6, net: 1, expenses: 0),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('one outcome per bucket, or nothing', () {
      expect(
        () => DashboardTrends.series(
          measure: TrendMeasure.netSales,
          grain: TrendGrain.monthly,
          buckets: threeMonths(),
          outcomes: [computed(4, net: 1, expenses: 0)],
        ),
        throwsArgumentError,
      );
    });

    test('a series refuses a measure its grain does not permit', () {
      expect(
        () => DashboardTrends.series(
          measure: TrendMeasure.operatingProfit,
          grain: TrendGrain.daily,
          buckets: const [],
          outcomes: const [],
        ),
        throwsArgumentError,
      );
    });

    test('points from two different scopes are refused', () {
      final buckets = threeMonths();
      PnlOutcome forUnit(int month, String unit) => PnlComputed(
        PnlResult(
          range: bucketRange(month),
          businessUnitId: unit,
          grossSales: _p(1),
          gst: Money.zero,
          netSales: _p(1),
          expenses: Money.zero,
        ),
      );
      expect(
        () => DashboardTrends.series(
          measure: TrendMeasure.netSales,
          grain: TrendGrain.monthly,
          buckets: buckets,
          outcomes: [
            forUnit(4, 'unit-ccr'),
            forUnit(5, 'unit-hki'),
            forUnit(6, 'unit-ccr'),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('best and worst day rank daily Net Sales only (D-255)', () {
    test('the highest and lowest Net Sales days', () {
      final r = DailyNetSalesRanking.rank({
        _d(2026, 9, 1): _day(_d(2026, 9, 1), 500),
        _d(2026, 9, 2): _day(_d(2026, 9, 2), 900),
        _d(2026, 9, 3): _day(_d(2026, 9, 3), 100),
      });
      final ranked = r as DailyRanked;
      expect(ranked.best, _p(900));
      expect(ranked.bestDays, [_d(2026, 9, 2)]);
      expect(ranked.worst, _p(100));
      expect(ranked.worstDays, [_d(2026, 9, 3)]);
      expect(ranked.allEqual, isFalse);
    });

    test('ties are all reported, in date order, never broken silently', () {
      final r =
          DailyNetSalesRanking.rank({
                _d(2026, 9, 3): _day(_d(2026, 9, 3), 900),
                _d(2026, 9, 1): _day(_d(2026, 9, 1), 900),
                _d(2026, 9, 2): _day(_d(2026, 9, 2), 100),
              })
              as DailyRanked;
      expect(r.bestDays, [_d(2026, 9, 1), _d(2026, 9, 3)]);
    });

    test('every day equal is stated as such', () {
      final r =
          DailyNetSalesRanking.rank({
                _d(2026, 9, 1): _day(_d(2026, 9, 1), 0),
                _d(2026, 9, 2): _day(_d(2026, 9, 2), 0),
              })
              as DailyRanked;
      expect(r.allEqual, isTrue);
    });

    test('one unavailable day refuses the whole ranking', () {
      final r = DailyNetSalesRanking.rank({
        _d(2026, 9, 1): _day(_d(2026, 9, 1), 500),
        _d(2026, 9, 2): const PnlRefused(PnlRefusal.revenueUnavailable),
      });
      expect(r, isA<DailyRankingUnavailable>());
      expect(
        (r as DailyRankingUnavailable).reason,
        DailyRankingRefusal.dayUnavailable,
      );
      expect(r.unavailableDays, [_d(2026, 9, 2)]);
    });

    test('no days is refused, not ranked', () {
      expect(
        (DailyNetSalesRanking.rank(const {}) as DailyRankingUnavailable).reason,
        DailyRankingRefusal.noDays,
      );
    });

    test(
      'a result that is not the single day it is filed under is an error',
      () {
        expect(
          () => DailyNetSalesRanking.rank({
            _d(2026, 9, 1): _day(_d(2026, 9, 2), 500),
          }),
          throwsArgumentError,
        );
      },
    );

    test('days from two different scopes cannot be ranked together', () {
      expect(
        () => DailyNetSalesRanking.rank({
          _d(2026, 9, 1): _day(_d(2026, 9, 1), 500),
          _d(2026, 9, 2): _day(_d(2026, 9, 2), 500, unit: 'unit-hki'),
        }),
        throwsArgumentError,
      );
    });
  });

  group('Top N + Others (D-258)', () {
    final lines = [
      _cat('d1', 'kirana', 5000),
      _cat('d1', 'veg', 3000),
      _cat('d2', 'power', 7000),
      _cat('d2', 'water', 1000),
      _cat('d3', 'misc', 3000),
    ];

    test('the top categories by amount, and Others is the exact rest', () {
      final g =
          TopN.expenseCategories(
                _result(expenses: lines, expenseTotal: 19000),
                n: 2,
              )
              as TopNGrouped;
      expect(g.top.map((l) => l.amount), [_p(7000), _p(5000)]);
      expect(g.others, _p(7000));
      expect(g.othersCount, 3);
      expect(g.total, _p(19000));
    });

    test('equal amounts are ordered by identity, deterministically', () {
      final g =
          TopN.expenseCategories(
                _result(expenses: lines, expenseTotal: 19000),
                n: 4,
              )
              as TopNGrouped;
      // veg and misc both 3000: ordered by their key, so the result never flickers.
      expect(g.top.map((l) => l.amount), [
        _p(7000),
        _p(5000),
        _p(3000),
        _p(3000),
      ]);
      expect(g.top[2].key.compareTo(g.top[3].key) < 0, isTrue);
      expect(g.others, _p(1000));
    });

    test('N at or above the count has no Others', () {
      final g =
          TopN.expenseCategories(
                _result(expenses: lines, expenseTotal: 19000),
                n: 5,
              )
              as TopNGrouped;
      expect(g.others, isNull);
      expect(g.othersCount, 0);
    });

    test('a set that does not reconcile is refused, not drawn', () {
      final g = TopN.expenseCategories(
        _result(expenses: lines, expenseTotal: 19001),
        n: 2,
      );
      expect(g, isA<TopNRefused>());
      expect((g as TopNRefused).reason, TopNRefusal.doesNotReconcile);
    });

    test('an empty set reconciles only against zero', () {
      expect(
        TopN.expenseCategories(
          _result(expenses: const [], expenseTotal: 0),
          n: 3,
        ),
        isA<TopNGrouped>(),
      );
      expect(
        TopN.expenseCategories(
          _result(expenses: const [], expenseTotal: 5),
          n: 3,
        ),
        isA<TopNRefused>(),
      );
    });

    test('departments are grouped exactly before ranking', () {
      final g =
          TopN.departments(_result(expenses: lines, expenseTotal: 19000), n: 1)
              as TopNGrouped<ExpenseHierarchyLine>;
      // d1 = 8000, d2 = 8000, d3 = 3000 -> tie on 8000 broken by key: d1 first.
      expect(g.top.single.amount, _p(8000));
      expect(g.top.single.line.departmentId, 'd1');
      expect(g.others, _p(11000));
    });

    test('revenue mix ranks by Net Sales and reconciles against it', () {
      final revenue = [
        _rev('restaurant', 8000),
        _rev('nandbhog', 2000),
        _rev('room', 5000),
      ];
      final g =
          TopN.revenueCategories(
                _result(
                  expenses: const [],
                  expenseTotal: 0,
                  revenue: revenue,
                  netTotal: 15000,
                ),
                n: 2,
              )
              as TopNGrouped;
      expect(g.top.map((l) => l.amount), [_p(8000), _p(5000)]);
      expect(g.others, _p(2000));
      expect(
        TopN.revenueCategories(
          _result(
            expenses: const [],
            expenseTotal: 0,
            revenue: revenue,
            netTotal: 15001,
          ),
          n: 2,
        ),
        isA<TopNRefused>(),
      );
    });

    test('N below one is a programming error', () {
      expect(
        () => TopN.expenseCategories(
          _result(expenses: lines, expenseTotal: 19000),
          n: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
