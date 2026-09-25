/// `lib/core/export` lays documents out and never calculates (Phase 7 Slice 4; §51.1).
///
/// Asserted over the directory, so the rule holds for files nobody has written yet. It
/// reuses the reporting-surface token lists (D-279) rather than a copy that could drift.
///
/// Three layers, three rules:
/// * **the writer** (`xlsx/`) knows nothing about money or finance — it imports no
///   project code — and it has no way to write a formula;
/// * **the layouts** (`workbook/`, and later `pdf/`) and **the wording** place and name
///   figures, and contain no arithmetic at all;
/// * **nothing** here reads storage, the network, a clock or a platform.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../support/surface_guard_tokens.dart';

typedef _Source = ({String path, String code});

List<_Source> _sources(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map(
      (f) => (
        path: f.path.replaceAll(r'\', '/'),
        code: surfaceCode(f.readAsStringSync()),
      ),
    )
    .toList(growable: false);

/// A binary arithmetic operator between two operands, as the formatter writes it.
final _arithmetic = RegExp(r'[\w)\]]\s+(\+|-|\*|/|~/|%)\s+[\w(]');

bool _isWriter(String path) => path.contains('/core/export/xlsx/');

/// Source with every single-quoted string's text removed — "Operating Profit / Loss" and
/// "(device clock)" are words, not code — while the code inside each `${...}` is kept, so
/// arithmetic cannot hide in an interpolation.
String _withoutStringText(String code) => code.replaceAllMapped(
  RegExp(r"'(?:[^'\\\n]|\\.)*'"),
  (m) => [
    for (final i in RegExp(r'\$\{([^}]*)\}').allMatches(m.group(0)!))
      i.group(1),
  ].join(' ; '),
);

/// The rule, as a function of source, so the planted controls exercise the same code the
/// directory scan does.
List<String> violationsIn(String path, String code) {
  final bare = _withoutStringText(code);
  return [
    for (final token in [
      ...surfaceCalculation,
      ...surfaceStorage,
      ...surfaceNavigation,
      ...surfaceMutation,
      ...surfaceOwnerAccounts,
      'Money.fromRupees(',
      'Money.tryParse(',
      'DateTime.now',
      'clock.',
      'Clock',
      'toDouble',
      'double.parse',
      'num.parse',
      'int.parse',
      // Money is never shrunk to fit, on paper as on screen (D-286).
      'FittedBox',
      'BoxFit',
      'textScale',
      // Fonts and figures arrive; nothing here loads or fetches them. (A file needs
      // `dart:io`, which is refused below; `ArchiveFile(` is not a file.)
      'rootBundle',
      'HttpClient',
    ])
      if (bare.contains(token)) token,
    // Only the writer may count columns; a layout that adds anything is doing arithmetic.
    if (!_isWriter(path) && _arithmetic.hasMatch(bare)) 'binary arithmetic',
    if (code.contains('<f>') || code.contains('<f ')) 'a formula element',
    for (final line in code.split('\n'))
      if (line.trimLeft().startsWith('import ') &&
          [
            'dart:io',
            'dart:ui',
            'package:flutter/',
            'package:flutter_riverpod/',
            'package:drift/',
            'package:supabase',
            'package:http',
            'package:krishna_mis/data/',
            'package:krishna_mis/features/',
            'package:krishna_mis/app/',
            // Delivery (print, share, save) lives in the feature layer.
            'package:printing',
            'package:file_selector',
            // The writer is packaging: it may not know what a P&L, or even money, is.
            if (_isWriter(path)) 'package:krishna_mis/',
            if (!_isWriter(path)) 'package:archive',
            if (!path.contains('/core/export/pdf/')) 'package:pdf',
          ].any(line.contains))
        'import: ${line.trim()}',
  ];
}

void main() {
  final files = _sources('lib/core/export');

  test('the directory holds the writer, the wording and the P&L workbook', () {
    expect(
      files.map((f) => f.path.split('/').last),
      containsAll([
        'xlsx_writer.dart',
        'export_wording.dart',
        'pnl_workbook.dart',
        'pdf_fonts.dart',
        'pnl_pdf.dart',
      ]),
    );
  });

  for (final file in files) {
    test('${file.path} lays out and calculates nothing', () {
      expect(violationsIn(file.path, file.code), isEmpty);
    });
  }

  test('the writer has no formula cell type', () {
    final writer = files.singleWhere((f) => _isWriter(f.path)).code;
    final cellTypes = RegExp(
      r'final class (Xlsx\w+) extends XlsxCell',
    ).allMatches(writer).map((m) => m.group(1)).toSet();
    expect(cellTypes, {'XlsxText', 'XlsxNumber', 'XlsxDate', 'XlsxBlank'});
    expect(writer, isNot(contains('Formula')));
  });

  test('a layout turns money into a cell only through the formatter', () {
    final workbook = files
        .singleWhere((f) => f.path.endsWith('pnl_workbook.dart'))
        .code;
    expect(workbook, contains('MoneyFormatter.decimalLiteral('));
    expect(workbook, contains('.displayedFractionLiteral'));
    // Every numeric cell in the layout is built from one of those two literals.
    final numbers = RegExp(
      r'XlsxCell\.number\(\s*([^,]+),',
    ).allMatches(workbook);
    expect(numbers, isNotEmpty);
    for (final m in numbers) {
      expect(
        m.group(1)!.trim(),
        anyOf(
          startsWith('MoneyFormatter.decimalLiteral('),
          'margin.displayedFractionLiteral',
        ),
      );
    }
  });

  test('the PDF prints money only through the screen formatter', () {
    final pdf = files.singleWhere((f) => f.path.endsWith('pnl_pdf.dart')).code;
    expect(pdf, contains('MoneyFormatter.standard.format('));
    expect(pdf, contains('.displayTwoDecimals'));
    expect(pdf, isNot(contains('decimalLiteral')));
    // No information dictionary: the package would stamp it with the device clock.
    final document = RegExp(
      r'pw\.Document\(([^;]*?)\);',
      dotAll: true,
    ).firstMatch(pdf)!.group(1)!;
    for (final key in [
      'title:',
      'author:',
      'creator:',
      'producer:',
      'subject:',
    ]) {
      expect(document, isNot(contains(key)), reason: key);
    }
  });

  group('the rule is seen to fail (planted controls)', () {
    const layout = 'lib/core/export/workbook/planted.dart';
    const writer = 'lib/core/export/xlsx/planted.dart';
    for (final (name, path, snippet) in [
      ('a sum', layout, 'final t = Money.sum(lines);'),
      ('paise read directly', layout, 'final p = m.paise;'),
      ('a subtraction', layout, 'final p = s.netSales - s.expenses;'),
      ('a recomputed margin', layout, 'final x = r.percentageScaled(2);'),
      ('a parsed figure', layout, 'final m = Money.tryParse(text);'),
      ('a clock', layout, 'final at = DateTime.now();'),
      ('a sort', layout, 'lines.sort((a, b) => 0);'),
      ('a platform import', layout, "import 'dart:io';"),
      (
        'a feature import',
        layout,
        "import 'package:krishna_mis/features/x.dart';",
      ),
      ('a formula', writer, "b.write('<c><f>SUM(A1:A2)</f></c>');"),
      ('a shrunk figure', layout, 'pw.FittedBox(child: pw.Text(amount));'),
      ('a font loaded here', layout, "final b = await rootBundle.load('f');"),
      (
        'printing from a layout',
        layout,
        "import 'package:printing/printing.dart';",
      ),
      (
        'the pdf package in a workbook',
        layout,
        "import 'package:pdf/pdf.dart';",
      ),
      (
        'project code in the writer',
        writer,
        "import 'package:krishna_mis/domain/value_objects/money.dart';",
      ),
    ]) {
      test(name, () => expect(violationsIn(path, snippet), isNotEmpty));
    }

    test('arithmetic hidden in an interpolation', () {
      expect(violationsIn(layout, r"final s = '${a - b}';"), isNotEmpty);
    });

    test('but words in a string are words', () {
      expect(
        violationsIn(layout, "final s = 'Profit / Loss (device clock)';"),
        isEmpty,
      );
    });

    test('but the writer may count columns', () {
      expect(violationsIn(writer, 'final next = column + 1;'), isEmpty);
    });
  });
}
