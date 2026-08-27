/// Tax configuration and vendors over the real local database.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/local_master_usage_reader.dart';
import 'package:krishna_mis/data/repositories/tax_repository.dart';
import 'package:krishna_mis/data/repositories/vendor_repository.dart';
import 'package:krishna_mis/domain/masters/master_usage.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

BusinessDate on(String iso) => BusinessDate.tryParse(iso)!;

void main() {
  late AppDatabase db;
  late TaxRepository tax;
  late VendorRepository vendors;
  final now = DateTime.utc(2026, 6, 15, 9);
  final restaurant = seedId('rev', 'CCR-RESTAURANT');
  final room = seedId('rev', 'HKI-ROOM');

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tax = TaxRepository(db);
    vendors = VendorRepository(db);
    await seedMasterData(db, now: now);
  });

  tearDown(() => db.close());

  Future<void> addRule({
    required String id,
    String category = '',
    int rateBp = 500,
    TaxTreatment treatment = TaxTreatment.inclusive,
    String from = '2026-04-01',
    String? to,
  }) => tax.addRule(
    id: id,
    orgId: seedOrgId,
    revenueCategoryId: category.isEmpty ? restaurant : category,
    rateBasisPoints: rateBp,
    treatment: treatment,
    effectiveFrom: on(from),
    effectiveTo: to == null ? null : on(to),
    createdBy: 'u-owner',
    now: now,
  );

  group('tax configuration', () {
    test('a rule is stored and resolves for dates inside its period', () async {
      await addRule(id: 't1');

      final resolved = await tax.resolveFor(
        revenueCategoryId: restaurant,
        businessDate: on('2026-06-15'),
      );
      expect(resolved, isNotNull);
      expect(resolved!.rateBasisPoints, 500);
      expect(resolved.treatment, TaxTreatment.inclusive);
      expect(resolved.isOpenEnded, isTrue);
    });

    test(
      'no rule before the effective date, rather than a silent zero',
      () async {
        await addRule(id: 't1', from: '2026-04-01');
        expect(
          await tax.resolveFor(
            revenueCategoryId: restaurant,
            businessDate: on('2026-03-31'),
          ),
          isNull,
        );
      },
    );

    test('the database refuses an overlapping period', () async {
      await addRule(id: 't1', from: '2026-04-01');
      await expectLater(
        addRule(id: 't2', from: '2026-06-01'),
        throwsA(
          isA<TaxRuleRejected>().having(
            (e) => e.refusal,
            'refusal',
            TaxRuleRefusal.overlapsExistingPeriod,
          ),
        ),
      );
      // And nothing was written.
      expect((await tax.rulesFor(restaurant)).active.length, 1);
    });

    test('adjacent periods are accepted', () async {
      await addRule(id: 't1', from: '2026-04-01', to: '2026-07-01');
      await addRule(id: 't2', from: '2026-07-01', rateBp: 1200);
      expect((await tax.rulesFor(restaurant)).active.length, 2);
    });

    test('the same period for a different category is fine', () async {
      await addRule(id: 't1', from: '2026-04-01');
      await addRule(id: 't2', category: room, from: '2026-04-01', rateBp: 1200);
      expect((await tax.rulesFor(restaurant)).active.length, 1);
      expect((await tax.rulesFor(room)).active.length, 1);
    });

    test('a rule for a category that does not exist is refused', () async {
      await expectLater(
        addRule(id: 't1', category: 'no-such-category'),
        throwsA(isA<TaxRuleRejected>()),
      );
    });

    test('an impossible rate is refused', () async {
      await expectLater(
        addRule(id: 't1', rateBp: 10001),
        throwsA(isA<TaxRuleRejected>()),
      );
    });

    test('an end date before the start is refused', () async {
      await expectLater(
        addRule(id: 't1', from: '2026-07-01', to: '2026-06-01'),
        throwsA(isA<TaxRuleRejected>()),
      );
    });
  });

  group('changing a rate never restates history', () {
    test(
      'supersede closes the old period and opens the new one atomically',
      () async {
        await addRule(id: 't1', rateBp: 500, from: '2026-04-01');

        await tax.supersede(
          currentRuleId: 't1',
          newRuleId: 't2',
          orgId: seedOrgId,
          revenueCategoryId: restaurant,
          newRateBasisPoints: 1200,
          newTreatment: TaxTreatment.inclusive,
          changeoverDate: on('2026-10-01'),
          createdBy: 'u-owner',
          now: now,
        );

        final set = await tax.rulesFor(restaurant);
        expect(set.active.length, 2);
        // No gap and no overlap across the changeover.
        expect(set.gaps(), isEmpty);

        // Before the change: still 5%.
        final before = set.ruleFor(on('2026-09-30'))!;
        expect(before.rateBasisPoints, 500);
        // On and after: 12%.
        expect(set.ruleFor(on('2026-10-01'))!.rateBasisPoints, 1200);
      },
    );

    test(
      'a report re-run after a rate change still uses the old rate',
      () async {
        await addRule(id: 't1', rateBp: 500, from: '2026-04-01');
        await tax.supersede(
          currentRuleId: 't1',
          newRuleId: 't2',
          orgId: seedOrgId,
          revenueCategoryId: restaurant,
          newRateBasisPoints: 1200,
          newTreatment: TaxTreatment.inclusive,
          changeoverDate: on('2026-10-01'),
          createdBy: 'u-owner',
          now: now,
        );

        // A June sale of ₹1,050 must still yield ₹50 tax, not ₹112.50.
        final juneRule = await tax.resolveFor(
          revenueCategoryId: restaurant,
          businessDate: on('2026-06-15'),
        );
        expect(
          juneRule!.compute(const Money.fromRupees(1050)).tax,
          const Money.fromRupees(50),
        );
      },
    );

    test('a changeover on or before the current start is refused', () async {
      await addRule(id: 't1', from: '2026-04-01');
      await expectLater(
        tax.supersede(
          currentRuleId: 't1',
          newRuleId: 't2',
          orgId: seedOrgId,
          revenueCategoryId: restaurant,
          newRateBasisPoints: 1200,
          newTreatment: TaxTreatment.inclusive,
          changeoverDate: on('2026-04-01'),
          createdBy: 'u-owner',
          now: now,
        ),
        throwsA(isA<TaxRuleRejected>()),
      );
      expect((await tax.rulesFor(restaurant)).active.length, 1);
    });

    test('archiving a rule keeps the row and frees the period', () async {
      await addRule(id: 't1', from: '2026-04-01');
      await tax.archiveRule(id: 't1', now: now);

      final set = await tax.rulesFor(restaurant);
      expect(set.active, isEmpty);
      expect(set.rules.length, 1, reason: 'the row must not be deleted');

      // The period is now free for a replacement.
      await addRule(id: 't2', from: '2026-04-01', rateBp: 1200);
      expect((await tax.rulesFor(restaurant)).active.length, 1);
    });
  });

  group('vendors', () {
    test('a name alone is a complete vendor', () async {
      await vendors.create(
        id: 'v1',
        orgId: seedOrgId,
        code: 'VEG_MARKET',
        name: 'Local Vegetable Market',
        now: now,
      );

      final vendor = (await vendors.list()).single;
      expect(vendor.name, 'Local Vegetable Market');
      expect(vendor.phone, isNull);
      expect(vendor.gstin, isNull);
      expect(vendor.address, isNull);
      expect(vendor.hasContactDetails, isFalse);
      expect(vendor.isArchived, isFalse);
    });

    test(
      'blank optional fields are stored as null, not empty strings',
      () async {
        await vendors.create(
          id: 'v1',
          orgId: seedOrgId,
          code: 'V1',
          name: 'Sharma Traders',
          phone: '   ',
          gstin: '',
          now: now,
        );
        final vendor = (await vendors.list()).single;
        expect(vendor.phone, isNull);
        expect(vendor.gstin, isNull);
      },
    );

    test('a name is required', () async {
      await expectLater(
        vendors.create(
          id: 'v1',
          orgId: seedOrgId,
          code: 'V1',
          name: '   ',
          now: now,
        ),
        throwsA(isA<VendorWriteRefused>()),
      );
    });

    test(
      'a duplicate name is refused, and says so usefully when archived',
      () async {
        await vendors.create(
          id: 'v1',
          orgId: seedOrgId,
          code: 'V1',
          name: 'Sharma Traders',
          now: now,
        );
        await expectLater(
          vendors.create(
            id: 'v2',
            orgId: seedOrgId,
            code: 'V2',
            name: 'sharma traders',
            now: now,
          ),
          throwsA(isA<VendorWriteRefused>()),
        );

        await vendors.archive(id: 'v1', now: now);
        await expectLater(
          vendors.create(
            id: 'v3',
            orgId: seedOrgId,
            code: 'V3',
            name: 'Sharma Traders',
            now: now,
          ),
          throwsA(
            isA<VendorWriteRefused>().having(
              (e) => e.message,
              'message',
              contains('Restore it'),
            ),
          ),
        );
      },
    );

    test('search ranks prefix matches first and excludes archived', () async {
      await vendors.create(
        id: 'v1',
        orgId: seedOrgId,
        code: 'V1',
        name: 'Krishna Sharma Provisions',
        now: now,
      );
      await vendors.create(
        id: 'v2',
        orgId: seedOrgId,
        code: 'V2',
        name: 'Sharma Traders',
        now: now,
      );
      await vendors.create(
        id: 'v3',
        orgId: seedOrgId,
        code: 'V3',
        name: 'Sharma Dairy',
        now: now,
      );
      await vendors.archive(id: 'v3', now: now);

      final results = await vendors.search('sha');
      expect(results.map((v) => v.name), [
        'Sharma Traders',
        'Krishna Sharma Provisions',
      ]);
      expect(
        results.map((v) => v.name),
        isNot(contains('Sharma Dairy')),
        reason: 'an archived vendor must not be selectable',
      );
    });

    test('archiving preserves the record and can be undone', () async {
      await vendors.create(
        id: 'v1',
        orgId: seedOrgId,
        code: 'V1',
        name: 'Sharma Traders',
        now: now,
      );
      await vendors.archive(id: 'v1', now: now);

      expect(await vendors.list(), isEmpty);
      expect(
        (await vendors.list(includeArchived: true)).single.isArchived,
        isTrue,
      );
      // The row is still there — nothing was deleted.
      expect((await vendors.byId('v1'))!.name, 'Sharma Traders');

      await vendors.unarchive(id: 'v1', now: now);
      expect((await vendors.list()).single.isArchived, isFalse);
    });

    test('the code is immutable — update offers no way to change it', () async {
      await vendors.create(
        id: 'v1',
        orgId: seedOrgId,
        code: 'SHARMA',
        name: 'Sharma Traders',
        now: now,
      );
      await vendors.update(id: 'v1', name: 'Sharma Trading Co', now: now);

      final vendor = (await vendors.byId('v1'))!;
      expect(vendor.name, 'Sharma Trading Co');
      expect(vendor.code, 'SHARMA');
    });
  });

  group('usage authority', () {
    test('a local count never claims to be authoritative', () async {
      final reader = LocalMasterUsageReader(db);
      final usage = await reader.usageForMaster(seedId('bu', 'CCR'));

      expect(usage.isAuthoritative, isFalse);
      expect(usage.mayHaveMoreElsewhere, isTrue);
      expect(usage.summary, contains('server has not been checked'));
    });

    test('an unknown figure is distinct from zero', () async {
      const reader = UnavailableServerUsageReader();
      final usage = await reader.usageForMaster('anything');

      expect(usage, isA<UsageUnknown>());
      expect(usage.hasKnownHistory, isFalse);
      expect(usage.summary, contains('Usage unknown'));
      expect(usage.summary, contains('no backend'));
    });

    test('the layered reader falls back without upgrading the label', () async {
      final reader = LayeredMasterUsageReader(
        server: const UnavailableServerUsageReader(),
        local: LocalMasterUsageReader(db),
      );
      final usage = await reader.usageForMaster(seedId('bu', 'CCR'));

      // It fell back to local, and local is still local.
      expect(usage, isA<UsageCounted>());
      expect(usage.isAuthoritative, isFalse);
      expect((usage as UsageCounted).source, UsageSource.localCache);
    });

    test('a server figure is authoritative and complete', () {
      const usage = MasterUsage.server(transactionCount: 42);
      expect(usage.isAuthoritative, isTrue);
      expect(usage.mayHaveMoreElsewhere, isFalse);
      expect(usage.hasKnownHistory, isTrue);
      expect(usage.summary, '42 transactions');
    });
  });
}
