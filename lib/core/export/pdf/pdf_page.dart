/// The page furniture every exported PDF shares (Phase 7 Slices 5 and 9; §51.5).
///
/// One header, one footer, one opening block and one table style, used by the P&L and by
/// the three analysis PDFs — so two PDFs of the same scope and period cannot state their
/// basis, their synchronisation or their generation time differently (D-232's rule, on
/// paper).
///
/// * Every figure is printed by `MoneyFormatter.standard` with Indian grouping. Nothing
///   here works a figure out.
/// * **Money is never shrunk or cut** (D-286). Amount columns take their natural width;
///   the label columns give way and wrap.
/// * Every page carries a header (scope, period, basis) and a footer (page *n* of *N*,
///   the synchronisation statement and the device generation time — never merged).
///   Table headings repeat on each page a table continues onto.
/// * The document carries **no information dictionary**: no author, producer or creation
///   date, so no device detail beyond what the visible header states (§51.8).
library;

import 'dart:typed_data';

import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One exported document, laid out on A4 portrait pages.
///
/// [compress] is on for a real file; a test may turn it off to read the content streams.
Future<Uint8List> exportPdfDocument({
  required ExportHeader header,
  required ExportPdfFonts fonts,
  required List<pw.Widget> body,
  List<String> openingLines = const [],
  bool compress = true,
}) {
  final pdf = pw.Document(
    compress: compress,
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      header: (context) => _pageHeader(header),
      footer: (context) =>
          _pageFooter(header, context.pageNumber, context.pagesCount),
      build: (context) => [..._titleBlock(header, openingLines), ...body],
    ),
  );
  return pdf.save();
}

// ── Styles ───────────────────────────────────────────────────────────────────

const _ink = PdfColor.fromInt(0xFF2B2A28);
const _muted = PdfColor.fromInt(0xFF6B675F);
const _rule = PdfColor.fromInt(0xFFD8D2C4);
const _fill = PdfColor.fromInt(0xFFEFEBE3);

const pdfBody = pw.TextStyle(fontSize: 9, color: _ink);
final pdfBodyBold = pdfBody.copyWith(fontWeight: pw.FontWeight.bold);
const pdfSmall = pw.TextStyle(fontSize: 7.5, color: _muted);
final pdfHeading = pdfBody.copyWith(
  fontSize: 11,
  fontWeight: pw.FontWeight.bold,
);

/// A figure, as the screen prints it.
String pdfMoney(Money m) => MoneyFormatter.standard.format(m);

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
          style: pdfSmall,
        ),
      ),
      pw.Text(
        '${exportRangeLabel(header.range)} · '
        '${exportBasisShort(header.dateBasis)}',
        style: pdfSmall,
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
              pw.Text(exportSynchronisedLine(f), style: pdfSmall),
              pw.Text(exportGeneratedLine(f), style: pdfSmall),
            ],
          ),
        ),
        pw.Text(exportPageLabel(page, pages), style: pdfSmall),
      ],
    ),
  );
}

// ── The opening block ────────────────────────────────────────────────────────

List<pw.Widget> _titleBlock(ExportHeader header, List<String> openingLines) {
  final f = header.freshness;
  final newer = exportServerNewerLine(f);
  return [
    pw.Text(
      exportReportTitle(header.report),
      style: pdfBody.copyWith(fontSize: 18, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 4),
    pw.Text(header.scopeLabel, style: pdfBody.copyWith(fontSize: 12)),
    pw.Text(
      '${header.periodName} · ${exportRangeLabel(header.range)}',
      style: pdfBody,
    ),
    for (final line in openingLines) pw.Text(line, style: pdfBody),
    pw.SizedBox(height: 6),
    pw.Text(exportBasisLine(header.dateBasis), style: pdfSmall),
    pw.Text(exportInclusionLine, style: pdfSmall),
    pw.SizedBox(height: 4),
    pw.Text(exportSynchronisedLine(f), style: pdfSmall),
    if (newer != null) pw.Text(newer, style: pdfBodyBold),
    pw.Text(exportGeneratedLine(f), style: pdfSmall),
    pw.SizedBox(height: 12),
  ];
}

/// A quiet sentence under a table: why something is not shown, or what a line means.
pw.Widget pdfNote(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Text(text, style: pdfSmall),
);

/// A section heading, with the space under it.
List<pw.Widget> pdfSectionHeading(String text) => [
  pw.Text(text, style: pdfHeading),
  pw.SizedBox(height: 4),
];

// ── Tables ───────────────────────────────────────────────────────────────────

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
    style: strong || heading ? pdfBodyBold : pdfBody,
    textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
  ),
);

/// One cell of a [pdfTable] row.
typedef PdfCell = ({String text, bool strong});

PdfCell pdfCell(String text, {bool strong = false}) =>
    (text: text, strong: strong);

/// A table whose heading row repeats on every page it continues onto.
///
/// The first [textColumns] columns are words: they flex and wrap. Every later column is
/// an amount or a short figure: it takes its natural width and is right-aligned, so an
/// amount is never cut.
pw.Widget pdfTable({
  required List<String> headings,
  required int textColumns,
  required List<List<PdfCell>> rows,
}) => pw.Table(
  border: const pw.TableBorder(
    horizontalInside: pw.BorderSide(color: _rule, width: 0.4),
  ),
  columnWidths: {
    for (final (i, _) in headings.indexed)
      i: i < textColumns
          ? const pw.FlexColumnWidth()
          : const pw.IntrinsicColumnWidth(),
  },
  children: [
    pw.TableRow(
      repeat: true,
      children: [
        for (final (i, h) in headings.indexed)
          _cell(h, heading: true, right: i >= textColumns),
      ],
    ),
    for (final row in rows)
      pw.TableRow(
        children: [
          for (final (i, c) in row.indexed)
            _cell(c.text, strong: c.strong, right: i >= textColumns),
        ],
      ),
  ],
);
