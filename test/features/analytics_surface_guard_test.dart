/// What the Windows Analytics workspace is, and is not (Phase 6 Slice 8).
///
/// The workspace arranges prepared dashboard values into three analysis sections beside
/// the existing Profit & Loss. These rules hold it there: it reaches no database, no
/// repository and no reporting engine of its own; it works out no figure; it decides no
/// authority and names no role; it carries no Owner Accounts value; it exports and prints
/// nothing; and it is not a second P&L.
///
/// The token lists are the dashboard guard's own (`surface_guard_tokens.dart`), so the two
/// guards cannot drift apart. Every rule is paired with a planted violation, because a
/// guard nobody has seen fail is a guard nobody can rely on (D-139, D-187, D-201).
///
/// The numbers in test names are the Slice 8 brief's (39 … 44).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/surface_guard_tokens.dart';

const _dir = 'lib/features/analytics';
const _page = '$_dir/presentation/analytics_page.dart';
const _navigation = '$_dir/presentation/analytics_navigation.dart';
const _presentation = '$_dir/presentation/analytics_presentation.dart';
const _widgets = '$_dir/presentation/analytics_widgets.dart';
const _revenue = '$_dir/presentation/revenue_analysis.dart';
const _expenses = '$_dir/presentation/expense_analysis.dart';
const _comparison = '$_dir/presentation/business_comparison.dart';

const _sections = [_revenue, _expenses, _comparison];

List<String> _dartFiles() => Directory(_dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.path.replaceAll(r'\', '/'))
    .toList(growable: false);

/// Reaching a figure any way but through the one prepared dashboard view.
const _reportingPath = [
  'Repository',
  'repositoryProvider',
  'ReportingEngine',
  'localReportingEngineProvider',
  'reportingCacheProvider',
  'reportingDrilldownSourceProvider',
  'reportingSyncProvider',
  'ReportRequest(',
  'DashboardEngine(',
  'dashboardEngineProvider',
  'engine.build(',
  'CachedReportingSource',
];

/// A second P&L: its calculator, its state, or its surfaces rebuilt here.
const _secondPnl = [
  'Pnl.compute(',
  'Pnl.consolidate(',
  'PnlResult(',
  'pnlViewProvider',
  'pnlSelectionProvider',
  'pnlSyncProvider',
  'pnlDrillProvider',
  'PnlDrilldown.',
  'OperatingMargin.of(',
  'MarginRatio(',
];

/// Money arithmetic a widget might be tempted into, written the way it would be.
final _moneyArithmetic = RegExp(
  r'\b(netSales|grossSales|gst|expenses|operatingProfit|amount|total|others)'
  r'\s*[-+*/]\s*\w',
);

/// Words that would place one property above the other (Business Comparison).
const _ranking = [
  'winner',
  'best',
  'better',
  'worse',
  'worst',
  'leading',
  'leader',
  'outperform',
  'strongest',
  'weakest',
];

/// Analysis the canonical reporting model does not support.
const _unsupportedAnalysis = [
  'valueBand',
  'supplySubtype',
  'vendor',
  'Vendor',
  'supplier',
  'Supplier',
  'occupancy',
  'forecast',
  'Forecast',
  'budget',
  'Budget',
  'target',
];

/// The string literals in [code], lower-cased — the words a reader would see.
List<String> _literals(String code) => [
  for (final m in RegExp(r"'([^'\\]|\\.)*'").allMatches(code))
    m.group(0)!.toLowerCase(),
];

List<String> _rankingWords(String code) => [
  for (final literal in _literals(code))
    for (final word in _ranking)
      if (RegExp('\\b$word\\b').hasMatch(literal)) word,
];

void main() {
  late List<String> files;
  late Map<String, String> code;

  setUpAll(() {
    files = _dartFiles();
    code = {for (final path in files) path: surfaceFileCode(path)};
  });

  test(
    'the feature holds the page, its state, its wording and three sections',
    () {
      expect(
        files,
        containsAll(<String>[
          _page,
          _navigation,
          _presentation,
          _widgets,
          ..._sections,
        ]),
      );
    },
  );

  // ── 39 · no database, repository or server reporting implementation ─────

  test(
    '39 · no analytics file reaches storage or a reporting implementation',
    () {
      code.forEach((path, source) {
        expect(
          surfaceViolations(source, [...surfaceStorage, ..._reportingPath]),
          isEmpty,
          reason:
              '$path reaches a figure some other way than the one prepared dashboard '
              'view',
        );
      });
    },
  );

  test('every figure arrives through dashboardViewProvider, once', () {
    expect(code[_page], contains('ref.watch(dashboardViewProvider)'));
    expect(
      code[_page],
      contains('dashboardPresentation('),
      reason:
          'the workspace must go through the one pure function that shows a state '
          'only to the authority that assembled it (D-267)',
    );
    for (final path in files) {
      expect(
        code[path]!.contains('stateAsync.value'),
        isFalse,
        reason: '$path reads a state directly, bypassing the authority test',
      );
    }
    for (final path in _sections) {
      expect(
        code[path]!.contains('dashboardViewProvider'),
        isFalse,
        reason:
            '$path reads the dashboard itself; a section is handed the ready view the '
            'workspace has already checked',
      );
    }
  });

  // ── 40 · no financial arithmetic ─────────────────────────────────────────

  test('40 · no analytics file works out a figure', () {
    code.forEach((path, source) {
      expect(
        surfaceViolations(source, surfaceCalculation),
        isEmpty,
        reason:
            'every figure in $path is a field of a result domain/finance produced '
            '(D-020, spec §21.1)',
      );
      expect(
        _moneyArithmetic.allMatches(source).map((m) => m.group(0)).toList(),
        isEmpty,
        reason: '$path does arithmetic on a money figure',
      );
    });
  });

  // ── 41 · no role-name authorization ──────────────────────────────────────

  test('41 · no role name and no capability decision anywhere', () {
    code.forEach((path, source) {
      for (final forbidden in const [
        "'owner'",
        "'manager'",
        "'accountant'",
        "'data_entry'",
        'RoleTemplates',
        'Capability.',
        'canAnywhere(',
        'scopedUnitsFor(',
        'hasCapability',
        'reports.view',
        'revenue.view',
        'expense.view',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason:
              '$path decides authority itself ($forbidden). Every section qualifies on '
              'exactly what PnlAuthority decides (D-164, D-187)',
        );
      }
    });
    // Business Comparison's gate is the P&L's own consolidated answer.
    expect(code[_page], contains('pnlScopeOptionsShownTo('));
    expect(code[_page], contains('consolidatedAllowed'));
  });

  // ── 42 · no Owner Accounts dependency ────────────────────────────────────

  test('42 · no analytics file names Owner Accounts', () {
    code.forEach((path, source) {
      expect(
        surfaceViolations(source, [
          ...surfaceOwnerAccounts,
          'owner_settlement',
        ]),
        isEmpty,
        reason:
            '$path names Owner Accounts, which is its own surface behind its own '
            'capability (D-212)',
      );
    });
  });

  // ── 43 · no export or printing ───────────────────────────────────────────

  test('43 · no export or printing — that is Phase 7', () {
    code.forEach((path, source) {
      expect(
        surfaceViolations(source, surfaceExports),
        isEmpty,
        reason: '$path exports or prints',
      );
    });
  });

  // ── 44 · no second P&L ───────────────────────────────────────────────────

  test(
    '44 · the Profit & Loss is the existing page, embedded exactly once',
    () {
      code.forEach((path, source) {
        expect(
          surfaceViolations(source, _secondPnl),
          isEmpty,
          reason: '$path rebuilds part of the P&L',
        );
      });
      expect(
        'ProfitAndLossPage('.allMatches(code[_page]!).length,
        1,
        reason: 'the P&L section is the Phase 5 page, not a second one',
      );
      expect(
        surfaceDense(code[_page]!),
        contains('ProfitAndLossPage(shellKind:widget.shellKind)'),
      );
      for (final path in _sections) {
        expect(code[path]!.contains('ProfitAndLossPage'), isFalse);
      }
    },
  );

  test('the desktop Analytics branch is the workspace, not the bare P&L', () {
    final router = File('lib/app/routing/app_router.dart').readAsStringSync();
    final start = router.indexOf('static GoRouter _desktopRouter(');
    expect(start, isNonNegative);
    final desktop = router.substring(start);
    final from = desktop.indexOf('AppRoutes.analytics');
    final to = desktop.indexOf('AppRoutes.reports');
    expect(from, isNonNegative);
    expect(to, greaterThan(from));
    final branch = desktop.substring(from, to);
    expect(branch, contains('AnalyticsPage(shellKind: AppShellKind.desktop)'));
    expect(branch, isNot(contains('ProfitAndLossPage(')));
  });

  // ── Section rules ────────────────────────────────────────────────────────

  test('the two period models are stated in the navigation state', () {
    final nav = code[_navigation]!;
    expect(nav, contains('AnalyticsPeriodModel.pnlPresets'));
    expect(nav, contains('AnalyticsPeriodModel.dashboardToDate'));
    // The analysis sections never touch the P&L's own selection (checked above) and
    // read periods only through the dashboard's.
    expect(code[_page], contains('dashboardSelectionProvider'));
  });

  test(
    'revenue analysis uses the canonical three sums and the prepared mix',
    () {
      final revenue = code[_revenue]!;
      for (final required in const [
        'result.grossSales',
        'result.gst',
        'result.netSales',
        'comparison.grossSales',
        'comparison.gst',
        'comparison.netSales',
        'dashboardTrendChartData(',
        'RankedBarChartData.fromTopN<RevenueCategoryLine>(',
        'view.topRevenueCategories',
      ]) {
        expect(revenue, contains(required), reason: 'no longer uses $required');
      }
      // It never plots cost or profit as a revenue trend.
      expect(revenue.contains('TrendMeasure.expenses'), isFalse);
      expect(revenue.contains('TrendMeasure.operatingProfit'), isFalse);
    },
  );

  test('expense analysis plots expenses monthly, and only monthly', () {
    final expenses = code[_expenses]!;
    expect(
      surfacePhrases(expenses),
      contains(
        'series.measure == TrendMeasure.expenses && series.grain == TrendGrain.monthly',
      ),
    );
    for (final forbidden in const [
      'TrendGrain.daily',
      'TrendGrain.weekly',
      'TrendMeasure.netSales',
      'TrendMeasure.operatingProfit',
    ]) {
      expect(
        expenses.contains(forbidden),
        isFalse,
        reason:
            '$_expenses names $forbidden. Expenses are trended by month only, because '
            'accrual dating makes a daily cost misleading (D-255)',
      );
    }
    for (final required in const [
      'RankedBarChartData.fromTopN<ExpenseHierarchyLine>(',
      'view.topExpenseCategories',
      'view.departmentSpending',
      'result.expenses',
      'comparison.expenses',
    ]) {
      expect(expenses, contains(required), reason: 'no longer uses $required');
    }
  });

  test('Others is drawn as the domain handed it over, never recomputed', () {
    for (final path in _sections) {
      for (final forbidden in const [
        '.others',
        'othersCount',
        '.top.',
        '.top[',
        'TopNGrouped',
      ]) {
        expect(
          code[path]!.contains(forbidden),
          isFalse,
          reason:
              '$path reaches into a Top-N grouping ($forbidden). The chart adapter '
              'draws it exactly as the domain grouped it (D-258)',
        );
      }
    }
  });

  test(
    "business comparison is the domain's ready split, and ranks nothing",
    () {
      final comparison = code[_comparison]!;
      expect(
        surfacePhrases(comparison),
        contains('view.propertyComparison case final PropertyComparisonReady'),
      );
      expect(comparison, contains('analyticsOperatingWord'));
      expect(
        comparison.contains('MoneyEmphasis.bySign'),
        isFalse,
        reason: 'no property is painted good or bad by colour',
      );
      for (final path in [_comparison, _presentation, _page]) {
        expect(
          _rankingWords(code[path]!),
          isEmpty,
          reason: '$path places one property above the other',
        );
      }
    },
  );

  test('no section offers analysis the canonical model does not support', () {
    for (final path in _sections) {
      expect(
        surfaceViolations(code[path]!, _unsupportedAnalysis),
        isEmpty,
        reason: '$path adds analysis outside the approved scope',
      );
    }
  });

  test('a trend gap reaches the chart layer as a gap', () {
    for (final path in [_revenue, _expenses]) {
      expect(code[path], contains('dashboardTrendChartData('));
      for (final forbidden in const [
        'Money.zero',
        'whereType<TrendValue>',
        'TrendGap',
      ]) {
        expect(
          code[path]!.contains(forbidden),
          isFalse,
          reason: '$path handles a missing trend point itself ($forbidden)',
        );
      }
    }
  });

  test('no analytics file navigates, or talks to the chart package', () {
    code.forEach((path, source) {
      expect(
        surfaceViolations(source, surfaceNavigation),
        isEmpty,
        reason: path,
      );
      expect(source.contains('goBranch('), isFalse, reason: path);
      expect(source.contains('package:fl_chart'), isFalse, reason: path);
      expect(
        surfaceViolations(source, surfaceMutation),
        isEmpty,
        reason: '$path reaches a write path',
      );
    });
  });

  // ── The guard fails when it should ───────────────────────────────────────

  group('the guard fails when it should', () {
    test('a planted repository read is seen', () {
      const planted =
          'final rows = ref.read(revenueRepositoryProvider).query();';
      expect(
        surfaceViolations(surfaceCode(planted), _reportingPath),
        isNotEmpty,
      );
    });

    test('a planted Net Sales calculation is seen', () {
      const planted = 'final net = result.grossSales - result.gst;';
      expect(_moneyArithmetic.hasMatch(surfaceCode(planted)), isTrue);
    });

    test('a planted margin rounding is seen', () {
      const planted = 'Text(margin.percentageScaled(2).toString())';
      expect(
        surfaceViolations(surfaceCode(planted), surfaceCalculation),
        isNotEmpty,
      );
    });

    test('a planted role branch is seen', () {
      const planted = "if (role == 'owner') return const BusinessComparison();";
      expect(planted.contains("'owner'"), isTrue);
    });

    test('a planted owner figure is seen', () {
      const planted = 'ref.watch(ownerSettlementPreviewProvider)';
      expect(
        surfaceViolations(surfaceCode(planted), surfaceOwnerAccounts),
        isNotEmpty,
      );
    });

    test('a planted export is seen', () {
      const planted = 'onPressed: () => exportTo(Excel.workbook()),';
      expect(
        surfaceViolations(surfaceCode(planted), surfaceExports),
        isNotEmpty,
      );
    });

    test('a planted second P&L is seen', () {
      const planted =
          'final r = Pnl.compute(period: p, revenue: a, expenses: b);';
      expect(surfaceViolations(surfaceCode(planted), _secondPnl), isNotEmpty);
    });

    test('a planted daily expense trend is seen', () {
      const planted = 'grain: TrendGrain.daily, measure: TrendMeasure.expenses';
      expect(planted.contains('TrendGrain.daily'), isTrue);
    });

    test('a planted Others recomputation is seen', () {
      const planted = 'final rest = grouped.total - grouped.others!;';
      expect(_moneyArithmetic.hasMatch(surfaceCode(planted)), isTrue);
      expect(planted.contains('.others'), isTrue);
    });

    test('planted winner wording is seen, and prose about it is not', () {
      expect(
        _rankingWords("const label = 'The better property this month';"),
        contains('better'),
      );
      expect(
        _rankingWords("Text('Winner: Hotel Krishna')"),
        contains('winner'),
      );
      // Words in a comment, or inside an identifier, are not what a reader sees.
      expect(_rankingWords(surfaceCode('// no winner is named')), isEmpty);
      expect(_rankingWords('final bestFit = BoxFit.scaleDown;'), isEmpty);
    });

    test('a planted unsupported analysis is seen', () {
      const planted = 'title: Text("Top vendors")';
      expect(surfaceViolations(planted, _unsupportedAnalysis), isNotEmpty);
    });

    test('a comment about a rule is not a violation', () {
      const planted = '// never Pnl.compute( here, and never context.go(';
      expect(surfaceViolations(surfaceCode(planted), _secondPnl), isEmpty);
      expect(
        surfaceViolations(surfaceCode(planted), surfaceNavigation),
        isEmpty,
      );
    });
  });
}
