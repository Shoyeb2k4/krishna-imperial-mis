/// The export document models copy canonical results and nothing else (Phase 7 Slice 3).
///
/// Parity (spec §21.3) at the model: every figure a document carries is the canonical
/// object the screen reads — the same `Money`, the same `MoneyComparison`, the same trend
/// series — never a recomputation. Refusals stay refusals, and a document exists only
/// under a permit issued for exactly its report and scope.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/export/export_builders.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';

import '../../support/export_fixtures.dart';

D _built<D extends ExportDocument>(ExportBuild<D> build) => switch (build) {
  ExportBuilt(:final document) => document,
  ExportNotBuilt(:final reason) => throw StateError('not built: $reason'),
};

ExportBuildRefusal? _refused(ExportBuild<ExportDocument> build) =>
    switch (build) {
      ExportBuilt() => null,
      ExportNotBuilt(:final reason) => reason,
    };

void _expectStatementIs(PnlExportStatement s, PnlResult r) {
  expect(s.grossSales, r.grossSales);
  expect(s.gst, r.gst);
  expect(s.netSales, r.netSales);
  expect(s.expenses, r.expenses);
  expect(s.operatingProfit, r.operatingProfit);
  expect(
    s.margin.displayTwoDecimals,
    r.margin.displayTwoDecimals,
    reason: 'the margin is the canonical exact ratio, not a recomputation',
  );
}

void _expectNoIds(ExportDocument document) {
  for (final text in fxDocumentStrings(document)) {
    for (final forbidden in fxForbidden) {
      expect(
        text,
        isNot(contains(forbidden)),
        reason: '"$text" leaks $forbidden',
      );
    }
  }
}

void main() {
  group('Profit & Loss, one property', () {
    final result = fxCcrSeptember();
    final doc = _built(
      ExportDocuments.profitAndLoss(
        fxContext(
          fxPermit(ExportReport.profitAndLoss, ExportScope.unit(fxCcr)),
          freshness: fxFreshness(),
          periodName: 'This month',
        ),
        result,
      ),
    );

    test('one statement whose every figure is the canonical result', () {
      expect(doc.statements, hasLength(1));
      final s = doc.statements.single;
      _expectStatementIs(s, result);
      expect(s.title, 'Crystal Canopy Rooftop');
      expect(s.isConsolidatedTotal, isFalse);
      expect(s.hasTrade, isTrue);
      expect(doc.propertySplitShown, isTrue);
    });

    test(
      'the lines are the canonical lines, in the screen order, with labels',
      () {
        final s = doc.statements.single;
        final lines = s.revenueLines!;
        // Ordered by category id, exactly as PnlLineOrder (and so the screen) orders them.
        expect(lines.map((l) => l.categoryLabel), ['Nandbhog', 'Restaurant']);
        final byId = {
          for (final l in result.revenueByCategory) l.revenueCategoryId: l,
        };
        expect(lines[0].gross, byId['nandbhog']!.totals.gross);
        expect(lines[0].gst, byId['nandbhog']!.totals.tax);
        expect(lines[0].net, byId['nandbhog']!.totals.net);
        expect(lines.every((l) => l.propertyLabel == null), isTrue);
        expect(s.expenseLines!.map((l) => (l.categoryLabel, l.amount.paise)), [
          ('Kirana', 9420343),
          ('Water', 120000),
        ]);
        expect(s.expenseLines!.first.departmentLabel, 'Kirana dept');
      },
    );

    test('the header states scope, exact range, period and date basis', () {
      final h = doc.header;
      expect(h.report, ExportReport.profitAndLoss);
      expect(h.scopeLabel, 'Crystal Canopy Rooftop');
      expect(h.consolidated, isFalse);
      expect(h.range, result.range);
      expect(h.periodName, 'This month');
      expect(h.dateBasis, ExportDateBasis.pnlDateAccrual);
    });

    test(
      'no internal id, snapshot id or capability code reaches the document',
      () {
        _expectNoIds(doc);
      },
    );
  });

  group('Profit & Loss, consolidated (the spec §10 shape)', () {
    final result = fxConsolidated();
    final doc = _built(
      ExportDocuments.profitAndLoss(
        fxContext(fxPermit(ExportReport.profitAndLoss, fxBoth)),
        result,
      ),
    );

    test(
      'one statement per property in id order, then the consolidated total',
      () {
        expect(doc.statements.map((s) => s.title), [
          'Crystal Canopy Rooftop',
          'Hotel Krishna Imperial',
          'Both properties (consolidated)',
        ]);
        expect(doc.statements.last.isConsolidatedTotal, isTrue);
        _expectStatementIs(doc.statements.last, result);
        expect(doc.propertySplitShown, isTrue);
      },
    );

    test('each property statement is the domain split, figure for figure', () {
      final split = PropertyComparison.of(result) as PropertyComparisonReady;
      for (final (i, p) in split.properties.indexed) {
        _expectStatementIs(doc.statements[i], p.result);
      }
    });

    test('a loss survives as a negative Operating Profit, never clamped', () {
      final hki = doc.statements[1];
      expect(hki.operatingProfit.isNegative, isTrue);
      expect(hki.margin, isA<MarginRatio>());
    });

    test('the total lists each line with its property, and marks No GST', () {
      final total = doc.statements.last;
      final banquet = total.revenueLines!.firstWhere(
        (l) => l.categoryLabel == 'Banquet',
      );
      expect(banquet.propertyLabel, 'Hotel Krishna Imperial');
      expect(banquet.noGst, isTrue);
      expect(banquet.gst.isZero, isTrue);
      expect(
        total.revenueLines!
            .where((l) => l.categoryLabel != 'Banquet')
            .every((l) => !l.noGst),
        isTrue,
      );
      // Property statements carry no property prefix: the statement is the property.
      expect(
        doc.statements.first.revenueLines!.every(
          (l) => l.propertyLabel == null,
        ),
        isTrue,
      );
    });

    test('no internal id reaches the document', () => _expectNoIds(doc));
  });

  group('Profit & Loss that does not reconcile', () {
    // The revenue side the engine reported is one paisa more than its lines.
    final lines = fxConsolidatedRevenue();
    final result = fxResult(
      range: fxSeptember,
      revenue: lines,
      expenses: fxConsolidatedExpenses(),
      revenueSide:
          lines.fold(RevenueTotals.zero, (sum, l) => sum + l.totals) +
          RevenueTotals(
            gross: fxP(1),
            tax: fxP(0),
            net: fxP(1),
            contributions: 0,
          ),
    );
    final doc = _built(
      ExportDocuments.profitAndLoss(
        fxContext(fxPermit(ExportReport.profitAndLoss, fxBoth)),
        result,
      ),
    );

    test('shows the totals, and no line breakdown at all', () {
      expect(result.breakdownReconciles, isFalse);
      expect(doc.statements, hasLength(1), reason: 'no property split either');
      expect(doc.propertySplitShown, isFalse);
      final s = doc.statements.single;
      expect(s.breakdownShown, isFalse);
      expect(s.revenueLines, isNull);
      expect(s.expenseLines, isNull);
      _expectStatementIs(s, result);
    });
  });

  group(
    'a document exists only under a permit for exactly its report and scope',
    () {
      test('a permit for another report is refused', () {
        expect(
          _refused(
            ExportDocuments.profitAndLoss(
              fxContext(
                fxPermit(ExportReport.revenueAnalysis, ExportScope.unit(fxCcr)),
              ),
              fxCcrSeptember(),
            ),
          ),
          ExportBuildRefusal.permitForAnotherReport,
        );
      });

      test('a permit for another property is refused', () {
        expect(
          _refused(
            ExportDocuments.profitAndLoss(
              fxContext(
                fxPermit(ExportReport.profitAndLoss, ExportScope.unit(fxHki)),
              ),
              fxCcrSeptember(),
            ),
          ),
          ExportBuildRefusal.permitForAnotherScope,
        );
      });

      test('a one-property permit does not cover a consolidated result', () {
        expect(
          _refused(
            ExportDocuments.profitAndLoss(
              fxContext(
                fxPermit(ExportReport.profitAndLoss, ExportScope.unit(fxCcr)),
              ),
              fxConsolidated(),
            ),
          ),
          ExportBuildRefusal.permitForAnotherScope,
        );
      });

      test(
        'a consolidated permit that omits a property in the figures is refused',
        () {
          expect(
            _refused(
              ExportDocuments.profitAndLoss(
                fxContext(
                  fxPermit(
                    ExportReport.profitAndLoss,
                    ExportScope({fxCcr, 'unit-some-other'}),
                  ),
                ),
                fxConsolidated(),
              ),
            ),
            ExportBuildRefusal.permitForAnotherScope,
          );
        },
      );

      test('a consolidated permit does not cover a one-property result', () {
        expect(
          _refused(
            ExportDocuments.profitAndLoss(
              fxContext(fxPermit(ExportReport.profitAndLoss, fxBoth)),
              fxCcrSeptember(),
            ),
          ),
          ExportBuildRefusal.permitForAnotherScope,
        );
      });
    },
  );

  group('freshness: three statements, never merged', () {
    ExportFreshness freshnessOf(ReportingFreshness? freshness) => _built(
      ExportDocuments.profitAndLoss(
        fxContext(
          fxPermit(ExportReport.profitAndLoss, ExportScope.unit(fxCcr)),
          freshness: freshness,
        ),
        fxCcrSeptember(),
      ),
    ).header.freshness;

    test(
      'synchronised: the server-confirmed time, and the device time apart',
      () {
        final f = freshnessOf(fxFreshness());
        expect(f.synchronisedAt, fxSynchronisedAt);
        expect(f.serverHasNewer, isFalse);
        expect(f.generatedOnDeviceAt, fxGeneratedAt);
        expect(f.generatedOnDeviceAt, isNot(f.synchronisedAt));
        expect(f.timeZoneId, 'Asia/Kolkata');
      },
    );

    test(
      'server has newer: only when the report says a check confirmed it',
      () {
        final f = freshnessOf(fxFreshness(serverHasNewer: true));
        expect(f.serverHasNewer, isTrue);
        expect(f.synchronisedAt, fxSynchronisedAt);
      },
    );

    test(
      'no evidence: no claim — never the generation time passed off as one',
      () {
        final f = freshnessOf(null);
        expect(f.synchronisedAt, isNull);
        expect(f.serverHasNewer, isFalse);
        expect(f.generatedOnDeviceAt, fxGeneratedAt);
      },
    );
  });

  group('Revenue Analysis', () {
    final result = fxConsolidated();
    final comparison = fxComparison();
    final trend = fxNetSalesTrendWithGap();
    final mix = TopN.revenueCategories(result, n: 2);
    final doc = _built(
      ExportDocuments.revenueAnalysis(
        fxContext(fxPermit(ExportReport.revenueAnalysis, fxBoth)),
        result: result,
        comparison: comparison,
        trends: [fxMonthlyExpenseTrend(), trend],
        revenueMix: mix,
      ),
    );

    test(
      'the three figures are canonical, each with the domain comparison',
      () {
        expect(doc.grossSales.current, result.grossSales);
        expect(doc.gst.current, result.gst);
        expect(doc.netSales.current, result.netSales);
        expect(
          identical(doc.grossSales.comparison, comparison.grossSales),
          isTrue,
        );
        expect(identical(doc.gst.comparison, comparison.gst), isTrue);
        expect(identical(doc.netSales.comparison, comparison.netSales), isTrue);
        expect(doc.pair, comparison.pair);
      },
    );

    test('the Net Sales trend is the series itself, its gap still a gap', () {
      expect(identical(doc.netSalesTrend, trend), isTrue);
      expect(doc.netSalesTrend!.points[1], isA<TrendGap>());
    });

    test('the mix is the domain ranking, labelled as the screen labels it', () {
      final grouped = doc.revenueMix! as ExportRankingGrouped;
      final domain = mix as TopNGrouped<RevenueCategoryLine>;
      expect(
        grouped.rows.map((r) => r.amount),
        domain.top.map((r) => r.amount),
      );
      expect(grouped.others, domain.others);
      expect(grouped.othersCount, domain.othersCount);
      expect(grouped.total, domain.total);
      expect(grouped.rows.first.label, 'Crystal Canopy Rooftop · Restaurant');
    });

    test('a refused ranking stays refused, not an empty table of zeros', () {
      final refused = _built(
        ExportDocuments.revenueAnalysis(
          fxContext(fxPermit(ExportReport.revenueAnalysis, fxBoth)),
          result: result,
          comparison: comparison,
          trends: const [],
          revenueMix: const TopNRefused(TopNRefusal.doesNotReconcile),
        ),
      );
      expect(refused.revenueMix, isA<ExportRankingRefused>());
      expect(refused.netSalesTrend, isNull);
    });

    test('an unavailable comparison is carried as unavailable', () {
      final withdrawn = fxComparison(
        previous: const PnlRefused(PnlRefusal.bothSidesUnavailable),
      );
      final d = _built(
        ExportDocuments.revenueAnalysis(
          fxContext(fxPermit(ExportReport.revenueAnalysis, fxBoth)),
          result: result,
          comparison: withdrawn,
          trends: const [],
          revenueMix: null,
        ),
      );
      expect(d.netSales.comparison, isA<MoneyComparisonUnavailable>());
      expect(d.netSales.current, result.netSales);
    });

    test('a comparison made for another range is refused', () {
      expect(
        _refused(
          ExportDocuments.revenueAnalysis(
            fxContext(fxPermit(ExportReport.revenueAnalysis, fxBoth)),
            result: fxConsolidated(range: fxAugust),
            comparison: comparison,
            trends: const [],
            revenueMix: null,
          ),
        ),
        ExportBuildRefusal.comparisonForAnotherRange,
      );
    });

    test('no internal id reaches the document', () => _expectNoIds(doc));
  });

  group('Expense & Department Analysis', () {
    final result = fxConsolidated();
    final monthly = fxMonthlyExpenseTrend();
    final categories = TopN.expenseCategories(result, n: 2);
    final departments = TopN.departments(result, n: 3);
    final doc = _built(
      ExportDocuments.expenseAnalysis(
        fxContext(fxPermit(ExportReport.expenseAnalysis, fxBoth)),
        result: result,
        comparison: fxComparison(),
        trends: [fxNetSalesTrendWithGap(), monthly],
        topExpenseCategories: categories,
        departmentSpending: departments,
      ),
    );

    test('Operating Expenses is canonical, with its comparison', () {
      expect(doc.expenses.current, result.expenses);
      expect(doc.expenses.comparison, isA<MoneyComparisonAvailable>());
    });

    test('only a monthly expense series is exported (D-255)', () {
      expect(identical(doc.monthlyExpenseTrend, monthly), isTrue);
      final none = _built(
        ExportDocuments.expenseAnalysis(
          fxContext(fxPermit(ExportReport.expenseAnalysis, fxBoth)),
          result: result,
          comparison: fxComparison(),
          trends: [fxNetSalesTrendWithGap()],
          topExpenseCategories: null,
          departmentSpending: null,
        ),
      );
      expect(none.monthlyExpenseTrend, isNull);
    });

    test('both rankings are the domain groupings, with their exact Others', () {
      final cats = doc.topExpenseCategories! as ExportRankingGrouped;
      final domain = categories as TopNGrouped<ExpenseHierarchyLine>;
      expect(cats.rows.map((r) => r.amount), domain.top.map((r) => r.amount));
      expect(cats.others, domain.others);
      expect(cats.total, result.expenses);
      final depts = doc.departmentSpending! as ExportRankingGrouped;
      expect(depts.rows.first.label, contains(' dept'));
      expect(depts.rows.first.label, startsWith('Hotel Krishna Imperial · '));
    });

    test('no internal id reaches the document', () => _expectNoIds(doc));
  });

  group('Business Comparison', () {
    final result = fxConsolidated();
    final doc = _built(
      ExportDocuments.businessComparison(
        fxContext(fxPermit(ExportReport.businessComparison, fxBoth)),
        result: result,
        comparison: fxComparison(),
        propertyComparison: fxSplit(),
      ),
    );

    test('each property in id order, then both together, all canonical', () {
      expect(doc.columns.map((c) => c.label), [
        'Crystal Canopy Rooftop',
        'Hotel Krishna Imperial',
        'Both properties (consolidated)',
      ]);
      final split = fxSplit() as PropertyComparisonReady;
      for (final (i, p) in split.properties.indexed) {
        expect(doc.columns[i].netSales, p.netSales);
        expect(doc.columns[i].expenses, p.expenses);
        expect(doc.columns[i].operatingProfit, p.operatingProfit);
        expect(doc.columns[i].isTotal, isFalse);
      }
      final total = doc.columns.last;
      expect(total.isTotal, isTrue);
      expect(total.netSales, result.netSales);
      expect(total.operatingProfit, result.operatingProfit);
    });

    test('no split, no document', () {
      expect(
        _refused(
          ExportDocuments.businessComparison(
            fxContext(fxPermit(ExportReport.businessComparison, fxBoth)),
            result: result,
            comparison: fxComparison(),
            propertyComparison: const PropertyComparisonRefused(
              PropertyComparisonRefusal.doesNotReconcile,
            ),
          ),
        ),
        ExportBuildRefusal.propertySplitUnavailable,
      );
    });

    test('no internal id reaches the document', () => _expectNoIds(doc));
  });
}
