/// The edit surface, as a user meets it (D-072).
///
/// The security rule under test is the project lead's, and it is narrow enough to state
/// in one line: **a scoped share of a shared expense is read-only in V1.** A Crystal
/// Canopy manager looking at `Your allocation ₹25,000` of a ₹58,000 invoice gets no Edit
/// control, and is told why rather than left to wonder whether something is broken.
///
/// The other half is ordinary: Edit is offered when the person may edit and the document
/// can be edited, and it is absent — not present-and-then-refused — when either is false.
/// Predicting eligibility here is what lets the interface be honest; the server re-decides
/// it and its answer is final (D-037).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/expense_detail_panel.dart';
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late ExpenseRepository repository;

  // Today, for the edit window. The fixtures are dated 15 June 2026, so "today" is set
  // close to them: the window is a real rule and a document three months old is outside
  // it for reasons that have nothing to do with what these tests are about.
  final today = BusinessDate.of(2026, 6, 16);
  final now = DateTime.utc(2026, 6, 16, 9);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await seedMasterData(db, now: now);
    repository = ExpenseRepository(db);
  });

  tearDown(() => db.close());

  Principal principalWith(
    Set<Capability> capabilities, {
    Set<String>? units,
    String userId = 'user-1',
  }) => Principal(
    userId: userId,
    grants: [
      for (final capability in capabilities)
        if (units == null)
          CapabilityGrant(capability)
        else
          for (final unit in units)
            CapabilityGrant(capability, businessUnitId: unit),
    ],
  );

  /// A document already accepted by the server, which is where every edit starts.
  Future<LocalExpense> accepted(ExpenseDocument expense) async {
    final mutationId = const Uuid().v4();
    await repository.createLocally(
      expense,
      actorUserId: 'user-1',
      mutationId: mutationId,
      now: now,
    );
    await repository.reconcileAcceptance(
      ExpenseAcceptance(
        expenseId: expense.id,
        txnNumber: 'KI-EXP-26-27-000011',
        financialYear: 2026,
        rowVersion: 2,
        serverUpdatedAt: now,
      ),
    );
    await db.customStatement(
      "UPDATE sync_outbox SET status = 'done' WHERE mutation_id = ?",
      [mutationId],
    );
    return (await repository.load(expense.id))!;
  }

  /// A surface tall enough to build the whole panel.
  ///
  /// The detail panel is a `ListView`, so off-screen children are never built. On a
  /// default 800x600 surface the action row sits below the fold and
  /// `findsNothing` would pass for every control in this file — including the ones that
  /// are supposed to be there. A negative assertion that cannot fail is not a test, so
  /// the viewport is made big enough that absence means absence.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> showDetail(
    WidgetTester tester,
    LocalExpense expense,
    Principal principal,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          principalProvider.overrideWithValue(principal),
          currentBusinessDateProvider.overrideWithValue(today),
        ],
        child: MaterialApp(
          home: Scaffold(body: ExpenseDetailPanel(expenseId: expense.row.id)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a scoped share of a shared expense is read-only', () {
    /// The Crystal Canopy manager's projection of the ₹58,000 bill.
    Future<LocalExpense> scopedShare() async {
      final bill = sharedExpense();
      await accepted(bill);
      await db.customStatement(
        "UPDATE expenses SET visibility = 'scoped', document_total_minor = NULL, "
        'visible_amount_minor = 2500000',
      );
      await db.customStatement(
        'DELETE FROM expense_period_allocations WHERE business_unit_id = ?',
        [hkiId],
      );
      await db.customStatement(
        'DELETE FROM expense_allocations WHERE business_unit_id = ?',
        [hkiId],
      );
      return (await repository.load(bill.id))!;
    }

    testWidgets('no Edit control, even with the edit capability', (
      tester,
    ) async {
      final scoped = await scopedShare();
      await showDetail(
        tester,
        scoped,
        principalWith(
          {Capability.expenseEditOwn, Capability.expenseViewAll},
          units: {ccrId},
        ),
      );

      expect(
        find.byKey(const Key('edit-expense')),
        findsNothing,
        reason:
            'holding expense.edit.own is not enough: this user cannot reconcile a '
            'document whose total they are not entitled to see',
      );
    });

    testWidgets('and says why, rather than leaving a gap', (tester) async {
      final scoped = await scopedShare();
      await showDetail(
        tester,
        scoped,
        principalWith(
          {Capability.expenseEditOwn, Capability.expenseViewAll},
          units: {ccrId},
        ),
      );

      expect(find.byKey(const Key('scoped-readonly-note')), findsOneWidget);
      expect(
        find.textContaining('allocation from a shared expense'),
        findsOneWidget,
      );
    });

    testWidgets('the withheld total is nowhere on the screen', (tester) async {
      final scoped = await scopedShare();
      await showDetail(
        tester,
        scoped,
        principalWith(
          {Capability.expenseEditOwn, Capability.expenseViewAll},
          units: {ccrId},
        ),
      );

      // The share is shown; the invoice and the other property's share are not, and the
      // caption never calls ₹25,000 a total (D-062).
      expect(find.textContaining('25,000'), findsWidgets);
      expect(find.textContaining('58,000'), findsNothing);
      expect(find.textContaining('33,000'), findsNothing);
    });
  });

  group('a complete document is editable by someone who may edit it', () {
    testWidgets('Edit is offered', (tester) async {
      final expense = await accepted(simpleExpense());
      await showDetail(
        tester,
        expense,
        principalWith(
          {Capability.expenseEditOwn, Capability.expenseViewAll},
          units: {ccrId},
        ),
      );

      expect(find.byKey(const Key('edit-expense')), findsOneWidget);
      expect(find.text('Edit expense'), findsOneWidget);
    });

    testWidgets(
      'a document wholly inside one property is complete for its manager',
      (tester) async {
        // "Complete" is about what this device was given, not about how many properties
        // the invoice charges. A ₹200 Crystal Canopy expense is the whole document.
        final expense = await accepted(simpleExpense());
        expect(expense.isScoped, isFalse);
        expect(expense.documentTotal, Money.fromRupees(200));

        await showDetail(
          tester,
          expense,
          principalWith(
            {Capability.expenseEditOwn, Capability.expenseViewAll},
            units: {ccrId},
          ),
        );
        expect(find.byKey(const Key('edit-expense')), findsOneWidget);
      },
    );

    testWidgets('without the capability there is no Edit control', (
      tester,
    ) async {
      final expense = await accepted(simpleExpense());
      await showDetail(
        tester,
        expense,
        principalWith({Capability.expenseViewAll}, units: {ccrId}),
      );

      expect(
        find.byKey(const Key('edit-expense')),
        findsNothing,
        reason: 'the control is absent, not present and then refused',
      );
      expect(
        find.byKey(const Key('scoped-readonly-note')),
        findsNothing,
        reason:
            'and the scoped explanation is not shown for a capability problem — it '
            'would be the wrong reason',
      );
    });

    testWidgets('outside the edit window there is no Edit control', (
      tester,
    ) async {
      final expense = await accepted(simpleExpense());
      useTallSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            principalProvider.overrideWithValue(
              principalWith(
                {Capability.expenseEditOwn, Capability.expenseViewAll},
                units: {ccrId},
              ),
            ),
            // D+8. The document is dated 15 June; this is the 23rd.
            currentBusinessDateProvider.overrideWithValue(
              BusinessDate.of(2026, 6, 23),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: ExpenseDetailPanel(expenseId: expense.row.id)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit-expense')), findsNothing);
    });

    testWidgets('a holder of the beyond-window capability keeps it', (
      tester,
    ) async {
      final expense = await accepted(simpleExpense());
      useTallSurface(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            principalProvider.overrideWithValue(
              principalWith(
                {
                  Capability.expenseEditAll,
                  Capability.expenseViewAll,
                  Capability.correctBeyondWindow,
                },
                units: {ccrId},
              ),
            ),
            currentBusinessDateProvider.overrideWithValue(
              BusinessDate.of(2026, 6, 23),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: ExpenseDetailPanel(expenseId: expense.row.id)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('edit-expense')),
        findsOneWidget,
        reason:
            'the beyond-window capability lifts the age rule, and nothing else '
            '(D-065)',
      );
    });
  });

  group('a voided document is immutable, and says so', () {
    testWidgets('no Edit and no Void, only the note', (tester) async {
      final expense = await accepted(simpleExpense());
      await repository.voidLocally(
        expense,
        reason: 'recorded twice',
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      final voided = (await repository.load(expense.row.id))!;

      await showDetail(
        tester,
        voided,
        principalWith(
          {
            Capability.expenseEditAll,
            Capability.expenseVoid,
            Capability.expenseViewAll,
          },
          units: {ccrId},
        ),
      );

      expect(find.byKey(const Key('edit-expense')), findsNothing);
      expect(find.byKey(const Key('void-expense')), findsNothing);
      expect(find.byKey(const Key('voided-immutable-note')), findsOneWidget);
    });
  });
}
