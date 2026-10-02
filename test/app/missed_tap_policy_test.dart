/// A missed tap is a test failure across the whole host suite (Phase 8 Slice 5, D-325).
///
/// `test/flutter_test_config.dart` makes `WidgetController.hitTestWarningShouldBeFatal`
/// true for every file under `test/`, sets it again before every test, and fails a test
/// that leaves it false. These checks hold the rest of the policy:
///
/// * the config does all three of those things;
/// * nothing else under `test/` assigns the flag — no file-wide switch, in either
///   direction, can come back;
/// * a tap that is meant to miss says so at the call (`warnIfMissed: false`) beside a
///   `// missed-tap opt-out:` comment giving the reason;
/// * the device acceptance suite keeps its own fatal setting (D-075), because
///   `integration_test/` is outside this config;
/// * and, behaviourally, a planted miss in this very file fails.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = 'test/flutter_test_config.dart';
const _self = 'test/app/missed_tap_policy_test.dart';
const _marker = '// missed-tap opt-out:';

final _assignment = RegExp(r'hitTestWarningShouldBeFatal\s*=(?!=)');
final _optOut = RegExp(r'warnIfMissed\s*:\s*false');

/// Files other than the config that assign the flag.
List<String> _flagAssignments(Map<String, String> sources) => [
  for (final MapEntry(key: path, value: text) in sources.entries)
    if (path != _config && _assignment.hasMatch(text)) path,
];

/// `warnIfMissed: false` in code, with no reason in the three lines above or on the line.
List<String> _unexplainedOptOuts(Map<String, String> sources) {
  final found = <String>[];
  for (final MapEntry(key: path, value: text) in sources.entries) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      // Prose about the parameter is not a call to it.
      if (lines[i].trimLeft().startsWith('//')) continue;
      if (!_optOut.hasMatch(lines[i])) continue;
      final from = i < 3 ? 0 : i - 3;
      final context = lines.sublist(from, i + 1).join('\n');
      if (!context.contains(_marker)) found.add('$path:${i + 1}');
    }
  }
  return found;
}

/// A text the test layout can tap only if nothing covers it.
Widget _covered() => const MaterialApp(
  home: Stack(
    children: [
      Center(child: Text('covered')),
      Positioned.fill(child: ColoredBox(color: Colors.black)),
    ],
  ),
);

void main() {
  final sources = {
    for (final f in Directory('test').listSync(recursive: true))
      if (f is File && f.path.endsWith('.dart'))
        if (f.path.replaceAll('\\', '/') case final path when path != _self)
          path: f.readAsStringSync(),
  };

  group('the global config', () {
    final config = File(_config).readAsStringSync();

    test('exists, is the only one, and wraps every test file', () {
      expect(config, contains('Future<void> testExecutable('));
      expect(config, contains('await testMain();'));
      final configs = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('flutter_test_config.dart'));
      expect(configs, hasLength(1), reason: 'a nested config would shadow it');
    });

    test('makes a missed tap fatal, before every test, and refuses a leak', () {
      final body = config.split('Future<void> testExecutable(').last;
      final beforeMain = body.split('await testMain();').first;
      expect(
        beforeMain,
        contains('WidgetController.hitTestWarningShouldBeFatal = true;'),
      );
      expect(
        beforeMain,
        contains(
          'setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);',
        ),
      );
      expect(beforeMain, contains('tearDown(() {'));
      expect(beforeMain, contains('fail('));
    });
  });

  group('no file-wide switch', () {
    test('nothing under test/ but the config assigns the flag', () {
      expect(sources, contains(_config), reason: 'the scan reads test/');
      expect(_flagAssignments(sources), isEmpty);
    });

    test('the guard sees a planted file-wide switch', () {
      final planted = {
        ...sources,
        'test/planted_test.dart':
            'void main() => setUpAll(() => '
            'WidgetController.hitTestWarningShouldBeFatal = false);',
      };
      expect(_flagAssignments(planted), ['test/planted_test.dart']);
    });

    test('a comparison is not an assignment', () {
      final planted = {
        'test/reads_test.dart':
            'expect(WidgetController.hitTestWarningShouldBeFatal == true, '
            'isTrue);',
      };
      expect(_flagAssignments(planted), isEmpty);
    });
  });

  group('an opt-out states its reason at the call', () {
    test('every warnIfMissed: false under test/ carries one', () {
      expect(_unexplainedOptOuts(sources), isEmpty);
    });

    test('the guard sees a planted opt-out with no reason', () {
      final planted = {
        'test/planted_test.dart':
            'await tester.tap(find.byKey(k), warnIfMissed: false);\n',
      };
      expect(_unexplainedOptOuts(planted), ['test/planted_test.dart:1']);
    });

    test('the guard accepts a planted opt-out with a reason', () {
      final planted = {
        'test/planted_test.dart':
            '$_marker the barrier is the thing under test\n'
            'await tester.tap(find.byKey(k), warnIfMissed: false);\n',
      };
      expect(_unexplainedOptOuts(planted), isEmpty);
    });
  });

  test('every real-application suite that taps keeps its own fatal setting', () {
    // Outside this config's reach, so each sets it itself: the device acceptance suite
    // since D-075, the Windows shell test since Phase 8 Slice 8.
    for (final path in const [
      'integration_test/device_acceptance_test.dart',
      'integration_test/windows_shell_test.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('WidgetController.hitTestWarningShouldBeFatal = true;'),
        reason: path,
      );
    }
    // And no real-application suite tolerates a miss without a stated reason.
    for (final file in Directory(
      'integration_test',
    ).listSync().whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      expect(
        file.readAsStringSync(),
        isNot(contains('warnIfMissed: false')),
        reason: file.path,
      );
    }
  });

  group('behaviour in a real test', () {
    testWidgets('the flag is fatal when a test starts', (tester) async {
      expect(WidgetController.hitTestWarningShouldBeFatal, isTrue);
    });

    testWidgets('a tap on a covered widget fails the test', (tester) async {
      await tester.pumpWidget(_covered());
      // `tap()` refuses before it returns a future, so the call goes in a closure.
      expect(
        () => tester.tap(find.text('covered')),
        throwsA(
          isA<FlutterError>().having(
            (e) => e.message,
            'message',
            contains('would not receive pointer events'),
          ),
        ),
      );
    });

    testWidgets('an opt-out covers its own call and nothing after it', (
      tester,
    ) async {
      await tester.pumpWidget(_covered());
      // missed-tap opt-out: the planted miss is what this test is about.
      await tester.tap(find.text('covered'), warnIfMissed: false);
      expect(WidgetController.hitTestWarningShouldBeFatal, isTrue);
      expect(
        () => tester.tap(find.text('covered')),
        throwsA(isA<FlutterError>()),
      );
    });
  });
}
