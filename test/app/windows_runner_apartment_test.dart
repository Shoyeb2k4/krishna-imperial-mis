/// The Windows runner keeps its main thread single-threaded after a print (D-308).
///
/// The first print dialog makes Windows' print stack release this thread's COM
/// apartment once without taking it. With one reference the next Save As deadlocks, so
/// the runner holds two. The behaviour is proven by the `p7-windows-repro` acceptance
/// phase in the real executable; this guard stops the second reference being tidied
/// away as a duplicate line.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('windows/runner/main.cpp').readAsStringSync();

  // Code only: the comment that explains the fix names the call too.
  final code = source
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('the runner takes two single-threaded apartment references', () {
    final references = RegExp(
      r'CoInitializeEx\(\s*nullptr\s*,\s*COINIT_APARTMENTTHREADED\s*\)',
    ).allMatches(code);
    expect(references, hasLength(2), reason: 'D-308');
    expect(
      source,
      contains('D-308'),
      reason: 'the reason is written beside it',
    );
  });

  test('the runner never joins the multithreaded apartment', () {
    expect(code, isNot(contains('COINIT_MULTITHREADED')));
  });

  test('both references come before the engine starts', () {
    final second = RegExp(
      r'CoInitializeEx\(\s*nullptr\s*,\s*COINIT_APARTMENTTHREADED\s*\)',
    ).allMatches(code).last.start;
    expect(second, lessThan(code.indexOf('flutter::DartProject')));
  });
}
