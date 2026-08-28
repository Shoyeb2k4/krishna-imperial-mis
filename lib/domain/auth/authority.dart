/// What the server currently says this user may do — and, just as importantly, whether
/// the server said anything at all.
///
/// D-048 turns on one distinction:
///
///     unknown ≠ revoked
///
/// A purge of locally cached data is destructive. It must follow a **positive** statement
/// of the user's current scopes, and nothing else. An unreachable server, a timed-out
/// refresh, a token that could not be renewed, a flaky connection on a rooftop — none of
/// those are evidence that anything was taken away, and treating them as evidence would
/// make going through a tunnel indistinguishable from being dismissed.
///
/// So the refresh result is a sealed type rather than a nullable snapshot. There is no
/// way to write code that purges on failure without saying so out loud.
library;

import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:meta/meta.dart';

/// The authority the server confirmed, at the moment it confirmed it.
@immutable
final class AuthoritySnapshot {
  AuthoritySnapshot({
    required this.userId,
    required this.orgId,
    required Iterable<CapabilityGrant> grants,
    required this.resolvedAt,
  }) : grants = Set.unmodifiable(grants);

  final String userId;
  final String orgId;
  final Set<CapabilityGrant> grants;

  /// Server time, not device time. Shown as the freshness of the permission state.
  final DateTime resolvedAt;

  Principal get principal => Principal(userId: userId, grants: grants);

  /// Whether this user holds an unscoped grant of anything — the Owner shape (D-025).
  ///
  /// Matters to the purge: an org-wide holder has no revoked units by construction, so
  /// there is nothing scope-specific to remove.
  bool get holdsOrgWideGrant => grants.any((g) => g.isOrgWide);

  /// Every business unit named by any grant. Empty for an org-wide holder, which is why
  /// [holdsOrgWideGrant] has to be consulted alongside it rather than inferred from this.
  Set<String> get scopedUnits => {
    for (final grant in grants)
      if (!grant.isOrgWide) grant.businessUnitId!,
  };

  /// Units this user could reach before and cannot reach now.
  ///
  /// Returns empty when the user now holds anything org-wide: gaining wider authority
  /// never revokes narrower authority, and computing a "loss" there would purge data the
  /// user can still legitimately see.
  Set<String> unitsRevokedSince(AuthoritySnapshot? previous) {
    if (previous == null || holdsOrgWideGrant) return const {};
    return previous.scopedUnits.difference(scopedUnits);
  }

  /// Units reachable now that were not reachable before. Drives a re-pull, never a purge.
  Set<String> unitsGrantedSince(AuthoritySnapshot? previous) {
    if (previous == null) return scopedUnits;
    return scopedUnits.difference(previous.scopedUnits);
  }

  @override
  String toString() =>
      'AuthoritySnapshot($userId, ${grants.length} grants, '
      '${holdsOrgWideGrant ? 'org-wide' : '${scopedUnits.length} units'})';
}

/// Why authority could not be established. Never a reason to purge anything.
enum AuthorityUnavailableReason {
  /// No connectivity, a DNS failure, a timeout — the request did not complete.
  offline,

  /// The server answered, but not usefully: a 5xx, a malformed body, a gateway error.
  serverUnreachable,

  /// The session expired and could not be renewed. The user must sign in again; their
  /// queued work is untouched (`docs/ARCHITECTURE.md` §5.1).
  sessionExpired;

  String get message => switch (this) {
    AuthorityUnavailableReason.offline =>
      'Working offline. Permissions were last confirmed earlier and are shown as they '
          'were then.',
    AuthorityUnavailableReason.serverUnreachable =>
      'The server could not be reached. Permissions are shown as they were last '
          'confirmed.',
    AuthorityUnavailableReason.sessionExpired =>
      'Your session has expired. Sign in again to continue — nothing you have entered '
          'has been lost.',
  };
}

/// The outcome of asking the server what this user may do.
///
/// Sealed on purpose: a caller must handle both cases, and only one of them is allowed
/// to reach the purge (D-048 §1).
@immutable
sealed class AuthorityRefresh {
  const AuthorityRefresh();

  const factory AuthorityRefresh.confirmed(AuthoritySnapshot snapshot) =
      AuthorityConfirmed;

  const factory AuthorityRefresh.unavailable(
    AuthorityUnavailableReason reason,
  ) = AuthorityUnavailable;

  /// **The only thing that may trigger a destructive cache purge.**
  ///
  /// Read it as the question it answers: "did the server positively tell us what this
  /// user may do?" Anything else — including a perfectly ordinary loss of signal — is
  /// not an answer, and silence must never be read as a denial.
  bool get establishesAuthority => this is AuthorityConfirmed;

  /// The snapshot, or null when authority is simply unknown.
  AuthoritySnapshot? get snapshotOrNull =>
      this is AuthorityConfirmed ? (this as AuthorityConfirmed).snapshot : null;
}

final class AuthorityConfirmed extends AuthorityRefresh {
  const AuthorityConfirmed(this.snapshot);
  final AuthoritySnapshot snapshot;

  @override
  String toString() => 'AuthorityConfirmed($snapshot)';
}

final class AuthorityUnavailable extends AuthorityRefresh {
  const AuthorityUnavailable(this.reason);
  final AuthorityUnavailableReason reason;

  @override
  String toString() => 'AuthorityUnavailable(${reason.name})';
}

/// How current the permission state on screen is.
///
/// The same three-way distinction the reporting layer makes about figures (§21.4): a
/// manager should never have to guess whether what they are looking at is current.
enum AuthorityFreshness {
  /// Confirmed by the server just now.
  confirmed,

  /// Last confirmed earlier; the device has not been able to check since.
  stale,

  /// Never confirmed on this device.
  unknown;

  String get label => switch (this) {
    AuthorityFreshness.confirmed => 'Permissions confirmed',
    AuthorityFreshness.stale => 'Permissions as last confirmed',
    AuthorityFreshness.unknown => 'Permissions not yet confirmed',
  };
}
