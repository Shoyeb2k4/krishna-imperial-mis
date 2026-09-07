/// `domain/finance` is pure, and stays pure.
///
/// The directive requires the calculation specification to be *"pure Dart over integer
/// paise, with no dependency on Drift, Supabase or Flutter"* (spec §21.1). That is a
/// property of every file in the directory, including the ones nobody has written yet, so
/// it is asserted over the directory rather than reviewed per file — the same shape as
/// `test/app/no_hardcoded_authority_test.dart`.
///
/// A comment saying "keep this pure" is the kind of rule this project has repeatedly found
/// nobody evaluates (D-068, D-071, D-077).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

typedef _Source = ({String path, String source});

List<_Source> _sourcesIn(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map(
      (f) => (path: f.path.replaceAll(r'\', '/'), source: f.readAsStringSync()),
    )
    .toList(growable: false);

void main() {
  final finance = _sourcesIn('lib/domain/finance');

  test('the directory exists and has something in it', () {
    expect(
      finance,
      isNotEmpty,
      reason:
          'lib/domain/finance is mandated by CLAUDE.md and spec §21.1 as the one home '
          'of derived financial arithmetic',
    );
  });

  group('nothing here knows about storage, transport or a screen', () {
    // Substring matches on the import line, so a transitive dependency is caught too:
    // importing something that itself imports Drift still names it in nobody's file, but
    // importing Drift directly is the failure this catches and the one that happens.
    const forbidden = <String, String>{
      'package:drift/': 'Drift — the engine fetches; the domain derives',
      'package:sqlite3/': 'SQLite',
      'package:supabase': 'Supabase — the domain has no network',
      'package:flutter/': 'Flutter — a calculator has no widgets',
      'package:flutter_riverpod/': 'Riverpod — no providers in the domain',
      'package:riverpod/': 'Riverpod',
      'dart:io': 'platform I/O',
      'dart:ui': 'the rendering layer',
      'package:krishna_mis/data/':
          'the data layer — the dependency points the other way',
      'package:krishna_mis/features/':
          'a feature — the domain is underneath them',
      'package:krishna_mis/app/': 'application bootstrap',
    };

    for (final file in finance) {
      test('${file.path} imports nothing forbidden', () {
        final imports = file.source
            .split('\n')
            .where((l) => l.trimLeft().startsWith('import '))
            .toList();
        for (final entry in forbidden.entries) {
          expect(
            imports.where((l) => l.contains(entry.key)),
            isEmpty,
            reason: '${file.path} imports ${entry.key} (${entry.value})',
          );
        }
      });
    }
  });

  group('no binary floating point anywhere near money', () {
    for (final file in finance) {
      test('${file.path} declares no double and no floating literal', () {
        // Strip comments and doc comments first: prose legitimately says "double" and
        // writes decimals like 56.53, and a grep that failed on those would be trained
        // away rather than fixed.
        final code = file.source
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');

        expect(
          RegExp(r'\bdouble\b').hasMatch(code),
          isFalse,
          reason:
              '${file.path} names `double`. Currency is integer paise everywhere '
              '(D-002); a margin is an exact ratio and is divided only for display',
        );
        expect(
          RegExp(r'\btoDouble\s*\(').hasMatch(code),
          isFalse,
          reason: '${file.path} converts to floating point',
        );
        expect(
          RegExp(r'(?<![\w.])\d+\.\d+(?![\w.])').hasMatch(code),
          isFalse,
          reason: '${file.path} contains a floating-point literal',
        );
        expect(
          RegExp(r'(?<![/~])/(?![/*])').hasMatch(
            // Division that is not integer division. `~/` is fine; `/` on ints yields a
            // double in Dart, which is exactly the accident this forbids.
            code.replaceAll(RegExp(r"'[^']*'"), "''"),
          ),
          isFalse,
          reason:
              '${file.path} uses `/`, which returns a double in Dart even between two '
              'ints. Integer division is `~/`',
        );
      });
    }
  });

  test('the test oracle is not shipped', () {
    // ARCHITECTURE §6.3's reference implementation is an independent check, not business
    // logic. If lib/ ever referenced it, the parity suite would be comparing production
    // against itself.
    final lib = _sourcesIn('lib');
    final offenders = lib
        .where((f) => f.source.contains('pnl_reference'))
        .map((f) => f.path);
    expect(
      offenders,
      isEmpty,
      reason:
          'the reference oracle lives under test/ and exists to disagree with '
          'production, not to be called by it',
    );
  });

  test('the oracle does not call the production calculator', () {
    // Code only. The oracle's documentation legitimately explains how it differs from
    // `Pnl.compute`, and a guard that failed on that prose would be deleted rather than
    // fixed.
    final oracle = File('test/support/pnl_reference.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    for (final forbidden in const [
      'domain/finance/pnl.dart',
      'Pnl.compute',
      'Pnl.consolidate',
      'PnlResult',
    ]) {
      expect(
        oracle.contains(forbidden),
        isFalse,
        reason:
            'the oracle references $forbidden. An oracle that delegates proves a '
            'function equals itself (ARCHITECTURE §6.3)',
      );
    }
  });
}
