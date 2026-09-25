/// The analysis exports say what the Analytics screens say (Phase 7 Slice 9; D-232).
///
/// `lib/core/export` may not import a feature file, so the analysis sentences live twice:
/// once in the dashboard and Analytics wording, once in `export_wording.dart`. This test
/// holds the two to the same words, so a screen and a file of the same report cannot
/// describe a comparison, a trend point or a ranking differently.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/design/charts/chart_series.dart';
import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';

import '../../support/export_fixtures.dart';

void main() {
  test('an unavailable comparison, for each missing side', () {
    for (final side in ComparisonSide.values) {
      final comparison = MoneyComparisonUnavailable(
        side: side,
        currentRefusal: null,
        previousRefusal: null,
      );
      expect(
        exportNoComparisonLine(side),
        dashboardMoneyMovement(comparison).text,
      );
    }
  });

  test('the movement and every reason a percentage is withheld', () {
    final cases = <PnlOutcome>[
      PnlComputed(fxConsolidatedAugust()),
      PnlComputed(
        fxResult(range: fxAugust, revenue: const [], expenses: const []),
      ),
      PnlComputed(
        fxResult(
          range: fxAugust,
          revenue: const [],
          expenses: [fxExpense(fxCcr, 'kirana', 500000)],
        ),
      ),
    ];
    final notes = <String?>{};
    for (final previous in cases) {
      final comparison = fxComparison(previous: previous);
      for (final c in [
        comparison.grossSales,
        comparison.netSales,
        comparison.operatingProfit,
      ]) {
        if (c is! MoneyComparisonAvailable) continue;
        final screen = dashboardMoneyMovement(c);
        expect(screen.text, startsWith(exportChangeText(c)));
        expect(exportPercentNote(c), screen.note);
        notes.add(exportPercentNote(c));
      }
    }
    // Not vacuous: a percentage, a nil previous period and a loss were all exercised.
    expect(notes, contains(null));
    expect(notes.whereType<String>().length, greaterThanOrEqualTo(2));
  });

  test('trend measures, grains and positions', () {
    for (final m in TrendMeasure.values) {
      expect(exportMeasureLabel(m), m.chartLabel);
    }
    for (final g in TrendGrain.values) {
      expect(exportGrainLabel(g), g.chartLabel);
    }
    final range = fxRange(
      BusinessDate.of(2026, 8, 12),
      BusinessDate.of(2026, 9, 19),
    );
    for (final grain in TrendGrain.values) {
      for (final bucket in DashboardTrends.buckets(
        range,
        grain,
        measure: TrendMeasure.netSales,
      )) {
        expect(
          exportBucketLabel(bucket, grain),
          dashboardBucketLabel(bucket, grain),
        );
      }
    }
  });

  test(
    'the comparison period, a capped comparator, and the missing trends',
    () {
      final capped = DashboardPeriodPair.forTesting(
        kind: DashboardPeriodKind.monthToDate,
        current: fxRange(
          BusinessDate.of(2027, 3, 1),
          BusinessDate.of(2027, 3, 31),
        ),
        comparison: fxRange(
          BusinessDate.of(2027, 2, 1),
          BusinessDate.of(2027, 2, 28),
        ),
        comparisonCapped: true,
      );
      for (final pair in [fxPair, capped]) {
        expect(exportComparedWithLine(pair), analyticsComparedWithLine(pair));
        expect(exportCapNote(pair), dashboardCapNote(pair));
      }
      for (final kind in DashboardPeriodKind.values) {
        expect(
          analyticsNoNetSalesTrend(kind),
          startsWith(exportNoNetSalesTrendLine(kind)),
        );
        expect(exportNoExpenseTrendLine(kind), analyticsNoExpenseTrend(kind));
      }
      expect(exportComparisonOrderNote, analyticsComparisonOrderNote);
    },
  );
}
