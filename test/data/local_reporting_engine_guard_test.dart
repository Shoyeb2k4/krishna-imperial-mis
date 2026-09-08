/// The reporting engine derives nothing (Phase 5 Slice 3, §34).
///
/// Spec §21.2 is explicit: an engine's whole job is *"given a date basis, a date range, a
/// unit scope and a grouping, return summed integer paise"*, and it *"performs no business
/// arithmetic"*. That is the property that shrinks the divergence surface between the local
/// and remote engines from "the P&L" to "did you sum the right rows", and it is the reason
/// the parity suite §21.3 requires can ever pass.
///
/// It is asserted here rather than reviewed, because the way it would be lost is somebody
/// adding one convenient subtraction to a file that already has the numbers to hand — and
/// the result would still be correct on the day it was written. D-068, D-071 and D-077 are
/// all rules nobody evaluated.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source with comments stripped. Prose legitimately explains Net Sales and Operating
/// Profit; a guard that failed on documentation would be worked around rather than fixed.
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final files = Directory('lib/data/reporting')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path.replaceAll(r'\', '/'))
      .toList(growable: false);

  test('the reporting layer exists', () => expect(files, isNotEmpty));

  group('no management formula lives in an engine', () {
    for (final path in files) {
      test('$path derives no figure', () {
        final code = _code(path);

        // Money arithmetic. An engine that adds or subtracts money is computing something,
        // and everything computable from these primitives already has one home.
        for (final forbidden in const [
          'Money.fromPaise(',
          'Money.sum(',
          'Money.zero',
          '.paise',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason:
                '$path uses $forbidden. Primitive sums arrive from the repositories and '
                'derived figures come from domain/finance; an engine touching paise '
                'directly is an engine that has started deriving (spec §21.2)',
          );
        }

        // The formulas themselves, in the shapes they would plausibly be written.
        for (final pattern in <RegExp>[
          RegExp(r'gross\w*\s*-\s*\w*tax', caseSensitive: false),
          RegExp(r'net\w*\s*-\s*\w*expense', caseSensitive: false),
          RegExp(r'\bnetSales\s*='),
          RegExp(r'\boperatingProfit\s*='),
          RegExp(r'\bgrossSales\s*='),
          RegExp(r'\bgst\s*=', caseSensitive: false),
        ]) {
          expect(
            pattern.hasMatch(code),
            isFalse,
            reason: '$path appears to compute a P&L figure: ${pattern.pattern}',
          );
        }

        // Tax. An engine that can see a rate can re-rate an aggregate, which is the
        // one-paisa defect. It is never given one, and must not reach for one.
        for (final forbidden in const [
          'TaxRule',
          'rateBasisPoints',
          'rate_bp',
          'taxRate',
          'TaxRuleSet',
          'TaxRule.compute', // tax extraction
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason: '$path reaches for tax configuration ($forbidden)',
          );
        }

        // Percentages, and floating point anywhere near them.
        expect(
          RegExp(r'\bdouble\b').hasMatch(code),
          isFalse,
          reason: '$path names double',
        );
        expect(
          code.contains('percentage'),
          isFalse,
          reason: '$path computes a percentage',
        );
        expect(
          code.contains('MarginRatio'),
          isFalse,
          reason: '$path constructs a margin; PnlResult derives it',
        );

        // Dates. Business-date and financial-year derivation are the domain's.
        for (final forbidden in const [
          'fromInstant',
          'BusinessDayCutoff',
          'FinancialYear(',
          'DateTime.now',
        ]) {
          expect(
            code.contains(forbidden),
            isFalse,
            reason:
                '$path derives a date. The engine receives a normalised ReportRange and '
                'reads stored pnl_date values (D-019, D-067)',
          );
        }
      });
    }
  });

  test('the engine delegates to the one calculator', () {
    // The complement of everything above: it is not enough that the engine computes
    // nothing, it has to be handing the primitives somewhere. If this ever stopped being
    // true the tests above would still pass over a file that did nothing at all.
    final engine = _code('lib/data/reporting/reporting_engine.dart');
    expect(engine, contains('Pnl.compute('));
    expect(
      engine,
      contains('Pnl.consolidate('),
      reason: 'consolidation has one implementation and it is not in an engine',
    );
  });

  test('both engines are that one orchestration, not two copies of it', () {
    // Spec §21.2 leaves an engine nothing to differ about except the rows it sums, so the
    // two are the same code over two sources. Asserted, because the alternative — writing
    // the orchestration twice so the parity suite has two copies to compare — would test a
    // duplication this design exists to avoid, on the one axis that cannot go wrong, while
    // leaving the axis that can untested (D-185).
    for (final path in const [
      'lib/data/reporting/local_reporting_engine.dart',
      'lib/data/reporting/remote_reporting_engine.dart',
    ]) {
      final code = _code(path);
      expect(
        code,
        contains('extends ReportingEngine'),
        reason: '$path re-implements the orchestration instead of sharing it',
      );
      expect(
        code.contains('Pnl.compute('),
        isFalse,
        reason: '$path has acquired a second copy of the calculation path',
      );
    }
  });

  test('the remote engine cannot write anything', () {
    // The remote engine exists to be an independent answer. One that filled the cache on
    // the way past would make the two sources agree because one had just overwritten the
    // other — a parity suite proving only that a copy equals its original (§30).
    for (final path in const [
      'lib/data/reporting/remote_reporting_engine.dart',
      'lib/data/remote/remote_reporting_source.dart',
    ]) {
      final code = _code(path);
      for (final forbidden in const [
        'ReportingCache',
        'ReportingSync',
        'AppDatabase',
        'applyYear(',
        'pruneYear(',
        'customStatement',
        'INSERT',
        'UPDATE ',
        'DELETE',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              '$path reaches for $forbidden — the remote read is independent of the '
              'cache, and independence is what makes the parity comparison mean anything',
        );
      }
    }
  });

  test('the source delegates to the canonical repository predicates', () {
    // Slice 1 put the canonical rule — accepted, not voided, not scope-revoked — in one
    // predicate builder per engine (D-168). A source writing its own SQL would be a second
    // place for that to live, and the two had already drifted apart once.
    final source = _code('lib/data/reporting/drift_reporting_source.dart');
    expect(source, contains('contributionTotals('));
    // A SQL statement shape, not the bare words: `from` and `where` are ordinary Dart
    // identifiers, and a guard that fired on a local variable named `from` would be
    // deleted rather than fixed.
    expect(
      RegExp(
        r'\bselect\b[\s\S]{0,200}?\bfrom\b',
        caseSensitive: false,
      ).hasMatch(source),
      isFalse,
      reason:
          'the source writes SQL of its own; the canonical predicate would then have '
          'two homes, which is the defect Slice 1 existed to close',
    );
  });

  test('no process-level cached report exists', () {
    // Every call carries its own scope and range. A cached "latest P&L" is how a user
    // switch or a confirmed revocation ends up showing one person another's figures
    // (D-074).
    for (final path in files) {
      final code = _code(path);
      expect(
        RegExp(
          r'\bstatic\s+\w*\s*(PnlResult|ReportEnvelope|PnlOutcome)',
        ).hasMatch(code),
        isFalse,
        reason: '$path holds a report in static state',
      );
      expect(
        RegExp(r'\b(late\s+)?\w*\s*_cached\w*').hasMatch(code),
        isFalse,
        reason: '$path caches something across calls',
      );
    }
  });
}
