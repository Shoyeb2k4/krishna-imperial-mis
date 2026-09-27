/// The acceptance helper that reads a saved, compressed PDF (Phase 7 Slice 10) must read
/// exactly what the uncompressed render of the same document says — otherwise a parity
/// check made through it proves nothing.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/core/export/pdf/pnl_pdf.dart';
import 'package:krishna_mis/domain/export/export_builders.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../../../integration_test/support/pdf_inflate.dart';
import '../../support/export_fixtures.dart';
import '../../support/pdf_text.dart';

ByteData _asset(String path) =>
    ByteData.sublistView(File(path).readAsBytesSync());

void main() {
  tzdata.initializeTimeZones();

  final fonts = ExportPdfFonts.fromBytes(
    regular: _asset(exportPdfRegularFontAsset),
    bold: _asset(exportPdfBoldFontAsset),
  );

  PnlExportDocument doc(ExportScope scope, PnlResult result) =>
      switch (ExportDocuments.profitAndLoss(
        fxContext(
          fxPermit(ExportReport.profitAndLoss, scope),
          freshness: fxFreshness(),
          periodName: 'This month',
        ),
        result,
      )) {
        ExportBuilt(:final document) => document,
        ExportNotBuilt(:final reason) => throw StateError('$reason'),
      };

  for (final (name, scope, result) in [
    ('one property', ExportScope.unit(fxCcr), fxCcrSeptember()),
    ('consolidated', fxBoth, fxConsolidated()),
  ]) {
    test(
      '$name: the inflated saved PDF reads line for line as the plain one',
      () async {
        final d = doc(scope, result);
        final compressed = await pnlPdf(d, fonts);
        final plain = await pnlPdf(d, fonts, compress: false);

        expect(
          () => PdfText.read(compressed),
          throwsStateError,
          reason: 'the shipped PDF really is compressed',
        );
        final inflated = PdfText.read(inflatePdfStreams(compressed));
        final expected = PdfText.read(plain);
        expect(inflated.pages.length, expected.pages.length);
        for (var i = 0; i < expected.pages.length; i++) {
          expect(
            inflated.pages[i].lines,
            expected.pages[i].lines,
            reason: 'page $i',
          );
        }
        expect(inflated.lines.join('\n'), contains('₹'));
      },
    );
  }
}
