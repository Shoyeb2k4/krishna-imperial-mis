/// The three analysis PDFs (Phase 7 Slice 9; D-290, `ARCHITECTURE.md` §51.5).
///
/// Revenue Analysis, Expense & Department Analysis and Business Comparison, each laid out
/// from its Slice 3 document model and nothing else:
///
/// * Every figure is a `Money` the document carried from the canonical result, printed by
///   `MoneyFormatter`. A movement is the domain's own `change`; a percentage is the
///   domain's own rounded text, or "N/A" with the reason. Nothing is worked out here.
/// * A comparison that could not be made says so in words. It is never ₹0 (D-163).
/// * A trend point whose figure could not be established is a gap, stated as one, never
///   zero; a clipped first or last point says it is partial (D-263).
/// * A ranked set prints the domain's lines in the domain's order, then the domain's exact
///   Others, then the total the set reconciled to (D-258). A set that did not reconcile
///   prints no line at all.
/// * Business Comparison lists the properties in the domain's fixed order, then both
///   together, each result stated in words beside its sign (D-278, spec §20).
///
/// Page furniture, fonts and the absence of an information dictionary are the shared
/// `pdf_page.dart`'s, so these PDFs and the P&L PDF state basis, synchronisation and
/// generation time identically. A4 portrait: the widest table has four amount columns,
/// which fit beside a wrapping label at their natural width.
library;

import 'dart:typed_data';

import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/core/export/pdf/pdf_page.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:pdf/widgets.dart' as pw;

/// The PDF bytes for a Revenue Analysis export.
Future<Uint8List> revenueAnalysisPdf(
  RevenueAnalysisExportDocument document,
  ExportPdfFonts fonts, {
  bool compress = true,
}) => exportPdfDocument(
  header: document.header,
  fonts: fonts,
  compress: compress,
  openingLines: _comparedLines(document.pair),
  body: [
    ..._comparedFigures([
      (exportGrossSalesLabel, document.grossSales, false),
      (exportGstLabel, document.gst, false),
      (exportNetSalesLabel, document.netSales, true),
    ]),
    ..._trend(
      document.netSalesTrend,
      absent: exportNoNetSalesTrendLine(document.pair.kind),
    ),
    ..._ranking(
      exportRevenueMixHeading,
      exportCategoryColumnLabel,
      exportNetSalesLabel,
      document.revenueMix,
    ),
  ],
);

/// The PDF bytes for an Expense & Department Analysis export.
Future<Uint8List> expenseAnalysisPdf(
  ExpenseAnalysisExportDocument document,
  ExportPdfFonts fonts, {
  bool compress = true,
}) => exportPdfDocument(
  header: document.header,
  fonts: fonts,
  compress: compress,
  openingLines: _comparedLines(document.pair),
  body: [
    ..._comparedFigures([
      (exportOperatingExpensesLabel, document.expenses, true),
    ]),
    ..._trend(
      document.monthlyExpenseTrend,
      absent: exportNoExpenseTrendLine(document.pair.kind),
    ),
    ..._ranking(
      exportTopExpenseCategoriesHeading,
      exportCategoryColumnLabel,
      exportAmountLabel,
      document.topExpenseCategories,
    ),
    ..._ranking(
      exportDepartmentSpendingHeading,
      exportDepartmentColumnLabel,
      exportAmountLabel,
      document.departmentSpending,
    ),
  ],
);

/// The PDF bytes for a Business Comparison export.
Future<Uint8List> businessComparisonPdf(
  BusinessComparisonExportDocument document,
  ExportPdfFonts fonts, {
  bool compress = true,
}) {
  final columns = document.columns;
  List<PdfCell> figureRow(String label, List<String> values, {bool? strong}) =>
      [
        pdfCell(label, strong: strong ?? false),
        for (final v in values) pdfCell(v, strong: strong ?? false),
      ];
  return exportPdfDocument(
    header: document.header,
    fonts: fonts,
    compress: compress,
    body: [
      pdfTable(
        headings: [exportFigureColumnLabel, for (final c in columns) c.label],
        textColumns: 1,
        rows: [
          figureRow(exportNetSalesLabel, [
            for (final c in columns) pdfMoney(c.netSales),
          ], strong: true),
          figureRow(exportOperatingExpensesLabel, [
            for (final c in columns) pdfMoney(c.expenses),
          ]),
          figureRow(exportOperatingProfitOrLossLabel, [
            for (final c in columns) pdfMoney(c.operatingProfit),
          ], strong: true),
          figureRow(exportResultLabel, [
            for (final c in columns) exportResultWord(c.operatingProfit),
          ]),
          figureRow(exportMarginLabel, [
            for (final c in columns) c.margin.displayTwoDecimals,
          ]),
        ],
      ),
      pw.SizedBox(height: 8),
      pdfNote(exportComparisonOrderNote),
    ],
  );
}

// ── Shared pieces ────────────────────────────────────────────────────────────

List<String> _comparedLines(DashboardPeriodPair pair) => [
  exportComparedWithLine(pair),
  ?exportCapNote(pair),
];

/// Each figure beside the same stretch before: this period, the previous period, the
/// domain's movement, and its percentage — or the sentence saying why there is none.
List<pw.Widget> _comparedFigures(
  List<(String, ExportComparedFigure, bool)> figures,
) {
  final notes = <String>[];
  final rows = <List<PdfCell>>[];
  for (final (label, figure, strong) in figures) {
    switch (figure.comparison) {
      case final MoneyComparisonAvailable c:
        rows.add([
          pdfCell(label, strong: strong),
          pdfCell(pdfMoney(figure.current), strong: strong),
          pdfCell(pdfMoney(c.previous)),
          pdfCell(exportChangeText(c)),
          pdfCell(exportPercentText(c)),
        ]);
        final note = exportPercentNote(c);
        if (note != null) notes.add('$label: $note');
      case MoneyComparisonUnavailable(:final side):
        rows.add([
          pdfCell(label, strong: strong),
          pdfCell(pdfMoney(figure.current), strong: strong),
          pdfCell(exportNotAvailable),
          pdfCell(exportNotAvailable),
          pdfCell(exportNotAvailable),
        ]);
        notes.add('$label: ${exportNoComparisonLine(side)}');
    }
  }
  return [
    ...pdfSectionHeading(exportComparedFiguresHeading),
    pdfTable(
      headings: const [
        exportFigureColumnLabel,
        exportThisPeriodLabel,
        exportPreviousPeriodLabel,
        exportChangeLabel,
        exportChangePercentLabel,
      ],
      textColumns: 1,
      rows: rows,
    ),
    pw.SizedBox(height: 6),
    for (final n in notes) pdfNote(n),
    pw.SizedBox(height: 8),
  ];
}

/// A trend, one row per point, in the domain's order. A gap is stated, never zero.
List<pw.Widget> _trend(TrendSeries? series, {required String absent}) {
  if (series == null) {
    return [...pdfSectionHeading(exportTrendHeading), pdfNote(absent)];
  }
  return [
    ...pdfSectionHeading('$exportTrendHeading · ${exportTrendTitle(series)}'),
    pdfTable(
      headings: [
        exportPeriodColumnLabel,
        exportNoteLabel,
        exportMeasureLabel(series.measure),
      ],
      textColumns: 2,
      rows: [
        for (final point in series.points)
          switch (point) {
            TrendValue(:final bucket, :final amount) => [
              pdfCell(exportBucketLabel(bucket, series.grain)),
              pdfCell(bucket.partial ? exportPartialPeriodNote : ''),
              pdfCell(pdfMoney(amount)),
            ],
            TrendGap(:final bucket) => [
              pdfCell(exportBucketLabel(bucket, series.grain)),
              pdfCell(exportTrendGapNote),
              pdfCell(exportNotAvailable),
            ],
          },
      ],
    ),
    pw.SizedBox(height: 14),
  ];
}

/// A ranked set as the domain grouped it: its lines, its exact Others, its total.
List<pw.Widget> _ranking(
  String heading,
  String column,
  String amount,
  ExportRanking? ranking,
) => [
  ...pdfSectionHeading(heading),
  switch (ranking) {
    null => pdfNote(exportNotAvailable),
    ExportRankingRefused(:final reason) => pdfNote(
      exportRankingRefusedLine(reason),
    ),
    ExportRankingGrouped(:final rows, :final others, :final othersCount) =>
      pdfTable(
        headings: [column, amount],
        textColumns: 1,
        rows: [
          for (final r in rows) [pdfCell(r.label), pdfCell(pdfMoney(r.amount))],
          if (others != null)
            [
              pdfCell(exportOthersLabel(othersCount)),
              pdfCell(pdfMoney(others)),
            ],
          // The headline figure the set reconciled to — never a sum of the rows above.
          [
            pdfCell(exportTotalLabel, strong: true),
            pdfCell(pdfMoney(ranking.total), strong: true),
          ],
        ],
      ),
  },
  pw.SizedBox(height: 14),
];
