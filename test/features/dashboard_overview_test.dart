/// The Windows Overview, rendered through the real provider chain (Phase 6 Slice 6).
///
/// What is real: the page, the Slice 4 providers, `PnlAuthority`, the master graph and
/// business-day rules read from SQLite, the canonical reporting cache, `ReportingSync`,
/// `MarkerCoverage`, `CachedReportingSource`, `LocalReportingEngine`, `Pnl.compute`, the
/// Slice 3 `DashboardEngine`, the Slice 2 comparison, trend, ranking and Top-N rules, and
/// the Slice 5 charts.
///
/// What is substituted, and only this: the remote reporting transport and the instant the
/// surface treats as "now". **A test never hands the widget a figure**: every paisa is
/// synchronised into the cache and read back by the engine, so what is asserted on screen
/// is what the shipped path produced.
///
/// The page is rendered beside a 240-pixel strip standing in for the desktop sidebar, at
/// the Windows sizes the other desktop surfaces are tested at.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/charts/charts.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_presentation.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/dashboard/presentation/overview_page.dart';
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
const _other = 'user-other';

const _laptop = Size(1366, 768);
const _narrow = Size(1024, 700);
const _wide = Size(1920, 1080);

/// A long hospitality category name, of the kind D-269 is about.
const _longCategory =
    'Kirana, Pulses, Dry Provisions & Cold Storage Consumables';
const _longDepartment = 'Food & Beverage Production and Banqueting Services';

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
  Completer<void>? gate;
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
    if (gate case final waiting?) await waiting.future;
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
  String department = 'dept',
  String section = 'section',
}) => {
  'id': 'ec-${++_seq}',
  'expense_id': 'ex-$_seq',
  'allocation_id': 'al-$_seq',
  'business_unit_id': unit,
  'department_id': '$unit-$department',
  'section_id': '$unit-$section',
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

class _Session extends StubSession {
  _Session(super.initial);
  void become(SessionState next) => state = next;
}

void main() {
  setUpAll(loadRealFonts);
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

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
    // A second Crystal Canopy department, named the way hospitality departments really
    // are, so a long label is rendered rather than imagined.
    await insert('departments', 'id, org_id, code, name, business_unit_id', [
      '$_ccr-kitchen',
      'test-org',
      'CCR-K',
      _longDepartment,
      _ccr,
    ]);
    // The kitchen department has its own section and categories. A cost booked to a
    // department must carry a section and category that really live under it: the
    // server's composite hierarchy keys make any other row impossible (D-040, D-280).
    await insert('sections', 'id, org_id, code, name, department_id', [
      '$_ccr-kitchen-section',
      'test-org',
      'CCR-KS',
      'Kitchen',
      '$_ccr-kitchen',
    ]);
    for (final (code, name) in const [
      ('gas', 'Cylinder & Coal'),
      ('milk', 'Milk & Dahi'),
      ('paneer', 'Paneer / Dairy'),
      ('veg', 'Vegetables & Fruits'),
    ]) {
      await insert('expense_categories', 'id, org_id, code, name, section_id', [
        '$_ccr-$code',
        'test-org',
        code.toUpperCase(),
        name,
        '$_ccr-kitchen-section',
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
  /// with. Every figure below is derived from these by the shipped engine.
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
    _Session? session,
    Size size = _laptop,
    DateTime? instant,
    bool withGateway = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(
            () =>
                session ??
                _Session(readySession(authority: _authority(grants ?? _d2()))),
          ),
          reportingClockProvider.overrideWithValue(() => instant ?? _agreeing),
          if (withGateway) reportingGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(width: 240),
                Expanded(child: OverviewPage(shellKind: AppShellKind.desktop)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(OverviewPage)));
  }

  Money amountAt(WidgetTester tester, String key) =>
      tester.widget<MoneyText>(find.byKey(Key(key))).amount;

  String textAt(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  /// Every ranked chart numbers its rows from zero, so a row key is unique only inside
  /// the section it belongs to.
  String rowTextAt(WidgetTester tester, String section, Key key) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(Key(section)),
          matching: find.byKey(key),
        ),
      )
      .data!;

  Future<DashboardReady> readyOf(ProviderContainer c) async =>
      await c.read(dashboardViewProvider.future) as DashboardReady;

  Future<void> choosePeriod(
    ProviderContainer c,
    WidgetTester tester,
    DashboardPeriodKind kind,
  ) async {
    c.read(dashboardSelectionProvider.notifier).selectPeriod(kind);
    await tester.pumpAndSettle();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1, 2, 6 · a dashboard renders, and its figures are the engine's
  // ═══════════════════════════════════════════════════════════════════════════

  group('an authorised dashboard', () {
    uiTest('1 · one property renders that property and its own figures', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pump(tester, grants: _d2(_ccr));

      expect(find.byKey(const Key('dashboard-body')), findsOneWidget);
      // The scope is the one permitted property, selected automatically.
      final ready = await readyOf(c);
      expect(ready.scope, const PnlUnitScope(_ccr));
      expect(find.text('Crystal Canopy Rooftop'), findsWidgets);

      // Crystal Canopy alone: 12364200 + 870000 gross, 588771 + 41429 GST.
      expect(amountAt(tester, 'dashboard-net-sales-value').paise, 12604000);
      expect(amountAt(tester, 'dashboard-gross-sales').paise, 13234200);
      expect(amountAt(tester, 'dashboard-gst').paise, 630200);
      // 9420343 + 120000.
      expect(amountAt(tester, 'dashboard-expenses-value').paise, 9540343);
      expect(amountAt(tester, 'dashboard-operating-value').paise, 3063657);
    });

    uiTest('2 · consolidated renders both properties added together', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pump(tester);

      final ready = await readyOf(c);
      expect(ready.scope, const PnlConsolidatedScope());
      // 12604000 + 4034300, and 9540343 + 3000000.
      expect(amountAt(tester, 'dashboard-net-sales-value').paise, 16638300);
      expect(amountAt(tester, 'dashboard-expenses-value').paise, 12540343);
      expect(amountAt(tester, 'dashboard-operating-value').paise, 4097957);
    });

    uiTest('6 · every headline figure is the engine result, not a widget sum', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pump(tester);
      final result = (await readyOf(c)).view.resultOrNull!;

      expect(amountAt(tester, 'dashboard-net-sales-value'), result.netSales);
      expect(amountAt(tester, 'dashboard-expenses-value'), result.expenses);
      expect(
        amountAt(tester, 'dashboard-operating-value'),
        result.operatingProfit,
      );
      expect(amountAt(tester, 'dashboard-gross-sales'), result.grossSales);
      expect(amountAt(tester, 'dashboard-gst'), result.gst);
      expect(
        textAt(tester, 'dashboard-margin-value'),
        result.margin.displayTwoDecimals,
      );
      // And Gross reconciles with GST and Net on screen, exactly.
      expect(
        amountAt(tester, 'dashboard-gross-sales'),
        amountAt(tester, 'dashboard-gst') +
            amountAt(tester, 'dashboard-net-sales-value'),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3, 4, 5 · authority
  // ═══════════════════════════════════════════════════════════════════════════

  group('authority', () {
    uiTest('3 · no qualifying authority gets the approved neutral Overview', (
      tester,
    ) async {
      crystalCanopySeptember();
      await pump(
        tester,
        grants: const [
          CapabilityGrant(Capability.mastersView, businessUnitId: _ccr),
        ],
      );

      expect(find.byKey(const Key('dashboard-not-authorised')), findsOneWidget);
      expect(
        find.text('Management analytics are not available for your access.'),
        findsOneWidget,
      );
      // The page itself still exists — the shell is for everyone.
      expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
      // And nothing financial, not even an empty chart or a scope chip.
      expect(find.byKey(const Key('dashboard-body')), findsNothing);
      expect(find.byKey(const Key('dashboard-scope-bar')), findsNothing);
      expect(find.byType(TrendLineChart), findsNothing);
      expect(find.byType(RankedBarChart), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });

    uiTest('4 · a property this reader may not see is never named', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      await pump(tester, grants: _d2(_ccr));

      expect(find.textContaining('Hotel Krishna Imperial'), findsNothing);
      expect(find.textContaining('Banquet'), findsNothing);
      expect(find.textContaining('Electricity'), findsNothing);
      expect(
        find.byKey(const Key('dashboard-property-comparison')),
        findsNothing,
      );
    });

    uiTest('5 · a changed authority cannot show the previous dashboard', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final session = _Session(readySession(authority: _authority(_d2())));
      final c = await pump(tester, session: session);

      // The Owner's consolidated dashboard is on screen.
      expect(amountAt(tester, 'dashboard-net-sales-value').paise, 16638300);

      final owners = await readyOf(c);
      expect(owners.view.resultOrNull!.netSales.paise, 16638300);

      // The rule the page depends on, exercised directly: the Owner's assembled
      // dashboard offered to the next authority is **not shown**, whatever a provider
      // happens to be holding at that moment (D-231, D-242, D-267).
      session.become(
        readySession(authority: _authority(_d2(_ccr), userId: _other)),
      );
      await tester.pump();
      final next = c.read(sessionProvider).principal;
      expect(dashboardShownTo(AsyncData<DashboardState>(owners), next), isNull);
      expect(
        dashboardPresentation(
          state: AsyncData<DashboardState>(owners),
          sync: c.read(dashboardSyncProvider),
          principal: next,
        ),
        isA<DashboardLoading>(),
        reason:
            "the previous authority's dashboard is not a dashboard for this one",
      );

      // And on screen, the Owner's consolidated figures are gone.
      await tester.pumpAndSettle();
      expect(find.textContaining('₹1,66,383.00'), findsNothing);
      expect(find.textContaining('Hotel Krishna Imperial'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 7 … 10 · comparisons
  // ═══════════════════════════════════════════════════════════════════════════

  group('comparisons', () {
    uiTest('7 · the movement shown is exactly the one the domain decided', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      final comparison = (await readyOf(c)).view.comparison;
      final net = comparison.netSales as MoneyComparisonAvailable;

      // Hand-worked from the fixture: 12604000 − 9523810.
      expect(net.change.paise, 3080190);
      expect(
        textAt(tester, 'dashboard-net-sales-movement'),
        '${MoneyFormatter.movement.format(net.change)} · '
        '${net.percentChange.displayTwoDecimals}',
      );
      expect(
        textAt(tester, 'dashboard-net-sales-movement'),
        startsWith('+₹30,801.90'),
      );
      // And the period it is compared with is named, never implied.
      expect(find.textContaining('1 Aug 2026 – 19 Aug 2026'), findsWidgets);
    });

    uiTest('8 · a negative Operating Profit says Loss in words', (
      tester,
    ) async {
      gateway
        ..revenue.add(_sale(_ccr, '2026-09-10', gross: 1050000, tax: 50000))
        ..expense.add(_cost(_ccr, '2026-09-11', 4000000));
      await pump(tester, grants: _d2(_ccr));

      expect(amountAt(tester, 'dashboard-operating-value').paise, -3000000);
      expect(find.text('OPERATING LOSS'), findsOneWidget);
      expect(find.text('OPERATING PROFIT'), findsNothing);
      // The figure carries its own sign as well, so colour is never the message.
      expect(find.textContaining('-₹30,000.00'), findsWidgets);
    });

    uiTest('9 · the margin movement is the difference of the two shown', (
      tester,
    ) async {
      crystalCanopySeptember();
      await pump(tester, grants: _d2(_ccr));

      final current = textAt(tester, 'dashboard-margin-value');
      final previous = textAt(
        tester,
        'dashboard-margin-previous',
      ).replaceFirst('Previous ', '');
      final movement = textAt(tester, 'dashboard-margin-movement');

      double parse(String percent) =>
          double.parse(percent.replaceAll(RegExp('[%+ p]'), ''));

      // Hand-worked from the fixture: 3063657 ÷ 12604000 now, 4523810 ÷ 9523810 before.
      expect(current, '24.31%');
      expect(previous, '47.50%');
      expect(movement, '-23.19 pp');
      // The three figures on screen reconcile, which is the whole of D-264.
      expect(
        (parse(current) - parse(previous) - parse(movement)).abs() < 0.0001,
        isTrue,
        reason: '$current − $previous must be $movement exactly, as displayed',
      );
    });

    uiTest('a comparator this device does not hold says so, and is not ₹0', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      // The previous financial year has never been fetched, so there is no comparator —
      // which is a different statement from "the previous period was nil".
      await choosePeriod(c, tester, DashboardPeriodKind.financialYearToDate);

      expect(
        textAt(tester, 'dashboard-net-sales-movement'),
        'No comparison — the previous period is not available.',
      );
      expect(
        find.byKey(const Key('dashboard-net-sales-movement-note')),
        findsNothing,
      );
      // The figures for the period itself are shown; only the movement is withheld.
      expect(find.byKey(const Key('dashboard-body')), findsOneWidget);
      expect(
        textAt(tester, 'dashboard-margin-movement'),
        'No comparison — the previous period is not available.',
      );
    });

    uiTest('10 · a previous period of nil gives N/A, never a percentage', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      // The previous financial year has to be fetched before it can be a **real** nil:
      // unsynchronised is "not available", which is a different statement entirely.
      await choosePeriod(c, tester, DashboardPeriodKind.financialYearToDate);
      await c.read(dashboardSyncProvider.notifier).refresh();
      await tester.pumpAndSettle();

      final movement = textAt(tester, 'dashboard-net-sales-movement');
      expect(movement, isNot(contains('%')));
      expect(movement, isNot(contains('Infinity')));
      expect(movement, isNot(contains('NaN')));
      expect(movement, startsWith('+₹'));
      expect(
        textAt(tester, 'dashboard-net-sales-movement-note'),
        'No percentage: the previous period was nil.',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 11, 12, 13 · refreshing, missing data and freshness
  // ═══════════════════════════════════════════════════════════════════════════

  group('refresh, availability and freshness', () {
    uiTest('11 · a failed refresh keeps the complete dashboard on screen', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      expect(amountAt(tester, 'dashboard-net-sales-value').paise, 12604000);

      gateway
        ..snapshotUnreachable = RemoteFailure.offline
        ..newerUnreachable = RemoteFailure.offline;
      await c.read(dashboardSyncProvider.notifier).refresh();
      await tester.pumpAndSettle();

      // Figures untouched — a failed run writes nothing (D-048) — and the failure is
      // reported beside them rather than instead of them.
      expect(amountAt(tester, 'dashboard-net-sales-value').paise, 12604000);
      expect(find.byKey(const Key('dashboard-offline')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-body')), findsOneWidget);
    });

    uiTest('12 · a range this device does not hold is never ₹0', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      // Two financial years back is outside retention and has never been fetched.
      c
          .read(dashboardSelectionProvider.notifier)
          .selectCustom(
            BusinessDate.of(2024, 5, 1),
            BusinessDate.of(2024, 5, 31),
          );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dashboard-not-downloaded')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-body')), findsNothing);
      expect(find.textContaining('₹0.00'), findsNothing);
      expect(find.byType(TrendLineChart), findsNothing);
    });

    uiTest('13 · two synchronisations make no single as-of claim', (
      tester,
    ) async {
      crystalCanopySeptember();
      gateway
        ..revenue.add(_sale(_ccr, '2025-03-10', gross: 2100000, tax: 100000))
        ..revenue.add(_sale(_ccr, '2025-04-12', gross: 1050000, tax: 50000))
        ..expense.add(_cost(_ccr, '2025-04-15', 300000));
      final c = await pump(tester, grants: _d2(_ccr));

      // A range spanning 1 April 2025: FY 25-26 is inside normal retention and arrives
      // with a refresh, while FY 24-25 is outside it and is fetched on demand — so the
      // two halves of this report carry two runs' evidence (D-188).
      c
          .read(dashboardSelectionProvider.notifier)
          .selectCustom(
            BusinessDate.of(2025, 3, 1),
            BusinessDate.of(2025, 4, 30),
          );
      await tester.pumpAndSettle();
      await c.read(dashboardSyncProvider.notifier).refresh();
      await tester.pumpAndSettle();
      await c.read(dashboardSyncProvider.notifier).download();
      await tester.pumpAndSettle();

      final ready = await readyOf(c);
      expect(ready.view.isComputed, isTrue);
      expect(
        ready.freshness,
        isNull,
        reason: 'segments from two runs cannot be dated to one moment (D-188)',
      );
      expect(find.byKey(const Key('dashboard-freshness-none')), findsOneWidget);
      expect(find.textContaining('Synchronised as of'), findsNothing);
    });

    uiTest('a synchronised dashboard states the server-confirmed time', (
      tester,
    ) async {
      crystalCanopySeptember();
      await pump(tester, grants: _d2(_ccr));
      expect(
        find.byKey(const Key('dashboard-freshness-synchronised')),
        findsOneWidget,
      );
      expect(find.textContaining('Synchronised as of'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 14, 15 · trends
  // ═══════════════════════════════════════════════════════════════════════════

  group('trends', () {
    uiTest('a Net Sales trend is drawn, and the profit trend only by month', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));

      // Month to date trends Net Sales daily and offers no cost trend at all (D-255).
      expect(
        find.byKey(const Key('dashboard-trend-net-sales')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('dashboard-trend-operating-profit')),
        findsNothing,
      );

      await choosePeriod(c, tester, DashboardPeriodKind.financialYearToDate);
      expect(
        find.byKey(const Key('dashboard-trend-net-sales')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('dashboard-trend-operating-profit')),
        findsOneWidget,
      );
    });

    uiTest('15 · a clipped bucket stays marked as a partial period', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      await choosePeriod(c, tester, DashboardPeriodKind.financialYearToDate);

      final series = (await readyOf(
        c,
      )).view.trends.firstWhere((s) => s.measure == TrendMeasure.netSales);
      // September ends at the 19th, so the last monthly bucket is clipped.
      expect(series.points.last.bucket.partial, isTrue);
      expect(
        find.textContaining('partial period'),
        findsWidgets,
        reason:
            'a clipped point is labelled rather than stretched to a whole month (D-263)',
      );
    });

    test('14 · a missing bucket reaches the chart as a gap, never as zero', () {
      // Composed exactly as the surface composes it — `dashboardTrendChartData` is the
      // one adapter both use — from a series whose middle bucket could not be
      // established.
      ReportRange range(int fromDay, int toDay) => switch (CustomRangePeriod(
        from: BusinessDate.of(2026, 9, fromDay),
        to: BusinessDate.of(2026, 9, toDay),
      ).resolve()) {
        ReportRangeResolved(:final range) => range,
        _ => throw StateError('range'),
      };

      final buckets = [
        for (var day = 1; day <= 3; day++)
          TrendBucket(range: range(day, day), partial: false),
      ];
      PnlOutcome computed(ReportRange r, int net) => PnlComputed(
        PnlResult(
          range: r,
          businessUnitId: _ccr,
          grossSales: Money.fromPaise(net),
          gst: Money.zero,
          netSales: Money.fromPaise(net),
          expenses: Money.zero,
        ),
      );

      final chart =
          dashboardTrendChartData(
                DashboardTrends.series(
                  measure: TrendMeasure.netSales,
                  grain: TrendGrain.daily,
                  buckets: buckets,
                  outcomes: [
                    computed(buckets[0].range, 500000),
                    const PnlRefused(PnlRefusal.bothSidesUnavailable),
                    computed(buckets[2].range, 700000),
                  ],
                ),
              )
              as TrendChartReady;

      expect(chart.points[0], isA<ChartPlotted>());
      expect(chart.points[1], isA<ChartAbsent>());
      expect(chart.points[2], isA<ChartPlotted>());
      expect(chart.hasGap, isTrue);
      // The gap carries no amount at all, so nothing downstream can plot one.
      expect(chart.points[1], isNot(isA<ChartPlotted>()));
      // And the axis is built from the two real figures alone.
      expect(chart.axis.maxPaise, 700000);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 16 … 20 · property comparison and the ranked sections
  // ═══════════════════════════════════════════════════════════════════════════

  group('property comparison', () {
    uiTest('a consolidated dashboard compares the properties exactly', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pump(tester);

      expect(
        find.byKey(const Key('dashboard-property-comparison')),
        findsOneWidget,
      );
      final split =
          (await readyOf(c)).view.propertyComparison!
              as PropertyComparisonReady;
      expect(split.properties.map((p) => p.businessUnitId), [_ccr, _hki]);
      expect(split.properties[0].netSales.paise, 12604000);
      expect(split.properties[1].netSales.paise, 4034300);
      expect(split.properties[0].operatingProfit.paise, 3063657);
      expect(split.properties[1].operatingProfit.paise, 1034300);
      // The parts add back to the headline on screen, exactly.
      expect(
        Money.sum(split.properties.map((p) => p.netSales)),
        amountAt(tester, 'dashboard-net-sales-value'),
      );
      // No winner is named.
      for (final word in const ['Best', 'Winner', 'Leading', 'Top property']) {
        expect(find.textContaining(word), findsNothing);
      }
    });

    uiTest('16 · it is hidden outside a consolidated scope', (tester) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pump(tester);
      expect(
        find.byKey(const Key('dashboard-property-comparison')),
        findsOneWidget,
      );

      c
          .read(dashboardSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(_ccr));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('dashboard-property-comparison')),
        findsNothing,
      );
      expect(
        (await readyOf(c)).view.propertyComparison,
        isA<PropertyComparisonRefused>(),
      );
    });
  });

  group('the ranked sections', () {
    uiTest('17 · revenue mix renders the prepared rows in the domain order', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      final top = (await readyOf(c)).view.topRevenueCategories! as TopNGrouped;

      expect(find.byKey(const Key('dashboard-revenue-mix')), findsOneWidget);
      for (var i = 0; i < top.top.length; i++) {
        expect(
          rowTextAt(
            tester,
            'dashboard-revenue-mix',
            RankedBarChart.valueKey(i),
          ),
          MoneyFormatter.standard.format(top.top[i].amount),
        );
      }
      // Restaurant is the larger, so it is first — the domain's order, not the page's.
      expect(
        rowTextAt(tester, 'dashboard-revenue-mix', RankedBarChart.labelKey(0)),
        'Restaurant',
      );
      expect(
        rowTextAt(tester, 'dashboard-revenue-mix', RankedBarChart.labelKey(1)),
        'Nandbhog',
      );
    });

    uiTest('18 · top expenses keep the domain\'s Top N and its exact Others', (
      tester,
    ) async {
      crystalCanopySeptember();
      // Enough categories that Others is real: with Kirana and Water, four kitchen
      // categories make six lines — five ranked lines plus a remainder. Each lives under
      // the kitchen's own section, as the server requires (D-040, D-280).
      for (final (day, amount, category) in const [
        ('2026-09-14', 400000, 'gas'),
        ('2026-09-15', 300000, 'milk'),
        ('2026-09-16', 200000, 'paneer'),
        ('2026-09-17', 100000, 'veg'),
      ]) {
        gateway.expense.add(
          _cost(
            _ccr,
            day,
            amount,
            category: category,
            department: 'kitchen',
            section: 'kitchen-section',
          ),
        );
      }
      final c = await pump(tester, grants: _d2(_ccr));
      final top = (await readyOf(c)).view.topExpenseCategories! as TopNGrouped;
      expect(top.top.length, 5);
      expect(top.others, isNotNull, reason: 'six lines: a real Others');

      expect(find.byKey(const Key('dashboard-top-expenses')), findsOneWidget);
      // Whatever the domain grouped is what is drawn, including its Others figure.
      expect(top.total, amountAt(tester, 'dashboard-expenses-value'));
      expect(
        Money.sum([...top.top.map((l) => l.amount), ?top.others]),
        top.total,
        reason: 'Others is the exact remainder, so the set still reconciles',
      );
    });

    uiTest('19 · department spending renders the prepared department lines', (
      tester,
    ) async {
      crystalCanopySeptember();
      gateway.expense.add(
        _cost(
          _ccr,
          '2026-09-14',
          750000,
          category: 'gas',
          department: 'kitchen',
          section: 'kitchen-section',
        ),
      );
      final c = await pump(tester, grants: _d2(_ccr));
      final departments =
          (await readyOf(c)).view.departmentSpending! as TopNGrouped;

      expect(find.byKey(const Key('dashboard-departments')), findsOneWidget);
      expect(departments.top.length, 2);
      expect(departments.total, amountAt(tester, 'dashboard-expenses-value'));
      expect(find.text(_longDepartment), findsOneWidget);
    });

    uiTest('20 · a long name stays readable and money is never truncated', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      final top = (await readyOf(c)).view.topExpenseCategories! as TopNGrouped;

      // The category with the long hospitality name is the largest.
      final label = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('dashboard-top-expenses')),
          matching: find.byKey(RankedBarChart.labelKey(0)),
        ),
      );
      expect(label.data, contains('Kirana'));
      // The whole name, wrapping onto a second line rather than being cut short
      // (D-269, D-286).
      expect(label.overflow, isNull);
      expect(label.maxLines, isNull);
      expectMoneyWholeAndUnshrunk(tester, 'the Overview');

      final value = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('dashboard-top-expenses')),
          matching: find.byKey(RankedBarChart.valueKey(0)),
        ),
      );
      expect(value.data, MoneyFormatter.standard.format(top.top.first.amount));
      expect(
        value.overflow,
        TextOverflow.visible,
        reason: 'a truncated amount is a wrong amount (D-269)',
      );
      expect(value.maxLines, 1);
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 21, 22 · Windows layout
  // ═══════════════════════════════════════════════════════════════════════════

  group('the Windows layout', () {
    for (final (name, size) in [
      ('1366×768', _laptop),
      ('a narrower window', _narrow),
      ('maximised', _wide),
    ]) {
      uiTest('21, 22 · $name renders with nothing clipped or overflowing', (
        tester,
      ) async {
        crystalCanopySeptember();
        hotelKrishnaSeptember();
        await pump(tester, size: size);

        expect(tester.takeException(), isNull);
        await expectEveryAmountWholeWhileScrolling(tester, name);
        // Every approved section is present and reachable at this width.
        for (final key in const [
          'dashboard-body',
          'dashboard-net-sales-value',
          'dashboard-expenses-value',
          'dashboard-operating-value',
          'dashboard-margin-value',
          'dashboard-trend-net-sales',
          'dashboard-property-comparison',
          'dashboard-revenue-mix',
          'dashboard-top-expenses',
          'dashboard-departments',
        ]) {
          expect(find.byKey(Key(key)), findsOneWidget, reason: '$key at $name');
        }
        // A page that scrolls vertically must never scroll sideways.
        final scrollables = tester.widgetList<Scrollable>(
          find.byType(Scrollable),
        );
        for (final scrollable in scrollables) {
          expect(
            scrollable.axisDirection,
            isNot(AxisDirection.right),
            reason: 'no horizontal page scroll at $name',
          );
          expect(scrollable.axisDirection, isNot(AxisDirection.left));
        }
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 23, 24, 25 · what the surface may not do
  // ═══════════════════════════════════════════════════════════════════════════

  group('what the Overview may not do', () {
    uiTest('23 · money on screen is the exact figure, never a coordinate', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      final result = (await readyOf(c)).view.resultOrNull!;

      // A figure read back from a `double` coordinate would lose the Indian grouping and
      // the paise; every label here is the formatter's own output over exact paise.
      expect(
        rowTextAt(tester, 'dashboard-revenue-mix', RankedBarChart.valueKey(0)),
        matches(RegExp(r'^₹[\d,]+\.\d{2}$')),
      );
      expect(find.textContaining('e+'), findsNothing);
      expect(find.textContaining('.0000'), findsNothing);
      expect(
        amountAt(tester, 'dashboard-net-sales-value').paise,
        result.netSales.paise,
      );
    });

    uiTest('24 · rendering reaches no server and no database of its own', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));
      final afterOpening = gateway.snapshots;

      // Re-rendering the whole page — a period change and back — asks the server nothing.
      await choosePeriod(c, tester, DashboardPeriodKind.weekToDate);
      await choosePeriod(c, tester, DashboardPeriodKind.monthToDate);
      expect(gateway.snapshots, afterOpening);
      expect(find.byKey(const Key('dashboard-body')), findsOneWidget);
    });

    uiTest('25 · no Owner Accounts figure appears on the Overview', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      await pump(
        tester,
        grants: [
          ..._d2(),
          const CapabilityGrant(Capability.ownerSettlementView),
          const CapabilityGrant(Capability.ownerLedgerView),
        ],
      );

      for (final word in const [
        'Owner Settlement',
        'Due to owner',
        'Recoverable from owner',
        'Entitlement',
        'Withdrawals',
        'Non-chargeable',
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Periods
  // ═══════════════════════════════════════════════════════════════════════════

  group('periods', () {
    uiTest('every period is named as unfinished, and Custom is offered', (
      tester,
    ) async {
      crystalCanopySeptember();
      await pump(tester, grants: _d2(_ccr));

      for (final kind in DashboardPeriodKind.values) {
        expect(find.text(kind.label), findsOneWidget, reason: kind.name);
      }
      expect(find.text('Today so far'), findsOneWidget);
      expect(find.text('Month to date'), findsOneWidget);
      // The P&L's whole-month semantics are not reused here (D-252).
      expect(find.text('This Month'), findsNothing);
      expect(find.text('Financial Year'), findsNothing);
    });

    uiTest('a period the properties disagree about is refused, not guessed', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      await pump(tester, instant: _disagreeing);

      expect(find.byKey(const Key('dashboard-periods-differ')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-body')), findsNothing);
      expect(find.textContaining('Use Custom'), findsOneWidget);
    });

    uiTest(
      'a custom range that ends before it starts is refused, not swapped',
      (tester) async {
        crystalCanopySeptember();
        final c = await pump(tester, grants: _d2(_ccr));
        c
            .read(dashboardSelectionProvider.notifier)
            .selectCustom(
              BusinessDate.of(2026, 9, 19),
              BusinessDate.of(2026, 9, 1),
            );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('dashboard-invalid-range')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('dashboard-body')), findsNothing);
      },
    );
  });
}
