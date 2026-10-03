/// Production surfaces show plain words, never an exception (Phase 9 Slice 3, D-348).
///
/// A raw exception on screen — its class name, its text, a SQLite or Drift message, a
/// provider name, a path, a stack — tells a manager nothing they can act on, and can carry
/// a local file path. The detail belongs in the developer log. This guard reads the
/// production files Slice 3 corrected and refuses the shapes that put an exception on
/// screen, with planted controls proving each detector fires and that a comment or a log
/// call does not trip it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The surfaces Slice 3 corrected (D-343), plus the shared pieces they render through.
const _guarded = [
  'lib/features/masters/presentation/windows_masters_view.dart',
  'lib/features/masters/presentation/android_masters_view.dart',
  'lib/features/masters/presentation/widgets/master_chrome.dart',
  'lib/features/tax/presentation/tax_rates_view.dart',
  'lib/features/vendors/presentation/vendors_view.dart',
  'lib/features/revenue/presentation/revenue_ledger_page.dart',
  'lib/features/expenses/presentation/expense_entry_page.dart',
  'lib/features/placeholder/placeholder_page.dart',
];

/// Removes `//` comments (including `///`), so prose about an error is never mistaken
/// for code rendering one. A `//` inside a string literal is left alone.
String _code(String source) {
  final out = StringBuffer();
  for (final line in source.split('\n')) {
    var inSingle = false;
    var inDouble = false;
    var cut = line.length;
    for (var i = 0; i < line.length - 1; i++) {
      final c = line[i];
      if (c == r'\') {
        i++;
        continue;
      }
      if (c == "'" && !inDouble) inSingle = !inSingle;
      if (c == '"' && !inSingle) inDouble = !inDouble;
      if (!inSingle && !inDouble && c == '/' && line[i + 1] == '/') {
        cut = i;
        break;
      }
    }
    out.writeln(line.substring(0, cut));
  }
  return out.toString();
}

/// The `name: argument` pairs of `developer.log(...)` calls are removed: passing the
/// exception to the log is exactly where it belongs.
String _withoutLogCalls(String code) =>
    code.replaceAll(RegExp(r'developer\.log\([^;]*\);', dotAll: true), '');

/// What an exception looks like on its way to the screen.
final _rawErrorShapes = <String, RegExp>{
  'an exception interpolated into a string': RegExp(
    r'''['"][^'"\n]*\$\{?(error|err|e|exception|ex|failure|cause)\b(?![\w(])''',
  ),
  "an exception's type name": RegExp(r'\.runtimeType\b'),
  "an exception's toString": RegExp(
    r'\b(error|err|e|exception|ex|failure|cause)\.toString\(\)',
  ),
  // A bare exception — not a curated refusal sentence such as `error.message`, which is
  // written for a person (D-113).
  'an exception handed straight to a text widget': RegExp(
    r'\b(Selectable)?Text\(\s*(error|err|e|exception|failure)\s*[,)]',
  ),
  'an AsyncValue error interpolated': RegExp(r'\$\{\w+\.error\}'),
};

List<String> _findings(String source) {
  final code = _withoutLogCalls(_code(source));
  return [
    for (final e in _rawErrorShapes.entries)
      if (e.value.hasMatch(code)) e.key,
  ];
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('the detectors fire, and only where they should', () {
    test('each planted rendering is caught', () {
      const planted = {
        "error: (error, _) => MasterErrorState('\$error'),":
            'an exception interpolated into a string',
        "body: '\${error}',": 'an exception interpolated into a string',
        "_failure = 'Not saved. (\${error.runtimeType})';":
            "an exception's type name",
        'return Text(error.toString());': "an exception's toString",
        'child: SelectableText(error),':
            'an exception handed straight to a text widget',
        "return MasterErrorState('\${graphAsync.error}');":
            'an AsyncValue error interpolated',
      };
      for (final entry in planted.entries) {
        expect(
          _findings(entry.key),
          contains(entry.value),
          reason: 'planted: ${entry.key}',
        );
      }
    });

    test('comments, log calls and ordinary text are not mistaken for one', () {
      const clean = '''
messenger.showSnackBar(SnackBar(content: Text(error.message)));
/// Never Text('\$error') on screen — the detail goes to the log.
// _failure = '(\${error.runtimeType})' was the old wording.
developer.log(
  '\$where could not be read',
  name: 'krishna_mis.masters',
  error: error,
  stackTrace: stack,
);
const sentence = 'The error could not be read. Try again.';
final url = 'https://example.invalid/path';
Text('\${pending == 1 ? 'entry' : 'entries'} waiting')
''';
      expect(_findings(clean), isEmpty);
    });
  });

  group('the corrected production surfaces', () {
    for (final path in _guarded) {
      test('$path renders no exception', () {
        expect(_findings(_read(path)), isEmpty, reason: path);
      });
    }

    test(
      'every master error state passes an approved sentence and a retry',
      () {
        final calls = <String>[];
        for (final path in _guarded) {
          final code = _code(_read(path));
          for (final m in RegExp(
            r'MasterErrorState\(([^;]*?)\)\s*;',
            dotAll: true,
          ).allMatches(code)) {
            // The constructor's own declaration is not a call site.
            if (!m.group(1)!.trimLeft().startsWith('this.')) {
              calls.add(m.group(1)!);
            }
          }
        }
        expect(calls, hasLength(4), reason: 'Windows, Android, tax, vendors');
        for (final args in calls) {
          expect(
            args.trimLeft(),
            matches(
              RegExp(
                r'^(masterStructureUnreadable|taxConfigurationUnreadable|'
                r'suppliersUnreadable)\b',
              ),
            ),
            reason: 'a written sentence, never an exception: $args',
          );
          expect(args, contains('onRetry:'), reason: 'Try again is offered');
        }
      },
    );

    test(
      'the sales ledger error offers a retry that reads the ledger again',
      () {
        final code = _code(_read(_guarded[5]));
        final failure = RegExp(
          r'Widget _readFailure\(.*?\n  \}',
          dotAll: true,
        ).firstMatch(code)!.group(0)!;
        expect(failure, contains('revenueLedgerUnreadable'));
        expect(failure, contains('invalidate(filteredRevenueProvider)'));
      },
    );

    test('the expense save failure states no exception type', () {
      final code = _code(_read(_guarded[6]));
      expect(code, contains('expenseSaveFailed'));
      expect(code, contains('expenseEditSaveFailed'));
      expect(code, isNot(contains('runtimeType')));
    });
  });

  group('the obsolete placeholder wording is gone (D-343)', () {
    test('no reachable UI promises a phase or says it is not built', () {
      final hits = <String>[];
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final code = _code(file.readAsStringSync());
        for (final phrase in [
          'Not built yet',
          'will be built',
          'arrivesIn',
          'Phase 2 — Masters & Permissions',
        ]) {
          if (code.contains(phrase)) hits.add('${file.path}: $phrase');
        }
      }
      expect(hits, isEmpty);
    });

    test('Administration carries the approved V1 sentence', () {
      final placeholder = _read(_guarded[7]);
      expect(
        placeholder.replaceAll(RegExp(r"'\s*\n\s*'"), ''),
        contains(
          'Users, roles, period close and audit review are handled by the '
          'project administrator in this version.',
        ),
      );
      final router = _code(_read('lib/app/routing/app_router.dart'));
      expect(router, contains('notice: administrationNotice'));
    });
  });
}
