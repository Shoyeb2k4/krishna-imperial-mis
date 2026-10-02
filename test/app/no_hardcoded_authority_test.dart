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
        email: 'user-1@example.test',
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
        email: 'user-1@example.test',
      );
      expect(state.grantsAccess, isTrue);
      expect((state as SessionReady).isStale, isTrue);
      expect(state.principal.grants, hasLength(1));
    });
  });

  group('the shipped seed is not a source of other properties data', () {
    // Found on a real Android device. The local seed contains **both** properties, and
    // start-up applied it unconditionally — so a fresh installation held a browsable
    // Hotel Krishna Imperial hierarchy before anybody signed in, and a Crystal
    // Canopy-scoped Manager signing in afterwards inherited it. Their own pull was
    // correctly scoped; the seed was sitting underneath it.
    test('seedMasterData runs only when no backend is configured', () {
      final bootstrap = File('lib/app/bootstrap.dart').readAsStringSync();
      expect(
        bootstrap.contains('seedMasterData('),
        isTrue,
        reason: 'the no-backend path still needs it',
      );

      final call = bootstrap.indexOf('await seedMasterData(');
      final guard = bootstrap.lastIndexOf('if (!config.hasBackend)', call);
      expect(
        guard,
        greaterThan(-1),
        reason:
            'with a backend the server decides which properties this user may cache; '
            'seeding locally hands them one the server never granted',
      );
      expect(
        call - guard,
        lessThan(200),
        reason: 'the guard must be the one immediately around the seed call',
      );
    });

    test('nothing else in lib/ applies the seed', () {
      final offenders = [
        for (final file in _shippedSources())
          if (file.source.contains('seedMasterData(') &&
              file.path != 'lib/app/bootstrap.dart' &&
              file.path != 'lib/data/local/seed/master_seed.dart')
            file.path,
      ];
      expect(offenders, isEmpty);
    });
  });

  group('the acceptance transport is not reachable from a shipped build', () {
    // `bootstrap({http.Client? transport})` lets the acceptance suite make the real
    // Windows executable's network genuinely fail, without touching machine security
    // settings. It is a parameter, not a switch — no environment variable, no registry,
    // no debug menu — so the only way to reach it is to call bootstrap with an argument.
    // These tests hold that true: if shipped code ever passes one, this fails.
    test('nothing in lib/ calls bootstrap with a transport', () {
      final offenders = [
        for (final file in _shippedSources())
          if (file.path != 'lib/app/bootstrap.dart' &&
              RegExp(r'bootstrap\s*\(\s*[^)]').hasMatch(file.source))
            file.path,
      ];
      expect(
        offenders,
        isEmpty,
        reason:
            'a shipped caller passing a transport would make the fault injector '
            'reachable in a real build, which is exactly what it must never be',
      );
    });

    test('main() starts the application with no arguments at all', () {
      final main = File('lib/main.dart').readAsStringSync();
      // Since Slice 7 `main()` hands the call to the start-up runner (D-329); every call
      // it makes still takes no arguments.
      expect(main, contains('bootstrap()'));
      expect(
        RegExp(r'bootstrap\(\s*[^)\s]').hasMatch(main),
        isFalse,
        reason: 'main() passes bootstrap an argument',
      );
      expect(main, isNot(contains('transport')));
      // The acceptance data folder is the same kind of parameter (D-246).
      expect(main, isNot(contains('appDataDirectory')));
    });

    test('lib/ contains no fault-injection switch of its own', () {
      for (final file in _shippedSources()) {
        expect(
          file.source,
          isNot(contains("fromEnvironment('KRISHNA_ACCEPTANCE")),
          reason: '${file.path} carries a compiled-in acceptance flag',
        );
        expect(
          file.source,
          isNot(contains('simulateOffline')),
          reason: '${file.path} carries a runtime offline switch',
        );
      }
    });
  });
}
