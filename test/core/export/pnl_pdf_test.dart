/// The P&L PDF prints the canonical figures, in the screen's words, on every page it needs
/// (Phase 7 Slice 5; D-295, spec §21.3).
///
/// Parity at the page: the text is read back out of the generated PDF through each font's
/// `/ToUnicode` map (`test/support/pdf_text.dart`) and compared with `MoneyFormatter`'s
/// rendering of the canonical `PnlResult`. It is the same string the screen shows.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/core/export/pdf/pnl_pdf.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/export/export_builders.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../support/export_fixtures.dart';
import '../../support/pdf_text.dart';

ByteData _asset(String path) =>
    ByteData.sublistView(File(path).readAsBytesSync());

final _fonts = ExportPdfFonts.fromBytes(
  regular: _asset(exportPdfRegularFontAsset),
  bold: _asset(exportPdfBoldFontAsset),
);

PnlExportDocument _doc(
  PnlResult result,
  ExportScope scope, {
  ReportingFreshness? freshness,
}) => switch (ExportDocuments.profitAndLoss(
  fxContext(
    fxPermit(ExportReport.profitAndLoss, scope),
    freshness: freshness,
    periodName: 'This month',
  ),
  result,
)) {
  ExportBuilt(:final document) => document,
  ExportNotBuilt(:final reason) => throw StateError('not built: $reason'),
};

Future<PdfText> _read(PnlExportDocument doc) async =>
    PdfText.read(await pnlPdf(doc, _fonts, compress: false));

String _m(Money m) => MoneyFormatter.standard.format(m);

/// The lines that begin with [label], in page order.
List<String> _linesStarting(PdfText pdf, String label) =>
    pdf.lines.where((l) => l.startsWith('$label ')).toList();

void main() {
  tzdata.initializeTimeZones();

  group('the bundled fonts', () {
    test('Regular and Bold load and can draw the rupee sign', () {
      expect(_fonts.regular, isNotNull);
      expect(_fonts.bold, isNotNull);
    });

    test('are declared as assets with their licence, and nothing else', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final assets = RegExp(
        r'^    - (assets/\S+)$',
        multiLine: true,
      ).allMatches(pubspec).map((m) => m.group(1)).toList();
      expect(assets, [
        exportPdfRegularFontAsset,
        exportPdfBoldFontAsset,
        'assets/fonts/noto_sans/OFL.txt',
      ]);
      for (final a in assets) {
        expect(File(a!).existsSync(), isTrue, reason: a);
      }
      expect(
        File('assets/fonts/noto_sans/OFL.txt').readAsStringSync(),
        contains('SIL Open Font License, Version 1.1'),
      );
    });

    test('bytes that are not a font are refused', () {
      expect(
        () => ExportPdfFonts.fromBytes(
          regular: ByteData(64),
          bold: _asset(exportPdfBoldFontAsset),
        ),
        throwsA(anything),
      );
    });
  });

  group('one property', () {
    final result = fxCcrSeptember();
    final doc = _doc(result, ExportScope.unit(fxCcr), freshness: fxFreshness());

    test(
      'every headline figure is the canonical one, as the screen prints it',
      () async {
        final pdf = await _read(doc);
        expect(_linesStarting(pdf, exportGrossSalesLabel), [
          '$exportGrossSalesLabel ${_m(result.grossSales)}',
        ]);
        expect(_linesStarting(pdf, exportGstLabel), [
          '$exportGstLabel ${_m(result.gst)}',
        ]);
        expect(_linesStarting(pdf, exportNetSalesLabel), [
          '$exportNetSalesLabel ${_m(result.netSales)}',
        ]);
        expect(_linesStarting(pdf, exportExpensesLabel), [
          '$exportExpensesLabel ${_m(result.expenses)}',
        ]);
        expect(_linesStarting(pdf, 'Operating Profit'), [
          'Operating Profit ${_m(result.operatingProfit)}',
        ]);
        expect(_linesStarting(pdf, 'Result'), ['Result Profit']);
        expect(_linesStarting(pdf, exportMarginLabel), [
          '$exportMarginLabel ${result.margin.displayTwoDecimals}',
        ]);
      },
    );

    test(
      'the opening block states scope, period, basis and freshness',
      () async {
        final text = (await _read(doc)).text;
        expect(text, contains('Crystal Canopy Rooftop'));
        expect(text, contains('This month · 1 Sep 2026 – 19 Sep 2026'));
        expect(text, contains(exportBasisLine(doc.header.dateBasis)));
        expect(text, contains(exportInclusionLine));
        expect(text, contains('Synchronised as of 19 Sep 2026, 11:30 IST'));
        expect(
          text,
          contains(
            'Generated on this device at 19 Sep 2026, 18:00 IST (device clock)',
          ),
        );
        expect(text, isNot(contains('newer changes')));
      },
    );

    test(
      'the category lines, and a Total that is the headline figure',
      () async {
        final pdf = await _read(doc);
        for (final l in doc.scopeStatement.revenueLines!) {
          expect(
            pdf.lines,
            contains(
              '${l.categoryLabel} ${_m(l.gross)} ${_m(l.gst)} ${_m(l.net)}',
            ),
          );
        }
        expect(
          pdf.lines,
          contains(
            '$exportTotalLabel ${_m(result.grossSales)} ${_m(result.gst)} '
            '${_m(result.netSales)}',
          ),
        );
        expect(pdf.lines, contains('$exportTotalLabel ${_m(result.expenses)}'));
      },
    );
  });

  group('both properties', () {
    final result = fxConsolidated();
    final split = PropertyComparison.of(result) as PropertyComparisonReady;
    final doc = _doc(
      result,
      fxBoth,
      freshness: fxFreshness(serverHasNewer: true),
    );

    test(
      'one statement per property, then the total, each canonical',
      () async {
        final pdf = await _read(doc);
        final expected = [for (final p in split.properties) p.result, result];
        expect(_linesStarting(pdf, exportNetSalesLabel), [
          for (final r in expected) '$exportNetSalesLabel ${_m(r.netSales)}',
        ]);
        expect(_linesStarting(pdf, 'Result'), [
          for (final r in expected)
            'Result ${exportResultWord(r.operatingProfit)}',
        ]);
        final titles = pdf.lines.where(
          (l) =>
              l == 'Crystal Canopy Rooftop' ||
              l == 'Hotel Krishna Imperial' ||
              l == 'Both properties (consolidated)',
        );
        expect(titles, [
          'Both properties (consolidated)',
          'Crystal Canopy Rooftop',
          'Hotel Krishna Imperial',
          'Both properties (consolidated)',
        ]);
      },
    );

    test('a loss is printed negative and called a loss', () async {
      final pdf = await _read(doc);
      final hki = split.properties.last.result;
      expect(hki.operatingProfit.isNegative, isTrue);
      expect(_linesStarting(pdf, 'Operating Loss'), [
        'Operating Loss ${_m(hki.operatingProfit)}',
      ]);
      expect(_m(hki.operatingProfit), startsWith('-₹'));
    });

    test('lines name their property, and Banquet says No GST', () async {
      final pdf = await _read(doc);
      for (final l in doc.scopeStatement.revenueLines!) {
        final label = l.noGst
            ? '${l.categoryLabel} · $exportNoGstLabel'
            : l.categoryLabel;
        expect(
          pdf.lines,
          contains(
            '${l.propertyLabel} $label ${_m(l.gross)} ${_m(l.gst)} ${_m(l.net)}',
          ),
        );
      }
      expect(pdf.text, contains('Banquet · No GST'));
    });

    test(
      'the server-newer statement appears because it was confirmed',
      () async {
        expect(
          (await _read(doc)).text,
          contains('The server has newer changes'),
        );
      },
    );

    test('no internal id reaches the page text', () async {
      final text = (await _read(doc)).text;
      for (final forbidden in fxForbidden) {
        expect(text, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('every page', () {
    // Sixty revenue categories: enough to carry a table across pages.
    final many = [
      for (var i = 10; i < 70; i++)
        fxRevenue(fxCcr, 'category$i', gross: 1000000 + i, tax: 47619),
    ];
    final result = fxResult(
      range: fxSeptember,
      businessUnitId: fxCcr,
      revenue: many,
      expenses: [fxExpense(fxCcr, 'kirana', 9420343)],
    );
    final doc = _doc(result, ExportScope.unit(fxCcr), freshness: fxFreshness());

    test('carries the header, the footer and its page number', () async {
      final pdf = await _read(doc);
      expect(pdf.pages.length, greaterThan(1));
      for (final (i, page) in pdf.pages.indexed) {
        expect(
          page.lines.first,
          'Krishna Imperial MIS · Profit & Loss · Crystal Canopy Rooftop '
          '1 Sep 2026 – 19 Sep 2026 · Accrual · P&L date',
        );
        expect(page.text, contains(exportPageLabel(i + 1, pdf.pages.length)));
        expect(
          page.text,
          contains('Synchronised as of 19 Sep 2026, 11:30 IST'),
        );
        expect(page.text, contains('Generated on this device at'));
      }
    });

    test(
      'repeats a table heading on each page the table continues onto',
      () async {
        final pdf = await _read(doc);
        final withLines = pdf.pages.where(
          (p) => p.lines.any((l) => l.startsWith('Category')),
        );
        expect(withLines.length, greaterThan(1));
        for (final page in withLines) {
          expect(page.lines, contains('Revenue category Gross GST Net'));
        }
        // Every line is printed once, in the document's order.
        final printed = pdf.lines
            .where((l) => l.startsWith('Category'))
            .toList();
        expect(printed, hasLength(many.length));
      },
    );
  });

  group('money is never shrunk or cut', () {
    test('a large amount prints whole, on the line with its label', () async {
      final result = fxResult(
        range: fxSeptember,
        businessUnitId: fxCcr,
        revenue: [
          fxRevenue(
            fxCcr,
            'restaurant',
            gross: 999999999999999,
            tax: 47619047619047,
          ),
        ],
        expenses: const [],
      );
      final doc = _doc(result, ExportScope.unit(fxCcr));
      final pdf = await _read(doc);
      final gross = _m(result.grossSales);
      expect(gross, '₹99,99,99,99,99,999.99');
      expect(pdf.lines, contains('$exportGrossSalesLabel $gross'));
      expect(pdf.lines.where((l) => l.contains(gross)), hasLength(3));
    });

    test('nothing is set smaller than the footer size', () async {
      final bytes = await pnlPdf(
        _doc(fxConsolidated(), fxBoth),
        _fonts,
        compress: false,
      );
      final sizes = RegExp(
        r'/F\d+ ([\d.]+) Tf',
      ).allMatches(latin1.decode(bytes)).map((m) => m.group(1)).toSet();
      expect(sizes, isNotEmpty);
      expect(sizes.difference({'7.5', '9', '11', '12', '18'}), isEmpty);
    });
  });

  group('refusals stay refusals', () {
    test('no freshness evidence: no time is claimed', () async {
      final text = (await _read(
        _doc(fxCcrSeptember(), ExportScope.unit(fxCcr)),
      )).text;
      expect(text, contains('No synchronisation time is stated'));
      expect(text, isNot(contains('Synchronised as of')));
      expect(text, contains('Generated on this device'));
    });

    test(
      'a breakdown that does not reconcile is withheld, and says so',
      () async {
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
        final pdf = await _read(_doc(result, fxBoth));
        expect(
          pdf.text.replaceAll('\n', ' '),
          contains(exportBreakdownNotShownLine),
        );
        expect(pdf.text, isNot(contains('Revenue category Gross GST Net')));
        expect(
          pdf.text.replaceAll('\n', ' '),
          contains(exportSplitNotShownLine),
        );
        expect(_linesStarting(pdf, exportGrossSalesLabel), [
          '$exportGrossSalesLabel ${_m(result.grossSales)}',
        ]);
      },
    );

    test(
      'zero net sales: the margin is N/A, and a real ₹0 is printed',
      () async {
        final result = fxResult(
          range: fxSeptember,
          businessUnitId: fxCcr,
          revenue: const [],
          expenses: const [],
        );
        final pdf = await _read(_doc(result, ExportScope.unit(fxCcr)));
        expect(_linesStarting(pdf, exportMarginLabel), [
          '$exportMarginLabel $exportNotApplicable',
        ]);
        expect(_linesStarting(pdf, exportNetSalesLabel), [
          '$exportNetSalesLabel ₹0.00',
        ]);
        expect(_linesStarting(pdf, 'Result'), ['Result Break-even']);
        expect(pdf.text, contains(exportNoTradeLine));
      },
    );
  });

  group('the file itself', () {
    test(
      'is a PDF, compressed by default, with no information dictionary',
      () async {
        final bytes = await pnlPdf(_doc(fxConsolidated(), fxBoth), _fonts);
        final raw = latin1.decode(bytes);
        expect(raw, startsWith('%PDF-'));
        expect(raw.trimRight(), endsWith('%%EOF'));
        expect(raw, contains('/FlateDecode'));
        for (final absent in [
          '/Info',
          '/Author',
          '/Producer',
          '/Creator',
          '/CreationDate',
          '/Title',
        ]) {
          expect(raw, isNot(contains(absent)), reason: absent);
        }
        expect(() => PdfText.read(bytes), throwsStateError);
      },
    );

    test('no internal id appears in any byte, compressed or not', () async {
      final doc = _doc(fxConsolidated(), fxBoth, freshness: fxFreshness());
      for (final compress in [true, false]) {
        final raw = latin1.decode(
          await pnlPdf(doc, _fonts, compress: compress),
        );
        for (final forbidden in fxForbidden) {
          expect(raw, isNot(contains(forbidden)), reason: forbidden);
        }
      }
    });
  });
}
