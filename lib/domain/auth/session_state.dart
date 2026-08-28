/// The authentication and authority state of the running application, in one place.
///
/// Scattering `session != null` across screens is how a build ends up with one screen
/// that renders for an unverified user and another that does not. There is one state
/// here, every screen asks it, and the states that look similar are kept apart because
/// they mean different things:
///
///  * **authenticated, authority never verified** — signed in, but this device has never
///    received an authoritative answer about what they may do. Fails closed (§8). No
///    privileged navigation, no guessing.
///  * **authenticated, authority cached** — verified before, offline now. Permitted read
///    workflows continue against the cache, marked stale, and privileged mutations stay
///    pending rather than final.
///  * **authenticated, authority confirmed** — the server answered just now.
///
/// The first two are the ones that matter. Collapsing them into "signed in" is exactly
/// the bug that would hand a brand-new user the run of the application because their
/// phone happened to be in a lift.
library;

import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:meta/meta.dart';

/// Why a sign-in attempt did not succeed.
///
/// Deliberately coarse. A login screen that distinguishes "no such account" from "wrong
/// password" is telling an attacker which half they got right; these map several server
/// answers onto one message on purpose.
enum SignInFailure {
  /// The email or the password was wrong. One message for both, deliberately.
  invalidCredentials,

  /// The account exists but has been deactivated by an administrator.
  accountDeactivated,

  /// No connectivity.
  offline,

  /// The server answered unusably.
  serverUnavailable;

  String get message => switch (this) {
    SignInFailure.invalidCredentials =>
      'That email address and password do not match an account.',
    SignInFailure.accountDeactivated =>
      'This account has been deactivated. Ask the owner to restore your access.',
    SignInFailure.offline =>
      'No connection. Signing in needs the internet, even though the rest of the app '
          'works offline once you are in.',
    SignInFailure.serverUnavailable =>
      'The server is not responding. Please try again in a moment.',
  };
}

@immutable
sealed class SessionState {
  const SessionState();

  /// Nobody is signed in. The login screen is the whole application.
  const factory SessionState.unauthenticated({SignInFailure? failure}) =
      Unauthenticated;

  /// Credentials submitted, waiting on the server.
  const factory SessionState.authenticating() = Authenticating;

  /// Signed in; asking the server what they may do.
  const factory SessionState.verifying(String userId) = VerifyingAuthority;

  /// Signed in, and the server has never told this device what they may do.
  ///
  /// **Fails closed.** Not an error state to be dismissed — the application simply
  /// cannot say what this person is allowed to do, so it offers nothing (§8).
  const factory SessionState.unverified(
    String userId,
    AuthorityUnavailableReason reason,
  ) = AuthorityUnverified;

  /// Signed in with authority the server confirmed, either now or earlier.
  const factory SessionState.ready({
    required AuthoritySnapshot authority,
    required AuthorityFreshness freshness,
  }) = SessionReady;

  /// The session expired and could not be renewed. Queued work is untouched.
  const factory SessionState.expired() = SessionExpired;

  /// The principal driving every capability check, or an empty one.
  ///
  /// [Principal.anonymous] holds nothing, so a screen that forgets to check the state
  /// and asks the authoriser directly still gets "no" rather than "yes".
  Principal get principal => switch (this) {
    SessionReady(:final authority) => authority.principal,
    _ => Principal.anonymous,
  };

  /// Whether the application may show anything beyond sign-in and status.
  ///
  /// True only for [SessionReady]. Authenticated-but-unverified deliberately returns
  /// false: knowing who someone is is not the same as knowing what they may do.
  bool get grantsAccess => this is SessionReady;

  String? get userId => switch (this) {
    VerifyingAuthority(:final userId) => userId,
    AuthorityUnverified(:final userId) => userId,
    SessionReady(:final authority) => authority.userId,
    _ => null,
  };
}

final class Unauthenticated extends SessionState {
  const Unauthenticated({this.failure});
  final SignInFailure? failure;
  @override
  String toString() => 'Unauthenticated(${failure?.name ?? 'clean'})';
}

final class Authenticating extends SessionState {
  const Authenticating();
  @override
  String toString() => 'Authenticating';
}

final class VerifyingAuthority extends SessionState {
  const VerifyingAuthority(this.userId);
  @override
  final String userId;
  @override
  String toString() => 'VerifyingAuthority';
}

final class AuthorityUnverified extends SessionState {
  const AuthorityUnverified(this.userId, this.reason);
  @override
  final String userId;
  final AuthorityUnavailableReason reason;

  /// What the user is told. Actionable, and honest that nothing is available yet.
  String get message =>
      'Unable to verify your access. Connect to the internet and try again.';

  @override
  String toString() => 'AuthorityUnverified(${reason.name})';
}

final class SessionReady extends SessionState {
  const SessionReady({required this.authority, required this.freshness});
  final AuthoritySnapshot authority;
  final AuthorityFreshness freshness;

  bool get isStale => freshness != AuthorityFreshness.confirmed;

  @override
  String toString() => 'SessionReady(${authority.userId}, ${freshness.name})';
}

final class SessionExpired extends SessionState {
  const SessionExpired();

  String get message =>
      'Your session has expired. Sign in again to continue — nothing you have entered '
      'has been lost.';

  @override
  String toString() => 'SessionExpired';
}
