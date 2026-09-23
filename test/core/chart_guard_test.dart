/// What the chart layer is, and is not (Phase 6 Slice 5).
///
/// Charts are presentation. Every rule below is a property of the directory rather than
/// of a file somebody remembered to check, and each is paired with a planted violation,
/// because a guard that has never been seen to fail is a guard nobody can rely on
/// (D-139, D-187, D-201, D-205).
///
/// The rule the whole layer exists to protect: **a coordinate is derived from an exact
/// figure and is never read back into one.** A chart may position a mark from a number; it
/// may not state a number it got from a position.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dir = 'lib/core/design/charts';
const _values = '$_dir/chart_values.dart';
const _series = '$_dir/chart_series.dart';

const _widgets = [
  '$_dir/trend_line_chart.dart',
  '$_dir/profit_bar_chart.dart',
  '$_dir/ranked_bar_chart.dart',
  '$_dir/comparison_bar_chart.dart',
];

/// Source with `//` comments stripped: prose legitimately names the very things these
/// rules forbid, which is how a guard ends up reading its own explanation as a violation
/// (D-139, and again in D-205).
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

List<String> _dartFiles() => Directory(_dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.path.replaceAll(r'\', '/'))
    .toList(growable: false);

void main() {
  late List<String> files;

  setUpAll(() => files = _dartFiles());

  test('the chart layer exists, and every approved family is in it', () {
    expect(files, isNotEmpty);
    for (final path in ['$_dir/charts.dart', _values, _series, ..._widgets]) {
      expect(files, contains(path));
    }
  });

  // ── 16 · no report, no database, no server ──────────────────────────────

  test('a chart reaches no report, no database and no server', () {
    for (final path in files) {
      final code = _code(path);
      for (final forbidden in const [
        'package:supabase',
        'package:drift',
        'package:krishna_mis/data/',
        'LocalReportingEngine',
        'RemoteReportingEngine',
        'ReportingEngine',
        'ReportingGateway',
        'AppDatabase',
        'customSelect',
        'customStatement',
        'rpc(',
        'Repository',
        'reporting_primitives',
        'reporting_snapshot',
        'CanonicalCacheLock',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              '$path reaches past presentation ($forbidden). A chart is handed values '
              'that were already read and already decided',
        );
      }
    }
  });

  test('a chart decides no authority, no coverage and no freshness', () {
    for (final path in files) {
      final code = _code(path);
      for (final forbidden in const [
        'PnlAuthority',
        'Capability.',
        'Principal',
        'hasCapability',
        'reports.view',
        'revenue.view',
        'expense.view',
        'ReportingCoverage',
        'ReportingFreshness',
        'ReportingSnapshotEvidence',
        "'owner'",
        "'manager'",
        "'accountant'",
        "'data_entry'",
        'RoleTemplates',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              '$path decides something that is not presentation ($forbidden). '
              'Authority, coverage and freshness arrive decided (D-164, D-188)',
        );
      }
    }
  });

  test('a chart resolves no tax and re-rates nothing', () {
    for (final path in files) {
      final code = _code(path);
      for (final forbidden in const [
        'TaxRule',
        'TaxTreatment',
        'RevenueTaxFacts',
        'rateBp',
        'rate_bp',
        'EnteredBasis',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: '$path names $forbidden',
        );
      }
    }
  });

  // ── the calculation boundary ────────────────────────────────────────────

  test('a chart calls none of the calculating entry points', () {
    for (final path in files) {
      final code = _code(path);
      for (final forbidden in const [
        'Pnl.compute(',
        'Pnl.consolidate(',
        'PnlComparison.compare(',
        'DashboardTrends.buckets(',
        'DashboardTrends.series(',
        'DashboardTrends.grainsFor(',
        'DashboardPeriods.',
        'DailyNetSalesRanking.',
        'TopN.group(',
        'TopN.expenseCategories(',
        'TopN.revenueCategories(',
        'TopN.departments(',
        'Money.sum(',
        'multiplyByRatio(',
        'allocate(',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              '$path computes a financial figure ($forbidden). Every one of these '
              'already happened in domain/finance, and a second answer here would be '
              'a second answer to a financial question',
        );
      }
    }
  });

  test('a chart never re-orders what the domain ranked', () {
    for (final path in files) {
      expect(
        _code(path).contains('.sort('),
        isFalse,
        reason:
            '$path sorts. A ranked chart draws the domain\'s order and its '
            'membership; re-ranking here would be a second answer to "which are the '
            'largest" (D-258)',
      );
    }
  });

  test('a chart derives no date and formats none', () {
    for (final path in files) {
      final code = _code(path);
      for (final forbidden in const [
        'BusinessDate.of(',
        'addDays(',
        'weekdayOf(',
        'DateTime.now',
        'DateTime(',
        'FinancialYear',
        'Duration(',
        "'Jan'",
        "'Apr'",
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              '$path derives or formats a date ($forbidden). A position\'s name '
              'arrives as a label from the surface, which owns the date wording',
        );
      }
    }
  });

  // ── 2 · 8 · money is never read back from a coordinate ──────────────────

  test('a coordinate is never turned back into money', () {
    // The only place paise become money again is the axis tick, which formats its own
    // integer. Everywhere else, a figure is the prepared label it arrived with.
    final constructions = [
      for (final path in files)
        if (_code(path).contains('Money.fromPaise(')) path,
    ];
    expect(
      constructions,
      [_values],
      reason:
          'only ChartAxis may build a Money, and only from a tick\'s own integer paise',
    );
    expect(
      'Money.fromPaise('.allMatches(_code(_values)).length,
      1,
      reason: 'one construction: the axis tick label',
    );

    for (final path in files) {
      final code = _code(path);
      for (final forbidden in const [
        '.toInt()',
        'spot.y',
        'rod.toY',
        'Money.tryParse(',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              '$path reads a figure back out of a coordinate ($forbidden). A tooltip '
              'and a readout take the touched index and look up the prepared label',
        );
      }
    }
  });

  test(
    'exactly one place turns a coordinate into anything, and it is an index',
    () {
      final rounding = [
        for (final path in files)
          if (_code(path).contains('.round()')) path,
      ];
      expect(
        rounding,
        ['$_dir/chart_selection.dart'],
        reason:
            'the only conversion from a coordinate in the layer is a position to a '
            'category index, which carries no money',
      );
      final selection = _code('$_dir/chart_selection.dart');
      expect('.round()'.allMatches(selection).length, 1);
      expect(
        selection,
        contains('static int indexAt(double position) => position.round();'),
        reason: 'it is named, so a reviewer sees it rather than finding it',
      );
      // …and every axis that carries money uses it for the category axis only.
      for (final path in _widgets) {
        final code = _code(path);
        if (!code.contains('ChartSelection.indexAt(')) continue;
        expect(
          code.contains('labelFor('),
          isTrue,
          reason: '$path must still label its value axis from exact ticks',
        );
      }
    },
  );

  test(
    'every chart states its figure by looking it up, and formats none itself',
    () {
      for (final path in _widgets) {
        final code = _code(path);
        expect(
          code.contains('ChartSelection.tooltipTextFor(') ||
              code.contains('ChartReadout('),
          isTrue,
          reason: '$path no longer states its figure through the shared lookup',
        );
        expect(
          code.contains('.format('),
          isFalse,
          reason:
              '$path formats money itself. Formatting happens once, when the exact '
              'figure becomes a ChartAmount',
        );
      }
      // …and the two charts fl_chart draws prove the lookup by index explicitly.
      for (final path in const [_widgets, <String>[]].first.take(2)) {
        expect(_code(path), contains('ChartSelection.tooltipTextFor('));
      }
    },
  );

  test('the exact source travels with every plotted value', () {
    final values = _code(_values);
    expect(values, contains('final Money source;'));
    expect(
      values,
      contains('double get plotted => source.paise.toDouble();'),
      reason:
          'the coordinate is a getter over the exact figure, so there is no way in '
          'from a double (the move D-094 made for RevenueTaxFacts)',
    );
    expect(
      values.contains('ChartAmount._({'),
      isTrue,
      reason:
          'the only constructor is private, so nothing outside can build a ChartAmount '
          'whose label disagrees with its source',
    );
  });

  // ── 17 · one wording for a measure ──────────────────────────────────────

  test('a chart calls a measure what both P&L surfaces call it', () {
    final series = _code(_series);
    final surfaces = [
      File(
        'lib/features/profit_and_loss/presentation/profit_and_loss_page.dart',
      ).readAsStringSync(),
      File(
        'lib/features/profit_and_loss/presentation/mobile_profit_and_loss_page.dart',
      ).readAsStringSync(),
    ];
    for (final name in const ['Net Sales', 'Operating Profit']) {
      expect(series, contains("'$name'"));
      for (final surface in surfaces) {
        expect(
          surface,
          contains("'$name'"),
          reason:
              'a chart and a figure table must never call the same measure two '
              'different things (D-232)',
        );
      }
    }
  });

  // ── 20 · one charting package, pinned ───────────────────────────────────

  group('the chart package', () {
    late String pubspec;
    late String lock;

    setUpAll(() {
      pubspec = File('pubspec.yaml').readAsStringSync();
      lock = File('pubspec.lock').readAsStringSync();
    });

    test('is pinned to an exact version, not a range', () {
      expect(
        RegExp(r'^  fl_chart: 1\.2\.0\s*$', multiLine: true).hasMatch(pubspec),
        isTrue,
        reason:
            'fl_chart is pinned exactly. A chart package\'s rendering is what several '
            'assertions read, so an unreviewed minor bump is a silent change to what '
            'a manager sees',
      );
      expect(
        pubspec.contains('fl_chart: ^'),
        isFalse,
        reason: 'a caret would let a minor version arrive unreviewed',
      );
    });

    test('resolves to the version it is pinned to', () {
      // The package's own block: its header line, and every line indented under it.
      final lines = lock.split('\n');
      final start = lines.indexOf('  fl_chart:');
      expect(start, isNot(-1), reason: 'fl_chart is not in the lockfile');
      final block = lines
          .skip(start + 1)
          .takeWhile((l) => l.startsWith('    '))
          .join(' ');
      expect(
        block,
        contains('version: "1.2.0"'),
        reason: 'the lockfile records the pinned version, not a resolved range',
      );
    });

    test('is documented, with the toolchain it was verified against', () {
      expect(pubspec, contains('Flutter 3.44.9'));
      expect(
        File('docs/ARCHITECTURE.md').readAsStringSync(),
        contains('fl_chart 1.2.0'),
        reason: 'the dependency decision is recorded, not merely made',
      );
    });

    test('is the only charting package in the project', () {
      for (final other in const [
        'charts_flutter',
        'syncfusion_flutter_charts',
        'graphic:',
        'flutter_echarts',
        'chart_sparkline',
        'k_chart',
      ]) {
        expect(
          pubspec.contains(other),
          isFalse,
          reason: 'a second chart package',
        );
        expect(lock.contains(other), isFalse, reason: 'a second chart package');
      }
    });

    test('is imported only by the chart layer', () {
      final leaked = <String>[];
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        final path = file.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart') || path.startsWith(_dir)) continue;
        if (file.readAsStringSync().contains('package:fl_chart')) {
          leaked.add(path);
        }
      }
      expect(
        leaked,
        isEmpty,
        reason:
            'a surface must talk to the chart layer, never to the package: swapping '
            'the package must not be a change to a screen',
      );
    });
  });

  // ── Who may wire the charts in ──────────────────────────────────────────

  /// **Deliberately changed in Slice 6.** It asserted the layer was wired into no screen
  /// at all, and said in as many words that it was the assertion Slice 6 would have to
  /// change. It is narrowed rather than deleted (D-237's move): the charts are the
  /// dashboard's presentation, so a surface that draws one belongs to the dashboard
  /// feature, and a transaction ledger or a master screen that started plotting money
  /// would still be caught.
  //
  // Slice 8 narrows it once more, to the one other surface D-260 approved: the Windows
  // Analytics workspace, which draws the same charts over the same prepared view (D-277).
  // Only its three analysis sections may draw; the workspace page and its state may not.
  test('only the dashboard and analytics surfaces draw charts', () {
    const permitted = [
      'lib/features/dashboard/',
      'lib/features/analytics/presentation/revenue_analysis.dart',
      'lib/features/analytics/presentation/expense_analysis.dart',
      'lib/features/analytics/presentation/business_comparison.dart',
    ];
    final wired = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart') || path.startsWith(_dir)) continue;
      if (permitted.any(path.startsWith)) continue;
      if (file.readAsStringSync().contains('core/design/charts/')) {
        wired.add(path);
      }
    }
    expect(
      wired,
      isEmpty,
      reason:
          'the chart layer is the dashboard presentation. A surface outside the '
          'dashboard and the three analytics sections that draws one is a second '
          'analytics surface nobody approved (D-257, D-260, D-277)',
    );
  });

  test('and the dashboard actually draws them', () {
    // The complement, so the rule above cannot be satisfied by there being no charts at
    // all — which is how a narrowed guard quietly stops checking anything (D-139).
    final drawing = Directory('lib/features/dashboard')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              f.readAsStringSync().contains('core/design/charts/'),
        );
    expect(drawing, isNotEmpty);
    // And each permitted analytics section really does draw one.
    for (final path in const [
      'lib/features/analytics/presentation/revenue_analysis.dart',
      'lib/features/analytics/presentation/expense_analysis.dart',
      'lib/features/analytics/presentation/business_comparison.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('core/design/charts/'),
        reason: '$path is permitted to draw a chart and no longer does',
      );
    }
  });

  // ── the guards fail when they should ────────────────────────────────────

  group('the guard fails when it should', () {
    test('a planted report read is seen', () {
      const planted = 'final r = await LocalReportingEngine().report(req);';
      expect(planted.contains('LocalReportingEngine'), isTrue);
    });

    test('a planted capability decision is seen', () {
      const planted = 'if (PnlAuthority.mayReadUnit(p, id)) draw();';
      expect(planted.contains('PnlAuthority'), isTrue);
    });

    test('a planted re-ranking is seen', () {
      const planted = 'final ordered = [...lines]..sort((a, b) => 0);';
      expect(planted.contains('.sort('), isTrue);
    });

    test('a planted coordinate-to-money conversion is seen', () {
      const planted =
          "Text(MoneyFormatter.standard.format(Money.fromPaise(spot.y.toInt())))";
      expect(planted.contains('Money.fromPaise('), isTrue);
      expect(planted.contains('.toInt()'), isTrue);
      expect(planted.contains('spot.y'), isTrue);
      expect(planted.contains('.format('), isTrue);
    });

    test('a planted date derivation is seen', () {
      const planted = "final label = '\${_months[d.month - 1]} \${d.year}';";
      expect(planted.contains('_months['), isTrue);
    });

    test('a planted second chart package is seen', () {
      const planted = '  syncfusion_flutter_charts: ^27.0.0';
      expect(planted.contains('syncfusion_flutter_charts'), isTrue);
    });

    test('a planted caret pin is seen', () {
      const planted = '  fl_chart: ^1.2.0';
      expect(
        RegExp(r'^  fl_chart: 1\.2\.0\s*$', multiLine: true).hasMatch(planted),
        isFalse,
      );
      expect(planted.contains('fl_chart: ^'), isTrue);
    });

    test('a planted chart on a surface outside the dashboard is seen', () {
      const permitted = ['lib/features/dashboard/'];
      const planted =
          "import 'package:krishna_mis/core/design/charts/charts.dart';";
      // The rule is the pair: the import, and a path the exclusion does not cover.
      const ledger =
          'lib/features/expenses/presentation/expense_ledger_page.dart';
      expect(planted.contains('core/design/charts/'), isTrue);
      expect(permitted.any(ledger.startsWith), isFalse);
      expect(
        permitted.any('lib/features/dashboard/presentation/x.dart'.startsWith),
        isTrue,
      );
    });
  });
}
