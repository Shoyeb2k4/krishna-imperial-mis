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

/// Deterministic ids so a re-run matches what is already there.
String seedId(String kind, String path) => 'seed-$kind-$path';

const String seedOrgId = 'seed-org-krishna';

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
  String orgId = seedOrgId,
}) async {
  await db.transaction(() async {
    var unitOrder = 0;
    for (final unit in _seedUnits) {
      final unitId = seedId('bu', unit.code);
      await db
          .into(db.businessUnits)
          .insert(
            BusinessUnitsCompanion.insert(
              id: unitId,
              orgId: orgId,
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
                id: seedId('rev', '${unit.code}-$code'),
                orgId: orgId,
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
        final departmentId = seedId('dept', '${unit.code}-${department.code}');
        await db
            .into(db.departments)
            .insert(
              DepartmentsCompanion.insert(
                id: departmentId,
                orgId: orgId,
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
          final sectionId = seedId('sec', '${unit.code}-${section.code}');
          await db
              .into(db.sections)
              .insert(
                SectionsCompanion.insert(
                  id: sectionId,
                  orgId: orgId,
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
                      'cat',
                      '${unit.code}-${section.code}-${category.code}',
                    ),
                    orgId: orgId,
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
              id: seedId('pm', code),
              orgId: orgId,
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
