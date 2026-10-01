/// Phase 8 Slice 4 — the expense ledger on the real encrypted database (D-313, D-323).
///
/// The host measurement (`test/data/expense_ledger_performance_test.dart`) asserts what a
/// page costs in statements and plans; a host timing is not a verdict. This runs **the
/// same workloads from the same shared fixture** against a SQLCipher-encrypted database in
/// the application's own storage directory:
///
/// ```
///   flutter test integration_test/expense_ledger_performance_test.dart -d windows
///   flutter test integration_test/expense_ledger_performance_test.dart -d <android device>
/// ```
///
/// Options, as `--dart-define`s: `KRISHNA_LEDGER_DATASETS` (comma list of current, scale,
/// stress; default all three), `KRISHNA_LEDGER_RUNS` (default 5),
/// `KRISHNA_LEDGER_SKIP` (comma list of workload names) and
/// `KRISHNA_LEDGER_WITHOUT_INDEXES=1` (drops the v22 indexes to reproduce the pre-v22
/// read path on the same data).
///
/// It needs no backend and creates nothing but its own temporary database, deleted at the
/// end. **Timings are reported, never asserted** (D-075).
library;

import 'dart:io';

import 'package:drift/drift.dart' show ApplyInterceptor;
import 'package:drift/native.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/expense_ledger_workload.dart';

/// A fixed key for a throwaway measurement database holding generated rows only. The
/// production key lives in the platform secure store and is not touched (D-022, D-249).
const _fixtureKey =
    'b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90a1';

const _datasets = String.fromEnvironment(
  'KRISHNA_LEDGER_DATASETS',
  defaultValue: 'current,scale,stress',
);
const _runs = int.fromEnvironment('KRISHNA_LEDGER_RUNS', defaultValue: 5);
const _skip = String.fromEnvironment('KRISHNA_LEDGER_SKIP');
const _withoutIndexes = bool.fromEnvironment('KRISHNA_LEDGER_WITHOUT_INDEXES');
const _pageSize = 50;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final skip = _skip.split(',').where((s) => s.isNotEmpty).toSet();

  for (final dataset in LedgerDatasetClass.values) {
    if (!_datasets.split(',').contains(dataset.name)) continue;

    test(
      'expense ledger, ${dataset.name}, on ${Platform.operatingSystem}',
      () async {
        final directory = await getApplicationSupportDirectory();
        await directory.create(recursive: true);
        final file = File(
          '${directory.path}/krishna_mis.ledger_perf.${dataset.name}.db',
        );
        if (file.existsSync()) file.deleteSync();

        final counter = StatementCounter();
        final db = openEncryptedDatabaseAt(file, _fixtureKey);
        try {
          await db.customSelect('SELECT 1').get();
          if (_withoutIndexes) {
            for (final name in ledgerIndexNames) {
              await db.customStatement('DROP INDEX IF EXISTS $name');
            }
          }
          final seeding = Stopwatch()..start();
          final counts = await seedExpenseLedgerFixture(
            db,
            documents: dataset.documents,
            years: dataset.years,
          );
          final seeded = seeding.elapsed;
          await db.close();
          expect(isFileEncrypted(file), isTrue);

          final measured = AppDatabase(
            NativeDatabase(
              file,
              setup: (d) => applyEncryptionKey(d, _fixtureKey),
            ).interceptWith(counter),
          );
          try {
            final repository = ExpenseRepository(measured);
            // ignore: avoid_print
            print(
              'E-${Platform.operatingSystem.toUpperCase()} LEDGER '
              '${dataset.name.toUpperCase()}: $counts; seeded in '
              '${seeded.inMilliseconds} ms; file '
              '${(file.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB; '
              'v22 indexes ${_withoutIndexes ? 'removed' : 'present'}; '
              'runs $_runs',
            );
            for (final workload in ledgerWorkloads(
              documents: dataset.documents,
              pageSize: _pageSize,
            )) {
              if (skip.contains(workload.name)) {
                // ignore: avoid_print
                print('  ${workload.name.padRight(22)} SKIPPED');
                continue;
              }
              final m = await measureLedger(
                measured,
                counter,
                workload,
                runs: _runs,
                read: (w) async => (await repository.query(
                  w.query,
                  limit: _pageSize,
                  offset: w.offset,
                )).length,
              );
              // ignore: avoid_print
              print('  ${m.row()}');
            }
          } finally {
            await measured.close();
          }
        } finally {
          if (file.existsSync()) file.deleteSync();
        }
      },
      timeout: const Timeout(Duration(hours: 2)),
    );
  }
}
