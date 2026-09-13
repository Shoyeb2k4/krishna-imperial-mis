/// Operating Margin shown to two decimal places (Phase 5 Slice 8).
///
/// The project lead's ruling: display to 2 decimal places, `12.34%` / `-4.27%`, rounding to
/// 0.01 percentage point exactly and symmetrically, and `N/A` — never `0.00%` — when Net
/// Sales are zero. Presentation rounding only: the exact `MarginRatio` stays the
/// calculation, and nothing here touches a rupee figure or a `double`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';

MarginRatio _m(int profit, int net) =>
    MarginRatio(operatingProfitPaise: profit, netSalesPaise: net);

void main() {
  test('zero net sales reads N/A, never 0.00%', () {
    expect(const MarginNotApplicable().displayTwoDecimals, 'N/A');
  });

  test('the examples in the ruling', () {
    expect(_m(1234, 10000).displayTwoDecimals, '12.34%');
    expect(_m(-427, 10000).displayTwoDecimals, '-4.27%');
  });

  test('a real margin of exactly zero is 0.00%, distinct from N/A', () {
    expect(_m(0, 10000).displayTwoDecimals, '0.00%');
  });

  test('the worked Crystal Canopy control', () {
    expect(_m(5852381, 10352381).displayTwoDecimals, '56.53%');
  });

  test('half a hundredth rounds away from zero, symmetrically', () {
    // 12.345% and -12.345%.
    expect(_m(12345, 100000).displayTwoDecimals, '12.35%');
    expect(_m(-12345, 100000).displayTwoDecimals, '-12.35%');
    // 12.344% and -12.344%.
    expect(_m(12344, 100000).displayTwoDecimals, '12.34%');
    expect(_m(-12344, 100000).displayTwoDecimals, '-12.34%');
  });

  test('a loss under one percent keeps its sign', () {
    // -0.05%: the whole-percent part is zero, and the sign must not disappear with it.
    expect(_m(-5, 10000).displayTwoDecimals, '-0.05%');
    expect(_m(5, 10000).displayTwoDecimals, '0.05%');
  });

  test('a loss that rounds to zero hundredths is not shown as negative', () {
    // -0.004% rounds to 0.00%, and "-0.00%" is not a figure.
    expect(_m(-4, 100000).displayTwoDecimals, '0.00%');
  });

  test('a margin beyond one hundred percent is shown in full', () {
    // Net sales negative and a larger loss, or a profit far above net — both real.
    expect(_m(-250000, 100000).displayTwoDecimals, '-250.00%');
    expect(_m(123456789, 100000).displayTwoDecimals, '123456.79%');
  });

  test('negative net sales with a positive profit is a negative margin', () {
    expect(_m(1000, -10000).displayTwoDecimals, '-10.00%');
  });
}
