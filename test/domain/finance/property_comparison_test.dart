/// Splitting a consolidated P&L into its properties (Phase 6 Slice 6).
///
/// Pure domain: no database, no engine, no widget. The figures compared are exactly the
/// category lines the consolidated result was built from, and the split refuses rather
/// than showing one it cannot stand behind.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';

ReportRange _september() => switch (CustomRangePeriod(
  from: BusinessDate.of(2026, 9, 1),
  to: BusinessDate.of(2026, 9, 19),
).resolve()) {
  ReportRangeResolved(:final range) => range,
  _ => throw StateError('range'),
};

Money _p(int paise) => Money.fromPaise(paise);

RevenueCategoryLine _revenue(
  String unit,
  String category, {
  required int gross,
  required int tax,
}) => RevenueCategoryLine(
  businessUnitId: unit,
  revenueCategoryId: category,
  totals: RevenueTotals(
    gross: _p(gross),
    tax: _p(tax),
    net: _p(gross - tax),
    contributions: 1,
  ),
);

ExpenseHierarchyLine _expense(String unit, String category, int amount) =>
    ExpenseHierarchyLine(
      businessUnitId: unit,
      departmentId: '$unit-dept',
      sectionId: '$unit-section',
      categoryId: category,
      totals: ExpenseTotals(amount: _p(amount), contributions: 1),
    );

/// A consolidated result whose headline is the exact sum of the lines given.
PnlResult _consolidated({
  required List<RevenueCategoryLine> revenue,
  required List<ExpenseHierarchyLine> expenses,
  String? businessUnitId,
  Money? grossOverride,
}) => PnlResult(
  range: _september(),
  businessUnitId: businessUnitId,
  grossSales: grossOverride ?? Money.sum(revenue.map((l) => l.totals.gross)),
  gst: Money.sum(revenue.map((l) => l.totals.tax)),
  netSales: Money.sum(revenue.map((l) => l.totals.net)),
  expenses: Money.sum(expenses.map((l) => l.totals.amount)),
  revenueContributions: revenue.length,
  expenseContributions: expenses.length,
  revenueByCategory: revenue,
  expenseByHierarchy: expenses,
);

void main() {
  final twoProperties = _consolidated(
    revenue: [
      _revenue(_ccr, 'restaurant', gross: 12364200, tax: 588771),
      _revenue(_ccr, 'nandbhog', gross: 870000, tax: 41429),
      _revenue(_hki, 'banquet', gross: 4034300, tax: 0),
    ],
    expenses: [
      _expense(_ccr, 'kirana', 9420343),
      _expense(_ccr, 'water', 120000),
      _expense(_hki, 'electricity', 3000000),
    ],
  );

  group('a consolidated result splits into its properties', () {
    test('each property carries its own exact figures, in id order', () {
      final split =
          PropertyComparison.of(twoProperties) as PropertyComparisonReady;

      expect(split.properties.map((p) => p.businessUnitId), [_ccr, _hki]);
      expect(split.properties[0].result.grossSales.paise, 13234200);
      expect(split.properties[0].result.gst.paise, 630200);
      expect(split.properties[0].netSales.paise, 12604000);
      expect(split.properties[0].expenses.paise, 9540343);
      expect(split.properties[0].operatingProfit.paise, 3063657);

      expect(split.properties[1].netSales.paise, 4034300);
      expect(split.properties[1].expenses.paise, 3000000);
      expect(split.properties[1].operatingProfit.paise, 1034300);
    });

    test('the parts add back to the whole, on every primitive', () {
      final split =
          PropertyComparison.of(twoProperties) as PropertyComparisonReady;
      expect(
        Money.sum(split.properties.map((p) => p.result.grossSales)),
        twoProperties.grossSales,
      );
      expect(
        Money.sum(split.properties.map((p) => p.result.gst)),
        twoProperties.gst,
      );
      expect(
        Money.sum(split.properties.map((p) => p.netSales)),
        twoProperties.netSales,
      );
      expect(
        Money.sum(split.properties.map((p) => p.expenses)),
        twoProperties.expenses,
      );
      expect(
        Money.sum(split.properties.map((p) => p.operatingProfit)),
        twoProperties.operatingProfit,
      );
    });

    test('each property keeps its own range, and it is the report\'s', () {
      final split =
          PropertyComparison.of(twoProperties) as PropertyComparisonReady;
      for (final property in split.properties) {
        expect(property.result.range, twoProperties.range);
        expect(property.result.businessUnitId, property.businessUnitId);
        expect(property.result.isConsolidated, isFalse);
      }
    });

    test(
      'Operating Profit and the margin are the canonical calculator\'s, not a copy',
      () {
        final split =
            PropertyComparison.of(twoProperties) as PropertyComparisonReady;
        for (final property in split.properties) {
          expect(
            property.operatingProfit,
            property.result.netSales - property.result.expenses,
          );
          expect(
            property.result.margin.displayTwoDecimals,
            isNot('N/A'),
            reason: 'both properties traded, so both have a margin',
          );
        }
      },
    );

    test('a property with costs and no takings is still a property', () {
      final split =
          PropertyComparison.of(
                _consolidated(
                  revenue: [
                    _revenue(_ccr, 'restaurant', gross: 1050000, tax: 50000),
                  ],
                  expenses: [
                    _expense(_ccr, 'kirana', 200000),
                    _expense(_hki, 'electricity', 300000),
                  ],
                ),
              )
              as PropertyComparisonReady;

      expect(split.properties.map((p) => p.businessUnitId), [_ccr, _hki]);
      final hki = split.properties[1];
      expect(hki.netSales, Money.zero);
      expect(hki.expenses.paise, 300000);
      expect(hki.operatingProfit.paise, -300000);
      // No net sales, so no margin — never 0.00%.
      expect(hki.result.margin.displayTwoDecimals, 'N/A');
    });

    test('a loss is reported as it is, never clamped', () {
      final split =
          PropertyComparison.of(
                _consolidated(
                  revenue: [
                    _revenue(_ccr, 'restaurant', gross: 1050000, tax: 50000),
                    _revenue(_hki, 'banquet', gross: 500000, tax: 0),
                  ],
                  expenses: [
                    _expense(_ccr, 'kirana', 4000000),
                    _expense(_hki, 'electricity', 100000),
                  ],
                ),
              )
              as PropertyComparisonReady;

      expect(split.properties[0].operatingProfit.paise, -3000000);
      expect(split.properties[1].operatingProfit.paise, 400000);
    });
  });

  group('it refuses rather than showing a split it cannot stand behind', () {
    test('a single-property report has nothing to compare', () {
      final refusal =
          PropertyComparison.of(
                _consolidated(
                  businessUnitId: _ccr,
                  revenue: [
                    _revenue(_ccr, 'restaurant', gross: 1050000, tax: 50000),
                  ],
                  expenses: [_expense(_ccr, 'kirana', 200000)],
                ),
              )
              as PropertyComparisonRefused;
      expect(refusal.reason, PropertyComparisonRefusal.singleProperty);
    });

    test('a consolidated report that happens to cover one property too', () {
      final refusal =
          PropertyComparison.of(
                _consolidated(
                  revenue: [
                    _revenue(_ccr, 'restaurant', gross: 1050000, tax: 50000),
                  ],
                  expenses: [_expense(_ccr, 'kirana', 200000)],
                ),
              )
              as PropertyComparisonRefused;
      expect(
        refusal.reason,
        PropertyComparisonRefusal.singleProperty,
        reason:
            'an organisation report over one trading property is a chart of one bar, '
            'which compares nothing',
      );
    });

    test('a breakdown that does not reconcile is refused outright', () {
      // One category line short of the headline: grouping it by property would make
      // whichever property is missing a line look smaller than it is (D-236).
      final broken = _consolidated(
        revenue: [
          _revenue(_ccr, 'restaurant', gross: 1050000, tax: 50000),
          _revenue(_hki, 'banquet', gross: 500000, tax: 0),
        ],
        expenses: [_expense(_ccr, 'kirana', 200000)],
        grossOverride: _p(9999999),
      );
      expect(broken.breakdownReconciles, isFalse);
      final refusal =
          PropertyComparison.of(broken) as PropertyComparisonRefused;
      expect(refusal.reason, PropertyComparisonRefusal.doesNotReconcile);
    });

    test(
      'a report with no lines at all is refused, not shown as two zeroes',
      () {
        final refusal =
            PropertyComparison.of(
                  PnlResult(
                    range: _september(),
                    grossSales: Money.zero,
                    gst: Money.zero,
                    netSales: Money.zero,
                    expenses: Money.zero,
                  ),
                )
                as PropertyComparisonRefused;
        expect(refusal.reason, PropertyComparisonRefusal.singleProperty);
      },
    );
  });
}
