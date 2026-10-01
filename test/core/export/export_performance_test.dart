/// Phase 8 Slice 6 — what an export costs, measured stage by stage (D-312 D2, D-313).
///
/// A host timing is not a verdict (D-313): this asserts that every workload renders,
/// carries every line it was given, and writes through the production atomic writer. The
/// timings are printed so a regression is visible; the T2 verdict comes from the
/// real Windows executable (`integration_test/export_performance_test.dart`) and the
/// reference Android device.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:krishna_mis/features/export/export_pipeline.dart'
    show ExportFileFormat;

import '../../support/export_workload.dart';
import '../../support/pdf_text.dart';
import '../../support/xlsx_reader.dart';

ByteData _asset(String path) =>
    ByteData.sublistView(File(path).readAsBytesSync());

final _fonts = ExportPdfFonts.fromBytes(
  regular: _asset(exportPdfRegularFontAsset),
  bold: _asset(exportPdfBoldFontAsset),
);

int _rowsOf(StoredWorkbook workbook, String sheet) {
  final rows = <String>{};
  for (final ref in workbook.cells(sheet).keys) {
    rows.add(ref.replaceAll(RegExp('[A-Z]'), ''));
  }
  return rows.length;
}

void main() {
  tzdata.initializeTimeZones();
  late Directory out;
  setUp(() => out = Directory.systemTemp.createTempSync('export_perf_'));
  tearDown(() => out.deleteSync(recursive: true));

  for (final size in ExportWorkloadSize.values) {
    group('${size.name} exports', () {
      for (final workload in exportWorkloads(size)) {
        test('${workload.name}: every line reaches both files', () async {
          final document = workload.build();

          final pdf = await renderExport(
            document,
            ExportFileFormat.pdf,
            _fonts,
            compress: false,
          );
          final pages = PdfText.read(pdf).pages.length;
          expect(pages, greaterThan(0));

          final xlsx = await renderExport(
            document,
            ExportFileFormat.xlsx,
            _fonts,
          );
          final workbook = StoredWorkbook(xlsx);

          // Completeness: a large export must not quietly lose lines.
          if (document case PnlExportDocument(:final scopeStatement)) {
            final revenue = scopeStatement.revenueLines!.length;
            final expenses = scopeStatement.expenseLines!.length;
            expect(
              _rowsOf(workbook, 'Revenue'),
              greaterThanOrEqualTo(revenue + 1),
            );
            expect(
              _rowsOf(workbook, 'Expenses'),
              greaterThanOrEqualTo(expenses + 1),
            );
            final text = PdfText.read(pdf).text;
            for (final line in scopeStatement.expenseLines!) {
              expect(
                text,
                contains(line.categoryLabel),
                reason: 'every expense line is printed',
              );
            }
          }

          final times = await timeExport(
            workload,
            ExportFileFormat.pdf,
            _fonts,
            out,
          );
          final sheetTimes = await timeExport(
            workload,
            ExportFileFormat.xlsx,
            _fonts,
            out,
          );
          expect(
            out.listSync().where((f) => f.path.endsWith('.part')),
            isEmpty,
            reason: 'the atomic writer leaves no hidden file behind',
          );

          // Reported, not asserted (D-313).
          // ignore: avoid_print
          print(
            'E-HOST ${size.name} ${workload.name}: '
            'pages $pages · pdf ${times.bytes} B '
            'model ${times.model} µs render ${times.render} µs '
            'write ${times.write} µs · xlsx ${sheetTimes.bytes} B '
            'render ${sheetTimes.render} µs',
          );
        });
      }
    });
  }
}
