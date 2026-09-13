/// Routing smoke tests.
///
/// Phase 1's navigation goal is to prove that Android and Windows each get their own
/// navigation architecture over one shared codebase — not to fake finished features.
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

import '../support/test_session.dart';

Future<void> pumpApp(WidgetTester tester, AppShellKind shellKind) async {
  await tester.binding.setSurfaceSize(
    shellKind == AppShellKind.desktop
        ? const Size(1440, 900)
        : const Size(390, 844),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // Masters is a real screen now, so the app needs its data layer. An in-memory,
  // seeded database keeps these tests about *navigation* rather than persistence.
  final db = AppDatabase(NativeDatabase.memory());
  await seedMasterData(db, now: DateTime.utc(2026, 6, 15));
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionProvider.overrideWith(() => StubSession(readySession())),
      ],
      child: KrishnaMisApp(shellKind: shellKind),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  group('Android shell', () {
    testWidgets('starts on Home with the phone navigation', (tester) async {
      await pumpApp(tester, AppShellKind.mobile);

      expect(find.text('Home'), findsWidgets);
      expect(find.text('Transactions'), findsWidgets);
      expect(find.text('Reports'), findsWidgets);
      expect(find.text('More'), findsWidgets);
      // The central add action is present and reachable.
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('moves between branches', (tester) async {
      await pumpApp(tester, AppShellKind.mobile);

      // Reports opens directly to Profit & Loss (Phase 5 Slice 9) — no placeholder and no
      // reports menu in front of it.
      await tester.tap(find.text('Reports').last);
      await tester.pumpAndSettle();
      expect(find.text('Profit & Loss'), findsOneWidget);
      expect(find.byKey(const Key('pnl-page')), findsOneWidget);
      expect(
        find.textContaining('Phase 5 — Ledger & Reporting Engine'),
        findsNothing,
      );

      // "More" now opens the real Masters set-up, not a placeholder. A phone picks a
      // section before drilling into a hierarchy.
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      expect(find.text('Set-up'), findsOneWidget);
      expect(find.text('Hierarchy'), findsOneWidget);
    });

    testWidgets(
      'the add action opens a sheet without leaving the current screen',
      (tester) async {
        await pumpApp(tester, AppShellKind.mobile);

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();

        expect(find.text('Add Expense'), findsOneWidget);
        expect(find.text('Add Sale'), findsOneWidget);
        // Home is still underneath — recording a bill never costs the user their place.
        expect(
          find.textContaining('Phase 6 — Dashboard & Analytics'),
          findsOneWidget,
        );
      },
    );

    testWidgets('does not present the desktop-only destinations', (
      tester,
    ) async {
      await pumpApp(tester, AppShellKind.mobile);
      expect(find.text('Masters'), findsNothing);
      expect(find.text('Administration'), findsNothing);
      expect(find.text('Analytics'), findsNothing);
    });
  });

  group('Windows shell', () {
    testWidgets('starts on Overview with the full sidebar', (tester) async {
      await pumpApp(tester, AppShellKind.desktop);

      expect(find.text('KRISHNA IMPERIAL'), findsOneWidget);
      for (final destination in [
        'Overview',
        'Transactions',
        'Analytics',
        'Reports',
        'Masters',
        'Administration',
      ]) {
        expect(
          find.text(destination),
          findsWidgets,
          reason: 'missing $destination',
        );
      }
    });

    testWidgets('moves between branches', (tester) async {
      await pumpApp(tester, AppShellKind.desktop);

      await tester.tap(find.text('Masters').first);
      await tester.pumpAndSettle();
      expect(find.text('Select a record'), findsOneWidget);

      await tester.tap(find.text('Analytics').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Profit & Loss'), findsOneWidget);
    });

    testWidgets('is not the phone UI stretched', (tester) async {
      await pumpApp(tester, AppShellKind.desktop);
      // No bottom bar, no central floating add action on the workstation.
      expect(find.byType(BottomAppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  testWidgets('each platform builds its own router', (tester) async {
    final mobile = AppRouter.create(shellKind: AppShellKind.mobile);
    final desktop = AppRouter.create(shellKind: AppShellKind.desktop);

    expect(
      mobile.configuration.findMatch(Uri.parse('/home')).uri.path,
      '/home',
    );
    expect(
      desktop.configuration.findMatch(Uri.parse('/overview')).uri.path,
      '/overview',
    );
    mobile.dispose();
    desktop.dispose();
  });
}
