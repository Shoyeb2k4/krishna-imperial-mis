/// Routing smoke tests.
///
/// Phase 1's navigation goal is to prove that Android and Windows each get their own
/// navigation architecture over one shared codebase — not to fake finished features.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/app.dart';
import 'package:krishna_mis/app/routing/app_router.dart';

Future<void> pumpApp(WidgetTester tester, AppShellKind shellKind) async {
  await tester.binding.setSurfaceSize(
    shellKind == AppShellKind.desktop
        ? const Size(1440, 900)
        : const Size(390, 844),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(KrishnaMisApp(shellKind: shellKind));
  await tester.pumpAndSettle();
}

void main() {
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

      await tester.tap(find.text('Reports').last);
      await tester.pumpAndSettle();
      expect(find.text('Phase 5 — Ledger & Reporting Engine'), findsNothing);
      expect(
        find.textContaining('Phase 5 — Ledger & Reporting Engine'),
        findsOneWidget,
      );

      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Phase 2 — Masters & Permissions'),
        findsOneWidget,
      );
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
      expect(
        find.textContaining('Business units, departments'),
        findsOneWidget,
      );

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
