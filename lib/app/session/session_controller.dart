/// The one place the application decides who is signed in and what they may do.
///
/// Every screen reads this. Nothing anywhere else asks whether a session exists, because
/// the interesting question is never "is there a session" — it is "has the server told us
/// what this person may do, and how long ago".
///
/// Three rules are load-bearing:
///
///  * **Fail closed on never-verified authority.** A user who signs in on a device that
///    has never received an authoritative answer gets no operational access at all, even
///    though authentication succeeded. Guessing would mean a brand-new user's permissions
///    depended on whether their phone had signal (§8).
///  * **A user switch isolates the cache before anything is shown.** Authority cached for
///    one person is never handed to the next, and the previous person's downloaded
///    hierarchy is purged before navigation opens. Shared back-office machines are the
///    normal case, not the exception (§16).
///  * **A deactivated account loses access at the next refresh.** The server refusing to
///    treat somebody as an actor is a *positive* statement, not a connectivity problem,
///    so it never falls back to cached authority (§14).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/data/local/authority_store.dart';
import 'package:krishna_mis/data/remote/auth_gateway.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';

/// The narrow slices of the gateways the session actually uses.
///
/// Named as capabilities rather than as classes so the controller depends on what it
/// needs, not on Supabase. The real gateways implement them; a test supplies its own and
/// exercises the fail-closed, user-switch and deactivation rules with no network at all —
/// which matters, because those are precisely the paths that are hard to reach on demand
/// against a live server.
abstract interface class SessionAuth {
  AuthenticatedUser? get currentUser;
  Future<SignInResult> signIn({
    required String email,
    required String password,
  });
  Future<void> signOut();
}

abstract interface class AuthoritySource {
  Future<AuthorityRefresh> refresh();
}

abstract interface class ReferenceSynchroniser {
  Future<void> synchronise();
}

/// What the controller needs, gathered so it can be built in a test without a network.
final class SessionDependencies {
  const SessionDependencies({
    required this.auth,
    required this.authority,
    required this.store,
    required this.purge,
    required this.referenceSync,
  });

  final SessionAuth auth;
  final AuthoritySource authority;
  final AuthorityStore store;
  final ScopeCachePurge purge;
  final ReferenceSynchroniser referenceSync;
}

/// What the application may ask of the session, independent of how it is satisfied.
///
/// The provider is typed on this rather than on the concrete controller so a test can
/// supply its own implementation without needing a Supabase client — and, more usefully,
/// so nothing in the UI can reach past the three actions below into the machinery.
abstract class SessionNotifier extends Notifier<SessionState> {
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();
  Future<void> refreshAuthority();
}

class SessionController extends SessionNotifier {
  SessionController(this._deps);

  final SessionDependencies _deps;

  @override
  SessionState build() {
    // Restoration is asynchronous; until it finishes the application is unauthenticated,
    // which is the safe thing to be while the answer is unknown.
    Future.microtask(restore);
    return const SessionState.unauthenticated();
  }

  /// Re-establishes a session left behind by a previous run of the application.
  Future<void> restore() async {
    final user = _deps.auth.currentUser;
    if (user == null) {
      state = const SessionState.unauthenticated();
      return;
    }
    await _establishAuthority(user.id, user.email);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    state = const SessionState.authenticating();
    final result = await _deps.auth.signIn(email: email, password: password);

    switch (result) {
      case SignInRejected(:final failure):
        state = SessionState.unauthenticated(failure: failure);
      case SignedIn(:final user):
        await _isolateFromPreviousUser(user.id);
        await _establishAuthority(user.id, user.email);
    }
  }

  /// Ends the session without taking anybody's unsent work with it.
  ///
  /// Tokens go; the **downloaded scope cache** goes; the cached authority goes, so it
  /// cannot leak into whoever signs in next. The local database itself and the outbox
  /// stay. Erasing local data is a separate, explicit, destructive action, and conflating
  /// the two would quietly destroy entries that exist nowhere else
  /// (`ARCHITECTURE.md` §8.2).
  ///
  /// The scope purge has to happen **here**, not on the next sign-in. Sign-out is the
  /// last moment at which the device still knows whose cached hierarchy this is: clearing
  /// the authority record erases that fact, so [_isolateFromPreviousUser] would find no
  /// previous owner and leave the whole of the previous user's downloaded hierarchy
  /// readable to whoever signs in next. On a shared back-office workstation that is the
  /// normal sequence, not an edge case — it was caught on a real device, with the Owner's
  /// Hotel Krishna Imperial data still browsable by a Crystal Canopy-only Manager.
  ///
  /// Nothing is lost by purging: the same user signing back in re-pulls what they are
  /// entitled to, and offline they would have no cached authority to work under anyway.
  /// **Fails closed.** If the purge cannot complete, the previous user's figures must
  /// not simply remain readable because a cleanup step threw (D-074). Nothing is
  /// destroyed on that path either — the fallback quarantines every remaining document
  /// instead, which satisfies the safe half of both guarantees: unbrowsable, and not
  /// deleted. The next successful purge clears it in the ordinary way.
  ///
  /// The authority store is cleared regardless, because a session that could not be
  /// cleaned up is emphatically not one to leave signed in.
  @override
  Future<void> signOut() async {
    await _deps.auth.signOut();
    try {
      await _deps.purge.purgeAllScopedCache();
    } on Object {
      await _deps.purge.quarantineAllDocuments();
      rethrow;
    } finally {
      await _deps.store.clear();
      state = const SessionState.unauthenticated();
    }
  }

  /// Re-asks the server what the current user may do — on reconnect, or on demand.
  ///
  /// Authority is refreshed **before** anything else touches the server, so a queued
  /// privileged mutation is never pushed through a window in which the client is acting
  /// on scope the server has already withdrawn. The server remains the final protection
  /// regardless; this only removes an avoidable window.
  @override
  Future<void> refreshAuthority() async {
    final userId = state.userId;
    if (userId == null) return;
    await _establishAuthority(
      userId,
      _deps.auth.currentUser?.email ?? '',
      keepingCurrentStateWhileWorking: true,
    );
  }

  /// The core transition: signed in → what may they do?
  Future<void> _establishAuthority(
    String userId,
    String email, {
    bool keepingCurrentStateWhileWorking = false,
  }) async {
    if (!keepingCurrentStateWhileWorking) {
      state = SessionState.verifying(userId);
    }

    final refresh = await _deps.authority.refresh();

    if (refresh is AuthorityConfirmed) {
      // Confirmed. The reference sync re-runs the same refresh internally, which is what
      // applies D-048 and pulls the permitted data; doing it here as well would be a
      // second, racier source of truth.
      await _deps.referenceSync.synchronise();

      // Then record the confirmed snapshot here as well. The sync also stores it — it has
      // to, because it needs the previous value to compute what was revoked — but the
      // session must not *depend* on that having happened. If the sync were ever skipped
      // or failed before its own save, this user would come back offline tomorrow with no
      // cached authority and be locked out of data they are entitled to see. Writing the
      // same value twice costs nothing; relying on somebody else to write it costs a
      // working day.
      await _deps.store.save(refresh.snapshot);

      state = SessionState.ready(
        authority: refresh.snapshot,
        freshness: AuthorityFreshness.confirmed,
        email: email,
      );
      return;
    }

    final reason = (refresh as AuthorityUnavailable).reason;

    // The server declining to treat this person as an actor is a *statement*, not a
    // connectivity problem: the account was deactivated, or the session is genuinely
    // finished. Falling back to cached authority here would leave a deactivated user
    // working indefinitely on permissions that have been withdrawn (§14).
    if (reason == AuthorityUnavailableReason.sessionExpired) {
      await _deps.store.clear();
      state = const SessionState.expired();
      return;
    }

    final cached = await _deps.store.loadFor(userId);
    if (cached != null) {
      // Verified before, unreachable now. Permitted cached workflows continue, marked
      // stale, and privileged mutations stay pending rather than final.
      state = SessionState.ready(
        authority: cached,
        freshness: AuthorityFreshness.stale,
        email: email,
      );
      return;
    }

    // Never verified on this device. Fails closed: authentication established who they
    // are, and nothing has established what they may do.
    state = SessionState.unverified(userId, reason);
  }

  /// Clears anything belonging to a different user before this one sees the application.
  ///
  /// On a shared workstation the previous person's downloaded hierarchy is sitting in the
  /// local database. It must not be browsable while the new user's own authority is still
  /// being established — and their own data arrives moments later from their own refresh,
  /// so the cost is a single pull.
  ///
  /// The outbox is not touched. Each entry belongs to whoever queued it (D-050), and
  /// somebody else signing in is not a reason to lose it.
  Future<void> _isolateFromPreviousUser(String userId) async {
    final previousOwner = await _deps.store.ownerUserId();
    if (previousOwner == null || previousOwner == userId) return;

    await _deps.purge.purgeAllScopedCache();
    await _deps.store.clear();
  }
}
