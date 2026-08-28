/// The Masters surfaces, on both platforms, against a real (in-memory) database.
///
/// These assert what the owner asked to see: a legible hierarchy, search, the detail
/// view, the D-038 rename distinction, archive semantics, and that the two platforms
/// genuinely differ rather than one being a shrunk copy of the other.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/features/masters/presentation/android_masters_view.dart';
import 'package:krishna_mis/features/masters/presentation/widgets/master_chrome.dart';
import 'package:krishna_mis/features/masters/presentation/windows_masters_view.dart';

/// A fully-capable principal, for exercising screens that assume the user may act.
///
/// This is a **test fixture**, not a runtime fallback. Shipped code has no way to build
/// one — `test/app/no_hardcoded_authority_test.dart` asserts that over `lib/`, which is
/// what actually reaches an Android or Windows binary.
Principal testOwnerPrincipal() => Principal(
  userId: 'test-owner',
  grants: [for (final c in RoleTemplates.owner) CapabilityGrant(c)],
);

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 6, 15, 9);

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await seedMasterData(db, now: now);
  });

  tearDown(() => db.close());

  Future<void> pump(
    WidgetTester tester,
    Widget view, {
    required Size size,
    Principal? principal,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          // Always overridden: the runtime provider derives from a real session, and
          // a widget test has no server to establish one.
          principalProvider.overrideWithValue(
            principal ?? testOwnerPrincipal(),
          ),
        ],
        child: MaterialApp(
          theme: size.width > 900 ? AppTheme.desktop : AppTheme.mobile,
          home: Scaffold(body: view),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpWindows(WidgetTester tester, {Principal? principal}) => pump(
    tester,
    const WindowsMastersView(),
    size: const Size(1536, 864),
    principal: principal,
  );

  Future<void> pumpAndroid(WidgetTester tester) =>
      pump(tester, const AndroidMastersView(), size: const Size(390, 844));

  group('Windows hierarchy', () {
    testWidgets('shows both properties at the top level', (tester) async {
      await pumpWindows(tester);

      expect(find.text('Masters'), findsOneWidget);
      expect(find.text('Crystal Canopy Rooftop'), findsOneWidget);
      expect(find.text('Hotel Krishna Imperial'), findsOneWidget);
      // Departments stay collapsed until asked for.
      expect(find.text('F&B / Kitchen'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'drills down Crystal Canopy → Kitchen → Food Production → Kirana',
      (tester) async {
        await pumpWindows(tester);

        await tester.tap(find.text('Crystal Canopy Rooftop'));
        await tester.pumpAndSettle();
        expect(find.text('F&B / Kitchen'), findsOneWidget);
        // Revenue categories hang off the unit too.
        expect(find.text('Nandbhog'), findsOneWidget);

        await tester.tap(find.text('F&B / Kitchen'));
        await tester.pumpAndSettle();
        expect(find.text('Food Production'), findsOneWidget);

        await tester.tap(find.text('Food Production'));
        await tester.pumpAndSettle();
        expect(find.text('Kirana & Pulses'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('selecting a record opens the detail panel beside the tree', (
      tester,
    ) async {
      await pumpWindows(tester);
      await tester.tap(find.text('Crystal Canopy Rooftop'));
      await tester.pumpAndSettle();

      // The hierarchy is still visible — the detail is a panel, not a modal.
      expect(find.text('Hotel Krishna Imperial'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      // Detail content.
      expect(find.text('CCR'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
    });

    testWidgets('the detail shows the permanent code, never a database id', (
      tester,
    ) async {
      await pumpWindows(tester);
      await tester.tap(find.text('Crystal Canopy Rooftop'));
      await tester.pumpAndSettle();

      expect(find.byType(CodeBadge), findsOneWidget);
      expect(find.text('CCR'), findsOneWidget);
      // The internal id must not be on screen.
      expect(find.textContaining(seedId('bu:CCR')), findsNothing);
    });

    testWidgets('usage is shown, and labelled as non-authoritative', (
      tester,
    ) async {
      await pumpWindows(tester);
      await tester.tap(find.text('Crystal Canopy Rooftop'));
      await tester.pumpAndSettle();

      expect(find.byType(UsageNote), findsOneWidget);
      expect(
        find.textContaining('server has not been checked'),
        findsOneWidget,
        reason: 'a cached count must never present itself as the whole truth',
      );
    });

    testWidgets(
      'an empty selection invites the user rather than showing blank',
      (tester) async {
        await pumpWindows(tester);
        expect(find.text('Select a record'), findsOneWidget);
      },
    );
  });

  group('Windows search', () {
    testWidgets('finds a category by name, with its path', (tester) async {
      await pumpWindows(tester);

      await tester.enterText(find.byType(TextField).first, 'kirana');
      await tester.pumpAndSettle();

      expect(find.text('Kirana & Pulses'), findsOneWidget);
      expect(
        find.textContaining('Crystal Canopy Rooftop › F&B / Kitchen'),
        findsOneWidget,
      );
    });

    testWidgets('finds a record by its permanent code', (tester) async {
      await pumpWindows(tester);

      await tester.enterText(find.byType(TextField).first, 'DIESEL');
      await tester.pumpAndSettle();

      expect(find.text('Diesel'), findsOneWidget);
    });

    testWidgets('says so plainly when nothing matches', (tester) async {
      await pumpWindows(tester);
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matched'), findsOneWidget);
    });
  });

  group('rename — D-038', () {
    testWidgets('warns and requires acknowledgement when usage is unproven', (
      tester,
    ) async {
      await pumpWindows(tester);
      await tester.tap(find.text('Crystal Canopy Rooftop'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      // The rule is stated, with both examples.
      expect(find.textContaining('only correct or clarify'), findsOneWidget);
      expect(find.textContaining('VEGETABLES & FRUITS'), findsOneWidget);
      expect(find.textContaining('Building Maintenance'), findsOneWidget);

      // Rename is refused until the name changes AND the rule is acknowledged.
      final renameButton = find.widgetWithText(FilledButton, 'Rename');
      expect(tester.widget<FilledButton>(renameButton).onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'Crystal Canopy');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(renameButton).onPressed,
        isNull,
        reason: 'a changed name alone must not be enough',
      );

      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(renameButton).onPressed, isNotNull);
    });

    testWidgets('a completed rename changes the name and keeps the code', (
      tester,
    ) async {
      await pumpWindows(tester);
      await tester.tap(find.text('Crystal Canopy Rooftop'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Crystal Canopy Terrace',
      );
      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Crystal Canopy Terrace'), findsWidgets);
      // The code did not move.
      final row = (await db.select(db.businessUnits).get()).firstWhere(
        (r) => r.id == seedId('bu:CCR'),
      );
      expect(row.name, 'Crystal Canopy Terrace');
      expect(row.code, 'CCR');
    });

    testWidgets('cancelling changes nothing', (tester) async {
      await pumpWindows(tester);
      await tester.tap(find.text('Crystal Canopy Rooftop'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Something Else');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final row = (await db.select(db.businessUnits).get()).firstWhere(
        (r) => r.id == seedId('bu:CCR'),
      );
      expect(row.name, 'Crystal Canopy Rooftop');
    });
  });

  group('archive', () {
    testWidgets('a parent with live children is refused, with the reason', (
      tester,
    ) async {
      await pumpWindows(tester);
      await tester.tap(find.text('Crystal Canopy Rooftop'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();

      expect(find.textContaining('underneath this one first'), findsOneWidget);
      // Nothing changed.
      final row = (await db.select(db.businessUnits).get()).firstWhere(
        (r) => r.id == seedId('bu:CCR'),
      );
      expect(row.archivedAt, isNull);
    });

    testWidgets(
      'a leaf archives, disappears from the tree, and can be restored',
      (tester) async {
        await pumpWindows(tester);
        for (final step in [
          'Crystal Canopy Rooftop',
          'F&B / Kitchen',
          'Food Production',
          'Kirana & Pulses',
        ]) {
          await tester.tap(find.text(step));
          await tester.pumpAndSettle();
        }

        await tester.tap(find.text('Archive'));
        await tester.pumpAndSettle();

        // Gone from the live *tree*. The detail panel still shows the record that
        // was just archived, which is correct — the user is looking at it.
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.text('Kirana & Pulses'),
          ),
          findsNothing,
        );
        final row = (await db.select(db.expenseCategories).get()).firstWhere(
          (r) => r.id == seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
        );
        expect(row.archivedAt, isNotNull);

        // Showing archived brings it back, marked as such.
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.text('Kirana & Pulses'),
          ),
          findsOneWidget,
        );
        expect(find.byType(MasterStatusChip), findsWidgets);
      },
    );
  });

  group('permissions shape the UI', () {
    testWidgets('a user without masters.manage sees no actions', (
      tester,
    ) async {
      final dataEntry = Principal(
        userId: 'u-de',
        grants: [
          for (final c in RoleTemplates.dataEntry)
            CapabilityGrant(c, businessUnitId: seedId('bu:CCR')),
        ],
      );
      await pumpWindows(tester, principal: dataEntry);

      await tester.tap(find.text('Crystal Canopy Rooftop'));
      await tester.pumpAndSettle();

      expect(find.text('Rename'), findsNothing);
      expect(find.text('Archive'), findsNothing);
      expect(
        find.textContaining('requires the "manage masters" permission'),
        findsOneWidget,
      );
    });
  });

  group('Android drill-down', () {
    testWidgets('starts at the business units', (tester) async {
      await pumpAndroid(tester);

      expect(find.text('Business units'), findsOneWidget);
      expect(find.text('Crystal Canopy Rooftop'), findsOneWidget);
      expect(find.text('Hotel Krishna Imperial'), findsOneWidget);
      // No desktop tree, no side panel.
      expect(find.text('Select a record'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('drills in one level at a time with a breadcrumb', (
      tester,
    ) async {
      await pumpAndroid(tester);

      await tester.tap(find.text('Hotel Krishna Imperial'));
      await tester.pumpAndSettle();
      expect(find.text('Housekeeping'), findsOneWidget);
      // The previous level is replaced, not stacked beside it.
      expect(find.text('Crystal Canopy Rooftop'), findsNothing);

      await tester.tap(find.text('Housekeeping'));
      await tester.pumpAndSettle();
      expect(find.text('Housekeeping Operations'), findsOneWidget);
      expect(find.textContaining('HOTEL KRISHNA IMPERIAL'), findsOneWidget);
    });

    testWidgets('back returns to the previous level', (tester) async {
      await pumpAndroid(tester);
      await tester.tap(find.text('Hotel Krishna Imperial'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Crystal Canopy Rooftop'), findsOneWidget);
      expect(find.text('Business units'), findsOneWidget);
    });

    testWidgets('a leaf opens the detail page', (tester) async {
      await pumpAndroid(tester);
      for (final step in [
        'Crystal Canopy Rooftop',
        'F&B / Kitchen',
        'Food Production',
        'Kirana & Pulses',
      ]) {
        await tester.tap(find.text(step));
        await tester.pumpAndSettle();
      }

      expect(find.byType(CodeBadge), findsOneWidget);
      expect(find.text('KIRANA'), findsOneWidget);
      expect(find.byType(UsageNote), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows how many records are inside each entry', (tester) async {
      await pumpAndroid(tester);
      expect(find.textContaining('inside'), findsWidgets);
    });
  });
}
