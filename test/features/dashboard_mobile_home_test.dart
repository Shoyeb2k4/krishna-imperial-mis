/// The Android Home dashboard, rendered inside the real phone shell (Phase 6 Slice 7).
///
/// The screen is reached the way a phone reaches it: the mobile router opened on Home,
/// inside `MobileShell` with its bottom bar and docked [ + ] action, under the mobile
/// theme. Behind it is the real chain — the Slice 4 providers, `PnlAuthority`, the master
/// graph and business-day rules read from SQLite, the canonical reporting cache,
/// `ReportingSync`, `MarkerCoverage`, `CachedReportingSource`, `LocalReportingEngine`,
/// `Pnl.compute`, the Slice 3 `DashboardEngine`, the Slice 2 comparison, trend and Top-N
/// rules, and the Slice 5 charts.
///
/// What is substituted, and only this: the remote reporting transport and the instant the
/// surface treats as "now". **A test never hands the widget a figure**: every paisa is
/// synchronised into the cache and read back by the engine.
library;

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
import 'package:krishna_mis/core/design/charts/charts.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/dashboard/presentation/mobile_home_page.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_profit_and_loss_page.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/money_layout.dart';
import '../support/test_session.dart';
import '../support/ui_harness.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _me = 'user-me';

/// The phones this is used on, and the one orientation change that matters.
const _phone320 = Size(320, 640);
const _phone360 = Size(360, 740);
const _phone411 = Size(411, 891);
const _phone390 = Size(390, 844);
const _phone430 = Size(430, 932);
const _landscape = Size(844, 390);
const _statusBar = 24.0;

/// A long hospitality category name, of the kind D-269 is about. At 360dp it is the
/// width the ranked list has to survive.
const _longCategory =
    'Kirana, Pulses, Dry Provisions & Cold Storage Consumables';

/// Saturday 19 September 2026, 12:00 UTC is 17:30 IST: both properties are on the 19th,
/// so a consolidated relative period describes one pair.
final _agreeing = DateTime.utc(2026, 9, 19, 12);

/// 21:00 UTC is 02:30 IST on the 20th. Crystal Canopy's 05:00 cut-off keeps it on the
/// 19th; Hotel Krishna's midnight cut-off puts it on the 20th, so they disagree.
final _disagreeing = DateTime.utc(2026, 9, 19, 21);

final class _Gateway extends ReportingGateway {
  _Gateway()
    : super(
        SupabaseClient(
          'http://localhost',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final revenue = <Map<String, dynamic>>[];
  final expense = <Map<String, dynamic>>[];
  RemoteFailure? snapshotUnreachable;
  RemoteFailure? newerUnreachable;
  int snapshots = 0;
  DateTime serverTime = DateTime.utc(2026, 9, 19, 11, 30);

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> snapshot({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
    List<int> financialYears = const [],
    ReportingPageCursor after = const ReportingPageCursor.start(),
    int pageDocuments = ReportingPageCursor.defaultPageDocuments,
  }) async {
    if (snapshotUnreachable case final failure?) {
      return RemoteUnreachable(failure);
    }
    snapshots++;
    List<Map<String, dynamic>> since(
      List<Map<String, dynamic>> rows,
      int generation,
    ) => [
      for (final row in rows)
        if ((row['change_seq'] as int) > generation &&
            businessUnitIds.contains(row['business_unit_id']))
          Map<String, dynamic>.from(row),
    ];
    return RemoteOk({
      'snapshot_id': 'snapshot-$snapshots',
      'server_time': serverTime.toIso8601String(),
      'units': [
        for (final unit in businessUnitIds)
          {'business_unit_id': unit, 'reporting_authorised': true},
      ],
      'revenue': since(revenue, revenueSince),
      'expense': since(expense, expenseSince),
    });
  }

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> newerThan({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
  }) async {
    if (newerUnreachable case final failure?) return RemoteUnreachable(failure);
    bool any(List<Map<String, dynamic>> rows, int generation) => rows.any(
      (r) =>
          (r['change_seq'] as int) > generation &&
          businessUnitIds.contains(r['business_unit_id']),
    );
    return RemoteOk({
      'server_time': serverTime.toIso8601String(),
      'revenue_newer': any(revenue, revenueSince),
      'expense_newer': any(expense, expenseSince),
    });
  }
}

var _seq = 0;

Map<String, dynamic> _sale(
  String unit,
  String date, {
  required int gross,
  required int tax,
  String category = 'restaurant',
}) => {
  'id': 'rc-${++_seq}',
  'revenue_entry_id': 're-$_seq',
  'business_unit_id': unit,
  'revenue_category_id': '$unit-$category',
  'pnl_date': date,
  'pnl_period_key': date.substring(0, 7),
  'gross_minor': gross,
  'tax_minor': tax,
  'net_minor': gross - tax,
  'tax_treatment': tax == 0 ? 'none' : 'inclusive',
  'tax_rate_bp': tax == 0 ? 0 : 500,
  'entered_basis': 'inclusive_total',
  'change_seq': _seq,
  'voided_at': null,
};

Map<String, dynamic> _cost(
  String unit,
  String date,
  int amount, {
  String category = 'kirana',
}) => {
  'id': 'ec-${++_seq}',
  'expense_id': 'ex-$_seq',
  'allocation_id': 'al-$_seq',
  'business_unit_id': unit,
  'department_id': '$unit-dept',
  'section_id': '$unit-section',
  'category_id': '$unit-$category',
  'vendor_id': null,
  'pnl_date': date,
  'pnl_period_key': date.substring(0, 7),
  'amount_minor': amount,
  'change_seq': _seq,
  'voided_at': null,
};

List<CapabilityGrant> _d2([String? unit]) => [
  CapabilityGrant(Capability.reportsView, businessUnitId: unit),
  CapabilityGrant(Capability.revenueView, businessUnitId: unit),
  CapabilityGrant(Capability.expenseViewAll, businessUnitId: unit),
];

AuthoritySnapshot _authority(
  Iterable<CapabilityGrant> grants, {
  String userId = _me,
}) => AuthoritySnapshot(
  userId: userId,
  orgId: 'test-org',
  resolvedAt: DateTime.utc(2026, 9, 19),
  grants: grants,
);

void main() {
  setUpAll(loadRealFonts);
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    // A tap that lands on nothing invalidates every assertion after it (D-075).
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late AppDatabase db;
  late _Gateway gateway;

  Future<void> insert(String table, String columns, List<Object?> values) =>
      db.customStatement(
        'INSERT INTO $table ($columns, sort_order, row_version, updated_at) '
        'VALUES (${List.filled(values.length, '?').join(', ')}, 1, 1, '
        "'2026-06-01T00:00:00.000Z')",
        values,
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = _Gateway();
    for (final (id, code, name, cutoff) in const [
      (_ccr, 'CCR', 'Crystal Canopy Rooftop', '05:00'),
      (_hki, 'HKI', 'Hotel Krishna Imperial', '00:00'),
    ]) {
      await insert(
        'business_units',
        'id, org_id, code, name, kind, timezone, business_day_cutoff',
        [id, 'test-org', code, name, 'hotel', 'Asia/Kolkata', cutoff],
      );
      await insert('departments', 'id, org_id, code, name, business_unit_id', [
        '$id-dept',
        'test-org',
        '$code-D',
        'Department',
        id,
      ]);
      await insert('sections', 'id, org_id, code, name, department_id', [
        '$id-section',
        'test-org',
        '$code-S',
        'Section',
        '$id-dept',
      ]);
    }
    for (final (unit, code, name) in const [
      (_ccr, 'restaurant', 'Restaurant'),
      (_ccr, 'nandbhog', 'Nandbhog'),
      (_hki, 'banquet', 'Banquet'),
    ]) {
      await insert(
        'revenue_categories',
        'id, org_id, code, name, business_unit_id',
        ['$unit-$code', 'test-org', code.toUpperCase(), name, unit],
      );
    }
    for (final (unit, code, name) in const [
      (_ccr, 'kirana', _longCategory),
      (_ccr, 'water', 'Water'),
      (_hki, 'electricity', 'Electricity'),
    ]) {
      await insert('expense_categories', 'id, org_id, code, name, section_id', [
        '$unit-$code',
        'test-org',
        code.toUpperCase(),
        name,
        '$unit-section',
      ]);
    }
  });
  tearDown(() => db.close());

  /// September takings and costs for Crystal Canopy, and the August they are compared
  /// with. Every figure asserted below is derived from these by the shipped engine.
  void crystalCanopySeptember() {
    gateway
      ..revenue.add(_sale(_ccr, '2026-09-10', gross: 12364200, tax: 588771))
      ..revenue.add(
        _sale(
          _ccr,
          '2026-09-12',
          gross: 870000,
          tax: 41429,
          category: 'nandbhog',
        ),
      )
      ..expense.add(_cost(_ccr, '2026-09-11', 9420343))
      ..expense.add(_cost(_ccr, '2026-09-13', 120000, category: 'water'))
      ..revenue.add(_sale(_ccr, '2026-08-05', gross: 10000000, tax: 476190))
      ..expense.add(_cost(_ccr, '2026-08-06', 5000000));
  }

  void hotelKrishnaSeptember() {
    gateway
      ..revenue.add(
        _sale(_hki, '2026-09-15', gross: 4034300, tax: 0, category: 'banquet'),
      )
      ..expense.add(
        _cost(_hki, '2026-09-16', 3000000, category: 'electricity'),
      );
  }

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<CapabilityGrant>? grants,
    Size size = _phone390,
    double textScale = 1,
    DateTime? instant,
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
      initialLocation: AppRoutes.home,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(
            () => StubSession(
              readySession(authority: _authority(grants ?? _d2())),
            ),
          ),
          reportingClockProvider.overrideWithValue(() => instant ?? _agreeing),
          reportingGatewayProvider.overrideWithValue(gateway),
        ],
        child: MaterialApp.router(theme: AppTheme.mobile, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(MobileHomePage)),
    );
  }

  Money amountAt(WidgetTester tester, String key) =>
      tester.widget<MoneyText>(find.byKey(Key(key))).amount;

  String textAt(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  Future<DashboardReady> readyOf(ProviderContainer c) async =>
      await c.read(dashboardViewProvider.future) as DashboardReady;

  /// Which branch the phone shell is showing, read from the shell itself.
  int branch(WidgetTester tester) => tester
      .widget<StatefulNavigationShell>(find.byType(StatefulNavigationShell))
      .currentIndex;

  Finder pageScrollable() => find
      .descendant(
        of: find.byKey(const Key('dashboard-home-page')),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Bring something below the fold into view, the way a thumb would.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      -120,
      scrollable: pageScrollable(),
      maxScrolls: 60,
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollToBottom(WidgetTester tester) async {
    for (var i = 0; i < 14; i++) {
      await tester.drag(pageScrollable(), const Offset(0, -400));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // The phone renders the engine's own figures, and none it worked out itself
  // ═══════════════════════════════════════════════════════════════════════════

  group('an authorised phone dashboard', () {
    uiTest('one property renders that property and its own figures', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      final result = (await readyOf(c)).view.resultOrNull!;

      expect(textAt(tester, 'dashboard-scope-name'), 'Crystal Canopy Rooftop');
      expect(amountAt(tester, 'dashboard-net-sales-value'), result.netSales);
      expect(amountAt(tester, 'dashboard-expenses-value'), result.expenses);
      expect(
        amountAt(tester, 'dashboard-operating-value'),
        result.operatingProfit,
      );
      expect(
        textAt(tester, 'dashboard-margin-value'),
        result.margin.displayTwoDecimals,
      );
      // Month to date, so the engine's own figures are September's alone.
      expect(result.netSales.paise, 12604000);
      expect(result.expenses.paise, 9540343);
      expect(result.operatingProfit.paise, 3063657);
    });

    uiTest('Gross Sales and GST are secondary to Net Sales, never a headline', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      final result = (await readyOf(c)).view.resultOrNull!;

      expect(amountAt(tester, 'dashboard-gross-sales'), result.grossSales);
      expect(amountAt(tester, 'dashboard-gst'), result.gst);
      expect(result.grossSales.paise, 13234200);
      expect(result.gst.paise, 630200);
      // They sit inside the Net Sales metric rather than beside it as figures of
      // their own.
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-kpi-net-sales')),
          matching: find.byKey(const Key('dashboard-gross-sales')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('dashboard-kpi-gross-sales')), findsNothing);
    });

    uiTest('consolidated renders both properties and their exact split', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pump(tester);
      final view = (await readyOf(c)).view;
      final result = view.resultOrNull!;
      final split = view.propertyComparison! as PropertyComparisonReady;

      expect(result.netSales.paise, 16638300);
      expect(result.expenses.paise, 12540343);
      expect(result.operatingProfit.paise, 4097957);
      expect(amountAt(tester, 'dashboard-net-sales-value'), result.netSales);

      expect(split.properties.map((p) => p.businessUnitId), [_ccr, _hki]);
      await reveal(
        tester,
        find.byKey(const Key('dashboard-property-comparison')),
      );
      for (final name in const [
        'Crystal Canopy Rooftop',
        'Hotel Krishna Imperial',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(const Key('dashboard-property-comparison')),
            matching: find.text(name),
          ),
          findsOneWidget,
          reason: '$name is named in the split',
        );
      }
    });

    uiTest('a loss is labelled a loss and carries its sign', (tester) async {
      gateway
        ..revenue.add(_sale(_ccr, '2026-09-10', gross: 1050000, tax: 50000))
        ..expense.add(_cost(_ccr, '2026-09-11', 4000000));
      final c = await pump(tester, grants: _d2(_ccr));
      final result = (await readyOf(c)).view.resultOrNull!;

      expect(result.operatingProfit.paise, -3000000);
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-kpi-operating')),
          matching: find.text(dashboardProfitLabel(result).toUpperCase()),
        ),
        findsOneWidget,
      );
      expect(dashboardProfitLabel(result), 'Operating Loss');
      final money = tester.widget<MoneyText>(
        find.byKey(const Key('dashboard-operating-value')),
      );
      expect(money.amount.paise, -3000000);
      expect(
        money.emphasis,
        MoneyEmphasis.bySign,
        reason: 'a loss is never distinguished by colour alone',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Comparisons are rendered, never computed
  // ═══════════════════════════════════════════════════════════════════════════

  group('comparison indicators', () {
    uiTest('every movement on screen is the domain comparison it came from', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      final view = (await readyOf(c)).view;
      final comparedWith = dashboardComparisonRangeLabel(
        (await readyOf(c)).pair,
      );

      for (final (key, money) in [
        ('net-sales', view.comparison.netSales),
        ('expenses', view.comparison.expenses),
        ('operating', view.comparison.operatingProfit),
      ]) {
        final movement = dashboardMoneyMovement(money);
        expect(
          textAt(tester, 'dashboard-$key-movement'),
          '${movement.text} · vs $comparedWith',
          reason: '$key states the comparison, not a figure of its own',
        );
      }
    });

    uiTest('a percentage the domain withheld is not printed', (tester) async {
      // September alone: the stretch it is compared with traded nothing, so the
      // previous figure is nil and no percentage is defined (D-256).
      gateway
        ..revenue.add(_sale(_ccr, '2026-09-10', gross: 1050000, tax: 50000))
        ..expense.add(_cost(_ccr, '2026-09-11', 200000));
      final c = await pump(tester, grants: _d2(_ccr));
      final netSales =
          (await readyOf(c)).view.comparison.netSales
              as MoneyComparisonAvailable;

      expect(netSales.percentChange, isA<PercentChangeNotApplicable>());
      final shown = textAt(tester, 'dashboard-net-sales-movement');
      expect(shown, isNot(contains('%')));
      expect(
        shown,
        contains(MoneyFormatter.movement.format(netSales.change)),
        reason:
            'the exact rupee movement is shown even where a percentage is not',
      );
      expect(
        textAt(tester, 'dashboard-net-sales-movement-note'),
        'No percentage: the previous period was nil.',
        reason: 'the reason is stated rather than left as a silent absence',
      );
    });

    uiTest('the margin moves in points, and the three figures reconcile', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      final view = (await readyOf(c)).view;
      final margin = view.comparison.margin;
      final comparedWith = dashboardComparisonRangeLabel(
        (await readyOf(c)).pair,
      );

      expect(
        textAt(tester, 'dashboard-margin-movement'),
        '${dashboardMarginMovement(margin).text} · vs $comparedWith',
      );
      expect(
        textAt(tester, 'dashboard-margin-previous'),
        'Previous ${dashboardPreviousMarginLabel(margin)}',
      );
      // What is on screen adds up: displayed current − displayed previous (D-264).
      expect(margin, isA<MarginMovement>());
      expect(
        textAt(tester, 'dashboard-margin-movement'),
        contains((margin as MarginMovement).displayTwoDecimals),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // D-260 · what the phone carries, and what stays on the Windows workspace
  // ═══════════════════════════════════════════════════════════════════════════

  group('the phone carries the approved content and no more', () {
    uiTest('the Net Sales trend and top expense categories are there', (
      tester,
    ) async {
      crystalCanopySeptember();
      await pump(tester, grants: _d2(_ccr));

      expect(
        find.byKey(const Key('dashboard-trend-net-sales')),
        findsOneWidget,
      );
      expect(find.byType(TrendLineChart), findsOneWidget);
      await reveal(tester, find.byKey(const Key('dashboard-top-expenses')));
      expect(find.byKey(const Key('dashboard-top-expenses')), findsOneWidget);
    });

    uiTest('the analytics workspace is not reproduced on the phone', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pump(tester);
      final view = (await readyOf(c)).view;
      await scrollToBottom(tester);

      // The engine still carries them; the phone deliberately does not show them.
      expect(view.topRevenueCategories, isNotNull);
      expect(view.departmentSpending, isNotNull);
      for (final key in const [
        'dashboard-revenue-mix',
        'dashboard-departments',
        'dashboard-trend-operating',
        'dashboard-trend-expenses',
      ]) {
        expect(
          find.byKey(Key(key)),
          findsNothing,
          reason: '$key belongs to the Windows Analytics workspace (D-260)',
        );
      }
      expect(find.byType(ProfitBarChart), findsNothing);
    });

    uiTest('one property shows no property comparison', (tester) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));

      expect(
        (await readyOf(c)).view.propertyComparison,
        isA<PropertyComparisonRefused>(),
      );
      await scrollToBottom(tester);
      expect(
        find.byKey(const Key('dashboard-property-comparison')),
        findsNothing,
        reason: 'a chart of one bar compares nothing',
      );
    });

    uiTest('the ranked list keeps the whole name and the whole amount', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr), size: _phone360);
      final top = (await readyOf(c)).view.topExpenseCategories! as TopNGrouped;
      await reveal(tester, find.byKey(const Key('dashboard-top-expenses')));

      Finder inSection(Key key) => find.descendant(
        of: find.byKey(const Key('dashboard-top-expenses')),
        matching: find.byKey(key),
      );

      final label = tester.widget<Text>(inSection(RankedBarChart.labelKey(0)));
      expect(label.data, contains('Kirana'));

      final value = tester.widget<Text>(inSection(RankedBarChart.valueKey(0)));
      expect(value.data, MoneyFormatter.standard.format(top.top.first.amount));
      expect(
        value.overflow,
        TextOverflow.visible,
        reason: 'a truncated amount is a wrong amount (D-269)',
      );
      expect(value.maxLines, 1);

      // At 360dp the name and the figure never share a line.
      final labelRect = tester.getRect(inSection(RankedBarChart.labelKey(0)));
      final valueRect = tester.getRect(inSection(RankedBarChart.valueKey(0)));
      expect(
        valueRect.top,
        greaterThanOrEqualTo(labelRect.bottom - 0.5),
        reason: 'the figure sits below the name at phone width',
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Scope and period, chosen the way a phone chooses them
  // ═══════════════════════════════════════════════════════════════════════════

  group('the phone controls', () {
    uiTest('the scope sheet opens over the shell and switches property', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      await pump(tester);
      expect(
        textAt(tester, 'dashboard-scope-name'),
        dashboardConsolidatedScopeLabel,
      );

      await tester.tap(find.byKey(const Key('dashboard-scope-selector')));
      await tester.pumpAndSettle();

      final sheet = tester.getRect(
        find.byKey(const Key('dashboard-scope-sheet')),
      );
      expect(
        sheet.bottom,
        moreOrLessEquals(_phone390.height, epsilon: 0.5),
        reason:
            'the sheet is presented on the root navigator, so it reaches past the '
            'bottom bar rather than stopping at the branch body',
      );

      await tester.tap(find.byKey(const Key('dashboard-scope-$_hki')));
      await tester.pumpAndSettle();
      expect(textAt(tester, 'dashboard-scope-name'), 'Hotel Krishna Imperial');
      expect(amountAt(tester, 'dashboard-net-sales-value').paise, 4034300);
    });

    uiTest('a period chip changes the period and the figures with it', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      expect(amountAt(tester, 'dashboard-net-sales-value').paise, 12604000);

      final chip = find.byKey(
        Key('dashboard-period-${DashboardPeriodKind.financialYearToDate.name}'),
      );
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();

      final result = (await readyOf(c)).view.resultOrNull!;
      expect(amountAt(tester, 'dashboard-net-sales-value'), result.netSales);
      expect(
        result.netSales.paise,
        22127810,
        reason: 'the year to date includes August as well as September',
      );
    });

    uiTest('the custom picker is a calendar, opened over the shell', (
      tester,
    ) async {
      crystalCanopySeptember();
      await pump(tester, grants: _d2(_ccr));

      final custom = find.byKey(const Key('dashboard-period-custom'));
      await tester.ensureVisible(custom);
      await tester.pumpAndSettle();
      await tester.tap(custom);
      await tester.pumpAndSettle();

      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'Android takes no typed dates (D-229, D-250)',
      );
      final dialog = tester.getRect(find.byType(DateRangePickerDialog));
      expect(
        dialog.bottom,
        moreOrLessEquals(_phone390.height, epsilon: 0.5),
        reason: 'the picker is on the root navigator, above the bottom bar',
      );

      // Dismissing changes nothing.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-custom-range')), findsNothing);
      expect(amountAt(tester, 'dashboard-net-sales-value').paise, 12604000);
    });

    uiTest('a period the properties disagree about is offered and refused', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      await pump(tester, instant: _disagreeing);

      final chip = tester.widget<ChoiceChip>(
        find.byKey(
          Key('dashboard-period-${DashboardPeriodKind.monthToDate.name}'),
        ),
      );
      expect(
        chip.onSelected,
        isNull,
        reason: 'no property is the master calendar (D-254)',
      );
      expect(
        find.byKey(const Key('dashboard-periods-unavailable-note')),
        findsOneWidget,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Nothing missing becomes a zero
  // ═══════════════════════════════════════════════════════════════════════════

  group('a refusal is a sentence, never a figure', () {
    uiTest('no qualifying authority names no property and shows no figure', (
      tester,
    ) async {
      crystalCanopySeptember();
      await pump(
        tester,
        grants: [CapabilityGrant(Capability.reportsView, businessUnitId: _ccr)],
      );

      expect(find.byKey(const Key('dashboard-not-authorised')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-body')), findsNothing);
      expect(find.byKey(const Key('dashboard-scope-selector')), findsNothing);
      expect(find.byKey(const Key('dashboard-period-bar')), findsNothing);
      for (final name in const [
        'Crystal Canopy Rooftop',
        'Hotel Krishna Imperial',
        dashboardConsolidatedScopeLabel,
      ]) {
        expect(
          find.text(name),
          findsNothing,
          reason: 'a neutral surface names no property (D-259)',
        );
      }
      expect(find.byType(MoneyText), findsNothing);
    });

    uiTest('a report that never arrived says so rather than showing zero', (
      tester,
    ) async {
      crystalCanopySeptember();
      gateway.snapshotUnreachable = RemoteFailure.offline;
      await pump(tester, grants: _d2(_ccr));

      expect(find.byKey(const Key('dashboard-body')), findsNothing);
      expect(find.byType(MoneyText), findsNothing);
      expect(
        find.byKey(const Key('dashboard-not-downloaded')),
        findsOneWidget,
        reason: 'not downloaded is not zero (D-170)',
      );
    });

    uiTest('a failed refresh keeps the dashboard and reports beside it', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      final before = amountAt(tester, 'dashboard-net-sales-value');

      gateway.snapshotUnreachable = RemoteFailure.offline;
      await c.read(dashboardSyncProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard-body')), findsOneWidget);
      expect(
        amountAt(tester, 'dashboard-net-sales-value'),
        before,
        reason: 'a failed run writes nothing, so the figures do not move',
      );
      expect(find.byKey(const Key('dashboard-offline')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Freshness
  // ═══════════════════════════════════════════════════════════════════════════

  group('freshness', () {
    uiTest('a synchronised dashboard states the server time it belongs to', (
      tester,
    ) async {
      crystalCanopySeptember();
      await pump(tester, grants: _d2(_ccr));

      expect(
        find.byKey(const Key('dashboard-freshness-synchronised')),
        findsOneWidget,
      );
    });

    uiTest('a confirmed newer server marks the report and moves no figure', (
      tester,
    ) async {
      crystalCanopySeptember();
      await pump(tester, grants: _d2(_ccr));
      final before = amountAt(tester, 'dashboard-net-sales-value');

      gateway
        ..revenue.add(_sale(_ccr, '2026-09-18', gross: 500000, tax: 23810))
        ..snapshotUnreachable = RemoteFailure.serverUnreachable;
      await tester.tap(find.byKey(const Key('dashboard-refresh')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('dashboard-freshness-server-newer')),
        findsOneWidget,
        reason:
            'the head check answers, so the dashboard learns it is behind without '
            'learning by how much',
      );
      expect(
        amountAt(tester, 'dashboard-net-sales-value'),
        before,
        reason: 'a head check moves no figure',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // The one navigation D-260 gives the phone
  // ═══════════════════════════════════════════════════════════════════════════

  group('through to the full profit & loss', () {
    uiTest('See full P&L switches the shell to Reports', (tester) async {
      crystalCanopySeptember();
      await pump(tester, grants: _d2(_ccr));
      expect(branch(tester), 0);

      final button = find.byKey(const Key('dashboard-see-full-pnl'));
      await reveal(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(branch(tester), AppRouter.mobileReportsBranch);
      expect(find.byType(MobileProfitAndLossPage), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Phone layout
  // ═══════════════════════════════════════════════════════════════════════════

  /// Walks the page top to bottom, checking every amount at each stop: the list is lazy,
  /// so a check at the top and the bottom alone misses everything in between.
  Future<int> expectEveryAmountWhole(WidgetTester tester, String where) async {
    var checked = 0;
    for (var stop = 0; stop < 40; stop++) {
      expectNoLayoutError(tester, '$where, stop $stop');
      checked += expectMoneyWholeAndUnshrunk(
        tester,
        '$where, stop $stop',
        atLeast: 0,
      );
      final page = find
          .descendant(
            of: find.byKey(const Key('dashboard-home-page')),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final position = tester.state<ScrollableState>(page).position;
      if (position.pixels >= position.maxScrollExtent) break;
      await tester.drag(page, const Offset(0, -240));
      await tester.pumpAndSettle();
    }
    expect(checked, greaterThan(0), reason: 'no amount checked at $where');
    return checked;
  }

  group('the phone layout', () {
    for (final (name, size) in [
      ('320×640', _phone320),
      ('360×740', _phone360),
      ('411×891', _phone411),
      ('390×844', _phone390),
      ('430×932', _phone430),
      ('landscape', _landscape),
    ]) {
      uiTest('$name renders with nothing clipped or overflowing', (
        tester,
      ) async {
        crystalCanopySeptember();
        hotelKrishnaSeptember();
        await pump(tester, size: size);

        expect(tester.takeException(), isNull);
        await expectEveryAmountWhole(tester, name);
        await tester.drag(pageScrollable(), const Offset(0, 20000));
        await tester.pumpAndSettle();
        for (final key in const [
          'dashboard-body',
          'dashboard-net-sales-value',
          'dashboard-expenses-value',
          'dashboard-operating-value',
          'dashboard-margin-value',
        ]) {
          expect(find.byKey(Key(key)), findsOneWidget, reason: '$key at $name');
        }
        await scrollToBottom(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('dashboard-see-full-pnl')), findsOneWidget);
      });
    }

    // D-286: at a large system font the layout gives way, never the money.
    for (final (name, size) in [
      ('320×640', _phone320),
      ('360×740', _phone360),
      ('411×891', _phone411),
    ]) {
      for (final scale in const [1.0, 1.6, 2.0]) {
        uiTest('$name at $scale× text keeps every amount whole and unshrunk', (
          tester,
        ) async {
          crystalCanopySeptember();
          hotelKrishnaSeptember();
          await pump(tester, size: size, textScale: scale);

          await expectEveryAmountWhole(tester, '$name ×$scale');

          // The last thing on the page still clears the docked [ + ].
          await scrollToBottom(tester);
          expectNoLayoutError(tester, '$name ×$scale, bottom');
          final last = tester.getRect(
            find.byKey(const Key('dashboard-see-full-pnl')),
          );
          final fab = tester.getRect(find.byType(FloatingActionButton));
          expect(last.bottom, lessThanOrEqualTo(fab.top));
        });
      }
    }

    uiTest(
      'at 2.0× on 320dp the figure moves to its own line and the card grows',
      (tester) async {
        crystalCanopySeptember();
        hotelKrishnaSeptember();
        await pump(tester, size: _phone320, textScale: 2);

        final kpi = find.byKey(const Key('dashboard-kpi-net-sales'));
        final label = find.descendant(
          of: kpi,
          matching: find.text('NET SALES'),
        );
        final value = find.byKey(const Key('dashboard-net-sales-value'));
        expect(
          tester.getRect(value).top,
          greaterThanOrEqualTo(tester.getRect(label).bottom - 0.5),
          reason:
              'the figure did not fit beside its label, so it is stacked below',
        );
        expectMoneyWholeAndUnshrunk(tester, '320×2.0 headline');
      },
    );

    uiTest('a raised system font scale still fits', (tester) async {
      crystalCanopySeptember();
      await pump(tester, grants: _d2(_ccr), size: _phone360, textScale: 1.6);

      expect(tester.takeException(), isNull);
      await scrollToBottom(tester);
      expect(tester.takeException(), isNull);
    });

    uiTest(
      'the page scrolls vertically; only the period strip scrolls sideways',
      (tester) async {
        crystalCanopySeptember();
        await pump(tester, grants: _d2(_ccr), size: _phone360);

        final sideways = find.byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              (w.axisDirection == AxisDirection.right ||
                  w.axisDirection == AxisDirection.left),
        );
        for (final element in sideways.evaluate()) {
          expect(
            find
                .ancestor(
                  of: find.byWidget(element.widget),
                  matching: find.byKey(const Key('dashboard-period-bar')),
                )
                .evaluate(),
            isNotEmpty,
            reason: 'the only sideways scroll on the phone is the period strip',
          );
        }
        expect(
          tester.widget<Scrollable>(pageScrollable()).axisDirection,
          AxisDirection.down,
        );
      },
    );

    uiTest('the last thing on the page clears the docked add action', (
      tester,
    ) async {
      crystalCanopySeptember();
      await pump(tester, grants: _d2(_ccr));
      await scrollToBottom(tester);

      final last = tester.getRect(
        find.byKey(const Key('dashboard-see-full-pnl')),
      );
      final fab = tester.getRect(find.byType(FloatingActionButton));
      expect(
        last.bottom,
        lessThanOrEqualTo(fab.top),
        reason:
            'a control under the docked [ + ] is a control nobody can press',
      );
    });
  });
}
