/// D-072 — the expense edit path, which until now did not exist on the client at all.
///
/// The server's `expense_update` has been implemented and proven against the real
/// backend since Phase 3 began; what was missing was any way for a user to reach it. This
/// suite covers the half that was missing, and it is written around the three things that
/// make an edit different from a create:
///
///  1. **It is atomic with its queue entry.** A local row that says "edited" beside an
///     outbox that never got the intent is a record the user believes is on its way and
///     is not.
///  2. **It carries the version the user saw**, not the version the row happens to hold
///     when Save is pressed. That difference is the entire conflict mechanism (D-021).
///  3. **It is complete-documents only.** A scoped share is read-only in V1, and the
///     refusal lives at the write, not only at the button.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_draft.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_edit_loader.dart';
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late ExpenseRepository repository;

  /// The canonical expense reporting total for a period (D-168).
  ///
  /// Only server-accepted documents contribute, so a fixture that stays local contributes
  /// nothing — which is the correction Slice 1 made and the reason these tests now accept
  /// their expenses before asserting a figure.
  Future<Money> contributionsOf(
    String periodKey, {
    String? businessUnitId,
  }) async => (await repository.contributionTotals(
    ExpenseContributionQuery(
      periodKey: periodKey,
      businessUnitId: businessUnitId,
    ),
  )).amount;

  final now = DateTime.utc(2026, 6, 15, 9, 30);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await seedMasterData(db, now: now);
    repository = ExpenseRepository(db);
  });

  tearDown(() => db.close());

  /// Saves a document and marks it accepted at [rowVersion], which is the state every
  /// edit starts from: on the server, numbered, with a version to base an intent on.
  Future<LocalExpense> accepted(
    ExpenseDocument expense, {
    int rowVersion = 3,
  }) async {
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
        txnNumber: 'KI-EXP-26-27-000007',
        financialYear: 2026,
        rowVersion: rowVersion,
        serverUpdatedAt: now,
      ),
    );
    await db.customStatement(
      "UPDATE sync_outbox SET status = 'done' WHERE mutation_id = ?",
      [mutationId],
    );
    return (await repository.load(expense.id))!;
  }

  /// The edited document: same identity, a different figure.
  ExpenseDocument edited(
    LocalExpense from, {
    required int rupees,
    String? notes,
    String? reference,
  }) {
    final draft = (draftFor(from) as EditableDraftReady).draft;
    final withAmount = draft
        .withTotal(Money.fromRupees(rupees))
        .copyWith(notes: notes, referenceNumber: reference);
    return withAmount.toDocument(
      orgId: from.row.orgId,
      createdByUserId: from.row.createdBy,
      capturedAt: from.row.capturedAt,
      labelFor: (_) => 'Kirana & Pulses',
    );
  }

  group('the edit is atomic with the intent that will deliver it', () {
    test('one transaction writes the document and queues the update', () async {
      final original = await accepted(simpleExpense());
      final mutationId = const Uuid().v4();

      await repository.updateLocally(
        edited(original, rupees: 750, reference: 'INV-9'),
        actorUserId: 'user-1',
        mutationId: mutationId,
        baseRowVersion: original.row.rowVersion,
        now: now,
      );

      final saved = await repository.load(original.row.id);
      expect(saved!.documentTotal, Money.fromRupees(750));
      expect(saved.visibleAmount, Money.fromRupees(750));
      expect(saved.row.referenceNumber, 'INV-9');
      expect(
        saved.row.id,
        original.row.id,
        reason: 'an edit corrects a document; it does not create another one',
      );
      expect(
        saved.row.txnNumber,
        'KI-EXP-26-27-000007',
        reason: 'the number is the server s and does not move',
      );

      final queued = await db.select(db.syncOutbox).get();
      final intent = queued.singleWhere((q) => q.mutationId == mutationId);
      expect(intent.op, MutationOp.update.name);
      expect(intent.entityType, 'expense');
      expect(intent.entityId, original.row.id);
      expect(intent.actorUserId, 'user-1');
      expect(intent.status, OutboxStatus.pending.name);
      expect(saved.syncState, SyncState.pendingSync);
    });

    test('exactly one expense row exists afterwards', () async {
      final original = await accepted(simpleExpense());
      await repository.updateLocally(
        edited(original, rupees: 750),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        baseRowVersion: original.row.rowVersion,
        now: now,
      );
      expect(await db.select(db.expenses).get(), hasLength(1));
    });

    test('a failure part way leaves the document exactly as it was', () async {
      final original = await accepted(sharedExpense());

      // Two lines sharing one primary key: the second insert is refused after the header
      // has already been rewritten and the first line inserted, which is precisely the
      // half-applied state this test exists to prove cannot survive.
      final broken = ExpenseDocument(
        id: original.row.id,
        orgId: original.row.orgId,
        businessDate: june15,
        businessDateSource: BusinessDateSource.derived,
        total: Money.fromRupees(400),
        allocations: [
          line(unit: ccrId, rupees: 200, id: 'duplicate'),
          line(unit: ccrId, rupees: 200, id: 'duplicate'),
        ],
        paymentStatus: PaymentStatus.unpaid,
        createdByUserId: 'user-1',
        capturedAt: now,
      );

      await expectLater(
        repository.updateLocally(
          broken,
          actorUserId: 'user-1',
          mutationId: const Uuid().v4(),
          baseRowVersion: original.row.rowVersion,
          now: now,
        ),
        throwsA(anything),
      );

      final after = await repository.load(original.row.id);
      expect(after!.documentTotal, Money.fromRupees(58000));
      expect(after.allocations, hasLength(2));
      expect(
        after.row.pendingMutationId,
        isNull,
        reason: 'no intent was queued, so nothing may claim to be pending',
      );
      expect(await db.select(db.syncOutbox).get(), hasLength(1));
    });
  });

  group('the version an edit carries is the one the user saw', () {
    test('the base version comes from the caller, not from the row', () async {
      final original = await accepted(simpleExpense(), rowVersion: 3);

      // A background pull advances the local row while the form is open. The intent must
      // still be judged against version 3, which is what the person was looking at.
      await db.customStatement('UPDATE expenses SET row_version = 9');

      final mutationId = const Uuid().v4();
      await repository.updateLocally(
        edited(original, rupees: 750),
        actorUserId: 'user-1',
        mutationId: mutationId,
        baseRowVersion: original.row.rowVersion,
        now: now,
      );

      final intent = (await db.select(db.syncOutbox).get()).singleWhere(
        (q) => q.mutationId == mutationId,
      );
      expect(
        intent.baseRowVersion,
        3,
        reason:
            'auto-rebasing to 9 here is exactly how one person silently overwrites an '
            'edit they never saw (D-021)',
      );
    });

    test('the draft refuses to re-base itself through copyWith', () {
      final draft = ExpenseDraft.fromExisting(
        id: 'e1',
        rowVersion: 4,
        businessDate: june15,
        total: Money.fromRupees(100),
        allocations: const [],
      );
      expect(draft.baseRowVersion, 4);
      expect(draft.isEdit, isTrue);
      expect(
        draft.copyWith(notes: 'typing').baseRowVersion,
        4,
        reason:
            'every keystroke rebuilds the draft; none of them may move the version',
      );
    });
  });

  group('a scoped share is read-only', () {
    /// The Crystal Canopy manager's view of the ₹58,000 bill: their ₹25,000, no total.
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

    test('the loader refuses it, and says why in the user s words', () async {
      final scoped = await scopedShare();
      expect(scoped.isScoped, isTrue);

      final outcome = draftFor(scoped);
      expect(outcome, isA<EditableDraftRefused>());
      expect(
        (outcome as EditableDraftRefused).reason,
        EditRefusal.scopedProjection,
      );
      expect(outcome.draftOrNull, isNull);
      expect(
        outcome.reason.message,
        contains('allocation from a shared expense'),
      );
    });

    test('nothing reconstructs the withheld total on the way past', () async {
      final scoped = await scopedShare();
      expect(scoped.documentTotal, isNull);
      expect(scoped.visibleAmount, Money.fromRupees(25000));
      // The refusal is the point, but so is what is *not* on the device: the loader
      // cannot produce a total because there is none to produce.
      expect(
        (await db.select(db.expenses).getSingle()).documentTotalMinor,
        isNull,
      );
    });

    test('the write refuses it too, not only the button', () async {
      final scoped = await scopedShare();
      // A modified client, or a future caller who skipped the loader.
      final forged = ExpenseDocument(
        id: scoped.row.id,
        orgId: scoped.row.orgId,
        businessDate: june15,
        businessDateSource: BusinessDateSource.derived,
        total: Money.fromRupees(25000),
        allocations: [line(unit: ccrId, rupees: 25000, id: 'ccr-line')],
        paymentStatus: PaymentStatus.unpaid,
        createdByUserId: 'user-1',
        capturedAt: now,
      );

      await expectLater(
        repository.updateLocally(
          forged,
          actorUserId: 'user-1',
          mutationId: const Uuid().v4(),
          baseRowVersion: scoped.row.rowVersion,
          now: now,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await db.select(db.syncOutbox).get(), hasLength(1));
    });
  });

  group('what the loader will and will not open', () {
    test('a voided document is immutable', () async {
      final original = await accepted(simpleExpense());
      await repository.voidLocally(
        original,
        reason: 'entered twice',
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      final voided = (await repository.load(original.row.id))!;
      expect(
        (draftFor(voided) as EditableDraftRefused).reason,
        EditRefusal.voided,
      );
    });

    test(
      'a document the server has not accepted has no version to edit from',
      () async {
        final expense = simpleExpense();
        await repository.createLocally(
          expense,
          actorUserId: 'user-1',
          mutationId: const Uuid().v4(),
          now: now,
        );
        final pending = (await repository.load(expense.id))!;
        expect(pending.row.txnNumber, isNull);
        expect(
          (draftFor(pending) as EditableDraftRefused).reason,
          EditRefusal.notYetSynced,
        );
      },
    );

    test('a complete document round-trips into the form that made it', () async {
      final original = await accepted(
        expenseWith(
          lines: [line(unit: ccrId, rupees: 1200)],
          payment: PaymentStatus.paid,
          paymentDate: BusinessDate.of(2026, 7, 5),
          paymentMethodId: seedId('pm:CASH'),
        ),
      );

      final draft = (draftFor(original) as EditableDraftReady).draft;
      expect(draft.id, original.row.id);
      expect(draft.baseRowVersion, original.row.rowVersion);
      expect(draft.txnNumber, 'KI-EXP-26-27-000007');
      expect(draft.total, Money.fromRupees(1200));
      expect(draft.allocations, hasLength(1));
      expect(draft.allocations.single.amount, Money.fromRupees(1200));
      expect(draft.paymentStatus, PaymentStatus.paid);
      expect(draft.paymentDate, BusinessDate.of(2026, 7, 5));
      expect(draft.businessDate, june15);
      expect(
        draft.isSplit,
        isFalse,
        reason:
            'a one-line expense with no deliberate split opens as a simple one',
      );
    });

    test(
      'a derived contribution is not loaded as a split somebody chose',
      () async {
        // Every line has at least one contribution (D-060). Loading the derived one into
        // the split editor would show a split nobody made — and saving would then send it
        // as deliberate, permanently changing what the document claims.
        final original = await accepted(simpleExpense());
        expect(original.periodContributions.single.isDerived, isTrue);

        final draft = (draftFor(original) as EditableDraftReady).draft;
        expect(draft.allocations.single.periodSplits, isEmpty);
        expect(draft.allocations.single.hasPeriodSplit, isFalse);
        expect(draft.isSplit, isFalse);
      },
    );

    test('a deliberate split is loaded, and opens in the split view', () async {
      final original = await accepted(crossPeriodExpense());
      expect(original.periodContributions.every((c) => !c.isDerived), isTrue);

      final draft = (draftFor(original) as EditableDraftReady).draft;
      expect(
        draft.isSplit,
        isTrue,
        reason: 'the editor that hosts the rows must build',
      );
      final splits = draft.allocations.single.periodSplits;
      expect(splits, hasLength(2));
      expect(splits.first.end.iso, '2026-05-31');
      expect(splits.last.end.iso, '2026-06-14');
      expect(
        splits.fold(Money.zero, (t, s) => t + s.amount!),
        draft.allocations.single.amount,
        reason: 'the loaded split still reconciles to its line',
      );
    });

    test('a shared document keeps both lines and opens split', () async {
      final original = await accepted(sharedExpense());
      final draft = (draftFor(original) as EditableDraftReady).draft;

      expect(draft.isSplit, isTrue);
      expect(draft.allocations, hasLength(2));
      expect(draft.total, Money.fromRupees(58000));
      expect(draft.reconciles, isTrue);
    });
  });

  group('editing metadata does not move the money', () {
    test('marking a June expense paid in July keeps it a June cost', () async {
      final original = await accepted(
        expenseWith(
          lines: [line(unit: ccrId, rupees: 80000)],
          businessDate: BusinessDate.of(2026, 6, 30),
        ),
      );
      expect(original.periodContributions.single.pnlPeriodKey, '2026-06');

      final draft = (draftFor(original) as EditableDraftReady).draft.copyWith(
        paymentStatus: PaymentStatus.paid,
        paymentDate: BusinessDate.of(2026, 7, 5),
        paymentMethodId: seedId('pm:CASH'),
      );
      await repository.updateLocally(
        draft.toDocument(
          orgId: original.row.orgId,
          createdByUserId: original.row.createdBy,
          capturedAt: original.row.capturedAt,
          labelFor: (_) => 'Kirana & Pulses',
        ),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        baseRowVersion: original.row.rowVersion,
        now: now,
      );

      final saved = await repository.load(original.row.id);
      expect(saved!.row.paymentStatus, 'paid');
      expect(saved.row.paymentDate, '2026-07-05');
      expect(
        saved.periodContributions.single.pnlPeriodKey,
        '2026-06',
        reason:
            'a payment date is cash reporting; it never moves profitability',
      );
      expect(await contributionsOf('2026-07'), Money.zero);
      expect(await contributionsOf('2026-06'), Money.fromRupees(80000));
    });
  });

  group('the money still has to reconcile', () {
    test('an unbalanced edit cannot even be constructed', () async {
      // The strongest form of this guarantee is that the aggregate refuses: an
      // `ExpenseDocument` whose lines do not sum to its total does not exist, so no
      // repository, endpoint or screen can be handed one. The repository re-asserts it
      // anyway, because the cost is a comparison and the alternative is a financial
      // record nobody can explain.
      final original = await accepted(sharedExpense());
      expect(
        () => ExpenseDocument(
          id: original.row.id,
          orgId: original.row.orgId,
          businessDate: june15,
          businessDateSource: BusinessDateSource.derived,
          total: Money.fromRupees(58000),
          allocations: [line(unit: ccrId, rupees: 25000, id: 'ccr-line')],
          paymentStatus: PaymentStatus.unpaid,
          createdByUserId: 'user-1',
          capturedAt: now,
        ),
        throwsA(isA<ExpenseImbalance>()),
      );
      expect(
        (await repository.load(original.row.id))!.allocations,
        hasLength(2),
      );
    });

    test('the draft will not let a user save an unbalanced split', () async {
      // And the same rule as the user meets it: Save becomes unavailable, rather than
      // the save being attempted and refused afterwards.
      final original = await accepted(sharedExpense());
      final draft = (draftFor(original) as EditableDraftReady).draft;
      final unbalanced = draft.withAllocationAmount(
        draft.allocations.first.id,
        Money.fromRupees(20000),
      );
      expect(unbalanced.reconciles, isFalse);
      expect(unbalanced.remaining, Money.fromRupees(5000));
    });

    test('contributions are replaced, never accumulated', () async {
      // The failure this guards is a document that reports twice: old contribution rows
      // left beside new ones would double a period's cost with nothing looking wrong.
      final original = await accepted(crossPeriodExpense());
      expect(original.periodContributions, hasLength(2));

      final draft = (draftFor(original) as EditableDraftReady).draft;
      final flattened = draft
          .clearPeriodSplit(draft.allocations.single.id)
          .withTotal(Money.fromRupees(60000));

      await repository.updateLocally(
        flattened.toDocument(
          orgId: original.row.orgId,
          createdByUserId: original.row.createdBy,
          capturedAt: original.row.capturedAt,
          labelFor: (_) => 'Kirana & Pulses',
        ),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        baseRowVersion: original.row.rowVersion,
        now: now,
      );

      final saved = await repository.load(original.row.id);
      expect(saved!.periodContributions, hasLength(1));
      expect(saved.periodContributions.single.isDerived, isTrue);
      expect(
        saved.periodContributions.single.amountMinor,
        6000000,
        reason:
            'one contribution for the whole line, not three totalling 12,000,000',
      );
    });
  });

  group('reconciling an edit keeps what the server did not restate', () {
    test('an update response carries no number, and must not erase one', () async {
      // `expense_create` issues the transaction number and reports it. `expense_update`
      // returns only the new `row_version`, because a correction does not renumber a
      // document. Treating that silence as "set it to null" wiped the KI-EXP- number
      // locally and left the document reading Pending Sync for ever — found by the first
      // edit ever pushed from a client, because a create states everything and so could
      // never expose it.
      final original = await accepted(simpleExpense(), rowVersion: 3);
      expect(original.row.txnNumber, 'KI-EXP-26-27-000007');
      expect(original.row.financialYear, 2026);

      await repository.updateLocally(
        edited(original, rupees: 750),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        baseRowVersion: original.row.rowVersion,
        now: now,
      );

      // Exactly what `expense_update` answers with, and nothing more.
      final acceptance = ExpenseAcceptance.fromResult(original.row.id, const {
        'status': 'applied',
        'entity_type': 'expense',
        'entity_id': 'ignored',
        'row_version': 4,
      });
      expect(acceptance, isNotNull);
      expect(acceptance!.txnNumber, isNull);
      expect(acceptance.financialYear, isNull);

      await repository.reconcileAcceptance(acceptance);

      final settled = await repository.load(original.row.id);
      expect(
        settled!.row.txnNumber,
        'KI-EXP-26-27-000007',
        reason: 'the number the server issued is not the update s to take away',
      );
      expect(settled.row.financialYear, 2026);
      expect(settled.row.rowVersion, 4);
      expect(settled.row.pendingMutationId, isNull);
      expect(
        settled.syncState,
        SyncState.synced,
        reason:
            'an accepted edit reads as synced; it read as Pending Sync for ever while '
            'the number was being erased',
      );
    });

    test('a create response still writes the number it issues', () async {
      final expense = simpleExpense();
      await repository.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      expect((await repository.load(expense.id))!.row.txnNumber, isNull);

      await repository.reconcileAcceptance(
        ExpenseAcceptance.fromResult(expense.id, const {
          'row_version': 1,
          'txn_number': 'KI-EXP-26-27-000042',
          'financial_year': 2026,
        })!,
      );

      final saved = await repository.load(expense.id);
      expect(saved!.row.txnNumber, 'KI-EXP-26-27-000042');
      expect(saved.row.financialYear, 2026);
      expect(saved.syncState, SyncState.synced);
    });
  });

  group('attachments are evidence, not form state', () {
    test('an existing uploaded attachment survives an edit untouched', () async {
      final original = await accepted(simpleExpense());
      await db.customInsert(
        'INSERT INTO expense_attachments (id, org_id, expense_id, file_name, '
        'content_type, byte_size, content_hash, upload_state, storage_path, '
        'uploaded_at, attempt_count, uploaded_by, created_at, updated_at) '
        "VALUES ('att-1', ?, ?, 'bill.jpg', 'image/jpeg', 2048, 'hash-1', "
        "'uploaded', 'org/x/bill.jpg', ?, 0, 'user-1', ?, ?)",
        variables: [
          Variable<String>(original.row.orgId),
          Variable<String>(original.row.id),
          Variable<DateTime>(now),
          Variable<DateTime>(now),
          Variable<DateTime>(now),
        ],
      );

      final reloaded = (await repository.load(original.row.id))!;
      await repository.updateLocally(
        edited(reloaded, rupees: 900),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        baseRowVersion: reloaded.row.rowVersion,
        now: now,
      );

      final saved = await repository.load(original.row.id);
      expect(saved!.attachments, hasLength(1));
      expect(saved.attachments.single.id, 'att-1');
      expect(
        saved.attachments.single.uploadState,
        'uploaded',
        reason:
            'rewriting upload state here would restart an upload that had already '
            'succeeded, and V1 offers no destructive attachment removal at all',
      );
      expect(saved.attachments.single.storagePath, 'org/x/bill.jpg');
    });
  });
}
