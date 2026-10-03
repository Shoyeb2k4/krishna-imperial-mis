/// The expense surfaces, driven as a user drives them.
///
/// The assertions that matter are the ones about money and about what a scoped user is
/// shown: an amount that reads back in Indian grouping, a Save button that stays disabled
/// while a split does not reconcile, and a share that is never labelled as a total.
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_draft.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_entry_page.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_ledger_page.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/expense_detail_panel.dart';
import 'package:uuid/uuid.dart';

import '../support/ui_harness.dart';
import '../support/money_layout.dart';
import '../support/expense_fixtures.dart';
import '../support/test_session.dart';

final _june15 = BusinessDate.of(2026, 6, 15);

Principal _principalFor(Set<Capability> bundle, Set<String?> units) =>
    Principal(
      userId: 'u',
      grants: [
        for (final unit in units)
          for (final capability in bundle)
            CapabilityGrant(capability, businessUnitId: unit),
      ],
    );

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await seedMasterData(db, now: DateTime.utc(2026, 6, 15));
  });

  tearDown(() => db.close());

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required Principal principal,
    Size size = const Size(430, 932),
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          outboxProvider.overrideWithValue(OutboxRepository(db)),
          sessionProvider.overrideWith(
            () => StubSession(readySession(authority: authorityFor(principal))),
          ),
          principalProvider.overrideWithValue(principal),
          currentBusinessDateProvider.overrideWithValue(_june15),
          ...overrides,
        ],
        // Both shells put their branches inside a Scaffold; the harness does the same
        // rather than pretending a page can float free of one.
        child: MaterialApp(
          theme: AppTheme.mobile,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Android entry — the fast path', () {
    testWidgets('amount reads back with Indian grouping', (tester) async {
      await pump(
        tester,
        const ExpenseEntryPage(),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
      );

      await tester.enterText(find.byKey(const Key('expense-amount')), '12500');
      await tester.pump();
      expect(findFigure('₹12,500'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('expense-amount')),
        '1236420',
      );
      await tester.pump();
      expect(
        findFigure('₹12,36,420'),
        findsOneWidget,
        reason: 'lakhs, not thousands — ₹1,236,420 would be wrong',
      );

      await tester.enterText(
        find.byKey(const Key('expense-amount')),
        '12500.50',
      );
      await tester.pump();
      expect(findFigure('₹12,500.50'), findsOneWidget);
    });

    testWidgets('a malformed amount is said to be malformed', (tester) async {
      await pump(
        tester,
        const ExpenseEntryPage(),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
      );

      await tester.enterText(find.byKey(const Key('expense-amount')), '12.345');
      await tester.pump();

      expect(find.text('That is not an amount this can read'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-expense')))
            .onPressed,
        isNull,
        reason: 'and it certainly does not silently round to two places',
      );
    });

    testWidgets('the optional fields start closed', (tester) async {
      await pump(
        tester,
        const ExpenseEntryPage(),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
      );

      expect(find.text('More details'), findsOneWidget);
      expect(
        find.byKey(const Key('vendor-picker')),
        findsNothing,
        reason: 'a ₹500 vegetable purchase never opens this',
      );
      expect(find.byKey(const Key('payment-method')), findsNothing);
    });

    testWidgets('Save is blocked until the expense is complete, and says why', (
      tester,
    ) async {
      await pump(
        tester,
        const ExpenseEntryPage(),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
      );

      // Nothing entered: the first thing missing is the amount.
      expect(find.text('Enter the amount.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('expense-amount')), '500');
      await tester.pump();
      expect(
        find.text('Choose the property, department, section and category.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-expense')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('the classification drills down and cascades', (tester) async {
      await pump(
        tester,
        const ExpenseEntryPage(),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
      );

      await tester.tap(find.byKey(const Key('classification-summary')));
      await tester.pumpAndSettle();

      // One property in scope, so the sheet opens at Department.
      expect(find.text('Department'), findsOneWidget);
      await tester.tap(find.text('F&B / Kitchen'));
      await tester.pumpAndSettle();
      expect(find.text('Section'), findsOneWidget);
      await tester.tap(find.text('Food Production'));
      await tester.pumpAndSettle();
      expect(find.text('Category'), findsOneWidget);

      // Archived masters are never offered for a new entry.
      await tester.tap(find.text('Kirana & Pulses'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Kirana & Pulses'),
        findsWidgets,
        reason: 'the chosen chain is shown on the form',
      );
    });

    testWidgets('a manager is not offered Split expense', (tester) async {
      await pump(
        tester,
        const ExpenseEntryPage(),
        principal: _principalFor(RoleTemplates.manager, {ccrId, hkiId}),
      );

      expect(
        find.byKey(const Key('split-expense')),
        findsNothing,
        reason:
            'holding both scopes is not the same as being allowed to apportion '
            'one cost between them (D-061)',
      );
    });

    testWidgets('an accountant is', (tester) async {
      await pump(
        tester,
        const ExpenseEntryPage(),
        principal: _principalFor(RoleTemplates.accountant, {ccrId, hkiId}),
      );

      expect(find.byKey(const Key('split-expense')), findsOneWidget);
    });
  });

  group('splitting shows the remainder and refuses to balance itself', () {
    testWidgets('₹25,000 + ₹32,000 against ₹58,000 leaves ₹1,000', (
      tester,
    ) async {
      await pump(
        tester,
        const ExpenseEntryPage(),
        principal: _principalFor(RoleTemplates.accountant, {ccrId, hkiId}),
      );

      await tester.enterText(find.byKey(const Key('expense-amount')), '58000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('split-expense')));
      await tester.pumpAndSettle();

      final amounts = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.prefixText == '₹ ',
      );
      // The header total, then the first allocation.
      await tester.enterText(amounts.at(1), '25000');
      await tester.pump();

      await tester.tap(find.byKey(const Key('add-allocation')));
      await tester.pumpAndSettle();
      await tester.enterText(amounts.at(2), '32000');
      await tester.pump();

      expect(find.text('REMAINING'), findsOneWidget);
      expect(findFigure('₹1,000.00'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-expense')))
            .onPressed,
        isNull,
        reason: 'no adjustment line is invented to make it balance',
      );
    });
  });

  group('the ledger never presents a share as a total', () {
    /// A scoped record, exactly as the server projection would deliver it.
    Future<void> insertScopedShare() async {
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: 'shared-1',
              orgId: seedOrgId,
              txnNumber: const Value('KI-EXP-26-27-000001'),
              financialYear: const Value(2026),
              businessDate: '2026-06-15',
              visibility: const Value('scoped'),
              // No document total: the server withheld it, and the schema refuses one.
              visibleAmountMinor: 2500000,
              isShared: const Value(true),
              createdBy: 'someone-else',
              capturedAt: DateTime.utc(2026, 6, 15),
              updatedAt: DateTime.utc(2026, 6, 15),
            ),
          );
      await db
          .into(db.expenseAllocations)
          .insert(
            ExpenseAllocationsCompanion.insert(
              id: 'shared-line',
              orgId: seedOrgId,
              expenseId: 'shared-1',
              businessUnitId: ccrId,
              departmentId: ccrDeptId,
              sectionId: ccrSectionId,
              categoryId: ccrCategoryId,
              amountMinor: 2500000,
              categoryLabel: 'Electricity',
              updatedAt: DateTime.utc(2026, 6, 15),
            ),
          );
      await db
          .into(db.expensePeriodAllocations)
          .insert(
            ExpensePeriodAllocationsCompanion.insert(
              id: 'shared-period',
              orgId: seedOrgId,
              expenseId: 'shared-1',
              allocationId: 'shared-line',
              businessUnitId: ccrId,
              accountingPeriodStart: '2026-06-15',
              accountingPeriodEnd: '2026-06-15',
              amountMinor: 2500000,
              pnlDate: '2026-06-15',
              pnlPeriodKey: '2026-06',
              updatedAt: DateTime.utc(2026, 6, 15),
            ),
          );
    }

    testWidgets('the detail says "Your allocation", never "Total"', (
      tester,
    ) async {
      await insertScopedShare();
      await pump(
        tester,
        const ExpenseDetailPanel(expenseId: 'shared-1'),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
      );

      expect(find.text('YOUR ALLOCATION'), findsOneWidget);
      expect(
        find.text('TOTAL'),
        findsNothing,
        reason: '₹25,000 is not the invoice, and must never be labelled as it',
      );
      expect(find.byKey(const Key('scoped-explanation')), findsOneWidget);
      expect(
        find.textContaining('58'),
        findsNothing,
        reason: 'the withheld total is not on this device at all',
      );
    });

    testWidgets('a scoped record explains why there is no attachment', (
      tester,
    ) async {
      await insertScopedShare();
      await pump(
        tester,
        const ExpenseDetailPanel(expenseId: 'shared-1'),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
      );

      expect(
        find.textContaining(
          'available to users who can see the whole document',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a complete record does say Total', (tester) async {
      final expense = simpleExpense();
      await ExpenseRepository(db).createLocally(
        expense,
        actorUserId: 'u',
        mutationId: const Uuid().v4(),
        now: DateTime.utc(2026, 6, 15),
      );

      await pump(
        tester,
        ExpenseDetailPanel(expenseId: expense.id),
        principal: _principalFor(RoleTemplates.accountant, {ccrId, hkiId}),
      );

      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text('YOUR ALLOCATION'), findsNothing);
    });
  });

  group('what the ledger says about state', () {
    uiTest('a locally saved expense shows a pending number', (tester) async {
      final expense = simpleExpense();
      await ExpenseRepository(db).createLocally(
        expense,
        actorUserId: 'u',
        mutationId: const Uuid().v4(),
        now: DateTime.utc(2026, 6, 15),
      );

      await pump(
        tester,
        const ExpenseLedgerPage(shellKind: AppShellKind.mobile),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
      );

      expect(find.textContaining('Pending number'), findsOneWidget);
      expect(find.textContaining('KI-EXP'), findsNothing);
    });

    uiTest('an empty ledger says something operationally useful', (
      tester,
    ) async {
      await pump(
        tester,
        const ExpenseLedgerPage(shellKind: AppShellKind.mobile),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
      );

      expect(find.text('No expenses recorded yet.'), findsOneWidget);
      expect(find.textContaining('No data found'), findsNothing);
    });

    testWidgets('a voided expense is marked, not hidden', (tester) async {
      final expense = simpleExpense();
      final repository = ExpenseRepository(db);
      await repository.createLocally(
        expense,
        actorUserId: 'u',
        mutationId: const Uuid().v4(),
        now: DateTime.utc(2026, 6, 15),
      );
      final loaded = await repository.load(expense.id);
      await repository.voidLocally(
        loaded!,
        reason: 'Entered twice',
        actorUserId: 'accountant',
        mutationId: const Uuid().v4(),
        now: DateTime.utc(2026, 6, 16),
      );

      await pump(
        tester,
        ExpenseDetailPanel(expenseId: expense.id),
        principal: _principalFor(RoleTemplates.accountant, {ccrId, hkiId}),
      );

      expect(find.byKey(const Key('voided-banner')), findsOneWidget);
      expect(find.byKey(const Key('voided-immutable-note')), findsOneWidget);
      expect(
        find.byKey(const Key('void-expense')),
        findsNothing,
        reason: 'a voided document cannot be voided again',
      );
      expect(find.text('Entered twice'), findsOneWidget);
    });
  });

  group('void is offered only to those who may', () {
    Future<String> saved() async {
      final expense = simpleExpense();
      await ExpenseRepository(db).createLocally(
        expense,
        actorUserId: 'u',
        mutationId: const Uuid().v4(),
        now: DateTime.utc(2026, 6, 15),
      );
      return expense.id;
    }

    testWidgets('a manager is not offered Void', (tester) async {
      final id = await saved();
      await pump(
        tester,
        ExpenseDetailPanel(expenseId: id),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
      );
      expect(find.byKey(const Key('void-expense')), findsNothing);
    });

    testWidgets('data entry is not offered Void', (tester) async {
      final id = await saved();
      await pump(
        tester,
        ExpenseDetailPanel(expenseId: id),
        principal: _principalFor(RoleTemplates.dataEntry, {ccrId}),
      );
      expect(find.byKey(const Key('void-expense')), findsNothing);
    });

    testWidgets('an accountant is, and must type a reason', (tester) async {
      final id = await saved();
      await pump(
        tester,
        ExpenseDetailPanel(expenseId: id),
        principal: _principalFor(RoleTemplates.accountant, {ccrId, hkiId}),
      );

      expect(find.byKey(const Key('void-expense')), findsOneWidget);
      await tester.tap(find.byKey(const Key('void-expense')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-void')))
            .onPressed,
        isNull,
        reason: 'no default reason is offered, and none is accepted',
      );

      await tester.enterText(
        find.byKey(const Key('void-reason')),
        'Duplicate of KI-EXP-26-27-000012',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-void')))
            .onPressed,
        isNotNull,
      );
    });
  });

  // ── The Phase 3 corrective, on the surface a person actually meets ─────────
  //
  // The server refuses regardless, and that is where the boundary is (D-037). What is
  // asserted here is that nobody is offered a control whose every outcome would be
  // refused, and that somebody who *may* correct a date is asked for the reason the
  // server will require rather than meeting a bare rejection after pressing Save.
  group('correcting the business date of a recorded expense', () {
    final june16 = BusinessDate.of(2026, 6, 16);

    ExpenseDraft loaded() => ExpenseDraft.fromExisting(
      id: 'e-edit-1',
      rowVersion: 3,
      businessDate: _june15,
      total: Money.fromRupees(500),
      txnNumber: 'KI-EXP-26-27-000031',
      allocations: [
        AllocationDraft(
          id: 'a1',
          businessUnitId: ccrId,
          departmentId: ccrDeptId,
          sectionId: ccrSectionId,
          categoryId: ccrCategoryId,
          amount: Money.fromRupees(500),
        ),
      ],
    );

    /// The Accountant bundle, which holds `transaction.correct.business_date`.
    Principal finance() => _principalFor(RoleTemplates.accountant, {ccrId});

    /// The Manager bundle, which does not.
    Principal manager() => _principalFor(RoleTemplates.manager, {ccrId});

    testWidgets('a new expense still offers an ordinary, editable date row', (
      tester,
    ) async {
      await pump(tester, const ExpenseEntryPage(), principal: manager());

      expect(find.byKey(const Key('business-date')), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(
              find.ancestor(
                of: find.byKey(const Key('business-date')),
                matching: find.byType(InkWell),
              ),
            )
            .onTap,
        isNotNull,
        reason:
            'choosing the date of an expense being recorded now is `manual`, not a '
            'correction, and has never needed a capability (D-019)',
      );
      expect(
        find.byKey(const Key('business-date-correction-reason')),
        findsNothing,
      );
    });

    testWidgets('an editor without the capability cannot open the date picker', (
      tester,
    ) async {
      await pump(
        tester,
        ExpenseEntryPage.editing(
          loaded(),
          capturedAt: DateTime.utc(2026, 6, 15),
        ),
        principal: manager(),
      );

      expect(
        find.byKey(const Key('business-date')),
        findsOneWidget,
        reason: 'the date is part of the document and is still shown',
      );
      expect(
        tester
            .widget<InkWell>(
              find.ancestor(
                of: find.byKey(const Key('business-date')),
                matching: find.byType(InkWell),
              ),
            )
            .onTap,
        isNull,
        reason:
            'a picker whose every outcome the server would refuse is worse than no '
            'picker — hiding it is not the boundary, it is the honesty',
      );
    });

    testWidgets('an editor with the capability can, and is asked why', (
      tester,
    ) async {
      await pump(
        tester,
        ExpenseEntryPage.editing(
          loaded(),
          capturedAt: DateTime.utc(2026, 6, 15),
        ),
        principal: finance(),
      );

      // Nothing is asked for until the date actually differs from the loaded one.
      expect(
        find.byKey(const Key('business-date-correction-reason')),
        findsNothing,
      );
      expect(
        tester
            .widget<InkWell>(
              find.ancestor(
                of: find.byKey(const Key('business-date')),
                matching: find.byType(InkWell),
              ),
            )
            .onTap,
        isNotNull,
      );
    });

    testWidgets('the reason appears when the date moves, and Save waits for it', (
      tester,
    ) async {
      // Driven through the draft rather than the OS date picker, which is a separate
      // route the harness cannot open — the same honest boundary D-077 records for the
      // attachment picker. What is under test is the form's reaction to a moved date.
      final page = ExpenseEntryPage.editing(
        loaded().copyWith(businessDate: june16),
        capturedAt: DateTime.utc(2026, 6, 15),
      );
      await pump(tester, page, principal: finance());

      expect(
        find.byKey(const Key('business-date-correction-notice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('business-date-correction-reason')),
        findsOneWidget,
      );
      expect(
        find.text('Business date changed from 2026-06-15 to 2026-06-16'),
        findsOneWidget,
        reason: 'the person is told what they changed, in both directions',
      );

      final saveButton = find.byKey(const Key('save-expense'));
      expect(
        tester.widget<FilledButton>(saveButton).onPressed,
        isNull,
        reason: 'no reason yet, and the server would refuse it',
      );

      await tester.enterText(
        find.byKey(const Key('business-date-correction-reason')),
        '   ',
      );
      await tester.pump();
      expect(
        tester.widget<FilledButton>(saveButton).onPressed,
        isNull,
        reason: 'blank is not a reason, on this side as well as the server s',
      );

      await tester.enterText(
        find.byKey(const Key('business-date-correction-reason')),
        'Recorded against the wrong trading day',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
    });
  });

  // D-326. Two presses before the next frame both used to reach `_save`, because the
  // button is disabled only once it rebuilds. The count is taken at the controller — the
  // first thing the form calls — so the database is not what stops the second.
  group('Save runs once per act (D-326)', () {
    /// Opens the entry page as production does: pushed, so a save can pop back.
    Future<Future<String?>> open(
      WidgetTester tester,
      List<String> saves, {
      bool failFirst = false,
    }) async {
      await pump(
        tester,
        const SizedBox.shrink(),
        principal: _principalFor(RoleTemplates.manager, {ccrId}),
        overrides: [
          expenseEntryControllerProvider.overrideWith(
            (ref) =>
                _CountingExpenseController(ref, saves, failFirst: failFirst),
          ),
        ],
      );
      final popped = tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<String>(
              builder: (_) => const Scaffold(body: ExpenseEntryPage()),
            ),
          );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('expense-amount')), '500');
      await tester.pump();
      await tester.tap(find.byKey(const Key('classification-summary')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('F&B / Kitchen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food Production'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kirana & Pulses'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-expense')))
            .onPressed,
        isNotNull,
        reason: 'the expense is complete and may be saved',
      );
      return popped;
    }

    Future<int> count(String table) async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS n FROM $table')
          .getSingle();
      return row.data['n'] as int;
    }

    uiTest('a double tap records one expense, not two', (tester) async {
      final saves = <String>[];
      final popped = await open(tester, saves);

      await tester.tap(find.byKey(const Key('save-expense')));
      await tester.tap(find.byKey(const Key('save-expense')));
      await tester.pumpAndSettle();

      expect(
        saves,
        hasLength(1),
        reason: 'the second press returns before it reaches the controller',
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('could not be saved'), findsNothing);
      expect(
        await popped,
        saves.single,
        reason: 'the first save completes normally and returns its expense',
      );
      expect(await count('expenses'), 1);
      expect(await count('sync_outbox'), 1, reason: 'and one queued intent');
    });

    // The guard must not become a latch: a failed save releases it, and a later
    // explicit press runs again.
    uiTest('a save that fails can be retried', (tester) async {
      final saves = <String>[];
      final popped = await open(tester, saves, failFirst: true);

      await tester.tap(find.byKey(const Key('save-expense')));
      await tester.pumpAndSettle();

      expect(saves, hasLength(1));
      expect(tester.takeException(), isNull, reason: 'shown, not thrown');
      expect(find.text(expenseSaveFailed), findsOneWidget);
      // The cause stays in the developer log; the screen names neither the exception
      // type nor its text (D-348).
      for (final raw in ['StateError', 'Bad state', 'the local write failed']) {
        expect(find.textContaining(raw), findsNothing, reason: raw);
      }
      expect(await count('expenses'), 0);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-expense')))
            .onPressed,
        isNotNull,
        reason: 'Save is offered again',
      );

      await tester.tap(find.byKey(const Key('save-expense')));
      await tester.pumpAndSettle();

      expect(saves, hasLength(2), reason: 'the retry reached the controller');
      expect(await popped, saves.last);
      expect(await count('expenses'), 1);
      expect(await count('sync_outbox'), 1);
    });
  });
}

/// The real controller, counting every save that reaches it, and optionally failing the
/// first one to prove the in-flight guard is released rather than latched (D-326).
class _CountingExpenseController extends ExpenseEntryController {
  _CountingExpenseController(super.ref, this.saves, {this.failFirst = false});

  final List<String> saves;
  final bool failFirst;

  @override
  Future<SaveOutcome> save(
    ExpenseDraft draft, {
    required MasterGraph graph,
    required Principal principal,
  }) {
    saves.add(draft.id);
    if (failFirst && saves.length == 1) {
      return Future.error(StateError('the local write failed'));
    }
    return super.save(draft, graph: graph, principal: principal);
  }
}

/// An authority snapshot carrying exactly the grants of [principal].
AuthoritySnapshot authorityFor(Principal principal) => AuthoritySnapshot(
  userId: principal.userId,
  orgId: seedOrgId,
  resolvedAt: DateTime.utc(2026, 6, 15),
  grants: principal.grants,
);
