/// No surface shrinks a figure to fit (D-286).
///
/// At a large system font the layout gives way — it reflows and grows taller — and the
/// money keeps the size the reader chose. The runtime checks in
/// `test/support/money_layout.dart` read what was painted; this reads the source, so a
/// shrink mechanism cannot come back in a screen nobody has rendered at 2.0× yet.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every way this codebase could make text smaller than the reader asked for.
const _shrinkTokens = [
  'FittedBox',
  'BoxFit.scaleDown',
  'Transform.scale',
  'withClampedTextScaling',
  'withNoTextScaling',
  'TextScaler.noScaling',
  'TextScaler.linear',
  'textScaleFactor',
];

String _stripComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((line) {
      final at = line.indexOf('//');
      return at < 0 ? line : line.substring(0, at);
    })
    .join('\n');

List<String> _shrinkMechanisms(String source) {
  final code = _stripComments(source);
  return [
    for (final token in _shrinkTokens)
      if (code.contains(token)) token,
  ];
}

void main() {
  test('nothing in lib/ shrinks text to fit', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final found = _shrinkMechanisms(file.readAsStringSync());
      if (found.isNotEmpty) offenders.add('${file.path}: ${found.join(', ')}');
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'money must not silently shrink to fit — reflow the layout instead '
          '(D-286)',
    );
  });

  group('the guard fails when it should', () {
    test('a FittedBox around a figure is found', () {
      expect(
        _shrinkMechanisms(
          'child: FittedBox(fit: BoxFit.scaleDown, child: MoneyText(a)),',
        ),
        containsAll(['FittedBox', 'BoxFit.scaleDown']),
      );
    });

    test('a clamped or disabled text scale is found', () {
      expect(_shrinkMechanisms('MediaQuery.withClampedTextScaling(child: x)'), [
        'withClampedTextScaling',
      ]);
      expect(_shrinkMechanisms('Text(a, textScaler: TextScaler.noScaling)'), [
        'TextScaler.noScaling',
      ]);
    });

    test('a comment mentioning the mechanism is not a use of it', () {
      expect(_shrinkMechanisms('// never a FittedBox here'), isEmpty);
    });
  });
}
