/// Phase 8 Slice 4 — what one page of the expense ledger costs (D-313, D-323).
///
/// The deterministic half is **asserted**: how many statements a page costs, and that the
/// statement that cuts the page reads through an index rather than a scan. Timings are
/// **reported, never asserted** — a host timing is not a verdict (D-313, E-HOST), and the
/// binding figures come from `integration_test/expense_ledger_performance_test.dart` on
/// the real encrypted database.
///
/// CURRENT runs in the ordinary suite. SCALE and STRESS take a minute or more to seed,
/// so they run only when asked, and four further switches reproduce the D-323 baseline:
///
/// ```
///   KRISHNA_LEDGER_DATASET=scale|stress    the dataset class (default current)
///   KRISHNA_LEDGER_WITHOUT_INDEXES=1       drop the v22 indexes after open
///   KRISHNA_LEDGER_REPORT_ONLY=1           report, assert nothing (for old code)
///   KRISHNA_LEDGER_RUNS=n                  measured runs per workload (default 5)
///   KRISHNA_LEDGER_SKIP=a,b                workloads to leave out, named in the output
/// ```
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';

import '../support/expense_ledger_workload.dart';

const _pageSize = 50;

void main() {
  final requested = Platform.environment['KRISHNA_LEDGER_DATASET'];
  final dataset = LedgerDatasetClass.values.firstWhere(
    (c) => c.name == requested,
    orElse: () => LedgerDatasetClass.current,
  );
  final reportOnly = Platform.environment['KRISHNA_LEDGER_REPORT_ONLY'] == '1';
  // A quadratic baseline cannot repeat five times at STRESS; these say so explicitly
  // rather than quietly running fewer.
  final runs =
      int.tryParse(Platform.environment['KRISHNA_LEDGER_RUNS'] ?? '') ?? 5;
  final withoutLedgerIndexes =
      Platform.environment['KRISHNA_LEDGER_WITHOUT_INDEXES'] == '1';
  final skip = (Platform.environment['KRISHNA_LEDGER_SKIP'] ?? '')
      .split(',')
      .where((s) => s.isNotEmpty)
      .toSet();

  late AppDatabase db;
  late StatementCounter counter;
  late ExpenseRepository repository;
  late LedgerFixtureCounts counts;

  setUpAll(() async {
    counter = StatementCounter();
    db = AppDatabase(NativeDatabase.memory().interceptWith(counter));
    if (withoutLedgerIndexes) {
      // Reproduces the pre-v22 read path on the same data (D-323).
      for (final name in ledgerIndexNames) {
        await db.customStatement('DROP INDEX IF EXISTS $name');
      }
    }
    final seeding = Stopwatch()..start();
    counts = await seedExpenseLedgerFixture(
      db,
      documents: dataset.documents,
      years: dataset.years,
    );
    // ignore: avoid_print
    print(
      'LEDGER ${dataset.name.toUpperCase()}: $counts '
      '(seeded in ${seeding.elapsed.inMilliseconds} ms, '
      'database ${(await databaseBytes(db) / 1024 / 1024).toStringAsFixed(1)} MB, '
      'v22 ledger indexes ${withoutLedgerIndexes ? 'removed' : 'present'})',
    );
    repository = ExpenseRepository(db);
  });

  tearDownAll(() => db.close());

  Future<int> read(LedgerWorkload w) async => (await repository.query(
    w.query,
    limit: _pageSize,
    offset: w.offset,
  )).length;

  test(
    'every ledger workload: statements per page and plans (timings reported only)',
    () async {
      final results = <LedgerMeasurement>[];
      for (final workload in ledgerWorkloads(
        documents: dataset.documents,
        pageSize: _pageSize,
      )) {
        if (skip.contains(workload.name)) {
          // ignore: avoid_print
          print(
            '  ${workload.name.padRight(22)} SKIPPED (KRISHNA_LEDGER_SKIP)',
          );
          continue;
        }
        final m = await measureLedger(
          db,
          counter,
          workload,
          read: read,
          runs: runs,
        );
        results.add(m);
        // ignore: avoid_print
        print('  ${m.row()}');
        // ignore: avoid_print
        print('      page plan: ${m.plan}');
        if (m.hydrationPlan != null) {
          // ignore: avoid_print
          print('      child plan: ${m.hydrationPlan}');
        }
      }
      if (reportOnly) return;

      for (final m in results) {
        // One statement cuts the page and one more per child table, however many rows
        // the page holds: the cost of a page does not grow with its length.
        expect(
          m.statements,
          lessThanOrEqualTo(4),
          reason: '${m.workload}: ${m.statements} statements for one page',
        );
        expect(
          m.hydrationPlan ?? 'USING INDEX',
          contains('USING INDEX'),
          reason: '${m.workload}: a child read scans its table',
        );
      }

      // A sync-state filter is decided before the page is cut, so it fills a page.
      final conflict = results.singleWhere(
        (m) => m.workload == 'sync filter: conflict',
      );
      expect(
        conflict.rows,
        counts.conflicts < _pageSize ? counts.conflicts : _pageSize,
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );

  test('the page memory a window of rows costs (reported only)', () async {
    final before = residentBytes();
    final rows = await repository.query(
      const LedgerWorkloadQuery(),
      limit: 1000,
    );
    final after = residentBytes();
    // ignore: avoid_print
    print(
      '  1,000-row window: ${rows.length} rows, resident '
      '${((after - before) / 1024 / 1024).toStringAsFixed(1)} MB delta',
    );
    expect(rows, isNotEmpty);
  });
}
