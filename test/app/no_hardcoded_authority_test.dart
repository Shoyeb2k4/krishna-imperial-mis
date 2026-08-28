/// A build invariant: shipped code must never manufacture authority.
///
/// The Phase 1 placeholder handed out an Owner principal holding every capability. That
/// was correct while no backend existed, and became a security defect the moment one did.
/// It has been removed — but "removed once" is not a property, and the exact shape of the
/// mistake is easy to reintroduce while debugging and easy to miss in review, because it
/// looks like a convenience rather than a hole.
///
/// So the invariant is asserted mechanically over `lib/`, which is what actually ships in
/// the Android and Windows binaries. Test fixtures may still construct whatever principal
/// they need; they are not in `lib/`, and they cannot enter a build.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';

List<({String path, String source})> _shippedSources() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
  return [
    for (final file in files)
      (path: file.path.replaceAll(r'\', '/'), source: file.readAsStringSync()),
  ];
}

void main() {
  group('no shipped code invents authority', () {
    test('nothing in lib/ grants every capability at once', () {
      // `RoleTemplates.owner` is the seed definition of the Owner bundle and belongs in
      // the domain. What must not exist is shipped code *constructing a principal from
      // it* — that is the omnipotent-dev-user shape.
      final offenders = [
        for (final file in _shippedSources())
          if (file.path != 'lib/domain/auth/capability.dart' &&
              (file.source.contains('RoleTemplates.owner') ||
                  file.source.contains('Capability.values)') ||
                  file.source.contains('for (final c in Capability.values)')))
            file.path,
      ];
      expect(
        offenders,
        isEmpty,
        reason: 'shipped code must not build a principal holding everything',
      );
    });

    test('nothing in lib/ constructs a Principal outside the session state', () {
      // Exactly one place turns confirmed authority into a Principal:
      // `AuthoritySnapshot.principal`. Anywhere else building one is manufacturing
      // permissions from something other than the server's answer.
      final offenders = [
        for (final file in _shippedSources())
          if (file.source.contains('Principal(') &&
              file.path != 'lib/domain/auth/capability.dart' &&
              file.path != 'lib/domain/auth/authority.dart')
            file.path,
      ];
      expect(offenders, isEmpty);
    });

    test('no development or debug principal survives anywhere in lib/', () {
      final suspicious = RegExp(
        r"(dev-owner|devOwner|debugPrincipal|fakePrincipal|assumeOwner|"
        r"bypassAuth|skipAuth)",
        caseSensitive: false,
      );
      for (final file in _shippedSources()) {
        expect(
          suspicious.hasMatch(file.source),
          isFalse,
          reason: '${file.path} looks like it carries a stand-in identity',
        );
      }
    });
  });

  group('every unverified state yields nothing', () {
    test('an unauthenticated session holds no capability', () {
      const state = SessionState.unauthenticated();
      expect(state.principal.grants, isEmpty);
      expect(state.grantsAccess, isFalse);
    });

    test('a session mid-authentication holds no capability', () {
      const state = SessionState.authenticating();
      expect(state.principal.grants, isEmpty);
      expect(state.grantsAccess, isFalse);
    });

    test('signed in but never verified holds no capability — the §8 rule', () {
      const state = SessionState.unverified(
        'user-1',
        AuthorityUnavailableReason.offline,
      );
      expect(state.principal.grants, isEmpty);
      expect(
        state.grantsAccess,
        isFalse,
        reason: 'knowing who somebody is is not knowing what they may do',
      );
      expect(state.userId, 'user-1');
    });

    test('an expired session holds no capability', () {
      const state = SessionState.expired();
      expect(state.principal.grants, isEmpty);
      expect(state.grantsAccess, isFalse);
    });

    test('only a ready session carries the grants the server confirmed', () {
      final state = SessionState.ready(
        authority: AuthoritySnapshot(
          userId: 'user-1',
          orgId: 'org-1',
          resolvedAt: DateTime.utc(2026, 8, 28),
          grants: const [
            CapabilityGrant(Capability.mastersView, businessUnitId: 'ccr'),
          ],
        ),
        freshness: AuthorityFreshness.confirmed,
      );

      expect(state.grantsAccess, isTrue);
      expect(
        state.principal.can(Capability.mastersView, businessUnitId: 'ccr'),
        isTrue,
      );
      expect(
        state.principal.can(Capability.mastersView, businessUnitId: 'hki'),
        isFalse,
      );
      expect(
        state.principal.can(Capability.mastersManage, businessUnitId: 'ccr'),
        isFalse,
        reason: 'a capability nobody granted is never held',
      );
    });

    test('a stale ready session still carries only what was confirmed', () {
      final state = SessionState.ready(
        authority: AuthoritySnapshot(
          userId: 'user-1',
          orgId: 'org-1',
          resolvedAt: DateTime.utc(2026, 8, 20),
          grants: const [
            CapabilityGrant(Capability.mastersView, businessUnitId: 'ccr'),
          ],
        ),
        freshness: AuthorityFreshness.stale,
      );
      expect(state.grantsAccess, isTrue);
      expect((state as SessionReady).isStale, isTrue);
      expect(state.principal.grants, hasLength(1));
    });
  });
}
