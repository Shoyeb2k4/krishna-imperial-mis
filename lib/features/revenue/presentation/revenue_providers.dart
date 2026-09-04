/// What the revenue screens read and write.
///
/// The controller is deliberately thin, exactly as the expense one is: it turns a draft
/// into the Slice 7 create call and nudges the sync worker. It performs no arithmetic and
/// makes no authority decision of its own — those live in `RevenueDraft`, in
/// `RevenueRepository.evaluate`, and finally in Postgres.
///
/// **There is no second create path here.** Everything a widget can reach goes through
/// `RevenueRepository`, which was proven end to end in Slice 7 against the real backend.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_draft.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_filters.dart';
import 'package:uuid/uuid.dart';

final revenueTaxRepositoryProvider = Provider<RevenueTaxRepository>(
  (ref) => RevenueTaxRepository(ref.watch(databaseProvider)),
);

final revenueRepositoryProvider = Provider<RevenueRepository>(
  (ref) => RevenueRepository(
    ref.watch(databaseProvider),
    tax: ref.watch(revenueTaxRepositoryProvider),
  ),
);

/// The confirmed authority, or null when the session cannot supply one.
///
/// Null rather than an empty snapshot, because "nobody is signed in" and "somebody is
/// signed in with no grants" are different facts and only one of them is a refusal the
/// user can do something about (D-051).
final revenueAuthorityProvider = Provider<AuthoritySnapshot?>((ref) {
  final session = ref.watch(sessionProvider);
  return session is SessionReady ? session.authority : null;
});

/// The tax rules cached for one category, as the domain model.
///
/// Loads **every** candidate rather than filtering to one, because the doctrine needs to
/// distinguish zero, one and many — a query that returned the first match by ordering
/// would silently reintroduce the ranking D-094 forbids.
final revenueRulesProvider = FutureProvider.family<RevenueTaxRuleSet, String>((
  ref,
  categoryId,
) {
  ref.watch(principalProvider);
  return ref.watch(revenueTaxRepositoryProvider).rulesFor(categoryId);
});

/// Whether this device may resolve tax for a scope at all, and if not, why.
///
/// Asked of the **repository**, not re-derived here. It is the same call
/// `RevenueRepository.evaluate` makes before it writes, so the screen and the save path
/// cannot disagree about whether the configuration is usable — including about D-112
/// freshness, which is measured from the server-confirmed timestamp and not from any
/// clock this layer could read.
final revenueConfigurationBlockProvider =
    FutureProvider.family<RevenueTaxResolution?, String>((ref, unitId) async {
      final authority = ref.watch(revenueAuthorityProvider);
      if (authority == null) return null;

      final state = await ref
          .watch(revenueTaxRepositoryProvider)
          .completenessFor(userId: authority.userId, businessUnitId: unitId);

      return switch (state) {
        RevenueConfigComplete() => switch (state.freshnessAt(
          DateTime.now().toUtc(),
        )) {
          RevenueConfigFreshness.fresh => null,
          RevenueConfigFreshness.expired =>
            const RevenueConfigurationUnavailable(
              RevenueConfigurationGap.expired,
            ),
          RevenueConfigFreshness.clockUnreliable =>
            const RevenueConfigurationUnavailable(
              RevenueConfigurationGap.clockUnreliable,
            ),
        },
        RevenueConfigRevoked() => const RevenueConfigurationUnavailable(
          RevenueConfigurationGap.revoked,
        ),
        RevenueConfigIncomplete() => const RevenueConfigurationUnavailable(
          RevenueConfigurationGap.partial,
        ),
        RevenueConfigNeverSynchronised() =>
          const RevenueConfigurationUnavailable(
            RevenueConfigurationGap.neverSynchronised,
          ),
      };
    });

/// The recent sales this actor may browse.
///
/// Excludes anything stamped `scope_revoked_at` by construction — the repository's own
/// query does, and there is deliberately no parameter here that could turn that off. A
/// retained attempt reaches its owner through the dedicated workflow and never through
/// the ordinary list (D-070, D-074).
/// One sale, loaded with its components.
///
/// Lives here rather than beside the panel that first needed it, because three surfaces
/// now read it - the Windows panel, the Android detail route and the correction controls
/// - and a provider owned by one widget is a provider the next widget imports a widget to
/// reach.
/// Where one sale stands in the sync lifecycle, for a detail surface.
///
/// Its own provider rather than a field plucked out of whichever ledger query happened to
/// have run: the phone has no ledger, and a detail screen that reads its status from an
/// empty list reports `Synced` for everything.
final revenueSyncStateProvider = FutureProvider.family<SyncState, String>((
  ref,
  id,
) {
  ref.watch(principalProvider);
  return ref.watch(revenueRepositoryProvider).syncStateOf(id);
});

final revenueDetailProvider = FutureProvider.family<RevenueEntry?, String>((
  ref,
  id,
) {
  // Depending on the principal is what makes a user switch re-read rather than serve the
  // previous person's cached projection - the defect D-072a found one layer above the
  // expense read model, arriving here before it can happen again.
  ref.watch(principalProvider);
  return ref.watch(revenueRepositoryProvider).load(id);
});

final recentRevenueProvider = FutureProvider<List<RevenueLedgerRow>>((ref) {
  // Depending on the principal is what makes a user switch re-read rather than serve the
  // previous person's cached rows — the defect D-072a found one layer above the read
  // model, arriving here before it can happen again.
  ref.watch(principalProvider);
  return ref.watch(revenueRepositoryProvider).list();
});

/// What a save produced.
final class RevenueSaveOutcome {
  const RevenueSaveOutcome({required this.entryId, required this.queued});

  final String entryId;

  /// Always true today: a sale is written locally and queued, and the server sees it
  /// afterwards. Named rather than assumed so the screen never says "sent" for something
  /// that is merely saved.
  final bool queued;
}

class RevenueEntryController {
  const RevenueEntryController(this._ref);

  final Ref _ref;

  /// Evaluates a draft without writing anything.
  ///
  /// The form calls this to decide whether Save may be offered and what to say when it
  /// may not. It is the identical call [save] makes, so a refusal cannot appear only at
  /// the moment somebody presses the button.
  Future<RevenueCreateDecision> evaluate(RevenueDraft draft) async {
    final authority = _ref.read(revenueAuthorityProvider);
    return _ref
        .read(revenueRepositoryProvider)
        .evaluate(
          draft.toEntryDraft(capturedAt: DateTime.now().toUtc()),
          authority: authority,
        );
  }

  /// Saves the draft locally and queues it. One transaction; no network.
  ///
  /// Returns the refusal rather than throwing when the entry may not be recorded: a
  /// refusal is an answer, and a screen that has to catch an exception to display one
  /// ends up showing whatever the exception said.
  Future<(RevenueSaveOutcome?, RevenueRefusal?)> save(
    RevenueDraft draft,
  ) async {
    final authority = _ref.read(revenueAuthorityProvider);
    final repository = _ref.read(revenueRepositoryProvider);
    final capturedAt = DateTime.now().toUtc();
    final entryDraft = draft.toEntryDraft(capturedAt: capturedAt);

    final decision = await repository.evaluate(
      entryDraft,
      authority: authority,
    );
    if (decision is RevenueCreateRefused) return (null, decision.refusal);

    await repository.createLocally(
      entryDraft,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: authority!.userId,
      orgId: authority.orgId,
      // A fresh idempotency key per act, generated once and reused by every retry. The
      // draft id is the document's identity; this is the delivery's (D-004).
      mutationId: const Uuid().v7(),
      now: DateTime.now().toUtc(),
    );

    // Every surface that shows this sale is a cached read model, so all of them have to
    // be told. Without this a user
    // records a sale, returns to the list, and does not see it — which reads as "my entry
    // was lost" rather than as a stale cache. The expense engine learned this the
    // expensive way during the Windows acceptance.
    _invalidateReadModel(draft.id);

    // Nudge the worker. It may do nothing — offline, or nothing due — and that is fine:
    // the entry is durable either way, which is the whole point of the outbox.
    unawaited(_pushThenRefresh());

    return (RevenueSaveOutcome(entryId: draft.id, queued: true), null);
  }

  /// Applies a correction locally and queues it (§12).
  ///
  /// Deliberately the same shape as [save], because it is the same form and the same
  /// rules — the only differences are the repository method it lands in and the version
  /// it carries. The draft's own `baseRowVersion` is used and nothing here re-reads the
  /// row: a correction is judged against the version the person was looking at, not
  /// against whatever a background pull has since written (D-021, §4).
  Future<(RevenueSaveOutcome?, RevenueRefusal?)> applyEdit(
    RevenueDraft draft,
  ) async {
    final baseRowVersion = draft.baseRowVersion;
    if (baseRowVersion == null) {
      throw StateError(
        'this draft was not loaded from an existing sale, so there is no version '
        'to base a correction on',
      );
    }

    final authority = _ref.read(revenueAuthorityProvider);
    final repository = _ref.read(revenueRepositoryProvider);
    final entryDraft = draft.toEntryDraft(
      // The original capture instant is the document's, and correcting a figure does not
      // change when the entry was made (D-019). The repository keeps the stored one; this
      // value never reaches the server on an update.
      capturedAt: DateTime.now().toUtc(),
    );

    final decision = await repository.evaluate(
      entryDraft,
      authority: authority,
    );
    if (decision is RevenueCreateRefused) return (null, decision.refusal);

    await repository.updateLocally(
      entryDraft,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: authority!.userId,
      orgId: authority.orgId,
      baseRowVersion: baseRowVersion,
      mutationId: const Uuid().v7(),
      now: DateTime.now().toUtc(),
    );

    _invalidateReadModel(draft.id);
    unawaited(_pushThenRefresh());

    return (RevenueSaveOutcome(entryId: draft.id, queued: true), null);
  }

  /// Queues a void, with its mandatory reason (§21).
  ///
  /// The reason is trimmed here and refused when empty, because the server refuses it
  /// too and telling somebody at the button is kinder than telling them after a sync.
  /// Voiding is a separate mutation with its own capability, its own base version and its
  /// own audit — not an edit that happens to blank a document (spec §14).
  Future<RevenueRefusal?> voidEntry({
    required String entryId,
    required int baseRowVersion,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) {
      return RevenueRefusal(
        RevenueRefusalReason.voidReasonRequired,
        'Say why this sale is being voided. The reason is kept with it.',
      );
    }

    final authority = _ref.read(revenueAuthorityProvider);
    if (authority == null) {
      return const RevenueRefusal(
        RevenueRefusalReason.notAuthenticated,
        'Sign in before voiding a sale.',
      );
    }

    final refusal = await _ref
        .read(revenueRepositoryProvider)
        .voidLocally(
          entryId: entryId,
          reason: trimmed,
          actorUserId: authority.userId,
          baseRowVersion: baseRowVersion,
          mutationId: const Uuid().v7(),
          now: DateTime.now().toUtc(),
        );

    if (refusal != null) return refusal;

    _invalidateReadModel(entryId);
    unawaited(_pushThenRefresh());
    return null;
  }

  /// Re-reads every surface that shows this document.
  ///
  /// All of them, because invalidating some is how the Windows expense acceptance found
  /// a finance user recording an entry the ledger then did not list.
  void _invalidateReadModel(String entryId) {
    _ref
      ..invalidate(recentRevenueProvider)
      ..invalidate(filteredRevenueProvider)
      ..invalidate(revenueHasMoreProvider)
      ..invalidate(revenueDetailProvider(entryId));
  }

  /// Pulls authoritative configuration again, for the case where it has gone stale.
  ///
  /// Offered *before* a D-112 refusal is presented, because "connect and try again" is
  /// only worth saying when trying again might work.
  ///
  /// Goes through the session's own `refreshAuthority`, which is the proven sequence:
  /// authority first and nothing before it, purge only on a confirmed answer, then the
  /// pull. Reaching past it to call the synchroniser directly would skip the ordering
  /// that keeps a queued privileged mutation from being pushed through a window in which
  /// the server has already withdrawn the scope.
  ///
  /// Returns whether the configuration is usable afterwards — a failed refresh withdraws
  /// nothing and leaves the previous snapshot standing, so "still stale" and "now
  /// unusable" are not the same outcome (D-048 §1).
  Future<bool> refreshConfiguration(String businessUnitId) async {
    await _ref.read(sessionProvider.notifier).refreshAuthority();

    _ref.invalidate(revenueConfigurationBlockProvider(businessUnitId));
    final blocked = await _ref.read(
      revenueConfigurationBlockProvider(businessUnitId).future,
    );
    return blocked == null;
  }

  Future<void> _pushThenRefresh() async {
    final engine = _ref.read(syncEngineProvider);
    if (engine == null) return;
    try {
      await engine.pushOnce();
    } on Object {
      // A push that fails changes nothing durable: the intent is queued and comes back on
      // the backoff clock. Swallowed here rather than surfaced, because the save has
      // already succeeded and a network complaint about it would be misleading.
      return;
    }
    _ref.invalidate(recentRevenueProvider);
  }
}

final revenueEntryControllerProvider = Provider<RevenueEntryController>(
  RevenueEntryController.new,
);
