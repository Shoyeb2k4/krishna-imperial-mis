/// Vendor management and tax configuration, on both platforms.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/features/masters/presentation/masters_page.dart';
import 'package:krishna_mis/features/tax/presentation/tax_rates_view.dart';
import 'package:krishna_mis/features/vendors/presentation/vendors_view.dart';

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

  /// Bounded pumping instead of `pumpAndSettle`.
  ///
  /// These screens show a progress indicator while their stream providers connect, and
  /// an indeterminate spinner schedules frames forever — `pumpAndSettle` would never
  /// return and would fail on its ten-minute timeout. Pumping a fixed number of frames
  /// lets the data arrive and keeps the suite deterministic.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    Widget view, {
    required Size size,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Tear the tree down before the database closes. These screens hold Drift stream
    // subscriptions through StreamProvider; closing the database underneath a live
    // subscription hangs. addTearDown runs before the group's tearDown, so this
    // disposes the ProviderScope first.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          principalProvider.overrideWithValue(testOwnerPrincipal()),
        ],
        child: MaterialApp(
          theme: size.width > 900 ? AppTheme.desktop : AppTheme.mobile,
          home: Scaffold(body: view),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> pumpVendors(WidgetTester tester, {bool desktop = true}) => pump(
    tester,
    VendorsView(isDesktop: desktop),
    size: desktop ? const Size(1536, 864) : const Size(390, 844),
  );

  Future<void> pumpTax(WidgetTester tester, {bool desktop = true}) => pump(
    tester,
    TaxRatesView(isDesktop: desktop),
    size: desktop ? const Size(1536, 864) : const Size(390, 844),
  );

  Future<void> addVendor(WidgetTester tester, String name) async {
    await tester.tap(find.byIcon(Icons.add).first);
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, name);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await settle(tester);
  }

  group('vendors', () {
    testWidgets('the empty state invites the first vendor', (tester) async {
      await pumpVendors(tester);
      expect(find.text('No vendors yet'), findsOneWidget);
      expect(find.textContaining('Local '), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('optional fields are hidden until asked for', (tester) async {
      await pumpVendors(tester);
      await tester.tap(find.byIcon(Icons.add).first);
      await settle(tester);

      // Only the name is on screen; the rest is one tap away.
      expect(find.text('The only thing required'), findsOneWidget);
      expect(find.text('GSTIN (optional)'), findsNothing);

      await tester.tap(find.textContaining('Add phone, GSTIN'));
      await settle(tester);
      expect(find.text('GSTIN (optional)'), findsOneWidget);
    });

    testWidgets('a name alone creates a complete vendor', (tester) async {
      await pumpVendors(tester);
      await addVendor(tester, 'Local Vegetable Market');

      expect(find.text('Local Vegetable Market'), findsWidgets);
      final row = (await db.select(db.vendors).get()).single;
      expect(row.name, 'Local Vegetable Market');
      expect(row.phone, isNull);
      expect(row.gstin, isNull);
    });

    testWidgets('add is disabled until a name is typed', (tester) async {
      await pumpVendors(tester);
      await tester.tap(find.byIcon(Icons.add).first);
      await settle(tester);

      final add = find.widgetWithText(FilledButton, 'Add');
      expect(tester.widget<FilledButton>(add).onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'Sharma Traders');
      await settle(tester);
      expect(tester.widget<FilledButton>(add).onPressed, isNotNull);
    });

    testWidgets('a duplicate name is refused with an explanation', (
      tester,
    ) async {
      await pumpVendors(tester);
      await addVendor(tester, 'Sharma Traders');
      await addVendor(tester, 'Sharma Traders');

      expect(find.textContaining('already exists'), findsOneWidget);
      expect((await db.select(db.vendors).get()).length, 1);
    });

    testWidgets('the detail explains that a bare name is complete', (
      tester,
    ) async {
      await pumpVendors(tester);
      await addVendor(tester, 'Local Vegetable Market');

      await tester.tap(find.text('Local Vegetable Market').first);
      await settle(tester);

      expect(find.textContaining('That is a complete vendor'), findsOneWidget);
      expect(
        find.text('Phone'),
        findsNothing,
        reason: 'blank fields are omitted',
      );
    });

    testWidgets('archiving keeps the record and says why it matters', (
      tester,
    ) async {
      await pumpVendors(tester);
      await addVendor(tester, 'Sharma Traders');
      await tester.tap(find.text('Sharma Traders').first);
      await settle(tester);

      await tester.tap(find.text('Archive'));
      await settle(tester);

      expect(find.textContaining('Past expenses still show'), findsWidgets);
      final row = (await db.select(db.vendors).get()).single;
      expect(row.archivedAt, isNotNull, reason: 'archived, not deleted');
    });

    testWidgets('search narrows the list', (tester) async {
      await pumpVendors(tester);
      await addVendor(tester, 'Sharma Traders');
      await addVendor(tester, 'Metro Wholesale');

      await tester.enterText(find.byType(TextField).first, 'metro');
      await settle(tester);

      expect(find.text('Metro Wholesale'), findsWidgets);
      expect(find.text('Sharma Traders'), findsNothing);
    });

    testWidgets('the phone list has no desktop detail panel', (tester) async {
      await pumpVendors(tester, desktop: false);
      expect(find.text('Select a vendor'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('tax rules', () {
    testWidgets('lists revenue categories per property', (tester) async {
      await pumpTax(tester);

      expect(find.text('Tax rules'), findsOneWidget);
      expect(find.text('Restaurant'), findsOneWidget);
      expect(find.text('Nandbhog'), findsOneWidget);
      expect(find.text('Room'), findsOneWidget);
      expect(find.text('Banquet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('warns when a category has no rule at all', (tester) async {
      await pumpTax(tester);
      expect(find.textContaining('No rule in force today'), findsWidgets);
      expect(
        find.textContaining('no tax extracted until one is set'),
        findsWidgets,
      );
    });

    testWidgets('setting a rate records it against the category', (
      tester,
    ) async {
      await pumpTax(tester);

      await tester.tap(find.text('Set rate').first);
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '5');
      await tester.enterText(find.byType(TextField).last, '2026-04-01');
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await settle(tester);

      final rows = await db.select(db.revenueTaxRates).get();
      expect(rows.length, 1);
      expect(rows.single.rateBasisPoints, 500);
      expect(rows.single.treatment, 'inclusive');
      expect(rows.single.effectiveFrom, '2026-04-01');
      expect(find.text('5%'), findsWidgets);
      expect(find.text('In force'), findsWidgets);
    });

    testWidgets('a decimal rate is stored as basis points', (tester) async {
      await pumpTax(tester);
      await tester.tap(find.text('Set rate').first);
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '12.5');
      await tester.enterText(find.byType(TextField).last, '2026-04-01');
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await settle(tester);

      expect(
        (await db.select(db.revenueTaxRates).get()).single.rateBasisPoints,
        1250,
      );
    });

    testWidgets('changing a rate adds a period and preserves the old one', (
      tester,
    ) async {
      await pumpTax(tester);

      await tester.tap(find.text('Set rate').first);
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '5');
      await tester.enterText(find.byType(TextField).last, '2026-04-01');
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await settle(tester);

      // Now change it from October.
      await tester.tap(find.text('Change rate').first);
      await settle(tester);
      expect(
        find.textContaining('keeps its original treatment'),
        findsOneWidget,
        reason: 'the dialog must say history is untouched',
      );
      await tester.enterText(find.byType(TextField).first, '12');
      await tester.enterText(find.byType(TextField).last, '2026-10-01');
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await settle(tester);

      final rows = await db.select(db.revenueTaxRates).get()
        ..sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
      expect(rows.length, 2, reason: 'the old period is kept, not overwritten');
      expect(rows.first.rateBasisPoints, 500);
      expect(
        rows.first.effectiveTo,
        '2026-10-01',
        reason: 'closed at the changeover',
      );
      expect(rows.last.rateBasisPoints, 1200);
      expect(rows.last.effectiveTo, isNull);

      // Both periods are visible on screen.
      expect(find.text('5%'), findsWidgets);
      expect(find.text('12%'), findsWidgets);
    });

    testWidgets('an invalid rate leaves Apply disabled', (tester) async {
      await pumpTax(tester);
      await tester.tap(find.text('Set rate').first);
      await settle(tester);

      final apply = find.widgetWithText(FilledButton, 'Apply');
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, 'abc');
      await settle(tester);
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, '150');
      await settle(tester);
      expect(
        tester.widget<FilledButton>(apply).onPressed,
        isNull,
        reason: 'a rate above 100% is impossible',
      );
    });
  });

  group('sections', () {
    testWidgets('Windows switches between hierarchy, vendors and tax', (
      tester,
    ) async {
      await pump(
        tester,
        const MastersPage(shellKind: AppShellKind.desktop),
        size: const Size(1536, 864),
      );

      expect(find.text('Select a record'), findsOneWidget);

      await tester.tap(find.text('Vendors'));
      await settle(tester);
      expect(find.text('No vendors yet'), findsOneWidget);

      await tester.tap(find.text('Tax rules').first);
      await settle(tester);
      expect(find.text('Restaurant'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Android offers the sections first, then drills in', (
      tester,
    ) async {
      await pump(
        tester,
        const MastersPage(shellKind: AppShellKind.mobile),
        size: const Size(390, 844),
      );

      // A phone picks a section before showing a hierarchy.
      expect(find.text('Set-up'), findsOneWidget);
      expect(find.text('Hierarchy'), findsOneWidget);
      expect(find.text('Vendors'), findsOneWidget);
      expect(find.text('Crystal Canopy Rooftop'), findsNothing);

      await tester.tap(find.text('Hierarchy'));
      await settle(tester);
      expect(find.text('Crystal Canopy Rooftop'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await settle(tester);
      expect(find.text('Set-up'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
