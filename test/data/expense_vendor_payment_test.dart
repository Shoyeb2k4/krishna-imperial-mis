/// Vendors and payment, as an expense uses them.
///
/// Both are places where a small convenience could quietly become a rule, and this file
/// exists to hold the line:
///
/// * a vendor's default business unit is a pre-selection, never a scope (D-049), and
///   losing access to that unit never changes the vendor;
/// * a payment date is when cash moved, never where the cost belongs (D-016).
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/repositories/vendor_repository.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late VendorRepository vendors;
  late ExpenseRepository expenses;
  final now = DateTime.utc(2026, 6, 15, 9);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await seedMasterData(db, now: now);
    vendors = VendorRepository(db);
    expenses = ExpenseRepository(db);
  });

  tearDown(() => db.close());

  Future<String> addVendor({
    required String code,
    required String name,
    String? defaultUnit,
  }) async {
    final id = const Uuid().v4();
    await db
        .into(db.vendors)
        .insert(
          VendorsCompanion.insert(
            id: id,
            orgId: seedOrgId,
            code: code,
            name: name,
            defaultBusinessUnitId: Value(defaultUnit),
            updatedAt: now,
          ),
        );
    return id;
  }

  group('a vendor is a supplier of the company (D-049)', () {
    test('one vendor serves both properties without being duplicated', () async {
      final vendorId = await addVendor(
        code: 'SHARMA',
        name: 'Sharma Traders',
        defaultUnit: ccrId,
      );

      // The same supplier on a Crystal Canopy expense and on a Hotel Krishna one.
      await expenses.createLocally(
        expenseWith(
          lines: [line(unit: ccrId, rupees: 1840)],
          vendorId: vendorId,
        ),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      await expenses.createLocally(
        expenseWith(
          lines: [line(unit: hkiId, rupees: 920, label: 'Electricity')],
          vendorId: vendorId,
        ),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );

      final rows = await db.select(db.expenses).get();
      expect(rows, hasLength(2));
      expect(rows.every((r) => r.vendorId == vendorId), isTrue);
      expect(
        await db.select(db.vendors).get(),
        hasLength(1),
        reason: 'one supplier, one master record',
      );
    });

    test('an expense may carry no vendor at all', () async {
      final expense = expenseWith(lines: [line(unit: ccrId, rupees: 200)]);
      await expenses.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );

      final saved = await expenses.load(expense.id);
      expect(saved!.row.vendorId, isNull);
    });

    test('search finds a supplier quickly, by name or code', () async {
      await addVendor(code: 'SHARMA', name: 'Sharma Traders');
      await addVendor(code: 'METRO', name: 'Metro Wholesale');
      await addVendor(code: 'GUPTA', name: 'Gupta Vegetables');

      expect((await vendors.search('sharma')).map((v) => v.code), ['SHARMA']);
      expect((await vendors.search('METRO')).map((v) => v.code), ['METRO']);
      expect(await vendors.search('nobody'), isEmpty);
    });

    test(
      'the default unit is filtered by scope without the vendor being changed',
      () async {
        final vendorId = await addVendor(
          code: 'HKI_ELEC',
          name: 'City Power',
          defaultUnit: hkiId,
        );

        final vendor = (await vendors.list()).firstWhere(
          (v) => v.id == vendorId,
        );

        // An org-wide holder sees the configured default.
        expect(vendor.effectiveDefaultBusinessUnitId(null), hkiId);

        // A Crystal Canopy manager does not — for them there is no default, and the
        // picker offers none rather than offering a property they cannot use.
        expect(vendor.effectiveDefaultBusinessUnitId({ccrId}), isNull);
        expect(vendor.hasUnreachableDefault({ccrId}), isTrue);

        // And the vendor itself is untouched: no null written, no version moved.
        final stored = (await db.select(db.vendors).get()).single;
        expect(
          stored.defaultBusinessUnitId,
          hkiId,
          reason: 'losing access to a unit is not a change to the supplier',
        );
        expect(stored.rowVersion, 1);

        // Scope restored, and the default is usable again with nothing written.
        expect(vendor.effectiveDefaultBusinessUnitId({ccrId, hkiId}), hkiId);
      },
    );
  });

  group('payment is a separate fact from profitability (D-016)', () {
    test('unpaid is the default and carries neither date nor method', () async {
      final expense = simpleExpense();
      await expenses.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );

      final saved = await expenses.load(expense.id);
      expect(saved!.row.paymentStatus, 'unpaid');
      expect(saved.row.paymentDate, isNull);
      expect(saved.row.paymentMethodId, isNull);
    });

    test('the two allowed states are exactly unpaid and paid', () {
      expect(PaymentStatus.values.map((s) => s.name), ['unpaid', 'paid']);
      expect(PaymentStatus.unpaid.label, 'Unpaid');
      expect(PaymentStatus.paid.label, 'Paid');
    });

    test('a paid expense states when and by what means', () async {
      final expense = juneSalaryPaidInJuly();
      await expenses.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );

      final saved = await expenses.load(expense.id);
      expect(saved!.row.paymentStatus, 'paid');
      expect(saved.row.paymentDate, '2026-07-05');
      expect(saved.row.paymentMethodId, isNotNull);
    });

    test(
      'June salary paid on 5 July is a June cost and a July payment, both',
      () async {
        final expense = juneSalaryPaidInJuly();
        await expenses.createLocally(
          expense,
          actorUserId: 'user-1',
          mutationId: const Uuid().v4(),
          now: now,
        );

        // Profitability: June, because that is when the cost was incurred.
        expect(
          await expenses.contributionTotal(periodKey: '2026-06'),
          Money.fromRupees(80000),
        );
        expect(
          await expenses.contributionTotal(periodKey: '2026-07'),
          Money.zero,
        );

        // Cash: July, because that is when it left the bank.
        final saved = await expenses.load(expense.id);
        expect(
          BusinessDate.tryParse(saved!.row.paymentDate!)!.periodKey,
          '2026-07',
        );

        // The two facts coexist, and neither moved the other.
        expect(
          saved.periodContributions.single.pnlPeriodKey,
          '2026-06',
          reason: 'paying in July does not move the cost out of June',
        );
      },
    );

    test('partial payment is not representable, deliberately (spec §5.4)', () {
      // There is no `partiallyPaid`, no amount-paid column and no balance. V1 models
      // whether cash moved, not how much of it — the doorway to a payables ledger is
      // left closed on purpose.
      expect(PaymentStatus.values, hasLength(2));
    });
  });
}
