/// The Windows workstation shell, exercised **inside the real Windows application**.
///
/// A screenshot cannot prove the absence of a layout overflow, and host-only widget
/// tests do not run in the Windows runtime at all. This suite runs in the compiled
/// desktop binary and asserts the things the owner asked to see proven: the shell
/// renders, navigation works by pointer, keyboard focus behaves, and **no overflow
/// occurs at any realistic window size**.
///
/// Run with: `flutter test integration_test/windows_shell_test.dart -d windows`
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krishna_mis/app/app.dart';
import 'package:krishna_mis/app/routing/app_router.dart';

/// Sizes a finance workstation actually gets used at, including this machine's screen
/// (1536x864) and the smallest laptop worth supporting.
const List<Size> _windowSizes = [
  Size(1024, 768), // small laptop
  Size(1280, 720), // the runner's default
  Size(1536, 864), // this machine's screen
  Size(1920, 1080), // external monitor
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpShell(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const KrishnaMisApp(shellKind: AppShellKind.desktop),
    );
    await tester.pumpAndSettle();
  }

  group('the Windows shell renders', () {
    testWidgets('sidebar and default destination appear', (tester) async {
      await pumpShell(tester, const Size(1536, 864));

      expect(find.text('KRISHNA IMPERIAL'), findsOneWidget);
      expect(find.text('Management MIS'), findsOneWidget);
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
      expect(tester.takeException(), isNull);
    });

    testWidgets('it is not the phone UI stretched', (tester) async {
      await pumpShell(tester, const Size(1536, 864));
      expect(find.byType(BottomAppBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('no layout overflow at any realistic window size', () {
    for (final size in _windowSizes) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        await pumpShell(tester, size);

        // Visiting every destination, because an overflow can hide on one page only.
        for (final destination in [
          'Transactions',
          'Analytics',
          'Reports',
          'Masters',
          'Administration',
          'Overview',
        ]) {
          await tester.tap(find.text(destination).first);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow or error on $destination at $size',
          );
        }
      });
    }

    testWidgets('a deliberately cramped window still does not overflow', (
      tester,
    ) async {
      // Narrower than the sidebar plus comfortable content. If anything is going to
      // overflow, it is here.
      await pumpShell(tester, const Size(820, 600));
      expect(tester.takeException(), isNull);
    });
  });

  group('mouse navigation', () {
    testWidgets('clicking each sidebar entry changes the destination', (
      tester,
    ) async {
      await pumpShell(tester, const Size(1536, 864));

      await tester.tap(find.text('Masters').first);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Business units, departments'),
        findsOneWidget,
      );

      await tester.tap(find.text('Analytics').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Profit & Loss'), findsOneWidget);

      await tester.tap(find.text('Administration').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('period close'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('re-clicking the current destination is harmless', (
      tester,
    ) async {
      await pumpShell(tester, const Size(1536, 864));
      await tester.tap(find.text('Overview').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Business-unit comparison'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a hover over the sidebar does not throw', (tester) async {
      await pumpShell(tester, const Size(1536, 864));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(find.text('Reports').first));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('keyboard and focus', () {
    testWidgets('Tab moves focus into the shell', (tester) async {
      await pumpShell(tester, const Size(1536, 864));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      expect(
        focused!.context,
        isNotNull,
        reason: 'focus must land on a real widget, not float free',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('every sidebar destination is reachable by keyboard', (
      tester,
    ) async {
      await pumpShell(tester, const Size(1536, 864));

      // Asserted against the application's own focus tree rather than through
      // simulated key routing, so this measures the app rather than the harness.
      // The node lives *inside* InkWell, so it is resolved by walking up from the
      // destination's own label.
      for (final destination in [
        'Overview',
        'Transactions',
        'Analytics',
        'Reports',
        'Masters',
        'Administration',
      ]) {
        final label = find.text(destination).first;
        final node = Focus.maybeOf(tester.element(label), scopeOk: false);
        expect(node, isNotNull, reason: '$destination has no focus node');
        expect(
          node!.canRequestFocus && !node.skipTraversal,
          isTrue,
          reason: '$destination is not reachable by keyboard traversal',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('focusing a destination is possible and visible', (
      tester,
    ) async {
      await pumpShell(tester, const Size(1536, 864));

      final node = Focus.maybeOf(
        tester.element(find.text('Masters').first),
        scopeOk: false,
      )!;
      node.requestFocus();
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus,
        node,
        reason: 'a sidebar destination must be able to hold focus',
      );

      // Focus must be *visible*: InkWell paints focusColor only when one is given.
      // Without it the caret moves through the sidebar invisibly.
      final ink = tester.widget<InkWell>(
        find.ancestor(
          of: find.text('Masters').first,
          matching: find.byType(InkWell),
        ),
      );
      expect(
        ink.focusColor,
        isNotNull,
        reason: 'keyboard focus would be invisible without a focus colour',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shift+Tab traverses backwards', (tester) async {
      await pumpShell(tester, const Size(1536, 864));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final forward = FocusManager.instance.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus, forward);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Escape and unhandled keys are ignored quietly', (
      tester,
    ) async {
      await pumpShell(tester, const Size(1536, 864));
      for (final key in [
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.f5,
        LogicalKeyboardKey.pageDown,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      // Still on the default destination; nothing was dismissed or navigated away.
      expect(find.textContaining('Business-unit comparison'), findsOneWidget);
    });
  });
}
