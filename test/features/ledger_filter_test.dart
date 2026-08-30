/// The ledger filter surface, and the rule that keeps it honest (D-073 §19–§20).
///
/// The dangerous filter is not the wrong one; it is the **stale** one. Narrowing to
/// Crystal Canopy while a Hotel Krishna section is still selected leaves two predicates
/// that intersect to nothing — and the section control is behind a collapsed panel, so
/// the ledger goes empty and the screen says nothing about why. Every test here is a
/// version of that.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/repositories/master_repository.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_filters.dart';
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late MasterGraph graph;
  final now = DateTime.utc(2026, 6, 15, 9);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await seedMasterData(db, now: now);
    graph = await MasterRepository(db).loadGraph();
  });

  tearDown(() => db.close());

  group('a narrowed parent drops the children it orphans', () {
    test(
      'choosing the other property clears department, section and category',
      () {
        final filter = ExpenseFilter(
          businessUnitId: ccrId,
          departmentId: ccrDeptId,
          sectionId: ccrSectionId,
          categoryId: ccrCategoryId,
        );
        expect(filter.withoutOrphanedChildren(graph), same(filter));

        final moved = filter
            .copyWith(businessUnitId: hkiId)
            .withoutOrphanedChildren(graph);

        expect(moved.businessUnitId, hkiId);
        expect(
          moved.departmentId,
          isNull,
          reason: 'a Crystal Canopy department is not in Hotel Krishna',
        );
        expect(moved.sectionId, isNull);
        expect(
          moved.categoryId,
          isNull,
          reason:
              'left behind it would intersect to nothing, from behind a collapsed panel',
        );
      },
    );

    test(
      'choosing another department clears the section and category below it',
      () {
        final filter = ExpenseFilter(
          businessUnitId: ccrId,
          departmentId: ccrDeptId,
          sectionId: ccrSectionId,
          categoryId: ccrCategoryId,
        );

        final otherDepartment = graph
            .departmentsOf(ccrId)
            .firstWhere((d) => d.id != ccrDeptId);
        final moved = filter
            .copyWith(departmentId: otherDepartment.id)
            .withoutOrphanedChildren(graph);

        expect(moved.departmentId, otherDepartment.id);
        expect(moved.sectionId, isNull);
        expect(moved.categoryId, isNull);
        expect(
          moved.businessUnitId,
          ccrId,
          reason: 'narrowing a child never widens the parent',
        );
      },
    );

    test('a section from another department clears only what it must', () {
      final otherDepartment = graph
          .departmentsOf(ccrId)
          .firstWhere((d) => d.id != ccrDeptId);
      final foreignSection = graph.sectionsOf(otherDepartment.id).first;

      final moved = ExpenseFilter(
        businessUnitId: ccrId,
        departmentId: ccrDeptId,
        sectionId: foreignSection.id,
      ).withoutOrphanedChildren(graph);

      expect(moved.businessUnitId, ccrId);
      expect(moved.departmentId, ccrDeptId);
      expect(
        moved.sectionId,
        isNull,
        reason: 'the section does not belong to the chosen department',
      );
    });

    test('a consistent chain is left exactly as it is', () {
      final filter = ExpenseFilter(
        businessUnitId: ccrId,
        departmentId: ccrDeptId,
        sectionId: ccrSectionId,
        categoryId: ccrCategoryId,
        vendorId: 'v1',
        paymentStatus: 'unpaid',
        includeVoided: true,
      );
      final same = filter.withoutOrphanedChildren(graph);

      expect(same.departmentId, ccrDeptId);
      expect(same.sectionId, ccrSectionId);
      expect(same.categoryId, ccrCategoryId);
      expect(
        same.vendorId,
        'v1',
        reason:
            'a vendor is organisation-global and hangs off no property (D-049)',
      );
      expect(same.paymentStatus, 'unpaid');
      expect(same.includeVoided, isTrue);
    });

    test('a child chosen with no parent selected is kept', () {
      // Choosing a category directly, with no unit or department, is a legitimate way to
      // ask "everything in Kirana & Pulses". There is nothing to be inconsistent with.
      final filter = ExpenseFilter(
        categoryId: ccrCategoryId,
      ).withoutOrphanedChildren(graph);
      expect(filter.categoryId, ccrCategoryId);
    });

    test('a selection that no longer exists is dropped rather than kept', () {
      final filter = ExpenseFilter(
        departmentId: const Uuid().v4(),
        sectionId: const Uuid().v4(),
        categoryId: const Uuid().v4(),
      ).withoutOrphanedChildren(graph);

      expect(filter.departmentId, isNull);
      expect(filter.sectionId, isNull);
      expect(filter.categoryId, isNull);
    });
  });

  group('the filter reaches the query, not a list in memory', () {
    late ExpenseRepository repository;

    setUp(() async {
      repository = ExpenseRepository(db);
      // Two documents: one Crystal Canopy grocery bill, one Hotel Krishna electricity.
      // `line` derives the whole classification from the unit, so each lands in a
      // different department, section and category.
      await repository.createLocally(
        expenseWith(lines: [line(unit: ccrId, rupees: 200)]),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      await repository.createLocally(
        expenseWith(lines: [line(unit: hkiId, rupees: 500)]),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
    });

    test('each hierarchy rung narrows the result', () async {
      expect(await repository.query(const ExpenseFilter()), hasLength(2));

      expect(
        await repository.query(ExpenseFilter(businessUnitId: ccrId)),
        hasLength(1),
      );
      expect(
        await repository.query(ExpenseFilter(departmentId: ccrDeptId)),
        hasLength(1),
      );
      expect(
        await repository.query(ExpenseFilter(sectionId: ccrSectionId)),
        hasLength(1),
      );
      expect(
        await repository.query(ExpenseFilter(categoryId: ccrCategoryId)),
        hasLength(1),
      );
      expect(
        await repository.query(ExpenseFilter(departmentId: hkiDeptId)),
        hasLength(1),
      );
    });

    test(
      'an inconsistent pair returns nothing, which is why they are cleared',
      () async {
        // The state this whole dependency rule exists to prevent: a Crystal Canopy
        // department beside a Hotel Krishna unit. The query is right; the *filter* was the
        // problem, and the ledger would simply have looked empty.
        final contradictory = ExpenseFilter(
          businessUnitId: hkiId,
          departmentId: ccrDeptId,
        );
        expect(await repository.query(contradictory), isEmpty);

        final corrected = contradictory.withoutOrphanedChildren(graph);
        expect(await repository.query(corrected), hasLength(1));
      },
    );
  });

  group('the active count is what the Filters button shows', () {
    test('it counts narrowing choices, and a date range counts once', () {
      expect(const ExpenseFilter().activeCount, 0);
      expect(
        const ExpenseFilter(from: '2026-06-01', to: '2026-06-30').activeCount,
        1,
        reason: 'a range is one choice, not two',
      );
      expect(
        ExpenseFilter(
          businessUnitId: ccrId,
          departmentId: ccrDeptId,
          includeVoided: true,
        ).activeCount,
        3,
      );
      expect(
        const ExpenseFilter(search: 'KI-EXP').activeCount,
        0,
        reason:
            'search has its own visible box, so it is not hidden behind the button',
      );
    });
  });
}
