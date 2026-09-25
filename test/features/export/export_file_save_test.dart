/// Saving an export (Phase 7 Slice 6, §51.7): the person chooses, a cancel writes
/// nothing, nothing is replaced silently, and a failed write leaves no partial file.
///
/// The native dialog is replaced by a picker that answers with a path; everything after
/// the dialog is the shipped code, writing to a real temporary folder.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/features/export/export_file_save.dart';
import 'package:krishna_mis/features/export/export_pipeline.dart';

void main() {
  late Directory dir;
  final bytes = Uint8List.fromList(List.generate(4096, (i) => i % 251));

  setUp(() => dir = Directory.systemTemp.createTempSync('export-save-'));
  tearDown(() => dir.deleteSync(recursive: true));

  String at(String name) => '${dir.path}${Platform.pathSeparator}$name';

  List<String> names() =>
      dir
          .listSync()
          .map((e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
          .toList()
        ..sort();

  ExportFileSaver saverAnswering(
    String? path, {
    List<({String name, ExportFileFormat format})>? asked,
  }) => ExportFileSaver(
    pickLocation: ({required suggestedName, required format}) async {
      asked?.add((name: suggestedName, format: format));
      return path;
    },
  );

  test('the dialog is offered the readable name and the format', () async {
    final asked = <({String name, ExportFileFormat format})>[];
    await saverAnswering(null, asked: asked).save(
      bytes: bytes,
      suggestedName:
          'KrishnaImperialMIS_ProfitAndLoss_Consolidated_2026-09-01_2026-09-19.pdf',
      format: ExportFileFormat.pdf,
    );
    expect(asked.single.name, endsWith('.pdf'));
    expect(asked.single.format, ExportFileFormat.pdf);
  });

  test('cancelling writes nothing and is not an error', () async {
    final outcome = await saverAnswering(
      null,
    ).save(bytes: bytes, suggestedName: 'x.pdf', format: ExportFileFormat.pdf);
    expect(outcome, isA<ExportSaveCancelled>());
    expect(names(), isEmpty);
  });

  test(
    'the chosen file holds exactly the bytes, and nothing else is left',
    () async {
      final outcome = await saverAnswering(at('P&L September.pdf')).save(
        bytes: bytes,
        suggestedName: 'x.pdf',
        format: ExportFileFormat.pdf,
      );
      expect((outcome as ExportSaved).fileName, 'P&L September.pdf');
      expect(File(at('P&L September.pdf')).readAsBytesSync(), bytes);
      expect(names(), ['P&L September.pdf']);
    },
  );

  test('a missing extension is added', () async {
    final outcome = await saverAnswering(at('september')).save(
      bytes: bytes,
      suggestedName: 'x.xlsx',
      format: ExportFileFormat.xlsx,
    );
    expect((outcome as ExportSaved).fileName, 'september.xlsx');
    expect(names(), ['september.xlsx']);
  });

  test('the extension is matched without regard to case', () async {
    final outcome = await saverAnswering(
      at('SEPTEMBER.PDF'),
    ).save(bytes: bytes, suggestedName: 'x.pdf', format: ExportFileFormat.pdf);
    expect((outcome as ExportSaved).fileName, 'SEPTEMBER.PDF');
  });

  test('a name the dialog never asked about is not replaced', () async {
    // The person typed "september"; the dialog confirmed nothing about september.pdf.
    File(at('september.pdf')).writeAsStringSync('an earlier report');
    final outcome = await saverAnswering(
      at('september'),
    ).save(bytes: bytes, suggestedName: 'x.pdf', format: ExportFileFormat.pdf);
    expect((outcome as ExportSaveFailed).failure, ExportSaveFailure.nameTaken);
    expect(File(at('september.pdf')).readAsStringSync(), 'an earlier report');
    expect(names(), ['september.pdf']);
  });

  test('a name the dialog confirmed is replaced whole', () async {
    File(
      at('september.pdf'),
    ).writeAsStringSync('an earlier, longer report text');
    final outcome = await saverAnswering(
      at('september.pdf'),
    ).save(bytes: bytes, suggestedName: 'x.pdf', format: ExportFileFormat.pdf);
    expect(outcome, isA<ExportSaved>());
    expect(File(at('september.pdf')).readAsBytesSync(), bytes);
    expect(names(), ['september.pdf']);
  });

  test('a write that fails leaves no partial file behind', () async {
    final outcome = await saverAnswering(
      at('no-such-folder${Platform.pathSeparator}september.pdf'),
    ).save(bytes: bytes, suggestedName: 'x.pdf', format: ExportFileFormat.pdf);
    expect(
      (outcome as ExportSaveFailed).failure,
      ExportSaveFailure.writeFailed,
    );
    expect(names(), isEmpty);
  });

  test('a rename that fails removes the temporary file', () async {
    // A folder stands where the file would go: the bytes are written, the rename fails.
    Directory(at('september.pdf')).createSync();
    final outcome = await saverAnswering(
      at('september.pdf'),
    ).save(bytes: bytes, suggestedName: 'x.pdf', format: ExportFileFormat.pdf);
    expect(outcome, isA<ExportSaveFailed>());
    expect(names(), ['september.pdf']);
    expect(Directory(at('september.pdf')).listSync(), isEmpty);
  });

  test('a dialog that cannot open is stated, and nothing is written', () async {
    final saver = ExportFileSaver(
      pickLocation: ({required suggestedName, required format}) async =>
          throw StateError('no window'),
    );
    final outcome = await saver.save(
      bytes: bytes,
      suggestedName: 'x.pdf',
      format: ExportFileFormat.pdf,
    );
    expect(
      (outcome as ExportSaveFailed).failure,
      ExportSaveFailure.dialogUnavailable,
    );
    expect(names(), isEmpty);
  });

  test('authority lost while the dialog was open writes nothing', () async {
    final outcome = await saverAnswering(at('september.pdf')).save(
      bytes: bytes,
      suggestedName: 'x.pdf',
      format: ExportFileFormat.pdf,
      beforeWrite: () => false,
    );
    expect(outcome, isA<ExportSaveCancelled>());
    expect(names(), isEmpty);
  });

  group('a file-system error, in the person\'s terms', () {
    test('Windows', () {
      expect(
        exportSaveFailureForWindows(5),
        ExportSaveFailure.permissionDenied,
      );
      expect(
        exportSaveFailureForWindows(19),
        ExportSaveFailure.permissionDenied,
      );
      expect(exportSaveFailureForWindows(32), ExportSaveFailure.fileInUse);
      expect(exportSaveFailureForWindows(33), ExportSaveFailure.fileInUse);
      expect(exportSaveFailureForWindows(112), ExportSaveFailure.writeFailed);
      expect(exportSaveFailureForWindows(null), ExportSaveFailure.writeFailed);
    });

    test('POSIX', () {
      expect(exportSaveFailureForPosix(13), ExportSaveFailure.permissionDenied);
      expect(exportSaveFailureForPosix(1), ExportSaveFailure.permissionDenied);
      expect(exportSaveFailureForPosix(30), ExportSaveFailure.permissionDenied);
      expect(exportSaveFailureForPosix(16), ExportSaveFailure.fileInUse);
      expect(exportSaveFailureForPosix(28), ExportSaveFailure.writeFailed);
    });
  });
}
