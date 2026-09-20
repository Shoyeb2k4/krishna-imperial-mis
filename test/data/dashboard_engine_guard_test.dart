/// The dashboard engine adds a reading strategy and nothing else (Phase 6 Slice 3).
///
/// A dashboard is where a second copy of the rules would be most tempting: the engine has
/// two results in hand and every figure a comparison needs, so one convenient subtraction
/// would work, and would still be correct on the day it was written. The directory guard
/// already forbids money arithmetic here; this adds the complement — the engine must be
/// seen to **delegate** to the domain rules, and must not have grown a parallel
/// implementation of any of them.
///
/// D-068, D-071 and D-077 are all rules nobody evaluated. This one is evaluated.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _engine = 'lib/data/reporting/dashboard_engine.dart';

/// Source with comments stripped. Prose legitimately names the rules the engine calls.
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  late String code;

  setUpAll(() => code = _code(_engine));

  test('the engine exists', () {
    expect(File(_engine).existsSync(), isTrue);
  });

  test('every dashboard rule is delegated to domain/finance', () {
    // The complement of "it derives nothing": it is not enough that the engine computes
    // no figure, it has to be handing the work to the one place each rule lives.
    for (final call in const [
      'PnlComparison.compare(',
      'DashboardTrends.buckets(',
      'DashboardTrends.series(',
      'DailyNetSalesRanking.rank(',
      'TopN.expenseCategories(',
      'TopN.revenueCategories(',
    ]) {
      expect(
        code,
        contains(call),
        reason: '$_engine no longer delegates to $call',
      );
    }
  });

  test('no dashboard rule is re-implemented here', () {
    // Constructing any of these would mean the engine had decided something the domain
    // decides: which bucket a point belongs to, whether a point is a gap, what a
    // comparison says, which day was best, or how lines are grouped.
    for (final constructed in const [
      'TrendBucket(',
      'TrendValue(',
      'TrendGap(',
      'TrendSeries(',
      'MoneyComparisonAvailable(',
      'MoneyComparisonUnavailable(',
      'PercentChangeRatio(',
      'MarginMovement(',
      'DailyRanked(',
      'DailyRankingUnavailable(',
      'TopNGrouped(',
      'TopNRefused(',
      'RankedLine(',
    ]) {
      expect(
        code.contains(constructed),
        isFalse,
        reason:
            '$_engine constructs $constructed, which is a rule domain/finance owns',
      );
    }
  });

  test('there is one reporting path, and the dashboard uses it', () {
    expect(
      code,
      contains('reports.report('),
      reason: 'the dashboard reads through the Phase 5 engine',
    );
    for (final forbidden in const [
      'Pnl.compute(',
      'Pnl.consolidate(',
      'ReportingFactsSource',
      'factsForScope(',
      'ReportingCache',
      'AppDatabase',
      'customSelect',
    ]) {
      expect(
        code.contains(forbidden),
        isFalse,
        reason:
            '$_engine reaches past the reporting engine ($forbidden). A second read '
            'path is a second place for the canonical predicate to be forgotten (D-168)',
      );
    }
  });

  test('the whole view is one lock span', () {
    // Not "it takes the lock" — *once*. Two spans would let a synchronisation land
    // between them, which is precisely the interleaving the lock exists to prevent, and
    // a dashboard is many more reads than a P&L screen (D-188, D-241).
    //
    // What this cannot see, and is not claimed to: whether the reads are *inside* that
    // span. A count is a count. Moving the reads out while leaving one `lock.run` behind
    // passes here and fails the engine's own suite — "a synchronisation cannot land
    // between two of its reads" — which is where that property is proven. Stated rather
    // than left for a later reader to discover the guard was weaker than it looked.
    expect(code, contains('lock.run('));
    expect(
      'lock.run('.allMatches(code).length,
      1,
      reason:
          '$_engine takes the lock more than once. The lock is not re-entrant and a '
          'view split across two spans is a view of two moments',
    );
  });

  test('nothing is read before the span opens', () {
    // The half of containment a text guard *can* establish: between entering `build` and
    // taking the lock there is no `await` at all, so no read can slip in ahead of it.
    final build = code.indexOf('Future<DashboardView> build(');
    final span = code.indexOf('lock.run(', build);
    expect(build, isNonNegative, reason: 'build has been renamed');
    expect(span, greaterThan(build), reason: 'the span is not inside build');
    // Exactly one: the `await` that belongs to `lock.run` itself, and nothing before it.
    expect(
      'await '.allMatches(code.substring(build, span)).length,
      1,
      reason:
          '$_engine awaits something before it takes the lock. Whatever that is, it is '
          'outside the span the rest of the view is read in',
    );
  });

  test('the engine resolves no period and derives no date', () {
    // The pair arrives already resolved from each property's own business date (D-225,
    // D-252). An engine that resolved a relative period would be a second answer to
    // "what is today here", and the directory guard already forbids reading a clock.
    for (final forbidden in const [
      'DashboardPeriods.',
      'forToday(',
      'forUnits(',
      'weekdayOf(',
      'BusinessDate.of(',
      'addDays(',
    ]) {
      expect(
        code.contains(forbidden),
        isFalse,
        reason: '$_engine derives a date or resolves a period ($forbidden)',
      );
    }
  });

  test('the engine decides no authority', () {
    // Who may read what is PnlAuthority's for the surface and the boundary's for the
    // truth (D-164, D-187, Slice 7). An engine with an opinion about it would be a third.
    for (final forbidden in const [
      'Capability.',
      'PnlAuthority',
      'Principal',
      'canAnywhere(',
    ]) {
      expect(
        code.contains(forbidden),
        isFalse,
        reason: '$_engine decides authority ($forbidden)',
      );
    }
  });

  test('a distinct range is read once', () {
    // The behavioural proof is in the engine's own suite; this pins the mechanism, so a
    // refactor to a list cannot quietly double the cost of the busiest dashboard.
    expect(
      code,
      contains('<ReportRange>{'),
      reason:
          'the plan is a set of ranges. A daily trend and a daily ranking over one '
          'period are the same reads and must be paid for once',
    );
  });

  group('the guard itself fails when it should', () {
    // Each planted violation is checked against the same predicates the tests above use,
    // so a pattern that had stopped matching would be caught here rather than reported
    // as a pass (D-139, D-187, D-201).
    test('a planted re-implementation is seen', () {
      const planted = 'final x = TrendValue(bucket: b, amount: m);';
      expect(planted.contains('TrendValue('), isTrue);
    });

    test('a planted second lock span is seen', () {
      const planted =
          'await lock.run(() async {}); await lock.run(() async {});';
      expect('lock.run('.allMatches(planted).length, 2);
    });

    test('a planted date derivation is seen', () {
      const planted = 'final d = BusinessDate.of(2026, 9, 17);';
      expect(planted.contains('BusinessDate.of('), isTrue);
    });

    test('a dropped delegation is seen', () {
      const planted = 'return null;';
      expect(planted.contains('PnlComparison.compare('), isFalse);
    });
  });
}
