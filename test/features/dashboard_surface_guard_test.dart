/// What the dashboard feature is, and is not (Phase 6, Slices 4 and 6).
///
/// Slice 4 connected the Slice 3 engine to the session and built no surface. Slice 6 adds
/// the Windows Overview, so the "no screen" rule is **narrowed rather than bypassed** —
/// the move D-237 made when Slice 10 needed the breakdowns the Slice 8 P&L guard forbade.
/// What is still forbidden is what a dashboard must never do: calculate, navigate,
/// mutate, reach a database, or decide for itself what qualifies.
///
/// Every rule is a property of the directory rather than of a file somebody remembered to
/// check, and each is paired with a planted violation, because a guard that has never been
/// seen to fail is a guard nobody can rely on (D-139, D-187, D-201, D-232).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dir = 'lib/features/dashboard';
const _providers = '$_dir/presentation/dashboard_providers.dart';
const _presentation = '$_dir/presentation/dashboard_presentation.dart';
const _page = '$_dir/presentation/overview_page.dart';

/// Source with comments stripped: prose legitimately names charts, screens, capabilities
/// and the rules these files delegate to.
String _code(String source) => source
    .split('\n')
    .where(
      (l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'),
    )
    .join('\n');

String _fileCode(String path) => _code(File(path).readAsStringSync());

/// Runs of whitespace collapsed to one space.
///
/// A phrase assertion must survive the formatter reflowing the line it sits on. That is
/// how D-153's documentation invariant went red for an encoding change, and it is how a
/// guard starts reporting a defect that is only a line break.
String _phrases(String code) => code.replaceAll(RegExp(r'\s+'), ' ');

List<String> _dartFiles() => Directory(_dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.path.replaceAll(r'\', '/'))
    .toList(growable: false);

/// A figure on a dashboard is never worked out by the thing that draws it.
const _calculation = [
  '.paise',
  'Money.sum(',
  'Money.fromPaise(',
  'Pnl.compute(',
  'Pnl.consolidate(',
  'PnlComparison.compare(',
  'DashboardTrends.buckets(',
  'DashboardTrends.series(',
  'DashboardTrends.grainsFor(',
  'DailyNetSalesRanking.',
  'TopN.',
  'PropertyComparison.of(',
  'percentageScaled(',
  'pointsScaled(',
  'double ',
  '.sort(',
  'reduce(',
  'fold(',
];

/// Routing is Slice 9's. A dashboard that navigated would be a second drill-down.
const _navigation = [
  'context.go(',
  'context.push(',
  'GoRouter',
  'GoRoute',
  'AppRoutes.',
  'Navigator.push',
  'MaterialPageRoute',
  'showDialog(',
];

/// A report is read-only, and this one is a summary of reports.
const _mutation = [
  'expenseRepositoryProvider',
  'revenueRepositoryProvider',
  'ownerLedgerRepositoryProvider',
  'createLocally(',
  'updateLocally(',
  'voidLocally(',
  'attachLocally(',
  'ExpenseEntryPage',
  'RevenueEntryPage',
];

/// Owner Accounts is its own surface behind its own capability (D-212).
const _ownerAccounts = [
  'ownerSettlement',
  'OwnerSettlement',
  'ownerLedger',
  'OwnerLedger',
  'PropertyFigures.owner',
];

/// Phase 7's, and it does not exist.
const _exports = ['Excel', 'pdf', 'Printing', 'printReport', 'exportTo'];

const _storage = [
  'AppDatabase',
  // Called with their parentheses: `customSelected`, a local on the period bar, is not a
  // Drift query, and a token that matched it would be the false positive D-069 records.
  'customStatement(',
  'customSelect(',
  'applySnapshot(',
  'applyYear(',
  'ReportingGateway',
  'SupabaseClient',
];

List<String> _violations(String code, List<String> forbidden) => [
  for (final token in forbidden)
    if (code.contains(token)) token,
];

void main() {
  late List<String> files;
  late String providers;
  late String page;
  late String presentation;

  setUpAll(() {
    files = _dartFiles();
    providers = _fileCode(_providers);
    page = _fileCode(_page);
    presentation = _fileCode(_presentation);
  });

  test(
    'the feature holds the providers, the wording and the Windows Overview',
    () {
      expect(files, containsAll(<String>[_providers, _presentation, _page]));
    },
  );

  // ── Still Slice 4's rules, unchanged ──────────────────────────────────────

  test('the providers build no chart and no screen', () {
    for (final forbidden in const [
      'package:flutter/material.dart',
      'package:fl_chart',
      'StatelessWidget',
      'StatefulWidget',
      'ConsumerWidget',
      'ConsumerStatefulWidget',
      'Widget build(',
      'Scaffold(',
    ]) {
      expect(
        providers.contains(forbidden),
        isFalse,
        reason:
            '$_providers contains $forbidden. It is application state; the surface is '
            'the page',
      );
    }
  });

  test('there is one financial authorization model, and this is not a second', () {
    for (final call in const [
      'PnlAuthority.readKey(',
      'PnlAuthority.mayReadUnit(',
      'PnlAuthority.mayReadConsolidated(',
      'pnlScopeOptionsProvider',
    ]) {
      expect(
        providers,
        contains(call),
        reason: '$_providers no longer delegates to $call',
      );
    }
    // The page offers the P&L's own scope options and decides nothing itself.
    expect(page, contains('pnlScopeOptionsShownTo('));
    for (final path in files) {
      final code = _fileCode(path);
      for (final forbidden in const [
        'Capability.',
        'canAnywhere(',
        'scopedUnitsFor(',
        'reports.view',
        'revenue.view',
        'expense.view',
        'hasCapability',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              '$path decides what qualifies ($forbidden). The dashboard qualifies on '
              'exactly the intersection PnlAuthority already decides (D-164, D-187)',
        );
      }
    }
  });

  test('no role name appears anywhere in the dashboard', () {
    for (final path in files) {
      final code = _fileCode(path);
      for (final role in const [
        "'owner'",
        "'manager'",
        "'accountant'",
        "'data_entry'",
        'RoleTemplates',
      ]) {
        expect(
          code.contains(role),
          isFalse,
          reason: '$path branches on a role name (spec §13.1)',
        );
      }
    }
  });

  test('periods come from the Slice 2 planner, not from provider arithmetic', () {
    for (final call in const [
      'DashboardPeriods.forUnits(',
      'DashboardPeriods.forCustom(',
    ]) {
      expect(
        providers,
        contains(call),
        reason: '$_providers no longer resolves periods through the planner',
      );
    }
    for (final forbidden in const [
      'BusinessDate.of(',
      'addDays(',
      'weekdayOf(',
      'DateTime.now',
      'DateTime.utc(',
      'FinancialYear.of(',
      'difference(',
      'Duration(',
    ]) {
      expect(
        providers.contains(forbidden),
        isFalse,
        reason:
            '$_providers derives a date ($forbidden). Every dashboard date is the '
            "planner's, under each property's own business-date rules (D-225, D-251)",
      );
    }
  });

  test('there is one dashboard path, through the Slice 3 engine', () {
    expect(providers, contains('engine.build('));
    expect(providers, contains('dashboardRequestFor('));
    for (final forbidden in const [
      'LocalReportingEngine(',
      'RemoteReportingEngine(',
      'ReportRequest(',
      'Pnl.compute(',
      'PnlComparison.compare(',
      'TopN.',
    ]) {
      expect(
        providers.contains(forbidden),
        isFalse,
        reason:
            '$_providers reassembles part of the dashboard itself ($forbidden). Every '
            'figure comes from one DashboardEngine.build, and the rules from the domain',
      );
    }
  });

  test("freshness is the engine's claim, never one made here", () {
    for (final path in files) {
      final code = _fileCode(path);
      for (final forbidden in const [
        'ReportingFreshness(',
        'ReportingFreshness.synchronised(',
        'ReportingSnapshotEvidence(',
        'serverConfirmedAt:',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              '$path constructs a freshness claim. When the engine can name no one '
              'snapshot, nothing here names one either (D-188)',
        );
      }
    }
    expect(providers, contains('view.freshness'));
    // And the surface must read the claim rather than inventing a timestamp.
    expect(presentation, contains('ready.freshness'));
  });

  test('a dashboard state is stamped with the authority that assembled it', () {
    expect(providers, contains('authorityKey'));
    expect(
      _phrases(providers),
      contains('value.authorityKey == PnlAuthority.readKey(principal)'),
      reason:
          'the visibility test is the authority key, not the person: the same person '
          'whose capabilities have moved is a different authority (D-231, D-242)',
    );
    expect(
      page,
      contains('dashboardPresentation('),
      reason:
          'the page must go through the one pure function that applies that test, so it '
          'cannot arrive at a different answer from the one under test',
    );
    expect(
      page.contains('stateAsync.value'),
      isFalse,
      reason: 'the page reads a state directly, bypassing the authority test',
    );
  });

  test('nothing here reaches past the repositories', () {
    for (final path in files) {
      expect(
        _violations(_fileCode(path), _storage),
        isEmpty,
        reason: '$path reaches storage or a transport directly',
      );
    }
  });

  // ── Slice 6's rules ───────────────────────────────────────────────────────

  test('the Overview calculates nothing', () {
    expect(
      _violations(page, _calculation),
      isEmpty,
      reason:
          'every figure on the Overview is a field of a result domain/finance produced '
          '(D-020, spec §21.1)',
    );
  });

  test('the shared wording calculates nothing either', () {
    expect(
      _violations(presentation, [
        for (final token in _calculation)
          // The wording legitimately prints a prepared percentage-point figure and a
          // prepared money movement; what it must not do is work one out.
          if (token != 'pointsScaled(' && token != 'double ') token,
      ]),
      isEmpty,
      reason: '$_presentation works out a figure rather than stating one',
    );
  });

  test('the Overview navigates nowhere — drill-down is Slice 9', () {
    expect(
      _violations(page, _navigation),
      isEmpty,
      reason:
          'the Overview must not grow its own drill-down or duplicate the P&L one '
          '(Slice 9 owns the integration)',
    );
  });

  test('the Overview can reach no mutation surface', () {
    for (final path in files) {
      expect(
        _violations(_fileCode(path), _mutation),
        isEmpty,
        reason: '$path reaches a write path. A dashboard is read-only',
      );
    }
  });

  test('no Owner Accounts value appears on the Overview', () {
    for (final path in files) {
      expect(
        _violations(_fileCode(path), _ownerAccounts),
        isEmpty,
        reason:
            '$path names Owner Accounts. Owner settlement is its own surface behind its '
            'own capability (D-212), and never part of a management dashboard',
      );
    }
  });

  test('no export or printing on the Overview — that is Phase 7', () {
    for (final path in files) {
      expect(
        _violations(_fileCode(path), _exports),
        isEmpty,
        reason: '$path exports or prints',
      );
    }
  });

  test('the Overview draws only the approved chart families', () {
    for (final family in const [
      'TrendLineChart(',
      'ProfitBarChart(',
      'ComparisonBarChart(',
      'RankedBarChart(',
    ]) {
      expect(
        page,
        contains(family),
        reason: '$_page no longer renders $family',
      );
    }
    expect(
      page.contains('package:fl_chart'),
      isFalse,
      reason:
          'only the chart layer imports the package, so replacing it is never a change '
          'to a screen (D-269)',
    );
  });

  test('the ranked families consume prepared rows, and rank nothing', () {
    for (final call in const [
      'RankedBarChartData.fromTopN<RevenueCategoryLine>(',
      'RankedBarChartData.fromTopN<ExpenseHierarchyLine>(',
    ]) {
      expect(page, contains(call), reason: '$_page no longer uses $call');
    }
    expect(
      page,
      contains('view.topRevenueCategories'),
      reason: 'revenue mix must be the engine\'s prepared Top N',
    );
    expect(page, contains('view.topExpenseCategories'));
    expect(page, contains('view.departmentSpending'));
  });

  test(
    'property comparison is the domain\'s split, shown only when it is ready',
    () {
      expect(
        _phrases(page),
        contains('view.propertyComparison case final PropertyComparisonReady'),
        reason:
            'the section renders only a ready split, so a single-property scope shows '
            'nothing rather than a chart of one bar',
      );
    },
  );

  test('a trend gap reaches the chart layer as a gap', () {
    // One composition, shared by the surface and its tests: the page hands a series to
    // `dashboardTrendChartData`, which is the only thing that adapts one, and that turns
    // every TrendGap into a ChartAbsent carrying no amount at all (D-263, D-268).
    expect(
      page,
      contains('dashboardTrendChartData('),
      reason: '$_page no longer adapts a trend through the shared composition',
    );
    expect(presentation, contains('TrendChartData.from('));
    for (final forbidden in const [
      'Money.zero',
      'whereType<TrendValue>',
      'TrendGap',
    ]) {
      expect(
        page.contains(forbidden),
        isFalse,
        reason:
            '$_page handles a missing trend point itself ($forbidden). A gap is never '
            'filtered out, substituted or zeroed',
      );
    }
  });

  test('the Overview assumes no property calendar and reads no clock', () {
    for (final path in files) {
      final code = _fileCode(path);
      expect(code, isNot(contains('Asia/Kolkata')));
      expect(code, isNot(contains('DateTime.now')));
    }
  });

  // ── The guard fails when it should ────────────────────────────────────────

  group('the guard fails when it should', () {
    test('a planted calculation is seen', () {
      const planted =
          'final profit = Money.fromPaise(net.paise - expenses.paise);';
      expect(_violations(_code(planted), _calculation), isNotEmpty);
    });

    test('a planted ranking is seen', () {
      const planted = 'final top = TopN.expenseCategories(result, n: 5);';
      expect(_violations(_code(planted), _calculation), contains('TopN.'));
    });

    test('a planted navigation is seen', () {
      const planted = 'onTap: () => context.go(AppRoutes.analytics),';
      expect(_violations(_code(planted), _navigation), isNotEmpty);
    });

    test('a planted mutation surface is seen', () {
      const planted = 'const ExpenseEntryPage(shellKind: shell)';
      expect(_violations(_code(planted), _mutation), isNotEmpty);
    });

    test('a planted owner-accounts figure is seen', () {
      const planted = 'final due = ref.watch(ownerSettlementPreviewProvider);';
      expect(_violations(_code(planted), _ownerAccounts), isNotEmpty);
    });

    test('a planted export is seen', () {
      const planted = 'onPressed: () => exportTo(Excel.workbook()),';
      expect(_violations(_code(planted), _exports), isNotEmpty);
    });

    test('a planted storage read is seen', () {
      const planted = 'final rows = await db.customSelect(sql).get();';
      expect(_violations(_code(planted), _storage), isNotEmpty);
    });

    test('a comment about a rule is not a violation', () {
      const planted = '// never Money.sum( here, and never context.go(';
      expect(_violations(_code(planted), _calculation), isEmpty);
      expect(_violations(_code(planted), _navigation), isEmpty);
    });

    test('a dropped delegation is seen', () {
      const planted = 'return true;';
      expect(planted.contains('PnlAuthority.readKey('), isFalse);
    });
  });
}
