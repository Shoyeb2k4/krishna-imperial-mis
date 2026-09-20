/// Period-over-period comparison rules (Phase 6 Slice 2, D-253).
///
/// The project lead's rulings:
///
/// * if either side is unavailable for any reason, there is **no** numerical comparison,
///   and nothing is substituted with zero;
/// * a previous figure of zero gives a percentage of N/A, and the rupee change is kept;
/// * for Operating Profit, a negative side gives no percentage, and a sign change is
///   stated in words beside the exact rupee movement;
/// * the margin moves in **percentage points**, exactly — never as a growth rate.
///
/// Every expected value below is worked by hand in the comment beside it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

Money _p(int paise) => Money.fromPaise(paise);

final DashboardPeriodPair _pair =
    (DashboardPeriods.forToday(
              DashboardPeriodKind.monthToDate,
              BusinessDate.of(2026, 9, 17),
            )
            as DashboardPairResolved)
        .pair;

PnlOutcome _computed(
  bool current, {
  int gross = 0,
  int gst = 0,
  int net = 0,
  int expenses = 0,
  String? unit = 'unit-ccr',
}) => PnlComputed(
  PnlResult(
    range: current ? _pair.current : _pair.comparison,
    businessUnitId: unit,
    grossSales: _p(gross),
    gst: _p(gst),
    netSales: _p(net),
    expenses: _p(expenses),
  ),
);

PnlComparison _compare(PnlOutcome current, PnlOutcome previous) =>
    PnlComparison.compare(pair: _pair, current: current, previous: previous);

MoneyComparisonAvailable _available(MoneyComparison c) {
  expect(c, isA<MoneyComparisonAvailable>());
  return c as MoneyComparisonAvailable;
}

void main() {
  group('an unavailable side means no numbers at all', () {
    const refused = PnlRefused(PnlRefusal.revenueUnavailable);

    for (final (label, current, previous, side) in [
      (
        'current refused',
        refused,
        _computed(false, net: 100),
        ComparisonSide.current,
      ),
      (
        'previous refused',
        _computed(true, net: 100),
        refused,
        ComparisonSide.previous,
      ),
      ('both refused', refused, refused, ComparisonSide.both),
    ]) {
      test(label, () {
        final c = _compare(current, previous);
        for (final m in [
          c.grossSales,
          c.gst,
          c.netSales,
          c.expenses,
          c.operatingProfit,
        ]) {
          expect(m, isA<MoneyComparisonUnavailable>());
          expect((m as MoneyComparisonUnavailable).side, side);
        }
        expect(c.margin, isA<MarginComparisonUnavailable>());
        expect(
          (c.margin as MarginComparisonUnavailable).reason,
          MarginComparisonUnavailableReason.sideUnavailable,
        );
      });
    }

    test('the refusal behind each side is carried, not flattened', () {
      final c = _compare(
        const PnlRefused(PnlRefusal.noPermittedBusinessUnit),
        const PnlRefused(PnlRefusal.expensesUnavailable),
      );
      final m = c.netSales as MoneyComparisonUnavailable;
      expect(m.currentRefusal, PnlRefusal.noPermittedBusinessUnit);
      expect(m.previousRefusal, PnlRefusal.expensesUnavailable);
    });

    test('an unavailable side is never a zero', () {
      final c = _compare(
        _computed(true, net: 5000),
        const PnlRefused(PnlRefusal.bothSidesUnavailable),
      );
      // There is no `change`, no `previous` and no percentage to read.
      expect(c.netSales, isNot(isA<MoneyComparisonAvailable>()));
    });
  });

  group('the pair and the results must describe the same thing', () {
    test('a current result for the wrong range is a programming error', () {
      expect(
        () => _compare(_computed(false, net: 1), _computed(false, net: 1)),
        throwsArgumentError,
      );
    });

    test('a previous result for the wrong range is a programming error', () {
      expect(
        () => _compare(_computed(true, net: 1), _computed(true, net: 1)),
        throwsArgumentError,
      );
    });

    test('two different properties cannot be compared', () {
      expect(
        () => _compare(
          _computed(true, net: 1, unit: 'unit-ccr'),
          _computed(false, net: 1, unit: 'unit-hki'),
        ),
        throwsArgumentError,
      );
    });

    test('consolidated against consolidated is fine', () {
      final c = _compare(
        _computed(true, net: 1, unit: null),
        _computed(false, net: 1, unit: null),
      );
      expect(_available(c.netSales).change, _p(0));
    });
  });

  group('ordinary figures: Net Sales, Expenses, Gross Sales, GST', () {
    test('rupee change and percentage, exactly', () {
      // 1,15,000.00 against 1,00,000.00: +15,000.00, +15.00%.
      final c = _compare(
        _computed(true, net: 11500000),
        _computed(false, net: 10000000),
      );
      final m = _available(c.netSales);
      expect(m.current, _p(11500000));
      expect(m.previous, _p(10000000));
      expect(m.change, _p(1500000));
      final pct = m.percentChange as PercentChangeRatio;
      expect(pct.percentageScaled(2), 1500);
      expect(pct.displayTwoDecimals, '+15.00%');
    });

    test('a fall is negative, and rounds half away from zero', () {
      // 1,00,000.00 -> 66,666.66: change -33,333.34, -33.33334% -> -33.33%.
      final c = _compare(
        _computed(true, expenses: 6666666),
        _computed(false, expenses: 10000000),
      );
      final pct = _available(c.expenses).percentChange as PercentChangeRatio;
      expect(pct.percentageScaled(2), -3333);
      expect(pct.displayTwoDecimals, '-33.33%');
    });

    test('half a hundredth rounds away from zero, in both directions', () {
      // +1 paisa on 20000 paise = +0.005% -> +0.01%.
      final up = _compare(
        _computed(true, net: 20001),
        _computed(false, net: 20000),
      );
      expect(
        (_available(up.netSales).percentChange as PercentChangeRatio)
            .percentageScaled(2),
        1,
      );
      // -1 paisa on 20000 = -0.005% -> -0.01%.
      final down = _compare(
        _computed(true, net: 19999),
        _computed(false, net: 20000),
      );
      final pct = _available(down.netSales).percentChange as PercentChangeRatio;
      expect(pct.percentageScaled(2), -1);
      expect(pct.displayTwoDecimals, '-0.01%');
    });

    test('no change reads 0.00% with no sign', () {
      final c = _compare(_computed(true, net: 500), _computed(false, net: 500));
      expect(
        (_available(c.netSales).percentChange as PercentChangeRatio)
            .displayTwoDecimals,
        '0.00%',
      );
    });

    test('a previous figure of zero: percentage N/A, rupee change kept', () {
      final c = _compare(
        _computed(true, expenses: 250000),
        _computed(false, expenses: 0),
      );
      final m = _available(c.expenses);
      expect(m.change, _p(250000));
      expect(m.percentChange, isA<PercentChangeNotApplicable>());
      expect(
        (m.percentChange as PercentChangeNotApplicable).reason,
        PercentNotApplicableReason.previousZero,
      );
      expect(m.percentChange.displayTwoDecimals, 'N/A');
    });

    test('zero against zero is a zero change with N/A', () {
      final m = _available(
        _compare(_computed(true), _computed(false)).netSales,
      );
      expect(m.change, _p(0));
      expect(
        (m.percentChange as PercentChangeNotApplicable).reason,
        PercentNotApplicableReason.previousZero,
      );
    });

    test('a negative previous figure gives no percentage', () {
      final m = _available(
        _compare(
          _computed(true, net: 100),
          _computed(false, net: -100),
        ).netSales,
      );
      expect(m.change, _p(200));
      expect(
        (m.percentChange as PercentChangeNotApplicable).reason,
        PercentNotApplicableReason.previousNegative,
      );
    });

    // ── D-256, final ────────────────────────────────────────────────────────
    //
    //   percentage only when   previous > 0  AND  current >= 0
    //
    // Every row states the rupee movement it still expects, because that is the half the
    // ruling keeps in every case.
    for (final (label, current, previous, change, reason)
        in <(String, int, int, int, PercentNotApplicableReason?)>[
          ('both positive, growth', 150, 100, 50, null),
          ('both positive, decline', 60, 100, -40, null),
          ('current exactly zero is still a percentage', 0, 100, -100, null),
          (
            'previous zero',
            100,
            0,
            100,
            PercentNotApplicableReason.previousZero,
          ),
          (
            'previous negative',
            100,
            -100,
            200,
            PercentNotApplicableReason.previousNegative,
          ),
          (
            'current negative',
            -100,
            100,
            -200,
            PercentNotApplicableReason.currentNegative,
          ),
          (
            'both negative names the base',
            -50,
            -100,
            50,
            PercentNotApplicableReason.previousNegative,
          ),
        ]) {
      test('D-256: $label', () {
        for (final m in [
          _available(
            _compare(
              _computed(true, net: current),
              _computed(false, net: previous),
            ).netSales,
          ),
          _available(
            _compare(
              _computed(true, expenses: current),
              _computed(false, expenses: previous),
            ).expenses,
          ),
        ]) {
          expect(
            m.change,
            _p(change),
            reason: 'the rupee movement is always shown',
          );
          if (reason == null) {
            expect(m.percentChange, isA<PercentChangeRatio>());
          } else {
            expect(m.percentChange, isA<PercentChangeNotApplicable>());
            expect(
              (m.percentChange as PercentChangeNotApplicable).reason,
              reason,
            );
            expect(m.percentChange.displayTwoDecimals, 'N/A');
          }
        }
      });
    }

    test('D-256 applies to all four ordinary figures, and not to profit', () {
      // Gross, GST, Net and Expenses all negative on the current side; Operating Profit
      // keeps its own stricter rule and reports the sign change instead.
      final c = _compare(
        _computed(true, gross: -300, gst: -100, net: -200, expenses: 50),
        _computed(false, gross: 300, gst: 100, net: 200, expenses: 50),
      );
      for (final m in [c.grossSales, c.gst, c.netSales]) {
        expect(
          (_available(m).percentChange as PercentChangeNotApplicable).reason,
          PercentNotApplicableReason.currentNegative,
        );
      }
      // Operating Profit: -250 against +150, a profit that became a loss.
      final profit = _available(c.operatingProfit);
      expect(profit.transition, ProfitTransition.profitToLoss);
      expect(
        (profit.percentChange as PercentChangeNotApplicable).reason,
        PercentNotApplicableReason.signChanged,
      );
    });

    test('an ordinary figure says when either side is negative', () {
      expect(
        _available(
          _compare(
            _computed(true, net: -1),
            _computed(false, net: 100),
          ).netSales,
        ).eitherSideNegative,
        isTrue,
      );
      expect(
        _available(
          _compare(
            _computed(true, net: 1),
            _computed(false, net: 100),
          ).netSales,
        ).eitherSideNegative,
        isFalse,
      );
    });

    test('ordinary figures carry no profit wording', () {
      final m = _available(
        _compare(
          _computed(true, net: 100),
          _computed(false, net: -100),
        ).netSales,
      );
      expect(m.transition, ProfitTransition.none);
    });

    test('amounts past 32 bits and a large scale do not overflow', () {
      // ₹900 crore against ₹450 crore: +100.00%.
      final c = _compare(
        _computed(true, gross: 900000000000),
        _computed(false, gross: 450000000000),
      );
      final pct = _available(c.grossSales).percentChange as PercentChangeRatio;
      expect(pct.percentageScaled(2), 10000);
      expect(pct.percentageScaled(8), 10000000000);
    });

    test('all four ordinary figures are compared, each from its own field', () {
      final c = _compare(
        _computed(true, gross: 1050, gst: 50, net: 1000, expenses: 400),
        _computed(false, gross: 525, gst: 25, net: 500, expenses: 800),
      );
      expect(_available(c.grossSales).change, _p(525));
      expect(_available(c.gst).change, _p(25));
      expect(_available(c.netSales).change, _p(500));
      expect(_available(c.expenses).change, _p(-400));
    });
  });

  group('Operating Profit', () {
    test('both positive: an ordinary percentage', () {
      // profit 600 against 400: +200, +50.00%.
      final m = _available(
        _compare(
          _computed(true, net: 1000, expenses: 400),
          _computed(false, net: 1000, expenses: 600),
        ).operatingProfit,
      );
      expect(m.current, _p(600));
      expect(m.previous, _p(400));
      expect(m.change, _p(200));
      expect(
        (m.percentChange as PercentChangeRatio).displayTwoDecimals,
        '+50.00%',
      );
      expect(m.transition, ProfitTransition.none);
    });

    test('loss to profit: words, exact rupees, no percentage', () {
      // profit +300 against a loss of -200: movement +500.
      final m = _available(
        _compare(
          _computed(true, net: 1000, expenses: 700),
          _computed(false, net: 1000, expenses: 1200),
        ).operatingProfit,
      );
      expect(m.change, _p(500));
      expect(m.transition, ProfitTransition.lossToProfit);
      expect(m.transition.wording, 'Moved from loss to profit');
      expect(
        (m.percentChange as PercentChangeNotApplicable).reason,
        PercentNotApplicableReason.signChanged,
      );
    });

    test('profit to loss: words, exact rupees, no percentage', () {
      final m = _available(
        _compare(
          _computed(true, net: 1000, expenses: 1250),
          _computed(false, net: 1000, expenses: 900),
        ).operatingProfit,
      );
      expect(m.change, _p(-350));
      expect(m.transition, ProfitTransition.profitToLoss);
      expect(m.transition.wording, 'Moved from profit to loss');
      expect(
        (m.percentChange as PercentChangeNotApplicable).reason,
        PercentNotApplicableReason.signChanged,
      );
    });

    test('two losses: no percentage, no transition', () {
      final m = _available(
        _compare(
          _computed(true, net: 100, expenses: 300),
          _computed(false, net: 100, expenses: 200),
        ).operatingProfit,
      );
      expect(m.change, _p(-100));
      expect(m.transition, ProfitTransition.none);
      expect(
        (m.percentChange as PercentChangeNotApplicable).reason,
        PercentNotApplicableReason.negativeSide,
      );
    });

    test('a loss against break-even is a negative side, not a sign change', () {
      final m = _available(
        _compare(
          _computed(true, net: 100, expenses: 300),
          _computed(false, net: 100, expenses: 100),
        ).operatingProfit,
      );
      expect(m.transition, ProfitTransition.none);
      expect(
        (m.percentChange as PercentChangeNotApplicable).reason,
        PercentNotApplicableReason.negativeSide,
      );
    });

    test('a profit against break-even: previous zero, N/A', () {
      final m = _available(
        _compare(
          _computed(true, net: 300, expenses: 100),
          _computed(false, net: 100, expenses: 100),
        ).operatingProfit,
      );
      expect(m.change, _p(200));
      expect(m.transition, ProfitTransition.none);
      expect(
        (m.percentChange as PercentChangeNotApplicable).reason,
        PercentNotApplicableReason.previousZero,
      );
    });

    test('ProfitTransition.none has no wording', () {
      expect(ProfitTransition.none.wording, isNull);
    });
  });

  group('Operating Margin moves in percentage points', () {
    test('12.30% -> 14.10% is +1.80 pp, not a growth rate', () {
      // 1230/10000 and 1410/10000.
      final c = _compare(
        _computed(true, net: 10000, expenses: 8590),
        _computed(false, net: 10000, expenses: 8770),
      );
      final m = c.margin as MarginMovement;
      expect(m.pointsScaled(2), 180);
      expect(m.displayTwoDecimals, '+1.80 pp');
    });

    test('a fall into loss is exact and signed', () {
      // current -500/2000 = -25%; previous 300/1200 = 25%: -50.00 pp.
      final c = _compare(
        _computed(true, net: 2000, expenses: 2500),
        _computed(false, net: 1200, expenses: 900),
      );
      expect((c.margin as MarginMovement).displayTwoDecimals, '-50.00 pp');
    });

    test(
      'the canonical movement is exact, taken from the two exact ratios',
      () {
        // current 1/3 = 33.333...%, previous 1/6 = 16.666...%.
        // exact movement 16.666...pp -> 16.67 pp.
        final c = _compare(
          _computed(true, net: 3, expenses: 2),
          _computed(false, net: 6, expenses: 5),
        );
        final m = c.margin as MarginMovement;
        expect(m.pointsScaled(2), 1667);
        expect(m.exactDisplayTwoDecimals, '+16.67 pp');
      },
    );

    test('D-264: what is displayed is the difference of the two displays', () {
      // The ruling's own example: 33.33% and 16.67% must show +16.66 pp on screen.
      final c = _compare(
        _computed(true, net: 3, expenses: 2),
        _computed(false, net: 6, expenses: 5),
      );
      final m = c.margin as MarginMovement;
      expect(m.current.displayTwoDecimals, '33.33%');
      expect(m.previous.displayTwoDecimals, '16.67%');
      expect(m.displayedPointsScaled(2), 1666);
      expect(m.displayTwoDecimals, '+16.66 pp');
      // And the exact figure is still here, not replaced by the rounded one.
      expect(m.pointsScaled(2), 1667);
    });

    test('equal margins read 0.00 pp', () {
      final c = _compare(
        _computed(true, net: 200, expenses: 100),
        _computed(false, net: 400, expenses: 200),
      );
      expect((c.margin as MarginMovement).displayTwoDecimals, '0.00 pp');
    });

    test('no net sales on either side: the margin is not applicable', () {
      for (final (cn, pn) in [(0, 100), (100, 0), (0, 0)]) {
        final c = _compare(
          _computed(true, net: cn, expenses: 10),
          _computed(false, net: pn, expenses: 10),
        );
        expect(c.margin, isA<MarginComparisonUnavailable>());
        expect(
          (c.margin as MarginComparisonUnavailable).reason,
          MarginComparisonUnavailableReason.marginNotApplicable,
        );
        expect(c.margin.displayTwoDecimals, 'N/A');
      }
    });

    test('crore-scale figures do not overflow the cross product', () {
      // ₹50 crore net and ₹10 crore profit against ₹40 crore and ₹6 crore:
      // 20.00% - 15.00% = +5.00 pp. The cross product is about 2e20 paise^2.
      final c = _compare(
        _computed(true, net: 50000000000, expenses: 40000000000),
        _computed(false, net: 40000000000, expenses: 34000000000),
      );
      expect((c.margin as MarginMovement).pointsScaled(2), 500);
    });

    test('negative net sales still compare exactly', () {
      // current 100/-400 = -25%, previous 100/400 = 25%: -50 pp.
      final c = _compare(
        _computed(true, net: -400, expenses: -500),
        _computed(false, net: 400, expenses: 300),
      );
      expect((c.margin as MarginMovement).pointsScaled(2), -5000);
    });
  });

  group('D-264: the three printed margin figures always reconcile', () {
    // Every pair of margins the sweep can build, at every precision a surface might
    // print. The property is exact and has no exceptions: what is shown as the movement
    // is, by construction, the difference of what is shown as the two margins.
    const nets = [1, 3, 6, 7, 9, 100, 3333, -400, -7, 999999, 2147483647];
    const profits = [0, 1, -1, 2, 5, 33, -33, 1234, -1234, 999998];

    test('displayed movement == displayed current - displayed previous', () {
      var pairs = 0;
      for (final scale in const [0, 1, 2, 3, 4]) {
        for (final n1 in nets) {
          for (final p1 in profits) {
            for (final n0 in nets) {
              for (final p0 in profits) {
                final m = MarginMovement(
                  current: MarginRatio(
                    operatingProfitPaise: p1,
                    netSalesPaise: n1,
                  ),
                  previous: MarginRatio(
                    operatingProfitPaise: p0,
                    netSalesPaise: n0,
                  ),
                );
                expect(
                  m.displayedPointsScaled(scale),
                  m.current.percentageScaled(scale) -
                      m.previous.percentageScaled(scale),
                  reason:
                      'scale $scale: $p1/$n1 against $p0/$n0 does not reconcile',
                );
                pairs++;
              }
            }
          }
        }
      }
      expect(pairs, 60_500, reason: 'the sweep must actually sweep');
    });

    test('the printed strings reconcile, parsed back', () {
      // Belt and braces: the property above is about the scaled integers. This one reads
      // the actual strings a surface puts on screen and adds them up.
      int hundredthsOf(String percent) {
        final body = percent.replaceAll('%', '').replaceAll(' pp', '');
        final negative = body.startsWith('-');
        final digits = body.replaceAll('+', '').replaceAll('-', '').split('.');
        final value = int.parse(digits[0]) * 100 + int.parse(digits[1]);
        return negative ? -value : value;
      }

      for (final (n1, p1, n0, p0) in const [
        (3, 2, 6, 5), // the ruling's example
        (10000, 1230, 10000, 1410),
        (7, 1, 9, 2),
        (-400, 100, 400, 100),
        (3333, -1234, 9, 5),
      ]) {
        final m = MarginMovement(
          current: MarginRatio(operatingProfitPaise: p1, netSalesPaise: n1),
          previous: MarginRatio(operatingProfitPaise: p0, netSalesPaise: n0),
        );
        expect(
          hundredthsOf(m.displayTwoDecimals),
          hundredthsOf(m.current.displayTwoDecimals) -
              hundredthsOf(m.previous.displayTwoDecimals),
          reason:
              '${m.current.displayTwoDecimals} - '
              '${m.previous.displayTwoDecimals} != ${m.displayTwoDecimals}',
        );
      }
    });

    test('displayed and exact never differ by more than one unit', () {
      // Each of the three roundings moves its figure by at most half a unit, so the two
      // answers can differ by at most one. Stated as a bound rather than assumed, because
      // a wider gap would mean one of the roundings is not what it claims to be.
      for (final scale in const [0, 2, 4]) {
        for (final n1 in nets) {
          for (final p1 in profits) {
            for (final n0 in nets) {
              for (final p0 in profits) {
                final m = MarginMovement(
                  current: MarginRatio(
                    operatingProfitPaise: p1,
                    netSalesPaise: n1,
                  ),
                  previous: MarginRatio(
                    operatingProfitPaise: p0,
                    netSalesPaise: n0,
                  ),
                );
                final gap =
                    (m.displayedPointsScaled(scale) - m.pointsScaled(scale))
                        .abs();
                expect(
                  gap <= 1,
                  isTrue,
                  reason: 'scale $scale: $p1/$n1 vs $p0/$n0 differ by $gap',
                );
              }
            }
          }
        }
      }
    });
  });

  group('the comparison carries the pair it was made for', () {
    test('including whether the comparator was capped', () {
      final c = _compare(_computed(true, net: 1), _computed(false, net: 1));
      expect(c.pair, same(_pair));
    });
  });
}
