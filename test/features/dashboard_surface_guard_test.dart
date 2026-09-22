/// What the dashboard feature is, and is not (Phase 6, Slices 4, 6 and 7).
///
/// Slice 4 connected the Slice 3 engine to the session and built no surface. Slice 6 added
/// the Windows Overview and Slice 7 the Android Home, so the "no screen" rule is
/// **narrowed rather than bypassed** — the move D-237 made when Slice 10 needed the
/// breakdowns the Slice 8 P&L guard forbade. What is still forbidden is what a dashboard
/// must never do: calculate, mutate, export, reach a database, or decide for itself what
/// qualifies — and navigate anywhere but the one destination D-260 approved.
///
/// **Every surface rule runs over every surface.** Slice 6's version asserted most of them
/// against the Overview file by name, so the Android Home arrived uncovered by all of
/// them; a guard that names one file cannot see the second one (the family D-068, D-071
/// and D-077 record). Each rule is paired with a planted violation, because a guard that
/// has never been seen to fail is a guard nobody can rely on (D-139, D-187, D-201).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dir = 'lib/features/dashboard';
const _providers = '$_dir/presentation/dashboard_providers.dart';
const _presentation = '$_dir/presentation/dashboard_presentation.dart';
const _overview = '$_dir/presentation/overview_page.dart';
const _home = '$_dir/presentation/mobile_home_page.dart';

/// Every surface in the feature. A rule about a dashboard screen runs over all of them.
const _surfaces = [_overview, _home];

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

/// Source with every whitespace character removed.
///
/// Collapsing runs to one space is not enough for a phrase the formatter may wrap
/// *inside* a call: the wrap introduces a space that was never written, so the two
/// forms of one expression stop matching each other.
String _dense(String code) => code.replaceAll(RegExp(r'\s'), '');

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

/// Routing a dashboard may not do. The one approved destination is checked separately.
const _navigation = [
  'context.go(',
  'context.push(',
  'GoRouter',
  'GoRoute(',
  'AppRoutes.',
  'Navigator.push',
  'MaterialPageRoute',
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
];

/// Phase 7's, and it does not exist.
const _exports = ['Excel', 'pdf', 'Printing', 'printReport', 'exportTo'];

const _storage = [
  'AppDatabase',
  // Called with their parentheses: `customSelected`, a local on the Overview's period
  // bar, is not a Drift query, and a token that matched it would be the false positive
  // D-069 records.
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
  late String presentation;
  late Map<String, String> surfaces;

  setUpAll(() {
    files = _dartFiles();
    providers = _fileCode(_providers);
    presentation = _fileCode(_presentation);
    surfaces = {for (final path in _surfaces) path: _fileCode(path)};
  });

  test('the feature holds the providers, the wording and both surfaces', () {
    expect(
      files,
      containsAll(<String>[_providers, _presentation, ..._surfaces]),
    );
  });

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
            '$_providers contains $forbidden. It is application state; the surfaces '
            'are the pages',
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
    // Each surface offers the P&L's own scope options and decides nothing itself.
    surfaces.forEach((path, code) {
      expect(
        code,
        contains('pnlScopeOptionsShownTo('),
        reason: '$path builds its own scope options',
      );
    });
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
    // And a surface must read the claim rather than inventing a timestamp.
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
    surfaces.forEach((path, code) {
      expect(
        code,
        contains('dashboardPresentation('),
        reason:
            '$path must go through the one pure function that applies that test, so '
            'it cannot arrive at a different answer from the one under test',
      );
      expect(
        code.contains('stateAsync.value'),
        isFalse,
        reason: '$path reads a state directly, bypassing the authority test',
      );
    });
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

  // ── Rules over every surface ──────────────────────────────────────────────

  test('a dashboard surface calculates nothing', () {
    surfaces.forEach((path, code) {
      expect(
        _violations(code, _calculation),
        isEmpty,
        reason:
            'every figure on $path is a field of a result domain/finance produced '
            '(D-020, spec §21.1)',
      );
    });
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

  test('a dashboard surface can reach no mutation surface', () {
    for (final path in files) {
      expect(
        _violations(_fileCode(path), _mutation),
        isEmpty,
        reason: '$path reaches a write path. A dashboard is read-only',
      );
    }
  });

  test('no Owner Accounts value appears on a dashboard', () {
    for (final path in files) {
      expect(
        _violations(_fileCode(path), _ownerAccounts),
        isEmpty,
        reason:
            '$path names Owner Accounts. Owner settlement is its own surface behind '
            'its own capability (D-212), never part of a management dashboard',
      );
    }
  });

  test('no export or printing on a dashboard — that is Phase 7', () {
    for (final path in files) {
      expect(
        _violations(_fileCode(path), _exports),
        isEmpty,
        reason: '$path exports or prints',
      );
    }
  });

  test(
    'a dashboard surface assumes no property calendar and reads no clock',
    () {
      for (final path in files) {
        final code = _fileCode(path);
        expect(code, isNot(contains('Asia/Kolkata')));
        expect(code, isNot(contains('DateTime.now')));
      }
    },
  );

  test('a trend gap reaches the chart layer as a gap', () {
    // One composition, shared by the surfaces and their tests: a page hands a series to
    // `dashboardTrendChartData`, which is the only thing that adapts one, and that turns
    // every TrendGap into a ChartAbsent carrying no amount at all (D-263, D-268).
    surfaces.forEach((path, code) {
      expect(
        code,
        contains('dashboardTrendChartData('),
        reason: '$path no longer adapts a trend through the shared composition',
      );
      for (final forbidden in const [
        'Money.zero',
        'whereType<TrendValue>',
        'TrendGap',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              '$path handles a missing trend point itself ($forbidden). A gap is never '
              'filtered out, substituted or zeroed',
        );
      }
    });
    expect(presentation, contains('TrendChartData.from('));
  });

  test('a ranked family consumes prepared rows, and ranks nothing', () {
    surfaces.forEach((path, code) {
      expect(
        code,
        contains('RankedBarChartData.fromTopN<'),
        reason: '$path builds its own ranked rows',
      );
    });
  });

  test("property comparison is the domain's split, shown only when ready", () {
    surfaces.forEach((path, code) {
      expect(
        _phrases(code),
        contains('view.propertyComparison case final PropertyComparisonReady'),
        reason:
            '$path renders something other than a ready split, so a single-property '
            'scope could show a chart of one bar',
      );
    });
  });

  // ── What each surface shows (D-260) ───────────────────────────────────────

  test('the Windows Overview draws the four approved families', () {
    final code = surfaces[_overview]!;
    for (final family in const [
      'TrendLineChart(',
      'ProfitBarChart(',
      'ComparisonBarChart(',
      'RankedBarChart(',
    ]) {
      expect(
        code,
        contains(family),
        reason: '$_overview no longer draws $family',
      );
    }
    for (final section in const [
      'view.topRevenueCategories',
      'view.topExpenseCategories',
      'view.departmentSpending',
    ]) {
      expect(code, contains(section));
    }
  });

  test('the Android Home shows what D-260 gives it, and not the workspace', () {
    final code = surfaces[_home]!;
    for (final shown in const [
      'TrendLineChart(',
      'ComparisonBarChart(',
      'RankedBarChart(',
      'view.topExpenseCategories',
    ]) {
      expect(code, contains(shown), reason: '$_home no longer shows $shown');
    }
    // Revenue mix and department spending belong to the Windows Analytics workspace,
    // which Phase 6 does not reproduce on Android (D-260).
    for (final notShown in const [
      'view.topRevenueCategories',
      'view.departmentSpending',
      'ProfitBarChart(',
    ]) {
      expect(
        code.contains(notShown),
        isFalse,
        reason:
            '$_home shows $notShown. The Android Home is a glance, not the analytics '
            'workspace (D-260)',
      );
    }
  });

  test('only the chart layer talks to the chart package', () {
    for (final path in files) {
      expect(
        _fileCode(path).contains('package:fl_chart'),
        isFalse,
        reason:
            '$path imports the package directly, so replacing it would be a change to '
            'a screen (D-269)',
      );
    }
  });

  // ── Navigation: one approved destination, and nothing else ────────────────

  test('a dashboard surface navigates nowhere it was not sent', () {
    surfaces.forEach((path, code) {
      expect(
        _violations(code, _navigation),
        isEmpty,
        reason:
            '$path routes somewhere. Drill-down from a dashboard figure to its '
            'transactions is Slice 9, and nothing here duplicates the P&L drill-down',
      );
    });
  });

  test('the Overview offers no navigation at all', () {
    expect(
      surfaces[_overview]!.contains('goBranch('),
      isFalse,
      reason:
          'the Windows shell has its own sidebar; the Overview sends nobody anywhere',
    );
  });

  test('the Android Home sends somebody exactly one place: Reports', () {
    final code = surfaces[_home]!;
    expect(
      'goBranch('.allMatches(code).length,
      1,
      reason:
          'exactly one navigation — See full P&L — and it is the destination D-260 '
          'approved',
    );
    expect(
      _dense(code),
      contains('goBranch(AppRouter.mobileReportsBranch)'),
      reason:
          'the destination is named rather than numbered, so the branch it means is '
          'reviewable and cannot drift from the router',
    );
  });

  test('the named Reports branch is the one the router actually has', () {
    final router = File('lib/app/routing/app_router.dart').readAsStringSync();
    final declared = RegExp(
      r'mobileReportsBranch\s*=\s*(\d+)',
    ).firstMatch(router);
    expect(declared, isNotNull, reason: 'the constant is gone');

    // Anchored on the method declarations, so the slice cannot be empty and the
    // assertion vacuous — the defect D-232 records about the Slice 8 router guard.
    final start = router.indexOf('static GoRouter _mobileRouter(');
    final end = router.indexOf('static GoRouter _desktopRouter(');
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final mobile = router.substring(start, end);

    final order = RegExp(
      r'_branch\(\s*AppRoutes\.(\w+)',
    ).allMatches(mobile).map((m) => m.group(1)).toList();
    expect(order, [
      'home',
      'transactions',
      'reports',
      'more',
    ], reason: 'the Android branch order changed');
    expect(
      int.parse(declared!.group(1)!),
      order.indexOf('reports'),
      reason:
          'AppRouter.mobileReportsBranch no longer points at the Reports branch, so '
          'See full P&L would open the wrong tab',
    );
  });

  test(
    'the Android Home is the Home branch, and the Overview the desktop one',
    () {
      final router = File('lib/app/routing/app_router.dart').readAsStringSync();
      final start = router.indexOf('static GoRouter _mobileRouter(');
      final end = router.indexOf('static GoRouter _desktopRouter(');
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final mobile = router.substring(start, end);
      final desktop = router.substring(end);

      final homeStart = mobile.indexOf('AppRoutes.home');
      final transactionsStart = mobile.indexOf('AppRoutes.transactions');
      expect(homeStart, isNonNegative);
      expect(transactionsStart, greaterThan(homeStart));
      final home = mobile.substring(homeStart, transactionsStart);
      expect(home, contains('const MobileHomePage()'));
      expect(home, isNot(contains('PlaceholderPage')));

      final overviewStart = desktop.indexOf('AppRoutes.overview');
      final desktopTransactions = desktop.indexOf('AppRoutes.transactions');
      expect(overviewStart, isNonNegative);
      expect(desktopTransactions, greaterThan(overviewStart));
      expect(
        desktop.substring(overviewStart, desktopTransactions),
        contains('OverviewPage(shellKind: AppShellKind.desktop)'),
      );
      expect(desktop, isNot(contains('MobileHomePage')));
    },
  );

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

    test('a planted second branch switch is seen', () {
      const planted =
          'onTap: () => shell.goBranch(1), onLongPress: () => shell.goBranch(3),';
      expect('goBranch('.allMatches(planted).length, isNot(1));
    });

    test('a planted numbered destination is seen', () {
      const planted = 'StatefulNavigationShell.of(context).goBranch(2)';
      expect(
        _dense(planted).contains('goBranch(AppRouter.mobileReportsBranch)'),
        isFalse,
      );
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

    test('a planted analytics section on the phone is seen', () {
      const planted =
          'data: RankedBarChartData.fromTopN(view.departmentSpending';
      expect(planted.contains('view.departmentSpending'), isTrue);
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
