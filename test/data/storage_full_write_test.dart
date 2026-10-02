/// Phase 8 Slice 7 — a financial save that meets a full disk.
///
/// The disk is not filled. SQLite's own limit, `PRAGMA max_page_count`, makes the
/// database refuse to grow, which raises the same `SQLITE_FULL` a full disk raises, at the
/// same point in the engine — so the save is interrupted exactly where a real one would
/// be, without touching the machine's storage (D-329).
library;

import 'dart:io';

import 'package:drift/drift.dart' show CouldNotRollBackException;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/startup/startup_failure.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

void main() {
  late File file;
  final now = DateTime.utc(2026, 6, 15, 9, 30);

  setUp(() async {
    file = await createTempDatabaseFile();
    final db = AppDatabase(NativeDatabase(file));
    await seedMasterData(db, now: now);
    await db.close();
  });

  tearDown(() {
    try {
      file.deleteSync();
    } on FileSystemException {
      // left for the OS temp sweep
    }
  });

  Future<({int expenses, int lines, int queued})> counts(AppDatabase db) async {
    Future<int> n(String sql) async =>
        (await db.customSelect(sql).getSingle()).read<int>('n');
    return (
      expenses: await n('SELECT COUNT(*) AS n FROM expenses'),
      lines: await n('SELECT COUNT(*) AS n FROM expense_allocations'),
      queued: await n(
        "SELECT COUNT(*) AS n FROM sync_outbox WHERE entity_type = 'expense'",
      ),
    );
  }

  test(
    'a save refused for space writes nothing — no document without its queue entry, '
    'no queue entry without its document — and a retry saves it exactly once',
    () async {
      // The database may not grow past the pages it has now.
      final capped = AppDatabase(
        NativeDatabase(
          file,
          setup: (raw) {
            final pages = raw.select('PRAGMA page_count').first.values.first;
            raw.execute('PRAGMA max_page_count = $pages');
          },
        ),
      );
      await capped.customStatement('PRAGMA foreign_keys = ON');
      final repository = ExpenseRepository(capped);

      Object? refusal;
      String? refusedId;
      for (var i = 0; i < 5000 && refusal == null; i++) {
        final expense = simpleExpense();
        try {
          await repository.createLocally(
            expense,
            actorUserId: 'user-1',
            mutationId: const Uuid().v4(),
            now: now,
          );
        } on Object catch (error) {
          refusal = error;
          refusedId = expense.id;
        }
      }
      expect(refusal, isNotNull, reason: 'the cap was never reached');
      // SQLite rolls back by itself on SQLITE_FULL, so drift's own ROLLBACK finds no
      // transaction and wraps the cause. What matters is that the cause is SQLITE_FULL.
      final cause = refusal is CouldNotRollBackException
          ? refusal.cause
          : refusal;
      expect(cause, isA<SqliteException>());
      expect((cause! as SqliteException).resultCode, 13); // SQLITE_FULL
      expect(
        StartupFailure.classify(refusal!).kind,
        StartupFailureKind.storage,
        reason: 'reported as storage, never as damage',
      );

      final after = await counts(capped);
      expect(
        after.queued,
        after.expenses,
        reason: 'one queue entry per document',
      );
      expect(
        after.lines,
        after.expenses,
        reason: 'one line per simple expense',
      );
      expect(await repository.load(refusedId!), isNull);
      await capped.close();

      // Space returns; the same document is saved once, with one queue entry.
      final free = AppDatabase(NativeDatabase(file));
      await free.customStatement('PRAGMA foreign_keys = ON');
      final retried = simpleExpense();
      await ExpenseRepository(free).createLocally(
        retried,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      final finalCounts = await counts(free);
      expect(finalCounts.expenses, after.expenses + 1);
      expect(finalCounts.queued, after.queued + 1);
      final integrity = await free.customSelect('PRAGMA integrity_check').get();
      expect(integrity.single.data.values.single, 'ok');
      await free.close();
    },
  );
}
