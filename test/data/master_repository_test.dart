/// Master data over the real local database.
///
/// The domain tests prove the *rules*; these prove they actually hold against SQLite,
/// with foreign keys on and the seed loaded.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/master_repository.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/masters/master_reference.dart';

void main() {
  late AppDatabase db;
  late MasterRepository masters;
  final now = DateTime.utc(2026, 6, 15, 9);

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    masters = MasterRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seed() => seedMasterData(db, now: now);

  String cat(String unit, String section, String code) =>
      seedId('cat', '$unit-$section-$code');

  group('seed data', () {
    test(
      'creates both properties with Nandbhog as a Crystal Canopy category',
      () async {
        await seed();
        final graph = await masters.loadGraph();

        expect(graph.businessUnits().map((u) => u.code), ['CCR', 'HKI']);

        final ccrRevenue = graph.revenueCategoriesOf(seedId('bu', 'CCR'));
        expect(
          ccrRevenue.map((c) => c.code),
          containsAll(['RESTAURANT', 'NANDBHOG']),
        );
        // Nandbhog is a revenue stream, never a business unit (D-024).
        expect(
          graph.businessUnits().map((u) => u.code),
          isNot(contains('NANDBHOG')),
        );

        expect(
          graph.revenueCategoriesOf(seedId('bu', 'HKI')).map((c) => c.name),
          containsAll(['Room', 'Banquet']),
        );
      },
    );

    test('is idempotent — running it twice changes nothing', () async {
      await seed();
      final first = await masters.loadGraph();
      final firstCount = first.businessUnits().length;

      await seed();
      final second = await masters.loadGraph();

      expect(second.businessUnits().length, firstCount);
      expect(
        second.categoriesOf(seedId('sec', 'CCR-FOOD_PROD')).length,
        first.categoriesOf(seedId('sec', 'CCR-FOOD_PROD')).length,
      );
    });

    test('does not undo an owner edit on a re-run', () async {
      await seed();
      await masters.rename(
        kind: MasterKind.expenseCategory,
        id: cat('CCR', 'FOOD_PROD', 'KIRANA'),
        name: 'Kirana and Pulses',
        now: now,
      );

      await seed();

      final graph = await masters.loadGraph();
      expect(
        graph.expenseCategory(cat('CCR', 'FOOD_PROD', 'KIRANA'))!.name,
        'Kirana and Pulses',
      );
    });

    test('electricity is marked shared for both properties', () async {
      await seed();
      final rows = await db.select(db.expenseCategories).get();
      final electricity = rows.where((r) => r.code == 'ELECTRICITY').toList();
      expect(electricity.length, 2, reason: 'one per property');
      expect(electricity.every((r) => r.isSharedByDefault), isTrue);
    });

    test('seeds no financial data whatsoever', () async {
      await seed();
      // The seed is business structure only. Nothing here implies a transaction.
      expect(await db.select(db.syncOutbox).get(), isEmpty);
    });
  });

  group('hierarchy integrity over real data', () {
    test('a valid Crystal Canopy path is accepted', () async {
      await seed();
      final result = await masters.validatePath(
        HierarchyPath(
          businessUnitId: seedId('bu', 'CCR'),
          departmentId: seedId('dept', 'CCR-FB'),
          sectionId: seedId('sec', 'CCR-FOOD_PROD'),
          categoryId: cat('CCR', 'FOOD_PROD', 'KIRANA'),
        ),
        forNewEntry: true,
      );
      expect(result.isValid, isTrue);
    });

    test(
      'a Hotel Krishna section under a Crystal Canopy department is rejected',
      () async {
        await seed();
        final result = await masters.validatePath(
          HierarchyPath(
            businessUnitId: seedId('bu', 'CCR'),
            departmentId: seedId('dept', 'CCR-FB'),
            sectionId: seedId('sec', 'HKI-HKI_POWER'),
            categoryId: cat('HKI', 'HKI_POWER', 'DIESEL'),
          ),
          forNewEntry: true,
        );
        expect(result.isValid, isFalse);
        expect(
          result.violations,
          contains(HierarchyViolation.sectionNotInDepartment),
        );
      },
    );

    test(
      "one property's electricity cannot be booked under the other's section",
      () async {
        await seed();
        final result = await masters.validatePath(
          HierarchyPath(
            businessUnitId: seedId('bu', 'HKI'),
            departmentId: seedId('dept', 'HKI-HKI_UTIL'),
            sectionId: seedId('sec', 'HKI-HKI_POWER'),
            categoryId: cat('CCR', 'CCR_UTIL_SVC', 'ELECTRICITY'),
          ),
          forNewEntry: true,
        );
        expect(
          result.violations,
          contains(HierarchyViolation.categoryNotInSection),
        );
      },
    );

    test(
      'a category id used where a section is expected does not silently match',
      () async {
        await seed();
        final result = await masters.validatePath(
          HierarchyPath(
            businessUnitId: seedId('bu', 'CCR'),
            departmentId: seedId('dept', 'CCR-FB'),
            sectionId: cat(
              'CCR',
              'FOOD_PROD',
              'KIRANA',
            ), // a category, not a section
            categoryId: cat('CCR', 'FOOD_PROD', 'KIRANA'),
          ),
          forNewEntry: true,
        );
        expect(result.violations, contains(HierarchyViolation.unknownSection));
      },
    );

    test('a category resolves its full chain for form pre-fill', () async {
      await seed();
      final graph = await masters.loadGraph();
      final path = graph.pathForCategory(cat('HKI', 'HKI_POWER', 'DIESEL'));
      expect(path!.businessUnitId, seedId('bu', 'HKI'));
      expect(path.departmentId, seedId('dept', 'HKI-HKI_UTIL'));
      expect(path.sectionId, seedId('sec', 'HKI-HKI_POWER'));
    });
  });

  group('creation guards', () {
    test(
      'a child cannot be created under a parent that does not exist',
      () async {
        await seed();
        await expectLater(
          masters.createSection(
            id: 'new-section',
            orgId: seedOrgId,
            departmentId: 'no-such-department',
            code: 'X',
            name: 'X',
            now: now,
          ),
          throwsA(isA<MasterWriteRefused>()),
        );
      },
    );

    test('a child cannot be created under an archived parent', () async {
      await seed();
      final department = seedId('dept', 'CCR-CCR_OTHER');
      // Archive bottom-up: category, then section, then department.
      await masters.archive(
        kind: MasterKind.expenseCategory,
        id: cat('CCR', 'CCR_OTHER_OPS', 'OTHER_OPEX'),
        now: now,
      );
      await masters.archive(
        kind: MasterKind.section,
        id: seedId('sec', 'CCR-CCR_OTHER_OPS'),
        now: now,
      );
      await masters.archive(
        kind: MasterKind.department,
        id: department,
        now: now,
      );

      await expectLater(
        masters.createSection(
          id: 'new-section',
          orgId: seedOrgId,
          departmentId: department,
          code: 'NEW',
          name: 'New Section',
          now: now,
        ),
        throwsA(isA<MasterWriteRefused>()),
      );
    });

    test(
      'a duplicate code under the same parent is rejected by the database',
      () async {
        await seed();
        await expectLater(
          masters.createExpenseCategory(
            id: 'duplicate',
            orgId: seedOrgId,
            sectionId: seedId('sec', 'CCR-FOOD_PROD'),
            code: 'KIRANA',
            name: 'Kirana again',
            now: now,
          ),
          throwsA(anything),
        );
      },
    );

    test('the same code under a different parent is fine', () async {
      await seed();
      // WATER legitimately exists under both properties.
      final rows = await db.select(db.expenseCategories).get();
      expect(rows.where((r) => r.code == 'WATER').length, 2);
    });
  });

  group('archive semantics', () {
    test('a master with live children may not be archived', () async {
      await seed();
      final decision = await masters.archive(
        kind: MasterKind.section,
        id: seedId('sec', 'CCR-FOOD_PROD'),
        now: now,
      );
      expect(decision.isAllowed, isFalse);
      expect(decision.refusal, ArchiveRefusal.hasActiveChildren);

      final graph = await masters.loadGraph();
      expect(
        graph.section(seedId('sec', 'CCR-FOOD_PROD'))!.isArchived,
        isFalse,
      );
    });

    test(
      'a leaf archives, and disappears from pickers but not from the record',
      () async {
        await seed();
        final kirana = cat('CCR', 'FOOD_PROD', 'KIRANA');
        final decision = await masters.archive(
          kind: MasterKind.expenseCategory,
          id: kirana,
          now: now,
        );
        expect(decision.isAllowed, isTrue);

        final graph = await masters.loadGraph();
        final section = seedId('sec', 'CCR-FOOD_PROD');
        expect(
          graph.categoriesOf(section).map((c) => c.id),
          isNot(contains(kirana)),
        );
        expect(
          graph.categoriesOf(section, includeArchived: true).map((c) => c.id),
          contains(kirana),
        );
        // The row still exists — nothing was deleted.
        expect(graph.expenseCategory(kirana), isNotNull);
      },
    );

    test('archiving never deletes a row', () async {
      await seed();
      final before = (await db.select(db.expenseCategories).get()).length;
      await masters.archive(
        kind: MasterKind.expenseCategory,
        id: cat('CCR', 'FOOD_PROD', 'KIRANA'),
        now: now,
      );
      expect((await db.select(db.expenseCategories).get()).length, before);
    });

    test('an archived master stays valid for existing history', () async {
      await seed();
      final path = HierarchyPath(
        businessUnitId: seedId('bu', 'CCR'),
        departmentId: seedId('dept', 'CCR-FB'),
        sectionId: seedId('sec', 'CCR-FOOD_PROD'),
        categoryId: cat('CCR', 'FOOD_PROD', 'KIRANA'),
      );
      await masters.archive(
        kind: MasterKind.expenseCategory,
        id: path.categoryId,
        now: now,
      );

      // New entries are refused...
      expect(
        (await masters.validatePath(path, forNewEntry: true)).isValid,
        isFalse,
      );
      // ...but the ₹1,50,181 already booked against it remains valid.
      expect(
        (await masters.validatePath(path, forNewEntry: false)).isValid,
        isTrue,
      );
    });

    test(
      'archiving twice is refused rather than reported as success',
      () async {
        await seed();
        final kirana = cat('CCR', 'FOOD_PROD', 'KIRANA');
        await masters.archive(
          kind: MasterKind.expenseCategory,
          id: kirana,
          now: now,
        );
        final second = await masters.archive(
          kind: MasterKind.expenseCategory,
          id: kirana,
          now: now,
        );
        expect(second.refusal, ArchiveRefusal.alreadyArchived);
      },
    );

    test('an archive made in error can be undone', () async {
      await seed();
      final kirana = cat('CCR', 'FOOD_PROD', 'KIRANA');
      await masters.archive(
        kind: MasterKind.expenseCategory,
        id: kirana,
        now: now,
      );
      await masters.unarchive(
        kind: MasterKind.expenseCategory,
        id: kirana,
        now: now,
      );
      final graph = await masters.loadGraph();
      expect(graph.expenseCategory(kirana)!.isArchived, isFalse);
    });
  });

  group('rename and historical integrity', () {
    test('a rename changes the name and leaves the code untouched', () async {
      await seed();
      final kirana = cat('CCR', 'FOOD_PROD', 'KIRANA');

      final graph = await masters.loadGraph();
      final recorded = graph.referenceTo(kirana)!;
      expect(recorded.labelSnapshot, 'Kirana & Pulses');

      await masters.rename(
        kind: MasterKind.expenseCategory,
        id: kirana,
        name: 'Kirana and Pulses',
        now: now,
      );

      final after = await masters.loadGraph();
      final node = after.expenseCategory(kirana)!;
      expect(node.name, 'Kirana and Pulses');
      expect(node.code, 'KIRANA', reason: 'the code must never move');
      expect(node.id, kirana, reason: 'aggregation keys on the id');

      // History still reports what was actually recorded, and can flag the rename.
      expect(recorded.labelSnapshot, 'Kirana & Pulses');
      expect(recorded.wasRenamedSince(node.name), isTrue);
      expect(recorded.displayName(currentName: node.name), 'Kirana and Pulses');
    });

    test(
      'a rename bumps row_version, so a stale edit can be detected',
      () async {
        await seed();
        final kirana = cat('CCR', 'FOOD_PROD', 'KIRANA');
        final before = (await db.select(db.expenseCategories).get())
            .firstWhere((r) => r.id == kirana)
            .rowVersion;

        await masters.rename(
          kind: MasterKind.expenseCategory,
          id: kirana,
          name: 'Renamed',
          now: now,
        );

        final after = (await db.select(db.expenseCategories).get())
            .firstWhere((r) => r.id == kirana)
            .rowVersion;
        expect(after, before + 1);
      },
    );

    test('an empty name is refused', () async {
      await seed();
      await expectLater(
        masters.rename(
          kind: MasterKind.expenseCategory,
          id: cat('CCR', 'FOOD_PROD', 'KIRANA'),
          name: '   ',
          now: now,
        ),
        throwsA(isA<MasterWriteRefused>()),
      );
    });

    test('renaming something that does not exist is refused', () async {
      await seed();
      await expectLater(
        masters.rename(
          kind: MasterKind.section,
          id: 'nope',
          name: 'X',
          now: now,
        ),
        throwsA(isA<MasterWriteRefused>()),
      );
    });
  });

  group('foreign keys are actually enforced', () {
    test('a section cannot reference a department that does not exist', () async {
      // Bypassing the repository entirely: the database itself must refuse.
      await expectLater(
        db.customStatement(
          "INSERT INTO sections (id, org_id, code, name, sort_order, row_version, "
          "updated_at, department_id) VALUES "
          "('s1', 'org', 'X', 'X', 0, 1, '2026-06-15T09:00:00.000Z', 'ghost-department')",
        ),
        throwsA(anything),
      );
    });
  });
}
