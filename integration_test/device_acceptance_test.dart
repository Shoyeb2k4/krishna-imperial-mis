/// Phase 2 acceptance, executed inside the **real installed application** on a real
/// device, against the real `krishna-mis-dev` project, with the real development
/// identities.
///
/// Nothing here is a widget test: the app is assembled exactly as `main()` assembles it —
/// the encrypted local database, the platform key store, the Supabase client, the session
/// state machine, the router and both shells. The only thing supplied from outside is the
/// identity to sign in as, which arrives through `--dart-define-from-file` so no password
/// is ever typed on a command line, rendered on screen, or captured in a screenshot.
///
/// The run is split into phases because several of the rules under test only exist
/// *across* application restarts (session restoration, user switching, offline authority)
/// or need an administrative act in the middle that the signed-in user is by definition
/// not allowed to perform on themselves (revocation, deactivation). Each phase is one
/// `flutter test` invocation, which is one real process launch against the same installed
/// app and the same encrypted database.
///
///     flutter test integration_test/device_acceptance_test.dart -d <device> \
///       --flavor dev --dart-define-from-file=config/dev.json \
///       --dart-define-from-file=<scratch>/identities.defines.json \
///       --dart-define=PHASE=owner
///
/// Phases, in the order they are meant to run:
///
///   owner            sign in as the Owner; both properties, masters, vendors, tax, rename
///   restart          no sign-in at all — the session must come back on its own
///   signout          the account control ends the session
///   ccr-manager      a scoped Manager on the *same* installation as the Owner
///   data-entry       capability-gated UI, and the server refusing regardless
///   offline-cached   cached authority, marked stale, with the cache intact
///   offline-queued   a privileged mutation queued offline stays pending, never final
///   unverified       authenticated, never verified, no network — no access at all
///   revoked          D-048 through the app after the Owner takes a property away
///   conflict         a stale-version mutation is a Conflict, not a Rejection
///   propagate-a      client A: rename and archive, while client B is watching
///   propagate-b      client B: the change arrives; a stale intent conflicts
///   propagate-restore  put the development fixtures back
///   login-ux         keyboard, focus, obscured password, refusal wording
///
/// Three phases need something to happen on the *host* while the phase is running — the
/// device's network taken away, a grant revoked, an account deactivated — because the
/// signed-in user is by definition not allowed to do any of those to themselves. The host
/// waits for the application process to appear on the device and then acts, and the phase
/// polls for the consequence rather than assuming a fixed delay:
///
///     after_app_starts.sh 30 net_off_later.sh 0     # offline
///     after_app_starts.sh 45 revoke_only.sh         # revoked
///     after_app_starts.sh 45 deactivate_only.sh     # deactivated
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krishna_mis/app/app.dart';
import 'package:krishna_mis/app/bootstrap.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/session/session_controller.dart';
import 'package:krishna_mis/data/local/authority_store.dart';
import 'package:krishna_mis/data/remote/master_gateway.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _phase = String.fromEnvironment('PHASE');

/// Identities, supplied by `--dart-define-from-file`. Empty in an ordinary run, which is
/// why every phase is skipped unless one is named.
const _identities = <String, String>{
  'giridhar@hki.com': String.fromEnvironment('PW_OWNER'),
  'ccr.manager@example.com': String.fromEnvironment('PW_CCR_MANAGER'),
  'hki.manager@example.com': String.fromEnvironment('PW_HKI_MANAGER'),
  'data.entry@example.com': String.fromEnvironment('PW_DATA_ENTRY'),
  'accountant@example.com': String.fromEnvironment('PW_ACCOUNTANT'),
  'unassigned@example.com': String.fromEnvironment('PW_UNASSIGNED'),
};

/// The seeded master ids, derived the same way the migration derives them.
String _seedId(String path) =>
    const Uuid().v5('d9d3f0a6-4c2b-5f7e-9a10-6b1e2c8f4a70', path);

final _ccr = _seedId('bu:CCR');
final _hki = _seedId('bu:HKI');
final _kirana = _seedId('cat:CCR/FB/FOOD_PROD/KIRANA');

/// Two safe leaf categories used by the two-client propagation phases, and put back by
/// `propagate-restore` afterwards.
final _paneer = _seedId('cat:CCR/FB/FOOD_PROD/PANEER');
final _milk = _seedId('cat:CCR/FB/FOOD_PROD/MILK_DAHI');
const _paneerOriginalName = 'Paneer / Dairy';
const _paneerRenamed = 'Paneer / Dairy (cosmetic)';

/// A fixed id, so the queued intent survives from one phase's process into the next.
const _queuedMutationId = '8c41b7d2-63ae-4f0b-9d55-2e7a1c4f8b60';

/// A second fixed id, for work the *Owner* queues before a user switch.
const _ownerQueuedMutationId = 'b5d0e91a-7c34-4a68-8e2f-19b7d3c05a44';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late BootstrapResult boot;

  setUpAll(() async {
    boot = await bootstrap();
  });

  // ── Driving the real application ──────────────────────────────────────────

  /// Builds the app exactly as `main()` does, and waits for start-up to settle.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
        child: KrishnaMisApp(shellKind: boot.shellKind),
      ),
    );
    await tester.pump();
  }

  /// Pumps until [condition] holds, or fails with a legible message.
  ///
  /// `pumpAndSettle` is unusable here: every screen that waits on the network shows a
  /// progress indicator, which never settles, and a real server takes real time.
  Future<void> pumpUntil(
    WidgetTester tester,
    String what,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 150));
    }
    fail('timed out waiting for: $what');
  }

  bool visible(String text) => find.text(text).evaluate().isNotEmpty;

  /// Named so it cannot be confused with the `contains` *matcher*: shadowing that was
  /// how an assertion about an outbox payload silently became an assertion about the
  /// screen.
  bool showsText(String text) =>
      find.textContaining(text).evaluate().isNotEmpty;

  /// Opens the account/masters area, which is "More" on a phone and "Masters" on Windows.
  Future<void> openSetUp(WidgetTester tester) async {
    final label = boot.shellKind.name == 'mobile' ? 'More' : 'Masters';
    await pumpUntil(tester, 'the $label destination', () => visible(label));
    await tester.tap(find.text(label).last);
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openHierarchy(WidgetTester tester) async {
    await openSetUp(tester);
    // Confirm we actually arrived. The Windows *Overview* placeholder names both
    // properties in its copy, so asserting "the other property is not on
    // screen" from the wrong page passes or fails for reasons that have nothing to do
    // with scope.
    await pumpUntil(
      tester,
      'the Masters surface',
      () => visible('Hierarchy'),
      timeout: const Duration(seconds: 20),
    );
    await tester.tap(find.text('Hierarchy').last);
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> openSection(WidgetTester tester, String label) async {
    await openSetUp(tester);
    await pumpUntil(tester, 'the $label section', () => visible(label));
    await tester.tap(find.text(label).last);
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Signs out the way a user does: through the account control, confirming the dialog.
  Future<void> signOutThroughTheUi(WidgetTester tester) async {
    await openSetUp(tester);
    await pumpUntil(tester, 'the account control', () => visible('Sign out'));
    await tester.tap(find.text('Sign out').last);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await pumpUntil(
      tester,
      'the sign-in screen',
      () => find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
    );
  }

  /// Signs [email] in, ending any session already open on this installation first.
  ///
  /// Each test in a phase shares one process and one installation, exactly as a shared
  /// workstation does, so "already signed in as somebody else" is the normal case rather
  /// than an error.
  Future<void> signIn(WidgetTester tester, String email) async {
    // Wait for start-up to settle first. A restored session takes a round trip, and
    // deciding before it lands is how this helper used to sign in on top of somebody
    // else's open session.
    await pumpUntil(
      tester,
      'start-up to settle on either the sign-in screen or a shell',
      () =>
          find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty ||
          visible('SIGNED IN') ||
          visible('Home') ||
          visible('Overview'),
      timeout: const Duration(seconds: 60),
    );

    if (visible('SIGNED IN') || visible('Home') || visible('Overview')) {
      // The dedicated `signout` phase proves the control itself. Here the point is only
      // to reach a clean sign-in screen, so the session is ended through the same
      // notifier the control calls.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      await container.read(sessionProvider.notifier).signOut();
      await pumpUntil(
        tester,
        'the sign-in screen after signing the previous user out',
        () =>
            find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
      );
    }

    final password = _identities[email];
    expect(
      password,
      isNotNull,
      reason: 'no development identity compiled in for $email',
    );
    expect(password, isNotEmpty, reason: 'empty password define for $email');

    await pumpUntil(tester, 'the sign-in screen', () => visible('Sign in'));

    // The labels sit above the fields as their own Text widgets rather than as
    // `labelText`, so the fields are addressed by position: email, then password.
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), email);
    await tester.pump();
    await tester.enterText(fields.at(1), password!);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    // A failed sign-in must fail the test here, with the message the user would see,
    // rather than 40 seconds later as "the shell never appeared".
    await tester.pump(const Duration(seconds: 3));
    final notice = find.textContaining('do not match');
    if (notice.evaluate().isNotEmpty) {
      fail(
        'sign-in refused for $email: ${(notice.evaluate().first.widget as Text).data}',
      );
    }
  }

  /// The shell is only ever reached through a session the server vouched for.
  Future<void> expectSignedIn(WidgetTester tester, String email) async {
    await pumpUntil(
      tester,
      'the application shell for $email',
      () => visible('SIGNED IN') || visible('Home') || visible('Overview'),
      timeout: const Duration(seconds: 60),
    );
  }

  // ── Phases ──────────────────────────────────────────────────

  group('owner', skip: _phase != 'owner', () {
    testWidgets('signs in, and the server states the whole company', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final store = AuthorityStore(boot.database);
      final owner = await store.ownerUserId();
      expect(owner, isNotNull, reason: 'authority must be cached per user');

      final snapshot = await store.loadFor(owner!);
      expect(snapshot, isNotNull);
      expect(
        snapshot!.holdsOrgWideGrant,
        isTrue,
        reason: 'only the Owner may hold an unscoped grant (D-025)',
      );
    });

    testWidgets('both properties arrive from the server', (tester) async {
      await launch(tester);
      await expectSignedIn(tester, 'giridhar@hki.com');

      final units = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(units.map((u) => u.id).toSet(), {_ccr, _hki});

      await openHierarchy(tester);
      await pumpUntil(
        tester,
        'both business units on screen',
        () =>
            showsText('Crystal Canopy Rooftop') &&
            showsText('Hotel Krishna Imperial'),
      );
    });

    testWidgets('vendors and payment methods load', (tester) async {
      await launch(tester);
      await expectSignedIn(tester, 'giridhar@hki.com');

      final methods = await boot.database
          .select(boot.database.paymentMethods)
          .get();
      expect(methods, isNotEmpty, reason: 'organisation-global company data');

      await openSection(tester, 'Vendors');
      await pumpUntil(
        tester,
        'the vendors surface',
        () => showsText('Vendor') || showsText('vendor'),
      );
    });

    testWidgets('tax says no rule is configured, and invents none', (
      tester,
    ) async {
      await launch(tester);
      await expectSignedIn(tester, 'giridhar@hki.com');

      final rules = await boot.database
          .select(boot.database.revenueTaxRates)
          .get();
      expect(rules, isEmpty, reason: 'the development project has no tax rule');

      await openSection(tester, 'Tax rules');
      // The approved equivalent of "No rule configured": the screen says a rule is
      // absent, and says what that means for revenue, in two places.
      await pumpUntil(
        tester,
        'the no-rule state',
        () => showsText('No rule in force today'),
        timeout: const Duration(seconds: 60),
      );
      expect(showsText('No tax rule configured'), isTrue);
      expect(showsText('no tax extracted until one is set'), isTrue);

      // "No configured rule" and "a configured zero rate" are different facts.
      expect(showsText('5%'), isFalse);
      expect(showsText('18%'), isFalse);
      expect(showsText('0%'), isFalse);
      expect(showsText('exempt'), isFalse);
    });
  });

  group('session', skip: _phase != 'session', () {
    testWidgets('a fresh session controller restores without credentials', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      // A second controller over the same dependencies is what a relaunch produces:
      // it reads the persisted session out of the platform-secure store and asks the
      // server again. Nothing is typed.
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);

      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();
      final restored = container.read(sessionProvider);
      expect(
        restored,
        isA<SessionReady>(),
        reason: 'the token in secure storage must survive a relaunch',
      );
      expect((restored as SessionReady).email, 'giridhar@hki.com');
    });
  });

  group('signout', skip: _phase != 'signout', () {
    testWidgets('the account control ends the session and keeps the queue', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: _queuedMutationId,
          entityType: 'expense_category',
          entityId: _kirana,
          op: MutationOp.update,
          payload: const {'name': 'Queued Before Sign Out'},
          baseRowVersion: 1,
          createdAt: DateTime.now().toUtc(),
        ),
        now: DateTime.now().toUtc(),
      );

      await openSetUp(tester);
      await pumpUntil(tester, 'the account control', () => visible('Sign out'));
      await tester.tap(find.text('Sign out').last);
      await tester.pump(const Duration(milliseconds: 600));
      expect(showsText('still waiting to reach the server'), isTrue);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));

      await pumpUntil(
        tester,
        'the sign-in screen',
        () =>
            find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
      );

      expect(
        await AuthorityStore(boot.database).ownerUserId(),
        isNull,
        reason: 'cached authority must not outlive the session that earned it',
      );
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      expect(
        queued.where((q) => q.mutationId == _queuedMutationId),
        hasLength(1),
        reason: 'signing out never destroys unsent work',
      );
    });
  });

  // Steps 3, 10 and 14: the whole point of the user-switch rules, in one process on one
  // installation — Owner first, so the Hotel Krishna cache genuinely exists before the
  // Crystal Canopy Manager arrives.
  group('user-switch', skip: _phase != 'user-switch', () {
    testWidgets('Owner → CCR Manager: no cache and no authority is inherited', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final ownerUnits = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(
        ownerUnits.map((u) => u.id).toSet(),
        {_ccr, _hki},
        reason: 'the Owner really did cache both properties',
      );
      final ownerId = await AuthorityStore(boot.database).ownerUserId();
      expect(ownerId, isNotNull);

      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: _ownerQueuedMutationId,
          entityType: 'expense_category',
          entityId: _kirana,
          op: MutationOp.update,
          payload: const {'name': "Owner's Queued Work"},
          baseRowVersion: 1,
          createdAt: DateTime.now().toUtc(),
          actorUserId: ownerId,
        ),
        now: DateTime.now().toUtc(),
      );

      await signOutThroughTheUi(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      // 1. The previous user's protected hierarchy is gone.
      final units = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(
        units.map((u) => u.id).toSet(),
        {_ccr},
        reason: "the Owner's Hotel Krishna data must not be browsable",
      );
      final departments = await boot.database
          .select(boot.database.departments)
          .get();
      expect(departments.every((d) => d.businessUnitId == _ccr), isTrue);

      // 2. The authority snapshot belongs to the new user, not the old one.
      final store = AuthorityStore(boot.database);
      final nowOwner = await store.ownerUserId();
      expect(nowOwner, isNot(ownerId));
      expect(
        await store.loadFor(ownerId!),
        isNull,
        reason: "one user's snapshot can never satisfy another's load",
      );
      final mine = await store.loadFor(nowOwner!);
      expect(mine!.holdsOrgWideGrant, isFalse);
      expect(mine.scopedUnits, {_ccr});

      // 3. The queue is preserved and still belongs to whoever queued it.
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      final ownersEntry = queued.firstWhere(
        (q) => q.mutationId == _ownerQueuedMutationId,
      );
      expect(
        ownersEntry.actorUserId,
        ownerId,
        reason: 'D-050 — an outbox entry keeps its original actor',
      );
      expect(ownersEntry.actorUserId, isNot(nowOwner));

      // 4. The UI agrees with the data.
      await openHierarchy(tester);
      await pumpUntil(
        tester,
        'Crystal Canopy alone',
        () => showsText('Crystal Canopy Rooftop'),
      );
      expect(showsText('Hotel Krishna Imperial'), isFalse);
      expect(
        visible('Administration'),
        isFalse,
        reason: 'no users.manage capability — and no role name was consulted',
      );
    });

    testWidgets('CCR Manager → HKI Manager: the swap is symmetric', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');
      expect(
        (await boot.database.select(boot.database.businessUnits).get())
            .map((u) => u.id)
            .toSet(),
        {_ccr},
      );

      await signOutThroughTheUi(tester);
      await signIn(tester, 'hki.manager@example.com');
      await expectSignedIn(tester, 'hki.manager@example.com');

      final units = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(
        units.map((u) => u.id).toSet(),
        {_hki},
        reason: 'Crystal Canopy must not remain browsable to a Hotel manager',
      );

      final methods = await boot.database
          .select(boot.database.paymentMethods)
          .get();
      expect(
        methods,
        isNotEmpty,
        reason: 'company-wide reference data is not scoped (D-049)',
      );
    });
  });

  group('data-entry', skip: _phase != 'data-entry', () {
    testWidgets('sees permitted reference data and no master actions', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'data.entry@example.com');
      await expectSignedIn(tester, 'data.entry@example.com');

      await openHierarchy(tester);
      await pumpUntil(
        tester,
        'their permitted hierarchy',
        () => showsText('Crystal Canopy Rooftop'),
      );

      expect(visible('Rename'), isFalse);
      expect(visible('Archive'), isFalse);
      expect(visible('Administration'), isFalse);
    });

    testWidgets('the server refuses the mutation anyway, in plain language', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'data.entry@example.com');
      await expectSignedIn(tester, 'data.entry@example.com');

      // Straight past the interface, exactly as a modified client would.
      final gateway = MasterGateway(Supabase.instance.client);
      final outcome = await gateway.rename(
        entityType: 'expense_category',
        entityId: _kirana,
        newName: 'Attempted By Data Entry',
        baseRowVersion: 1,
      );

      expect(
        outcome.isRefused,
        isTrue,
        reason: 'hiding a button has never been security',
      );
      final refusal = outcome.refusalOrNull!;
      expect(refusal.kind, RefusalKind.missingCapability);
      expect(refusal.message, 'You do not have permission to do this.');
      expect(refusal.message, isNot(contains('SQLSTATE')));
      expect(refusal.message, isNot(contains('permission denied')));
      expect(refusal.message, isNot(contains('42501')));
    });
  });

  // Steps 5, 6 and 14. The host takes the device's network away part-way through; the
  // test waits for that to happen rather than assuming it already has.
  group('offline', skip: _phase != 'offline', () {
    testWidgets('cached authority survives, marked stale, cache intact', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      final before = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(before.map((u) => u.id).toSet(), {_ccr});

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      // Wait for the host to pull the network, then confirm the session degrades to
      // stale rather than either failing or pretending to be current.
      var state = container.read(sessionProvider);
      final deadline = DateTime.now().add(const Duration(seconds: 240));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(sessionProvider.notifier).refreshAuthority();
        state = container.read(sessionProvider);
        if (state is SessionReady && state.isStale) break;
        await tester.pump(const Duration(seconds: 2));
      }

      expect(
        state,
        isA<SessionReady>(),
        reason: 'a verified user keeps their permitted workflows offline',
      );
      final ready = state as SessionReady;
      expect(
        ready.isStale,
        isTrue,
        reason: 'and is told the access is not fresh',
      );
      expect(ready.authority.userId, isNotNull);
      expect(
        ready.email,
        'ccr.manager@example.com',
        reason: 'the cached authority belongs to this user',
      );

      final after = await boot.database
          .select(boot.database.businessUnits)
          .get();
      expect(
        after.map((u) => u.id).toSet(),
        {_ccr},
        reason: 'a network failure is not a statement of scope (D-048)',
      );

      // A privileged mutation queued offline is pending, never final.
      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: _queuedMutationId,
          entityType: 'expense_category',
          entityId: _kirana,
          op: MutationOp.update,
          payload: const {'name': 'Queued While Offline'},
          baseRowVersion: 1,
          createdAt: DateTime.now().toUtc(),
        ),
        now: DateTime.now().toUtc(),
      );
      final status = await boot.outbox.statusOf(_queuedMutationId);
      expect(status, OutboxStatus.pending);
      expect(status!.userVisibleState, SyncState.pendingSync);
      expect(status.userVisibleState.isOnServer, isFalse);
    });

    testWidgets('a user who has never verified here gets nothing at all', (
      tester,
    ) async {
      // The exact precondition: a real authenticated session, an authority store with
      // nothing in it for this user, and no way to ask.
      await AuthorityStore(boot.database).clear();

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      final state = container.read(sessionProvider);
      expect(
        state,
        isA<AuthorityUnverified>(),
        reason: 'fails closed: authenticated is not authorised',
      );
      final blocked = state as AuthorityUnverified;
      expect(
        blocked.message,
        'Unable to verify your access. Connect to the internet and try again.',
      );
      expect(state.grantsAccess, isFalse);
      expect(
        state.principal.grants,
        isEmpty,
        reason: 'no fallback Owner, no fallback Manager, no guessed capability',
      );
    });
  });

  // Step 7: the full D-048 scenario, driven through the app. The host revokes the scope
  // while the device is offline and restores the network afterwards.
  group('revoked', skip: _phase != 'revoked', () {
    testWidgets('authority first, then purge, then a terminal refusal', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');

      expect(
        (await boot.database.select(boot.database.businessUnits).get())
            .map((u) => u.id)
            .toSet(),
        {_ccr},
        reason: 'Crystal Canopy is cached while the scope is held',
      );

      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: _queuedMutationId,
          entityType: 'expense_category',
          entityId: _kirana,
          op: MutationOp.update,
          payload: const {'name': 'Queued While Authorised'},
          baseRowVersion: 1,
          createdAt: DateTime.now().toUtc(),
        ),
        now: DateTime.now().toUtc(),
      );
      expect(
        await boot.outbox.statusOf(_queuedMutationId),
        OutboxStatus.pending,
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      // The host is meanwhile revoking the Crystal Canopy grant as the Owner. Refresh
      // authority — which is what happens on reconnect — until the server says the
      // scope is gone. Authority is asked *before* anything privileged is pushed.
      var purged = false;
      final deadline = DateTime.now().add(const Duration(seconds: 300));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(sessionProvider.notifier).refreshAuthority();
        final state = container.read(sessionProvider);
        if (state is SessionReady &&
            !state.isStale &&
            state.authority.scopedUnits.isEmpty) {
          purged = true;
          break;
        }
        await tester.pump(const Duration(seconds: 3));
      }
      expect(
        purged,
        isTrue,
        reason: 'the server must positively confirm the scope was removed',
      );

      // The server-owned Crystal Canopy cache goes…
      expect(
        await boot.database.select(boot.database.businessUnits).get(),
        isEmpty,
      );
      expect(
        await boot.database.select(boot.database.departments).get(),
        isEmpty,
      );
      // …organisation-global rows stay…
      expect(
        await boot.database.select(boot.database.paymentMethods).get(),
        isNotEmpty,
        reason: 'a payment method is company data, not property data (D-049)',
      );
      // …and the queue is untouched.
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      expect(
        queued.where((q) => q.mutationId == _queuedMutationId),
        hasLength(1),
      );

      // The queued mutation now reaches the server on current authority.
      final gateway = MasterGateway(Supabase.instance.client);
      final outcome = await gateway.rename(
        entityType: 'expense_category',
        entityId: _kirana,
        newName: 'Queued While Authorised',
        baseRowVersion: 1,
        mutationId: _queuedMutationId,
      );
      expect(
        outcome.isRefused,
        isTrue,
        reason: 'authority at delivery time wins',
      );
      final refusal = outcome.refusalOrNull!;
      expect(refusal.kind.isAuthorityRefusal, isTrue);
      expect(refusal.kind.isAutomaticallyRetryable, isFalse);
      expect(refusal.message, isNot(contains('SQLSTATE')));

      await boot.outbox.updateStatus(
        _queuedMutationId,
        status: OutboxStatus.rejected,
        lastError: refusal.message,
      );
      final status = await boot.outbox.statusOf(_queuedMutationId);
      expect(status, OutboxStatus.rejected);
      expect(status!.userVisibleState, SyncState.rejected);
      expect(status.isAutomaticallyRetryable, isFalse);

      final rows = await boot.database.select(boot.database.syncOutbox).get();
      expect(
        rows.singleWhere((r) => r.mutationId == _queuedMutationId).payload,
        contains('Queued While Authorised'),
        reason: 'the refused attempt stays inspectable',
      );

      // And the property is gone from the interface.
      await openHierarchy(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(showsText('Crystal Canopy Rooftop'), isFalse);
    });
  });

  // Step 13: a deactivated account loses access at the next refresh, and never falls
  // back to the authority it had cached.
  group('deactivated', skip: _phase != 'deactivated', () {
    testWidgets('a revoked account expires rather than continuing on cache', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'accountant@example.com');
      await expectSignedIn(tester, 'accountant@example.com');
      expect(
        await AuthorityStore(boot.database).ownerUserId(),
        isNotNull,
        reason: 'authority was cached while the account was live',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      // The host deactivates the account through the Owner's own administration path.
      var expired = false;
      final deadline = DateTime.now().add(const Duration(seconds: 300));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(sessionProvider.notifier).refreshAuthority();
        if (container.read(sessionProvider) is SessionExpired) {
          expired = true;
          break;
        }
        await tester.pump(const Duration(seconds: 3));
      }

      expect(
        expired,
        isTrue,
        reason:
            'the server declining to treat somebody as an actor is a statement',
      );
      final state = container.read(sessionProvider);
      expect(state.grantsAccess, isFalse);
      expect(state.principal.grants, isEmpty);
      expect(
        await AuthorityStore(boot.database).ownerUserId(),
        isNull,
        reason: 'stale authority must not be left behind to fall back on',
      );
    });
  });

  group('conflict', skip: _phase != 'conflict', () {
    testWidgets('a stale base version is a Conflict, never a Rejection', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final gateway = MasterGateway(Supabase.instance.client);
      final department = _seedId('dept:CCR/FB');
      final startVersion = await _currentVersion(department);

      // Move the server on by one version, the way a second authenticated client would.
      final first = await gateway.rename(
        entityType: 'department',
        entityId: department,
        newName: 'F&B / Kitchen',
        baseRowVersion: startVersion,
        acknowledged: true,
      );
      expect(
        first.isOk,
        isTrue,
        reason: 'the Owner may rename: ${first.refusalOrNull?.message}',
      );
      final moved = first.valueOrNull!['row_version'] as int;
      expect(moved, greaterThan(startVersion));

      // Now submit a *new* intent based on the version this client still held.
      final stale = await gateway.rename(
        entityType: 'department',
        entityId: department,
        newName: 'Stale Intent',
        baseRowVersion: startVersion,
        acknowledged: true,
      );

      expect(stale.isRefused, isTrue);
      final refusal = stale.refusalOrNull!;
      expect(
        refusal.kind,
        RefusalKind.versionConflict,
        reason: 'KM003 — resolvable by a person, not a terminal rejection',
      );
      expect(
        refusal.kind.isAuthorityRefusal,
        isFalse,
        reason: 'a conflict is about the record, not about permission',
      );
      expect(refusal.message, isNot(contains('SQLSTATE')));

      // The canonical server state is the one that was applied, not the stale one.
      final row = await Supabase.instance.client
          .from('departments')
          .select('name,row_version')
          .eq('id', department)
          .single();
      expect(row['name'], isNot('Stale Intent'));
      expect(row['row_version'], moved);

      // And the two states are distinguishable to a user: a conflict is not a rejection.
      expect(OutboxStatus.conflict.userVisibleState, SyncState.conflict);
      expect(OutboxStatus.rejected.userVisibleState, SyncState.rejected);
      expect(
        SyncState.conflict.label,
        isNot(SyncState.rejected.label),
        reason: 'Rejected and Conflict must read as different states',
      );
    });
  });
  // Step 11. Two real clients, one on each platform, against one server. `propagate-b`
  // signs in and holds the current label, then waits; `propagate-a` runs on the other
  // platform part-way through that wait and makes the change; `propagate-b` refreshes and
  // watches it arrive.
  // Step 9's login checks. Keyboard-first, because the Windows build is a finance
  // workstation and a form that can only be driven by mouse is a defect there.
  group('login-ux', skip: _phase != 'login-ux', () {
    testWidgets('the password is obscured until the user asks to see it', (
      tester,
    ) async {
      await launch(tester);
      await pumpUntil(
        tester,
        'the sign-in screen',
        () =>
            find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );

      TextField passwordField() =>
          tester.widgetList<TextField>(find.byType(TextField)).last;

      expect(passwordField().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(passwordField().obscureText, isFalse);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(passwordField().obscureText, isTrue);
    });

    testWidgets('Tab and Shift-Tab move between the fields, visibly', (
      tester,
    ) async {
      await launch(tester);
      await pumpUntil(
        tester,
        'the sign-in screen',
        () =>
            find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );

      final fields = find.byType(TextFormField);
      await tester.tap(fields.at(0));
      await tester.pump();
      final email = Focus.of(tester.element(fields.at(0)));
      expect(email.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(tester.element(fields.at(1))).hasFocus,
        isTrue,
        reason: 'Tab must reach the password field',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        Focus.of(tester.element(fields.at(0))).hasFocus,
        isTrue,
        reason: 'Shift-Tab must come back',
      );
    });

    testWidgets('a wrong password is refused in plain language, and Enter '
        'submits the form', (tester) async {
      await launch(tester);
      await pumpUntil(
        tester,
        'the sign-in screen',
        () =>
            find.widgetWithText(FilledButton, 'Sign in').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'giridhar@hki.com');
      await tester.pump();
      await tester.enterText(fields.at(1), 'not-the-password');
      await tester.pump();

      // Enter in the password field submits, rather than doing nothing.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpUntil(
        tester,
        'the refusal notice',
        () => showsText('do not match'),
        timeout: const Duration(seconds: 45),
      );

      expect(
        showsText('That email address and password do not match an account.'),
        isTrue,
      );
      expect(showsText('SQLSTATE'), isFalse);
      expect(showsText('invalid_grant'), isFalse);
      expect(showsText('400'), isFalse);
      expect(
        find.widgetWithText(FilledButton, 'Sign in'),
        findsOneWidget,
        reason: 'a refusal leaves the user on the form, able to try again',
      );
    });
  });

  group('propagate-a', skip: _phase != 'propagate-a', () {
    testWidgets('client A renames cosmetically and archives a leaf', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final gateway = MasterGateway(Supabase.instance.client);

      final paneer = await _row('expense_categories', _paneer);
      final rename = await gateway.rename(
        entityType: 'expense_category',
        entityId: _paneer,
        newName: _paneerRenamed,
        baseRowVersion: paneer['row_version'] as int,
        acknowledged: true,
      );
      expect(
        rename.isOk,
        isTrue,
        reason: 'rename refused: ${rename.refusalOrNull?.message}',
      );
      expect(
        rename.valueOrNull!['row_version'],
        greaterThan(paneer['row_version'] as int),
      );

      final milk = await _row('expense_categories', _milk);
      final archive = await gateway.archive(
        entityType: 'expense_category',
        entityId: _milk,
        baseRowVersion: milk['row_version'] as int,
      );
      expect(
        archive.isOk,
        isTrue,
        reason: 'archive refused: ${archive.refusalOrNull?.message}',
      );

      // The immutable code never moves, whatever the label says (D-035).
      final after = await _row('expense_categories', _paneer);
      expect(after['code'], paneer['code']);
      expect(after['name'], _paneerRenamed);
    });
  });

  group('propagate-b', skip: _phase != 'propagate-b', () {
    testWidgets("the other client's change arrives, once, with the same id", (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final db = boot.database;
      final held = (await db.select(db.expenseCategories).get()).singleWhere(
        (c) => c.id == _paneer,
      );
      final heldVersion = held.rowVersion;
      final heldCode = held.code;
      expect(
        held.name,
        _paneerOriginalName,
        reason: 'client B starts out holding the old label',
      );

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          sessionProvider.overrideWith(() => SessionController(boot.session!)),
        ],
      );
      addTearDown(container.dispose);
      await (container.read(sessionProvider.notifier) as SessionController)
          .restore();

      // Client A is renaming it right now, on the other platform.
      var arrived = false;
      final deadline = DateTime.now().add(const Duration(seconds: 300));
      while (DateTime.now().isBefore(deadline)) {
        await container.read(sessionProvider.notifier).refreshAuthority();
        final rows = await db.select(db.expenseCategories).get();
        final match = rows.where((c) => c.id == _paneer).toList();
        if (match.length == 1 && match.single.name == _paneerRenamed) {
          arrived = true;
          break;
        }
        await tester.pump(const Duration(seconds: 3));
      }
      expect(arrived, isTrue, reason: 'the rename never reached this client');

      final rows = await db.select(db.expenseCategories).get();
      final now = rows.where((c) => c.id == _paneer).toList();
      expect(
        now,
        hasLength(1),
        reason: 'a rename must not create a second master',
      );
      expect(
        now.single.code,
        heldCode,
        reason: 'the immutable code never moves',
      );
      expect(
        now.single.rowVersion,
        greaterThan(heldVersion),
        reason: 'the version the server assigned came with it',
      );

      // The archived leaf arrived as archived, and is out of the picker for new use.
      final milk = rows.singleWhere((c) => c.id == _milk);
      expect(milk.archivedAt, isNotNull);
      expect(
        milk.name,
        isNotEmpty,
        reason: 'archiving keeps the record; history stays readable',
      );

      // A stale intent from this client is a conflict, not a rejection.
      final gateway = MasterGateway(Supabase.instance.client);
      final stale = await gateway.rename(
        entityType: 'expense_category',
        entityId: _paneer,
        newName: 'Stale From Client B',
        baseRowVersion: heldVersion,
        acknowledged: true,
      );
      expect(stale.isRefused, isTrue);
      expect(stale.refusalOrNull!.kind, RefusalKind.versionConflict);

      final server = await _row('expense_categories', _paneer);
      expect(server['name'], _paneerRenamed);
    });
  });

  group('propagate-restore', skip: _phase != 'propagate-restore', () {
    testWidgets('the development fixtures are put back', (tester) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final gateway = MasterGateway(Supabase.instance.client);

      final paneer = await _row('expense_categories', _paneer);
      if (paneer['name'] != _paneerOriginalName) {
        final back = await gateway.rename(
          entityType: 'expense_category',
          entityId: _paneer,
          newName: _paneerOriginalName,
          baseRowVersion: paneer['row_version'] as int,
          acknowledged: true,
        );
        expect(back.isOk, isTrue, reason: '${back.refusalOrNull?.message}');
      }

      final milk = await _row('expense_categories', _milk);
      if (milk['archived_at'] != null) {
        final restored = await gateway.restore(
          entityType: 'expense_category',
          entityId: _milk,
          baseRowVersion: milk['row_version'] as int,
        );
        expect(
          restored.isOk,
          isTrue,
          reason: '${restored.refusalOrNull?.message}',
        );
      }

      expect(
        (await _row('expense_categories', _paneer))['name'],
        _paneerOriginalName,
      );
      expect((await _row('expense_categories', _milk))['archived_at'], isNull);
    });
  });
}

/// One row, read the way any client would.
Future<Map<String, dynamic>> _row(String table, String id) async =>
    await Supabase.instance.client
        .from(table)
        .select('id,code,name,row_version,archived_at')
        .eq('id', id)
        .single();

/// The department's current `row_version`, read the way any client would.
Future<int> _currentVersion(String departmentId) async {
  final row = await Supabase.instance.client
      .from('departments')
      .select('row_version')
      .eq('id', departmentId)
      .single();
  return row['row_version'] as int;
}
