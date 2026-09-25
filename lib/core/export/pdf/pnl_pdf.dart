/// The Profit & Loss PDF (Phase 7 Slice 5; D-295, `ARCHITECTURE.md` §51.5).
///
/// It lays out a [PnlExportDocument] on A4 portrait pages and does nothing else:
///
/// * Every figure is a `Money` the document copied from the canonical result, printed by
///   `MoneyFormatter.standard` with Indian grouping. No figure is worked out here, and a
///   total under a table is the headline figure, never a sum of the rows.
/// * **Money is never shrunk or cut** (D-286, on paper as on screen). Amount columns take
///   their natural width; the label columns give way and wrap.
/// * Every page carries a header (scope, period, basis) and a footer (page *n* of *N*, the
///   synchronisation statement and the generation time). Table headings repeat on each
///   page a table continues onto.
/// * The fonts are handed in (`ExportPdfFonts`). Nothing is loaded or fetched here.
/// * The PDF carries **no document-information dictionary**: no author, producer or
///   creation date, so no device detail beyond what the visible header states (§51.8).
///
/// The same bytes are what Windows prints and what Android shares (§51.5).
library;

import 'dart:typed_data';

import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The PDF bytes for a P&L export.
///
/// [compress] is on for a real file; a test may turn it off to read the content streams.
Future<Uint8List> pnlPdf(
  PnlExportDocument document,
  ExportPdfFonts fonts, {
  bool compress = true,
}) {
  final pdf = pw.Document(
    compress: compress,
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );
  final header = document.header;
  final scope = document.scopeStatement;

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      header: (context) => _pageHeader(header),
      footer: (context) =>
          _pageFooter(header, context.pageNumber, context.pagesCount),
      build: (context) => [
        ..._titleBlock(header),
        for (final statement in document.statements) _statement(statement),
        if (!document.propertySplitShown) _note(exportSplitNotShownLine),
        ..._revenueLines(scope, header.consolidated),
        ..._expenseLines(scope, header.consolidated),
      ],
    ),
  );
  return pdf.save();
}

// ── Styles ───────────────────────────────────────────────────────────────────

const _ink = PdfColor.fromInt(0xFF2B2A28);
const _muted = PdfColor.fromInt(0xFF6B675F);
const _rule = PdfColor.fromInt(0xFFD8D2C4);
const _fill = PdfColor.fromInt(0xFFEFEBE3);

const _body = pw.TextStyle(fontSize: 9, color: _ink);
final _bodyBold = _body.copyWith(fontWeight: pw.FontWeight.bold);
const _small = pw.TextStyle(fontSize: 7.5, color: _muted);
final _heading = _body.copyWith(fontSize: 11, fontWeight: pw.FontWeight.bold);

String _money(Money m) => MoneyFormatter.standard.format(m);

// ── Page furniture ───────────────────────────────────────────────────────────

pw.Widget _pageHeader(ExportHeader header) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 10),
  padding: const pw.EdgeInsets.only(bottom: 4),
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.5)),
  ),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Text(
          '$exportProductName · ${exportReportTitle(header.report)} · '
          '${header.scopeLabel}',
          style: _small,
        ),
      ),
      pw.Text(
        '${exportRangeLabel(header.range)} · '
        '${exportBasisShort(header.dateBasis)}',
        style: _small,
      ),
    ],
  ),
);

pw.Widget _pageFooter(ExportHeader header, int page, int pages) {
  final f = header.freshness;
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 10),
    padding: const pw.EdgeInsets.only(top: 4),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.5)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(exportSynchronisedLine(f), style: _small),
              pw.Text(exportGeneratedLine(f), style: _small),
            ],
          ),
        ),
        pw.Text(exportPageLabel(page, pages), style: _small),
      ],
    ),
  );
}

// ── The opening block ────────────────────────────────────────────────────────

List<pw.Widget> _titleBlock(ExportHeader header) {
  final f = header.freshness;
  final newer = exportServerNewerLine(f);
  return [
    pw.Text(
      exportReportTitle(header.report),
      style: _body.copyWith(fontSize: 18, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 4),
    pw.Text(header.scopeLabel, style: _body.copyWith(fontSize: 12)),
    pw.Text(
      '${header.periodName} · ${exportRangeLabel(header.range)}',
      style: _body,
    ),
    pw.SizedBox(height: 6),
    pw.Text(exportBasisLine(header.dateBasis), style: _small),
    pw.Text(exportInclusionLine, style: _small),
    pw.SizedBox(height: 4),
    pw.Text(exportSynchronisedLine(f), style: _small),
    if (newer != null) pw.Text(newer, style: _bodyBold),
    pw.Text(exportGeneratedLine(f), style: _small),
    pw.SizedBox(height: 12),
  ];
}

pw.Widget _note(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Text(text, style: _small),
);

// ── One statement ────────────────────────────────────────────────────────────

pw.Widget _statement(PnlExportStatement s) {
  pw.TableRow row(String label, String value, {bool strong = false}) =>
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(label, style: strong ? _bodyBold : _body),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(
              value,
              style: strong ? _bodyBold : _body,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(s.title, style: _heading),
      pw.SizedBox(height: 4),
      pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(),
          1: pw.IntrinsicColumnWidth(),
        },
        children: [
          row(exportGrossSalesLabel, _money(s.grossSales)),
          row(exportGstLabel, _money(s.gst)),
          row(exportNetSalesLabel, _money(s.netSales), strong: true),
          row(exportExpensesLabel, _money(s.expenses)),
          row(
            exportOperatingLabel(s.operatingProfit),
            _money(s.operatingProfit),
            strong: true,
          ),
          row('Result', exportResultWord(s.operatingProfit)),
          row(exportMarginLabel, s.margin.displayTwoDecimals),
        ],
      ),
      if (!s.hasTrade) _note(exportNoTradeLine),
      pw.SizedBox(height: 14),
    ],
  );
}

// ── Line tables ──────────────────────────────────────────────────────────────

pw.Widget _cell(
  String text, {
  bool strong = false,
  bool right = false,
  bool heading = false,
}) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
  color: heading ? _fill : null,
  child: pw.Text(
    text,
    style: strong || heading ? _bodyBold : _body,
    textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
  ),
);

/// A table whose heading row repeats on every page it continues onto. Text columns flex
/// and wrap; amount columns take their natural width, so an amount is never cut.
pw.Widget _lineTable({
  required List<String> textHeadings,
  required List<String> moneyHeadings,
  required List<(List<String>, List<Money>)> rows,
  required List<Money> totals,
}) {
  final isAmount = [
    for (final _ in textHeadings) false,
    for (final _ in moneyHeadings) true,
  ];
  return pw.Table(
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _rule, width: 0.4),
    ),
    columnWidths: {
      for (final (i, amount) in isAmount.indexed)
        i: amount
            ? const pw.IntrinsicColumnWidth()
            : const pw.FlexColumnWidth(),
    },
    children: [
      pw.TableRow(
        repeat: true,
        children: [
          for (final h in textHeadings) _cell(h, heading: true),
          for (final h in moneyHeadings) _cell(h, heading: true, right: true),
        ],
      ),
      for (final (texts, amounts) in rows)
        pw.TableRow(
          children: [
            for (final t in texts) _cell(t),
            for (final a in amounts) _cell(_money(a), right: true),
          ],
        ),
      pw.TableRow(
        children: [
          for (final (i, _) in textHeadings.indexed)
            _cell(i == 0 ? exportTotalLabel : '', strong: true),
          for (final a in totals) _cell(_money(a), strong: true, right: true),
        ],
      ),
    ],
  );
}

List<pw.Widget> _revenueLines(PnlExportStatement s, bool consolidated) {
  final lines = s.revenueLines;
  return [
    pw.Text(exportRevenueLinesHeading, style: _heading),
    pw.SizedBox(height: 4),
    if (lines == null)
      _note(exportBreakdownNotShownLine)
    else
      _lineTable(
        textHeadings: [if (consolidated) 'Property', 'Revenue category'],
        moneyHeadings: const ['Gross', 'GST', 'Net'],
        rows: [
          for (final l in lines)
            (
              [
                if (consolidated) l.propertyLabel ?? '',
                l.noGst
                    ? '${l.categoryLabel} · $exportNoGstLabel'
                    : l.categoryLabel,
              ],
              [l.gross, l.gst, l.net],
            ),
        ],
        totals: [s.grossSales, s.gst, s.netSales],
      ),
    pw.SizedBox(height: 14),
  ];
}

List<pw.Widget> _expenseLines(PnlExportStatement s, bool consolidated) {
  final lines = s.expenseLines;
  return [
    pw.Text(exportExpenseLinesHeading, style: _heading),
    pw.SizedBox(height: 4),
    if (lines == null)
      _note(exportBreakdownNotShownLine)
    else
      _lineTable(
        textHeadings: [
          if (consolidated) 'Property',
          'Department',
          'Section',
          'Expense category',
        ],
        moneyHeadings: const ['Amount'],
        rows: [
          for (final l in lines)
            (
              [
                if (consolidated) l.propertyLabel ?? '',
                l.departmentLabel,
                l.sectionLabel,
                l.categoryLabel,
              ],
              [l.amount],
            ),
        ],
        totals: [s.expenses],
      ),
  ];
}
