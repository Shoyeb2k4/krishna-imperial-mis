/// A real-application test never reaches the installation's own data or key (D-246,
/// D-249, D-247).
///
/// Phase 8 Slice 8 found four "restart" steps in the device acceptance suite calling
/// `bootstrap` without the acceptance folder — on Windows that opened the database in the
/// ordinary application data folder — and a suite that created and deleted the
/// installation's key and erased its database file. This guard reads every file under
/// `integration_test/` and refuses each shape of that, with planted violations proving it
/// can fail.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//` comments so prose that names a call is not mistaken for the call.
String _code(String source) => [
  for (final line in source.split('\n'))
    if (!line.trimLeft().startsWith('//')) line,
].join('\n');

/// Every place [source] reaches installation data without naming an isolated location.
List<String> _violations(String source) {
  final code = _code(source);
  final found = <String>[];
  for (final m in RegExp(
    r'\bbootstrap\(([^;]*?)\);',
    dotAll: true,
  ).allMatches(code)) {
    if (!m.group(1)!.contains('appDataDirectory:')) {
      found.add('bootstrap without appDataDirectory');
    }
  }
  for (final call in const [
    'DatabaseKeyManager()',
    'openEncryptedDatabase()',
    'openLocalStore()',
    'resolveDatabaseFile()',
    'databaseKeyNameFor()',
  ]) {
    if (code.contains(call)) found.add(call);
  }
  for (final m in RegExp(
    r'getApplicationSupportDirectory\(\)',
  ).allMatches(code)) {
    final before = code.substring(m.start < 300 ? 0 : m.start - 300, m.start);
    if (!before.contains('Platform.isWindows')) {
      found.add('getApplicationSupportDirectory() reachable on Windows');
    }
  }
  for (final m in RegExp(
    r'LocalDataLifecycle\(([^;]*?)\);',
    dotAll: true,
  ).allMatches(code)) {
    if (!m.group(1)!.contains('resolveFile:')) {
      found.add('LocalDataLifecycle erasing the default database file');
    }
  }
  return found;
}

void main() {
  test('no real-application test reaches the installation data or key', () {
    final files = Directory('integration_test')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    for (final file in files) {
      expect(_violations(file.readAsStringSync()), isEmpty, reason: file.path);
    }
  });

  group('the guard can fail', () {
    for (final (name, planted) in const [
      (
        'a restart without the folder',
        'final r = await bootstrap(transport: t);',
      ),
      ('the installation key', 'await DatabaseKeyManager().deleteKey();'),
      ('the default database', 'final db = await openEncryptedDatabase();'),
      ('the default file', 'final f = await resolveDatabaseFile();'),
      (
        'the support folder on Windows',
        'final d = await getApplicationSupportDirectory();',
      ),
      (
        'an erase of the default file',
        'final l = LocalDataLifecycle(outbox: o, keyManager: k);',
      ),
    ]) {
      test(name, () => expect(_violations(planted), isNotEmpty));
    }

    test('isolated calls pass', () {
      expect(
        _violations('''
final r = await bootstrap(
  transport: t,
  appDataDirectory: _acceptanceDataDirectory(),
);
final d = Platform.isWindows
    ? Directory('x')
    : await getApplicationSupportDirectory();
final l = LocalDataLifecycle(outbox: o, keyManager: k, resolveFile: f);
// await bootstrap(transport: t); is only prose here
'''),
        isEmpty,
      );
    });
  });
}
