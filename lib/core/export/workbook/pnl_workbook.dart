/// The Profit & Loss workbook (Phase 7 Slice 4; D-294, `ARCHITECTURE.md` §51.5).
///
/// It lays out a [PnlExportDocument] as three sheets: **Summary**, **Revenue** and
/// **Expenses**. It places cells and nothing else:
///
/// * Every figure is a `Money` the document copied from the canonical result, written as
///   an exact decimal literal by `MoneyFormatter.decimalLiteral`. Integer formatting only.
/// * Every margin is the screen's own rounded value, as a fraction literal
///   (`MarginRatio.displayedFractionLiteral`), or the text "N/A".
/// * A total under a table is the headline figure the domain computed. It is never a sum
///   of the rows above it, and there are no formulas anywhere (the writer has no formula
///   cell).
/// * Rows are in the document's order, which is the screen's order.
library;

import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/core/export/xlsx/xlsx_writer.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// The workbook for a P&L export.
XlsxWorkbook pnlWorkbook(PnlExportDocument document) {
  final header = document.header;
  return XlsxWorkbook(
    title:
        '$exportProductName · ${exportReportTitle(header.report)} · '
        '${header.scopeLabel}',
    sheets: [
      _summary(document),
      _revenue(document.scopeStatement, header.consolidated),
      _expenses(document.scopeStatement, header.consolidated),
    ],
  );
}

// ── Shared pieces ────────────────────────────────────────────────────────────

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

/// The heading block: scope, period, basis, what is included, and the three freshness
/// statements, each on its own row (§51.6).
List<List<XlsxCell>> exportHeaderRows(ExportHeader header) {
  final f = header.freshness;
  final newer = exportServerNewerLine(f);
  return [
    [
      _text(
        '$exportProductName · ${exportReportTitle(header.report)}',
        XlsxStyle.title,
      ),
    ],
    [],
    [_text('Scope', XlsxStyle.bold), _text(header.scopeLabel)],
    [_text('Period', XlsxStyle.bold), _text(header.periodName)],
    [_text('From', XlsxStyle.bold), _date(header.range.from)],
    [_text('To', XlsxStyle.bold), _date(header.range.to)],
    [_text('Basis', XlsxStyle.bold), _text(exportBasisLine(header.dateBasis))],
    [_text('Includes', XlsxStyle.bold), _text(exportInclusionLine)],
    [_text('Freshness', XlsxStyle.bold), _text(exportSynchronisedLine(f))],
    if (newer != null) [const XlsxCell.blank(), _text(newer, XlsxStyle.bold)],
    [const XlsxCell.blank(), _text(exportGeneratedLine(f), XlsxStyle.caption)],
  ];
}

// ── Summary ──────────────────────────────────────────────────────────────────

XlsxSheet _summary(PnlExportDocument document) {
  final statements = document.statements;
  final operatingLabel = statements.length == 1
      ? exportOperatingLabel(statements.single.operatingProfit)
      : 'Operating Profit / Loss';

  List<XlsxCell> figureRow(
    String label,
    Money Function(PnlExportStatement) figure, {
    bool bold = false,
  }) => [
    _text(label, bold ? XlsxStyle.bold : XlsxStyle.plain),
    for (final s in statements) _money(figure(s), bold: bold),
  ];

  return XlsxSheet(
    name: 'Summary',
    columnWidths: [26, for (final _ in statements) 26],
    rows: [
      ...exportHeaderRows(document.header),
      [],
      [
        _text('', XlsxStyle.header),
        for (final s in statements) _text(s.title, XlsxStyle.header),
      ],
      figureRow(exportGrossSalesLabel, (s) => s.grossSales),
      figureRow(exportGstLabel, (s) => s.gst),
      figureRow(exportNetSalesLabel, (s) => s.netSales, bold: true),
      figureRow(exportExpensesLabel, (s) => s.expenses),
      figureRow(operatingLabel, (s) => s.operatingProfit, bold: true),
      [
        _text('Result', XlsxStyle.bold),
        for (final s in statements)
          _text(exportResultWord(s.operatingProfit), XlsxStyle.bold),
      ],
      [
        _text(exportMarginLabel, XlsxStyle.bold),
        for (final s in statements) _margin(s.margin),
      ],
      [],
      for (final s in statements)
        if (!s.hasTrade)
          [_text('${s.title}: $exportNoTradeLine', XlsxStyle.caption)],
      if (!document.propertySplitShown)
        [_text(exportSplitNotShownLine, XlsxStyle.caption)],
    ],
  );
}

// ── Line sheets ──────────────────────────────────────────────────────────────

XlsxSheet _revenue(PnlExportStatement statement, bool consolidated) {
  final lines = statement.revenueLines;
  if (lines == null) {
    return XlsxSheet(
      name: 'Revenue',
      columnWidths: const [90],
      rows: [
        [_text(exportBreakdownNotShownLine, XlsxStyle.caption)],
      ],
    );
  }
  return XlsxSheet(
    name: 'Revenue',
    columnWidths: [if (consolidated) 26, 30, 12, 18, 16, 18],
    freezeRows: 1,
    autoFilter: (
      firstRow: 0,
      lastRow: lines.length,
      firstColumn: 0,
      lastColumn: consolidated ? 5 : 4,
    ),
    rows: [
      [
        if (consolidated) _text('Property', XlsxStyle.header),
        _text('Revenue category', XlsxStyle.header),
        _text('Treatment', XlsxStyle.header),
        _text('Gross', XlsxStyle.header),
        _text('GST', XlsxStyle.header),
        _text('Net', XlsxStyle.header),
      ],
      for (final line in lines)
        [
          if (consolidated) _text(line.propertyLabel ?? ''),
          _text(line.categoryLabel),
          _text(line.noGst ? exportNoGstLabel : ''),
          _money(line.gross),
          _money(line.gst),
          _money(line.net),
        ],
      [
        _text('Total', XlsxStyle.bold),
        if (consolidated) const XlsxCell.blank(),
        const XlsxCell.blank(),
        _money(statement.grossSales, bold: true),
        _money(statement.gst, bold: true),
        _money(statement.netSales, bold: true),
      ],
    ],
  );
}

XlsxSheet _expenses(PnlExportStatement statement, bool consolidated) {
  final lines = statement.expenseLines;
  if (lines == null) {
    return XlsxSheet(
      name: 'Expenses',
      columnWidths: const [90],
      rows: [
        [_text(exportBreakdownNotShownLine, XlsxStyle.caption)],
      ],
    );
  }
  return XlsxSheet(
    name: 'Expenses',
    columnWidths: [if (consolidated) 26, 24, 24, 28, 18],
    freezeRows: 1,
    autoFilter: (
      firstRow: 0,
      lastRow: lines.length,
      firstColumn: 0,
      lastColumn: consolidated ? 4 : 3,
    ),
    rows: [
      [
        if (consolidated) _text('Property', XlsxStyle.header),
        _text('Department', XlsxStyle.header),
        _text('Section', XlsxStyle.header),
        _text('Expense category', XlsxStyle.header),
        _text('Amount', XlsxStyle.header),
      ],
      for (final line in lines)
        [
          if (consolidated) _text(line.propertyLabel ?? ''),
          _text(line.departmentLabel),
          _text(line.sectionLabel),
          _text(line.categoryLabel),
          _money(line.amount),
        ],
      [
        _text('Total', XlsxStyle.bold),
        if (consolidated) const XlsxCell.blank(),
        const XlsxCell.blank(),
        const XlsxCell.blank(),
        _money(statement.expenses, bold: true),
      ],
    ],
  );
}
