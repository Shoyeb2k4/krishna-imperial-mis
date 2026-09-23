/// What a dashboard or analytics figure may do when it is opened (Phase 6 Slice 9).
///
/// The dashboard surfaces produce **navigation intent** and nothing else: canonical ids, a
/// scope and a resolved range, turned into a destination by one shared adapter and opened
/// into the existing Phase 5 drill-down or P&L. These rules hold that structurally, and
/// each is paired with a planted violation, because a guard that has never been seen to
/// fail is a guard nobody can rely on (D-139, D-187, D-201).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/surface_guard_tokens.dart';
import 'pnl_surface_guard_test.dart' show mutationViolations;

const _adapter = 'lib/features/dashboard/presentation/dashboard_drill.dart';
const _pane = 'lib/features/dashboard/presentation/dashboard_drill_view.dart';

/// Every file a dashboard figure is drawn in.
const _surfaces = [
  'lib/features/dashboard/presentation/overview_page.dart',
  'lib/features/dashboard/presentation/mobile_home_page.dart',
  'lib/features/dashboard/presentation/dashboard_widgets.dart',
  'lib/features/analytics/presentation/analytics_page.dart',
  'lib/features/analytics/presentation/revenue_analysis.dart',
  'lib/features/analytics/presentation/expense_analysis.dart',
  'lib/features/analytics/presentation/business_comparison.dart',
  'lib/features/analytics/presentation/analytics_widgets.dart',
];

/// The surfaces that open something, and so must do it through the adapter.
const _opening = [
  'lib/features/dashboard/presentation/overview_page.dart',
  'lib/features/dashboard/presentation/mobile_home_page.dart',
  'lib/features/analytics/presentation/revenue_analysis.dart',
  'lib/features/analytics/presentation/expense_analysis.dart',
  'lib/features/analytics/presentation/business_comparison.dart',
];

List<String> _dartFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => f.path.replaceAll(r'\', '/'))
    .toList(growable: false);

/// A period is handed over resolved, never reconstructed from a clock or a calendar.
List<String> reconstructedPeriod(String code) => surfaceViolations(code, const [
  'reportingClockProvider',
  'DateTime.now',
  'businessDateAt(',
  'fromInstant(',
  'businessDayRulesProvider',
  'DashboardPeriods.',
  'resolvePresetForUnits(',
  'RelativePreset.',
  '.addDays(',
]);

/// A target is built from canonical ids, never from what a reader sees.
List<String> displayIdentity(String code) => [
  for (final (pattern, what) in [
    (RegExp(r'masterGraph'), 'reads the master graph'),
    (RegExp(r'\bgraph\b'), 'reads a graph'),
    (RegExp(r'\w+Name\('), 'resolves a display name'),
    (RegExp(r'\.name\b'), 'reads a name'),
  ])
    if (pattern.hasMatch(code)) what,
];

/// A dashboard reads no drill-down rows, documents or reports itself.
List<String> drillReads(String code) => surfaceViolations(code, const [
  'pnlDrillLevelProvider',
  'pnlDashboardDrillReportProvider',
  // Read or watched. Invalidating the source after a dashboard synchronisation is the
  // Slice 4 sync's job, and reads nothing.
  '.read(reportingDrilldownSourceProvider',
  '.watch(reportingDrilldownSourceProvider',
  'reportDocumentReaderProvider',
  'ReportDocumentReader',
  'revenueDocuments(',
  'expenseDocuments(',
  '.read(pnlDocumentDetailProvider',
  '.watch(pnlDocumentDetailProvider',
]);

/// Only the adapter builds a drill-down location or anchor.
List<String> locationBuilding(String code) => surfaceViolations(code, const [
  'PnlDrillAnchor',
  'PnlRevenueCategoriesAt(',
  'PnlRevenueDocumentsAt(',
  'PnlExpenseDepartmentsAt(',
  'PnlExpenseSectionsAt(',
  'PnlExpenseCategoriesAt(',
  'PnlExpenseDocumentsAt(',
  'DashboardDrillLevel(',
  'DashboardPnlHandoff(',
  'pnlSelectionProvider',
]);

void main() {
  late String adapter;
  late String pane;
  late Map<String, String> surfaces;

  setUpAll(() {
    adapter = surfaceFileCode(_adapter);
    pane = surfaceFileCode(_pane);
    surfaces = {for (final path in _surfaces) path: surfaceFileCode(path)};
  });

  test(
    'the adapter passes the resolved range and reads no clock or calendar',
    () {
      expect(reconstructedPeriod(adapter), isEmpty);
      // The positive half: a bucket opens over the bucket's own range.
      expect(surfaceDense(adapter), contains('finalrange=point.bucket.range;'));
      expect(surfaceDense(adapter), contains('_ready.pair.current'));
    },
  );

  test('a target is canonical ids and a range, never a display name', () {
    expect(displayIdentity(adapter), isEmpty);
  });

  test('no dashboard or analytics file reads drill-down rows or documents', () {
    for (final path in [
      ..._dartFiles('lib/features/dashboard'),
      ..._dartFiles('lib/features/analytics'),
    ]) {
      expect(
        drillReads(surfaceFileCode(path)),
        isEmpty,
        reason:
            '$path reads what the drill-down destination reads. A dashboard produces '
            'navigation intent; the Phase 5 providers read',
      );
    }
  });

  test('there is one document query path, and it is Phase 5\'s', () {
    final holders = [
      for (final path in _dartFiles('lib'))
        if (RegExp(
          r'\b(revenueDocuments|expenseDocuments)\(',
        ).hasMatch(surfaceFileCode(path)))
          path,
    ]..sort();
    expect(holders, [
      'lib/data/reporting/cached_drilldown_source.dart',
      'lib/data/repositories/reporting_cache.dart',
      'lib/features/profit_and_loss/presentation/pnl_drilldown_providers.dart',
    ]);
  });

  test(
    'only the adapter builds a location, and every opening surface uses it',
    () {
      surfaces.forEach((path, code) {
        expect(locationBuilding(code), isEmpty, reason: path);
        expect(
          surfaceViolations(code, surfaceNavigation),
          isEmpty,
          reason: '$path routes somewhere itself',
        );
      });
      for (final path in _opening) {
        expect(
          surfaces[path],
          contains('openDashboardTarget('),
          reason: '$path opens nothing through the shared adapter',
        );
        expect(surfaces[path], contains('DashboardDrillTargets.of('));
      }
    },
  );

  test('the pane and the adapter compose no mutation surface', () {
    for (final (path, code) in [
      (_pane, File(_pane).readAsStringSync()),
      (_adapter, File(_adapter).readAsStringSync()),
    ]) {
      expect(mutationViolations(code), isEmpty, reason: path);
    }
    // The document is the immutable body the Phase 5 drill-down renders.
    expect(pane, contains('PnlDocumentDetail('));
  });

  test('no Owner Accounts value is reachable from a dashboard intent', () {
    for (final (path, code) in [(_adapter, adapter), (_pane, pane)]) {
      expect(
        surfaceViolations(code, surfaceOwnerAccounts),
        isEmpty,
        reason: path,
      );
    }
  });

  group('the guard fails when it should', () {
    test('a planted clock is seen', () {
      expect(
        reconstructedPeriod('final now = ref.read(reportingClockProvider)();'),
        isNotEmpty,
      );
      expect(
        reconstructedPeriod('DashboardPeriods.forUnits(k, t)'),
        isNotEmpty,
      );
    });

    test('a planted display name is seen', () {
      expect(
        displayIdentity(
          'revenueCategoryId: dashboardRevenueCategoryName(graph, id)',
        ),
        isNotEmpty,
      );
    });

    test('a planted second document query is seen', () {
      expect(
        drillReads('return source.revenueDocuments(scope: s, range: r);'),
        isNotEmpty,
      );
    });

    test('a planted location built by a surface is seen', () {
      expect(
        locationBuilding('open(PnlRevenueCategoriesAt(anchor));'),
        isNotEmpty,
      );
    });

    test('a planted mutable ledger panel is seen', () {
      expect(
        mutationViolations("child: RevenueDetailPanel(entry: entry),"),
        isNotEmpty,
      );
    });
  });
}
