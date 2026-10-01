/// A one-shot read never waits on a provider's automatic retries (Phase 8 Slice 3).
///
/// `await ref.read(p.future)` in an action waits through every retry `p` makes — about 38
/// seconds — and, when nothing watches `p`, never settles at all, because Riverpod re-runs
/// only a provider somebody is watching. So every such read in `lib/` must name a provider
/// that answers once: one declared with `retry: noAutomaticRetry` or an explicit `null`
/// retry. Watching (`ref.watch(p.future)`) inside another provider is not a one-shot read
/// and is not covered here.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _oneShotRead = RegExp(r'ref\s*\.read\(\s*(\w+)\s*\.future\s*\)');

/// The provider names `lib/` reads once through `.future`, with where.
Map<String, List<String>> _oneShotReads(Map<String, String> sources) {
  final reads = <String, List<String>>{};
  for (final MapEntry(key: path, value: text) in sources.entries) {
    for (final m in _oneShotRead.allMatches(text)) {
      reads.putIfAbsent(m.group(1)!, () => []).add(path);
    }
  }
  return reads;
}

/// The whole declaration of [name], from `final name =` to its closing line.
String? _declaration(String name, Map<String, String> sources) {
  final pattern = RegExp(
    'final\\s+$name\\s*=\\s*FutureProvider[\\s\\S]*?^[)}][^\\n]*;',
    multiLine: true,
  );
  for (final text in sources.values) {
    if (pattern.firstMatch(text) case final m?) return m.group(0);
  }
  return null;
}

bool _answersOnce(String declaration) =>
    declaration.contains('retry: noAutomaticRetry') ||
    RegExp(r'retry:\s*\(_,\s*_\)\s*=>\s*null').hasMatch(declaration);

List<String> _violations(Map<String, String> sources) => [
  for (final MapEntry(key: name, value: where) in _oneShotReads(
    sources,
  ).entries)
    if (_declaration(name, sources) case final d?)
      if (!_answersOnce(d)) '$name (read once in ${where.toSet().join(', ')})',
];

void main() {
  final sources = {
    for (final f in Directory('lib').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        f.path.replaceAll('\\', '/'): f.readAsStringSync(),
  };

  test('every provider read once through .future answers once', () {
    expect(_oneShotReads(sources), isNotEmpty, reason: 'the scan found reads');
    expect(_violations(sources), isEmpty);
  });

  test('the guard sees a planted one-shot read of a retrying provider', () {
    final planted = {
      ...sources,
      'lib/planted.dart': '''
final plantedProvider = FutureProvider<int>((ref) async {
  return 1;
});

class Planted extends Notifier<int> {
  @override
  int build() => 0;
  Future<void> act() async => state = await ref.read(plantedProvider.future);
}
''',
    };
    expect(_violations(planted), [contains('plantedProvider')]);

    final answered = {
      ...planted,
      'lib/planted.dart': planted['lib/planted.dart']!.replaceFirst(
        '});',
        '}, retry: noAutomaticRetry);',
      ),
    };
    expect(_violations(answered), isEmpty);
  });
}
