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
import 'package:krishna_mis/core/export/pdf/pdf_page.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:pdf/widgets.dart' as pw;

/// The PDF bytes for a P&L export.
///
/// [compress] is on for a real file; a test may turn it off to read the content streams.
Future<Uint8List> pnlPdf(
  PnlExportDocument document,
  ExportPdfFonts fonts, {
  bool compress = true,
}) {
  final header = document.header;
  final scope = document.scopeStatement;
  return exportPdfDocument(
    header: header,
    fonts: fonts,
    compress: compress,
    body: [
      for (final statement in document.statements) _statement(statement),
      if (!document.propertySplitShown) pdfNote(exportSplitNotShownLine),
      ..._revenueLines(scope, header.consolidated),
      ..._expenseLines(scope, header.consolidated),
    ],
  );
}

// ── One statement ────────────────────────────────────────────────────────────

pw.Widget _statement(PnlExportStatement s) {
  pw.TableRow row(String label, String value, {bool strong = false}) =>
      pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(label, style: strong ? pdfBodyBold : pdfBody),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Text(
              value,
              style: strong ? pdfBodyBold : pdfBody,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(s.title, style: pdfHeading),
      pw.SizedBox(height: 4),
      pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(),
          1: pw.IntrinsicColumnWidth(),
        },
        children: [
          row(exportGrossSalesLabel, pdfMoney(s.grossSales)),
          row(exportGstLabel, pdfMoney(s.gst)),
          row(exportNetSalesLabel, pdfMoney(s.netSales), strong: true),
          row(exportExpensesLabel, pdfMoney(s.expenses)),
          row(
            exportOperatingLabel(s.operatingProfit),
            pdfMoney(s.operatingProfit),
            strong: true,
          ),
          row('Result', exportResultWord(s.operatingProfit)),
          row(exportMarginLabel, s.margin.displayTwoDecimals),
        ],
      ),
      if (!s.hasTrade) pdfNote(exportNoTradeLine),
      pw.SizedBox(height: 14),
    ],
  );
}

// ── Line tables ──────────────────────────────────────────────────────────────

List<pw.Widget> _revenueLines(PnlExportStatement s, bool consolidated) {
  final lines = s.revenueLines;
  return [
    ...pdfSectionHeading(exportRevenueLinesHeading),
    if (lines == null)
      pdfNote(exportBreakdownNotShownLine)
    else
      pdfTable(
        headings: [
          if (consolidated) 'Property',
          'Revenue category',
          'Gross',
          'GST',
          'Net',
        ],
        textColumns: consolidated ? 2 : 1,
        rows: [
          for (final l in lines)
            [
              if (consolidated) pdfCell(l.propertyLabel ?? ''),
              pdfCell(
                l.noGst
                    ? '${l.categoryLabel} · $exportNoGstLabel'
                    : l.categoryLabel,
              ),
              pdfCell(pdfMoney(l.gross)),
              pdfCell(pdfMoney(l.gst)),
              pdfCell(pdfMoney(l.net)),
            ],
          // The totals are the headline figures, never a sum of the rows above.
          [
            pdfCell(exportTotalLabel, strong: true),
            if (consolidated) pdfCell(''),
            pdfCell(pdfMoney(s.grossSales), strong: true),
            pdfCell(pdfMoney(s.gst), strong: true),
            pdfCell(pdfMoney(s.netSales), strong: true),
          ],
        ],
      ),
    pw.SizedBox(height: 14),
  ];
}

List<pw.Widget> _expenseLines(PnlExportStatement s, bool consolidated) {
  final lines = s.expenseLines;
  return [
    ...pdfSectionHeading(exportExpenseLinesHeading),
    if (lines == null)
      pdfNote(exportBreakdownNotShownLine)
    else
      pdfTable(
        headings: [
          if (consolidated) 'Property',
          'Department',
          'Section',
          'Expense category',
          'Amount',
        ],
        textColumns: consolidated ? 4 : 3,
        rows: [
          for (final l in lines)
            [
              if (consolidated) pdfCell(l.propertyLabel ?? ''),
              pdfCell(l.departmentLabel),
              pdfCell(l.sectionLabel),
              pdfCell(l.categoryLabel),
              pdfCell(pdfMoney(l.amount)),
            ],
          [
            pdfCell(exportTotalLabel, strong: true),
            pdfCell(''),
            pdfCell(''),
            if (consolidated) pdfCell(''),
            pdfCell(pdfMoney(s.expenses), strong: true),
          ],
        ],
      ),
  ];
}
