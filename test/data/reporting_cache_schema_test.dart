/// Local schema **v17** — the canonical reporting cache, and the migration that adds it.
///
/// Phase 5 Slice 4. Three tables that hold server-owned financial facts so a device can
/// report a property's P&L including transactions it never recorded (D-171).
///
/// Three things are pinned here, and each is a rule rather than a shape.
///
/// **Every row is owned by a user.** A back-office workstation is shared — that is the
/// whole reason D-054 added a sign-out control and D-074 exists — so a cached figure is a
/// fact about *a person's* authority at a moment, not about the installation. Every
/// primary key and every index leads with `owner_user_id`, which makes User B reading
/// User A's figures structurally unavailable rather than something a query must remember.
///
/// **A migration synchronises nothing.** The tables arrive empty and carry no coverage
/// marker, so an upgraded device reports `notDownloaded` until it has actually asked the
/// server. Certifying a year complete because a schema step ran is exactly the false
/// claim the marker exists to prevent (D-108).
///
/// **Nothing local authors these amounts.** Asserted over `lib/` rather than argued,
/// because a rule is worth only as much as the thing that evaluates it (D-068, D-071).
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/expense_fixtures.dart' show createTempDatabaseFile;

const _reportingTables = [
  'reporting_revenue_contributions',
  'reporting_expense_contributions',
  'reporting_coverage_markers',
];

const _reportingIndexes = [
  'ix_reporting_revenue_period',
  'ix_reporting_revenue_date',
  'ix_reporting_revenue_document',
  'ix_reporting_expense_period',
  'ix_reporting_expense_date',
  'ix_reporting_expense_document',
];

/// Rewinds a database built from the current schema back to [version] by removing what
/// the later steps added. A fixture that claims to be an older schema has to actually be
/// one — the trap D-144 and D-159 both record.
Future<void> _rewindTo(AppDatabase db, int version) async {
  for (final index in _reportingIndexes) {
    await db.customStatement('DROP INDEX IF EXISTS $index');
  }
  for (final table in _reportingTables) {
    await db.customStatement('DROP TABLE IF EXISTS $table');
  }
  if (version < 16) {
    await db.customStatement(
      'DROP VIEW IF EXISTS expense_period_contributions',
    );
    await db.customStatement(
      'DROP INDEX IF EXISTS ix_expense_contributions_reporting',
    );
  }
  await db.customStatement('PRAGMA user_version = $version');
}

Future<Set<String>> _objects(AppDatabase db, String type) async {
  final rows = await db
      .customSelect(
        'SELECT name FROM sqlite_master WHERE type = ?',
        variables: [Variable<String>(type)],
      )
      .get();
  return {for (final row in rows) row.read<String>('name')};
}

Future<List<String>> _primaryKey(AppDatabase db, String table) async {
  final columns = await db.customSelect('PRAGMA table_info($table)').get();
  final key = columns.where((c) => c.read<int>('pk') > 0).toList()
    ..sort((a, b) => a.read<int>('pk').compareTo(b.read<int>('pk')));
  return [for (final column in key) column.read<String>('name')];
}

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  group('a fresh database is born with the reporting cache', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.customStatement('PRAGMA foreign_keys = ON');
    });
    tearDown(() => db.close());

    test('the schema is at least v17', () async {
      expect(
        db.schemaVersion,
        greaterThanOrEqualTo(17),
        reason:
            'a lower bound, not a literal — the subject is "the current schema has the '
            'reporting cache", and a hard-coded number needs editing on every bump '
            '(D-144, D-159)',
      );
    });

    test('all three tables exist, and they are tables', () async {
      final tables = await _objects(db, 'table');
      for (final table in _reportingTables) {
        expect(tables, contains(table));
      }
    });

    test('every index exists and leads with the owner', () async {
      final indexes = await _objects(db, 'index');
      for (final index in _reportingIndexes) {
        expect(
          indexes,
          contains(index),
          reason:
              'added to onCreate as well as to the upgrade step — a fresh database '
              'lacking an index the upgrade path has is the defect D-159 recorded',
        );
        final sql =
            (await db
                    .customSelect(
                      'SELECT sql FROM sqlite_master WHERE name = ?',
                      variables: [Variable<String>(index)],
                    )
                    .getSingle())
                .read<String>('sql');
        expect(
          sql.split('(')[1].trimLeft(),
          startsWith('owner_user_id'),
          reason:
              'a reporting read is always "this person, this property" — an index that '
              'did not lead with the owner would invite a query that omitted it (D-074)',
        );
      }
    });

    test('every primary key leads with the owner', () async {
      for (final table in _reportingTables) {
        expect(
          (await _primaryKey(db, table)).first,
          'owner_user_id',
          reason: '$table is keyed per person before anything else (D-074)',
        );
      }
    });

    test('the coverage marker names one scope and one dataset', () async {
      expect(
        (await _primaryKey(db, 'reporting_coverage_markers')).toSet(),
        {'owner_user_id', 'business_unit_id', 'dataset', 'financial_year'},
        reason:
            'the smallest thing that can honestly be complete on its own: revenue may '
            'synchronise while expenses fail, and a P&L needs both (D-163)',
      );
    });

    test('the dataset vocabulary is closed', () async {
      await db.customStatement(
        "INSERT INTO reporting_coverage_markers (owner_user_id, org_id, "
        "business_unit_id, dataset, financial_year, generation, on_demand, updated_at) "
        "VALUES ('u1', 'org-1', 'unit-ccr', 'revenue', 2026, 10, 0, "
        "'2026-09-07T00:00:00.000Z')",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO reporting_coverage_markers (owner_user_id, org_id, "
          "business_unit_id, dataset, financial_year, generation, on_demand, "
          "updated_at) VALUES ('u1', 'org-1', 'unit-ccr', 'profit', 2026, 10, 0, "
          "'2026-09-07T00:00:00.000Z')",
        ),
        throwsA(anything),
        reason:
            'a dataset the synchroniser cannot produce would be a marker nothing could '
            'ever satisfy — the shape D-116 records',
      );
    });

    test('two people may hold the same contribution independently', () async {
      for (final owner in const ['user-a', 'user-b']) {
        await db.customStatement(
          "INSERT INTO reporting_revenue_contributions (owner_user_id, org_id, "
          "contribution_id, revenue_entry_id, business_unit_id, revenue_category_id, "
          "pnl_date, pnl_period_key, gross_minor, tax_minor, net_minor, tax_treatment, "
          "tax_rate_basis_points, entered_basis, financial_year, document_generation, "
          "synced_at) VALUES (?, 'org-1', 'c1', 'r1', 'unit-ccr', 'cat-rest', "
          "'2026-06-15', '2026-06', 10000000, 476190, 9523810, 'inclusive', 500, "
          "'inclusive_total', 2026, 40, '2026-09-07T00:00:00.000Z')",
          [owner],
        );
      }
      expect(
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM reporting_revenue_contributions',
                )
                .getSingle())
            .read<int>('n'),
        2,
        reason:
            'one server fact, cached twice, because two people synchronised it under '
            'their own authority — and neither may read the other (D-074)',
      );
    });
  });

  group('the v16 to v17 migration', () {
    test('an accumulated device keeps its history and gains an empty cache', () async {
      final file = await createTempDatabaseFile();
      addTearDown(() => file.parent.deleteSync(recursive: true));

      final seeded = AppDatabase(NativeDatabase(file));
      await seeded.customStatement('PRAGMA foreign_keys = OFF');
      await seeded.customStatement(
        "INSERT INTO expenses (id, org_id, txn_number, financial_year, business_date, "
        "business_date_source, visibility, document_total_minor, visible_amount_minor, "
        "is_shared, payment_status, created_by, captured_at, row_version, updated_at) "
        "VALUES ('e1', 'org-1', 'KI-EXP-26-27-000100', 2026, '2026-06-15', 'derived', "
        "'complete', 500000, 500000, 0, 'unpaid', 'user-1', "
        "'2026-06-15T10:00:00.000Z', 1, '2026-06-15T10:00:00.000Z')",
      );
      await _rewindTo(seeded, 16);
      await seeded.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final tables = await _objects(upgraded, 'table');
      for (final table in _reportingTables) {
        expect(tables, contains(table));
      }
      final indexes = await _objects(upgraded, 'index');
      for (final index in _reportingIndexes) {
        expect(indexes, contains(index));
      }

      expect(
        (await upgraded
                .customSelect('SELECT COUNT(*) AS n FROM expenses')
                .getSingle())
            .read<int>('n'),
        1,
        reason: 'the upgrade adds tables and touches nothing already there',
      );

      for (final table in _reportingTables) {
        expect(
          (await upgraded
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
          0,
          reason:
              'a migration synchronises nothing. In particular there is no coverage '
              'marker, so this device reports notDownloaded until it has asked the '
              'server — certifying a year because a schema step ran is the claim the '
              'marker exists to prevent (D-108)',
        );
      }
    });

    test('a v15 device reaches v17 through both steps', () async {
      final file = await createTempDatabaseFile();
      addTearDown(() => file.parent.deleteSync(recursive: true));

      final seeded = AppDatabase(NativeDatabase(file));
      await seeded.customStatement('PRAGMA foreign_keys = OFF');
      await _rewindTo(seeded, 15);
      await seeded.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      final tables = await _objects(upgraded, 'table');
      for (final table in _reportingTables) {
        expect(tables, contains(table));
      }
      expect(
        await _objects(upgraded, 'view'),
        contains('expense_period_contributions'),
        reason:
            'the v17 step is written before the v16 step in source order and both must '
            'still run — the ordering hazard D-144 records, in the direction where a '
            'skipped step is silent',
      );
    });
  });

  group('nothing local authors a cached financial amount', () {
    test('only the reporting cache writes these tables', () async {
      const permitted = [
        // The one writer.
        'lib/data/reporting/reporting_cache.dart',
        // Declarations and schema wiring: they name the tables and write no row.
        'lib/data/local/reporting_tables.dart',
        'lib/data/local/app_database.dart',
      ];

      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.g.dart')) continue;
        final normalised = entity.path.replaceAll(Platform.pathSeparator, '/');
        if (permitted.any(normalised.endsWith)) continue;

        final source = entity.readAsStringSync();
        for (final table in _reportingTables) {
          // Deleting is not authoring: the scope purge legitimately removes rows.
          final authors = RegExp(
            '(insert|update|replace)[^;]{0,200}$table',
            caseSensitive: false,
          );
          if (authors.hasMatch(source)) offenders.add('$normalised -> $table');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'these rows are server-owned (D-171). One writer is what makes a cached '
            'figure provably the server\'s own — and it is why the canonical-only '
            'predicate is unnecessary here rather than merely remembered (D-168)',
      );
    });
  });
}
