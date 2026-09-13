/// Local schema **v21** — the settlement start date, on the coverage row that certified it.
///
/// Phase 5 OA-3 Q1. One nullable column, and three things pinned about it:
///
/// * a fresh database is born with it;
/// * a genuine v20 device upgrades, keeps its coverage row, and reads **not configured**
///   rather than a guessed date — a migration certifies nothing (D-108);
/// * a device arriving from v19 or earlier does not trip over its own step: the table is
///   created from the current definition, which already carries the column, and the
///   `from >= 20` guard is what stops a `duplicate column` failure (D-144).
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';

import '../support/expense_fixtures.dart' show createTempDatabaseFile;
import '../support/cache_principal.dart';

Future<Set<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.read<String>('name')};
}

Future<int> _userVersion(AppDatabase db) async =>
    (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
      'user_version',
    );

void main() {
  late File file;

  setUp(() async => file = await createTempDatabaseFile());
  tearDown(() {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // left for the OS temp sweep (a failed test may still hold the handle on Windows)
    }
  });

  test('a fresh database is born at v21 with the start-date column', () async {
    final db = AppDatabase(NativeDatabase(file));
    await db.customSelect('SELECT 1').get();

    expect(await _userVersion(db), db.schemaVersion);
    expect(db.schemaVersion, greaterThanOrEqualTo(21));
    expect(
      await _columns(db, 'owner_settlement_coverage'),
      contains('ownership_start_date'),
    );
    await db.close();
  });

  test(
    'a v20 device upgrades, keeps its coverage, and reads "not configured"',
    () async {
      final seeded = AppDatabase(NativeDatabase(file));
      await seeded.customSelect('SELECT 1').get();

      // Rewind to a genuine v20: the column did not exist then.
      await seeded.customStatement(
        'ALTER TABLE owner_settlement_coverage DROP COLUMN ownership_start_date',
      );
      await seeded.customStatement(
        'INSERT INTO owner_settlement_coverage '
        '(owner_user_id, snapshot_id, server_confirmed_at, movement_count, updated_at) '
        "VALUES ('user-1', 'snap-v20', '2026-09-10T10:00:00.000Z', 7, "
        "'2026-09-10T10:00:00.000Z')",
      );
      await seeded.customStatement('PRAGMA user_version = 20');
      expect(
        await _columns(seeded, 'owner_settlement_coverage'),
        isNot(contains('ownership_start_date')),
        reason: 'the fixture must genuinely be a v20 schema',
      );
      await seeded.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      await upgraded.customSelect('SELECT 1').get();

      expect(await _userVersion(upgraded), upgraded.schemaVersion);
      final coverage = await OwnerSettlementRepository(
        upgraded,
        principal: canonicalCachePrincipal('user-1'),
      ).coverage();
      expect(coverage, isNotNull, reason: 'the coverage row is kept');
      expect(coverage!.snapshotId, 'snap-v20');
      expect(coverage.movementCount, 7);
      expect(
        coverage.ownershipStartDate,
        isNull,
        reason:
            'certified by a transport that did not carry the date. Not configured until '
            'the next synchronisation states it — never guessed by a migration',
      );
      await upgraded.close();
    },
  );

  test(
    'a device from v19 reaches v21 without a duplicate column (D-144)',
    () async {
      final seeded = AppDatabase(NativeDatabase(file));
      await seeded.customSelect('SELECT 1').get();
      // v19 had none of the OA-2 tables.
      for (final table in const [
        'owner_settlement_coverage',
        'canonical_owner_movements',
        'canonical_ownership_shares',
        'canonical_owners',
      ]) {
        await seeded.customStatement('DROP TABLE IF EXISTS $table');
      }
      await seeded.customStatement('PRAGMA user_version = 19');
      await seeded.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      await upgraded.customSelect('SELECT 1').get();

      expect(await _userVersion(upgraded), upgraded.schemaVersion);
      expect(
        await _columns(upgraded, 'owner_settlement_coverage'),
        contains('ownership_start_date'),
      );
      await upgraded.close();
    },
  );
}
