/// The three analysis workbooks (Phase 7 Slice 9; D-290, `ARCHITECTURE.md` §51.5).
///
/// Revenue Analysis, Expense & Department Analysis and Business Comparison, each laid out
/// from its Slice 3 document model. Cells are placed and nothing else:
///
/// * Every figure is a `Money` the document carried, written as an exact decimal literal
///   by `MoneyFormatter.decimalLiteral`. A movement is the domain's own `change`. A
///   percentage change is the domain's own rounded text, or "N/A" with its reason — it is
///   not re-derived as a number here.
/// * Every margin is the screen's own rounded value (`displayedFractionLiteral`), or the
///   text "N/A".
/// * A total is the headline figure the domain computed, never a sum of rows. There are
///   no formulas anywhere (the writer has no formula cell), and no raw paise column.
/// * A comparison that could not be made, and a trend point with no figure, are stated in
///   words. Neither is ever a zero cell (D-163, D-263).
/// * Every workbook opens with the heading block the P&L uses: scope, period, basis, what
///   is included, and the three freshness statements on their own rows (§51.6).
library;

import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/core/export/workbook/pnl_workbook.dart'
    show exportHeaderRows;
import 'package:krishna_mis/core/export/xlsx/xlsx_writer.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// The workbook for a Revenue Analysis export.
XlsxWorkbook revenueAnalysisWorkbook(RevenueAnalysisExportDocument document) =>
    XlsxWorkbook(
      title: _title(document.header),
      sheets: [
        _summary(document.header, document.pair, [
          (exportGrossSalesLabel, document.grossSales, false),
          (exportGstLabel, document.gst, false),
          (exportNetSalesLabel, document.netSales, true),
        ]),
        _trend(
          document.netSalesTrend,
          absent: exportNoNetSalesTrendLine(document.pair.kind),
        ),
        _ranking(
          'Revenue mix',
          exportRevenueMixHeading,
          exportCategoryColumnLabel,
          exportNetSalesLabel,
          document.revenueMix,
        ),
      ],
    );

/// The workbook for an Expense & Department Analysis export.
XlsxWorkbook expenseAnalysisWorkbook(ExpenseAnalysisExportDocument document) =>
    XlsxWorkbook(
      title: _title(document.header),
      sheets: [
        _summary(document.header, document.pair, [
          (exportOperatingExpensesLabel, document.expenses, true),
        ]),
        _trend(
          document.monthlyExpenseTrend,
          absent: exportNoExpenseTrendLine(document.pair.kind),
        ),
        _ranking(
          'Top categories',
          exportTopExpenseCategoriesHeading,
          exportCategoryColumnLabel,
          exportAmountLabel,
          document.topExpenseCategories,
        ),
        _ranking(
          'Departments',
          exportDepartmentSpendingHeading,
          exportDepartmentColumnLabel,
          exportAmountLabel,
          document.departmentSpending,
        ),
      ],
    );

/// The workbook for a Business Comparison export: one sheet, the properties in the
/// domain's fixed order and then both together.
XlsxWorkbook businessComparisonWorkbook(
  BusinessComparisonExportDocument document,
) {
  final columns = document.columns;
  List<XlsxCell> figureRow(
    String label,
    Money Function(BusinessComparisonExportColumn) figure, {
    bool bold = false,
  }) => [
    _text(label, bold ? XlsxStyle.bold : XlsxStyle.plain),
    for (final c in columns) _money(figure(c), bold: bold),
  ];

  return XlsxWorkbook(
    title: _title(document.header),
    sheets: [
      XlsxSheet(
        name: 'Comparison',
        columnWidths: [28, for (final _ in columns) 30],
        rows: [
          ...exportHeaderRows(document.header),
          [],
          [
            _text(exportFigureColumnLabel, XlsxStyle.header),
            for (final c in columns) _text(c.label, XlsxStyle.header),
          ],
          figureRow(exportNetSalesLabel, (c) => c.netSales, bold: true),
          figureRow(exportOperatingExpensesLabel, (c) => c.expenses),
          figureRow(
            exportOperatingProfitOrLossLabel,
            (c) => c.operatingProfit,
            bold: true,
          ),
          [
            _text(exportResultLabel, XlsxStyle.bold),
            for (final c in columns)
              _text(exportResultWord(c.operatingProfit), XlsxStyle.bold),
          ],
          [
            _text(exportMarginLabel, XlsxStyle.bold),
            for (final c in columns) _margin(c.margin),
          ],
          [],
          [_text(exportComparisonOrderNote, XlsxStyle.caption)],
        ],
      ),
    ],
  );
}

// ── Shared pieces ────────────────────────────────────────────────────────────

String _title(ExportHeader header) =>
    '$exportProductName · ${exportReportTitle(header.report)} · '
    '${header.scopeLabel}';

XlsxCell _money(Money m, {bool bold = false}) => XlsxCell.number(
  MoneyFormatter.decimalLiteral(m),
  style: bold ? XlsxStyle.moneyBold : XlsxStyle.money,
);

XlsxCell _margin(OperatingMargin margin) => switch (margin) {
  MarginRatio() => XlsxCell.number(
    margin.displayedFractionLiteral,
    style: XlsxStyle.percentBold,
  ),
  MarginNotApplicable() => const XlsxCell.text(
    exportNotApplicable,
    style: XlsxStyle.bold,
  ),
};

XlsxCell _date(BusinessDate d) => XlsxCell.date(d.year, d.month, d.day);

XlsxCell _text(String s, [XlsxStyle style = XlsxStyle.plain]) =>
    XlsxCell.text(s, style: style);

/// The heading block, then the comparison period, then each figure beside the same
/// stretch before.
XlsxSheet _summary(
  ExportHeader header,
  DashboardPeriodPair pair,
  List<(String, ExportComparedFigure, bool)> figures,
) {
  final cap = exportCapNote(pair);
  return XlsxSheet(
    name: 'Summary',
    columnWidths: const [26, 20, 20, 20, 14, 60],
    rows: [
      ...exportHeaderRows(header),
      [_text('Compared from', XlsxStyle.bold), _date(pair.comparison.from)],
      [_text('Compared to', XlsxStyle.bold), _date(pair.comparison.to)],
      if (cap != null) [const XlsxCell.blank(), _text(cap, XlsxStyle.caption)],
      [],
      [
        _text(exportFigureColumnLabel, XlsxStyle.header),
        _text(exportThisPeriodLabel, XlsxStyle.header),
        _text(exportPreviousPeriodLabel, XlsxStyle.header),
        _text(exportChangeLabel, XlsxStyle.header),
        _text(exportChangePercentLabel, XlsxStyle.header),
        _text(exportNoteLabel, XlsxStyle.header),
      ],
      for (final (label, figure, bold) in figures)
        switch (figure.comparison) {
          final MoneyComparisonAvailable c => [
            _text(label, bold ? XlsxStyle.bold : XlsxStyle.plain),
            _money(figure.current, bold: bold),
            _money(c.previous),
            _money(c.change),
            _text(exportPercentText(c)),
            _text(exportPercentNote(c) ?? '', XlsxStyle.caption),
          ],
          MoneyComparisonUnavailable(:final side) => [
            _text(label, bold ? XlsxStyle.bold : XlsxStyle.plain),
            _money(figure.current, bold: bold),
            _text(exportNotAvailable),
            _text(exportNotAvailable),
            _text(exportNotAvailable),
            _text(exportNoComparisonLine(side), XlsxStyle.caption),
          ],
        },
    ],
  );
}

/// A trend, one row per point in the domain's order: its label, its dates, its figure —
/// or, for a gap, the words "Not available" and why. Never a zero cell.
XlsxSheet _trend(TrendSeries? series, {required String absent}) {
  if (series == null) {
    return XlsxSheet(
      name: 'Trend',
      columnWidths: const [100],
      rows: [
        [_text(absent, XlsxStyle.caption)],
      ],
    );
  }
  // The measure and grain head the one column that holds them, so the table starts on
  // the first row and its filter needs no arithmetic.
  return XlsxSheet(
    name: 'Trend',
    columnWidths: const [18, 14, 14, 22, 60],
    freezeRows: 1,
    autoFilter: (
      firstRow: 0,
      lastRow: series.points.length,
      firstColumn: 0,
      lastColumn: 4,
    ),
    rows: [
      [
        _text(exportPeriodColumnLabel, XlsxStyle.header),
        _text('From', XlsxStyle.header),
        _text('To', XlsxStyle.header),
        _text(exportTrendTitle(series), XlsxStyle.header),
        _text(exportNoteLabel, XlsxStyle.header),
      ],
      for (final point in series.points)
        switch (point) {
          TrendValue(:final bucket, :final amount) => [
            _text(exportBucketLabel(bucket, series.grain)),
            _date(bucket.range.from),
            _date(bucket.range.to),
            _money(amount),
            _text(
              bucket.partial ? exportPartialPeriodNote : '',
              XlsxStyle.caption,
            ),
          ],
          TrendGap(:final bucket) => [
            _text(exportBucketLabel(bucket, series.grain)),
            _date(bucket.range.from),
            _date(bucket.range.to),
            _text(exportNotAvailable),
            _text(exportTrendGapNote, XlsxStyle.caption),
          ],
        },
    ],
  );
}

/// A ranked set as the domain grouped it: its lines, its exact Others, its total.
XlsxSheet _ranking(
  String sheetName,
  String heading,
  String column,
  String amount,
  ExportRanking? ranking,
) => switch (ranking) {
  null => XlsxSheet(
    name: sheetName,
    columnWidths: const [90],
    rows: [
      [_text(heading, XlsxStyle.title)],
      [_text(exportNotAvailable, XlsxStyle.caption)],
    ],
  ),
  ExportRankingRefused(:final reason) => XlsxSheet(
    name: sheetName,
    columnWidths: const [90],
    rows: [
      [_text(heading, XlsxStyle.title)],
      [_text(exportRankingRefusedLine(reason), XlsxStyle.caption)],
    ],
  ),
  ExportRankingGrouped(:final rows, :final others, :final othersCount) => XlsxSheet(
    name: sheetName,
    columnWidths: const [48, 22],
    freezeRows: 1,
    // The filter covers the ranked lines only; Others and the total stay below it.
    autoFilter: (
      firstRow: 0,
      lastRow: rows.length,
      firstColumn: 0,
      lastColumn: 1,
    ),
    rows: [
      [_text(column, XlsxStyle.header), _text(amount, XlsxStyle.header)],
      for (final r in rows) [_text(r.label), _money(r.amount)],
      if (others != null)
        [_text(exportOthersLabel(othersCount)), _money(others)],
      // The headline figure the set reconciled to — never a sum of the rows above.
      [
        _text(exportTotalLabel, XlsxStyle.bold),
        _money(ranking.total, bold: true),
      ],
    ],
  ),
};
