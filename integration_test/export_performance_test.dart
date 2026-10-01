/// Phase 8 Slice 6 — export performance on a real device (D-312 D2, D-313 T2/T3).
///
/// The host test (`test/core/export/export_performance_test.dart`) asserts that every
/// workload renders completely; a host timing is not a verdict. This runs **the same
/// workloads from the same shared fixture** in the real application binary, with the
/// fonts read from the application bundle exactly as production reads them:
///
/// ```
///   flutter test integration_test/export_performance_test.dart -d windows
///   flutter test integration_test/export_performance_test.dart -d <android device>
/// ```
///
/// Stages, each timed separately: the document model, the XLSX or PDF render, and the
/// file write through the production atomic writer. Dialogs and human waits are not part
/// of any figure (D2). The one-off font load is reported on its own line.
///
/// Options, as `--dart-define`s: `KRISHNA_EXPORT_RUNS` (default 5) and
/// `KRISHNA_EXPORT_SIZES` (comma list of normal, stress; default both).
///
/// It needs no backend and writes only into its own temporary folder, deleted at the end.
/// **Timings are reported, never asserted** (D-075).
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/domain/export/export_document.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';
import 'package:krishna_mis/features/export/export_pipeline.dart'
    show ExportFileFormat;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../test/support/export_workload.dart';
import '../test/support/pdf_text.dart';
import 'support/pdf_inflate.dart';

const _runs = int.fromEnvironment('KRISHNA_EXPORT_RUNS', defaultValue: 5);
const _sizes = String.fromEnvironment(
  'KRISHNA_EXPORT_SIZES',
  defaultValue: 'normal,stress',
);

void _report(String line) {
  // ignore: avoid_print
  print('EXPORT-PERF ${Platform.operatingSystem} $line');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'export stages on ${Platform.operatingSystem}',
    () async {
      tzdata.initializeTimeZones();
      final root = await getTemporaryDirectory();
      final out = Directory(
        '${root.path}${Platform.pathSeparator}krishna_mis_export_perf',
      );
      if (out.existsSync()) out.deleteSync(recursive: true);
      out.createSync(recursive: true);

      try {
        // The font load production pays once, on the first PDF (exportPdfFontsProvider).
        final fontWatch = Stopwatch()..start();
        final fonts = ExportPdfFonts.fromBytes(
          regular: await rootBundle.load(exportPdfRegularFontAsset),
          bold: await rootBundle.load(exportPdfBoldFontAsset),
        );
        _report(
          'fonts load+check ${(fontWatch.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms '
          '(once per session)',
        );

        // What this device actually produced: the P&L PDF, as written, read back.
        for (final size in ExportWorkloadSize.values) {
          if (!_sizes.split(',').contains(size.name)) continue;
          final workload = exportWorkloads(
            size,
          ).firstWhere((w) => w.report == ExportReport.profitAndLoss);
          final document = workload.build() as PnlExportDocument;
          // The first P&L of its size in this process: for `normal`, the session's very
          // first export (fonts already loaded, reported above).
          final first = await timeExport(
            workload,
            ExportFileFormat.pdf,
            fonts,
            out,
          );
          _report(
            '${size.name} · P&L · pdf · FIRST in session · '
            'model ${(first.model / 1000).toStringAsFixed(1)} · '
            'render ${(first.render / 1000).toStringAsFixed(1)} · '
            'write ${(first.write / 1000).toStringAsFixed(1)} · '
            'TOTAL ${(first.total / 1000).toStringAsFixed(1)} ms',
          );
          final written = File('${out.path}${Platform.pathSeparator}PL.pdf');
          expect(
            written.path,
            startsWith(root.path),
            reason: 'the app-private cache',
          );
          final pdf = PdfText.read(
            inflatePdfStreams(written.readAsBytesSync()),
          );
          final text = pdf.lines.join('\n');
          final scope = document.scopeStatement;
          final money = MoneyFormatter.standard;
          expect(text, contains('₹'));
          expect(text, contains(document.header.scopeLabel));
          expect(text, contains(exportRangeLabel(document.header.range)));
          expect(text, contains('Synchronised as of'));
          for (final figure in [
            scope.grossSales,
            scope.gst,
            scope.netSales,
            scope.expenses,
            scope.operatingProfit,
          ]) {
            expect(text, contains(money.format(figure)), reason: 'whole');
          }
          for (final line in scope.revenueLines!) {
            expect(text, contains(line.categoryLabel));
            expect(text, contains(money.format(line.net)));
          }
          for (final line in scope.expenseLines!) {
            expect(text, contains(line.categoryLabel));
            expect(text, contains(money.format(line.amount)));
          }
          _report(
            '${size.name} · P&L · pdf verified on device: '
            '${pdf.pages.length} pages · '
            '${scope.revenueLines!.length} revenue + '
            '${scope.expenseLines!.length} expense lines, each printed whole · '
            'scope, period, freshness and ₹ present · under ${root.path}',
          );
        }

        for (final size in ExportWorkloadSize.values) {
          if (!_sizes.split(',').contains(size.name)) continue;
          for (final workload in exportWorkloads(size)) {
            for (final format in ExportFileFormat.values) {
              // One warm-up, discarded and reported (D-313).
              final cold = await timeExport(workload, format, fonts, out);
              final model = <int>[];
              final render = <int>[];
              final write = <int>[];
              final total = <int>[];
              var bytes = 0;
              for (var i = 0; i < _runs; i++) {
                final t = await timeExport(workload, format, fonts, out);
                model.add(t.model);
                render.add(t.render);
                write.add(t.write);
                total.add(t.total);
                bytes = t.bytes;
              }
              _report(
                '${size.name} · ${workload.name} · ${format.extension} · '
                '$bytes B · warm-up ${(cold.total / 1000).toStringAsFixed(1)} ms · '
                'model ${exportStageSummary(model)} · '
                'render ${exportStageSummary(render)} · '
                'write ${exportStageSummary(write)} · '
                'TOTAL ${exportStageSummary(total)} ms (median (min–max), $_runs runs)',
              );
            }
          }
        }
      } finally {
        if (out.existsSync()) out.deleteSync(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
