/// What the chart widgets actually draw (Phase 6 Slice 5).
///
/// These assert the rendered configuration rather than a screenshot: the rods fl_chart is
/// handed, the spots it is handed, the text a readout prints, and the geometry of a line
/// at a phone width. A picture comparison would pass on a chart that plotted the right
/// shape from the wrong numbers.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/design/charts/charts.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

ReportRange _range(BusinessDate from, BusinessDate to) =>
    (CustomRangePeriod(from: from, to: to).resolve() as ReportRangeResolved)
        .range;

const _refused = PnlRefused(PnlRefusal.bothSidesUnavailable);

TrendChartData _dailyNetSales(List<Money?> amounts) {
  final buckets = DashboardTrends.buckets(
    _range(
      BusinessDate.of(2026, 6, 1),
      BusinessDate.of(2026, 6, amounts.length),
    ),
    TrendGrain.daily,
    measure: TrendMeasure.netSales,
  );
  return TrendChartData.from(
    DashboardTrends.series(
      measure: TrendMeasure.netSales,
      grain: TrendGrain.daily,
      buckets: buckets,
      outcomes: [
        for (var i = 0; i < amounts.length; i++)
          if (amounts[i] == null)
            _refused
          else
            PnlComputed(
              PnlResult(
                range: buckets[i].range,
                businessUnitId: 'ccr',
                grossSales: amounts[i]!,
                gst: Money.zero,
                netSales: amounts[i]!,
                expenses: Money.zero,
              ),
            ),
      ],
    ),
    bucketLabel: (b) => '${b.range.from.day} Jun',
  );
}

TrendChartData _monthlyProfit(List<Money?> profits) {
  final buckets = DashboardTrends.buckets(
    _range(
      BusinessDate.of(2026, 4, 1),
      BusinessDate.of(2026, 4 + profits.length, 1).addDays(-1),
    ),
    TrendGrain.monthly,
    measure: TrendMeasure.operatingProfit,
  );
  const net = Money.fromRupees(100000);
  return TrendChartData.from(
    DashboardTrends.series(
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
                businessUnitId: 'hki',
                grossSales: net,
                gst: Money.zero,
                netSales: net,
                expenses: net - profits[i]!,
              ),
            ),
      ],
    ),
    bucketLabel: (b) => 'M${b.range.from.month}',
  );
}

RankedBarChartData _ranked(List<(String, int)> lines, {required int n}) =>
    RankedBarChartData.fromTopN<String>(
      TopN.group(
        [
          for (final (name, rupees) in lines)
            RankedLine(key: name, amount: Money.fromRupees(rupees), line: name),
        ],
        total: Money.fromPaise(
          lines.fold(0, (sum, l) => sum + Money.fromRupees(l.$2).paise),
        ),
        n: n,
      ),
      label: (l) => l,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1280, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: size.width, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _phone = Size(360, 800);

BarChartData _barData(WidgetTester tester) =>
    tester.widget<BarChart>(find.byType(BarChart)).data;

LineChartData _lineData(WidgetTester tester) =>
    tester.widget<LineChart>(find.byType(LineChart)).data;

String _semanticsOf(WidgetTester tester, Finder finder) =>
    tester.widget<Semantics>(finder).properties.label ?? '';

void main() {
  // ── 3 · 4 · 5 · around zero ───────────────────────────────────────────────

  group('an Operating Profit chart draws on both sides of zero', () {
    testWidgets('a loss renders below the baseline, at its real size', (
      tester,
    ) async {
      await _pump(
        tester,
        ProfitBarChart(
          title: 'Monthly Operating Profit',
          periodLabel: 'FY 2026-27',
          data: _monthlyProfit([
            Money.fromRupees(40000),
            Money.fromRupees(-15000),
          ]),
        ),
      );

      final data = _barData(tester);
      expect(data.minY, lessThan(0));
      expect(data.maxY, greaterThan(0));

      final loss = data.barGroups[1].barRods.single;
      expect(loss.fromY, 0, reason: 'a bar is measured from the baseline');
      expect(loss.toY, -1500000.0, reason: 'the exact figure, in paise');
      expect(
        data.minY,
        lessThanOrEqualTo(loss.toY),
        reason: 'a loss must never be clipped out of the plotted range',
      );
    });

    testWidgets('a profit renders above the baseline', (tester) async {
      await _pump(
        tester,
        ProfitBarChart(
          title: 'Monthly Operating Profit',
          periodLabel: 'FY 2026-27',
          data: _monthlyProfit([
            Money.fromRupees(40000),
            Money.fromRupees(-15000),
          ]),
        ),
      );
      final profit = _barData(tester).barGroups[0].barRods.single;
      expect(profit.fromY, 0);
      expect(profit.toY, 4000000.0);
      expect(_barData(tester).maxY, greaterThanOrEqualTo(profit.toY));
    });

    testWidgets('zero is a bar at the baseline; a gap is no bar at all', (
      tester,
    ) async {
      await _pump(
        tester,
        ProfitBarChart(
          title: 'Monthly Operating Profit',
          periodLabel: 'FY 2026-27',
          data: _monthlyProfit([Money.zero, null, Money.fromRupees(5000)]),
        ),
      );
      final groups = _barData(tester).barGroups;

      // Break-even: a rod, sitting exactly on zero.
      expect(groups[0].barRods, hasLength(1));
      expect(groups[0].barRods.single.toY, 0);

      // Not established: no rod. A zero-height rod is what break-even looks like, and
      // the two must never render the same (D-263).
      expect(groups[1].barRods, isEmpty);

      expect(groups[2].barRods.single.toY, 500000.0);
    });

    testWidgets('the baseline is drawn stronger than the grid', (tester) async {
      await _pump(
        tester,
        ProfitBarChart(
          title: 'Monthly Operating Profit',
          periodLabel: 'FY 2026-27',
          data: _monthlyProfit([
            Money.fromRupees(40000),
            Money.fromRupees(-15000),
          ]),
        ),
      );
      final data = _barData(tester);
      // Zero is drawn as an explicit reference line, not as whichever grid line happens
      // to land there — a generated grid does not promise to include zero at all.
      final baseline = data.extraLinesData.horizontalLines.single;
      expect(baseline.y, 0);
      final grid = data.gridData.getDrawingHorizontalLine(1000000);
      expect(baseline.strokeWidth, greaterThan(grid.strokeWidth));
      expect(baseline.color, isNot(grid.color));
    });
  });

  // ── 6 · never colour alone ────────────────────────────────────────────────

  group('profit and loss are never communicated by colour alone', () {
    testWidgets('the words appear in the description and in the readout', (
      tester,
    ) async {
      final data = _monthlyProfit([
        Money.fromRupees(40000),
        Money.fromRupees(-15000),
      ]);
      await _pump(
        tester,
        ProfitBarChart(
          title: 'Monthly Operating Profit',
          periodLabel: 'FY 2026-27',
          data: data,
        ),
      );

      // The description states both, without reference to a colour.
      final described = ChartSemantics.trend(
        title: 'Monthly Operating Profit',
        periodLabel: 'FY 2026-27',
        data: data,
      );
      expect(described.toLowerCase(), contains('profit'));
      expect(described.toLowerCase(), contains('loss'));
      expect(described.toLowerCase(), isNot(contains('red')));
      expect(described.toLowerCase(), isNot(contains('green')));

      // The readout opens on the most recent point — the loss — and says the word.
      expect(find.text('-₹15,000.00'), findsOneWidget);
      expect(find.text('loss'), findsOneWidget);
    });

    testWidgets('the figure itself carries the sign', (tester) async {
      await _pump(
        tester,
        ProfitBarChart(
          title: 'Monthly Operating Profit',
          periodLabel: 'FY 2026-27',
          data: _monthlyProfit([Money.fromRupees(-15000)]),
        ),
      );
      expect(find.text('-₹15,000.00'), findsOneWidget);
    });

    testWidgets('break-even is its own word, neither profit nor loss', (
      tester,
    ) async {
      await _pump(
        tester,
        ProfitBarChart(
          title: 'Monthly Operating Profit',
          periodLabel: 'FY 2026-27',
          data: _monthlyProfit([Money.zero]),
        ),
      );
      expect(find.text('break-even'), findsOneWidget);
    });
  });

  // ── 1 · a gap breaks the line ─────────────────────────────────────────────

  group('a missing point is a break, not a zero', () {
    testWidgets('the line carries a null spot where the figure is missing', (
      tester,
    ) async {
      await _pump(
        tester,
        TrendLineChart(
          title: 'Net Sales',
          periodLabel: '1–3 Jun 2026',
          data: _dailyNetSales([
            Money.fromRupees(1000),
            null,
            Money.fromRupees(3000),
          ]),
        ),
      );

      final spots = _lineData(tester).lineBarsData.single.spots;
      expect(spots, hasLength(3));
      expect(spots[0].y, 100000.0);
      expect(
        spots[1],
        FlSpot.nullSpot,
        reason:
            'fl_chart breaks the line at a null spot; nothing is plotted there',
      );
      expect(spots[1].y.isNaN, isTrue, reason: 'a gap is not the number zero');
      expect(spots[2].y, 300000.0);
    });

    testWidgets('the gap is stated under the plot, not left to be noticed', (
      tester,
    ) async {
      await _pump(
        tester,
        TrendLineChart(
          title: 'Net Sales',
          periodLabel: '1–3 Jun 2026',
          data: _dailyNetSales([
            Money.fromRupees(1000),
            null,
            Money.fromRupees(3000),
          ]),
        ),
      );
      expect(
        find.textContaining('shown as a gap rather than as zero'),
        findsOneWidget,
      );
    });
  });

  // ── 8 · 13 · 14 · selection prints the exact source value ─────────────────

  group('a selected figure is the exact prepared one', () {
    testWidgets(
      'a tooltip is looked up by index, never formatted from a coordinate',
      (tester) async {
        final data = _dailyNetSales([
          Money.fromPaise(123456),
          null,
          Money.fromPaise(654321),
        ]);
        await _pump(
          tester,
          TrendLineChart(title: 'Net Sales', periodLabel: 'June', data: data),
        );

        final tooltip = _lineData(tester).lineTouchData.touchTooltipData;
        final ready = data as TrendChartReady;
        final exact = (ready.points[0] as ChartPlotted).amount.label;

        final items = tooltip.getTooltipItems([
          TouchLineBarSpot(
            _lineData(tester).lineBarsData.single,
            0,
            _lineData(tester).lineBarsData.single.spots[0],
            0,
          ),
        ]);
        expect(items.single!.text, contains(exact));
        expect(items.single!.text, contains('₹1,234.56'));

        // …and a missing point says so rather than stating a figure.
        final gapItem = tooltip.getTooltipItems([
          TouchLineBarSpot(
            _lineData(tester).lineBarsData.single,
            0,
            _lineData(tester).lineBarsData.single.spots[1],
            0,
          ),
        ]);
        expect(gapItem.single!.text, contains('Not available'));
        expect(gapItem.single!.text, isNot(contains('₹')));
      },
    );

    testWidgets('Android: a touch selects a line and reads its exact figure', (
      tester,
    ) async {
      await _pump(
        tester,
        RankedBarChart(
          title: 'Top expense categories',
          periodLabel: 'June 2026',
          data: _ranked(const [
            ('Kirana & Pulses', 150181),
            ('Vegetables & Fruits', 64200),
            ('Water', 9000),
          ], n: 3),
        ),
        size: _phone,
      );

      // Nothing selected until somebody asks.
      expect(find.text('₹64,200.00'), findsOneWidget); // its own row only

      await tester.tap(find.byKey(RankedBarChart.rowKey(1)));
      await tester.pumpAndSettle();

      final readout = find.descendant(
        of: find.byKey(ChartReadout.findKey),
        matching: find.text('₹64,200.00'),
      );
      expect(readout, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ChartReadout.findKey),
          matching: find.text('Vegetables & Fruits'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Windows: a hover selects a line and reads its exact figure', (
      tester,
    ) async {
      await _pump(
        tester,
        RankedBarChart(
          title: 'Top expense categories',
          periodLabel: 'June 2026',
          data: _ranked(const [
            ('Kirana & Pulses', 150181),
            ('Vegetables & Fruits', 64200),
            ('Water', 9000),
          ], n: 3),
        ),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();
      await mouse.moveTo(
        tester.getCenter(find.byKey(RankedBarChart.rowKey(0))),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(ChartReadout.findKey),
          matching: find.text('₹1,50,181.00'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the keyboard moves the same selection', (tester) async {
      await _pump(
        tester,
        ProfitBarChart(
          title: 'Monthly Operating Profit',
          periodLabel: 'FY 2026-27',
          data: _monthlyProfit([
            Money.fromRupees(40000),
            Money.fromRupees(-15000),
          ]),
        ),
      );

      // Opens on the most recent point.
      expect(
        find.descendant(
          of: find.byKey(ChartReadout.findKey),
          matching: find.text('-₹15,000.00'),
        ),
        findsOneWidget,
      );

      // The chart owns its focus node, so the keyboard reaches the same selection a
      // pointer does.
      final focus = tester.widget<Focus>(
        find
            .ancestor(of: find.byType(BarChart), matching: find.byType(Focus))
            .first,
      );
      focus.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(ChartReadout.findKey),
          matching: find.text('₹40,000.00'),
        ),
        findsOneWidget,
      );
    });
  });

  // ── 12 · a refusal draws nothing ──────────────────────────────────────────

  group('a domain refusal creates no chart data', () {
    testWidgets('a refused ranked grouping draws no bar and no figure', (
      tester,
    ) async {
      await _pump(
        tester,
        RankedBarChart(
          title: 'Revenue mix',
          periodLabel: 'June 2026',
          data: RankedBarChartData.fromTopN<String>(
            TopN.group(
              [
                RankedLine(
                  key: 'room',
                  amount: Money.fromRupees(100),
                  line: 'room',
                ),
              ],
              total: Money.fromRupees(999),
              n: 1,
            ),
            label: (l) => l,
          ),
        ),
      );

      expect(find.byKey(ChartUnavailable.findKey), findsOneWidget);
      expect(find.byKey(RankedBarChart.rowKey(0)), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
      expect(find.textContaining('do not add up'), findsOneWidget);
    });

    testWidgets('a trend of nothing but gaps draws no plot', (tester) async {
      await _pump(
        tester,
        TrendLineChart(
          title: 'Net Sales',
          periodLabel: 'June 2026',
          data: _dailyNetSales([null, null]),
        ),
      );
      expect(find.byType(LineChart), findsNothing);
      expect(find.byKey(ChartUnavailable.findKey), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });
  });

  // ── 19 · narrow widths ────────────────────────────────────────────────────

  group('a phone width keeps a label off a figure', () {
    testWidgets('a long category and a crore figure never share a line', (
      tester,
    ) async {
      await _pump(
        tester,
        RankedBarChart(
          title: 'Department spending',
          periodLabel: 'FY 2026-27',
          data: _ranked(const [
            ('Hotel Krishna Imperial · Housekeeping & Maintenance', 12364200),
            ('Crystal Canopy Rooftop · Food Production', 8450000),
          ], n: 2),
        ),
        size: _phone,
      );

      expect(tester.takeException(), isNull);

      final label = tester.getRect(find.byKey(RankedBarChart.labelKey(0)));
      final value = tester.getRect(find.byKey(RankedBarChart.valueKey(0)));
      expect(
        label.bottom,
        lessThanOrEqualTo(value.top),
        reason: 'at phone width the name sits on its own line above the figure',
      );

      // The figure is printed whole — a truncated amount is a wrong amount.
      expect(find.text('₹1,23,64,200.00'), findsOneWidget);
      expect(value.width, greaterThan(0));
      expect(value.right, lessThanOrEqualTo(_phone.width));
    });

    testWidgets('a desktop width keeps them in separate slots on one line', (
      tester,
    ) async {
      await _pump(
        tester,
        RankedBarChart(
          title: 'Department spending',
          periodLabel: 'FY 2026-27',
          data: _ranked(const [
            ('Hotel Krishna Imperial · Housekeeping & Maintenance', 12364200),
            ('Crystal Canopy Rooftop · Food Production', 8450000),
          ], n: 2),
        ),
      );

      expect(tester.takeException(), isNull);
      final label = tester.getRect(find.byKey(RankedBarChart.labelKey(0)));
      final value = tester.getRect(find.byKey(RankedBarChart.valueKey(0)));
      expect(
        label.right,
        lessThanOrEqualTo(value.left),
        reason: 'the name never runs into the figure',
      );
      expect(find.text('₹1,23,64,200.00'), findsOneWidget);
    });

    testWidgets('a phone drops the value axis rather than squeezing the plot', (
      tester,
    ) async {
      await _pump(
        tester,
        TrendLineChart(
          title: 'Net Sales',
          periodLabel: 'June 2026',
          data: _dailyNetSales([
            Money.fromRupees(76450),
            Money.fromRupees(81200),
          ]),
        ),
        size: _phone,
      );
      expect(tester.takeException(), isNull);
      expect(
        _lineData(tester).titlesData.leftTitles.sideTitles.showTitles,
        isFalse,
      );
    });

    testWidgets(
      'a desktop shows the value axis, formatted from integer paise',
      (tester) async {
        await _pump(
          tester,
          TrendLineChart(
            title: 'Net Sales',
            periodLabel: 'June 2026',
            data: _dailyNetSales([
              Money.fromRupees(76450),
              Money.fromRupees(81200),
            ]),
          ),
        );
        expect(
          _lineData(tester).titlesData.leftTitles.sideTitles.showTitles,
          isTrue,
        );
        expect(find.text('₹81,200'), findsOneWidget);
      },
    );
  });

  // ── the description is attached to the chart ──────────────────────────────

  group('a chart carries its description in the tree', () {
    testWidgets('the semantics node holds the whole description', (
      tester,
    ) async {
      final data = _dailyNetSales([
        Money.fromRupees(1000),
        null,
        Money.fromRupees(3000),
      ]);
      await _pump(
        tester,
        TrendLineChart(
          title: 'Net Sales trend',
          periodLabel: '1–3 Jun 2026',
          data: data,
        ),
      );

      final label = _semanticsOf(tester, find.byKey(ChartFrame.semanticsKey));
      expect(label, contains('Net Sales trend'));
      expect(label, contains('₹1,000.00'));
      expect(label.toLowerCase(), contains('not available'));
    });
  });
}
