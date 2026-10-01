/// Dashboard and analytics figures, opened into the existing Phase 5 drill-down
/// (Phase 6 Slice 9).
///
/// What is real: both shells and their routers, the Overview, the Analytics workspace, the
/// Android Home, the shared adapter (`dashboard_drill.dart`), the Phase 5 drill-down
/// providers, view and pages, the immutable document bodies, `ReportDocumentReader`, the
/// canonical reporting cache, `ReportingSync`, the local engine and every domain rule. What
/// is substituted: only the network — the reporting snapshot and the document projections —
/// and "now". A test never hands a widget a figure, and never hands the destination one.
///
/// The numbers in the test names are the brief's own proofs, 1 … 34.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/app/routing/app_routes.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/core/design/charts/charts.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_navigation.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_page.dart';
import 'package:krishna_mis/features/attachments/presentation/attachment_strip.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_drill.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/dashboard/presentation/mobile_home_page.dart';
import 'package:krishna_mis/features/dashboard/presentation/overview_page.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_pnl_drilldown_pages.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_profit_and_loss_page.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_view.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/profit_and_loss_page.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/pnl_fixture.dart';
import '../support/report_detail_fakes.dart';
import '../support/ui_harness.dart';

const _laptop = Size(1366, 900);
const _phone = Size(390, 844);

/// Saturday 19 September 2026, 12:00 UTC — 17:30 IST: both properties are on the 19th, so
/// a consolidated relative period describes one pair.
final _now = DateTime.utc(2026, 9, 19, 12);

BusinessDate _d(int month, int day) => BusinessDate.of(2026, month, day);

/// The P&L intersection, plus every capability a ledger would act on.
List<CapabilityGrant> _mutationCapable([String? unit]) => [
  ...pnlD2(unit),
  for (final c in const [
    Capability.revenueCreate,
    Capability.revenueEdit,
    Capability.revenueEditAll,
    Capability.revenueVoid,
    Capability.expenseCreate,
    Capability.expenseEditOwn,
    Capability.expenseEditAll,
    Capability.expenseVoid,
    Capability.attachmentView,
    Capability.attachmentUpload,
  ])
    CapabilityGrant(c, businessUnitId: unit),
];

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late FakeReportingGateway gateway;
  late FakeRevenueDocuments revenueDocs;
  late FakeExpenseDocuments expenseDocs;
  late SwitchableSession session;

  // The fixture, kept so a test can name a document by the row that produced it.
  late Map<String, dynamic> restaurantSale;
  late Map<String, dynamic> nandbhogSale;
  late Map<String, dynamic> augustSale;
  late Map<String, dynamic> kiranaCost;
  late Map<String, dynamic> banquetSale;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeReportingGateway();
    revenueDocs = FakeRevenueDocuments();
    expenseDocs = FakeExpenseDocuments();
    await seedPnlMasters(db);

    restaurantSale = pnlSale(pnlCcr, '2026-09-10', gross: 1050000, tax: 50000);
    nandbhogSale = pnlSale(
      pnlCcr,
      '2026-09-12',
      gross: 210000,
      tax: 10000,
      category: 'nandbhog',
    );
    augustSale = pnlSale(pnlCcr, '2026-08-05', gross: 525000, tax: 25000);
    kiranaCost = pnlCost(pnlCcr, '2026-09-11', 400000);
    final augustCost = pnlCost(pnlCcr, '2026-08-06', 100000);
    banquetSale = pnlSale(
      pnlHki,
      '2026-09-15',
      gross: 300000,
      tax: 0,
      category: 'banquet',
    );
    final electricity = pnlCost(
      pnlHki,
      '2026-09-16',
      150000,
      category: 'electricity',
    );

    gateway
      ..revenue.addAll([restaurantSale, nandbhogSale, augustSale, banquetSale])
      ..expense.addAll([kiranaCost, augustCost, electricity]);
    for (final sale in [
      restaurantSale,
      nandbhogSale,
      augustSale,
      banquetSale,
    ]) {
      revenueDocs.addFromSale(sale);
    }
    for (final cost in [kiranaCost, augustCost, electricity]) {
      expenseDocs.addFromCosts(
        [cost],
        complete: true,
        visibleMinor: cost['amount_minor'] as int,
      );
    }
  });
  tearDown(() => db.close());

  List<Override> overrides(List<CapabilityGrant> grants) => [
    databaseProvider.overrideWithValue(db),
    sessionProvider.overrideWith(() {
      session = SwitchableSession(pnlSession(grants: grants));
      return session;
    }),
    reportingClockProvider.overrideWithValue(() => _now),
    reportingGatewayProvider.overrideWithValue(gateway),
    expenseGatewayProvider.overrideWithValue(expenseDocs),
    revenueGatewayProvider.overrideWithValue(revenueDocs),
  ];

  Future<(ProviderContainer, GoRouter)> pumpWindows(
    WidgetTester tester, {
    List<CapabilityGrant>? grants,
    String initial = AppRoutes.overview,
  }) async {
    await tester.binding.setSurfaceSize(_laptop);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = AppRouter.create(
      shellKind: AppShellKind.desktop,
      initialLocation: initial,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(grants ?? pnlD2(pnlCcr)),
        child: MaterialApp.router(
          theme: AppTheme.desktop,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final anchor = initial == AppRoutes.overview
        ? find.byType(OverviewPage)
        : find.byType(AnalyticsPage);
    return (ProviderScope.containerOf(tester.element(anchor)), router);
  }

  Future<ProviderContainer> pumpPhone(
    WidgetTester tester, {
    List<CapabilityGrant>? grants,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = _phone
      ..padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    final router = AppRouter.create(
      shellKind: AppShellKind.mobile,
      initialLocation: AppRoutes.home,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(grants ?? pnlD2(pnlCcr)),
        child: MaterialApp.router(theme: AppTheme.mobile, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(MobileHomePage)),
    );
  }

  Future<void> tapKey(WidgetTester tester, Key key, {Finder? within}) async {
    final finder = within == null
        ? find.byKey(key)
        : find.descendant(of: within, matching: find.byKey(key));
    expect(finder, findsOneWidget, reason: '$key');
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<DashboardReady> readyOf(ProviderContainer c) async =>
      await c.read(dashboardViewProvider.future) as DashboardReady;

  DashboardDrillTargets targetsOf(ProviderContainer c, DashboardReady ready) =>
      DashboardDrillTargets.of(ready, c.read(principalProvider));

  Future<PnlDrillView> levelOf(
    ProviderContainer c,
    PnlDrillLocation location,
  ) async {
    final sub = c.listen(pnlDrillLevelProvider(location), (_, _) {});
    addTearDown(sub.close);
    return c.read(pnlDrillLevelProvider(location).future);
  }

  PnlDrillLocation openLocation(ProviderContainer c) =>
      c.read(dashboardDrillProvider)!.location;

  /// Opens position [index] of the chart inside [section] from the keyboard — Home, then
  /// right, then Enter — the path a reader without a mouse takes.
  Future<void> openChartPoint(
    WidgetTester tester,
    Key section,
    int index,
  ) async {
    final panel = find.byKey(section);
    await tester.ensureVisible(panel);
    await tester.pumpAndSettle();
    final node = tester
        .widgetList<Focus>(
          find.descendant(of: panel, matching: find.byType(Focus)),
        )
        .map((f) => f.focusNode)
        .firstWhere((n) => n?.debugLabel == 'chart')!;
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    for (var i = 0; i < index; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  Future<void> openSection(
    WidgetTester tester,
    ProviderContainer c,
    AnalyticsSection section,
  ) async {
    await tapKey(tester, Key('analytics-section-${section.name}'));
  }

  Key revenueCategoryRow(String unit, String category) =>
      Key('pnl-drill-revenue-category-$unit-$unit-$category');

  void expectNoMutationSurface() {
    for (final key in const [
      'revenue-edit',
      'revenue-void',
      'edit-expense',
      'void-expense',
      'revenue-conflict-review-latest',
      'conflict-review-latest',
      'revenue-evidence',
      'attention-banner',
      'revenue-conflict-banner',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    expect(find.byType(AttachmentStrip), findsNothing);
    for (final text in const [
      'Edit',
      'Edit expense',
      'Void',
      'Review latest',
    ]) {
      expect(find.text(text), findsNothing, reason: text);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Windows Overview · 1 … 12
  // ═══════════════════════════════════════════════════════════════════════════

  group('Windows Overview', () {
    uiTest(
      '1 · Net Sales opens the revenue drill-down for the scope and period',
      (tester) async {
        final (c, _) = await pumpWindows(tester);
        final ready = await readyOf(c);

        await tapKey(tester, const Key('dashboard-net-sales-open'));

        final location = openLocation(c);
        expect(location, isA<PnlRevenueCategoriesAt>());
        expect(location.anchor.origin, PnlDrillOrigin.dashboard);
        expect(location.anchor.businessUnitIds, [pnlCcr]);
        expect(location.anchor.range.from, ready.pair.current.from);
        expect(location.anchor.range.to, ready.pair.current.to);
        expect(find.byKey(const Key('dashboard-drill')), findsOneWidget);
        expect(
          find.byKey(revenueCategoryRow(pnlCcr, 'restaurant')),
          findsOneWidget,
        );
        expect(
          find.byKey(revenueCategoryRow(pnlCcr, 'nandbhog')),
          findsOneWidget,
        );
        // The destination read its own report; its total is the canonical Net Sales.
        final level = await levelOf(c, location) as PnlRevenueLevelView;
        expect(level.parent.net, ready.view.resultOrNull!.netSales);
      },
    );

    uiTest('2 · Operating Expenses opens the expense departments', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester);
      await tapKey(tester, const Key('dashboard-expenses-open'));

      expect(openLocation(c), isA<PnlExpenseDepartmentsAt>());
      expect(
        find.byKey(Key('pnl-drill-dept-$pnlCcr-$pnlCcr-dept')),
        findsOneWidget,
      );
    });

    uiTest(
      '3 · Operating Profit opens the existing P&L — no profit documents exist',
      (tester) async {
        final (c, router) = await pumpWindows(tester);
        final ready = await readyOf(c);
        await tapKey(tester, const Key('dashboard-operating-open'));

        expect(c.read(dashboardDrillProvider), isNull);
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          AppRoutes.analytics,
        );
        expect(
          c.read(analyticsSectionProvider),
          AnalyticsSection.profitAndLoss,
        );
        expect(find.byKey(const Key('pnl-page')), findsOneWidget);
        final selection = c.read(pnlSelectionProvider);
        expect(selection.scope, const PnlUnitScope(pnlCcr));
        expect(
          selection.period,
          PnlCustomPeriod(ready.pair.current.from, ready.pair.current.to),
        );
      },
    );

    uiTest(
      '4 · Operating Margin opens the existing P&L, not margin documents',
      (tester) async {
        final (c, _) = await pumpWindows(tester);
        final ready = await readyOf(c);
        await tapKey(tester, const Key('dashboard-margin-open'));

        expect(c.read(dashboardDrillProvider), isNull);
        expect(
          c.read(analyticsSectionProvider),
          AnalyticsSection.profitAndLoss,
        );
        expect(
          c.read(pnlSelectionProvider).period,
          PnlCustomPeriod(ready.pair.current.from, ready.pair.current.to),
        );
      },
    );

    uiTest('Gross Sales and GST open the P&L; there is no GST drill-down', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester);
      await tapKey(tester, const Key('dashboard-gross-gst-open'));

      expect(c.read(dashboardDrillProvider), isNull);
      expect(c.read(analyticsSectionProvider), AnalyticsSection.profitAndLoss);
      expect(c.read(pnlSelectionProvider).period, isA<PnlCustomPeriod>());
    });

    uiTest('5 · a revenue mix row opens its canonical category documents', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester);
      await tapKey(
        tester,
        RankedBarChart.rowKey(0),
        within: find.byKey(const Key('dashboard-revenue-mix')),
      );

      final location = openLocation(c) as PnlRevenueDocumentsAt;
      expect(location.businessUnitId, pnlCcr);
      expect(location.revenueCategoryId, '$pnlCcr-restaurant');
      expect(
        find.byKey(Key('pnl-drill-doc-${restaurantSale['revenue_entry_id']}')),
        findsOneWidget,
      );
      // From a dashboard, Revenue is a level of its own, and it opens.
      await tapKey(tester, const Key('pnl-crumb-revenue'));
      expect(openLocation(c), isA<PnlRevenueCategoriesAt>());
    });

    uiTest('6 · a top expense row opens its category documents, full path', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester);
      await tapKey(
        tester,
        RankedBarChart.rowKey(0),
        within: find.byKey(const Key('dashboard-top-expenses')),
      );

      final location = openLocation(c) as PnlExpenseDocumentsAt;
      expect(location.businessUnitId, pnlCcr);
      expect(location.departmentId, '$pnlCcr-dept');
      expect(location.sectionId, '$pnlCcr-section');
      expect(location.categoryId, '$pnlCcr-kirana');
      expect(
        find.byKey(Key('pnl-drill-doc-${kiranaCost['expense_id']}')),
        findsOneWidget,
      );
    });

    uiTest('7 · a department row opens that department\'s sections', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester);
      await tapKey(
        tester,
        RankedBarChart.rowKey(0),
        within: find.byKey(const Key('dashboard-departments')),
      );

      final location = openLocation(c) as PnlExpenseSectionsAt;
      expect(location.departmentId, '$pnlCcr-dept');
      expect(
        find.byKey(Key('pnl-drill-section-$pnlCcr-$pnlCcr-section')),
        findsOneWidget,
      );
    });

    uiTest('8 · a trend point carries its exact bucket range', (tester) async {
      final (c, _) = await pumpWindows(tester);
      // Month to date is daily: position 9 is 10 September.
      await openChartPoint(tester, const Key('dashboard-trend-net-sales'), 9);

      final location = openLocation(c);
      expect(location, isA<PnlRevenueCategoriesAt>());
      expect(location.anchor.range.from, _d(9, 10));
      expect(location.anchor.range.to, _d(9, 10));
      final level = await levelOf(c, location) as PnlRevenueLevelView;
      // That day held one sale, and only that sale is beneath it.
      expect(level.children.single.revenueCategoryId, '$pnlCcr-restaurant');
      expect(level.parent.gross.paise, restaurantSale['gross_minor']);
    });

    uiTest('9 · a clipped first bucket carries its clipped range', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester);
      // 46 days: weekly. The first week begins Monday 3 August and is clipped to the 5th.
      c
          .read(dashboardSelectionProvider.notifier)
          .selectCustom(_d(8, 5), _d(9, 19));
      await tester.pumpAndSettle();
      final ready = await readyOf(c);
      final series = ready.view.trends.firstWhere(
        (s) => s.measure == TrendMeasure.netSales,
      );
      expect(series.grain, TrendGrain.weekly);
      expect(series.points.first.bucket.partial, isTrue);

      await openChartPoint(tester, const Key('dashboard-trend-net-sales'), 0);

      final range = openLocation(c).anchor.range;
      expect(range.from, _d(8, 5), reason: 'the clipped start, not Monday 3rd');
      expect(range.to, _d(8, 9));
      expect(range, series.points.first.bucket.range);
    });

    uiTest('10 · a custom period drills over exactly the chosen range', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester);
      c
          .read(dashboardSelectionProvider.notifier)
          .selectCustom(_d(9, 10), _d(9, 15));
      await tester.pumpAndSettle();
      await tapKey(tester, const Key('dashboard-net-sales-open'));

      final range = openLocation(c).anchor.range;
      expect(range.from, _d(9, 10));
      expect(range.to, _d(9, 15));
    });

    uiTest(
      '12 · a single-property authority cannot manufacture another property\'s intent',
      (tester) async {
        final (c, _) = await pumpWindows(tester);
        final ready = await readyOf(c);
        final targets = targetsOf(c, ready);

        // A line of another property yields nothing to open…
        expect(targets.property(pnlHki), isNull);
        expect(
          targets.revenueCategory(
            RevenueCategoryLine(
              businessUnitId: pnlHki,
              revenueCategoryId: '$pnlHki-banquet',
              totals: RevenueTotals.zero,
            ),
          ),
          isNull,
        );
        // …and a location built by hand is refused at the destination, before any read.
        final anchor = PnlDrillAnchor.dashboard(
          viewerUserId: pnlMe,
          scope: ReportingScope.unit(pnlHki),
          range: ready.pair.current,
        );
        expect(
          await levelOf(c, PnlRevenueCategoriesAt(anchor)),
          isA<PnlDrillRefused>().having(
            (r) => r.reason,
            'reason',
            PnlDrillRefusal.notAuthorised,
          ),
        );
        expect(c.exists(pnlDashboardDrillReportProvider(anchor)), isFalse);
        // And the P&L refuses a handed-off scope it would not offer.
        c
            .read(pnlSelectionProvider.notifier)
            .selectScope(const PnlUnitScope(pnlHki));
        expect(await c.read(pnlViewProvider.future), isA<PnlNotAuthorised>());
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Windows Analytics · 11, 17 … 20, 31 … 33
  // ═══════════════════════════════════════════════════════════════════════════

  group('Windows Analytics', () {
    uiTest('11 · a Business Comparison property opens that property\'s P&L', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(
        tester,
        grants: pnlD2(),
        initial: AppRoutes.analytics,
      );
      await openSection(tester, c, AnalyticsSection.businessComparison);
      final ready = await readyOf(c);

      await tapKey(tester, Key('analytics-comparison-$pnlHki-open'));

      expect(c.read(analyticsSectionProvider), AnalyticsSection.profitAndLoss);
      final selection = c.read(pnlSelectionProvider);
      expect(selection.scope, const PnlUnitScope(pnlHki));
      expect(
        selection.period,
        PnlCustomPeriod(ready.pair.current.from, ready.pair.current.to),
      );
      expect(find.byKey(const Key('pnl-page')), findsOneWidget);
    });

    uiTest('17 · a Revenue Analysis category row opens its documents', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester, initial: AppRoutes.analytics);
      await openSection(tester, c, AnalyticsSection.revenue);
      await tapKey(
        tester,
        RankedBarChart.rowKey(0),
        within: find.byKey(const Key('analytics-revenue-mix')),
      );

      final drill = c.read(dashboardDrillProvider)!;
      expect(drill.origin, DashboardDrillOrigin.revenueAnalysis);
      expect(drill.location, isA<PnlRevenueDocumentsAt>());
      expect(
        find.byKey(Key('pnl-drill-doc-${restaurantSale['revenue_entry_id']}')),
        findsOneWidget,
      );
      expect(find.text('Back to Revenue Analysis'), findsOneWidget);
    });

    uiTest('Revenue Analysis Net Sales and trend open the revenue context', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester, initial: AppRoutes.analytics);
      await openSection(tester, c, AnalyticsSection.revenue);
      await tapKey(tester, const Key('analytics-revenue-net-sales-open'));
      expect(openLocation(c), isA<PnlRevenueCategoriesAt>());
      await tapKey(tester, const Key('dashboard-drill-back'));

      await openChartPoint(tester, const Key('analytics-revenue-trend'), 11);
      final range = openLocation(c).anchor.range;
      expect(range.from, _d(9, 12));
      expect(range.to, _d(9, 12));
    });

    uiTest('18 · an Expense Analysis category row opens its documents', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester, initial: AppRoutes.analytics);
      await openSection(tester, c, AnalyticsSection.expenses);
      await tapKey(
        tester,
        RankedBarChart.rowKey(0),
        within: find.byKey(const Key('analytics-top-expenses')),
      );

      expect(openLocation(c), isA<PnlExpenseDocumentsAt>());
      expect(
        find.byKey(Key('pnl-drill-doc-${kiranaCost['expense_id']}')),
        findsOneWidget,
      );
    });

    uiTest('19 · a Department Analysis row opens the department hierarchy', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester, initial: AppRoutes.analytics);
      await openSection(tester, c, AnalyticsSection.expenses);
      await tapKey(
        tester,
        RankedBarChart.rowKey(0),
        within: find.byKey(const Key('analytics-departments')),
      );

      expect(openLocation(c), isA<PnlExpenseSectionsAt>());
      await tapKey(tester, Key('pnl-drill-section-$pnlCcr-$pnlCcr-section'));
      expect(openLocation(c), isA<PnlExpenseCategoriesAt>());
    });

    uiTest('the expense headline and a monthly point open the departments', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester, initial: AppRoutes.analytics);
      c
          .read(dashboardSelectionProvider.notifier)
          .selectPeriod(DashboardPeriodKind.financialYearToDate);
      await openSection(tester, c, AnalyticsSection.expenses);

      await tapKey(tester, const Key('analytics-expense-total-open'));
      expect(openLocation(c), isA<PnlExpenseDepartmentsAt>());
      await tapKey(tester, const Key('dashboard-drill-back'));

      // Financial year to date is monthly: position 5 is September, clipped to the 19th.
      await openChartPoint(tester, const Key('analytics-expense-trend'), 5);
      final location = openLocation(c);
      expect(location, isA<PnlExpenseDepartmentsAt>());
      expect(location.anchor.range.from, _d(9, 1));
      expect(location.anchor.range.to, _d(9, 19));
    });

    uiTest('20 · the Profit & Loss section is still the Phase 5 page', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester, initial: AppRoutes.analytics);
      expect(find.byType(ProfitAndLossPage), findsOneWidget);
      expect(
        DashboardDrillOrigin.ofSection(AnalyticsSection.profitAndLoss),
        isNull,
      );

      await openSection(tester, c, AnalyticsSection.revenue);
      await tapKey(tester, const Key('analytics-revenue-net-sales-open'));
      // A dashboard drill-down is its own; the P&L's drill-down is untouched by it.
      expect(c.read(pnlDrillProvider), isNull);
      expect(
        c.read(pnlSelectionProvider).period,
        const PnlPresetPeriod(RelativePreset.thisMonth),
      );
    });

    uiTest(
      '31, 32 · Back returns to the same section, period and place on the page',
      (tester) async {
        final (c, _) = await pumpWindows(tester, initial: AppRoutes.analytics);
        c
            .read(dashboardSelectionProvider.notifier)
            .selectPeriod(DashboardPeriodKind.weekToDate);
        await openSection(tester, c, AnalyticsSection.revenue);
        final list = find.byKey(const Key('analytics-workspace'));
        await tester.drag(list, const Offset(0, -300));
        await tester.pumpAndSettle();
        final scrolled = tester
            .state<ScrollableState>(
              find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            )
            .position
            .pixels;
        expect(scrolled, greaterThan(0));

        await tapKey(tester, const Key('analytics-revenue-net-sales-open'));
        expect(find.byKey(const Key('dashboard-drill')), findsOneWidget);
        await tapKey(tester, const Key('dashboard-drill-back'));

        expect(c.read(dashboardDrillProvider), isNull);
        expect(c.read(analyticsSectionProvider), AnalyticsSection.revenue);
        expect(
          c.read(dashboardSelectionProvider).period,
          const DashboardRelativePeriod(DashboardPeriodKind.weekToDate),
        );
        expect(
          tester
              .state<ScrollableState>(
                find
                    .descendant(of: list, matching: find.byType(Scrollable))
                    .first,
              )
              .position
              .pixels,
          scrolled,
          reason: 'the section was kept mounted underneath',
        );
      },
    );

    uiTest('33 · a hand-off does not move the P&L presets', (tester) async {
      final (c, _) = await pumpWindows(tester, initial: AppRoutes.analytics);
      await openSection(tester, c, AnalyticsSection.revenue);
      await tapKey(tester, const Key('analytics-revenue-gross-sales-open'));
      expect(
        c.read(pnlSelectionProvider).period,
        PnlCustomPeriod(_d(9, 1), _d(9, 19)),
      );

      // This Month is still the whole calendar month on the P&L (D-225, D-252).
      c
          .read(pnlSelectionProvider.notifier)
          .selectPreset(RelativePreset.thisMonth);
      final view = await c.read(pnlViewProvider.future) as PnlReportView;
      expect(view.range.from, _d(9, 1));
      expect(view.range.to, _d(9, 30));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Authority · 21 … 23
  // ═══════════════════════════════════════════════════════════════════════════

  group('authority at the destination', () {
    uiTest('21 · the destination decides authority again, for now', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester);
      final ready = await readyOf(c);
      final location =
          (targetsOf(c, ready).netSales() as DashboardDrillLevel).location;
      expect(await levelOf(c, location), isA<PnlRevenueLevelView>());

      // Visibility of the dashboard earlier is not authority now.
      session.switchTo(
        pnlSession(
          grants: [
            const CapabilityGrant(
              Capability.reportsView,
              businessUnitId: pnlCcr,
            ),
            const CapabilityGrant(
              Capability.revenueView,
              businessUnitId: pnlCcr,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        await levelOf(c, location),
        isA<PnlDrillRefused>().having(
          (r) => r.reason,
          'reason',
          PnlDrillRefusal.notAuthorised,
        ),
      );
    });

    uiTest('22 · a stale intent after a user switch exposes nothing', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester);
      await tapKey(tester, const Key('dashboard-net-sales-open'));
      final location = openLocation(c);
      expect(find.byKey(const Key('pnl-drill-total')), findsOneWidget);

      session.switchTo(pnlSession(userId: 'user-other', grants: pnlD2(pnlCcr)));
      await tester.pumpAndSettle();

      expect(c.read(dashboardDrillProvider), isNull);
      expect(find.byKey(const Key('dashboard-drill')), findsNothing);
      expect(
        await levelOf(c, location),
        isA<PnlDrillRefused>().having(
          (r) => r.reason,
          'reason',
          PnlDrillRefusal.reportChanged,
        ),
      );
    });

    uiTest(
      '23 · a stale intent after a capability revocation exposes nothing',
      (tester) async {
        final (c, _) = await pumpWindows(tester);
        await tapKey(tester, const Key('dashboard-expenses-open'));
        final location = openLocation(c);

        session.switchTo(
          pnlSession(
            grants: [
              const CapabilityGrant(
                Capability.reportsView,
                businessUnitId: pnlCcr,
              ),
              const CapabilityGrant(
                Capability.revenueView,
                businessUnitId: pnlCcr,
              ),
              const CapabilityGrant(
                Capability.expenseViewOwn,
                businessUnitId: pnlCcr,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(c.read(dashboardDrillProvider), isNull);
        expect(find.byKey(const Key('pnl-drill-total')), findsNothing);
        expect(
          await levelOf(c, location),
          isA<PnlDrillRefused>().having(
            (r) => r.reason,
            'reason',
            PnlDrillRefusal.notAuthorised,
          ),
        );
      },
    );

    uiTest('24 · an intent carries canonical ids, never a display name', (
      tester,
    ) async {
      final (c, _) = await pumpWindows(tester);
      final ready = await readyOf(c);
      final targets = targetsOf(c, ready);
      final rows = DashboardDrillTargets.ranked(
        ready.view.topRevenueCategories!,
        targets.revenueCategory,
      );
      final location =
          (rows.first! as DashboardDrillLevel).location
              as PnlRevenueDocumentsAt;
      expect(location.revenueCategoryId, '$pnlCcr-restaurant');
      expect(location.revenueCategoryId, isNot('Restaurant'));
      expect(location.anchor.businessUnitIds, [pnlCcr]);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Document detail · 27 … 30
  // ═══════════════════════════════════════════════════════════════════════════

  group('document detail', () {
    Future<ProviderContainer> openRestaurantDocument(
      WidgetTester tester, {
      List<CapabilityGrant>? grants,
    }) async {
      final (c, _) = await pumpWindows(tester, grants: grants);
      await tapKey(
        tester,
        RankedBarChart.rowKey(0),
        within: find.byKey(const Key('dashboard-revenue-mix')),
      );
      await tapKey(
        tester,
        Key('pnl-drill-doc-${restaurantSale['revenue_entry_id']}'),
      );
      return c;
    }

    uiTest('27 · dashboard-opened detail is the immutable body, no actions', (
      tester,
    ) async {
      await openRestaurantDocument(tester, grants: _mutationCapable(pnlCcr));

      expect(find.byKey(const Key('pnl-document-revenue')), findsOneWidget);
      expect(
        find.byKey(const Key('pnl-document-contribution')),
        findsOneWidget,
      );
      expectNoMutationSurface();
    });

    uiTest('28 · full detail needs a connection', (tester) async {
      revenueDocs.offline = true;
      await openRestaurantDocument(tester);

      expect(
        find.byKey(const Key('pnl-document-not-downloaded')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
    });

    uiTest('29 · a document fetched before is not reused offline (D-239)', (
      tester,
    ) async {
      final c = await openRestaurantDocument(tester);
      expect(find.byKey(const Key('pnl-document-revenue')), findsOneWidget);
      final firstReads = revenueDocs.reads;
      final request = c.read(dashboardDrillProvider)!.selected!;
      // Hold the fetched copy, as the real application may when the row is tapped again.
      final hold = c.listen(pnlDocumentDetailProvider(request), (_, _) {});
      addTearDown(hold.close);

      await tapKey(tester, const Key('pnl-document-close'));
      revenueDocs.offline = true;
      await tapKey(
        tester,
        Key('pnl-drill-doc-${restaurantSale['revenue_entry_id']}'),
      );

      expect(revenueDocs.reads, greaterThan(firstReads));
      expect(
        find.byKey(const Key('pnl-document-not-downloaded')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
    });

    uiTest('30 · a document that no longer explains its row is refused', (
      tester,
    ) async {
      final id = restaurantSale['revenue_entry_id'] as String;
      final component = revenueDocs.components[id]!.single;
      component['gross_amount_minor'] =
          (component['gross_amount_minor'] as int) + 100;
      component['net_amount_minor'] =
          (component['net_amount_minor'] as int) + 100;
      component['entered_amount_minor'] = component['gross_amount_minor'];

      await openRestaurantDocument(tester);

      expect(find.byKey(const Key('pnl-document-changed')), findsOneWidget);
      expect(find.text(pnlDocumentChangedText), findsOneWidget);
      expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Android Home · 13 … 16
  // ═══════════════════════════════════════════════════════════════════════════

  group('Android Home', () {
    uiTest('13 · the phone opens the same target the shared adapter builds', (
      tester,
    ) async {
      final c = await pumpPhone(tester);
      final ready = await readyOf(c);
      await tapKey(tester, const Key('dashboard-net-sales-open'));

      final page = tester.widget<MobilePnlDrillPage>(
        find.byType(MobilePnlDrillPage),
      );
      expect(
        DashboardDrillLevel(page.location),
        targetsOf(c, ready).netSales(),
      );
      expect(page.reportLabel, 'Home');
      expect(
        find.byKey(revenueCategoryRow(pnlCcr, 'restaurant')),
        findsOneWidget,
      );

      // Android back is one level per press: categories → documents, back, back to Home.
      await tapKey(tester, revenueCategoryRow(pnlCcr, 'restaurant'));
      expect(find.byType(MobilePnlDrillPage), findsNWidgets(1));
      expect(
        tester
            .widget<MobilePnlDrillPage>(find.byType(MobilePnlDrillPage))
            .location,
        isA<PnlRevenueDocumentsAt>(),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MobilePnlDrillPage>(find.byType(MobilePnlDrillPage))
            .location,
        isA<PnlRevenueCategoriesAt>(),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MobilePnlDrillPage), findsNothing);
      expect(find.byKey(const Key('dashboard-home-page')), findsOneWidget);
    });

    uiTest('14 · a top expense row reaches the existing expense drill-down', (
      tester,
    ) async {
      await pumpPhone(tester);
      await tapKey(
        tester,
        RankedBarChart.rowKey(0),
        within: find.byKey(const Key('dashboard-top-expenses')),
      );

      final page = tester.widget<MobilePnlDrillPage>(
        find.byType(MobilePnlDrillPage),
      );
      final location = page.location as PnlExpenseDocumentsAt;
      expect(location.categoryId, '$pnlCcr-kirana');
      expect(
        find.byKey(Key('pnl-drill-doc-${kiranaCost['expense_id']}')),
        findsOneWidget,
      );
    });

    uiTest('15 · a trend point reaches its own bucket', (tester) async {
      await pumpPhone(tester);
      await openChartPoint(tester, const Key('dashboard-trend-net-sales'), 11);

      final range = tester
          .widget<MobilePnlDrillPage>(find.byType(MobilePnlDrillPage))
          .location
          .anchor
          .range;
      expect(range.from, _d(9, 12));
      expect(range.to, _d(9, 12));
    });

    uiTest('16 · See full P&L still goes to Reports, and moves nothing', (
      tester,
    ) async {
      final c = await pumpPhone(tester);
      await tapKey(tester, const Key('dashboard-see-full-pnl'));

      expect(find.byType(MobileProfitAndLossPage), findsOneWidget);
      expect(
        c.read(pnlSelectionProvider).period,
        const PnlPresetPeriod(RelativePreset.thisMonth),
      );
    });

    uiTest('Operating Profit on the phone opens Reports for the same period', (
      tester,
    ) async {
      final c = await pumpPhone(tester);
      final ready = await readyOf(c);
      await tapKey(tester, const Key('dashboard-operating-open'));

      expect(find.byType(MobileProfitAndLossPage), findsOneWidget);
      expect(
        c.read(pnlSelectionProvider).period,
        PnlCustomPeriod(ready.pair.current.from, ready.pair.current.to),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 34 · Owner Accounts is not reachable
  // ═══════════════════════════════════════════════════════════════════════════

  uiTest('34 · no dashboard intent reaches an Owner Accounts route', (
    tester,
  ) async {
    final (c, router) = await pumpWindows(tester, grants: pnlD2());
    final paths = <String>{};
    void record() =>
        paths.add(router.routerDelegate.currentConfiguration.uri.path);
    router.routerDelegate.addListener(record);
    addTearDown(() => router.routerDelegate.removeListener(record));

    for (final key in const [
      'dashboard-net-sales-open',
      'dashboard-expenses-open',
      'dashboard-operating-open',
    ]) {
      if (router.routerDelegate.currentConfiguration.uri.path !=
          AppRoutes.overview) {
        router.go(AppRoutes.overview);
        await tester.pumpAndSettle();
      }
      c.read(dashboardDrillProvider.notifier).close();
      await tester.pumpAndSettle();
      await tapKey(tester, Key(key));
    }
    expect(paths, isNot(contains(AppRoutes.ownerSettlement)));
    expect(
      paths.every((p) => p == AppRoutes.overview || p == AppRoutes.analytics),
      isTrue,
    );
  });
}
