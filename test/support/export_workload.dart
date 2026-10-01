/// The export workloads Phase 8 Slice 6 measures (D-312 D2, D-313 T2/T3).
///
/// Shared by the host test and the on-device measurement, so both report the same work.
/// Every result is produced by the canonical calculator and the domain's own comparison,
/// trend, ranking and split functions — the same objects an export is built from in
/// production. Nothing here reads a database: the stage D2 calls "canonical result
/// already available" is exactly that, so the measurement starts at the document model.
///
/// Two sizes:
///
/// * **normal** — a realistic month: both properties, the four revenue categories and the
///   twenty-three expense concepts the seed and the management P&L carry (spec §4), a
///   daily Net Sales trend over a month and a monthly expense trend over a financial year;
/// * **stress** — deliberately large, reported separately and not a verdict (T3).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:krishna_mis/core/export/pdf/analysis_pdf.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/core/export/pdf/pnl_pdf.dart';
import 'package:krishna_mis/core/export/workbook/analysis_workbook.dart';
import 'package:krishna_mis/core/export/workbook/pnl_workbook.dart';
import 'package:krishna_mis/domain/export/export_builders.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/export/export_file_save.dart';
import 'package:krishna_mis/features/export/export_pipeline.dart'
    show ExportFileFormat;

import 'export_fixtures.dart';

enum ExportWorkloadSize { normal, stress }

/// The expense concepts of spec §4, per property.
const _ccrCosts = [
  'kirana',
  'vegetables',
  'milk',
  'cylinder',
  'water',
  'paneer',
  'kitchenpayroll',
  'wages',
  'incentives',
  'electricity',
  'otheropex',
];
const _hkiCosts = [
  'housekeepingsalary',
  'frontofficesalary',
  'water',
  'tanker',
  'watercans',
  'diesel',
  'building',
  'electricity',
  'housekeeping',
  'maintenance',
  'payroll',
  'otheropex',
];

/// How large each size is. The stress lines are invented names; a real hotel has tens.
({int revenuePerUnit, int expensePerUnit, int trendMonths}) _shape(
  ExportWorkloadSize size,
) => switch (size) {
  ExportWorkloadSize.normal => (
    revenuePerUnit: 2,
    expensePerUnit: 0,
    trendMonths: 12,
  ),
  ExportWorkloadSize.stress => (
    revenuePerUnit: 20,
    expensePerUnit: 300,
    trendMonths: 60,
  ),
};

/// Expense lines for one property: the §4 concepts, or [count] invented ones.
List<ExpenseHierarchyLine> _expenses(
  String unit,
  List<String> concepts,
  int count,
  int salt,
) => [
  if (count == 0)
    for (final (i, c) in concepts.indexed)
      fxExpense(unit, c, 1500000 + (i * 237311) + salt)
  else
    for (var i = 0; i < count; i++)
      fxExpense(unit, 'cost${i.toString().padLeft(3, '0')}', 9000 + i * 1373),
];

List<RevenueCategoryLine> _revenue(ExportWorkloadSize size, int salt) {
  final shape = _shape(size);
  if (size == ExportWorkloadSize.normal) {
    return [
      fxRevenue(fxCcr, 'restaurant', gross: 7645000 + salt, tax: 364048),
      fxRevenue(fxCcr, 'nandbhog', gross: 870000, tax: 41429),
      fxRevenue(fxHki, 'room', gross: 5200000, tax: 247619),
      fxRevenue(
        fxHki,
        'banquet',
        gross: 4034300,
        tax: 0,
        treatment: TaxTreatment.none,
      ),
    ];
  }
  return [
    for (final unit in [fxCcr, fxHki])
      for (var i = 0; i < shape.revenuePerUnit; i++)
        fxRevenue(
          unit,
          'sales${i.toString().padLeft(2, '0')}',
          gross: 2100000 + i * 10500 + salt,
          tax: 100000 + i * 500,
        ),
  ];
}

PnlResult _result(ExportWorkloadSize size, ReportRange range, int salt) {
  final shape = _shape(size);
  return fxResult(
    range: range,
    revenue: _revenue(size, salt),
    expenses: [
      ..._expenses(fxCcr, _ccrCosts, shape.expensePerUnit, salt),
      ..._expenses(fxHki, _hkiCosts, shape.expensePerUnit, salt),
    ],
  );
}

ReportRange _previous(ReportRange current) {
  final days = current.to.differenceInDays(current.from) + 1;
  final to = current.from.addDays(-1);
  return fxRange(to.addDays(-(days - 1)), to);
}

PnlComparison _comparison(
  ExportWorkloadSize size,
  ReportRange current,
  DashboardPeriodKind kind,
) {
  final previous = _previous(current);
  return PnlComparison.compare(
    pair: DashboardPeriodPair.forTesting(
      current: current,
      comparison: previous,
      comparisonCapped: false,
      kind: kind,
    ),
    current: PnlComputed(_result(size, current, 0)),
    previous: PnlComputed(_result(size, previous, -3100)),
  );
}

TrendSeries _trend(ReportRange range, TrendGrain grain, TrendMeasure measure) {
  final buckets = DashboardTrends.buckets(range, grain, measure: measure);
  return DashboardTrends.series(
    measure: measure,
    grain: grain,
    buckets: buckets,
    outcomes: [
      for (final (i, b) in buckets.indexed)
        PnlComputed(
          fxResult(
            range: b.range,
            revenue: [
              fxRevenue(fxCcr, 'restaurant', gross: 250000 + i * 977, tax: 0),
            ],
            expenses: [fxExpense(fxCcr, 'kirana', 180000 + i * 613)],
          ),
        ),
    ],
  );
}

/// One report to export, as a document built from canonical objects.
final class ExportWorkload {
  const ExportWorkload(this.name, this.size, this.report, this._build);

  final String name;
  final ExportWorkloadSize size;
  final ExportReport report;
  final ExportBuild<ExportDocument> Function() _build;

  /// The document-model stage: the export builders over canonical objects.
  ExportDocument build() => switch (_build()) {
    ExportBuilt(:final document) => document,
    ExportNotBuilt(:final reason) => throw StateError('not built: $reason'),
  };
}

/// The four reports at [size].
List<ExportWorkload> exportWorkloads(ExportWorkloadSize size) {
  final shape = _shape(size);
  final month = fxRange(
    BusinessDate.of(2026, 9, 1),
    BusinessDate.of(2026, 9, 30),
  );
  final year = fxRange(
    BusinessDate.of(2026, 4, 1),
    BusinessDate.of(2026 + shape.trendMonths ~/ 12, 4, 1).addDays(-1),
  );
  final kindForYear = shape.trendMonths == 12
      ? DashboardPeriodKind.financialYearToDate
      : DashboardPeriodKind.custom;
  final monthResult = _result(size, month, 0);
  final yearResult = _result(size, year, 0);

  ExportContext context(ExportReport report) => fxContext(
    fxPermit(report, fxBoth),
    freshness: fxFreshness(),
    periodName: report == ExportReport.expenseAnalysis
        ? 'Financial year to date'
        : 'Month to date',
  );

  return [
    ExportWorkload(
      'P&L',
      size,
      ExportReport.profitAndLoss,
      () => ExportDocuments.profitAndLoss(
        context(ExportReport.profitAndLoss),
        monthResult,
      ),
    ),
    ExportWorkload(
      'Revenue Analysis',
      size,
      ExportReport.revenueAnalysis,
      () => ExportDocuments.revenueAnalysis(
        context(ExportReport.revenueAnalysis),
        result: monthResult,
        comparison: _comparison(size, month, DashboardPeriodKind.monthToDate),
        trends: [_trend(month, TrendGrain.daily, TrendMeasure.netSales)],
        revenueMix: TopN.revenueCategories(monthResult, n: 5),
      ),
    ),
    ExportWorkload(
      'Expense Analysis',
      size,
      ExportReport.expenseAnalysis,
      () => ExportDocuments.expenseAnalysis(
        context(ExportReport.expenseAnalysis),
        result: yearResult,
        comparison: _comparison(size, year, kindForYear),
        trends: [_trend(year, TrendGrain.monthly, TrendMeasure.expenses)],
        topExpenseCategories: TopN.expenseCategories(yearResult, n: 5),
        departmentSpending: TopN.departments(yearResult, n: 5),
      ),
    ),
    ExportWorkload(
      'Business Comparison',
      size,
      ExportReport.businessComparison,
      () => ExportDocuments.businessComparison(
        context(ExportReport.businessComparison),
        result: monthResult,
        comparison: _comparison(size, month, DashboardPeriodKind.monthToDate),
        propertyComparison: PropertyComparison.of(monthResult),
      ),
    ),
  ];
}

/// The render stage: the same layout functions the export pipeline calls for [format].
Future<Uint8List> renderExport(
  ExportDocument document,
  ExportFileFormat format,
  ExportPdfFonts fonts, {
  bool compress = true,
}) async => switch ((document, format)) {
  (final PnlExportDocument d, ExportFileFormat.pdf) => await pnlPdf(
    d,
    fonts,
    compress: compress,
  ),
  (final PnlExportDocument d, ExportFileFormat.xlsx) => pnlWorkbook(d).encode(),
  (final RevenueAnalysisExportDocument d, ExportFileFormat.pdf) =>
    await revenueAnalysisPdf(d, fonts, compress: compress),
  (final RevenueAnalysisExportDocument d, ExportFileFormat.xlsx) =>
    revenueAnalysisWorkbook(d).encode(),
  (final ExpenseAnalysisExportDocument d, ExportFileFormat.pdf) =>
    await expenseAnalysisPdf(d, fonts, compress: compress),
  (final ExpenseAnalysisExportDocument d, ExportFileFormat.xlsx) =>
    expenseAnalysisWorkbook(d).encode(),
  (final BusinessComparisonExportDocument d, ExportFileFormat.pdf) =>
    await businessComparisonPdf(d, fonts, compress: compress),
  (final BusinessComparisonExportDocument d, ExportFileFormat.xlsx) =>
    businessComparisonWorkbook(d).encode(),
};

/// One timed export: model, render and write, in microseconds.
final class ExportStageTimes {
  const ExportStageTimes(this.model, this.render, this.write, this.bytes);
  final int model;
  final int render;
  final int write;
  final int bytes;
  int get total => model + render + write;
}

/// Runs one export through its three stages, writing with the production atomic writer.
Future<ExportStageTimes> timeExport(
  ExportWorkload workload,
  ExportFileFormat format,
  ExportPdfFonts fonts,
  Directory into,
) async {
  final watch = Stopwatch()..start();
  final document = workload.build();
  final model = watch.elapsedMicroseconds;

  watch
    ..reset()
    ..start();
  final bytes = await renderExport(document, format, fonts);
  final render = watch.elapsedMicroseconds;

  final path =
      '${into.path}${Platform.pathSeparator}'
      '${workload.name.replaceAll(RegExp('[^A-Za-z]'), '')}.${format.extension}';
  watch
    ..reset()
    ..start();
  final saved = await writeAtomically(path, bytes);
  final write = watch.elapsedMicroseconds;
  if (saved is! ExportSaved) throw StateError('not written: $saved');
  return ExportStageTimes(model, render, write, bytes.length);
}

/// Median, minimum and maximum of [values], in milliseconds to one decimal.
String exportStageSummary(List<int> micros) {
  final sorted = [...micros]..sort();
  String ms(int us) => (us / 1000).toStringAsFixed(1);
  return '${ms(sorted[sorted.length ~/ 2])} '
      '(${ms(sorted.first)}–${ms(sorted.last)})';
}
