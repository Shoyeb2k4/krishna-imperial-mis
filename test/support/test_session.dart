/// Session fixtures for widget tests.
///
/// These live in `test/` deliberately. The runtime provider has no fallback and no
/// development identity — `test/app/no_hardcoded_authority_test.dart` asserts that over
/// `lib/`, which is what reaches an Android or Windows binary. A widget test has no
/// server to establish a session with, so it states plainly which session it is testing
/// under rather than relying on anything the application does on its own.
library;

import 'package:krishna_mis/app/session/session_controller.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';

/// A session frozen in one state, with the three actions recorded rather than performed.
class StubSession extends SessionNotifier {
  StubSession(this._initial);

  final SessionState _initial;

  int signInCalls = 0;
  int signOutCalls = 0;
  int refreshCalls = 0;

  @override
  SessionState build() => _initial;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    state = const SessionState.unauthenticated();
  }

  @override
  Future<void> refreshAuthority() async {
    refreshCalls++;
  }
}

/// A session holding every capability, for screens whose subject is not authorisation.
///
/// Named so it reads as the fixture it is. Where a test *is* about authorisation it
/// should build the exact grants it means, not reach for this.
AuthoritySnapshot fullAuthority({String userId = 'test-owner'}) =>
    AuthoritySnapshot(
      userId: userId,
      orgId: 'test-org',
      resolvedAt: DateTime.utc(2026, 8, 28),
      grants: [for (final c in RoleTemplates.owner) CapabilityGrant(c)],
    );

/// A ready session holding every capability.
///
/// Call sites do the override themselves — `sessionProvider.overrideWith(() =>
/// StubSession(readySession()))` — so the provider's own types stay the only thing that
/// has to agree, rather than a helper trying to name Riverpod's internal override type.
SessionState readySession({
  AuthoritySnapshot? authority,
  AuthorityFreshness freshness = AuthorityFreshness.confirmed,
}) => SessionState.ready(
  authority: authority ?? fullAuthority(),
  freshness: freshness,
);
