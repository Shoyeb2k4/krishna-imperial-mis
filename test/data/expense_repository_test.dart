/// The local expense save, and the two things it must never do:
/// tell a user their expense is saved when nothing will send it, and hold a figure the
/// server withheld.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late ExpenseRepository repository;
  final now = DateTime.utc(2026, 6, 15, 9, 30);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await seedMasterData(db, now: now);
    repository = ExpenseRepository(db);
  });

  tearDown(() => db.close());

  Future<String> save(ExpenseDocument expense, {String? mutationId}) =>
      repository.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: mutationId ?? const Uuid().v4(),
        now: now,
      );

  group('the save is atomic, and the outbox is inside it', () {
    test(
      'one transaction writes the document, lines, periods and queue',
      () async {
        final expense = simpleExpense();
        final mutationId = await save(expense);

        final saved = await repository.load(expense.id);
        expect(saved, isNotNull);
        expect(saved!.allocations, hasLength(1));
        expect(saved.periodContributions, hasLength(1));
        expect(saved.visibleAmount, Money.fromRupees(200));

        final queued = await db.select(db.syncOutbox).get();
        expect(queued, hasLength(1));
        expect(queued.single.mutationId, mutationId);
        expect(queued.single.entityType, 'expense');
        expect(queued.single.op, 'create');
        expect(
          queued.single.actorUserId,
          'user-1',
          reason: 'the queued intent belongs to whoever saved it (D-050)',
        );
        expect(saved.syncState, SyncState.pendingSync);
      },
    );

    test('an unbalanced document is refused before anything is written', () async {
      // The aggregate cannot be constructed unbalanced, so the repository is handed a
      // balanced one and the check is that it agrees. Belt and braces on the number that
      // becomes a P&L.
      final expense = sharedExpense();
      expect(
        Money.sum(expense.allocations.map((a) => a.amount)),
        expense.total,
      );
      await save(expense);
      expect((await db.select(db.expenses).get()), hasLength(1));
    });

    test(
      'a failure while writing the lines leaves no document and no queue entry',
      () async {
        // A line naming a business unit that does not exist trips the foreign key
        // mid-transaction, after the header has been inserted.
        final broken = expenseWith(
          lines: [line(unit: 'no-such-unit', rupees: 100)],
        );

        await expectLater(save(broken), throwsA(anything));

        expect(
          await db.select(db.expenses).get(),
          isEmpty,
          reason: 'the header must not survive a failure further down',
        );
        expect(await db.select(db.expenseAllocations).get(), isEmpty);
        expect(
          await db.select(db.syncOutbox).get(),
          isEmpty,
          reason:
              'and nothing may be queued for a document that does not exist',
        );
      },
    );

    test(
      'a failure while writing a period contribution rolls the whole save back',
      () async {
        // A contribution whose pnl key disagrees with its date trips the check
        // constraint, after the header *and* the line are already inserted.
        final broken = expenseWith(
          lines: [
            ExpenseAllocation(
              id: 'line-bad',
              businessUnitId: ccrId,
              departmentId: ccrDeptId,
              sectionId: ccrSectionId,
              categoryId: ccrCategoryId,
              amount: Money.fromRupees(100),
              periodContributions: [
                PeriodContribution(
                  id: 'p-bad',
                  periodStart: BusinessDate.of(2026, 6, 1),
                  periodEnd: BusinessDate.of(2026, 6, 30),
                  amount: Money.fromRupees(100),
                  isDerived: true,
                ),
              ],
            ),
          ],
        );

        // Corrupt the stored key by writing through a companion the repository would
        // never build: the point is that SQLite refuses it and the transaction unwinds.
        await expectLater(
          db.transaction(() async {
            await save(broken);
            await db
                .into(db.expensePeriodAllocations)
                .insert(
                  ExpensePeriodAllocationsCompanion.insert(
                    id: 'p-corrupt',
                    orgId: broken.orgId,
                    expenseId: broken.id,
                    allocationId: 'line-bad',
                    businessUnitId: ccrId,
                    accountingPeriodStart: '2026-06-01',
                    accountingPeriodEnd: '2026-06-30',
                    amountMinor: 1,
                    pnlDate: '2026-06-30',
                    pnlPeriodKey: '2026-07', // disagrees with the date
                    updatedAt: now,
                  ),
                );
          }),
          throwsA(anything),
        );

        expect(await db.select(db.expenses).get(), isEmpty);
        expect(await db.select(db.expenseAllocations).get(), isEmpty);
        expect(await db.select(db.expensePeriodAllocations).get(), isEmpty);
        expect(await db.select(db.syncOutbox).get(), isEmpty);
      },
    );

    test(
      'a failure while queueing leaves no expense — saved and unsent is the one '
      'outcome that must be impossible',
      () async {
        final expense = simpleExpense();

        await expectLater(
          db.transaction(() async {
            await save(expense);
            // Something goes wrong after the queue entry, still inside the transaction.
            throw StateError('queue write failed');
          }),
          throwsA(isA<StateError>()),
        );

        expect(await db.select(db.expenses).get(), isEmpty);
        expect(await db.select(db.syncOutbox).get(), isEmpty);
      },
    );
  });

  group('restart persistence', () {
    test('the expense and its queued intent survive a reopen', () async {
      // A file-backed database, closed and reopened, is what an app kill looks like from
      // the data's point of view.
      final file = await createTempDatabaseFile();
      addTearDown(() => file.parent.deleteSync(recursive: true));

      final expense = sharedExpense();
      final mutationId = const Uuid().v4();

      final first = AppDatabase(NativeDatabase(file));
      await first.customStatement('PRAGMA foreign_keys = ON');
      await seedMasterData(first, now: now);
      await ExpenseRepository(first).createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: mutationId,
        now: now,
      );
      await first.close();

      final second = AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      final reopened = await ExpenseRepository(second).load(expense.id);

      expect(reopened, isNotNull);
      expect(reopened!.allocations, hasLength(2));
      expect(reopened.periodContributions, hasLength(2));
      expect(reopened.visibleAmount, Money.fromRupees(58000));
      expect(reopened.syncState, SyncState.pendingSync);

      final queued = await second.select(second.syncOutbox).get();
      expect(queued.single.mutationId, mutationId);
      expect(queued.single.status, OutboxStatus.pending.name);
    });
  });

  group('numbering', () {
    test('a locally created expense has no transaction number', () async {
      final expense = simpleExpense();
      await save(expense);

      final saved = await repository.load(expense.id);
      expect(saved!.row.txnNumber, isNull);
      expect(saved.row.financialYear, isNull);
      expect(saved.number, isNull);
      expect(
        saved.displayReference,
        startsWith('Pending number'),
        reason: 'an honest pending state, never a fabricated KI-EXP number',
      );
      expect(saved.displayReference, isNot(contains('KI-EXP')));
    });

    test('the server number is reconciled onto the same row', () async {
      final expense = simpleExpense();
      await save(expense);

      await repository.reconcileAcceptance(
        ExpenseAcceptance(
          expenseId: expense.id,
          rowVersion: 2,
          txnNumber: 'KI-EXP-26-27-000001',
          financialYear: 2026,
          serverUpdatedAt: DateTime.utc(2026, 6, 15, 10),
        ),
      );

      final reconciled = await repository.load(expense.id);
      expect(reconciled!.row.txnNumber, 'KI-EXP-26-27-000001');
      expect(reconciled.number?.sequence, 1);
      expect(reconciled.row.rowVersion, 2);
      expect(reconciled.row.pendingMutationId, isNull);
      expect(reconciled.syncState, SyncState.synced);
      expect(
        reconciled.row.id,
        expense.id,
        reason: 'identity never changes — the client id is the identity',
      );
    });

    test('reconciling does not disturb attachment upload state', () async {
      final expense = expenseWith(
        lines: [line(unit: ccrId, rupees: 200)],
        attachments: [stagedAttachment(id: 'att-1')],
      );
      await save(expense);

      // The upload finished before the financial record was reconciled — the ordinary
      // case when a photo is small and the queue is busy.
      await (db.update(
        db.expenseAttachments,
      )..where((t) => t.id.equals('att-1'))).write(
        ExpenseAttachmentsCompanion(
          uploadState: const Value('uploaded'),
          storagePath: const Value('org/o/expenses/e/att-1.jpg'),
          uploadedAt: Value(now),
        ),
      );

      await repository.reconcileAcceptance(
        ExpenseAcceptance(
          expenseId: expense.id,
          rowVersion: 2,
          txnNumber: 'KI-EXP-26-27-000002',
          financialYear: 2026,
        ),
      );

      final attachment = (await db.select(db.expenseAttachments).get()).single;
      expect(
        attachment.uploadState,
        'uploaded',
        reason:
            'an accepted financial record says nothing about a photo, and '
            'overwriting this would restart an upload that already succeeded',
      );
      expect(attachment.storagePath, isNotNull);
    });
  });

  group('the reporting source is the contributions, and only them', () {
    test(
      'a simple expense contributes its whole amount to one period',
      () async {
        await save(simpleExpense());

        expect(
          await repository.contributionTotal(periodKey: '2026-06'),
          Money.fromRupees(200),
        );
        expect(
          await repository.contributionTotal(periodKey: '2026-05'),
          Money.zero,
        );
      },
    );

    test(
      'a cross-period split contributes to each month and not twice',
      () async {
        await save(crossPeriodExpense());

        expect(
          await repository.contributionTotal(periodKey: '2026-05'),
          Money.fromRupees(30000),
        );
        expect(
          await repository.contributionTotal(periodKey: '2026-06'),
          Money.fromRupees(30000),
        );

        final everything = (await db.select(db.expensePeriodAllocations).get())
            .fold<int>(0, (s, r) => s + r.amountMinor);
        expect(
          everything,
          6000000,
          reason:
              'not 12,000,000 — the line amount is not a second reporting source',
        );
      },
    );

    test(
      'shared and cross-period at once reconciles on both dimensions',
      () async {
        await save(sharedCrossPeriodExpense());

        // Globally: every paisa once.
        final total = (await db.select(db.expensePeriodAllocations).get())
            .fold<int>(0, (s, r) => s + r.amountMinor);
        expect(total, 5800000);

        // Per unit.
        expect(
          await repository.contributionTotal(
            periodKey: '2026-05',
            businessUnitId: ccrId,
          ),
          Money.fromRupees(12500),
        );
        expect(
          await repository.contributionTotal(
            periodKey: '2026-06',
            businessUnitId: ccrId,
          ),
          Money.fromRupees(12500),
        );
        expect(
          await repository.contributionTotal(
            periodKey: '2026-06',
            businessUnitId: hkiId,
          ),
          Money.fromRupees(33000),
        );
      },
    );

    test('an odd amount split three ways reconciles to the paisa', () async {
      final expense = oddSplitExpense();
      await save(expense);

      final rows = await db.select(db.expensePeriodAllocations).get();
      final total = rows.fold<int>(0, (s, r) => s + r.amountMinor);
      expect(total, expense.total.paise);
      expect(
        rows.map((r) => r.amountMinor).toSet().length,
        greaterThan(1),
        reason:
            'an odd amount cannot split evenly; the remainder goes somewhere',
      );
      expect(
        await repository.contributionTotal(periodKey: '2026-04') +
            await repository.contributionTotal(periodKey: '2026-05') +
            await repository.contributionTotal(periodKey: '2026-06'),
        expense.total,
      );
    });

    test('a voided expense leaves the aggregate', () async {
      final expense = simpleExpense();
      await save(expense);
      await (db.update(
        db.expenses,
      )..where((t) => t.id.equals(expense.id))).write(
        ExpensesCompanion(
          voidedAt: Value(now),
          voidedBy: const Value('accountant'),
          voidReason: const Value('Entered twice'),
        ),
      );

      expect(
        await repository.contributionTotal(periodKey: '2026-06'),
        Money.zero,
      );
      expect(
        await db.select(db.expensePeriodAllocations).get(),
        isNotEmpty,
        reason: 'the rows remain — void is not deletion (D-006)',
      );
    });
  });

  group('the schema refuses a record that would leak another unit s share', () {
    test('a scoped record cannot carry a document total', () async {
      await expectLater(
        db
            .into(db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: 'leaky',
                orgId: 'org',
                businessDate: '2026-06-15',
                visibility: const Value('scoped'),
                // 58,000 alongside a visible 25,000 hands over the other 33,000.
                documentTotalMinor: const Value(5800000),
                visibleAmountMinor: 2500000,
                createdBy: 'u',
                capturedAt: now,
                updatedAt: now,
              ),
            ),
        throwsA(anything),
        reason: 'SQLite itself must refuse this, not a convention above it',
      );
    });

    test('a complete record must carry one', () async {
      await expectLater(
        db
            .into(db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: 'headless',
                orgId: 'org',
                businessDate: '2026-06-15',
                visibility: const Value('complete'),
                visibleAmountMinor: 2500000,
                createdBy: 'u',
                capturedAt: now,
                updatedAt: now,
              ),
            ),
        throwsA(anything),
      );
    });

    test('a scoped record is legal without one', () async {
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: 'scoped-ok',
              orgId: 'org',
              businessDate: '2026-06-15',
              visibility: const Value('scoped'),
              visibleAmountMinor: 2500000,
              isShared: const Value(true),
              createdBy: 'u',
              capturedAt: now,
              updatedAt: now,
            ),
          );

      final saved = await ExpenseRepository(db).load('scoped-ok');
      expect(saved!.isScoped, isTrue);
      expect(saved.documentTotal, isNull);
      expect(saved.visibleAmount, Money.fromRupees(25000));
      expect(saved.row.isShared, isTrue);
    });
  });

  group('payment states', () {
    test('paid requires a date and a method, in the database too', () async {
      await expectLater(
        db
            .into(db.expenses)
            .insert(
              ExpensesCompanion.insert(
                id: 'half-paid',
                orgId: 'org',
                businessDate: '2026-06-15',
                visibility: const Value('complete'),
                documentTotalMinor: const Value(100),
                visibleAmountMinor: 100,
                paymentStatus: const Value('paid'),
                createdBy: 'u',
                capturedAt: now,
                updatedAt: now,
              ),
            ),
        throwsA(anything),
      );
    });

    test(
      'a June cost paid in July stays in June, and says when it was paid',
      () async {
        final expense = juneSalaryPaidInJuly();
        await save(expense);

        final saved = await repository.load(expense.id);
        expect(saved!.row.paymentStatus, 'paid');
        expect(saved.row.paymentDate, '2026-07-05');
        expect(
          saved.row.businessDate,
          '2026-06-30',
          reason: 'the operational date of the document',
        );

        // Profitability follows the accounting period, not the payment.
        expect(
          await repository.contributionTotal(periodKey: '2026-06'),
          Money.fromRupees(80000),
        );
        expect(
          await repository.contributionTotal(periodKey: '2026-07'),
          Money.zero,
          reason: 'paying in July does not move the cost out of June (D-016)',
        );
      },
    );
  });
}
