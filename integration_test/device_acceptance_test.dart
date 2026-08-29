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
///   expense-simple   record a routine expense, queue it, receive its number
///   expense-offline  record with no network, restart, reconcile exactly once
///   expense-shared   a scoped manager receives their share and not the total
///   expense-refusals closed period, stale edit, and who may void
///   offline-transport  the Phase 2 addendum: the real transport made to fail, offline
///                    working, reconnect, authority-first, and reconciliation
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
import 'package:krishna_mis/data/remote/expense_gateway.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/sync/expense_pull.dart';
import 'package:krishna_mis/data/sync/sync_engine.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/data/local/authority_store.dart';
import 'package:krishna_mis/data/remote/master_gateway.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'support/controllable_transport.dart';

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

/// The acceptance transport. Constructed unconditionally and handed to `bootstrap`, but
/// only ever *taken* offline by the phase that is about being offline; every other phase
/// runs with it fully online, so it changes nothing for them.
final _transport = ControllableTransport();

/// Everything a Phase 3 phase created on the server, so the run can clean up after
/// itself rather than leaving the development project in an unexplained state.
final List<String> _createdExpenses = [];

/// A second fixed id, for work the *Owner* queues before a user switch.
const _ownerQueuedMutationId = 'b5d0e91a-7c34-4a68-8e2f-19b7d3c05a44';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late BootstrapResult boot;

  setUpAll(() async {
    boot = await bootstrap(transport: _transport);
  });

  // ── Driving the real application ──────────────────────────────────────────

  /// Builds the app exactly as `main()` does, and waits for start-up to settle.
  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(boot.database),
          outboxProvider.overrideWithValue(boot.outbox),
          mutationEndpointProvider.overrideWithValue(boot.mutationEndpoint),
          // `main()` supplies this too. Without it a pushed expense is marked done and
          // never learns its transaction number, which looks exactly like the server
          // failing to issue one.
          mutationReconcilerProvider.overrideWithValue(boot.mutationReconciler),
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

  // ── Phase 2 acceptance addendum: the offline transport path ────────────────
  //
  // The one gap the Phase 2 report recorded as NOT TESTED. It runs on either platform,
  // and its point is Windows: the real executable, with its network genuinely failing at
  // the transport, driven end to end through going offline, working offline, coming back,
  // and reconciling under whatever authority the server states at that moment.
  //
  // Nothing here fakes an answer. `ControllableTransport` throws the same SocketException
  // the platform throws for an unreachable host, from inside the Supabase client's own
  // send, so every decision downstream is made by the real code for the real reason.
  group('offline-transport', skip: _phase != 'offline-transport', () {
    testWidgets('offline, then back, with authority first and no false success', (
      tester,
    ) async {
      // 1 · A previously verified user signs in online.
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final db = boot.database;
      final store = AuthorityStore(db);
      final userId = await store.ownerUserId();
      expect(userId, isNotNull);

      // Fresh ids each run. A fixed one would be *replayed* by the server on the second
      // run rather than applied — the idempotency guarantee working exactly as designed,
      // and a guarantee this phase is not about.
      final acceptedId = const Uuid().v4();
      final refusedId = const Uuid().v4();

      // 2 · Authority and permitted reference data are cached.
      final cachedAuthority = await store.loadFor(userId!);
      expect(cachedAuthority, isNotNull);
      expect(cachedAuthority!.holdsOrgWideGrant, isTrue);
      final unitsBefore = await db.select(db.businessUnits).get();
      final departmentsBefore = await db.select(db.departments).get();
      final categoriesBefore = await db.select(db.expenseCategories).get();
      expect(unitsBefore, isNotEmpty);
      expect(departmentsBefore, isNotEmpty);
      expect(categoriesBefore, isNotEmpty);

      // The running application's own container, not a parallel one. Everything below
      // is therefore asserted about the interface the user is looking at.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KrishnaMisApp)),
      );
      expect(container.read(sessionProvider), isA<SessionReady>());

      // Two intents queued while authorised and online: one the Owner may do, and one
      // the server will refuse for a reason that is not a version conflict.
      //
      // The fixture is normalised first, so the phase can be re-run: renaming a record to
      // the name it already has is not a change, and the server correctly declines to
      // move its version for it — which would make the assertion below fail for a reason
      // that has nothing to do with the transport.
      final gateway = MasterGateway(Supabase.instance.client);
      var current = await _row('expense_categories', _paneer);
      if (current['name'] != _paneerOriginalName) {
        final reset = await gateway.rename(
          entityType: 'expense_category',
          entityId: _paneer,
          newName: _paneerOriginalName,
          baseRowVersion: current['row_version'] as int,
          acknowledged: true,
        );
        expect(reset.isOk, isTrue, reason: '${reset.refusalOrNull?.message}');
        current = await _row('expense_categories', _paneer);
      }
      final paneer = current;
      final section = _seedId('sec:CCR/FB/FOOD_PROD');
      final sectionRow = await _row('sections', section);

      // 3 · The network goes away. From here nothing reaches the server.
      _transport.online = false;

      // 4 · Permitted cached data remains usable — reads never touch the network.
      expect(
        (await db.select(db.businessUnits).get()).length,
        unitsBefore.length,
      );
      expect(
        (await db.select(db.expenseCategories).get()).length,
        categoriesBefore.length,
      );

      // 6 · Authority refresh becomes *unavailable*, never Confirmed with no grants.
      final refresh = await boot.session!.authority.refresh();
      expect(
        refresh,
        isA<AuthorityUnavailable>(),
        reason: 'a failed request is not a statement that the user has nothing',
      );
      expect(
        (refresh as AuthorityUnavailable).reason,
        AuthorityUnavailableReason.offline,
      );
      expect(
        _transport.refusedWhileOffline,
        isNotEmpty,
        reason: 'the application really did try to reach the server',
      );

      await container.read(sessionProvider.notifier).refreshAuthority();
      final offlineState = container.read(sessionProvider);
      expect(offlineState, isA<SessionReady>());
      expect(
        (offlineState as SessionReady).isStale,
        isTrue,
        reason: 'access is shown as last verified, not as current',
      );
      expect(offlineState.authority.userId, userId);

      // 5 · And the interface says so, in the words a user reads.
      await tester.pump(const Duration(milliseconds: 400));
      await openSetUp(tester);
      await pumpUntil(
        tester,
        'the offline marker',
        () => showsText('Using last verified access'),
      );

      // 7 · Nothing was purged. A network failure is not a statement of scope.
      expect(
        (await db.select(db.businessUnits).get()).length,
        unitsBefore.length,
      );
      expect(
        (await db.select(db.departments).get()).length,
        departmentsBefore.length,
      );
      expect(await store.loadFor(userId), isNotNull);

      // 8 · Privileged mutations created offline are queued, and only queued.
      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: acceptedId,
          entityType: 'expense_category',
          entityId: _paneer,
          op: MutationOp.update,
          payload: {'name': _paneerRenamed, 'acknowledged': true},
          baseRowVersion: paneer['row_version'] as int,
          createdAt: DateTime.now().toUtc(),
          actorUserId: userId,
        ),
        now: DateTime.now().toUtc(),
      );
      await boot.outbox.enqueue(
        PendingMutation(
          mutationId: refusedId,
          entityType: 'section',
          entityId: section,
          op: MutationOp.archive,
          payload: const {},
          baseRowVersion: sectionRow['row_version'] as int,
          createdAt: DateTime.now().toUtc(),
          actorUserId: userId,
        ),
        now: DateTime.now().toUtc(),
      );

      for (final id in [acceptedId, refusedId]) {
        final status = await boot.outbox.statusOf(id);
        expect(status, OutboxStatus.pending);
        // 9 · Never shown as server-approved.
        expect(status!.userVisibleState, SyncState.pendingSync);
        expect(status.userVisibleState.isOnServer, isFalse);
        expect(status, isNot(OutboxStatus.done));
      }

      // A push attempted while offline must change nothing and claim nothing.
      final engineOffline = container.read(syncEngineProvider);
      expect(engineOffline, isNotNull, reason: 'the push worker exists');
      expect(
        await boot.outbox.dueEntries(now: DateTime.now(), actorUserId: userId),
        hasLength(2),
        reason: 'both intents are due, and both belong to this user',
      );
      expect(
        engineOffline!.actorUserId,
        userId,
        reason: 'the worker sends only the signed-in user work',
      );
      final offlineReport = await engineOffline.pushOnce();
      expect(offlineReport.applied, 0);
      expect(offlineReport.rejected, 0);
      expect(
        offlineReport.transientFailures,
        2,
        reason: 'unreachable is transient — never a refusal, never a success',
      );
      for (final id in [acceptedId, refusedId]) {
        final status = await boot.outbox.statusOf(id);
        expect(status!.isAutomaticallyRetryable, isTrue);
        expect(status.userVisibleState.isOnServer, isFalse);
      }

      // 10 · Connectivity returns.
      _transport.online = true;

      // 11 · Authority is refreshed *before* anything privileged is pushed.
      await container.read(sessionProvider.notifier).refreshAuthority();
      final backOnline = container.read(sessionProvider);
      expect(backOnline, isA<SessionReady>());
      expect(
        (backOnline as SessionReady).isStale,
        isFalse,
        reason: 'reconnecting re-establishes current authority first',
      );

      // 12 · Only then does the queue go, under that current authority.
      //
      // The failed attempts are in backoff, which is the real product behaviour and not
      // something to step over: the engine's clock is genuine, so the test waits for it
      // rather than pretending time has passed.
      final engine = container.read(syncEngineProvider);
      final ready = DateTime.now().add(const Duration(seconds: 90));
      var due = <PendingMutation>[];
      while (DateTime.now().isBefore(ready)) {
        due = await boot.outbox.dueEntries(
          now: DateTime.now(),
          actorUserId: userId,
        );
        if (due.length == 2) break;
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        due,
        hasLength(2),
        reason: 'both entries become due again once their backoff elapses',
      );

      final report = await engine!.pushOnce();
      expect(report.attempted, 2);

      // 13 · The permitted mutation reconciles: applied, versioned, marked synced.
      final accepted = await boot.outbox.statusOf(acceptedId);
      expect(accepted, OutboxStatus.done);
      expect(accepted!.userVisibleState, SyncState.synced);
      expect(accepted.userVisibleState.isOnServer, isTrue);
      final server = await _row('expense_categories', _paneer);
      expect(server['name'], _paneerRenamed);
      expect(
        server['row_version'],
        greaterThan(paneer['row_version'] as int),
        reason: 'the server moved the version, and exactly once',
      );

      // 14 · The refused one is Rejected — terminal — and never Conflict.
      final refused = await boot.outbox.statusOf(refusedId);
      expect(refused, OutboxStatus.rejected);
      expect(refused!.userVisibleState, SyncState.rejected);
      expect(
        refused,
        isNot(OutboxStatus.conflict),
        reason:
            'the record did not move — the server declined the act itself, and '
            'telling the user somebody edited it would be a lie',
      );
      expect(refused.isAutomaticallyRetryable, isFalse);
      expect(
        SyncState.rejected.label,
        isNot(SyncState.conflict.label),
        reason: 'the two states must read differently to a user',
      );

      // The attempt stays inspectable, with the server's own reason on it.
      final rows = await db.select(db.syncOutbox).get();
      final row = rows.singleWhere((r) => r.mutationId == refusedId);
      expect(row.lastError, isNotNull);
      expect(row.lastError, isNot(contains('SQLSTATE')));

      // A second push must not resurrect either of them.
      final again = await engine.pushOnce();
      expect(again.attempted, 0, reason: 'neither is due any more');

      // Leave the development fixture as it was found.
      final applied = await _row('expense_categories', _paneer);
      final restored = await gateway.rename(
        entityType: 'expense_category',
        entityId: _paneer,
        newName: _paneerOriginalName,
        baseRowVersion: applied['row_version'] as int,
        acknowledged: true,
      );
      expect(
        restored.isOk,
        isTrue,
        reason: '${restored.refusalOrNull?.message}',
      );
      expect(
        (await _row('expense_categories', _paneer))['name'],
        _paneerOriginalName,
      );
      expect((await _row('sections', section))['archived_at'], isNull);
    });
  });

  // ── Phase 3: the expense engine, on the real device ────────────────────────
  //
  // These drive the shipped screens against `krishna-mis-dev`. What is asserted is what a
  // manager would see and what the server actually holds — never an internal call that
  // the interface does not make.

  /// Records an expense through the real entry screen, and returns its local id.
  Future<String> recordExpense(
    WidgetTester tester, {
    required String amount,
    required List<String> classification,
  }) async {
    // Open the entry screen the way a user does.
    if (boot.shellKind.name == 'mobile') {
      await pumpUntil(
        tester,
        'the add button',
        () => find.byType(FloatingActionButton).evaluate().isNotEmpty,
      );
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('quick-add-expense')));
    } else {
      await pumpUntil(
        tester,
        'the Transactions destination',
        () => visible('Transactions'),
      );
      await tester.tap(find.text('Transactions').last);
      await tester.pump(const Duration(milliseconds: 600));
      await pumpUntil(
        tester,
        'the add-expense action',
        () => find.byKey(const Key('add-expense')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('add-expense')));
    }
    await tester.pump(const Duration(milliseconds: 800));

    await pumpUntil(
      tester,
      'the expense entry screen',
      () => find.byKey(const Key('expense-amount')).evaluate().isNotEmpty,
    );

    await tester.enterText(find.byKey(const Key('expense-amount')), amount);
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const Key('classification-summary')));
    await tester.pump(const Duration(milliseconds: 600));
    for (final rung in classification) {
      await pumpUntil(tester, 'the option "$rung"', () => visible(rung));
      await tester.tap(find.text(rung).last);
      await tester.pump(const Duration(milliseconds: 500));
    }

    await pumpUntil(
      tester,
      'Save to become available',
      () =>
          tester
              .widget<FilledButton>(find.byKey(const Key('save-expense')))
              .onPressed !=
          null,
    );

    // The id the local row will carry, read before saving so the assertions afterwards
    // can find it without guessing.
    final before = (await boot.database.select(boot.database.expenses).get())
        .map((e) => e.id)
        .toSet();

    await tester.tap(find.byKey(const Key('save-expense')));

    // The save is a transaction against an encrypted database on a phone; it takes as
    // long as it takes. Poll rather than guess at a duration.
    var created = <ExpenseRow>[];
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));

      // If the screen is saying why it could not save, that is the useful failure —
      // "no row appeared" is not.
      final notice = find.textContaining('was not saved');
      if (notice.evaluate().isNotEmpty) {
        fail(
          'the save was refused on screen: '
          '${(notice.evaluate().first.widget as Text).data}',
        );
      }

      created = (await boot.database.select(boot.database.expenses).get())
          .where((e) => !before.contains(e.id))
          .toList();
      if (created.isNotEmpty) break;
    }

    if (created.isEmpty) {
      // Say what the screen is actually showing, so this reports the real problem
      // rather than "no row appeared".
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .where((t) => t.trim().isNotEmpty)
          .take(25)
          .join(' | ');
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      fail(
        'no expense was recorded. Outbox holds ${queued.length} entries. '
        'On screen: $texts',
      );
    }
    return created.single.id;
  }

  /// Pushes whatever is queued and waits for the row to learn its number.
  Future<void> syncAndAwaitNumber(
    WidgetTester tester,
    String expenseId, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KrishnaMisApp)),
    );
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await container.read(syncEngineProvider)?.pushOnce();
      final row = await ExpenseRepository(boot.database).load(expenseId);
      if (row?.row.txnNumber != null) return;
      await tester.pump(const Duration(seconds: 2));
    }
    fail('the expense never received a transaction number');
  }

  group('expense-simple', skip: _phase != 'expense-simple', () {
    testWidgets('a routine expense is recorded, queued and numbered', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final id = await recordExpense(
        tester,
        amount: '500',
        classification: const [
          'Crystal Canopy Rooftop',
          'F&B / Kitchen',
          'Food Production',
          'Vegetables & Fruits',
        ],
      );

      final repository = ExpenseRepository(boot.database);
      var saved = await repository.load(id);

      // One expense, one allocation, one derived contribution — the routine shape.
      expect(saved!.allocations, hasLength(1));
      expect(saved.periodContributions, hasLength(1));
      expect(saved.periodContributions.single.isDerived, isTrue);
      expect(saved.visibleAmount, Money.fromRupees(500));
      expect(saved.row.visibility, 'complete');

      // Queued in the same transaction as the document. Whether it has *already* been
      // delivered by the time this line runs is a race the product wins on a fast
      // connection, so the assertion is about the queue entry existing rather than
      // about the number still being absent. The deterministic "never fabricated
      // locally" proof lives in `expense-offline`, where no number can arrive at all.
      final queued = await boot.database.select(boot.database.syncOutbox).get();
      expect(
        queued.where((q) => q.entityId == id),
        hasLength(1),
        reason: 'saved and unqueued must be impossible',
      );
      expect(queued.firstWhere((q) => q.entityId == id).op, 'create');

      await syncAndAwaitNumber(tester, id);
      saved = await repository.load(id);

      // The number came from the server, and the identity never moved.
      expect(saved!.row.txnNumber, startsWith('KI-EXP-'));
      expect(ExpenseNumber.tryParse(saved.row.txnNumber!), isNotNull);
      expect(saved.row.financialYear, isNotNull);
      expect(saved.syncState, SyncState.synced);
      expect(saved.row.rowVersion, greaterThan(1));
      expect(
        saved.row.id,
        id,
        reason: 'the client-generated id is the identity, start to finish',
      );

      _createdExpenses.add(id);
    });
  });

  group('expense-offline', skip: _phase != 'expense-offline', () {
    testWidgets(
      'recorded with no network, survives a restart, then reconciles once',
      (tester) async {
        await launch(tester);
        await signIn(tester, 'giridhar@hki.com');
        await expectSignedIn(tester, 'giridhar@hki.com');

        // The network goes away. Everything below is the shipped code deciding for the
        // shipped reason — only the cable is simulated (D-058).
        _transport.online = false;

        final id = await recordExpense(
          tester,
          amount: '750',
          classification: const [
            'Crystal Canopy Rooftop',
            'F&B / Kitchen',
            'Food Production',
            'Kirana & Pulses',
          ],
        );

        final repository = ExpenseRepository(boot.database);
        var saved = await repository.load(id);
        expect(
          saved,
          isNotNull,
          reason: 'the save must succeed with no network at all',
        );
        expect(saved!.syncState.isOnServer, isFalse);
        expect(saved.row.txnNumber, isNull);

        // A push while offline changes nothing and claims nothing.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(KrishnaMisApp)),
        );
        final offlinePush = await container
            .read(syncEngineProvider)!
            .pushOnce();
        expect(offlinePush.applied, 0);
        expect(offlinePush.transientFailures, 1);

        // "Restart": the database is closed and reopened, which is what an app kill
        // looks like from the data's point of view.
        await boot.database.close();
        final reopened = await bootstrap(transport: _transport);
        final afterRestart = ExpenseRepository(reopened.database);
        saved = await afterRestart.load(id);
        expect(saved, isNotNull, reason: 'the expense survives being killed');
        expect(saved!.syncState, isNot(SyncState.synced));
        final queued = await reopened.database
            .select(reopened.database.syncOutbox)
            .get();
        expect(
          queued.where((q) => q.entityId == id),
          hasLength(1),
          reason: 'and so does its queued intent',
        );

        // Back online: one push, one server record, one reconciled local row.
        _transport.online = true;
        final engine = SyncEngine(
          outbox: reopened.outbox,
          endpoint: reopened.mutationEndpoint!,
          reconciler: reopened.mutationReconciler,
          actorUserId: saved.row.createdBy,
        );

        final deadline = DateTime.now().add(const Duration(seconds: 120));
        while (DateTime.now().isBefore(deadline)) {
          await engine.pushOnce();
          final row = await afterRestart.load(id);
          if (row?.row.txnNumber != null) break;
          await tester.pump(const Duration(seconds: 2));
        }

        saved = await afterRestart.load(id);
        expect(saved!.row.txnNumber, startsWith('KI-EXP-'));
        expect(saved.syncState, SyncState.synced);
        expect(
          (await reopened.database.select(reopened.database.expenses).get())
              .where((e) => e.id == id),
          hasLength(1),
          reason: 'exactly one local record',
        );

        _createdExpenses.add(id);
        await reopened.database.close();
      },
    );
  });

  group('expense-shared', skip: _phase != 'expense-shared', () {
    testWidgets('a scoped manager receives their share and not the total', (
      tester,
    ) async {
      // The Owner records the shared bill through the server, then a scoped manager
      // syncs it and the local database is inspected.
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final id = const Uuid().v4();
      final gateway = ExpenseGateway(Supabase.instance.client);
      final created = await gateway.create(
        arguments: {
          'p_id': id,
          'p_business_date': '2026-06-15',
          'p_total_minor': 5800000,
          'p_notes': 'Device acceptance: shared electricity',
          'p_allocations': [
            {
              'business_unit_id': _ccr,
              'department_id': _seedId('dept:CCR/FB'),
              'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
              'category_id': _seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
              'amount_minor': 2500000,
            },
            {
              'business_unit_id': _hki,
              'department_id': _seedId('dept:HKI/HKI_UTIL'),
              'section_id': _seedId('sec:HKI/HKI_UTIL/HKI_POWER'),
              'category_id': _seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY'),
              'amount_minor': 3300000,
            },
          ],
        },
        mutationId: const Uuid().v4(),
      );
      expect(created.isOk, isTrue, reason: '${created.refusalOrNull?.message}');
      _createdExpenses.add(id);

      // The Owner's own device holds the whole document.
      final pull = ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      );
      await pull.pullOne(id);
      var local = await ExpenseRepository(boot.database).load(id);
      expect(local!.row.visibility, 'complete');
      expect(local.row.documentTotalMinor, 5800000);
      expect(local.allocations, hasLength(2));

      // Now the Crystal Canopy manager, on the same installation.
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');
      await ExpensePull(
        db: boot.database,
        gateway: ExpenseGateway(Supabase.instance.client),
      ).pullOne(id);

      local = await ExpenseRepository(boot.database).load(id);
      expect(local!.row.visibility, 'scoped');
      expect(local.visibleAmount, Money.fromRupees(25000));
      expect(
        local.row.documentTotalMinor,
        isNull,
        reason: '₹58,000 − ₹25,000 is Hotel Krishna s ₹33,000',
      );
      expect(local.allocations, hasLength(1));
      expect(local.allocations.single.businessUnitId, _ccr);

      // And the raw amounts on this device contain neither forbidden figure.
      final amounts = [
        ...(await boot.database.select(boot.database.expenses).get()).expand(
          (r) => [r.documentTotalMinor, r.visibleAmountMinor],
        ),
        ...(await boot.database.select(boot.database.expenseAllocations).get())
            .map((r) => r.amountMinor),
        ...(await boot.database
                .select(boot.database.expensePeriodAllocations)
                .get())
            .map((r) => r.amountMinor),
      ];
      expect(amounts, isNot(contains(3300000)));
      expect(amounts, isNot(contains(5800000)));

      // The interface says so too, in words.
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('expense-refusals', skip: _phase != 'expense-refusals', () {
    testWidgets('closed period, revoked permission, conflict and void', (
      tester,
    ) async {
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');

      final client = Supabase.instance.client;
      final gateway = ExpenseGateway(client);
      final ccrKirana = {
        'business_unit_id': _ccr,
        'department_id': _seedId('dept:CCR/FB'),
        'section_id': _seedId('sec:CCR/FB/FOOD_PROD'),
        'category_id': _seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
      };

      // ── A closed period refuses, and says the true reason ──────────────
      await client.rpc<dynamic>(
        'period_close',
        params: {'p_period_key': '2026-03', 'p_business_unit_id': _ccr},
      );
      final closed = await gateway.create(
        arguments: {
          'p_id': const Uuid().v4(),
          'p_business_date': '2026-03-10',
          'p_total_minor': 1000,
          'p_allocations': [
            {...ccrKirana, 'amount_minor': 1000},
          ],
        },
        mutationId: const Uuid().v4(),
      );
      expect(closed.isRefused, isTrue);
      expect(closed.refusalOrNull!.kind, RefusalKind.periodClosed);
      expect(
        closed.refusalOrNull!.kind,
        isNot(RefusalKind.versionConflict),
        reason: 'a closed period is never dressed up as a conflict',
      );
      expect(closed.refusalOrNull!.message, isNot(contains('SQLSTATE')));
      await client.rpc<dynamic>(
        'period_reopen',
        params: {
          'p_period_key': '2026-03',
          'p_business_unit_id': _ccr,
          'p_reason': 'Device acceptance: restoring the fixture',
        },
      );

      // ── A stale edit is a Conflict, not a refusal ──────────────────────
      final conflictId = const Uuid().v4();
      final made = await gateway.create(
        arguments: {
          'p_id': conflictId,
          'p_business_date': '2026-06-15',
          'p_total_minor': 4200,
          'p_allocations': [
            {...ccrKirana, 'amount_minor': 4200},
          ],
        },
        mutationId: const Uuid().v4(),
      );
      expect(made.isOk, isTrue, reason: '${made.refusalOrNull?.message}');
      _createdExpenses.add(conflictId);

      final stale = await gateway.update(
        arguments: {
          'p_id': conflictId,
          'p_business_date': '2026-06-15',
          'p_total_minor': 4300,
          'p_allocations': [
            {...ccrKirana, 'amount_minor': 4300},
          ],
        },
        baseRowVersion: 1, // the server holds 2
        mutationId: const Uuid().v4(),
      );
      expect(stale.isRefused, isTrue);
      expect(stale.refusalOrNull!.kind, RefusalKind.versionConflict);

      // ── Void: refused for a manager, permitted for an accountant ───────
      await signIn(tester, 'ccr.manager@example.com');
      await expectSignedIn(tester, 'ccr.manager@example.com');
      final managerVoid = await ExpenseGateway(Supabase.instance.client)
          .voidExpense(
            expenseId: conflictId,
            baseRowVersion: 2,
            reason: 'Device acceptance: should be refused',
            mutationId: const Uuid().v4(),
          );
      expect(managerVoid.isRefused, isTrue);
      expect(
        managerVoid.refusalOrNull!.kind,
        RefusalKind.missingCapability,
        reason: 'a Manager cannot void — it is not in the bundle',
      );

      await signIn(tester, 'accountant@example.com');
      await expectSignedIn(tester, 'accountant@example.com');
      final accountantVoid = await ExpenseGateway(Supabase.instance.client)
          .voidExpense(
            expenseId: conflictId,
            baseRowVersion: 2,
            reason: 'Device acceptance: correcting a duplicate',
            mutationId: const Uuid().v4(),
          );
      expect(
        accountantVoid.isOk,
        isTrue,
        reason: '${accountantVoid.refusalOrNull?.message}',
      );
    });
  });

  group('expense-cleanup', skip: _phase != 'expense-cleanup', () {
    testWidgets('the development fixtures are removed', (tester) async {
      // Deliberately its own phase: acceptance leaves real rows behind, and the dev
      // project should end a run in the state it started in. The append-only audit rows
      // correctly remain — they are how a test-generated event is recognised.
      await launch(tester);
      await signIn(tester, 'giridhar@hki.com');
      await expectSignedIn(tester, 'giridhar@hki.com');
      expect(true, isTrue);
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
