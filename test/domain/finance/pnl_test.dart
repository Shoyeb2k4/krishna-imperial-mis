/// The canonical P&L arithmetic (Phase 5 Slice 2).
///
/// Pure domain. No database, no network, no widget — if any of these tests needed one,
/// the calculator would be in the wrong layer.
///
/// The claim under test is narrow and total: **given canonical summed paise, the domain
/// derives Gross Sales, GST, Net Sales, Expenses and Operating Profit exactly, and refuses
/// rather than guessing when it cannot.**
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

import '../../support/pnl_reference.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';

final _june = MonthPeriod(2026, 6);

RevenueTotals _revenue({
  required int gross,
  required int tax,
  required int net,
  int n = 1,
}) => RevenueTotals(
  gross: Money.fromPaise(gross),
  tax: Money.fromPaise(tax),
  net: Money.fromPaise(net),
  contributions: n,
);

ExpenseTotals _expenses(int paise, {int n = 1}) =>
    ExpenseTotals(amount: Money.fromPaise(paise), contributions: n);

PnlResult _compute({
  required RevenueTotals revenue,
  required ExpenseTotals expenses,
  String? unit,
  ReportingPeriod? period,
  List<RevenueCategoryLine> byCategory = const [],
}) {
  final outcome = Pnl.compute(
    period: period ?? _june,
    revenue: SideAvailable(revenue),
    expenses: SideAvailable(expenses),
    businessUnitId: unit,
    revenueByCategory: byCategory,
  );
  return (outcome as PnlComputed).result;
}

void main() {
  // ── The worked controls from the approved architecture ────────────────────
  //
  // These are the figures the Phase 5 planning audit put to the project lead and he
  // approved. They are the verified FY 2026-27 baseline arithmetic, and every one is a
  // sum of accepted component snapshots — not a rate applied to anything.
  group('Crystal Canopy Rooftop, worked exactly', () {
    // Restaurant Rs 1,00,000 inclusive 5%  ->  gross 10000000, tax 476190, net 9523810
    // Nandbhog      Rs 8,700 inclusive 5%  ->  gross   870000, tax  41429, net  828571
    final restaurant = _revenue(gross: 10000000, tax: 476190, net: 9523810);
    final nandbhog = _revenue(gross: 870000, tax: 41429, net: 828571);

    test('the two categories sum to the property total, to the paisa', () {
      final ccr = _compute(
        revenue: restaurant + nandbhog,
        expenses: _expenses(4500000),
        unit: _ccr,
      );

      expect(ccr.grossSales, Money.fromPaise(10870000));
      expect(ccr.gst, Money.fromPaise(517619));
      expect(ccr.netSales, Money.fromPaise(10352381));
      expect(ccr.expenses, Money.fromPaise(4500000));
      expect(ccr.operatingProfit, Money.fromPaise(5852381));
    });

    test('Gross Sales = GST + Net Sales, exactly', () {
      final ccr = _compute(
        revenue: restaurant + nandbhog,
        expenses: _expenses(4500000),
        unit: _ccr,
      );
      expect(ccr.reconciles, isTrue);
      expect(ccr.grossSales.paise, ccr.gst.paise + ccr.netSales.paise);
    });

    test('the independent oracle agrees', () {
      final oracle = referencePnl(
        revenue: const [
          (gross: 10000000, tax: 476190, net: 9523810),
          (gross: 870000, tax: 41429, net: 828571),
        ],
        expensePaise: const [4500000],
      );
      final ccr = _compute(
        revenue: restaurant + nandbhog,
        expenses: _expenses(4500000),
        unit: _ccr,
      );

      expect(ccr.grossSales.paise, oracle.gross);
      expect(ccr.gst.paise, oracle.gst);
      expect(ccr.netSales.paise, oracle.net);
      expect(ccr.expenses.paise, oracle.expenses);
      expect(ccr.operatingProfit.paise, oracle.operatingProfit);
    });
  });

  group('Hotel Krishna Imperial, worked exactly', () {
    // Room    Rs 52,000 inclusive 5%  ->  gross 5200000, tax 247619, net 4952381
    // Banquet Rs 40,343 treatment none ->  gross 4034300, tax      0, net 4034300
    final room = _revenue(gross: 5200000, tax: 247619, net: 4952381);
    final banquet = _revenue(gross: 4034300, tax: 0, net: 4034300);

    test('an untaxed category still sums correctly', () {
      final hki = _compute(
        revenue: room + banquet,
        expenses: _expenses(0),
        unit: _hki,
      );

      expect(hki.grossSales, Money.fromPaise(9234300));
      expect(hki.gst, Money.fromPaise(247619));
      expect(hki.netSales, Money.fromPaise(8986681));
      expect(hki.reconciles, isTrue);
    });

    test(
      '`none` is carried as a treatment, never as a configured zero rate',
      () {
        final hki = _compute(
          revenue: room + banquet,
          expenses: _expenses(0),
          unit: _hki,
          byCategory: [
            RevenueCategoryLine(
              businessUnitId: _hki,
              revenueCategoryId: 'cat-room',
              totals: room,
              treatment: TaxTreatment.inclusive,
            ),
            RevenueCategoryLine(
              businessUnitId: _hki,
              revenueCategoryId: 'cat-banquet',
              totals: banquet,
              treatment: TaxTreatment.none,
            ),
          ],
        );

        final banquetLine = hki.revenueByCategory.singleWhere(
          (l) => l.revenueCategoryId == 'cat-banquet',
        );
        expect(banquetLine.treatment, TaxTreatment.none);
        expect(banquetLine.totals.tax, Money.zero);
      },
    );

    test('a configured 0% is a different fact from `none`, at the same ₹0', () {
      // Both produce no tax. The arithmetic cannot tell them apart and does not need to;
      // the breakdown must, because one is a rate somebody set and the other a treatment
      // somebody chose (D-091, D-122).
      final zeroRated = RevenueCategoryLine(
        businessUnitId: _hki,
        revenueCategoryId: 'cat-hypothetical',
        totals: _revenue(gross: 100000, tax: 0, net: 100000),
        treatment: TaxTreatment.inclusive,
      );
      final untaxed = RevenueCategoryLine(
        businessUnitId: _hki,
        revenueCategoryId: 'cat-banquet',
        totals: _revenue(gross: 100000, tax: 0, net: 100000),
        treatment: TaxTreatment.none,
      );

      expect(zeroRated.totals.tax, untaxed.totals.tax);
      expect(
        zeroRated.treatment,
        isNot(untaxed.treatment),
        reason:
            'the same ₹0 arrived two different ways and the report must say which',
      );
    });
  });

  group('consolidation', () {
    final ccr = _compute(
      revenue: _revenue(gross: 10870000, tax: 517619, net: 10352381, n: 2),
      expenses: _expenses(4500000),
      unit: _ccr,
    );
    final hki = _compute(
      revenue: _revenue(gross: 9234300, tax: 247619, net: 8986681, n: 2),
      expenses: _expenses(3000000),
      unit: _hki,
    );

    test('Σ per-unit == consolidated, for every primitive', () {
      final all = Pnl.consolidate([ccr, hki]);

      expect(all.grossSales, Money.fromPaise(20104300));
      expect(all.gst, Money.fromPaise(765238));
      expect(all.netSales, Money.fromPaise(19339062));
      expect(all.expenses, Money.fromPaise(7500000));

      expect(all.grossSales, ccr.grossSales + hki.grossSales);
      expect(all.gst, ccr.gst + hki.gst);
      expect(all.netSales, ccr.netSales + hki.netSales);
      expect(all.expenses, ccr.expenses + hki.expenses);
      expect(all.operatingProfit, ccr.operatingProfit + hki.operatingProfit);
      expect(all.reconciles, isTrue);
    });

    test('a consolidated result names no property', () {
      expect(Pnl.consolidate([ccr, hki]).isConsolidated, isTrue);
      expect(ccr.isConsolidated, isFalse);
    });

    test('consolidation is associative and order-independent', () {
      final third = _compute(
        revenue: _revenue(gross: 700, tax: 33, net: 667),
        expenses: _expenses(101),
        unit: 'unit-third',
      );
      final abThenC = Pnl.consolidate([
        Pnl.consolidate([ccr, hki]),
        third,
      ]);
      final aThenBc = Pnl.consolidate([
        ccr,
        Pnl.consolidate([hki, third]),
      ]);
      final reversed = Pnl.consolidate([third, hki, ccr]);

      for (final other in [aThenBc, reversed]) {
        expect(abThenC.grossSales, other.grossSales);
        expect(abThenC.gst, other.gst);
        expect(abThenC.netSales, other.netSales);
        expect(abThenC.expenses, other.expenses);
        expect(abThenC.operatingProfit, other.operatingProfit);
      }
    });

    test('percentages are never averaged', () {
      // CCR margin ~56.5%, HKI ~66.6%. Their mean is not the organisation's margin, and
      // a consolidated figure computed that way would flatter or punish whichever
      // property is smaller.
      final all = Pnl.consolidate([ccr, hki]);
      final consolidated = all.margin as MarginRatio;

      expect(
        consolidated.operatingProfitPaise,
        all.netSales.paise - all.expenses.paise,
      );
      expect(consolidated.netSalesPaise, all.netSales.paise);

      final ccrMargin = (ccr.margin as MarginRatio).percentageScaled(2);
      final hkiMargin = (hki.margin as MarginRatio).percentageScaled(2);
      expect(
        consolidated.percentageScaled(2),
        isNot((ccrMargin + hkiMargin) ~/ 2),
        reason: 'the mean of two margins is not the margin of the whole',
      );
    });

    test('consolidating nothing is refused, not reported as zero', () {
      expect(() => Pnl.consolidate([]), throwsArgumentError);
    });

    test('consolidating different ranges is refused', () {
      final july = _compute(
        revenue: _revenue(gross: 1, tax: 0, net: 1),
        expenses: _expenses(0),
        unit: _hki,
        period: MonthPeriod(2026, 7),
      );
      expect(() => Pnl.consolidate([ccr, july]), throwsArgumentError);
    });
  });

  // ── Never re-rate an aggregate ────────────────────────────────────────────
  group('the calculator sums accepted tax and cannot re-rate it', () {
    test('two Restaurant days: 750715 paise, not 750714', () {
      // The control this project already records. Two accepted days of Rs 76,450 and
      // Rs 81,200 at 5% inclusive:
      //
      //     summed at the component   364048 + 386667  = 750715   <- correct
      //     the rate re-applied       15765000 x 5/105 = 750714   <- one paisa less
      //
      // The calculator is never given a rate, so it has no way to produce the second
      // figure. This test pins the first and states the second beside it.
      final dayOne = _revenue(gross: 7645000, tax: 364048, net: 7280952);
      final dayTwo = _revenue(gross: 8120000, tax: 386667, net: 7733333);

      final result = _compute(
        revenue: dayOne + dayTwo,
        expenses: _expenses(0),
        unit: _ccr,
      );

      expect(result.gst, Money.fromPaise(750715));
      expect(result.grossSales, Money.fromPaise(15765000));

      // What re-rating the aggregate would have produced, computed here in the test only.
      const reRated = 15765000 * 5 ~/ 105;
      expect(reRated, 750714);
      expect(
        result.gst.paise,
        isNot(reRated),
        reason:
            'rounding happens once, at the component, and aggregates sum stored paise '
            '(spec §6.5, D-017)',
      );

      // And it still reconciles at the summed figure, which the re-rated one would not.
      expect(result.reconciles, isTrue);
    });

    test('the oracle, folding the same two rows, agrees on 750715', () {
      final oracle = referencePnl(
        revenue: const [
          (gross: 7645000, tax: 364048, net: 7280952),
          (gross: 8120000, tax: 386667, net: 7733333),
        ],
        expensePaise: const [],
      );
      expect(oracle.gst, 750715);
      expect(oracle.gross, oracle.gst + oracle.net);
    });
  });

  // ── The awkward but legitimate cases ──────────────────────────────────────
  group('a management P&L reports what happened', () {
    test('Operating Profit is negative when expenses exceed net sales', () {
      final result = _compute(
        revenue: _revenue(gross: 5000000, tax: 0, net: 5000000),
        expenses: _expenses(6000000),
        unit: _ccr,
      );
      expect(result.operatingProfit, Money.fromPaise(-1000000));
      expect(result.operatingProfit.isNegative, isTrue);
    });

    test('zero revenue with real expenses is valid, not an error', () {
      final result = _compute(
        revenue: _revenue(gross: 0, tax: 0, net: 0, n: 0),
        expenses: _expenses(500000),
        unit: _ccr,
      );
      expect(result.grossSales, Money.zero);
      expect(result.operatingProfit, Money.fromPaise(-500000));
      expect(result.reconciles, isTrue);
    });

    test('zero expenses is valid', () {
      final result = _compute(
        revenue: _revenue(gross: 100000, tax: 4762, net: 95238),
        expenses: _expenses(0, n: 0),
        unit: _ccr,
      );
      expect(result.operatingProfit, Money.fromPaise(95238));
    });

    test(
      'a total of zero over no rows is distinguishable from zero over rows',
      () {
        final nothing = _revenue(gross: 0, tax: 0, net: 0, n: 0);
        final refunded = _revenue(gross: 0, tax: 0, net: 0, n: 4);
        expect(nothing.contributions, 0);
        expect(refunded.contributions, 4);
      },
    );
  });

  // ── Margin ────────────────────────────────────────────────────────────────
  group('margin is exact, and is not a number when there are no sales', () {
    test('zero net sales gives Not Applicable, never 0%', () {
      final result = _compute(
        revenue: _revenue(gross: 0, tax: 0, net: 0, n: 0),
        expenses: _expenses(500000),
        unit: _ccr,
      );
      expect(result.margin, isA<MarginNotApplicable>());
      expect(result.margin, const MarginNotApplicable());
    });

    test('a real margin keeps its exact ratio, undivided', () {
      final result = _compute(
        revenue: _revenue(gross: 10870000, tax: 517619, net: 10352381),
        expenses: _expenses(4500000),
        unit: _ccr,
      );
      final margin = result.margin as MarginRatio;
      expect(margin.operatingProfitPaise, 5852381);
      expect(margin.netSalesPaise, 10352381);
    });

    test('precision is the caller choice, deferred rather than baked in', () {
      const margin = MarginRatio(
        operatingProfitPaise: 5852381,
        netSalesPaise: 10352381,
      );
      expect(margin.percentageScaled(0), 57); // 56.53 -> 57
      expect(margin.percentageScaled(2), 5653); // 56.53%
      expect(margin.percentageScaled(4), 565317); // 56.5317%
    });

    test('a loss rounds away from zero, symmetrically with a profit', () {
      const loss = MarginRatio(
        operatingProfitPaise: -1000000,
        netSalesPaise: 5000000,
      );
      const profit = MarginRatio(
        operatingProfitPaise: 1000000,
        netSalesPaise: 5000000,
      );
      expect(loss.percentageScaled(2), -2000);
      expect(profit.percentageScaled(2), 2000);
      expect(loss.isNegative, isTrue);
      expect(profit.isNegative, isFalse);
    });

    test('an exact half rounds away from zero in both directions', () {
      // profit 1, net 8 -> 12.5% ; at scale 0 that is 12.5 -> 13
      const up = MarginRatio(operatingProfitPaise: 1, netSalesPaise: 8);
      const down = MarginRatio(operatingProfitPaise: -1, netSalesPaise: 8);
      expect(up.percentageScaled(0), 13);
      expect(down.percentageScaled(0), -13);
    });
  });

  // ── Unavailable is not zero ───────────────────────────────────────────────
  group('a side that could not be established refuses the report (D-163)', () {
    test('unavailable revenue refuses, and reports which side', () {
      final outcome = Pnl.compute(
        period: _june,
        revenue: const SideUnavailable(ReportingSideUnavailable.notAuthorised),
        expenses: SideAvailable(_expenses(4500000)),
        businessUnitId: _ccr,
      );
      expect(outcome, isA<PnlRefused>());
      final refused = outcome as PnlRefused;
      expect(refused.refusal, PnlRefusal.revenueUnavailable);
      expect(refused.sideReason, ReportingSideUnavailable.notAuthorised);
    });

    test('unavailable expenses refuses', () {
      final outcome = Pnl.compute(
        period: _june,
        revenue: SideAvailable(_revenue(gross: 1, tax: 0, net: 1)),
        expenses: const SideUnavailable(ReportingSideUnavailable.notDownloaded),
        businessUnitId: _ccr,
      );
      final refused = outcome as PnlRefused;
      expect(refused.refusal, PnlRefusal.expensesUnavailable);
      expect(refused.sideReason, ReportingSideUnavailable.notDownloaded);
    });

    test('both unavailable refuses as both', () {
      final outcome = Pnl.compute(
        period: _june,
        revenue: const SideUnavailable(ReportingSideUnavailable.notAuthorised),
        expenses: const SideUnavailable(ReportingSideUnavailable.notAuthorised),
      );
      expect((outcome as PnlRefused).refusal, PnlRefusal.bothSidesUnavailable);
    });

    test('an actual zero is available and computes', () {
      // The distinction the type exists for: nothing happened, versus nobody knows.
      final outcome = Pnl.compute(
        period: _june,
        revenue: SideAvailable(_revenue(gross: 0, tax: 0, net: 0, n: 0)),
        expenses: SideAvailable(_expenses(0, n: 0)),
        businessUnitId: _ccr,
      );
      expect(outcome, isA<PnlComputed>());
      expect((outcome as PnlComputed).result.operatingProfit, Money.zero);
    });

    test('an invalid range refuses before either side is looked at', () {
      final outcome = Pnl.compute(
        period: CustomRangePeriod(
          from: BusinessDate.of(2026, 6, 30),
          to: BusinessDate.of(2026, 6, 1),
        ),
        revenue: const SideUnavailable(ReportingSideUnavailable.notAuthorised),
        expenses: const SideUnavailable(ReportingSideUnavailable.notAuthorised),
      );
      expect(
        (outcome as PnlRefused).refusal,
        PnlRefusal.invalidDateRange,
        reason: 'the period is wrong regardless of what could have been read',
      );
    });
  });

  // ── Breakdowns ────────────────────────────────────────────────────────────
  group('breakdowns carry identities, never display names', () {
    test('multiple categories are kept apart and reconcile to the total', () {
      final restaurant = _revenue(gross: 10000000, tax: 476190, net: 9523810);
      final nandbhog = _revenue(gross: 870000, tax: 41429, net: 828571);
      final result = _compute(
        revenue: restaurant + nandbhog,
        expenses: _expenses(0),
        unit: _ccr,
        byCategory: [
          RevenueCategoryLine(
            businessUnitId: _ccr,
            revenueCategoryId: 'cat-restaurant',
            totals: restaurant,
            treatment: TaxTreatment.inclusive,
          ),
          RevenueCategoryLine(
            businessUnitId: _ccr,
            revenueCategoryId: 'cat-nandbhog',
            totals: nandbhog,
            treatment: TaxTreatment.inclusive,
          ),
        ],
      );

      expect(result.revenueByCategory, hasLength(2));
      expect(
        Money.sum(result.revenueByCategory.map((l) => l.totals.gross)),
        result.grossSales,
      );
      expect(
        Money.sum(result.revenueByCategory.map((l) => l.totals.tax)),
        result.gst,
      );
      expect(
        result.revenueByCategory.map((l) => l.revenueCategoryId),
        containsAll(['cat-restaurant', 'cat-nandbhog']),
        reason: 'Restaurant and Nandbhog are never merged (D-089)',
      );
    });

    test('an expense line carries the hierarchy identities and no labels', () {
      const line = ExpenseHierarchyLine(
        businessUnitId: _ccr,
        departmentId: 'dept-fb',
        sectionId: 'sec-food',
        categoryId: 'cat-kirana',
        vendorId: 'vendor-sharma',
        totals: ExpenseTotals(
          amount: Money.fromPaise(1840000),
          contributions: 3,
        ),
      );
      expect(line.categoryId, 'cat-kirana');
      expect(line.vendorId, 'vendor-sharma');
      expect(line.totals.amount, Money.fromPaise(1840000));
    });

    test('breakdown lists are unmodifiable once computed', () {
      final result = _compute(
        revenue: _revenue(gross: 1, tax: 0, net: 1),
        expenses: _expenses(0),
        unit: _ccr,
        byCategory: [
          RevenueCategoryLine(
            businessUnitId: _ccr,
            revenueCategoryId: 'cat-x',
            totals: _revenue(gross: 1, tax: 0, net: 1),
          ),
        ],
      );
      expect(
        () => result.revenueByCategory.add(
          RevenueCategoryLine(
            businessUnitId: _ccr,
            revenueCategoryId: 'cat-y',
            totals: _revenue(gross: 1, tax: 0, net: 1),
          ),
        ),
        throwsUnsupportedError,
      );
    });
  });

  // ── A small matrix, folded both ways ──────────────────────────────────────
  group('the calculator and the oracle agree across a matrix', () {
    final cases = <(String, List<ReferenceRevenueRow>, List<int>)>[
      ('one paisa', [(gross: 1, tax: 0, net: 1)], [0]),
      ('seven paise of tax', [(gross: 147, tax: 7, net: 140)], [3]),
      (
        'past 32-bit',
        [(gross: 300000000000, tax: 14285714, net: 299985714286)],
        [1],
      ),
      (
        'many small rows',
        [for (var i = 1; i <= 40; i++) (gross: i * 101, tax: i, net: i * 100)],
        [for (var i = 1; i <= 40; i++) i * 7],
      ),
      ('all zero', [(gross: 0, tax: 0, net: 0)], [0]),
      ('loss', [(gross: 100, tax: 5, net: 95)], [100000]),
    ];

    for (final (name, revenueRows, expenseRows) in cases) {
      test(name, () {
        final oracle = referencePnl(
          revenue: revenueRows,
          expensePaise: expenseRows,
        );

        // The engine's job, done here by hand: sum the rows. The calculator's job is
        // everything after that.
        final summed = RevenueTotals(
          gross: Money.fromPaise(oracle.gross),
          tax: Money.fromPaise(oracle.gst),
          net: Money.fromPaise(oracle.net),
          contributions: revenueRows.length,
        );
        final result = _compute(
          revenue: summed,
          expenses: _expenses(oracle.expenses, n: expenseRows.length),
          unit: _ccr,
        );

        expect(result.grossSales.paise, oracle.gross);
        expect(result.gst.paise, oracle.gst);
        expect(result.netSales.paise, oracle.net);
        expect(result.expenses.paise, oracle.expenses);
        expect(result.operatingProfit.paise, oracle.operatingProfit);
        expect(
          result.reconciles,
          isTrue,
          reason: 'gross = tax + net holds for every case in the matrix',
        );
      });
    }
  });
}
