/// The expense reporting projection, and the v15 → v16 migration that adds it.
///
/// Phase 5 Slice 1. Before it, revenue reporting read a named view and expense reporting
/// joined three tables by hand in Dart — two shapes for one question, which is how the
/// canonical-only exclusion came to be applied on one side and not the other (D-168).
///
/// The migration step deliberately carries **no** version floor, unlike the v13 and v15
/// revenue steps (D-144). The three expense tables arrive at v7 and
/// `expenses.scope_revoked_at` at v9, and the `from < 9` step runs *before* this one in
/// source order, so every column the view names exists on every upgrade path by the time
/// it is created. That ordering is the guard, and this file is what holds it — a test
/// that only ever ran against a fresh database would not notice it being reordered.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/expense_fixtures.dart' show createTempDatabaseFile;

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
  });
  tearDown(() => db.close());

  group('a fresh database is born with the expense reporting projection', () {
    test('the view exists, and is a view', () async {
      expect(db.schemaVersion, greaterThanOrEqualTo(16));

      final view = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = "
            "'expense_period_contributions' AND type = 'view'",
          )
          .getSingle();
      final sql = view.read<String>('sql');

      for (final column in const [
        'business_unit_id',
        'department_id',
        'section_id',
        'category_id',
        'pnl_date',
        'pnl_period_key',
        'amount_minor',
        'vendor_id',
      ]) {
        expect(sql, contains(column), reason: 'reporting groups on $column');
      }

      expect(
        sql,
        contains('txn_number'),
        reason:
            'the canonical marker. A device holds documents the server has never '
            'accepted, and a P&L must exclude them (D-168)',
      );
      expect(
        sql,
        contains('scope_revoked_at'),
        reason: 'retained work over a lost property is nobody cost (D-070)',
      );
      expect(
        sql,
        contains('voided_at'),
        reason:
            'carried and not filtered, exactly as the revenue projection does: the '
            'aggregate excludes, the row remains inspectable (D-006)',
      );
    });

    test('the reporting index exists', () async {
      final index = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'index' "
            "AND name = 'ix_expense_contributions_reporting'",
          )
          .getSingle();
      expect(
        index.read<int>('n'),
        1,
        reason:
            'added to onCreate as well as to the upgrade step — a fresh database '
            'lacking an index the upgrade path has is the defect D-159 recorded',
      );
    });

    test('nothing here is a table', () async {
      final tables = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' "
            "AND name = 'expense_period_contributions'",
          )
          .getSingle();
      expect(
        tables.read<int>('n'),
        0,
        reason:
            'the contributions are already a physical table; a second copy projected '
            'beside them would be two sources for one figure (D-060)',
      );
    });
  });

  group('the v15 to v16 migration', () {
    test('a v15 device gains the projection over the rows it already holds', () async {
      final file = await createTempDatabaseFile();
      addTearDown(() => file.parent.deleteSync(recursive: true));

      // A v15-shaped database holding one accepted expense with one contribution. Built
      // with raw SQL against the current table definitions, then stamped back to v15 with
      // the v16 objects removed — a fixture that claims to be an older schema has to
      // actually be one (D-144, D-159).
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
      await seeded.customStatement(
        "INSERT INTO expense_allocations (id, org_id, expense_id, business_unit_id, "
        "department_id, section_id, category_id, amount_minor, category_label, "
        "sort_order, row_version, updated_at) "
        "VALUES ('a1', 'org-1', 'e1', 'unit-ccr', 'dept-1', 'sec-1', 'cat-1', 500000, "
        "'Kirana', 0, 1, '2026-06-15T10:00:00.000Z')",
      );
      await seeded.customStatement(
        "INSERT INTO expense_period_allocations (id, org_id, expense_id, allocation_id, "
        "business_unit_id, accounting_period_start, accounting_period_end, amount_minor, "
        "pnl_date, pnl_period_key, is_derived, row_version, updated_at) "
        "VALUES ('p1', 'org-1', 'e1', 'a1', 'unit-ccr', '2026-06-01', '2026-06-30', "
        "500000, '2026-06-30', '2026-06', 1, 1, '2026-06-15T10:00:00.000Z')",
      );
      await seeded.customStatement(
        'DROP VIEW IF EXISTS expense_period_contributions',
      );
      await seeded.customStatement(
        'DROP INDEX IF EXISTS ix_expense_contributions_reporting',
      );
      await seeded.customStatement('PRAGMA user_version = 15');
      await seeded.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);
      final repository = ExpenseRepository(upgraded);

      final totals = await repository.contributionTotals(
        const ExpenseContributionQuery(periodKey: '2026-06'),
      );
      expect(
        totals.amount,
        Money.fromRupees(5000),
        reason:
            'the accepted row the device already held is reportable after upgrade',
      );
      expect(totals.contributions, 1);

      final rows = await repository.contributions(
        const ExpenseContributionQuery(periodKey: '2026-06'),
      );
      expect(rows.single.categoryId, 'cat-1');
      expect(rows.single.departmentId, 'dept-1');
      expect(rows.single.isCanonical, isTrue);
      expect(rows.single.pnlPeriodKey, '2026-06');

      expect(
        (await upgraded
                .customSelect(
                  "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'index' "
                  "AND name = 'ix_expense_contributions_reporting'",
                )
                .getSingle())
            .read<int>('n'),
        1,
      );
    });

    test('a pre-v16 row with no number stays out of the total after upgrade', () async {
      final file = await createTempDatabaseFile();
      addTearDown(() => file.parent.deleteSync(recursive: true));

      final seeded = AppDatabase(NativeDatabase(file));
      await seeded.customStatement('PRAGMA foreign_keys = OFF');
      await seeded.customStatement(
        "INSERT INTO expenses (id, org_id, business_date, business_date_source, "
        "visibility, document_total_minor, visible_amount_minor, is_shared, "
        "payment_status, created_by, captured_at, row_version, updated_at) "
        "VALUES ('e2', 'org-1', '2026-06-15', 'derived', 'complete', 700000, 700000, 0, "
        "'unpaid', 'user-1', '2026-06-15T10:00:00.000Z', 1, '2026-06-15T10:00:00.000Z')",
      );
      await seeded.customStatement(
        "INSERT INTO expense_allocations (id, org_id, expense_id, business_unit_id, "
        "department_id, section_id, category_id, amount_minor, category_label, "
        "sort_order, row_version, updated_at) "
        "VALUES ('a2', 'org-1', 'e2', 'unit-ccr', 'dept-1', 'sec-1', 'cat-1', 700000, "
        "'Kirana', 0, 1, '2026-06-15T10:00:00.000Z')",
      );
      await seeded.customStatement(
        "INSERT INTO expense_period_allocations (id, org_id, expense_id, allocation_id, "
        "business_unit_id, accounting_period_start, accounting_period_end, amount_minor, "
        "pnl_date, pnl_period_key, is_derived, row_version, updated_at) "
        "VALUES ('p2', 'org-1', 'e2', 'a2', 'unit-ccr', '2026-06-01', '2026-06-30', "
        "700000, '2026-06-30', '2026-06', 1, 1, '2026-06-15T10:00:00.000Z')",
      );
      await seeded.customStatement(
        'DROP VIEW IF EXISTS expense_period_contributions',
      );
      await seeded.customStatement('PRAGMA user_version = 15');
      await seeded.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);

      expect(
        (await ExpenseRepository(upgraded).contributionTotals(
          const ExpenseContributionQuery(periodKey: '2026-06'),
        )).amount,
        Money.zero,
        reason:
            'an upgrade does not accept anything. A document this device recorded and '
            'never delivered was not a cost before v16 and is not one after it (D-168)',
      );
    });
  });
}
