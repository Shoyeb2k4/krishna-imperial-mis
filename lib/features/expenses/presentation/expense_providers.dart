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
import 'package:krishna_mis/features/expenses/presentation/expense_filters.dart';
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

    await _attachmentsAwaitExpense(document.id);

    // The ledger is a cached read model, so it has to be told. Without this a user
    // records an expense, returns to the ledger, and does not see it — which the
    // Windows acceptance found, and which reads as "my entry was lost" rather than as a
    // stale cache. The void path has always done this; create and edit had not.
    _invalidateReadModel(document.id);

    // Nudge the worker. It may do nothing — offline, or nothing due — and that is fine:
    // the entry is durable either way, which is the whole point of the outbox.
    _pushThenRefresh(document.id);

    return SaveOutcome(expenseId: document.id, queued: true);
  }

  /// Re-reads every surface that shows this document.
  ///
  /// **All three**, and the third is the one that was missed. Android's home surface
  /// reads `recentExpensesProvider`; the Windows ledger reads `filteredExpensesProvider`;
  /// the detail panel reads its own family entry. Invalidating two of the three meant a
  /// finance user on Windows recorded an expense and the ledger simply did not list it —
  /// found by the Windows edit acceptance, which could not open a document the ledger
  /// never showed.
  void _invalidateReadModel(String expenseId) {
    _ref.invalidate(expenseDetailProvider(expenseId));
    _ref.invalidate(recentExpensesProvider);
    _ref.invalidate(filteredExpensesProvider);
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
          // Sent only when this edit actually moves the date. The server decides that
          // question again from canonical state and refuses a blank reason on its own
          // branch, so this shapes the request rather than authorising it (spec §9).
          correctionReason: draft.movesBusinessDate
              ? draft.correctionReason
              : null,
        );

    await _attachmentsAwaitExpense(document.id);
    _invalidateReadModel(document.id);
    _pushThenRefresh(document.id);

    return SaveOutcome(expenseId: document.id, queued: true);
  }

  /// Attachments stop being a draft's staged files and start waiting for their document.
  ///
  /// Called at save. A bill cannot be uploaded yet — the Storage policy requires the
  /// expense to exist canonically — so it moves to `waitingForExpense`, and the worker
  /// promotes it the moment the server accepts the document (D-073 §2).
  Future<void> _attachmentsAwaitExpense(String expenseId) async {
    await _ref
        .read(attachmentUploadWorkerProvider)
        ?.markWaitingForExpense(expenseId);
  }

  /// Pushes, and re-reads the ledger once the push has finished.
  ///
  /// The invalidation *before* the push shows the entry immediately, pending. This one
  /// is for what the push brings back: the server issues the transaction number, the
  /// reconciler writes it in the data layer — where no provider can be reached — and
  /// without this the ledger goes on showing a document as unnumbered and pending long
  /// after it was accepted. Found by the Windows edit acceptance, which had to look up a
  /// document by the number the ledger was not showing.
  ///
  /// Deliberately not awaited by the caller: a save is durable whether or not the push
  /// succeeds, and making the screen wait for the network is the thing offline-first
  /// exists to avoid.
  void _pushThenRefresh(String expenseId) {
    final engine = _ref.read(syncEngineProvider);
    if (engine == null) return;
    unawaited(
      engine
          .pushOnce()
          .then((_) async {
            // The expense may have just been accepted, which is exactly what makes its
            // attachments eligible. Uploading happens *after* the financial record and
            // never blocks it (spec §15, D-073 §2).
            await _ref.read(attachmentUploadWorkerProvider)?.uploadDue();
            _invalidateReadModel(expenseId);
          })
          .catchError(
            // A failed push is the outbox's problem, not the ledger's. The entry stays
            // queued and visibly pending, which is already true on screen. A failed
            // upload is the attachment's own problem, on its own retry clock.
            (Object _) {},
          ),
    );
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
      _ref.invalidate(filteredExpensesProvider);
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
///
/// Watches the signed-in principal, and not because the query needs it: these caches
/// must not outlive the session that filled them. The device acceptance found the
/// consequence of leaving them alone — an Owner opened a ₹58,000 shared invoice, a
/// Crystal Canopy manager signed in on the same installation, and the detail surface
/// served them the Owner's **complete** projection out of the cache. The local row had
/// been correctly re-pulled as `scoped` with no document total; the screen was reading a
/// value the database no longer held.
///
/// That is precisely the leak D-062 shapes the read model to make impossible, arriving
/// one layer above it. Re-reading on a change of principal costs one local query and
/// closes it.
final recentExpensesProvider = FutureProvider<List<LocalExpense>>((ref) {
  ref.watch(principalProvider);
  return ref.watch(expenseRepositoryProvider).list(limit: 50);
});

/// One expense, re-read whenever the signed-in principal changes. See
/// [recentExpensesProvider] for why that dependency is deliberate.
final expenseDetailProvider = FutureProvider.family<LocalExpense?, String>((
  ref,
  id,
) {
  ref.watch(principalProvider);
  return ref.watch(expenseRepositoryProvider).load(id);
});

/// Fire and forget, without the analyzer complaining that nobody awaited it.
void unawaited(Future<void>? future) {}
