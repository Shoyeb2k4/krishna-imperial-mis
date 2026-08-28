/// Asking the server what this user may do.
///
/// The single most consequential call in the client, because its answer is the only
/// thing permitted to trigger a destructive local purge (D-048 §1). Every failure path
/// therefore returns [AuthorityRefresh.unavailable] with a reason, and only a genuine
/// `200` carrying a well-formed payload returns [AuthorityRefresh.confirmed].
///
/// A malformed or partial payload is treated as *unavailable*, not as an empty set of
/// grants. That distinction is the difference between "the server says you have nothing"
/// and "we could not tell", and reading the second as the first would wipe a manager's
/// cache because a proxy truncated a response.
library;

import 'package:krishna_mis/app/session/session_controller.dart';

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/supabase_gateway.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';

class AuthorityGateway extends SupabaseGateway implements AuthoritySource {
  const AuthorityGateway(super.client);

  /// The caller's current organisation, capabilities and business-unit scopes.
  @override
  Future<AuthorityRefresh> refresh() async {
    final outcome = await guard(() => client.rpc<dynamic>('my_authority'));

    return switch (outcome) {
      RemoteOk(:final value) => _parse(value),
      // A refusal here means the session is not an actor at all — signed out, or the
      // profile deactivated. Not connectivity, but equally not a statement of scope, so
      // it must not purge anything either.
      RemoteRefused() => const AuthorityRefresh.unavailable(
        AuthorityUnavailableReason.sessionExpired,
      ),
      RemoteUnreachable(:final failure) => AuthorityRefresh.unavailable(
        switch (failure) {
          RemoteFailure.offline => AuthorityUnavailableReason.offline,
          RemoteFailure.sessionExpired =>
            AuthorityUnavailableReason.sessionExpired,
          RemoteFailure.serverUnreachable =>
            AuthorityUnavailableReason.serverUnreachable,
        },
      ),
    };
  }

  /// Turns the RPC payload into a snapshot, or declines to.
  ///
  /// Anything unexpected in the shape yields `unavailable`. A snapshot is a licence to
  /// delete local data, and one is not issued from a response that could not be read
  /// with confidence.
  AuthorityRefresh _parse(dynamic payload) {
    if (payload is! Map) {
      return const AuthorityRefresh.unavailable(
        AuthorityUnavailableReason.serverUnreachable,
      );
    }

    final userId = payload['user_id'];
    final orgId = payload['org_id'];
    final rawGrants = payload['grants'];
    final resolvedAt = DateTime.tryParse('${payload['resolved_at']}');

    if (userId is! String ||
        orgId is! String ||
        rawGrants is! List ||
        resolvedAt == null) {
      return const AuthorityRefresh.unavailable(
        AuthorityUnavailableReason.serverUnreachable,
      );
    }

    final grants = <CapabilityGrant>[];
    for (final entry in rawGrants) {
      if (entry is! Map) continue;
      final code = entry['capability'];
      if (code is! String) continue;
      final Capability capability;
      try {
        capability = Capability.fromCode(code);
      } on ArgumentError {
        // A capability this build does not know about. Skipping it is the safe
        // direction — the user simply does not get a power this client cannot render —
        // whereas guessing at it would grant something unreviewed.
        continue;
      }
      grants.add(
        CapabilityGrant(
          capability,
          businessUnitId: entry['business_unit_id'] as String?,
        ),
      );
    }

    return AuthorityRefresh.confirmed(
      AuthoritySnapshot(
        userId: userId,
        orgId: orgId,
        grants: grants,
        resolvedAt: resolvedAt.toUtc(),
      ),
    );
  }
}
