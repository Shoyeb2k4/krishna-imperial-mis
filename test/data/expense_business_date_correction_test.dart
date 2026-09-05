/// The Phase 3 corrective, on the client side.
///
/// The financial-integrity half of this change lives in Postgres and is proven against
/// `krishna-mis-dev` — a closed month cannot be emptied by an edit, whoever asks. What is
/// covered here is the half a host suite can actually decide: that the client asks the
/// right question, carries the reason to the server, and does not offer a form whose
/// every outcome the server would refuse.
///
/// Two rules are structural rather than conventional, and both have their own test:
///
///  1. **Whether the date moved is measured against the date the form was loaded with**,
///     captured once at load and untouchable by `copyWith` — the same discipline
///     `baseRowVersion` has carried since D-072a, for the same reason. A field that could
///     move on every keystroke would stop calling an edit a correction halfway through
///     typing it.
///  2. **The reason travels in the outbox payload**, so an authorised correction queued
///     offline still carries it when it is delivered days later from a different process.
///     A reason held only in a widget's state is a reason that disappears on sync.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_draft.dart';
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late ExpenseRepository repository;
  final now = DateTime.utc(2026, 6, 15, 9, 30);
  final june16 = BusinessDate.of(2026, 6, 16);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await seedMasterData(db, now: now);
    repository = ExpenseRepository(db);
  });

  tearDown(() => db.close());

  Principal principalWith(Set<Capability> capabilities, {String? unit}) =>
      Principal(
        userId: 'user-1',
        grants: [
          for (final capability in capabilities)
            CapabilityGrant(capability, businessUnitId: unit),
        ],
      );

  /// A document the server has already accepted, which is where every edit starts.
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
        txnNumber: 'KI-EXP-26-27-000021',
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

  ExpenseDraft loadedDraft({BusinessDate? date}) => ExpenseDraft.fromExisting(
    id: 'e1',
    rowVersion: 4,
    businessDate: date ?? june15,
    total: Money.fromRupees(500),
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

  group('the date a correction is measured against is the one that was loaded', () {
    test('a new expense never counts as a correction, whatever date is chosen', () {
      final blank = ExpenseDraft.blank(businessDate: june15);
      expect(blank.originalBusinessDate, isNull);
      expect(blank.movesBusinessDate, isFalse);
      expect(
        blank
            .copyWith(businessDate: BusinessDate.of(2026, 1, 1))
            .movesBusinessDate,
        isFalse,
        reason:
            'recording an expense against a chosen date is `manual`, not `corrected` '
            '(D-019) — the correction rules govern moving a date that was recorded',
      );
    });

    test('an edit that leaves the date alone is not a correction', () {
      expect(loadedDraft().movesBusinessDate, isFalse);
      expect(
        loadedDraft().copyWith(notes: 'typing').movesBusinessDate,
        isFalse,
      );
    });

    test('an edit that moves the date is, and moving it back is not', () {
      final moved = loadedDraft().copyWith(businessDate: june16);
      expect(moved.movesBusinessDate, isTrue);
      expect(
        moved.copyWith(businessDate: june15).movesBusinessDate,
        isFalse,
        reason:
            'the comparison is against the loaded date, so undoing the change '
            'genuinely undoes it rather than leaving the form stuck in correction mode',
      );
    });

    test('copyWith cannot move the loaded date', () {
      final draft = loadedDraft();
      expect(draft.originalBusinessDate, june15);
      expect(
        draft
            .copyWith(businessDate: june16, notes: 'typing')
            .originalBusinessDate,
        june15,
        reason:
            'every keystroke rebuilds the draft; if the anchor moved with it, a '
            'correction would stop looking like one halfway through being typed',
      );
    });
  });

  group('the form refuses what the server would refuse, before the save', () {
    test('moving the date without the capability is a stated problem', () {
      final draft = loadedDraft().copyWith(
        businessDate: june16,
        correctionReason: 'Wrong trading day',
      );
      final without = principalWith({
        Capability.expenseCreate,
        Capability.expenseEditOwn,
      }, unit: ccrId);

      expect(
        draft.problemsFor(without),
        contains(DraftProblem.businessDateCorrectionNotPermitted),
      );
      expect(draft.canSave(without), isFalse);
    });

    test('the same edit without the date move is fine for the same person', () {
      final without = principalWith({
        Capability.expenseCreate,
        Capability.expenseEditOwn,
      }, unit: ccrId);
      expect(
        loadedDraft().copyWith(notes: 'a corrected figure').canSave(without),
        isTrue,
        reason:
            'the new gate must bind on the branch it is for and on no other — the '
            'fast path gains no permission requirement',
      );
    });

    test(
      'a correction with no reason, or a blank one, is a stated problem',
      () {
        final finance = principalWith({
          Capability.expenseCreate,
          Capability.expenseEditAll,
          Capability.correctBusinessDate,
        }, unit: ccrId);

        for (final reason in [null, '', '   ', '\t']) {
          final draft = loadedDraft().copyWith(
            businessDate: june16,
            correctionReason: reason,
          );
          expect(
            draft.problemsFor(finance),
            contains(DraftProblem.businessDateCorrectionNeedsReason),
            reason: 'reason ${jsonEncode(reason)} must not count as a reason',
          );
        }
      },
    );

    test('a permitted correction with a real reason has no problems', () {
      final finance = principalWith({
        Capability.expenseCreate,
        Capability.expenseEditAll,
        Capability.correctBusinessDate,
      }, unit: ccrId);
      final draft = loadedDraft().copyWith(
        businessDate: june16,
        correctionReason: 'Recorded against the wrong trading day',
      );
      expect(draft.problemsFor(finance), isEmpty);
    });

    test(
      'no refusal message names a capability code, an RPC or a refusal code',
      () {
        // The same discipline D-113 applies to revenue: a manager is told what to do, not
        // what the schema is called.
        for (final problem in [
          DraftProblem.businessDateCorrectionNotPermitted,
          DraftProblem.businessDateCorrectionNeedsReason,
        ]) {
          for (final forbidden in [
            'transaction.correct',
            'expense_update',
            'KM0',
            'business_date',
            'SQL',
          ]) {
            expect(
              problem.message,
              isNot(contains(forbidden)),
              reason: '${problem.name} leaks $forbidden',
            );
          }
        }
      },
    );
  });

  group('the reason reaches the server, and only when there is one', () {
    Future<Map<String, dynamic>> queuedUpdatePayload({
      String? correctionReason,
      BusinessDate? businessDate,
    }) async {
      final original = await accepted(simpleExpense());
      final mutationId = const Uuid().v4();
      await repository.updateLocally(
        expenseWith(
          id: original.row.id,
          businessDate: businessDate ?? june15,
          lines: [line(unit: ccrId, rupees: 200, date: businessDate ?? june15)],
        ),
        actorUserId: 'user-1',
        mutationId: mutationId,
        baseRowVersion: 2,
        now: now,
        correctionReason: correctionReason,
      );
      final intent = (await db.select(db.syncOutbox).get()).singleWhere(
        (q) => q.mutationId == mutationId,
      );
      return jsonDecode(intent.payload) as Map<String, dynamic>;
    }

    test('an ordinary edit sends no correction reason at all', () async {
      final payload = await queuedUpdatePayload();
      expect(
        payload.containsKey('p_correction_reason'),
        isFalse,
        reason:
            'an absent reason and an empty one are different things, and the empty '
            'one is what the server refuses',
      );
    });

    test('a correction carries its reason in the durable payload', () async {
      final payload = await queuedUpdatePayload(
        businessDate: june16,
        correctionReason: '  Recorded against the wrong trading day  ',
      );
      expect(
        payload['p_correction_reason'],
        'Recorded against the wrong trading day',
      );
      expect(
        payload['p_business_date'],
        '2026-06-16',
        reason: 'the payload is the intent, captured at save time',
      );
    });

    test('a reason of only whitespace is not sent as a reason', () async {
      // Sending `"   "` would be asking the server to refuse something the client could
      // have refused first, and would reach the audit row if the server ever stopped
      // checking. Both halves check.
      final payload = await queuedUpdatePayload(
        businessDate: june16,
        correctionReason: '   \t ',
      );
      expect(payload.containsKey('p_correction_reason'), isFalse);
    });

    test('the update payload still never restates the date provenance', () async {
      // `business_date_source` is the server's to write, on the branch where the date
      // actually moved. A client that sent its own would be claiming the act rather
      // than requesting it.
      final payload = await queuedUpdatePayload(
        businessDate: june16,
        correctionReason: 'Wrong day',
      );
      expect(payload.containsKey('p_business_date_source'), isFalse);
      expect(payload.containsKey('p_captured_at'), isFalse);
    });

    test('the intent survives a restart, reason and all', () async {
      // The offline case, stated as the thing that actually matters: the queue is a
      // table, so an authorised correction queued today is delivered verbatim whenever
      // the network returns, from whatever process happens to be running then.
      final original = await accepted(simpleExpense());
      final mutationId = const Uuid().v4();
      await repository.updateLocally(
        expenseWith(
          id: original.row.id,
          businessDate: june16,
          lines: [line(unit: ccrId, rupees: 200, date: june16)],
        ),
        actorUserId: 'user-1',
        mutationId: mutationId,
        baseRowVersion: 2,
        now: now,
        correctionReason: 'Wrong day',
      );

      final reopened = AppDatabase(db.executor);
      final intent = (await reopened.select(reopened.syncOutbox).get())
          .singleWhere((q) => q.mutationId == mutationId);
      final payload = jsonDecode(intent.payload) as Map<String, dynamic>;
      expect(payload['p_correction_reason'], 'Wrong day');
      expect(
        intent.baseRowVersion,
        2,
        reason:
            'a correction is still judged against the version it was made on',
      );
      expect(intent.actorUserId, 'user-1');
    });
  });
}
