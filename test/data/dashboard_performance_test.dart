/// The Phase 6 Slice 3 performance gate, on the host.
///
/// The gate the project lead set: measure representative financial-year workloads on the
/// **existing** Phase 5 reporting foundation, and add no dashboard RPC, second cache,
/// materialised aggregate, index or server function unless the measurement says the
/// existing approach is unsuitable.
///
/// So this measures the shipped path and nothing else — a file-backed SQLite database, the
/// real canonical reporting cache holding two financial years of trade for two properties,
/// the real `MarkerCoverage`, `CachedReportingSource`, `LocalReportingEngine` and
/// `DashboardEngine`, under the real `CanonicalCacheLock`.
///
/// **Timings are reported, never asserted.** A wall-clock threshold in a suite that shares
/// a machine with a build is a test that fails for reasons unrelated to the product
/// (D-075). What *is* asserted is the deterministic half — how many reports each dashboard
/// costs and how many points it plots — because a regression that doubled the work would
/// otherwise show up only as "the machine was busy".
///
/// The on-device half, against the real encrypted database, is
/// `integration_test/dashboard_performance_test.dart`.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/dashboard_engine.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/canonical_cache_lock.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/value_objects/business_date.dart';

import '../support/cache_principal.dart';
import '../support/dashboard_workload.dart';

const _me = 'user-me';

void main() {
  late Directory dir;
  late File file;
  late AppDatabase db;
  late ({int revenue, int expense}) rows;

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('krishna-dashboard-perf');
    file = File('${dir.path}/perf.db');
    db = AppDatabase(NativeDatabase(file));

    final seeding = Stopwatch()..start();
    rows = await seedDashboardFixture(
      db,
      years: [
        FinancialYear.of(BusinessDate.of(2026, 9, 17)),
        FinancialYear.of(BusinessDate.of(2025, 9, 17)),
      ],
      ownerUserId: _me,
    );
    seeding.stop();

    // ignore: avoid_print
    print(
      '\n=== Phase 6 Slice 3 — dashboard performance, host (Windows) ===\n'
      'fixture: ${rows.revenue} revenue contributions, ${rows.expense} expense '
      'contributions, 2 financial years, 2 properties\n'
      'database: ${file.path} '
      '(${(file.lengthSync() / 1024).round()} KiB, unencrypted host file)\n'
      'cache apply (the local half of a full synchronisation): '
      '${seeding.elapsedMilliseconds} ms',
    );
  });

  tearDownAll(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<DashboardEngine> engine() async => DashboardEngine(
    reports: LocalReportingEngine(
      CachedReportingSource(
        cache: ReportingCache(db),
        principal: canonicalCachePrincipal(_me),
        coverage: await MarkerCoverage.load(ReportingCache(db), _me),
      ),
    ),
    lock: CanonicalCacheLock(),
  );

  test('every workload computes, and costs what the plan says', () async {
    // ignore: avoid_print
    print(
      '\n  workload                                             '
      'reads  points   cold    warm',
    );

    for (final workload in dashboardWorkloads()) {
      final cold = Stopwatch()..start();
      final first = await (await engine()).build(workload.request);
      cold.stop();

      // Three more, so a warm figure is not one sample. The cache is the operating
      // system's page cache and SQLite's own — nothing in this product caches a report
      // (D-074), and the second run proves it by still doing all the work.
      var warmest = 1 << 30;
      for (var i = 0; i < 3; i++) {
        final warm = Stopwatch()..start();
        await (await engine()).build(workload.request);
        warm.stop();
        if (warm.elapsedMicroseconds < warmest) {
          warmest = warm.elapsedMicroseconds;
        }
      }

      expect(
        first.isComputed,
        isTrue,
        reason: '${workload.name} did not compute',
      );
      expect(
        first.stats.rangesRead,
        workload.expectedReads,
        reason: '${workload.name} read a different number of ranges',
      );
      expect(
        first.stats.trendPoints,
        workload.expectedTrendPoints,
        reason: '${workload.name} plotted a different number of points',
      );
      expect(
        first.trends.every((s) => !s.hasGap),
        isTrue,
        reason: '${workload.name} has a gap over a fully synchronised fixture',
      );

      // ignore: avoid_print
      print(
        '  ${workload.name.padRight(52)}'
        '${first.stats.rangesRead.toString().padLeft(5)}'
        '${first.stats.trendPoints.toString().padLeft(8)}'
        '${'${cold.elapsedMilliseconds} ms'.padLeft(8)}'
        '${'${(warmest / 1000).round()} ms'.padLeft(8)}',
      );
    }
  });

  test(
    'the per-read cost is the reporting engine\'s, not the dashboard\'s',
    () async {
      // One P&L for the same range, through the same engine, so the dashboard's cost can
      // be read as "n reports" rather than as an unexplained total.
      final workload = dashboardWorkloads().firstWhere(
        (w) => w.name.startsWith('month to date'),
      );
      final single = DashboardRequest(
        pair: workload.request.pair,
        scope: workload.request.scope,
      );

      final headlineOnly = Stopwatch()..start();
      final view = await (await engine()).build(single);
      headlineOnly.stop();

      expect(view.stats.rangesRead, 2);
      // ignore: avoid_print
      print(
        '\n  headline + comparator alone (2 reads): '
        '${headlineOnly.elapsedMilliseconds} ms\n',
      );
    },
  );
}
