/// Category lines reconcile exactly with the headline P&L (Phase 5 Slice 8).
///
/// The project lead's ruling: revenue by category and expense by category are shown on the
/// Windows P&L, and each must reconcile **exactly** with the headline totals. The check is
/// a property of the domain result, not a sum a widget performs, so the surface can refuse
/// to show a breakdown that does not add up rather than computing one of its own.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

RevenueTotals _rev(int gross, int tax, int net) => RevenueTotals(
  gross: Money.fromPaise(gross),
  tax: Money.fromPaise(tax),
  net: Money.fromPaise(net),
  contributions: 1,
);

ExpenseTotals _exp(int amount) =>
    ExpenseTotals(amount: Money.fromPaise(amount), contributions: 1);

PnlResult _compute({
  required RevenueTotals revenue,
  required ExpenseTotals expenses,
  List<RevenueCategoryLine> revenueLines = const [],
  List<ExpenseHierarchyLine> expenseLines = const [],
  String unit = 'ccr',
}) =>
    (Pnl.compute(
              period: MonthPeriod(2026, 6),
              revenue: SideAvailable(revenue),
              expenses: SideAvailable(expenses),
              businessUnitId: unit,
              revenueByCategory: revenueLines,
              expenseByHierarchy: expenseLines,
            )
            as PnlComputed)
        .result;

void main() {
  final restaurant = RevenueCategoryLine(
    businessUnitId: 'ccr',
    revenueCategoryId: 'restaurant',
    treatment: TaxTreatment.inclusive,
    totals: _rev(10000000, 476190, 9523810),
  );
  final nandbhog = RevenueCategoryLine(
    businessUnitId: 'ccr',
    revenueCategoryId: 'nandbhog',
    treatment: TaxTreatment.inclusive,
    totals: _rev(870000, 41429, 828571),
  );
  final kirana = ExpenseHierarchyLine(
    businessUnitId: 'ccr',
    departmentId: 'fb',
    sectionId: 'food',
    categoryId: 'kirana',
    totals: _exp(3000000),
  );
  final power = ExpenseHierarchyLine(
    businessUnitId: 'ccr',
    departmentId: 'util',
    sectionId: 'power',
    categoryId: 'electricity',
    totals: _exp(1500000),
  );

  test('lines that sum to the headline reconcile, on every figure', () {
    final result = _compute(
      revenue: _rev(10870000, 517619, 10352381),
      expenses: _exp(4500000),
      revenueLines: [restaurant, nandbhog],
      expenseLines: [kirana, power],
    );
    expect(result.revenueBreakdownReconciles, isTrue);
    expect(result.expenseBreakdownReconciles, isTrue);
    expect(result.breakdownReconciles, isTrue);
  });

  test('one paisa of gross missing from the lines does not reconcile', () {
    final result = _compute(
      revenue: _rev(10870001, 517619, 10352382),
      expenses: _exp(4500000),
      revenueLines: [restaurant, nandbhog],
      expenseLines: [kirana, power],
    );
    expect(result.revenueBreakdownReconciles, isFalse);
    expect(result.breakdownReconciles, isFalse);
  });

  test('GST is checked on its own, not only gross and net', () {
    // Gross and net both still agree; only the tax split disagrees.
    final skewed = RevenueCategoryLine(
      businessUnitId: 'ccr',
      revenueCategoryId: 'restaurant',
      totals: _rev(10000000, 476191, 9523810),
    );
    final result = _compute(
      revenue: _rev(10870000, 517619, 10352381),
      expenses: _exp(4500000),
      revenueLines: [skewed, nandbhog],
      expenseLines: [kirana, power],
    );
    expect(result.revenueBreakdownReconciles, isFalse);
  });

  test('one paisa of expense missing from the lines does not reconcile', () {
    final result = _compute(
      revenue: _rev(10870000, 517619, 10352381),
      expenses: _exp(4500001),
      revenueLines: [restaurant, nandbhog],
      expenseLines: [kirana, power],
    );
    expect(result.expenseBreakdownReconciles, isFalse);
    expect(result.breakdownReconciles, isFalse);
  });

  test('a genuine zero period with no lines reconciles', () {
    final result = _compute(
      revenue: RevenueTotals.zero,
      expenses: ExpenseTotals.zero,
    );
    expect(result.breakdownReconciles, isTrue);
  });

  test('a period with trade but no lines does not reconcile', () {
    // Absent lines are not a breakdown of ₹1,00,000: they are no breakdown at all.
    final result = _compute(
      revenue: _rev(10000000, 476190, 9523810),
      expenses: ExpenseTotals.zero,
    );
    expect(result.revenueBreakdownReconciles, isFalse);
  });

  test('a consolidated result reconciles when every property did', () {
    final hkiRoom = RevenueCategoryLine(
      businessUnitId: 'hki',
      revenueCategoryId: 'room',
      treatment: TaxTreatment.inclusive,
      totals: _rev(5200000, 247619, 4952381),
    );
    final hkiPower = ExpenseHierarchyLine(
      businessUnitId: 'hki',
      categoryId: 'hki-electricity',
      totals: _exp(3000000),
    );
    final ccr = _compute(
      revenue: _rev(10870000, 517619, 10352381),
      expenses: _exp(4500000),
      revenueLines: [restaurant, nandbhog],
      expenseLines: [kirana, power],
    );
    final hki = _compute(
      unit: 'hki',
      revenue: _rev(5200000, 247619, 4952381),
      expenses: _exp(3000000),
      revenueLines: [hkiRoom],
      expenseLines: [hkiPower],
    );
    final consolidated = Pnl.consolidate([ccr, hki]);
    expect(consolidated.breakdownReconciles, isTrue);
    expect(
      consolidated.range,
      (MonthPeriod(2026, 6).resolve() as ReportRangeResolved).range,
    );
    expect(BusinessDate.of(2026, 6, 1), consolidated.range.from);
  });
}
