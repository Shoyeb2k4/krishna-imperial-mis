/// Both shells must state whose session is open and offer a way out of it.
///
/// The application shipped Phase 2's first integration with **no sign-out control at
/// all**: `signOut` existed on the session controller and was reachable only from the
/// "access not verified" screen. A signed-in user could not leave, which on a shared
/// back-office machine means the next person enters their figures under the previous
/// person's account — and it made the user-switch isolation rules (D-050, §16)
/// unreachable in practice.
///
/// These tests hold that closed on both platforms.
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
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';

import '../support/test_session.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late OutboxRepository outbox;
  late StubSession session;

  Future<void> pumpApp(
    WidgetTester tester,
    AppShellKind shellKind, {
    AuthoritySnapshot? authority,
    String email = 'ccr.manager@example.test',
  }) async {
    await tester.binding.setSurfaceSize(
      shellKind == AppShellKind.desktop
          ? const Size(1440, 900)
          : const Size(390, 844),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));

    db = AppDatabase(NativeDatabase.memory());
    await seedMasterData(db, now: DateTime.utc(2026, 6, 15));
    outbox = OutboxRepository(db);
    addTearDown(db.close);

    session = StubSession(readySession(authority: authority, email: email));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          outboxProvider.overrideWithValue(outbox),
          sessionProvider.overrideWith(() => session),
        ],
        child: KrishnaMisApp(shellKind: shellKind),
      ),
    );
    await tester.pumpAndSettle();

    // Android keeps the account block on "More"; Windows keeps it in the sidebar.
    if (shellKind == AppShellKind.mobile) {
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
    }
  }

  for (final shellKind in AppShellKind.values) {
    group('${shellKind.name} shell', () {
      testWidgets('names the signed-in user and offers Sign out', (
        tester,
      ) async {
        await pumpApp(tester, shellKind);

        expect(find.text('SIGNED IN'), findsOneWidget);
        expect(find.text('ccr.manager@example.test'), findsOneWidget);
        expect(find.text('Sign out'), findsOneWidget);
      });

      testWidgets('signing out asks first, then ends the session', (
        tester,
      ) async {
        await pumpApp(tester, shellKind);

        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        expect(find.text('Sign out?'), findsOneWidget);

        await tester.tap(find.text('Stay signed in'));
        await tester.pumpAndSettle();
        expect(session.signOutCalls, 0, reason: 'cancelling must not sign out');

        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
        await tester.pumpAndSettle();
        expect(session.signOutCalls, 1);
      });

      testWidgets('warns that queued entries are kept, not sent', (
        tester,
      ) async {
        await pumpApp(tester, shellKind);
        await outbox.enqueue(
          PendingMutation(
            mutationId: '5f1c1b2e-9a3d-4c77-8f21-0d6b4e2a91cc',
            entityType: 'expense_category',
            entityId: 'cat-1',
            op: MutationOp.update,
            payload: const {'name': 'Queued'},
            baseRowVersion: 1,
            createdAt: DateTime.utc(2026, 8, 28),
          ),
          now: DateTime.utc(2026, 8, 28),
        );

        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();

        expect(find.textContaining('1 entry still waiting'), findsOneWidget);
        expect(
          find.textContaining('nothing queued is deleted'),
          findsOneWidget,
        );
      });

      testWidgets('states the scope rather than a role name', (tester) async {
        await pumpApp(
          tester,
          shellKind,
          authority: AuthoritySnapshot(
            userId: 'u1',
            orgId: 'org-1',
            resolvedAt: DateTime.utc(2026, 8, 28),
            grants: const [
              CapabilityGrant(Capability.mastersView, businessUnitId: 'ccr'),
            ],
          ),
        );

        expect(find.text('1 business unit'), findsOneWidget);
        expect(find.textContaining('Manager'), findsNothing);
        expect(find.textContaining('Owner'), findsNothing);
      });
    });
  }
}
