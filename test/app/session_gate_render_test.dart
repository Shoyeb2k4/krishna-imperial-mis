/// Every pre-session screen must render inside the real application.
///
/// These states are built by `MaterialApp.builder`, which sits **above** the router's
/// Navigator, so nothing in scope provides an `Overlay`. A tooltip and a text field's
/// selection handles both require one, and without it the framework paints its red error
/// box where the widget should be.
///
/// That is not a hypothetical: the first launch of the signed Android build showed the
/// error box in place of the password field, because the show/hide-password button
/// carries a tooltip. A widget test that pumped `SignInScreen` inside its own
/// `MaterialApp` could never have caught it — the `MaterialApp` supplied the Overlay the
/// real application did not.
///
/// So these tests assemble the app exactly as `main()` does, and assert that each gate
/// state renders with no exception at all.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/app.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';

import '../support/test_session.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  Future<void> pumpGate(
    WidgetTester tester,
    SessionState session,
    AppShellKind shellKind,
  ) async {
    await tester.binding.setSurfaceSize(
      shellKind == AppShellKind.desktop
          ? const Size(1440, 900)
          : const Size(390, 844),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(() => StubSession(session)),
        ],
        child: KrishnaMisApp(shellKind: shellKind),
      ),
    );
    // Deliberately not `pumpAndSettle`: two of these states show a progress indicator,
    // which never settles. Frames are what matter here — the error box appears on the
    // first one.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  final states = <String, SessionState>{
    'unauthenticated': const SessionState.unauthenticated(),
    'authenticating': const SessionState.authenticating(),
    'verifying authority': SessionState.verifying('u1'),
    'authority never verified': SessionState.unverified(
      'u1',
      AuthorityUnavailableReason.offline,
    ),
    'session expired': const SessionState.expired(),
  };

  for (final shellKind in AppShellKind.values) {
    group('${shellKind.name} shell', () {
      states.forEach((label, session) {
        testWidgets('$label renders with no framework error', (tester) async {
          await pumpGate(tester, session, shellKind);
          expect(
            tester.takeException(),
            isNull,
            reason: 'the $label screen threw inside the real application',
          );
          // The error box the framework paints carries this text. Asserting on it as
          // well means a *silenced* exception still fails the test.
          expect(find.textContaining('No Overlay widget found'), findsNothing);
          expect(find.byType(ErrorWidget), findsNothing);
        });
      });

      testWidgets('the sign-in password toggle has its tooltip overlay', (
        tester,
      ) async {
        await pumpGate(tester, const SessionState.unauthenticated(), shellKind);

        expect(find.byType(Tooltip), findsWidgets);
        expect(
          Overlay.maybeOf(tester.element(find.byType(Tooltip).first)),
          isNotNull,
          reason:
              'a tooltip without an Overlay ancestor throws on a real device',
        );
      });
    });
  }
}
