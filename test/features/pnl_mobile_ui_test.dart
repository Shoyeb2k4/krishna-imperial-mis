/// The Android P&L surface, rendered inside the real phone shell (Phase 5 Slice 9).
///
/// The page is reached the way a phone reaches it: the mobile router, opened on the Reports
/// tab, inside `MobileShell` with its bottom bar and docked [ + ] action, under the mobile
/// theme. Everything behind it is the real provider chain over SQLite and the canonical
/// reporting cache; only the remote transport and "now" are substituted
/// (`test/support/pnl_fixture.dart`). A test never hands the widget a figure.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/app/routing/app_routes.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_profit_and_loss_page.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_presentation.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/pnl_fixture.dart';
import '../support/ui_harness.dart';

const _phone360 = Size(360, 740);
const _phone390 = Size(390, 844);
const _phone430 = Size(430, 932);
const _landscape = Size(844, 390);

/// A status bar the page must stay clear of.
const _statusBar = 24.0;

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    // A tap that lands on nothing fails where it happens, not as a later assertion about
    // a picker that never opened (D-075).
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late AppDatabase db;
  late FakeReportingGateway gateway;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeReportingGateway();
    await seedPnlMasters(db);
  });
  tearDown(() => db.close());

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<CapabilityGrant>? grants,
    Size size = _phone390,
    double textScale = 1,
    bool withGateway = true,
    bool settle = true,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size
      ..padding = const FakeViewPadding(top: _statusBar);
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final GoRouter router = AppRouter.create(
      shellKind: AppShellKind.mobile,
      initialLocation: AppRoutes.reports,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(
            () => SwitchableSession(pnlSession(grants: grants)),
          ),
          reportingClockProvider.overrideWithValue(() => pnlInstant),
          if (withGateway) reportingGatewayProvider.overrideWithValue(gateway),
        ],
        child: MaterialApp.router(theme: AppTheme.mobile, routerConfig: router),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    return ProviderScope.containerOf(
      tester.element(find.byType(MobileProfitAndLossPage)),
    );
  }

  Money amountAt(WidgetTester tester, String key) =>
      tester.widget<MoneyText>(find.byKey(Key(key))).amount;

  String textAt(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  Finder pageScrollable() => find
      .descendant(
        of: find.byKey(const Key('pnl-page')),
        matching: find.byType(Scrollable),
      )
      .first;

  Future<void> selectCustom(
    ProviderContainer container,
    WidgetTester tester,
    BusinessDate from,
    BusinessDate to,
  ) async {
    container.read(pnlSelectionProvider.notifier).selectCustom(from, to);
    await tester.pumpAndSettle();
  }

  /// A day cell in the open date-range picker, by the date it announces.
  Finder dayCell(String fullDate) =>
      find.bySemanticsLabel(RegExp(RegExp.escape(fullDate)));

  /// Taps [finder] after centring it in every scrollable around it, so the tap lands on it
  /// rather than on the docked [ + ] action or past the end of the preset strip.
  Future<void> tapInView(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  group('the Reports tab', () {
    uiTest('opens directly to Profit & Loss, with no reports menu', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(MobileProfitAndLossPage), findsOneWidget);
      expect(find.text('Profit & Loss'), findsOneWidget);
      expect(find.textContaining('Phase 5'), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byType(BottomAppBar), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('a computed report on a phone', () {
    uiTest('a profit shows the headline, a two-decimal margin and its basis', (
      tester,
    ) async {
      gateway
        ..revenue.add(
          pnlSale(pnlCcr, '2026-09-10', gross: 12364200, tax: 588771),
        )
        ..expense.add(pnlCost(pnlCcr, '2026-09-11', 9420343));
      await pump(tester);

      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
      expect(amountAt(tester, 'pnl-gross').paise, 12364200);
      expect(amountAt(tester, 'pnl-gst').paise, 588771);
      expect(amountAt(tester, 'pnl-net').paise, 11775429);
      expect(amountAt(tester, 'pnl-expenses').paise, 9420343);
      expect(amountAt(tester, 'pnl-operating-result').paise, 2355086);
      expect(textAt(tester, 'pnl-operating-label'), 'Operating Profit');
      expect(textAt(tester, 'pnl-margin'), '20.00%');
      expect(find.byKey(const Key('pnl-basis')), findsOneWidget);
      expect(
        textAt(tester, 'pnl-freshness-synchronised'),
        contains('20 Sep 2026, 02:00'),
      );
      expect(
        textAt(tester, 'pnl-scope-name'),
        'Both properties (consolidated)',
      );
    });

    uiTest('category lines reconcile exactly with the headline totals', (
      tester,
    ) async {
      gateway
        ..revenue.addAll([
          pnlSale(pnlCcr, '2026-06-10', gross: 10000000, tax: 476190),
          pnlSale(
            pnlCcr,
            '2026-06-11',
            gross: 870000,
            tax: 41429,
            category: 'nandbhog',
          ),
          pnlSale(
            pnlHki,
            '2026-06-12',
            gross: 4034300,
            tax: 0,
            category: 'banquet',
          ),
        ])
        ..expense.addAll([
          pnlCost(pnlCcr, '2026-06-10', 4500000),
          pnlCost(pnlHki, '2026-06-15', 3000000, category: 'electricity'),
        ]);
      final container = await pump(tester);
      await selectCustom(
        container,
        tester,
        BusinessDate.of(2026, 6, 1),
        BusinessDate.of(2026, 6, 30),
      );

      for (final name in [
        'Restaurant',
        'Nandbhog',
        'Banquet',
        'Kirana & Pulses',
        'Electricity',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('Hotel Krishna Imperial · No GST'), findsOneWidget);

      var gross = 0;
      var tax = 0;
      var net = 0;
      for (final line in [
        '$pnlCcr-$pnlCcr-restaurant',
        '$pnlCcr-$pnlCcr-nandbhog',
        '$pnlHki-$pnlHki-banquet',
      ]) {
        gross += amountAt(tester, 'pnl-rev-$line-gross').paise;
        tax += amountAt(tester, 'pnl-rev-$line-gst').paise;
        net += amountAt(tester, 'pnl-rev-$line-net').paise;
      }
      expect(gross, amountAt(tester, 'pnl-gross').paise);
      expect(tax, amountAt(tester, 'pnl-gst').paise);
      expect(net, amountAt(tester, 'pnl-net').paise);
      expect(amountAt(tester, 'pnl-rev-total-gross').paise, gross);
      expect(amountAt(tester, 'pnl-rev-total-gst').paise, tax);
      expect(amountAt(tester, 'pnl-rev-total-net').paise, net);

      final expenses =
          amountAt(tester, 'pnl-exp-$pnlCcr-$pnlCcr-kirana-amount').paise +
          amountAt(tester, 'pnl-exp-$pnlHki-$pnlHki-electricity-amount').paise;
      expect(expenses, amountAt(tester, 'pnl-expenses').paise);
      expect(amountAt(tester, 'pnl-exp-total-amount').paise, expenses);
      expect(gross, 14904300);
      expect(expenses, 7500000);
    });

    uiTest('a loss is labelled Operating Loss and keeps its sign', (
      tester,
    ) async {
      gateway
        ..revenue.add(pnlSale(pnlCcr, '2026-09-10', gross: 105000, tax: 5000))
        ..expense.add(pnlCost(pnlCcr, '2026-09-10', 150000));
      await pump(tester);

      expect(textAt(tester, 'pnl-operating-label'), 'Operating Loss');
      expect(amountAt(tester, 'pnl-operating-result').paise, -50000);
      expect(textAt(tester, 'pnl-margin'), '-50.00%');
    });

    uiTest('a period with no trade is a genuine zero, and the margin is N/A', (
      tester,
    ) async {
      await pump(tester);
      expect(amountAt(tester, 'pnl-gross').paise, 0);
      expect(amountAt(tester, 'pnl-operating-result').paise, 0);
      expect(textAt(tester, 'pnl-margin'), 'N/A');
      expect(find.text('0.00%'), findsNothing);
      expect(find.byKey(const Key('pnl-no-trade')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('authorisation', () {
    uiTest('without the D2 intersection nothing is offered or read', (
      tester,
    ) async {
      await pump(
        tester,
        grants: const [
          CapabilityGrant(Capability.reportsView, businessUnitId: pnlCcr),
          CapabilityGrant(Capability.revenueView, businessUnitId: pnlCcr),
          CapabilityGrant(Capability.expenseViewOwn, businessUnitId: pnlCcr),
        ],
      );
      expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
      expect(find.byKey(const Key('pnl-statement')), findsNothing);
      expect(find.byKey(const Key('pnl-scope-selector')), findsNothing);
      expect(gateway.askedUnits, isEmpty);
    });

    uiTest('one property\'s authority offers it alone, and a direct read of '
        'another scope is refused on screen', (tester) async {
      gateway.revenue.addAll([
        pnlSale(pnlCcr, '2026-09-10', gross: 105000, tax: 5000),
        pnlSale(
          pnlHki,
          '2026-09-10',
          gross: 999000,
          tax: 0,
          category: 'banquet',
        ),
      ]);
      final container = await pump(tester, grants: pnlD2(pnlCcr));

      expect(textAt(tester, 'pnl-scope-name'), 'Crystal Canopy Rooftop');
      expect(amountAt(tester, 'pnl-gross').paise, 105000);
      expect(gateway.askedUnits.every((u) => !u.contains(pnlHki)), isTrue);

      await tester.tap(find.byKey(const Key('pnl-scope-selector')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-scope-$pnlCcr')), findsOneWidget);
      expect(find.byKey(const Key('pnl-scope-$pnlHki')), findsNothing);
      expect(find.byKey(const Key('pnl-scope-consolidated')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      container
          .read(pnlSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(pnlHki));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
      expect(find.byKey(const Key('pnl-statement')), findsNothing);

      container
          .read(pnlSelectionProvider.notifier)
          .selectScope(const PnlConsolidatedScope());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the scope bottom sheet', () {
    uiTest('choosing a property closes the sheet and reports that property', (
      tester,
    ) async {
      gateway.revenue.addAll([
        pnlSale(pnlCcr, '2026-09-10', gross: 105000, tax: 5000),
        pnlSale(
          pnlHki,
          '2026-09-10',
          gross: 999000,
          tax: 0,
          category: 'banquet',
        ),
      ]);
      await pump(tester);
      expect(amountAt(tester, 'pnl-gross').paise, 1104000);

      await tester.tap(find.byKey(const Key('pnl-scope-selector')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-scope-sheet')), findsOneWidget);
      for (final key in [
        'pnl-scope-consolidated',
        'pnl-scope-$pnlCcr',
        'pnl-scope-$pnlHki',
      ]) {
        expect(find.byKey(Key(key)).hitTestable(), findsOneWidget, reason: key);
      }

      await tester.tap(find.byKey(const Key('pnl-scope-$pnlCcr')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-scope-sheet')), findsNothing);
      expect(textAt(tester, 'pnl-scope-name'), 'Crystal Canopy Rooftop');
      expect(amountAt(tester, 'pnl-gross').paise, 105000);
    });

    uiTest('Android back closes the sheet and changes nothing', (tester) async {
      final container = await pump(tester);
      await tester.tap(find.byKey(const Key('pnl-scope-selector')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-scope-sheet')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-scope-sheet')), findsNothing);
      expect(find.byType(MobileProfitAndLossPage), findsOneWidget);
      expect(container.read(pnlSelectionProvider).scope, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('periods', () {
    uiTest('consolidated disables a preset the properties disagree about', (
      tester,
    ) async {
      final container = await pump(tester);

      ChoiceChip chip(String name) =>
          tester.widget<ChoiceChip>(find.byKey(Key('pnl-preset-$name')));
      expect(chip('today').onSelected, isNull);
      expect(chip('yesterday').onSelected, isNull);
      expect(chip('thisMonth').onSelected, isNotNull);
      expect(
        find.byKey(const Key('pnl-presets-unavailable-note')),
        findsOneWidget,
      );

      container
          .read(pnlSelectionProvider.notifier)
          .selectPreset(RelativePreset.today);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-preset-unavailable')), findsOneWidget);
      expect(find.textContaining('Use Custom'), findsWidgets);

      // One property has one business date, so Today is available for it.
      container
          .read(pnlSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(pnlCcr));
      await tester.pumpAndSettle();
      expect(chip('today').onSelected, isNotNull);
      expect(
        find.byKey(const Key('pnl-presets-unavailable-note')),
        findsNothing,
      );
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
    });

    uiTest('every preset is reachable in the horizontal strip', (tester) async {
      final container = await pump(tester, size: _phone360);
      container
          .read(pnlSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(pnlCcr));
      await tester.pumpAndSettle();
      for (final preset in [
        ...RelativePreset.values.map((p) => p.name),
        'custom',
      ]) {
        final chip = find.byKey(Key('pnl-preset-$preset'));
        await tester.scrollUntilVisible(
          chip,
          80,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('pnl-period-bar')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(chip.hitTestable(), findsOneWidget, reason: preset);
      }
      await tapInView(tester, find.byKey(const Key('pnl-preset-lastMonth')));
      await tester.pumpAndSettle();
      final view = container.read(pnlViewProvider).value! as PnlReportView;
      expect(view.range.from, BusinessDate.of(2026, 8, 1));
      expect(view.range.to, BusinessDate.of(2026, 8, 31));
    });

    uiTest('Custom opens the calendar picker with no typed entry, and the tapped '
        'days become the P&L dates', (tester) async {
      final semantics = tester.ensureSemantics();
      final container = await pump(tester);
      container
          .read(pnlSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(pnlCcr));
      await tester.pumpAndSettle();

      await tapInView(tester, find.byKey(const Key('pnl-preset-custom')));
      await tester.pumpAndSettle();
      expect(find.text('Profit & loss period'), findsOneWidget);
      // Calendar only: no text field and no switch to typed entry.
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);

      // It opened on the period being reported: September 2026 for Crystal Canopy.
      await tester.tap(dayCell('September 3, 2026'));
      await tester.pumpAndSettle();
      await tester.tap(dayCell('September 17, 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      final period = container.read(pnlSelectionProvider).period;
      expect(period, isA<PnlCustomPeriod>());
      expect((period as PnlCustomPeriod).from, BusinessDate.of(2026, 9, 3));
      expect(period.to, BusinessDate.of(2026, 9, 17));
      expect(
        textAt(tester, 'pnl-custom-range'),
        'Custom: 3 Sep 2026 – 17 Sep 2026',
      );
      final view = container.read(pnlViewProvider).value! as PnlReportView;
      expect(view.range.from, BusinessDate.of(2026, 9, 3));
      expect(view.range.to, BusinessDate.of(2026, 9, 17));
      semantics.dispose();
    });

    for (final (direction, from, to) in [
      ('forward', BusinessDate.of(2027, 3, 1), BusinessDate.of(2027, 3, 31)),
      ('backward', BusinessDate.of(2025, 3, 1), BusinessDate.of(2025, 3, 31)),
    ]) {
      uiTest('Custom scrolls the calendar $direction to dates outside the month '
          'it opened on', (tester) async {
        final semantics = tester.ensureSemantics();
        final container = await pump(tester, size: const Size(412, 915));
        container
            .read(pnlSelectionProvider.notifier)
            .selectScope(const PnlUnitScope(pnlCcr));
        await tester.pumpAndSettle();

        await tapInView(tester, find.byKey(const Key('pnl-preset-custom')));
        await tester.pumpAndSettle();
        const names = [
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
        // The month list is the scrollable nearest a day the picker opened on. The first
        // vertical scrollable inside the dialog is not it, and dragging that one moves
        // nothing. Bound to the element once, so it survives that day scrolling away.
        final monthsElement = tester.element(
          find
              .ancestor(
                of: dayCell('September 1, 2026'),
                // Each month is its own non-scrolling grid; the list of months is the
                // nearest ancestor that can actually scroll.
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Scrollable &&
                      w.physics is! NeverScrollableScrollPhysics,
                ),
              )
              .first,
        );
        final months = find.byElementPredicate((e) => e == monthsElement);
        for (final day in [from, to]) {
          final cell = dayCell(
            '${names[day.month - 1]} ${day.day}, ${day.year}',
          );
          await tester.scrollUntilVisible(
            cell,
            day >= BusinessDate.of(2026, 9, 1) ? 250 : -250,
            scrollable: months,
            maxScrolls: 400,
          );
          await tester.pumpAndSettle();
          await tester.tap(cell);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(
          container.read(pnlSelectionProvider).period,
          PnlCustomPeriod(from, to),
        );
        semantics.dispose();
      });
    }

    uiTest('Android back dismisses the picker and changes nothing', (
      tester,
    ) async {
      final container = await pump(tester);
      await tapInView(tester, find.byKey(const Key('pnl-preset-custom')));
      await tester.pumpAndSettle();
      expect(find.text('Profit & loss period'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Profit & loss period'), findsNothing);
      expect(
        container.read(pnlSelectionProvider).period,
        const PnlPresetPeriod(RelativePreset.thisMonth),
      );
      expect(find.byType(MobileProfitAndLossPage), findsOneWidget);
    });

    uiTest('a range that ends before it starts is refused, never swapped', (
      tester,
    ) async {
      final container = await pump(tester);
      final dates = pnlCustomDatesFrom(
        _Reversed(DateTime(2026, 9, 10), DateTime(2026, 9, 1)),
      )!;
      expect(dates.from, BusinessDate.of(2026, 9, 10));
      expect(dates.to, BusinessDate.of(2026, 9, 1));
      container
          .read(pnlSelectionProvider.notifier)
          .selectCustom(dates.from, dates.to);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-invalid-range')), findsOneWidget);
      expect(find.byKey(const Key('pnl-statement')), findsNothing);
    });
  });

  group('picker dates are calendar days, never converted', () {
    test('a dismissed picker gives no dates', () {
      expect(pnlCustomDatesFrom(null), isNull);
    });

    test('only year, month and day are read', () {
      final late = pnlCustomDatesFrom(
        DateTimeRange(
          start: DateTime(2026, 3, 1, 0, 1),
          end: DateTime(2026, 3, 31, 23, 59),
        ),
      )!;
      expect(late.from, BusinessDate.of(2026, 3, 1));
      expect(late.to, BusinessDate.of(2026, 3, 31));

      // A UTC instant late in the day is not moved into the next day by a device zone.
      final utc = pnlCustomDatesFrom(
        DateTimeRange(
          start: DateTime.utc(2026, 3, 31, 23, 30),
          end: DateTime.utc(2026, 3, 31, 23, 45),
        ),
      )!;
      expect(utc.from, BusinessDate.of(2026, 3, 31));
      expect(utc.to, BusinessDate.of(2026, 3, 31));
    });

    test('the picker opens on the calendar day of a P&L date', () {
      final day = pnlCalendarDay(BusinessDate.of(2027, 3, 10));
      expect((day.year, day.month, day.day), (2027, 3, 10));
      expect(day.isUtc, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('older history', () {
    uiTest('not downloaded is offered for download, and then computes', (
      tester,
    ) async {
      gateway.revenue.add(
        pnlSale(pnlCcr, '2023-06-10', gross: 210000, tax: 10000),
      );
      final container = await pump(tester);
      await selectCustom(
        container,
        tester,
        BusinessDate.of(2023, 6, 1),
        BusinessDate.of(2023, 6, 30),
      );

      expect(find.byKey(const Key('pnl-not-downloaded')), findsOneWidget);
      expect(find.byKey(const Key('pnl-statement')), findsNothing);
      await tapInView(tester, find.byKey(const Key('pnl-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
      expect(amountAt(tester, 'pnl-gross').paise, 210000);
    });

    uiTest('a custom range across two missing years downloads both first', (
      tester,
    ) async {
      gateway.revenue.addAll([
        pnlSale(pnlCcr, '2023-03-20', gross: 105000, tax: 5000),
        pnlSale(pnlCcr, '2023-04-05', gross: 210000, tax: 10000),
      ]);
      final container = await pump(tester);
      await selectCustom(
        container,
        tester,
        BusinessDate.of(2023, 3, 15),
        BusinessDate.of(2023, 4, 15),
      );
      expect(find.textContaining('FY 22-23, FY 23-24'), findsOneWidget);
      await tapInView(tester, find.byKey(const Key('pnl-download')));
      await tester.pumpAndSettle();
      expect(amountAt(tester, 'pnl-gross').paise, 315000);
    });

    uiTest('downloading required history is shown while it runs', (
      tester,
    ) async {
      gateway.revenue.add(
        pnlSale(pnlCcr, '2023-06-10', gross: 210000, tax: 10000),
      );
      final container = await pump(tester);
      await selectCustom(
        container,
        tester,
        BusinessDate.of(2023, 6, 1),
        BusinessDate.of(2023, 6, 30),
      );

      gateway.gate = Completer<void>();
      await tapInView(tester, find.byKey(const Key('pnl-download')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byKey(const Key('pnl-downloading')), findsOneWidget);

      gateway.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
    });

    uiTest('a failed download says a connection is required, and shows no '
        'figure', (tester) async {
      gateway.revenue.add(
        pnlSale(pnlCcr, '2023-06-10', gross: 210000, tax: 10000),
      );
      final container = await pump(tester);
      await selectCustom(
        container,
        tester,
        BusinessDate.of(2023, 6, 1),
        BusinessDate.of(2023, 6, 30),
      );

      gateway.snapshotUnreachable = RemoteFailure.offline;
      await tapInView(tester, find.byKey(const Key('pnl-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-download-failed')), findsOneWidget);
      expect(find.textContaining('connection is required'), findsOneWidget);
      expect(find.byKey(const Key('pnl-statement')), findsNothing);
    });

    uiTest('with no server, missing history says a connection is required', (
      tester,
    ) async {
      final container = await pump(tester, withGateway: false);
      await selectCustom(
        container,
        tester,
        BusinessDate.of(2023, 6, 1),
        BusinessDate.of(2023, 6, 30),
      );
      expect(find.byKey(const Key('pnl-not-downloaded')), findsOneWidget);
      expect(find.textContaining('connection is required'), findsOneWidget);
      expect(find.byKey(const Key('pnl-download')), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('synchronisation and freshness', () {
    uiTest('synchronising is shown on first open until the report lands', (
      tester,
    ) async {
      gateway
        ..revenue.add(pnlSale(pnlCcr, '2026-09-10', gross: 105000, tax: 5000))
        ..gate = Completer<void>();
      await pump(tester, settle: false);
      expect(find.byKey(const Key('pnl-synchronising')), findsOneWidget);

      gateway.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
    });

    uiTest('pull-to-refresh runs the same synchronisation', (tester) async {
      gateway.revenue.add(
        pnlSale(pnlCcr, '2026-09-10', gross: 105000, tax: 5000),
      );
      await pump(tester);
      final before = gateway.snapshots;
      expect(amountAt(tester, 'pnl-gross').paise, 105000);

      gateway.revenue.add(
        pnlSale(pnlCcr, '2026-09-12', gross: 21000, tax: 1000),
      );
      await tester.fling(pageScrollable(), const Offset(0, 500), 1500);
      await tester.pumpAndSettle();
      expect(gateway.snapshots, greaterThan(before));
      expect(amountAt(tester, 'pnl-gross').paise, 126000);
    });

    uiTest('an unreachable server leaves the complete report readable', (
      tester,
    ) async {
      gateway.revenue.add(
        pnlSale(pnlCcr, '2026-09-10', gross: 105000, tax: 5000),
      );
      await pump(tester);
      gateway
        ..snapshotUnreachable = RemoteFailure.offline
        ..newerUnreachable = RemoteFailure.offline;

      await tester.tap(find.byKey(const Key('pnl-refresh')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-offline')), findsOneWidget);
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
      expect(
        find.byKey(const Key('pnl-freshness-synchronised')),
        findsOneWidget,
      );
      expect(amountAt(tester, 'pnl-gross').paise, 105000);
    });

    uiTest(
      'newer canonical changes on the server are stated, no figure moves',
      (tester) async {
        gateway.revenue.add(
          pnlSale(pnlCcr, '2026-09-10', gross: 105000, tax: 5000),
        );
        await pump(tester);
        gateway
          ..revenue.add(pnlSale(pnlCcr, '2026-09-12', gross: 21000, tax: 1000))
          ..snapshotUnreachable = RemoteFailure.serverUnreachable;

        await tester.tap(find.byKey(const Key('pnl-refresh')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('pnl-freshness-server-newer')),
          findsOneWidget,
        );
        expect(amountAt(tester, 'pnl-gross').paise, 105000);
      },
    );

    uiTest('figures from two synchronisation runs state no single time', (
      tester,
    ) async {
      final cache = ReportingCache(db);
      for (final (unit, snapshot) in const [
        (pnlCcr, 'run-a'),
        (pnlHki, 'run-b'),
      ]) {
        await cache.applySnapshot(
          ownerUserId: pnlMe,
          orgId: 'test-org',
          snapshotId: snapshot,
          serverConfirmedAt: DateTime.utc(2026, 9, 19, 20),
          businessUnitIds: {unit},
          financialYears: const [2026],
          datasets: {
            for (final dataset in ReportingDataset.values)
              dataset: const DatasetApplication(
                documentIds: [],
                rowsByYear: {2026: []},
                generationByYear: {2026: 1},
              ),
          },
          onDemand: false,
          now: DateTime.utc(2026, 9, 19, 20),
        );
      }
      await pump(tester, withGateway: false);
      expect(find.byKey(const Key('pnl-freshness-none')), findsOneWidget);
    });

    for (final (missing, key) in const [
      (ReportingDataset.revenue, 'pnl-revenue-unavailable'),
      (ReportingDataset.expense, 'pnl-expense-unavailable'),
    ]) {
      uiTest(
        'a missing ${missing.wireName} side is named, never shown as zero',
        (tester) async {
          await ReportingCache(db).applySnapshot(
            ownerUserId: pnlMe,
            orgId: 'test-org',
            snapshotId: 'one-side',
            serverConfirmedAt: DateTime.utc(2026, 9, 19, 20),
            businessUnitIds: const {pnlCcr},
            financialYears: const [2026],
            datasets: {
              for (final dataset in ReportingDataset.values)
                if (dataset != missing)
                  dataset: const DatasetApplication(
                    documentIds: [],
                    rowsByYear: {2026: []},
                    generationByYear: {2026: 1},
                  ),
            },
            onDemand: false,
            now: DateTime.utc(2026, 9, 19, 20),
          );
          final container = await pump(tester, withGateway: false);
          container
              .read(pnlSelectionProvider.notifier)
              .selectScope(const PnlUnitScope(pnlCcr));
          await tester.pumpAndSettle();
          expect(find.byKey(Key(key)), findsOneWidget);
          expect(find.byKey(const Key('pnl-statement')), findsNothing);
        },
      );
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('layout on phones, in every state', () {
    Future<void> profit(WidgetTester tester, Size size, double scale) async {
      gateway
        ..revenue.addAll([
          pnlSale(pnlCcr, '2026-09-10', gross: 1236420000, tax: 58877143),
          pnlSale(
            pnlHki,
            '2026-09-11',
            gross: 403430000,
            tax: 0,
            category: 'banquet',
          ),
        ])
        ..expense.addAll([
          pnlCost(pnlCcr, '2026-09-10', 450000000),
          pnlCost(pnlHki, '2026-09-11', 300000000, category: 'electricity'),
        ]);
      await pump(tester, size: size, textScale: scale);
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
    }

    final states = <String, Future<void> Function(WidgetTester, Size, double)>{
      'profit with categories': profit,
      'loss': (tester, size, scale) async {
        gateway
          ..revenue.add(pnlSale(pnlCcr, '2026-09-10', gross: 105000, tax: 5000))
          ..expense.add(pnlCost(pnlCcr, '2026-09-10', 98765432100));
        await pump(tester, size: size, textScale: scale);
        expect(find.text('Operating Loss'), findsOneWidget);
      },
      'not authorised': (tester, size, scale) async {
        await pump(tester, size: size, textScale: scale, grants: const []);
        expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
      },
      'preset unavailable': (tester, size, scale) async {
        final container = await pump(tester, size: size, textScale: scale);
        container
            .read(pnlSelectionProvider.notifier)
            .selectPreset(RelativePreset.today);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pnl-preset-unavailable')), findsOneWidget);
      },
      'not downloaded': (tester, size, scale) async {
        final container = await pump(tester, size: size, textScale: scale);
        await selectCustom(
          container,
          tester,
          BusinessDate.of(2023, 6, 1),
          BusinessDate.of(2023, 6, 30),
        );
        expect(find.byKey(const Key('pnl-not-downloaded')), findsOneWidget);
      },
      'download failed': (tester, size, scale) async {
        final container = await pump(tester, size: size, textScale: scale);
        await selectCustom(
          container,
          tester,
          BusinessDate.of(2023, 6, 1),
          BusinessDate.of(2023, 6, 30),
        );
        gateway.snapshotUnreachable = RemoteFailure.offline;
        await tester.ensureVisible(find.byKey(const Key('pnl-download')));
        await tapInView(tester, find.byKey(const Key('pnl-download')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pnl-download-failed')), findsOneWidget);
      },
      'offline and readable': (tester, size, scale) async {
        gateway.revenue.add(
          pnlSale(pnlCcr, '2026-09-10', gross: 105000, tax: 5000),
        );
        await pump(tester, size: size, textScale: scale);
        gateway
          ..snapshotUnreachable = RemoteFailure.offline
          ..newerUnreachable = RemoteFailure.offline;
        await tester.tap(find.byKey(const Key('pnl-refresh')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pnl-offline')), findsOneWidget);
      },
      'scope sheet open': (tester, size, scale) async {
        await pump(tester, size: size, textScale: scale);
        await tester.tap(find.byKey(const Key('pnl-scope-selector')));
        await tester.pumpAndSettle();
        for (final key in [
          'pnl-scope-consolidated',
          'pnl-scope-$pnlCcr',
          'pnl-scope-$pnlHki',
        ]) {
          await tester.ensureVisible(find.byKey(Key(key)));
          expect(
            find.byKey(Key(key)).hitTestable(),
            findsOneWidget,
            reason: key,
          );
        }
      },
      'date picker open': (tester, size, scale) async {
        await pump(tester, size: size, textScale: scale);
        await tester.ensureVisible(find.byKey(const Key('pnl-preset-custom')));
        await tester.pumpAndSettle();
        await tapInView(tester, find.byKey(const Key('pnl-preset-custom')));
        await tester.pumpAndSettle();
        expect(find.text('Profit & loss period'), findsOneWidget);
        expect(find.text('Apply').hitTestable(), findsOneWidget);
      },
    };

    for (final (label, size, scale) in const [
      ('360 × 740', _phone360, 1.0),
      ('390 × 844', _phone390, 1.0),
      ('430 × 932', _phone430, 1.0),
      ('844 × 390 landscape', _landscape, 1.0),
      ('360 × 740 at 1.3× text', _phone360, 1.3),
    ]) {
      for (final entry in states.entries) {
        uiTest('${entry.key} at $label renders without overflow', (
          tester,
        ) async {
          await entry.value(tester, size, scale);
          expect(tester.takeException(), isNull);
        });
      }

      uiTest('at $label nothing sits behind the status bar, the bottom bar or '
          'the [ + ] action', (tester) async {
        await profit(tester, size, scale);

        // Clear of the status bar.
        expect(
          tester.getRect(find.text('Profit & Loss')).top,
          greaterThanOrEqualTo(_statusBar),
        );
        // The refresh control and the scope selector can be reached.
        expect(
          find.byKey(const Key('pnl-refresh')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('pnl-scope-selector')).hitTestable(),
          findsOneWidget,
        );

        // Scrolled to the end, the last line stays above the docked action.
        await tester.drag(pageScrollable(), const Offset(0, -20000));
        await tester.pumpAndSettle();
        final last = find.byKey(const Key('pnl-exp-total-amount'));
        expect(last.hitTestable(), findsOneWidget);
        final fab = tester.getRect(find.byType(FloatingActionButton));
        expect(tester.getRect(last).bottom, lessThanOrEqualTo(fab.top));
        expect(
          tester.getRect(find.byKey(const Key('pnl-basis'))).bottom,
          lessThanOrEqualTo(fab.top),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// A range whose end precedes its start, as no well-behaved picker returns but a caller
/// might. `DateTimeRange` asserts against it, so the check is bypassed here only to prove
/// the conversion neither swaps nor repairs it.
final class _Reversed implements DateTimeRange {
  _Reversed(this.start, this.end);

  @override
  final DateTime start;

  @override
  final DateTime end;

  @override
  Duration get duration => end.difference(start);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
