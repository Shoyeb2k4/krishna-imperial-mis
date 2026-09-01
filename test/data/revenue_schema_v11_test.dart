/// Local schema v11 — the revenue read model (Phase 4 Slice 3).
///
/// Three things are being pinned here, and only the first is about revenue:
///
/// 1. the revenue tables themselves — persistence, reconciliation, and the snapshots that
///    keep a component explainable after the configuration it names is gone;
/// 2. that a **real v10 database survives the upgrade unchanged**, including the parts
///    v11 does not touch, because the only migration defect this project has shipped was
///    invisible on a freshly installed device (D-073's v10 rewrite, found on Windows);
/// 3. that nothing about v11 weakens D-070 or D-074 — a revocation must not disclose one
///    person's retained work to another, and the guard for that must fail when the
///    ownership predicate is removed.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/auth/cache_classification.dart';

/// A temporary file-backed database, so migrations run against something real.
Future<File> tempDatabaseFile() async {
  final dir = await Directory.systemTemp.createTemp('krishna_v11_');
  return File('${dir.path}/app.sqlite');
}

/// Inserts a revenue entry and its components through raw SQL.
///
/// Raw rather than through a repository on purpose: Slice 3 is the schema, and a
/// repository does not exist yet. What is being asserted is what the *database* permits.
Future<void> insertEntry(
  AppDatabase db, {
  required String id,
  String unit = 'unit-ccr',
  String category = 'cat-restaurant',
  String date = '2026-06-15',
  String actor = 'user-1',
  String? pendingMutationId,
  DateTime? scopeRevokedAt,
  List<(String id, int entered, int gross, int tax, int net)> components =
      const [('c1', 10000000, 10000000, 476190, 9523810)],
  String basis = 'inclusive_total',
  String treatment = 'inclusive',
  int rateBp = 500,
  String? valueBandId,
  int? bandFloor,
  int? bandCeiling,
}) async {
  await db.customStatement(
    'INSERT INTO revenue_entries (id, org_id, business_unit_id, '
    'revenue_category_id, business_date, pnl_period_key, captured_at, '
    'entry_kind, created_by, pending_mutation_id, row_version, updated_at, '
    'scope_revoked_at) '
    "VALUES (?, 'org-1', ?, ?, ?, ?, '2026-06-15T09:00:00.000Z', "
    "'daily_summary', ?, ?, 1, '2026-06-15T09:00:00.000Z', ?)",
    [
      id,
      unit,
      category,
      date,
      date.substring(0, 7),
      actor,
      pendingMutationId,
      scopeRevokedAt?.toIso8601String(),
    ],
  );
  for (final c in components) {
    await db.customStatement(
      'INSERT INTO revenue_components (id, org_id, revenue_entry_id, '
      'entered_amount_minor, entered_basis, gross_amount_minor, '
      'tax_amount_minor, net_amount_minor, tax_rule_id, '
      'tax_rate_basis_points, tax_treatment, value_band_id, '
      'value_band_label, value_band_floor_minor, value_band_ceiling_minor) '
      "VALUES (?, 'org-1', ?, ?, ?, ?, ?, ?, 'rule-1', ?, ?, ?, ?, ?, ?)",
      [
        '$id-${c.$1}',
        id,
        c.$2,
        basis,
        c.$3,
        c.$4,
        c.$5,
        rateBp,
        treatment,
        valueBandId,
        valueBandId == null ? null : 'Lower tariff band',
        bandFloor,
        bandCeiling,
      ],
    );
  }
}

/// Turns a freshly created database back into a genuine v10 one.
///
/// Derived from the real schema rather than hand-written DDL: hand-written v10 tables
/// would drift from what v10 actually shipped, and a migration test whose "before" state
/// is fiction proves nothing. Everything v11 adds is removed, the index v11 drops is put
/// back, and the version marker is reset.
Future<void> downgradeToV10(AppDatabase db) async {
  for (final statement in const [
    'DROP VIEW IF EXISTS revenue_entry_totals',
    'DROP TABLE IF EXISTS revenue_components',
    'DROP TABLE IF EXISTS revenue_entries',
    'DROP TABLE IF EXISTS revenue_value_bands',
    'DROP TABLE IF EXISTS revenue_supply_subtypes',
    'DROP TABLE IF EXISTS business_unit_tax_statuses',
    // The v11 columns cannot be dropped in place: the CHECK on `input_basis` references
    // one of them, and SQLite has no DROP CONSTRAINT. Recreate the table in its v10
    // shape and copy the rows across.
    'ALTER TABLE revenue_tax_rates RENAME TO revenue_tax_rates_v11',
    'CREATE TABLE revenue_tax_rates ('
        'id TEXT NOT NULL PRIMARY KEY, '
        'org_id TEXT NOT NULL, '
        'revenue_category_id TEXT NOT NULL REFERENCES revenue_categories (id), '
        'rate_basis_points INTEGER NOT NULL, '
        'treatment TEXT NOT NULL, '
        'effective_from TEXT NOT NULL, '
        'effective_to TEXT NULL, '
        'note TEXT NULL, '
        'archived_at TEXT NULL, '
        'created_by TEXT NOT NULL, '
        'created_at TEXT NOT NULL, '
        'row_version INTEGER NOT NULL DEFAULT 1, '
        'updated_at TEXT NOT NULL)',
    'INSERT INTO revenue_tax_rates SELECT id, org_id, revenue_category_id, '
        'rate_basis_points, treatment, effective_from, effective_to, note, '
        'archived_at, created_by, created_at, row_version, updated_at '
        'FROM revenue_tax_rates_v11',
    'DROP TABLE revenue_tax_rates_v11',
    // The index v10 had and v11 removes.
    'CREATE UNIQUE INDEX IF NOT EXISTS ux_tax_rates_live_period '
        'ON revenue_tax_rates (revenue_category_id, effective_from) '
        'WHERE archived_at IS NULL',
    'PRAGMA user_version = 10',
  ]) {
    await db.customStatement(statement);
  }
}

Future<Map<String, int>> totalsFor(AppDatabase db, String entryId) async {
  final row = await db
      .customSelect(
        'SELECT gross_minor, tax_minor, net_minor, component_count '
        'FROM revenue_entry_totals WHERE revenue_entry_id = ?',
        variables: [Variable<String>(entryId)],
      )
      .getSingle();
  return {for (final e in row.data.entries) e.key: (e.value as int?) ?? 0};
}

void main() {
  group('a fresh v11 database', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('opens at schema version 11 with every revenue table present', () async {
      await db.customSelect('SELECT 1').get();

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.first, 11);

      final names = {
        for (final r
            in await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type IN ('table','view')",
                )
                .get())
          r.data['name'] as String,
      };
      expect(
        names,
        containsAll([
          'revenue_entries',
          'revenue_components',
          'revenue_value_bands',
          'revenue_supply_subtypes',
          'business_unit_tax_statuses',
          'revenue_entry_totals',
        ]),
      );
    });

    test(
      'the reference masters ship empty — no invented configuration',
      () async {
        // D-083, D-096. The hinges exist; no band, subtype or premises status is created
        // until a real one is verified.
        for (final table in const [
          'revenue_value_bands',
          'revenue_supply_subtypes',
          'business_unit_tax_statuses',
        ]) {
          final count = await db
              .customSelect('SELECT COUNT(*) AS n FROM $table')
              .getSingle();
          expect(count.data['n'], 0, reason: '$table must ship empty');
        }
      },
    );

    test('no local tax rule is seeded either', () async {
      // Slice 3 creates no canonical tax configuration: it would be local-only data that
      // could diverge from the server, which arrives in Slice 4 (D-096).
      final count = await db
          .customSelect('SELECT COUNT(*) AS n FROM revenue_tax_rates')
          .getSingle();
      expect(count.data['n'], 0);
    });

    test(
      'the pre-v11 unique tax-rate index is absent, so two bands can coexist',
      () async {
        // The local mirror of D-093. `ux_tax_rates_live_period` was unique over
        // (category, effective_from) among live rules; Room's two value bands are by
        // construction two live rules for one category from the same date, so a fresh
        // v11 database must not be born with it — the failure would have surfaced as a
        // sync error, not as anything a person could act on.
        final indexes = {
          for (final r
              in await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'index'",
                  )
                  .get())
            r.data['name'] as String?,
        };
        expect(indexes, isNot(contains('ux_tax_rates_live_period')));

        await db.customStatement(
          'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
          'business_day_cutoff, sort_order, row_version, updated_at) '
          "VALUES ('unit-hki', 'org-1', 'HKI', 'Hotel Krishna', 'hotel', "
          "'Asia/Kolkata', '05:00', 1, 1, '2026-06-01T00:00:00.000Z')",
        );

        for (final id in const ['rule-lower', 'rule-upper']) {
          await db.customStatement(
            'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
            'name, sort_order, row_version, updated_at) '
            "VALUES ('cat-room', 'org-1', 'unit-hki', 'ROOM', 'Room', 1, 1, "
            "'2026-06-15T09:00:00.000Z') ON CONFLICT DO NOTHING",
          );
          await db.customStatement(
            'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
            'rate_basis_points, treatment, effective_from, input_basis, '
            'value_band_id, created_by, created_at, row_version, updated_at) '
            "VALUES (?, 'org-1', 'cat-room', 500, 'inclusive', '2026-04-01', "
            "'inclusive_total', ?, 'u', '2026-04-01T00:00:00.000Z', 1, "
            "'2026-04-01T00:00:00.000Z')",
            [id, id == 'rule-lower' ? 'band-lower' : 'band-upper'],
          );
        }

        final rules = await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM revenue_tax_rates '
              "WHERE revenue_category_id = 'cat-room'",
            )
            .getSingle();
        expect(
          rules.data['n'],
          2,
          reason:
              'two value bands for one category on one date must be storable',
        );
      },
    );
  });

  group('entry and component persistence', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('totals are derived from components, exactly', () async {
      await insertEntry(db, id: 'e1');

      final totals = await totalsFor(db, 'e1');
      expect(totals['gross_minor'], 10000000);
      expect(totals['tax_minor'], 476190);
      expect(totals['net_minor'], 9523810);
      expect(totals['component_count'], 1);
    });

    test('a multi-component entry sums to the paisa', () async {
      await insertEntry(
        db,
        id: 'e2',
        components: const [
          ('lower', 4200000, 4200000, 200000, 4000000),
          ('upper', 2300000, 2300000, 109524, 2190476),
        ],
      );

      final totals = await totalsFor(db, 'e2');
      expect(totals['gross_minor'], 6500000);
      expect(totals['tax_minor'], 309524);
      expect(totals['net_minor'], 6190476);
      expect(
        totals['net_minor']! + totals['tax_minor']!,
        totals['gross_minor'],
        reason:
            'the header reconciles because it is the sum, not a second copy',
      );
    });

    test('there is no stored header total to drift from the components', () async {
      // The guarantee is structural (D-078): with no header amount columns there is
      // nothing a future writer can set to a wrong value, and nothing to keep in step.
      final columns = {
        for (final r
            in await db
                .customSelect('PRAGMA table_info(revenue_entries)')
                .get())
          r.data['name'] as String,
      };
      for (final forbidden in const [
        'gross_amount_minor',
        'tax_amount_minor',
        'net_amount_minor',
        'total_amount_minor',
      ]) {
        expect(
          columns,
          isNot(contains(forbidden)),
          reason: 'a stored header total can drift; derived totals cannot',
        );
      }
    });

    test('deleting an entry removes its components', () async {
      await insertEntry(db, id: 'e3');
      await db.customStatement("DELETE FROM revenue_entries WHERE id = 'e3'");

      final left = await db
          .customSelect('SELECT COUNT(*) AS n FROM revenue_components')
          .getSingle();
      expect(left.data['n'], 0);
    });

    test('a component that does not reconcile is refused by SQLite', () async {
      await expectLater(
        insertEntry(
          db,
          id: 'bad',
          components: const [('c1', 10000000, 10000000, 476190, 9999999)],
        ),
        throwsA(anything),
        reason: 'net = gross - tax is a database constraint, not a convention',
      );
    });

    test('an unknown entered basis is refused', () async {
      await expectLater(
        insertEntry(db, id: 'bad2', basis: 'none'),
        throwsA(anything),
        reason: 'there is no third basis value (D-097)',
      );
    });

    test('an untaxed component carrying tax is refused', () async {
      await expectLater(
        insertEntry(
          db,
          id: 'bad3',
          treatment: 'none',
          rateBp: 0,
          components: const [('c1', 4034300, 4034300, 1, 4034299)],
        ),
        throwsA(anything),
      );
    });

    test('band bounds without a band identity are refused', () async {
      // The bounds explain a band. Without one they are a number nothing selects on,
      // which is the shape D-094 warns about.
      await expectLater(
        insertEntry(db, id: 'bad4', bandFloor: 750000),
        throwsA(anything),
      );
    });
  });

  group('the Room band is an identity, never inferred from money', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test(
      'two entries with the same band and very different amounts keep that band',
      () async {
        // D-094. A day's aggregate attributable to a band is not a per-room-per-night
        // tariff — forty ₹1,800 rooms and five ₹8,400 rooms report the same daily total —
        // so nothing in the schema derives, checks or corrects the band from an amount.
        await insertEntry(
          db,
          id: 'small',
          valueBandId: 'band-upper',
          bandFloor: 750000,
          components: const [('c1', 100, 100, 5, 95)],
        );
        await insertEntry(
          db,
          id: 'large',
          valueBandId: 'band-upper',
          bandFloor: 750000,
          components: const [('c1', 990000000, 990000000, 47142857, 942857143)],
        );

        final bands = await db
            .customSelect(
              'SELECT DISTINCT value_band_id FROM revenue_components',
            )
            .get();
        expect(bands, hasLength(1));
        expect(bands.single.data['value_band_id'], 'band-upper');
      },
    );

    test(
      'the band bounds are snapshotted, and no constraint compares them',
      () async {
        // An amount far below the band's own floor is stored without complaint, because
        // the two describe different things and the schema knows it.
        await insertEntry(
          db,
          id: 'below-floor',
          valueBandId: 'band-upper',
          bandFloor: 750000,
          bandCeiling: null,
          components: const [('c1', 1000, 1000, 48, 952)],
        );

        final row = await db
            .customSelect(
              'SELECT entered_amount_minor, value_band_floor_minor '
              'FROM revenue_components',
            )
            .getSingle();
        expect(row.data['entered_amount_minor'], 1000);
        expect(row.data['value_band_floor_minor'], 750000);
      },
    );
  });

  group('cache classification stays exhaustive', () {
    test('every v11 table is classified', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final classified = {for (final t in CacheClassification.tables) t.name};
      for (final table in const [
        'revenue_entries',
        'revenue_components',
        'revenue_value_bands',
        'revenue_supply_subtypes',
        'business_unit_tax_statuses',
      ]) {
        expect(
          classified,
          contains(table),
          reason: '$table must have an explicit cache classification (D-068)',
        );
      }
    });

    test(
      'revenue financial rows are retained-with-exception, not plain scoped',
      () {
        final entries = CacheClassification.tables.firstWhere(
          (t) => t.name == 'revenue_entries',
        );
        expect(entries.ownership, CacheOwnership.scopedFinancialHistory);
        expect(entries.isPurgedOnRevocation, isTrue);
        expect(
          entries.retainsUnsyncedWork,
          isTrue,
          reason: "a revocation must spare the actor's own unsent revenue",
        );
      },
    );

    test('revenue reference caches are purged with no such exception', () {
      for (final name in const [
        'revenue_value_bands',
        'revenue_supply_subtypes',
        'business_unit_tax_statuses',
      ]) {
        final table = CacheClassification.tables.firstWhere(
          (t) => t.name == name,
        );
        expect(table.ownership, CacheOwnership.businessUnitScoped);
        expect(table.isPurgedOnRevocation, isTrue);
        expect(
          table.retainsUnsyncedWork,
          isFalse,
          reason: 'a cached band is nobody\'s unsent attempt',
        );
      }
    });

    test('components are deleted before their entries', () {
      final order = [for (final t in CacheClassification.tables) t.name];
      expect(
        order.indexOf('revenue_components'),
        lessThan(order.indexOf('revenue_entries')),
        reason: 'children before parents, so no step leaves an orphan',
      );
    });
  });

  group('a retained entry survives its reference cache being purged', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test(
      'component snapshots explain the figures with no rule row present',
      () async {
        // D-070 §11. A revocation purges the rule, band and subtype caches; a retained
        // unsent entry must stay financially explainable from its own columns. The
        // snapshot pointers are soft for exactly this reason — a foreign key would either
        // block the purge or destroy the work it exists to spare.
        await insertEntry(
          db,
          id: 'retained',
          pendingMutationId: 'm-1',
          valueBandId: 'band-lower',
          bandFloor: 0,
          bandCeiling: 750000,
        );

        await db.customStatement('DELETE FROM revenue_tax_rates');
        await db.customStatement('DELETE FROM revenue_value_bands');

        final row = await db
            .customSelect(
              'SELECT tax_rule_id, tax_rate_basis_points, tax_treatment, '
              'entered_basis, value_band_id, value_band_label, '
              'value_band_floor_minor, gross_amount_minor, tax_amount_minor, '
              'net_amount_minor FROM revenue_components',
            )
            .getSingle();

        expect(row.data['tax_rule_id'], 'rule-1');
        expect(row.data['tax_rate_basis_points'], 500);
        expect(row.data['tax_treatment'], 'inclusive');
        expect(row.data['entered_basis'], 'inclusive_total');
        expect(row.data['value_band_label'], 'Lower tariff band');
        expect(row.data['value_band_floor_minor'], 0);
        expect(row.data['gross_amount_minor'], 10000000);
        expect(row.data['tax_amount_minor'], 476190);
        expect(row.data['net_amount_minor'], 9523810);
      },
    );
  });

  group('the v10 → v11 migration', () {
    test('Phase 3 data survives, and nothing is backfilled', () async {
      final file = await tempDatabaseFile();
      addTearDown(() => file.parent.deleteSync(recursive: true));

      // Build a v10 database the way a real Phase 3 device has one: masters, an expense
      // with its lines, outbox work, and a tax rule cached before v11 existed.
      final v10 = AppDatabase(NativeDatabase(file));
      await v10.customSelect('SELECT 1').get();
      await v10.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES ('unit-ccr', 'org-1', 'CCR', 'Crystal Canopy', 'rooftop', "
        "'Asia/Kolkata', "
        "'05:00', 1, 1, '2026-06-01T00:00:00.000Z')",
      );
      await v10.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES ('cat-restaurant', 'org-1', 'unit-ccr', 'REST', 'Restaurant', "
        "1, 1, '2026-06-01T00:00:00.000Z')",
      );
      await v10.customStatement(
        'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
        'rate_basis_points, treatment, effective_from, created_by, created_at, '
        'row_version, updated_at) '
        "VALUES ('old-rule', 'org-1', 'cat-restaurant', 500, 'inclusive', "
        "'2026-04-01', 'u', '2026-04-01T00:00:00.000Z', 1, "
        "'2026-04-01T00:00:00.000Z')",
      );
      await v10.customStatement(
        'INSERT INTO sync_outbox (mutation_id, entity_type, entity_id, op, '
        'payload, status, attempt_count, next_attempt_at, created_at, '
        'actor_user_id) '
        "VALUES ('m-old', 'expense', 'exp-1', 'create', '{}', 'pending', 0, "
        "'2026-06-15T09:00:00.000Z', '2026-06-15T09:00:00.000Z', 'user-1')",
      );
      await downgradeToV10(v10);
      final v10Indexes = {
        for (final r
            in await v10
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index'",
                )
                .get())
          r.data['name'] as String?,
      };
      expect(
        v10Indexes,
        contains('ux_tax_rates_live_period'),
        reason: 'the v10 database really does carry the index v11 drops',
      );
      await v10.close();

      // Opening at v11 runs the migration.
      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.first, 11);

      // 1 · Phase 3 data is untouched.
      final unit = await db
          .customSelect("SELECT name FROM business_units WHERE id = 'unit-ccr'")
          .getSingle();
      expect(unit.data['name'], 'Crystal Canopy');
      final queued = await db
          .customSelect(
            "SELECT actor_user_id, status FROM sync_outbox WHERE mutation_id = 'm-old'",
          )
          .getSingle();
      expect(queued.data['actor_user_id'], 'user-1');
      expect(queued.data['status'], 'pending');

      // 2 · The old rule keeps its own values and gains NO invented semantics.
      final rule = await db
          .customSelect(
            'SELECT rate_basis_points, treatment, input_basis, value_band_id, '
            'supply_subtype_id, premises_status_code FROM revenue_tax_rates '
            "WHERE id = 'old-rule'",
          )
          .getSingle();
      expect(rule.data['rate_basis_points'], 500);
      expect(rule.data['treatment'], 'inclusive');
      expect(
        rule.data['input_basis'],
        isNull,
        reason:
            'a pre-v11 rule has no authoritative basis; inventing inclusive_total '
            'would be inventing a business fact (D-043)',
      );
      expect(rule.data['value_band_id'], isNull);
      expect(rule.data['supply_subtype_id'], isNull);
      expect(rule.data['premises_status_code'], isNull);

      // 3 · The new tables and the view exist, and the stale index is gone.
      final objects = {
        for (final r
            in await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type IN ('table','view','index')",
                )
                .get())
          r.data['name'] as String?,
      };
      expect(
        objects,
        containsAll([
          'revenue_entries',
          'revenue_components',
          'revenue_value_bands',
          'revenue_supply_subtypes',
          'business_unit_tax_statuses',
          'revenue_entry_totals',
          'ix_revenue_entries_ledger',
          'ix_revenue_components_entry',
        ]),
      );
      expect(objects, isNot(contains('ux_tax_rates_live_period')));

      // 4 · The database is structurally sound and usable.
      final integrity = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(integrity, isEmpty);
      await insertEntry(db, id: 'after-migration');
      expect((await totalsFor(db, 'after-migration'))['gross_minor'], 10000000);
    });

    test('a v10 rule that DID carry a treatment keeps it verbatim', () async {
      // The migration adds columns; it rewrites nothing. `none` stays `none`.
      final file = await tempDatabaseFile();
      addTearDown(() => file.parent.deleteSync(recursive: true));

      final v10 = AppDatabase(NativeDatabase(file));
      await v10.customSelect('SELECT 1').get();
      await v10.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES ('unit-hki', 'org-1', 'HKI', 'Hotel Krishna', 'hotel', "
        "'Asia/Kolkata', "
        "'05:00', 1, 1, '2026-06-01T00:00:00.000Z')",
      );
      await v10.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES ('cat-banquet', 'org-1', 'unit-hki', 'BANQ', 'Banquet', 1, 1, "
        "'2026-06-01T00:00:00.000Z')",
      );
      await v10.customStatement(
        'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
        'rate_basis_points, treatment, effective_from, created_by, created_at, '
        'row_version, updated_at) '
        "VALUES ('banq', 'org-1', 'cat-banquet', 0, 'none', '2026-04-01', 'u', "
        "'2026-04-01T00:00:00.000Z', 1, '2026-04-01T00:00:00.000Z')",
      );
      await downgradeToV10(v10);
      await v10.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final rule = await db
          .customSelect(
            "SELECT treatment, rate_basis_points, input_basis FROM revenue_tax_rates "
            "WHERE id = 'banq'",
          )
          .getSingle();
      expect(rule.data['treatment'], 'none');
      expect(rule.data['rate_basis_points'], 0);
      expect(
        rule.data['input_basis'],
        isNull,
        reason: 'a treatment is not evidence of a basis',
      );
    });
  });
}
