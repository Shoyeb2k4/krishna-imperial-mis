/// Moving the seeded masters onto derived ids, without losing what the owner changed.
///
/// The original seed produced ids like `seed-cat-CCR-FOOD_PROD-KIRANA`. Postgres keys
/// masters on `uuid`, so a device that seeded itself offline would have met a server
/// holding the same hierarchy under different ids. Schema v4 rewrites identity once.
///
/// The risk in a rewrite like this is not the rewrite — it is what it takes with it. A
/// rename the owner made must survive, and no reference may be left dangling.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 8, 27, 9);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // A migration runs before `beforeOpen` turns enforcement on. Reproduce that, because
    // the operation is only correct in that state and refuses otherwise.
    await db.customStatement('PRAGMA foreign_keys = OFF');
  });

  tearDown(() => db.close());

  /// A hierarchy as the original scheme wrote it, with one master already renamed.
  Future<void> insertLegacyRows() async {
    await db.customStatement(
      "INSERT INTO business_units (id, org_id, code, name, kind, timezone, "
      "business_day_cutoff, sort_order, row_version, updated_at) VALUES "
      "('seed-bu-CCR', 'seed-org-krishna', 'CCR', 'Crystal Canopy Rooftop', "
      "'restaurant', 'Asia/Kolkata', '05:00', 0, 1, '2026-08-27T09:00:00.000Z')",
    );
    await db.customStatement(
      "INSERT INTO departments (id, org_id, business_unit_id, code, name, sort_order, "
      "row_version, updated_at) VALUES "
      "('seed-dept-CCR-FB', 'seed-org-krishna', 'seed-bu-CCR', 'FB', 'F&B / Kitchen', "
      "0, 1, '2026-08-27T09:00:00.000Z')",
    );
    await db.customStatement(
      "INSERT INTO sections (id, org_id, department_id, code, name, sort_order, "
      "row_version, updated_at) VALUES "
      "('seed-sec-CCR-FOOD_PROD', 'seed-org-krishna', 'seed-dept-CCR-FB', "
      "'FOOD_PROD', 'Food Production', 0, 1, '2026-08-27T09:00:00.000Z')",
    );
    await db.customStatement(
      "INSERT INTO expense_categories (id, org_id, section_id, code, name, nature, "
      "is_shared_by_default, sort_order, row_version, updated_at) VALUES "
      // Renamed by the owner: a corrected spelling, which must survive the move.
      "('seed-cat-CCR-FOOD_PROD-VEG_FRUIT', 'seed-org-krishna', "
      "'seed-sec-CCR-FOOD_PROD', 'VEG_FRUIT', 'VEGETABLES & FRUITS', 'operating', "
      "0, 1, 1, '2026-08-27T09:00:00.000Z')",
    );
  }

  test('legacy ids become the derived ids the server also derives', () async {
    await insertLegacyRows();
    await remapSeedIds(db);

    final unit = await (db.select(
      db.businessUnits,
    )..where((t) => t.code.equals('CCR'))).getSingle();
    expect(unit.id, seedId('bu:CCR'));
    expect(unit.orgId, seedOrgId);

    final section = await (db.select(
      db.sections,
    )..where((t) => t.code.equals('FOOD_PROD'))).getSingle();
    expect(section.id, seedId('sec:CCR/FB/FOOD_PROD'));
    expect(section.departmentId, seedId('dept:CCR/FB'));
  });

  test('a rename the owner made survives the move', () async {
    await insertLegacyRows();
    await remapSeedIds(db);

    final category = await (db.select(
      db.expenseCategories,
    )..where((t) => t.code.equals('VEG_FRUIT'))).getSingle();

    expect(category.name, 'VEGETABLES & FRUITS');
    expect(
      category.code,
      'VEG_FRUIT',
      reason: 'the permanent code never moves',
    );
    expect(category.id, seedId('cat:CCR/FB/FOOD_PROD/VEG_FRUIT'));
    expect(category.sectionId, seedId('sec:CCR/FB/FOOD_PROD'));
  });

  test('no reference is left dangling', () async {
    await insertLegacyRows();
    await remapSeedIds(db);
    await db.customStatement('PRAGMA foreign_keys = ON');

    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty);
  });

  test('re-seeding afterwards adds the rest and duplicates nothing', () async {
    await insertLegacyRows();
    await remapSeedIds(db);
    await db.customStatement('PRAGMA foreign_keys = ON');

    await seedMasterData(db, now: now);
    await seedMasterData(db, now: now);

    final units = await db.select(db.businessUnits).get();
    expect(units.where((u) => u.code == 'CCR').length, 1);
    expect(units.length, 2);

    final renamed = await (db.select(
      db.expenseCategories,
    )..where((t) => t.code.equals('VEG_FRUIT'))).getSingle();
    expect(
      renamed.name,
      'VEGETABLES & FRUITS',
      reason: 'a re-run must never undo an intentional rename',
    );
  });

  test('running the move twice changes nothing the second time', () async {
    await insertLegacyRows();
    final first = await remapSeedIds(db);
    final second = await remapSeedIds(db);

    expect(first, greaterThan(0));
    expect(second, 0);
  });

  test('it refuses to run with foreign key enforcement on', () async {
    await db.customStatement('PRAGMA foreign_keys = ON');
    await expectLater(remapSeedIds(db), throwsStateError);
  });
}
