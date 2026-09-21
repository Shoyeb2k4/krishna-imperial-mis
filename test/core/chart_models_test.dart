/// The chart presentation models (Phase 6 Slice 5).
///
/// Written before the models existed, against the API described here.
///
/// Everything below is a statement about one thing: **a chart carries the exact figure it
/// was given, and a plotted coordinate is a one-way derivation from it.** Money is never
/// reconstructed from a `double`, a gap is never a zero, and nothing a chart draws is
/// regrouped, re-ranked or re-summed from the lines it was handed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/design/charts/charts.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

ReportRange _range(BusinessDate from, BusinessDate to) =>
    (CustomRangePeriod(from: from, to: to).resolve() as ReportRangeResolved)
        .range;

PnlOutcome _netSales(ReportRange range, Money net) => PnlComputed(
  PnlResult(
    range: range,
    businessUnitId: 'ccr',
    grossSales: net,
    gst: Money.zero,
    netSales: net,
    expenses: Money.zero,
  ),
);

const _refused = PnlRefused(PnlRefusal.bothSidesUnavailable);

/// A daily Net Sales series; a null entry is a bucket the engine refused.
TrendSeries dailySeries(List<Money?> amounts) {
  final buckets = DashboardTrends.buckets(
    _range(
      BusinessDate.of(2026, 6, 1),
      BusinessDate.of(2026, 6, amounts.length),
    ),
    TrendGrain.daily,
    measure: TrendMeasure.netSales,
  );
  return DashboardTrends.series(
    measure: TrendMeasure.netSales,
    grain: TrendGrain.daily,
    buckets: buckets,
    outcomes: [
      for (var i = 0; i < amounts.length; i++)
        if (amounts[i] == null)
          _refused
        else
          _netSales(buckets[i].range, amounts[i]!),
    ],
  );
}

/// A monthly Operating Profit series from 1 April; a null entry is a refused bucket.
TrendSeries monthlyProfit(List<Money?> profits) {
  final buckets = DashboardTrends.buckets(
    _range(
      BusinessDate.of(2026, 4, 1),
      BusinessDate.of(2026, 4 + profits.length, 1).addDays(-1),
    ),
    TrendGrain.monthly,
    measure: TrendMeasure.operatingProfit,
  );
  expect(buckets, hasLength(profits.length), reason: 'fixture');
  const net = Money.fromRupees(100000);
  return DashboardTrends.series(
    measure: TrendMeasure.operatingProfit,
    grain: TrendGrain.monthly,
    buckets: buckets,
    outcomes: [
      for (var i = 0; i < profits.length; i++)
        if (profits[i] == null)
          _refused
        else
          PnlComputed(
            PnlResult(
              range: buckets[i].range,
              businessUnitId: 'ccr',
              grossSales: net,
              gst: Money.zero,
              netSales: net,
              expenses: net - profits[i]!,
            ),
          ),
    ],
  );
}

String bucketLabel(TrendBucket b) =>
    '${b.range.from.day}/${b.range.from.month}';

RankedLine<String> line(String key, int rupees) =>
    RankedLine(key: key, amount: Money.fromRupees(rupees), line: key);

void main() {
  // ── 2 · 18 · the exact figure, and the coordinate derived from it ─────────

  group('an exact figure, and a coordinate derived from it', () {
    test("the label is the production formatter's, not the coordinate's", () {
      final amount = ChartAmount.money(Money.fromPaise(12364200));
      expect(amount.label, MoneyFormatter.standard.format(amount.source));
      expect(amount.label, '₹1,23,642.00');
    });

    test('a crore-scale figure keeps every paisa through the coordinate', () {
      // ₹1,23,64,20,000.07 — past 32-bit, and the size a financial year reaches.
      const source = Money.fromPaise(123642000007);
      final amount = ChartAmount.money(source);
      expect(amount.plotted, source.paise.toDouble());
      expect(
        Money.fromPaise(amount.plotted.toInt()),
        source,
        reason: 'a coordinate that cannot round-trip is one that lost money',
      );
      expect(amount.label, '₹1,23,64,20,000.07');
    });

    test('a negative figure plots below zero and prints its sign', () {
      final amount = ChartAmount.money(Money.fromRupees(-4500));
      expect(amount.plotted, -450000.0);
      expect(amount.isNegative, isTrue);
      expect(amount.label, '-₹4,500.00');
    });

    test('a percentage carries its prepared text, never a recomputed one', () {
      const prepared = '+1.20 pp';
      const v = ChartPercent(scaled: 120, scale: 2, label: prepared);
      expect(v.label, prepared);
      expect(v.plotted, closeTo(1.2, 1e-12));
    });
  });

  // ── 1 · 5 · 7 · trends: gaps break, zero is real, partial stays partial ───

  group('a trend becomes chart points', () {
    test('a TrendGap is an absent point, never a zero', () {
      final data = TrendChartData.from(
        dailySeries([Money.fromRupees(1000), null, Money.fromRupees(3000)]),
        bucketLabel: bucketLabel,
      );
      final ready = data as TrendChartReady;

      expect(ready.points, hasLength(3));
      expect(ready.points[0], isA<ChartPlotted>());
      expect(ready.points[1], isA<ChartAbsent>());
      expect(ready.points[2], isA<ChartPlotted>());
      expect(ready.hasGap, isTrue);

      // The gap carries no figure at all — not zero, not the neighbours' average.
      expect((ready.points[1] as ChartAbsent).reason, isNotEmpty);
      expect(
        ready.points.whereType<ChartPlotted>().map((p) => p.amount.source),
        [Money.fromRupees(1000), Money.fromRupees(3000)],
      );
    });

    test('a real zero is a plotted point, and stays distinct from a gap', () {
      final ready =
          TrendChartData.from(
                dailySeries([Money.zero, null]),
                bucketLabel: bucketLabel,
              )
              as TrendChartReady;
      expect(ready.points[0], isA<ChartPlotted>());
      expect((ready.points[0] as ChartPlotted).amount.source, Money.zero);
      expect(ready.points[1], isA<ChartAbsent>());
    });

    test('a partial bucket stays marked partial, and is not extrapolated', () {
      // 15–30 June at monthly grain: one clipped month.
      final buckets = DashboardTrends.buckets(
        _range(BusinessDate.of(2026, 6, 15), BusinessDate.of(2026, 6, 30)),
        TrendGrain.monthly,
        measure: TrendMeasure.netSales,
      );
      expect(buckets.single.partial, isTrue, reason: 'fixture');

      final ready =
          TrendChartData.from(
                DashboardTrends.series(
                  measure: TrendMeasure.netSales,
                  grain: TrendGrain.monthly,
                  buckets: buckets,
                  outcomes: [
                    _netSales(buckets.single.range, Money.fromRupees(50000)),
                  ],
                ),
                bucketLabel: bucketLabel,
              )
              as TrendChartReady;

      final point = ready.points.single as ChartPlotted;
      expect(point.partial, isTrue);
      expect(
        point.amount.source,
        Money.fromRupees(50000),
        reason: 'a clipped bucket plots what that shorter period actually was',
      );
    });

    test('a series of nothing but gaps is refused rather than drawn empty', () {
      final data = TrendChartData.from(
        dailySeries([null, null]),
        bucketLabel: bucketLabel,
      );
      expect(data, isA<TrendChartRefused>());
      expect((data as TrendChartRefused).reason, isNotEmpty);
    });
  });

  // ── 3 · 4 · 5 · an Operating Profit series around zero ────────────────────

  group('an Operating Profit series', () {
    test('the axis spans both sides of zero and includes it', () {
      final ready =
          TrendChartData.from(
                monthlyProfit([
                  Money.fromRupees(40000),
                  Money.fromRupees(-15000),
                ]),
                bucketLabel: bucketLabel,
              )
              as TrendChartReady;

      expect(ready.axis.includesZero, isTrue);
      expect(ready.axis.minPaise, lessThan(0));
      expect(ready.axis.maxPaise, greaterThan(0));
      expect(
        ready.axis.minPaise,
        lessThanOrEqualTo(-1500000),
        reason: 'a loss must not be clipped out of the plotted range',
      );
      expect(
        ready.axis.maxPaise,
        greaterThanOrEqualTo(4000000),
        reason: 'a profit must not be clipped out of the plotted range',
      );
    });

    test(
      'an all-profit series still anchors at zero, so a bar has a baseline',
      () {
        final ready =
            TrendChartData.from(
                  monthlyProfit([
                    Money.fromRupees(40000),
                    Money.fromRupees(10000),
                  ]),
                  bucketLabel: bucketLabel,
                )
                as TrendChartReady;
        expect(ready.axis.includesZero, isTrue);
        expect(ready.axis.minPaise, 0);
      },
    );

    test('an all-loss series still anchors at zero', () {
      final ready =
          TrendChartData.from(
                monthlyProfit([
                  Money.fromRupees(-40000),
                  Money.fromRupees(-10000),
                ]),
                bucketLabel: bucketLabel,
              )
              as TrendChartReady;
      expect(ready.axis.includesZero, isTrue);
      expect(ready.axis.maxPaise, 0);
    });
  });

  // ── 9 · 10 · 11 · 12 · ranked bars consume, never recompute ───────────────

  group('ranked bars consume a reconciled domain result', () {
    test('a refused grouping produces no chart data at all', () {
      // Lines that do not sum to the headline: the domain refuses, and so must the chart.
      final outcome = TopN.group(
        [line('a', 100), line('b', 200)],
        total: Money.fromRupees(999),
        n: 2,
      );
      expect(outcome, isA<TopNRefused<String>>());

      final data = RankedBarChartData.fromTopN<String>(
        outcome,
        label: (l) => l,
      );
      expect(data, isA<RankedBarChartRefused>());
      expect((data as RankedBarChartRefused).reason, isNotEmpty);
    });

    test("membership is the domain's, and is not recomputed here", () {
      final outcome =
          TopN.group(
                [
                  line('kirana', 500),
                  line('vegetables', 300),
                  line('water', 100),
                  line('diesel', 100),
                ],
                total: Money.fromRupees(1000),
                n: 2,
              )
              as TopNGrouped<String>;
      expect(outcome.top.map((l) => l.key), ['kirana', 'vegetables']);

      final ready =
          RankedBarChartData.fromTopN<String>(outcome, label: (l) => l)
              as RankedBarChartReady;

      expect(ready.lines.where((l) => !l.isOthers).map((l) => l.label), [
        'kirana',
        'vegetables',
      ]);
      expect(ready.lines.last.isOthers, isTrue);
      expect(ready.lines, hasLength(3));
    });

    test('Others is the figure the domain computed, carried verbatim', () {
      final outcome =
          TopN.group(
                [
                  line('kirana', 500),
                  line('vegetables', 300),
                  line('water', 150),
                  line('diesel', 50),
                ],
                total: Money.fromRupees(1000),
                n: 1,
              )
              as TopNGrouped<String>;
      expect(outcome.others, Money.fromRupees(500));
      expect(outcome.othersCount, 3);

      final ready =
          RankedBarChartData.fromTopN<String>(outcome, label: (l) => l)
              as RankedBarChartReady;
      final others = ready.lines.singleWhere((l) => l.isOthers);
      expect(others.amount.source, Money.fromRupees(500));
      expect(ready.othersCount, 3);
      expect(others.label, contains('3'));
      expect(ready.total.source, Money.fromRupees(1000));
    });

    test('with nothing left over there is no Others line', () {
      final ready =
          RankedBarChartData.fromTopN<String>(
                TopN.group(
                  [line('room', 600), line('banquet', 400)],
                  total: Money.fromRupees(1000),
                  n: 5,
                ),
                label: (l) => l,
              )
              as RankedBarChartReady;
      expect(ready.lines.any((l) => l.isOthers), isFalse);
      expect(ready.othersCount, 0);
    });

    test("a bar's share of the widest line is a presentation ratio only", () {
      final ready =
          RankedBarChartData.fromTopN<String>(
                TopN.group(
                  [line('a', 800), line('b', 200)],
                  total: Money.fromRupees(1000),
                  n: 2,
                ),
                label: (l) => l,
              )
              as RankedBarChartReady;
      expect(ready.lines[0].fractionOfWidest, 1.0);
      expect(ready.lines[1].fractionOfWidest, closeTo(0.25, 1e-12));
      // …and the money it prints is still the exact source.
      expect(ready.lines[1].amount.label, '₹200.00');
    });

    test('a negative line still draws, and is marked as such', () {
      final ready =
          RankedBarChartData.fromTopN<String>(
                TopN.group(
                  [line('refund', -200), line('room', 1200)],
                  total: Money.fromRupees(1000),
                  n: 2,
                ),
                label: (l) => l,
              )
              as RankedBarChartReady;
      final refund = ready.lines.singleWhere((l) => l.label == 'refund');
      expect(refund.amount.isNegative, isTrue);
      expect(refund.fractionOfWidest, closeTo(200 / 1200, 1e-12));
    });
  });

  // ── 17 · one set of formatters ────────────────────────────────────────────

  group("chart formatting is the application's formatting", () {
    test('Indian digit grouping, exactly as every other surface prints it', () {
      for (final paise in const [0, 100, 123456789, -123642000, 999999999999]) {
        final money = Money.fromPaise(paise);
        expect(
          ChartAmount.money(money).label,
          MoneyFormatter.standard.format(money),
        );
      }
    });

    test('an axis tick is formatted from its own integer paise', () {
      final axis = ChartAxis.forAmounts(const [
        Money.zero,
        Money.fromRupees(1236420),
      ]);
      for (final tick in axis.ticks) {
        expect(
          tick.label,
          MoneyFormatter.wholeRupees.format(Money.fromPaise(tick.paise)),
        );
        expect(tick.plotted, tick.paise.toDouble());
      }
      expect(axis.ticks.map((t) => t.label), contains('₹12,36,420'));
    });

    test('an axis label is looked up by the coordinate it was given', () {
      final axis = ChartAxis.forAmounts(const [
        Money.zero,
        Money.fromRupees(1000),
      ]);
      final tick = axis.ticks.first;
      expect(axis.labelFor(tick.plotted), tick.label);
      expect(
        axis.labelFor(tick.plotted + 1),
        isNull,
        reason: 'a coordinate that is not a tick is not turned into a figure',
      );
    });
  });

  // ── 15 · accessibility ────────────────────────────────────────────────────

  group('a chart describes itself without colour', () {
    test('a trend names its purpose, period, series and every value', () {
      final ready =
          TrendChartData.from(
                dailySeries([
                  Money.fromRupees(1000),
                  null,
                  Money.fromRupees(3000),
                ]),
                bucketLabel: bucketLabel,
              )
              as TrendChartReady;

      final text = ChartSemantics.trend(
        title: 'Net Sales trend',
        periodLabel: '1 Jun 2026 – 3 Jun 2026',
        data: ready,
      );

      expect(text, contains('Net Sales trend'));
      expect(text, contains('1 Jun 2026 – 3 Jun 2026'));
      expect(text, contains('Net Sales'));
      expect(text, contains('₹1,000.00'));
      expect(text, contains('₹3,000.00'));
      expect(
        text.toLowerCase(),
        contains('not available'),
        reason: 'a gap must be audible, not merely invisible',
      );
      expect(
        '₹'.allMatches(text).length,
        2,
        reason: 'the gap states no figure of its own',
      );
    });

    test('a ranked chart names its lines, its Others and its total', () {
      final ready =
          RankedBarChartData.fromTopN<String>(
                TopN.group(
                  [
                    line('Kirana & Pulses', 500),
                    line('Vegetables & Fruits', 300),
                    line('Water', 200),
                  ],
                  total: Money.fromRupees(1000),
                  n: 2,
                ),
                label: (l) => l,
              )
              as RankedBarChartReady;

      final text = ChartSemantics.ranked(
        title: 'Top expense categories',
        periodLabel: 'June 2026',
        data: ready,
      );
      expect(text, contains('Top expense categories'));
      expect(text, contains('June 2026'));
      expect(text, contains('Kirana & Pulses'));
      expect(text, contains('₹500.00'));
      expect(text, contains('₹200.00'));
      expect(text, contains('₹1,000.00'));
    });

    test('a refused chart says so, and states no figure', () {
      final text = ChartSemantics.ranked(
        title: 'Revenue mix',
        periodLabel: 'June 2026',
        data: RankedBarChartData.fromTopN<String>(
          TopN.group([line('a', 1)], total: Money.fromRupees(999), n: 1),
          label: (l) => l,
        ),
      );
      expect(text, contains('Revenue mix'));
      expect(text, isNot(contains('₹')));
    });

    test('profit and loss are named in words, never left to colour', () {
      final ready =
          TrendChartData.from(
                monthlyProfit([
                  Money.fromRupees(40000),
                  Money.fromRupees(-15000),
                ]),
                bucketLabel: bucketLabel,
              )
              as TrendChartReady;
      final text = ChartSemantics.trend(
        title: 'Monthly Operating Profit',
        periodLabel: 'Apr – May 2026',
        data: ready,
      );
      expect(text.toLowerCase(), contains('profit'));
      expect(text.toLowerCase(), contains('loss'));
      expect(text, contains('-₹15,000.00'));
    });
  });
}
