/// `lib/features/export` delivers files and decides nothing about money (Phase 7 Slices
/// 6–8; `ARCHITECTURE.md` §51.1).
///
/// Asserted over the directory, so the rules hold for files nobody has written yet. The
/// token lists are the reporting surfaces' own (D-279), plus the delivery layer's rules:
///
/// * **no synchronisation** — an export is made from what the device holds (§51.6);
/// * **no role name** — authority is capability and scope (D-291, D-292);
/// * **no chosen-for-you folder** — the person picks where a file goes (§51.7);
/// * **one writer** — only the Save As file writes bytes to disk;
/// * **authority decided here** — the complement, so the rules cannot pass by the
///   directory doing nothing at all.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/surface_guard_tokens.dart';

const _dir = 'lib/features/export';

const _sync = [
  'pnlSyncProvider.notifier',
  'dashboardSyncProvider.notifier',
  'reportingSyncProvider',
  'ReportingSync',
  'RefreshWhenOpened',
  'OwnerSettlementRefresher',
  '.refresh()',
  '.download()',
  'ReportingGateway',
];

const _roles = [
  'RoleTemplates',
  "'owner'",
  "'manager'",
  "'accountant'",
  "'data_entry'",
  'roleCode',
  '.role ',
];

const _folders = [
  'getDownloadsDirectory',
  'Downloads',
  'getApplicationDocumentsDirectory',
  'getExternalStorage',
  'USERPROFILE',
  'Platform.environment',
];

const _shareFile = 'export_share.dart';

const _fileWriter = 'export_file_save.dart';

/// The only files that talk to `printing`: the print dialog (Slice 7) and, on Android, the
/// share sheet (Slice 8).
const _printingUsers = ['export_print.dart', 'export_share.dart'];

/// The rule, as a function of source, so the planted controls exercise the same code the
/// directory scan does.
List<String> violationsIn(String path, String code) => [
  ...surfaceViolations(code, [
    ...surfaceCalculation,
    ...surfaceMutation,
    ...surfaceOwnerAccounts,
    ...surfaceStorage,
    ..._sync,
    ..._roles,
    ..._folders,
    'DateTime.now',
  ]),
  if (!path.endsWith(_fileWriter))
    ...surfaceViolations(code, ['File(', 'writeAsBytes']),
  // The Save As writer, and the share cleanup of the app's own private cache, are the only
  // files that touch the file system.
  if (!path.endsWith(_fileWriter) && !path.endsWith(_shareFile))
    ...surfaceViolations(code, ['dart:io', 'path_provider']),
  if (path.endsWith(_shareFile)) ...[
    ...surfaceViolations(code, ['writeAsBytes', 'createSync', 'copySync']),
    if (code.contains('path_provider') &&
        !code.contains('path_provider.dart\' show getTemporaryDirectory;'))
      'a folder other than the private cache',
  ],
  if (!_printingUsers.any(path.endsWith))
    ...surfaceViolations(code, ['package:printing', 'Printing.']),
  // Printing is the PDF: no second renderer, no print layout (§51.5, D-299).
  if (_printingUsers.any(path.endsWith))
    ...surfaceViolations(code, [
      'package:pdf/widgets.dart',
      'core/export/pdf/',
      'core/export/workbook/',
      'pnlPdf(',
      'Workbook(',
      'ExportDocuments.',
    ]),
  // The one navigation: opening a report's own section in Analytics.
  for (final m in RegExp(r'context\.(go|push)\(([^)]*)\)').allMatches(code))
    if (m.group(2) != 'AppRoutes.analytics') 'navigates to ${m.group(2)}',
  if (code.contains('Navigator.push') || code.contains('MaterialPageRoute'))
    'pushes a route',
];

void main() {
  final files = Directory(_dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('the directory exists and is scanned', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    test('${file.path} delivers and decides nothing about money', () {
      expect(violationsIn(file.path, surfaceFileCode(file.path)), isEmpty);
    });
  }

  group('the complement: authority is decided here', () {
    String code(String name) => surfacePhrases(surfaceFileCode('$_dir/$name'));

    test('the pipeline decides through ExportAuthority before it builds', () {
      final pipeline = code('export_pipeline.dart');
      expect(pipeline, contains('ExportAuthority.decide('));
      expect(
        pipeline.indexOf('decide(') < pipeline.indexOf('ExportDocuments.'),
        isTrue,
      );
    });

    test('an action is decided again before its bytes leave the app', () {
      expect(
        code('export_providers.dart'),
        contains('ExportAuthority.offers('),
      );
      expect(code('export_providers.dart'), contains('stillPermitted'));
    });

    test('the Export Centre offers only what the pipeline would permit', () {
      expect(
        code('export_centre_page.dart'),
        contains('ExportPipeline.decide('),
      );
    });

    test(
      'printing hands the renderer\'s bytes to the native dialog, unchanged',
      () {
        final printing = surfaceDense(
          surfaceFileCode('$_dir/export_print.dart'),
        );
        expect(printing, contains('Printing.layoutPdf('));
        // The dialog is given the layout, which is the renderer's bytes unchanged or,
        // once authority is gone, nothing (Slice 10).
        expect(printing, contains('onLayout:(_)async=>layout()'));
        expect(printing, contains('stillPermitted()?bytes:Uint8List(0)'));
        expect(printing, contains('dynamicLayout:false'));
        final providers = surfaceDense(
          surfaceFileCode('$_dir/export_providers.dart'),
        );
        expect(providers, contains('ExportAction.print,ExportFileFormat.pdf,'));
        expect(
          providers,
          contains(
            'layout:()=>exportPrintLayout(rendered.bytes,stillPermitted)',
          ),
        );
      },
    );

    test('the file writer writes beside the target, then renames', () {
      final writer = code(_fileWriter);
      expect(writer, contains('.part'));
      expect(writer, contains('.rename('));
      expect(writer, contains('getSaveLocation('));
    });
  });

  group('the guard catches what it exists to catch', () {
    const page = '$_dir/export_centre_page.dart';
    for (final (label, snippet) in [
      (
        'a refresh before export',
        'ref.read(pnlSyncProvider.notifier).refresh();',
      ),
      (
        'a dashboard download',
        'ref.read(dashboardSyncProvider.notifier).download();',
      ),
      ('a role name', "if (principal.role == 'manager') return;"),
      ('a role bundle', 'RoleTemplates.owner.contains(c)'),
      ('the Downloads folder', "final path = 'C:/Users/me/Downloads/x.pdf';"),
      ('a documents folder', 'await getApplicationDocumentsDirectory();'),
      ('a sum', 'final total = Money.sum(lines);'),
      ('a paise read', 'final p = figure.paise;'),
      ('a device clock', 'final at = DateTime.now();'),
      (
        'a file written outside the writer',
        "File('x.pdf').writeAsBytesSync(b);",
      ),
      ('another destination', 'context.go(AppRoutes.overview);'),
      ('an Owner Accounts export', 'ownerSettlementPreviewProvider'),
      (
        'the print dialog outside its file',
        'await Printing.layoutPdf(onLayout: f);',
      ),
    ]) {
      test(label, () {
        expect(violationsIn(page, snippet), isNotEmpty);
      });
    }

    for (final (label, snippet) in [
      ('a print layout', "import 'package:pdf/widgets.dart' as pw;"),
      ('a second render for printing', 'onLayout: (f) => pnlPdf(doc, fonts),'),
      ('a print-specific document', 'ExportDocuments.profitAndLoss(c, r)'),
    ]) {
      test(label, () {
        expect(violationsIn('$_dir/export_print.dart', snippet), isNotEmpty);
      });
    }

    test('the one approved navigation is allowed', () {
      expect(violationsIn(page, 'context.go(AppRoutes.analytics);'), isEmpty);
    });

    test('the writer may write files', () {
      expect(
        violationsIn('$_dir/$_fileWriter', "await File(p).writeAsBytes(b);"),
        isEmpty,
      );
    });
  });
}
