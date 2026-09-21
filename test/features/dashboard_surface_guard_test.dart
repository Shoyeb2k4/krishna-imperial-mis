/// What Slice 4 is, and is not (Phase 6 Slice 4).
///
/// Slice 4 connects the Slice 3 engine to the session. It builds **no chart and no
/// screen** — those are Slices 5 to 9 — and it introduces **no second financial
/// authorization model**, no second reporting path and no date arithmetic of its own.
///
/// Every rule below is a property of the directory rather than of a file somebody
/// remembered to check, and each is paired with a planted violation, because a guard that
/// has never been seen to fail is a guard nobody can rely on (D-139, D-187, D-201).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dir = 'lib/features/dashboard';
const _providers = '$_dir/presentation/dashboard_providers.dart';

/// Source with comments stripped: prose legitimately names charts, screens, capabilities
/// and the rules this file delegates to.
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
  late String providers;

  setUpAll(() {
    files = _dartFiles();
    providers = _code(_providers);
  });

  test('the dashboard feature exists and is providers only', () {
    expect(files, isNotEmpty);
    expect(files, contains(_providers));
  });

  test('Slice 4 builds no chart and no screen', () {
    for (final path in files) {
      final code = _code(path);
      for (final forbidden in const [
        'package:flutter/material.dart',
        'package:flutter/widgets.dart',
        'package:fl_chart',
        'StatelessWidget',
        'StatefulWidget',
        'ConsumerWidget',
        'ConsumerStatefulWidget',
        'Widget build(',
        'Scaffold(',
        'GoRoute',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason:
              '$path contains $forbidden. Slice 4 is application state; the surfaces '
              'and their charts are Slices 5 to 9',
        );
      }
    }
  });

  test('there is one financial authorization model, and this is not a second', () {
    // It must delegate to PnlAuthority…
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
    // …and must decide nothing about capabilities itself.
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
        providers.contains(forbidden),
        isFalse,
        reason:
            '$_providers decides what qualifies ($forbidden). The dashboard qualifies '
            'on exactly the intersection PnlAuthority already decides (D-164, D-187)',
      );
    }
  });

  test('no role name appears anywhere in the dashboard', () {
    for (final path in files) {
      final code = _code(path);
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
      'reportForUnit(',
      'ReportRequest(',
      'Pnl.compute(',
      'Pnl.consolidate(',
      'PnlComparison.compare(',
      'DashboardTrends.buckets(',
      'DashboardTrends.series(',
      'DailyNetSalesRanking.',
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

  test('freshness is the engine\'s claim, never one made here', () {
    for (final forbidden in const [
      'ReportingFreshness(',
      'ReportingFreshness.synchronised(',
      'ReportingSnapshotEvidence(',
      'serverConfirmedAt:',
    ]) {
      expect(
        providers.contains(forbidden),
        isFalse,
        reason:
            '$_providers constructs a freshness claim. When the engine can name no one '
            'snapshot, the provider names none either (D-188)',
      );
    }
    // The complement: the engine's own claim must be what is read.
    expect(providers, contains('view.freshness'));
  });

  test('a dashboard state is stamped with the authority that assembled it', () {
    expect(providers, contains('authorityKey'));
    expect(
      providers,
      contains('value.authorityKey == PnlAuthority.readKey(principal)'),
      reason:
          'the visibility test is the authority key, not the person: the same person '
          'whose capabilities have moved is a different authority (D-231, D-242)',
    );
  });

  test('nothing here writes to the canonical caches', () {
    for (final path in files) {
      final code = _code(path);
      for (final forbidden in const [
        'applySnapshot(',
        'applyYear(',
        'customStatement',
        'customSelect',
        'AppDatabase',
      ]) {
        expect(
          code.contains(forbidden),
          isFalse,
          reason: '$path reaches past the repositories ($forbidden)',
        );
      }
    }
  });

  group('the guard fails when it should', () {
    test('a planted widget is seen', () {
      const planted = 'class HomePage extends ConsumerWidget {';
      expect(planted.contains('ConsumerWidget'), isTrue);
    });

    test('a planted capability branch is seen', () {
      const planted = 'if (p.can(Capability.reportsView)) return true;';
      expect(planted.contains('Capability.'), isTrue);
    });

    test('a planted date derivation is seen', () {
      const planted = 'final today = BusinessDate.of(2026, 9, 17);';
      expect(planted.contains('BusinessDate.of('), isTrue);
    });

    test('a planted second reporting path is seen', () {
      const planted =
          'await engine.report(ReportRequest(period: p, scope: s));';
      expect(planted.contains('ReportRequest('), isTrue);
    });

    test('a planted freshness claim is seen', () {
      const planted = 'ReportingFreshness.synchronised(evidence)';
      expect(planted.contains('ReportingFreshness.synchronised('), isTrue);
    });

    test('a dropped delegation is seen', () {
      const planted = 'return true;';
      expect(planted.contains('PnlAuthority.readKey('), isFalse);
    });
  });
}
