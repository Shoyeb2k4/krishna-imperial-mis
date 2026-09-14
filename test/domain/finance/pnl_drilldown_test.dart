/// The drill-down rules: hierarchy grouping, exact reconciliation, and whether a fetched
/// document explains a cached row (Phase 5 Slice 10).
///
/// Pure domain. Every reconciliation rule is paired with a tampered input that must turn it
/// false, because a check that has never been seen to fail has never been shown to look at
/// anything (D-139).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_drilldown.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

Money p(int paise) => Money.fromPaise(paise);

ExpenseTotals et(int paise, [int rows = 1]) =>
    ExpenseTotals(amount: p(paise), contributions: rows);

RevenueTotals rt(int gross, int tax, [int rows = 1]) => RevenueTotals(
  gross: p(gross),
  tax: p(tax),
  net: p(gross - tax),
  contributions: rows,
);

ReportRange range(String from, String to) =>
    (CustomRangePeriod(
              from: BusinessDate.tryParse(from)!,
              to: BusinessDate.tryParse(to)!,
            ).resolve()
            as ReportRangeResolved)
        .range;

ExpenseHierarchyLine leaf(
  String unit,
  String dept,
  String section,
  String category,
  ExpenseTotals totals,
) => ExpenseHierarchyLine(
  businessUnitId: unit,
  departmentId: dept,
  sectionId: section,
  categoryId: category,
  totals: totals,
);

void main() {
  final june = range('2026-06-01', '2026-06-30');
  final d = BusinessDate.tryParse;

  group(
    'the expense hierarchy is grouped from the category lines, exactly',
    () {
      final leaves = [
        leaf('ccr', 'fb', 'food', 'kirana', et(1845000, 3)),
        leaf('ccr', 'fb', 'food', 'veg', et(420001, 2)),
        leaf('ccr', 'fb', 'bev', 'milk', et(99999, 1)),
        leaf('ccr', 'util', 'power', 'elec', et(5800000, 1)),
        leaf('hki', 'util', 'power', 'elec', et(3300000, 1)),
      ];

      test('departments, per property, add up to every expense', () {
        final departments = PnlDrilldown.departments(leaves);
        expect(
          [
            for (final l in departments)
              (
                l.businessUnitId,
                l.departmentId,
                l.totals.amount.paise,
                l.totals.contributions,
              ),
          ],
          [
            ('ccr', 'fb', 2365000, 6),
            ('ccr', 'util', 5800000, 1),
            ('hki', 'util', 3300000, 1),
          ],
        );
        expect(departments.every((l) => l.sectionId == null), isTrue);
        expect(
          PnlDrilldown.expenseChildrenReconcile(
            et(11465000, 8),
            departments.map((l) => l.totals),
          ),
          isTrue,
        );
      });

      test('sections of one department, and categories of one section', () {
        final sections = PnlDrilldown.sections(
          leaves,
          businessUnitId: 'ccr',
          departmentId: 'fb',
        );
        expect(
          [for (final l in sections) (l.sectionId, l.totals.amount.paise)],
          [('bev', 99999), ('food', 2265001)],
        );
        final categories = PnlDrilldown.categories(
          leaves,
          businessUnitId: 'ccr',
          departmentId: 'fb',
          sectionId: 'food',
        );
        expect(
          [for (final l in categories) (l.categoryId, l.totals.amount.paise)],
          [('kirana', 1845000), ('veg', 420001)],
        );
        final dept = PnlDrilldown.department(
          leaves,
          businessUnitId: 'ccr',
          departmentId: 'fb',
        )!;
        expect(
          PnlDrilldown.expenseChildrenReconcile(
            dept.totals,
            sections.map((l) => l.totals),
          ),
          isTrue,
        );
      });

      test('a department of the same id in another property is not merged', () {
        final ccr = PnlDrilldown.sections(
          leaves,
          businessUnitId: 'ccr',
          departmentId: 'util',
        );
        expect(ccr.single.totals.amount.paise, 5800000);
        expect(
          PnlDrilldown.category(
            leaves,
            businessUnitId: 'hki',
            departmentId: 'util',
            sectionId: 'power',
            categoryId: 'elec',
          )!.totals.amount.paise,
          3300000,
        );
        expect(
          PnlDrilldown.category(
            leaves,
            businessUnitId: 'hki',
            departmentId: 'fb',
            sectionId: 'food',
            categoryId: 'kirana',
          ),
          isNull,
        );
      });
    },
  );

  group('reconciliation is exact, with no tolerance and no residual bucket', () {
    test('expense children reconcile on amount and row count', () {
      final children = [et(100, 1), et(250, 2)];
      expect(
        PnlDrilldown.expenseChildrenReconcile(et(350, 3), children),
        isTrue,
      );
      // Positive controls: one paisa, and one row.
      expect(
        PnlDrilldown.expenseChildrenReconcile(et(351, 3), children),
        isFalse,
      );
      expect(
        PnlDrilldown.expenseChildrenReconcile(et(349, 3), children),
        isFalse,
      );
      expect(
        PnlDrilldown.expenseChildrenReconcile(et(350, 4), children),
        isFalse,
      );
    });

    test(
      'revenue children reconcile on gross, GST and net each, and row count',
      () {
        final children = [rt(10500, 500), rt(21000, 1000, 2)];
        final parent = rt(31500, 1500, 3);
        expect(PnlDrilldown.revenueChildrenReconcile(parent, children), isTrue);

        RevenueTotals tampered({int g = 0, int t = 0, int n = 0, int r = 0}) =>
            RevenueTotals(
              gross: p(31500 + g),
              tax: p(1500 + t),
              net: p(30000 + n),
              contributions: 3 + r,
            );
        // Each figure is compared on its own: gross and net can agree while the tax split
        // does not.
        expect(
          PnlDrilldown.revenueChildrenReconcile(tampered(g: 1), children),
          isFalse,
        );
        expect(
          PnlDrilldown.revenueChildrenReconcile(tampered(t: 1), children),
          isFalse,
        );
        expect(
          PnlDrilldown.revenueChildrenReconcile(tampered(n: 1), children),
          isFalse,
        );
        expect(
          PnlDrilldown.revenueChildrenReconcile(
            tampered(t: 1, n: -1),
            children,
          ),
          isFalse,
        );
        expect(
          PnlDrilldown.revenueChildrenReconcile(tampered(r: 1), children),
          isFalse,
        );
      },
    );

    test('no children reconcile only with a genuine zero parent', () {
      expect(PnlDrilldown.expenseChildrenReconcile(et(0, 0), const []), isTrue);
      expect(
        PnlDrilldown.expenseChildrenReconcile(et(1, 0), const []),
        isFalse,
      );
    });
  });

  group(
    'a fetched revenue document explains a cached row only when it matches',
    () {
      final line = RevenueDocumentLine(
        businessUnitId: 'ccr',
        revenueCategoryId: 'restaurant',
        revenueEntryId: 're-1',
        pnlDate: d('2026-06-15')!,
        totals: rt(10000000, 476190),
      );
      RevenueDocumentFacts facts({
        String unit = 'ccr',
        String category = 'restaurant',
        String date = '2026-06-15',
        bool accepted = true,
        bool voided = false,
        List<(int, int)> components = const [(10000000, 476190)],
      }) => RevenueDocumentFacts(
        businessUnitId: unit,
        revenueCategoryId: category,
        businessDate: d(date)!,
        accepted: accepted,
        voided: voided,
        components: [
          for (final (g, t) in components)
            (gross: p(g), tax: p(t), net: p(g - t)),
        ],
      );

      bool explains(RevenueDocumentFacts f) =>
          PnlDrilldown.revenueDocumentExplains(line, range: june, fetched: f);

      test('the same document explains the row', () {
        expect(explains(facts()), isTrue);
      });

      test('an amount correction does not', () {
        expect(
          explains(facts(components: const [(10000100, 476195)])),
          isFalse,
        );
      });

      test('a business-date correction out of the period does not', () {
        expect(explains(facts(date: '2026-07-01')), isFalse);
      });

      test('a correction to another day inside the period does not', () {
        expect(explains(facts(date: '2026-06-16')), isFalse);
      });

      test(
        'another category, another property, a void, or no acceptance does not',
        () {
          expect(explains(facts(category: 'nandbhog')), isFalse);
          expect(explains(facts(unit: 'hki')), isFalse);
          expect(explains(facts(voided: true)), isFalse);
          expect(explains(facts(accepted: false)), isFalse);
        },
      );

      test('the same total in a different number of components does not', () {
        expect(
          explains(
            facts(components: const [(5000000, 238095), (5000000, 238095)]),
          ),
          isFalse,
        );
      });
    },
  );

  group('a fetched expense document explains its contribution to one bucket', () {
    ExpenseContributionFact c(
      int paise, {
      String unit = 'ccr',
      String dept = 'fb',
      String section = 'food',
      String category = 'kirana',
      String date = '2026-06-18',
    }) => ExpenseContributionFact(
      businessUnitId: unit,
      departmentId: dept,
      sectionId: section,
      categoryId: category,
      pnlDate: d(date)!,
      amount: p(paise),
    );

    ExpenseDocumentLine line(
      int paise,
      int rows, {
      String first = '2026-06-18',
      String? last,
    }) => ExpenseDocumentLine(
      businessUnitId: 'ccr',
      departmentId: 'fb',
      sectionId: 'food',
      categoryId: 'kirana',
      expenseId: 'ex-1',
      firstPnlDate: d(first)!,
      lastPnlDate: d(last ?? first)!,
      totals: et(paise, rows),
    );

    bool explains(
      ExpenseDocumentLine l,
      List<ExpenseContributionFact> rows, {
      bool accepted = true,
      bool voided = false,
    }) => PnlDrilldown.expenseDocumentExplains(
      l,
      range: june,
      fetched: ExpenseDocumentFacts(
        accepted: accepted,
        voided: voided,
        contributions: rows,
      ),
    );

    test(
      'a multi-allocation document: two lines in one bucket are one row',
      () {
        expect(explains(line(3000, 2), [c(1000), c(2000)]), isTrue);
        expect(explains(line(3000, 2), [c(1000), c(2001)]), isFalse);
      },
    );

    test('a shared document: only this property share is the contribution', () {
      // ₹58,000 electricity: CCR ₹25,000, HKI ₹33,000. The CCR bucket holds ₹25,000.
      final shared = [
        c(2500000, dept: 'util', section: 'power', category: 'elec'),
        c(
          3300000,
          unit: 'hki',
          dept: 'util',
          section: 'power',
          category: 'elec',
        ),
      ];
      final ccrLine = ExpenseDocumentLine(
        businessUnitId: 'ccr',
        departmentId: 'util',
        sectionId: 'power',
        categoryId: 'elec',
        expenseId: 'ex-2',
        firstPnlDate: d('2026-06-18')!,
        lastPnlDate: d('2026-06-18')!,
        totals: et(2500000),
      );
      expect(
        PnlDrilldown.expenseDocumentExplains(
          ccrLine,
          range: june,
          fetched: ExpenseDocumentFacts(
            accepted: true,
            voided: false,
            contributions: shared,
          ),
        ),
        isTrue,
      );
      // A scoped reader is given only CCR's line: the same answer, for the same reason.
      expect(
        PnlDrilldown.expenseDocumentExplains(
          ccrLine,
          range: june,
          fetched: ExpenseDocumentFacts(
            accepted: true,
            voided: false,
            contributions: [shared.first],
          ),
        ),
        isTrue,
      );
    });

    test(
      'a multi-period document: only contributions inside the range count',
      () {
        // ₹60,000 across May and June: the June row is ₹30,000.
        final split = [
          c(3000000, date: '2026-05-31'),
          c(3000000, date: '2026-06-30'),
        ];
        expect(explains(line(3000000, 1, first: '2026-06-30'), split), isTrue);
        expect(
          explains(
            line(6000000, 2, first: '2026-05-31', last: '2026-06-30'),
            split,
          ),
          isFalse,
        );
      },
    );

    test('two periods inside the range are one row spanning both dates', () {
      final l = line(5000, 2, first: '2026-06-05', last: '2026-06-25');
      expect(l.spansPeriods, isTrue);
      expect(
        explains(l, [c(2000, date: '2026-06-05'), c(3000, date: '2026-06-25')]),
        isTrue,
      );
      expect(
        explains(l, [c(2000, date: '2026-06-06'), c(3000, date: '2026-06-25')]),
        isFalse,
      );
    });

    test(
      'moved to another category, voided, unaccepted, or out of the range does not',
      () {
        expect(explains(line(1000, 1), [c(1000, category: 'veg')]), isFalse);
        expect(explains(line(1000, 1), [c(1000)], voided: true), isFalse);
        expect(explains(line(1000, 1), [c(1000)], accepted: false), isFalse);
        expect(explains(line(1000, 1), [c(1000, date: '2026-07-01')]), isFalse);
        expect(explains(line(1000, 1), const []), isFalse);
      },
    );
  });

  test('document lines are equal only when every identity and figure is', () {
    RevenueDocumentLine r(int gross) => RevenueDocumentLine(
      businessUnitId: 'ccr',
      revenueCategoryId: 'restaurant',
      revenueEntryId: 're-1',
      pnlDate: d('2026-06-15')!,
      totals: rt(gross, 0),
    );
    expect(r(100), r(100));
    expect(r(100) == r(101), isFalse);
    expect({r(100)}.contains(r(100)), isTrue);
  });
}
