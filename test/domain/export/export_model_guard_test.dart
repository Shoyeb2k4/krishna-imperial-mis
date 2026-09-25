/// `lib/domain/export` copies and never calculates (Phase 7 Slice 3; D-299, §51.4).
///
/// Asserted over the whole directory, so the rule holds for files nobody has written yet.
/// It reuses the reporting-surface token lists (D-279) rather than a copy that could drift
/// from them, with one named exception: the builders may call [PropertyComparison.of], the
/// canonical per-property split (D-270) that the Business Comparison screen itself shows.
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
final _arithmetic = RegExp(r'[\w)\]]\s+(\+|-|\*|/|~/)\s+[\w(]');

/// The rule, as a function of source, so the planted controls below exercise the same code
/// the directory scan does.
List<String> violationsIn(String path, String code) {
  final allowed = {
    if (path.endsWith('export_builders.dart')) 'PropertyComparison.of(',
  };
  return [
    for (final token in [
      ...surfaceCalculation,
      ...surfaceStorage,
      ...surfaceNavigation,
      ...surfaceMutation,
      ...surfaceOwnerAccounts,
      'DateTime.now',
      'clock',
      'toDouble',
      'double.',
    ])
      if (!allowed.contains(token) && code.contains(token)) token,
    if (_arithmetic.hasMatch(code)) 'binary arithmetic',
    for (final line in code.split('\n'))
      if (line.trimLeft().startsWith('import ') &&
          const [
            'dart:io',
            'dart:ui',
            'package:flutter/',
            'package:flutter_riverpod/',
            'package:drift/',
            'package:supabase',
            'package:krishna_mis/data/',
            'package:krishna_mis/features/',
            'package:krishna_mis/app/',
          ].any(line.contains))
        'import: ${line.trim()}',
  ];
}

void main() {
  final files = _sources('lib/domain/export');

  test('the directory exists and holds the models and the builders', () {
    expect(
      files.map((f) => f.path.split('/').last),
      containsAll(['export_document.dart', 'export_builders.dart']),
    );
  });

  for (final file in files) {
    test('${file.path} copies figures and derives none', () {
      expect(violationsIn(file.path, file.code), isEmpty);
    });
  }

  test('the builders delegate to the canonical line order and split', () {
    final builders = files.singleWhere(
      (f) => f.path.endsWith('export_builders.dart'),
    );
    expect(builders.code, contains('PnlLineOrder.revenue('));
    expect(builders.code, contains('PnlLineOrder.expenses('));
    expect(builders.code, contains('PropertyComparison.of('));
    // Every public builder demands a permit: the context carries one and is required.
    expect(builders.code, contains('final ExportPermitted permit;'));
    expect(
      RegExp(
        r'static ExportBuild<\w+> \w+\(\s*ExportContext context',
      ).allMatches(builders.code),
      hasLength(4),
    );
  });

  test('a permit can be made only by ExportAuthority.decide', () {
    final authority = surfaceCode(
      File('lib/domain/finance/export_authority.dart').readAsStringSync(),
    );
    expect(authority, contains('const ExportPermitted._('));
    expect(authority, isNot(contains('const ExportPermitted(')));
  });

  group('the rule is seen to fail (planted controls)', () {
    const path = 'lib/domain/export/planted.dart';
    for (final (name, snippet) in [
      (
        'a profit worked out here',
        'final p = result.netSales - result.expenses;',
      ),
      ('a sum', 'final t = Money.sum(lines);'),
      ('a recomputed margin', 'final m = x.percentageScaled(2);'),
      ('a clock', 'final at = DateTime.now();'),
      ('a platform import', "import 'dart:io';"),
      ('a storage reach', 'final db = AppDatabase();'),
      ('a sort', 'lines.sort((a, b) => 0);'),
      ('a split outside the builders', 'PropertyComparison.of(result);'),
    ]) {
      test(name, () => expect(violationsIn(path, snippet), isNotEmpty));
    }

    test('but the builders may call the canonical split', () {
      expect(
        violationsIn(
          'lib/domain/export/export_builders.dart',
          'PropertyComparison.of(result);',
        ),
        isEmpty,
      );
    });
  });
}
