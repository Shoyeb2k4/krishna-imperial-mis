/// The session rules that carry security weight.
///
/// Each of these is a path that is awkward to reach on demand against a live server —
/// a first sign-in with no connectivity, an account deactivated mid-session, two people
/// sharing one back-office machine — and each is a path where getting it wrong hands
/// somebody access they should not have. They are therefore driven directly, with the
/// gateways stubbed, so every branch is exercised deliberately rather than when the
/// network happens to cooperate.
library;

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/session/session_controller.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/authority_store.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/remote/auth_gateway.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:uuid/uuid.dart';

class _Auth implements SessionAuth {
  // Both are set by the tests after construction, as the scenario requires.
  AuthenticatedUser? user;
  SignInFailure? failure;
  int signOutCalls = 0;

  @override
  AuthenticatedUser? get currentUser => user;

  @override
  Future<SignInResult> signIn({
    required String email,
    required String password,
  }) async => failure != null
      ? SignInResult.failed(failure!)
      : SignInResult.ok(
          user ?? const AuthenticatedUser(id: 'u1', email: 'a@b.c'),
        );

  @override
  Future<void> signOut() async {
    signOutCalls++;
    user = null;
  }
}

class _Authority implements AuthoritySource {
  _Authority(this.answer);
  AuthorityRefresh answer;
  int calls = 0;

  @override
  Future<AuthorityRefresh> refresh() async {
    calls++;
    return answer;
  }
}

class _Sync implements ReferenceSynchroniser {
  int calls = 0;
  @override
  Future<void> synchronise() async => calls++;
}

AuthoritySnapshot snapshotFor(
  String userId,
  Set<String> units, {
  DateTime? at,
}) => AuthoritySnapshot(
  userId: userId,
  orgId: 'org-1',
  resolvedAt: at ?? DateTime.utc(2026, 8, 28),
  grants: [
    for (final unit in units)
      CapabilityGrant(Capability.mastersView, businessUnitId: unit),
  ],
);

void main() {
  late AppDatabase db;
  late AuthorityStore store;
  late _Auth auth;
  late _Authority authority;
  late _Sync sync;
  late ProviderContainer container;

  final ccr = seedId('bu:CCR');
  final hki = seedId('bu:HKI');

  late NotifierProvider<SessionNotifier, SessionState> sessionProviderForTest;

  SessionState currentState() => container.read(sessionProviderForTest);

  Future<void> build() async {
    sessionProviderForTest = NotifierProvider<SessionNotifier, SessionState>(
      () => SessionController(
        SessionDependencies(
          auth: auth,
          authority: authority,
          store: store,
          purge: ScopeCachePurge(db),
          referenceSync: sync,
        ),
      ),
    );
    container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(sessionProviderForTest);
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedMasterData(db, now: DateTime.utc(2026, 8, 28));
    store = AuthorityStore(db);
    auth = _Auth();
    authority = _Authority(
      AuthorityRefresh.confirmed(snapshotFor('u1', {ccr})),
    );
    sync = _Sync();
  });

  tearDown(() => db.close());

  group('fail closed when authority was never established', () {
    test(
      'a first sign-in with no connectivity grants nothing at all',
      () async {
        authority.answer = const AuthorityRefresh.unavailable(
          AuthorityUnavailableReason.offline,
        );
        await build();
        await container
            .read(sessionProviderForTest.notifier)
            .signIn(email: 'a@b.c', password: 'x');

        final state = currentState();
        expect(state, isA<AuthorityUnverified>());
        expect(state.grantsAccess, isFalse);
        expect(state.principal.grants, isEmpty);
        expect(
          state.userId,
          'u1',
          reason: 'we know who they are; we do not know what they may do',
        );
      },
    );

    test('the reference sync is not run for an unverified session', () async {
      authority.answer = const AuthorityRefresh.unavailable(
        AuthorityUnavailableReason.serverUnreachable,
      );
      await build();
      await container
          .read(sessionProviderForTest.notifier)
          .signIn(email: 'a@b.c', password: 'x');
      expect(sync.calls, 0);
    });

    test(
      'a rejected sign-in reports the reason and stays signed out',
      () async {
        auth.failure = SignInFailure.invalidCredentials;
        await build();
        await container
            .read(sessionProviderForTest.notifier)
            .signIn(email: 'a@b.c', password: 'wrong');

        final state = currentState();
        expect(state, isA<Unauthenticated>());
        expect(
          (state as Unauthenticated).failure,
          SignInFailure.invalidCredentials,
        );
        expect(state.principal.grants, isEmpty);
      },
    );
  });

  group('cached authority', () {
    test('a previously verified user works offline, marked stale', () async {
      await build();
      await container
          .read(sessionProviderForTest.notifier)
          .signIn(email: 'a@b.c', password: 'x');
      expect(currentState(), isA<SessionReady>());

      // Now offline. The same user signs in again on the same device.
      authority.answer = const AuthorityRefresh.unavailable(
        AuthorityUnavailableReason.offline,
      );
      await container
          .read(sessionProviderForTest.notifier)
          .signIn(email: 'a@b.c', password: 'x');

      final state = currentState();
      expect(state, isA<SessionReady>());
      expect((state as SessionReady).freshness, AuthorityFreshness.stale);
      expect(state.isStale, isTrue);
      expect(
        state.principal.can(Capability.mastersView, businessUnitId: ccr),
        isTrue,
        reason: 'exactly what was confirmed before, and nothing more',
      );
    });

    test("one user's cached authority is never handed to another", () async {
      await build();
      await container
          .read(sessionProviderForTest.notifier)
          .signIn(email: 'a@b.c', password: 'x');
      expect(await store.ownerUserId(), 'u1');

      // A different person signs in on the same installation, offline.
      auth.user = const AuthenticatedUser(id: 'u2', email: 'other@b.c');
      authority.answer = const AuthorityRefresh.unavailable(
        AuthorityUnavailableReason.offline,
      );
      await container
          .read(sessionProviderForTest.notifier)
          .signIn(email: 'other@b.c', password: 'x');

      final state = currentState();
      expect(
        state,
        isA<AuthorityUnverified>(),
        reason:
            "u2 has never been verified here, so u1's authority is not reused",
      );
      expect(state.principal.grants, isEmpty);
    });
  });

  group('a user switch isolates the cache before anything is shown', () {
    test(
      "the previous user's hierarchy is purged when someone else signs in",
      () async {
        await build();
        await container
            .read(sessionProviderForTest.notifier)
            .signIn(email: 'a@b.c', password: 'x');
        expect(await db.select(db.businessUnits).get(), isNotEmpty);

        auth.user = const AuthenticatedUser(id: 'u2', email: 'other@b.c');
        authority.answer = const AuthorityRefresh.unavailable(
          AuthorityUnavailableReason.offline,
        );
        await container
            .read(sessionProviderForTest.notifier)
            .signIn(email: 'other@b.c', password: 'x');

        expect(
          await db.select(db.businessUnits).get(),
          isEmpty,
          reason:
              'a shared back-office machine must not show one person another '
              "person's downloaded hierarchy",
        );
        expect(await store.ownerUserId(), isNull);
      },
    );

    test('signing in again as the same user purges nothing', () async {
      await build();
      final notifier = container.read(sessionProviderForTest.notifier);
      await notifier.signIn(email: 'a@b.c', password: 'x');
      final before = (await db.select(db.businessUnits).get()).length;

      await notifier.signIn(email: 'a@b.c', password: 'x');
      expect(await db.select(db.businessUnits).get(), hasLength(before));
    });

    test('a user switch never touches the queue', () async {
      await build();
      final outbox = OutboxRepository(db);
      await outbox.enqueue(
        PendingMutation(
          mutationId: const Uuid().v4(),
          entityType: 'expense_category',
          entityId: seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
          op: MutationOp.update,
          payload: const {'name': 'queued by the first user'},
          baseRowVersion: 1,
          createdAt: DateTime.utc(2026, 8, 28),
        ),
        now: DateTime.utc(2026, 8, 28),
      );

      await container
          .read(sessionProviderForTest.notifier)
          .signIn(email: 'a@b.c', password: 'x');
      auth.user = const AuthenticatedUser(id: 'u2', email: 'other@b.c');
      await container
          .read(sessionProviderForTest.notifier)
          .signIn(email: 'other@b.c', password: 'x');

      expect(
        await db.select(db.syncOutbox).get(),
        hasLength(1),
        reason:
            "somebody else signing in is not a reason to lose a person's work",
      );
    });
  });

  group('deactivation and expiry', () {
    test(
      'a deactivated account loses access rather than coasting on cache',
      () async {
        await build();
        final notifier = container.read(sessionProviderForTest.notifier);
        await notifier.signIn(email: 'a@b.c', password: 'x');
        expect(currentState(), isA<SessionReady>());

        // The server declines to treat them as an actor at all. That is a statement, not
        // a connectivity problem, so cached authority must not rescue it.
        authority.answer = const AuthorityRefresh.unavailable(
          AuthorityUnavailableReason.sessionExpired,
        );
        await notifier.refreshAuthority();

        final state = currentState();
        expect(state, isA<SessionExpired>());
        expect(state.grantsAccess, isFalse);
        expect(state.principal.grants, isEmpty);
        expect(
          await store.ownerUserId(),
          isNull,
          reason:
              'the withdrawn authority is forgotten, not kept for a stale fallback',
        );
      },
    );

    test('signing out clears authority and keeps the queue', () async {
      await build();
      final outbox = OutboxRepository(db);
      final notifier = container.read(sessionProviderForTest.notifier);
      await notifier.signIn(email: 'a@b.c', password: 'x');
      await outbox.enqueue(
        PendingMutation(
          mutationId: const Uuid().v4(),
          entityType: 'vendor',
          entityId: 'v1',
          op: MutationOp.create,
          payload: const {'name': 'Sharma Traders'},
          createdAt: DateTime.utc(2026, 8, 28),
        ),
        now: DateTime.utc(2026, 8, 28),
      );

      await notifier.signOut();

      expect(currentState(), isA<Unauthenticated>());
      expect(auth.signOutCalls, 1);
      expect(await store.ownerUserId(), isNull);
      expect(
        await db.select(db.syncOutbox).get(),
        hasLength(1),
        reason: 'signing out is not the destructive erase action',
      );
    });
  });

  group('a confirmed session', () {
    test(
      'runs the reference sync and carries exactly the confirmed grants',
      () async {
        await build();
        await container
            .read(sessionProviderForTest.notifier)
            .signIn(email: 'a@b.c', password: 'x');

        final state = currentState();
        expect(state, isA<SessionReady>());
        expect((state as SessionReady).freshness, AuthorityFreshness.confirmed);
        expect(sync.calls, 1);
        expect(
          state.principal.can(Capability.mastersView, businessUnitId: ccr),
          isTrue,
        );
        expect(
          state.principal.can(Capability.mastersView, businessUnitId: hki),
          isFalse,
        );
        expect(
          state.principal.can(Capability.mastersManage, businessUnitId: ccr),
          isFalse,
        );
      },
    );

    test('refreshing authority asks the server again', () async {
      await build();
      final notifier = container.read(sessionProviderForTest.notifier);
      await notifier.signIn(email: 'a@b.c', password: 'x');
      final before = authority.calls;
      await notifier.refreshAuthority();
      expect(authority.calls, before + 1);
    });
  });
}
