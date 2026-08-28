/// Initial master data (master spec §4).
///
/// This is **business structure, not financial history** — no amounts, no transactions,
/// no credentials. Real figures are never seeded or committed (D-027).
///
/// Seeding is idempotent: ids are derived deterministically from codes and rows are
/// inserted with "or ignore", so running it twice changes nothing and running it after
/// the owner has edited a master does not undo their edit.
///
/// Everything here is a starting point. Every master is editable and archivable in-app,
/// and none of these codes is referenced by business logic.
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:uuid/uuid.dart';

/// The namespace the seed ids are derived in.
///
/// Duplicated, deliberately and identically, in
/// `supabase/migrations/20260827091200_seed.sql`. It is a fixed, arbitrary, non-secret
/// constant whose only job is to make the derivation reproducible.
const String seedNamespace = 'd9d3f0a6-4c2b-5f7e-9a10-6b1e2c8f4a70';

/// A stable id derived from a record's permanent code path — `bu:CCR`,
/// `cat:CCR/FB/FOOD_PROD/KIRANA`.
///
/// UUID v5, so **the server derives exactly the same id for the same record**. That is
/// the point. Without it a device that seeded itself offline would later meet a server
/// holding the identical hierarchy under different ids, and the two could only be
/// reconciled by matching on names — precisely the rename-sensitive matching that the
/// master-identity design exists to make unnecessary (D-035).
String seedId(String path) => const Uuid().v5(seedNamespace, path);

/// The seeded organisation.
final String seedOrgId = seedId('org:KRISHNA');

class _Category {
  const _Category(
    this.code,
    this.name, {
    this.nature = 'operating',
    this.shared = false,
  });
  final String code;
  final String name;
  final String nature;
  final bool shared;
}

class _Section {
  const _Section(this.code, this.name, this.categories);
  final String code;
  final String name;
  final List<_Category> categories;
}

class _Department {
  const _Department(this.code, this.name, this.sections);
  final String code;
  final String name;
  final List<_Section> sections;
}

class _Unit {
  const _Unit({
    required this.code,
    required this.name,
    required this.kind,
    required this.departments,
    required this.revenueCategories,
  });
  final String code;
  final String name;
  final String kind;
  final List<_Department> departments;

  /// (code, name) pairs.
  final List<(String, String)> revenueCategories;
}

/// Crystal Canopy Rooftop and Hotel Krishna Imperial, exactly as specified.
///
/// Nandbhog appears as a **revenue category under Crystal Canopy**, not as a business
/// unit (D-024).
const List<_Unit> _seedUnits = [
  _Unit(
    code: 'CCR',
    name: 'Crystal Canopy Rooftop',
    kind: 'restaurant',
    revenueCategories: [('RESTAURANT', 'Restaurant'), ('NANDBHOG', 'Nandbhog')],
    departments: [
      _Department('FB', 'F&B / Kitchen', [
        _Section('FOOD_PROD', 'Food Production', [
          _Category('KIRANA', 'Kirana & Pulses'),
          _Category('VEG_FRUIT', 'Vegetables & Fruits'),
          _Category('MILK_DAHI', 'Milk & Dahi'),
          _Category('PANEER', 'Paneer / Dairy'),
        ]),
        _Section('KITCHEN_FUEL', 'Kitchen Fuel', [
          _Category('CYL_COAL', 'Cylinder & Coal', nature: 'utility'),
        ]),
      ]),
      _Department('CCR_PAYROLL', 'Payroll', [
        _Section('CCR_WAGES', 'Wages', [
          _Category(
            'KITCHEN_PAYROLL',
            'Kitchen / F&B Payroll',
            nature: 'payroll',
          ),
          _Category('OTHER_WAGES', 'Other Wages', nature: 'payroll'),
          _Category('INCENTIVES', 'Incentives', nature: 'payroll'),
        ]),
      ]),
      _Department('CCR_UTIL', 'Utilities', [
        _Section('CCR_UTIL_SVC', 'Utility Services', [
          _Category(
            'ELECTRICITY',
            'Electricity',
            nature: 'utility',
            shared: true,
          ),
          _Category('WATER', 'Water', nature: 'utility', shared: true),
        ]),
      ]),
      _Department('CCR_OTHER', 'Other', [
        _Section('CCR_OTHER_OPS', 'Other Operations', [
          _Category('OTHER_OPEX', 'Other Operating Expenses', nature: 'other'),
        ]),
      ]),
    ],
  ),
  _Unit(
    code: 'HKI',
    name: 'Hotel Krishna Imperial',
    kind: 'hotel',
    revenueCategories: [('ROOM', 'Room'), ('BANQUET', 'Banquet')],
    departments: [
      _Department('HK', 'Housekeeping', [
        _Section('HK_OPS', 'Housekeeping Operations', [
          _Category('HK_SALARY', 'Housekeeping Salary', nature: 'payroll'),
          _Category('HK_EXPENSES', 'Housekeeping Expenses'),
        ]),
      ]),
      _Department('FO', 'Front Office', [
        _Section('FO_OPS', 'Front Office Operations', [
          _Category('FO_SALARY', 'Front Office Salary', nature: 'payroll'),
        ]),
      ]),
      _Department('HKI_UTIL', 'Utilities', [
        _Section('HKI_WATER', 'Water', [
          _Category('WATER', 'Water', nature: 'utility', shared: true),
          _Category('TANKER', 'Tanker', nature: 'utility'),
          _Category('WATER_CANS', 'Water Cans', nature: 'utility'),
        ]),
        _Section('HKI_POWER', 'Power & Fuel', [
          _Category(
            'ELECTRICITY',
            'Electricity',
            nature: 'utility',
            shared: true,
          ),
          _Category('DIESEL', 'Diesel', nature: 'utility'),
        ]),
      ]),
      _Department('HKI_MAINT', 'Maintenance', [
        _Section('HKI_BUILDING', 'Building & Upkeep', [
          _Category('BUILDING', 'Building Expenses'),
          _Category('MAINTENANCE', 'Maintenance'),
        ]),
      ]),
      _Department('HKI_PAYROLL', 'Payroll', [
        _Section('HKI_WAGES', 'Wages', [
          _Category('PAYROLL', 'Payroll', nature: 'payroll'),
        ]),
      ]),
      _Department('HKI_OTHER', 'Other', [
        _Section('HKI_OTHER_OPS', 'Other Operations', [
          _Category('OTHER_OPEX', 'Other Operating Expenses', nature: 'other'),
        ]),
      ]),
    ],
  ),
];

const List<(String, String, bool)> _seedPaymentMethods = [
  ('CASH', 'Cash', false),
  ('UPI', 'UPI', true),
  ('BANK', 'Bank Transfer', true),
  ('CARD', 'Card', false),
  ('CREDIT', 'Credit / On Account', false),
];

/// Inserts the seed masters if they are not already present.
///
/// Runs in one transaction: a half-seeded hierarchy would be worse than none, because a
/// department without its sections looks like a deliberate structure rather than a
/// failure.
Future<void> seedMasterData(
  AppDatabase db, {
  required DateTime now,
  String? orgId,
}) async {
  final org = orgId ?? seedOrgId;
  await db.transaction(() async {
    var unitOrder = 0;
    for (final unit in _seedUnits) {
      final unitId = seedId('bu:${unit.code}');
      await db
          .into(db.businessUnits)
          .insert(
            BusinessUnitsCompanion.insert(
              id: unitId,
              orgId: org,
              code: unit.code,
              name: unit.name,
              kind: unit.kind,
              sortOrder: Value(unitOrder++),
              updatedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );

      var revenueOrder = 0;
      for (final (code, name) in unit.revenueCategories) {
        await db
            .into(db.revenueCategories)
            .insert(
              RevenueCategoriesCompanion.insert(
                id: seedId('rev:${unit.code}/$code'),
                orgId: org,
                businessUnitId: unitId,
                code: code,
                name: name,
                sortOrder: Value(revenueOrder++),
                updatedAt: now,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }

      var departmentOrder = 0;
      for (final department in unit.departments) {
        final departmentId = seedId('dept:${unit.code}/${department.code}');
        await db
            .into(db.departments)
            .insert(
              DepartmentsCompanion.insert(
                id: departmentId,
                orgId: org,
                businessUnitId: unitId,
                code: department.code,
                name: department.name,
                sortOrder: Value(departmentOrder++),
                updatedAt: now,
              ),
              mode: InsertMode.insertOrIgnore,
            );

        var sectionOrder = 0;
        for (final section in department.sections) {
          final sectionId = seedId(
            'sec:${unit.code}/${department.code}/${section.code}',
          );
          await db
              .into(db.sections)
              .insert(
                SectionsCompanion.insert(
                  id: sectionId,
                  orgId: org,
                  departmentId: departmentId,
                  code: section.code,
                  name: section.name,
                  sortOrder: Value(sectionOrder++),
                  updatedAt: now,
                ),
                mode: InsertMode.insertOrIgnore,
              );

          var categoryOrder = 0;
          for (final category in section.categories) {
            await db
                .into(db.expenseCategories)
                .insert(
                  ExpenseCategoriesCompanion.insert(
                    id: seedId(
                      'cat:${unit.code}/${department.code}/'
                      '${section.code}/${category.code}',
                    ),
                    orgId: org,
                    sectionId: sectionId,
                    code: category.code,
                    name: category.name,
                    nature: Value(category.nature),
                    isSharedByDefault: Value(category.shared),
                    sortOrder: Value(categoryOrder++),
                    updatedAt: now,
                  ),
                  mode: InsertMode.insertOrIgnore,
                );
          }
        }
      }
    }

    var methodOrder = 0;
    for (final (code, name, needsReference) in _seedPaymentMethods) {
      await db
          .into(db.paymentMethods)
          .insert(
            PaymentMethodsCompanion.insert(
              id: seedId('pm:$code'),
              orgId: org,
              code: code,
              name: name,
              requiresReference: Value(needsReference),
              sortOrder: Value(methodOrder++),
              updatedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  });
}

/// Every seeded record's id under the original scheme, paired with its id under the
/// derived-UUID scheme.
///
/// The first scheme produced strings like `seed-cat-CCR-FOOD_PROD-KIRANA`, which are
/// perfectly stable but have no counterpart on the server — Postgres keys masters on
/// `uuid`. Rather than reconcile two id spaces forever, the local ids move once, to the
/// same UUID v5 values the server derives.
Map<String, String> seedIdRemapping() {
  final map = <String, String>{'seed-org-krishna': seedId('org:KRISHNA')};

  for (final unit in _seedUnits) {
    map['seed-bu-${unit.code}'] = seedId('bu:${unit.code}');

    for (final (code, _) in unit.revenueCategories) {
      map['seed-rev-${unit.code}-$code'] = seedId('rev:${unit.code}/$code');
    }

    for (final department in unit.departments) {
      map['seed-dept-${unit.code}-${department.code}'] = seedId(
        'dept:${unit.code}/${department.code}',
      );

      for (final section in department.sections) {
        // The old section id omitted the department. It happened to be unique in the
        // seeded tree; the new one carries the full path so it cannot stop being.
        map['seed-sec-${unit.code}-${section.code}'] = seedId(
          'sec:${unit.code}/${department.code}/${section.code}',
        );

        for (final category in section.categories) {
          map['seed-cat-${unit.code}-${section.code}-${category.code}'] =
              seedId(
                'cat:${unit.code}/${department.code}/'
                '${section.code}/${category.code}',
              );
        }
      }
    }
  }

  for (final (code, _, _) in _seedPaymentMethods) {
    map['seed-pm-$code'] = seedId('pm:$code');
  }

  return map;
}

/// Every column anywhere in the local schema that holds a master id.
///
/// Listed explicitly rather than discovered, because a column missed here would leave a
/// dangling reference that foreign keys — switched off during a migration — would not
/// catch until much later.
const List<(String table, String column)> _masterIdColumns = [
  ('business_units', 'org_id'),
  ('business_units', 'id'),
  ('departments', 'org_id'),
  ('departments', 'business_unit_id'),
  ('departments', 'id'),
  ('sections', 'org_id'),
  ('sections', 'department_id'),
  ('sections', 'id'),
  ('expense_categories', 'org_id'),
  ('expense_categories', 'section_id'),
  ('expense_categories', 'id'),
  ('revenue_categories', 'org_id'),
  ('revenue_categories', 'business_unit_id'),
  ('revenue_categories', 'id'),
  ('vendors', 'org_id'),
  ('vendors', 'default_business_unit_id'),
  ('vendors', 'default_category_id'),
  ('payment_methods', 'org_id'),
  ('payment_methods', 'id'),
  ('period_locks', 'org_id'),
  ('period_locks', 'business_unit_id'),
  ('period_lock_events', 'org_id'),
  ('revenue_tax_rates', 'org_id'),
  ('revenue_tax_rates', 'revenue_category_id'),
];

/// Moves any rows still carrying the original seed ids onto the derived UUIDs.
///
/// Renames survive: this rewrites identity, never labels. A master the owner renamed to
/// `VEGETABLES & FRUITS` keeps that name and simply acquires the id the server will use
/// for it (D-038).
///
/// Safe to run when there is nothing to move — it is a no-op then, which is what makes it
/// safe to call from a migration that may already have run on some devices.
Future<int> remapSeedIds(AppDatabase db) async {
  final remapping = seedIdRemapping();

  // Rewriting a parent's id and its children's references cannot be ordered so that
  // referential integrity holds at every intermediate step: parent-first orphans the
  // children, child-first points them at a row that does not exist yet. The operation is
  // therefore only correct with enforcement suspended — which is exactly the state during
  // a Drift migration, since `PRAGMA foreign_keys = ON` is set in `beforeOpen` and that
  // runs afterwards.
  //
  // Refusing outright is better than trusting the caller to know that. Called with
  // enforcement on, this would fail partway and leave the hierarchy in pieces.
  final enforcing = await db
      .customSelect('PRAGMA foreign_keys')
      .getSingle()
      .then((row) => row.data.values.first == 1);
  if (enforcing) {
    throw StateError(
      'remapSeedIds must run with foreign key enforcement suspended. It rewrites parent '
      'ids and the columns referencing them, which has no valid intermediate state.',
    );
  }

  return db.transaction(() async {
    await db.customStatement(
      'CREATE TEMP TABLE IF NOT EXISTS seed_id_remap '
      '(old_id TEXT PRIMARY KEY, new_id TEXT NOT NULL)',
    );
    await db.customStatement('DELETE FROM seed_id_remap');
    for (final entry in remapping.entries) {
      await db.customStatement(
        'INSERT INTO seed_id_remap (old_id, new_id) VALUES (?, ?)',
        [entry.key, entry.value],
      );
    }

    var updated = 0;
    for (final (table, column) in _masterIdColumns) {
      final result = await db.customUpdate(
        'UPDATE $table SET $column = '
        '(SELECT new_id FROM seed_id_remap WHERE old_id = $table.$column) '
        'WHERE $column IN (SELECT old_id FROM seed_id_remap)',
        updates: const {},
      );
      updated += result;
    }

    await db.customStatement('DROP TABLE seed_id_remap');
    return updated;
  });
}

/// Every path the seed derives an id from, in the same form the Postgres seed uses.
///
/// Exposed so a test can assert that the local seed and
/// `supabase/migrations/20260827091200_seed.sql` describe the *same* hierarchy. Two
/// seeds that quietly disagree would produce two organisations with the same names and
/// different ids, which is the failure this whole derivation exists to prevent.
Set<String> seedPaths() {
  final paths = <String>{'org:KRISHNA'};

  for (final unit in _seedUnits) {
    paths.add('bu:${unit.code}');
    for (final (code, _) in unit.revenueCategories) {
      paths.add('rev:${unit.code}/$code');
    }
    for (final department in unit.departments) {
      paths.add('dept:${unit.code}/${department.code}');
      for (final section in department.sections) {
        paths.add('sec:${unit.code}/${department.code}/${section.code}');
        for (final category in section.categories) {
          paths.add(
            'cat:${unit.code}/${department.code}/'
            '${section.code}/${category.code}',
          );
        }
      }
    }
  }

  for (final (code, _, _) in _seedPaymentMethods) {
    paths.add('pm:$code');
  }

  return paths;
}
