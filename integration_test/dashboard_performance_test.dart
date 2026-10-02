/// The Phase 6 Slice 3 performance gate, on a real device, on the real encrypted database.
///
/// The host measurement (`test/data/dashboard_performance_test.dart`) runs on a plain
/// SQLite file on a development machine. Neither of those is what a manager uses: the
/// shipped database is SQLCipher-encrypted, and the phone that opens it is a long way from
/// this desk. A gate measured only on the host would be evidence about the wrong machine.
///
/// So this runs **the same workloads, from the same shared fixture**, against a real
/// encrypted database in the application's own storage directory, on whichever platform it
/// is pointed at:
///
/// ```
///   flutter test integration_test/dashboard_performance_test.dart -d windows
///   flutter test integration_test/dashboard_performance_test.dart -d emulator-5554
/// ```
///
/// It needs no backend and creates no fixture anywhere but its own temporary database,
/// which it deletes afterwards.
///
/// **Timings are reported, never asserted** (D-075). The deterministic half — how many
/// reports each dashboard costs — is asserted, here as on the host.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/dashboard_engine.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/canonical_cache_lock.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/dashboard_workload.dart';

const _me = 'user-me';

/// A fixed key for a throwaway measurement database. It protects nothing real: the
/// database it opens holds generated fixture rows and is deleted when the run ends. The
/// production key is generated per installation and lives in the platform secure store
/// (D-022, D-036, D-249) and is deliberately not touched here.
const _fixtureKey =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

/// Unscoped P&L read authority. Authorisation is not what this run measures.
Principal _principal() => Principal(
  userId: _me,
  grants: const [
    CapabilityGrant(Capability.reportsView),
    CapabilityGrant(Capability.revenueView),
    CapabilityGrant(Capability.expenseViewAll),
  ],
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final platform = Platform.operatingSystem;
  late File file;
  late AppDatabase db;

  setUpAll(() async {
    // Never the installation's folder on Windows (D-247): a temporary one.
    final directory = Platform.isWindows
        ? Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}krishna_mis_perf',
          )
        : await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    file = File('${directory.path}/krishna_mis.dashboard_perf.db');
    if (file.existsSync()) file.deleteSync();

    db = openEncryptedDatabaseAt(file, _fixtureKey);

    final seeding = Stopwatch()..start();
    final rows = await seedDashboardFixture(
      db,
      years: [
        FinancialYear.of(BusinessDate.of(2026, 9, 17)),
        FinancialYear.of(BusinessDate.of(2025, 9, 17)),
      ],
      ownerUserId: _me,
    );
    seeding.stop();

    // The file must actually be encrypted, or this is a measurement of something else.
    expect(
      isFileEncrypted(file),
      isTrue,
      reason: 'the measurement database is not encrypted',
    );

    // ignore: avoid_print
    print(
      '\n=== Phase 6 Slice 3 — dashboard performance, $platform, '
      'REAL ENCRYPTED DATABASE ===\n'
      'fixture: ${rows.revenue} revenue contributions, ${rows.expense} expense '
      'contributions, 2 financial years, 2 properties\n'
      'database: ${file.path} (${(file.lengthSync() / 1024).round()} KiB)\n'
      'cache apply (the local half of a full synchronisation): '
      '${seeding.elapsedMilliseconds} ms',
    );
  });

  tearDownAll(() async {
    await db.close();
    if (file.existsSync()) file.deleteSync();
  });

  Future<DashboardEngine> engine() async {
    final cache = ReportingCache(db);
    return DashboardEngine(
      reports: LocalReportingEngine(
        CachedReportingSource(
          cache: cache,
          principal: _principal(),
          coverage: await MarkerCoverage.load(cache, _me),
        ),
      ),
      lock: CanonicalCacheLock(),
    );
  }

  testWidgets('every dashboard workload, on $platform', (tester) async {
    // Real file I/O and real SQLite: outside the fake-async zone (D-152).
    await tester.runAsync(() async {
      // ignore: avoid_print
      print(
        '\n  workload                                             '
        'reads  points   cold    warm',
      );

      for (final workload in dashboardWorkloads()) {
        final cold = Stopwatch()..start();
        final view = await (await engine()).build(workload.request);
        cold.stop();

        var warmest = 1 << 30;
        for (var i = 0; i < 3; i++) {
          final warm = Stopwatch()..start();
          await (await engine()).build(workload.request);
          warm.stop();
          if (warm.elapsedMicroseconds < warmest) {
            warmest = warm.elapsedMicroseconds;
          }
        }

        expect(view.isComputed, isTrue, reason: workload.name);
        expect(
          view.stats.rangesRead,
          workload.expectedReads,
          reason: '${workload.name} read a different number of ranges',
        );
        expect(
          view.stats.trendPoints,
          workload.expectedTrendPoints,
          reason: '${workload.name} plotted a different number of points',
        );

        // ignore: avoid_print
        print(
          '  ${workload.name.padRight(52)}'
          '${view.stats.rangesRead.toString().padLeft(5)}'
          '${view.stats.trendPoints.toString().padLeft(8)}'
          '${'${cold.elapsedMilliseconds} ms'.padLeft(8)}'
          '${'${(warmest / 1000).round()} ms'.padLeft(8)}',
        );
      }

      // One report through the same engine, so the dashboard's cost reads as "n reports"
      // rather than as an unexplained total.
      final single = dashboardWorkloads().firstWhere(
        (w) => w.name.startsWith('month to date'),
      );
      final headline = Stopwatch()..start();
      final view = await (await engine()).build(
        DashboardRequest(
          pair: single.request.pair,
          scope: single.request.scope,
        ),
      );
      headline.stop();
      expect(view.stats.rangesRead, 2);
      // ignore: avoid_print
      print(
        '\n  headline + comparator alone (2 reads): '
        '${headline.elapsedMilliseconds} ms\n',
      );
    });
  });
}
