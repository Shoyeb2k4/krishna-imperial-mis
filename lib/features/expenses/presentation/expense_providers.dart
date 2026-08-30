/// What the expense screens read and write.
///
/// The controller is deliberately thin: it turns a draft into the domain aggregate, hands
/// it to the repository's one atomic transaction, and nudges the sync worker. It performs
/// no arithmetic and makes no authority decision of its own — those live in
/// [ExpenseDraft], [ExpenseDocument] and, finally, in Postgres.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_draft.dart';
import 'package:uuid/uuid.dart';

/// The signed-in user's organisation, as the server stated it.
///
/// Read from the confirmed authority snapshot rather than from configuration: the
/// organisation a user belongs to is the server's answer, not the client's assumption.
final organisationIdProvider = Provider<String>((ref) {
  final session = ref.watch(sessionProvider);
  return session is SessionReady ? session.authority.orgId : '';
});

/// Today, under the business-day cut-off rather than the raw device clock.
///
/// The default cut-off is 05:00 local property time, so a rooftop bill entered at 01:00
/// belongs to the previous trading day (D-019). Overridden in tests to a fixed date.
final currentBusinessDateProvider = Provider<BusinessDate>(
  (ref) => BusinessDate.fromInstant(
    DateTime.now().toUtc(),
    timeZoneId: 'Asia/Kolkata',
    cutoff: BusinessDayCutoff.defaultCutoff,
  ),
);

/// What the entry form offers again next time.
///
/// In memory for the life of the session. Persisting it would mean a stale suggestion
/// surviving a scope change, and [LastUsedClassification.validAgainst] would then be
/// doing security work rather than convenience work.
class LastUsedClassificationNotifier extends Notifier<LastUsedClassification> {
  @override
  LastUsedClassification build() => const LastUsedClassification();

  void remember(ExpenseDraft draft) =>
      state = LastUsedClassification.from(draft);
}

final lastUsedClassificationProvider =
    NotifierProvider<LastUsedClassificationNotifier, LastUsedClassification>(
      LastUsedClassificationNotifier.new,
    );

/// What a save produced.
final class SaveOutcome {
  const SaveOutcome({required this.expenseId, required this.queued});
  final String expenseId;

  /// Always true today: an expense is written locally and queued, and the server sees it
  /// afterwards. Named rather than assumed so the screen never says "sent" for something
  /// that is merely saved.
  final bool queued;
}

class ExpenseEntryController {
  const ExpenseEntryController(this._ref);

  final Ref _ref;

  /// Saves the draft locally and queues it. One transaction; no network.
  Future<SaveOutcome> save(
    ExpenseDraft draft, {
    required MasterGraph graph,
    required Principal principal,
  }) async {
    final document = draft.toDocument(
      orgId: _ref.read(organisationIdProvider),
      createdByUserId: principal.userId,
      capturedAt: DateTime.now().toUtc(),
      labelFor: (categoryId) =>
          graph.expenseCategory(categoryId)?.name ?? 'Category',
    );

    final mutationId = const Uuid().v7();
    await _ref
        .read(expenseRepositoryProvider)
        .createLocally(
          document,
          actorUserId: principal.userId,
          mutationId: mutationId,
          now: DateTime.now().toUtc(),
        );

    // Nudge the worker. It may do nothing — offline, or nothing due — and that is fine:
    // the entry is durable either way, which is the whole point of the outbox.
    unawaited(_ref.read(syncEngineProvider)?.pushOnce());

    return SaveOutcome(expenseId: document.id, queued: true);
  }

  /// Applies an edit to a document that already exists, and queues it (D-072).
  ///
  /// Deliberately the same shape as [save], because it is the same form and the same
  /// rules — the only differences are the repository method it lands in and the version
  /// it carries. The draft's own [ExpenseDraft.baseRowVersion] is used and nothing here
  /// re-reads the row: an edit is judged against the version the person was looking at,
  /// not against whatever a background pull has since written (§3, D-021).
  Future<SaveOutcome> applyEdit(
    ExpenseDraft draft, {
    required MasterGraph graph,
    required Principal principal,
    required DateTime capturedAt,
  }) async {
    final baseRowVersion = draft.baseRowVersion;
    if (baseRowVersion == null) {
      throw StateError(
        'this draft was not loaded from an existing document, so there is no '
        'version to base an edit on',
      );
    }

    final document = draft.toDocument(
      orgId: _ref.read(organisationIdProvider),
      createdByUserId: principal.userId,
      // The original capture instant, not now: correcting a figure does not change when
      // the entry was made, and `captured_at` is forensic metadata about that (D-019).
      capturedAt: capturedAt,
      labelFor: (categoryId) =>
          graph.expenseCategory(categoryId)?.name ?? 'Category',
    );

    final mutationId = const Uuid().v7();
    await _ref
        .read(expenseRepositoryProvider)
        .updateLocally(
          document,
          actorUserId: principal.userId,
          mutationId: mutationId,
          baseRowVersion: baseRowVersion,
          now: DateTime.now().toUtc(),
        );

    unawaited(_ref.read(syncEngineProvider)?.pushOnce());

    return SaveOutcome(expenseId: document.id, queued: true);
  }
}

final expenseEntryControllerProvider = Provider<ExpenseEntryController>(
  ExpenseEntryController.new,
);

/// Voiding, from the detail panel.
class ExpenseVoidController {
  const ExpenseVoidController(this._ref);

  final Ref _ref;

  /// Marks it voided locally and queues the intent. Returns false if the local write
  /// failed, in which case nothing changed.
  Future<bool> voidExpense(
    LocalExpense expense, {
    required String reason,
  }) async {
    try {
      await _ref
          .read(expenseRepositoryProvider)
          .voidLocally(
            expense,
            reason: reason,
            actorUserId: _ref.read(principalProvider).userId,
            mutationId: const Uuid().v7(),
            now: DateTime.now().toUtc(),
          );
      _ref.invalidate(expenseDetailProvider(expense.row.id));
      _ref.invalidate(recentExpensesProvider);
      unawaited(_ref.read(syncEngineProvider)?.pushOnce());
      return true;
    } on Object {
      return false;
    }
  }
}

final expenseVoidControllerProvider = Provider<ExpenseVoidController>(
  ExpenseVoidController.new,
);

/// The recent ledger, newest business date first.
final recentExpensesProvider = FutureProvider<List<LocalExpense>>(
  (ref) => ref.watch(expenseRepositoryProvider).list(limit: 50),
);

final expenseDetailProvider = FutureProvider.family<LocalExpense?, String>(
  (ref, id) => ref.watch(expenseRepositoryProvider).load(id),
);

/// Fire and forget, without the analyzer complaining that nobody awaited it.
void unawaited(Future<void>? future) {}
