/// The Windows Analytics workspace, rendered through the real provider chain
/// (Phase 6 Slice 8).
///
/// What is real: the page, the embedded Phase 5 Profit & Loss, the Slice 4 providers,
/// `PnlAuthority`, the master graph and business-day rules read from SQLite, the canonical
/// reporting cache, `ReportingSync`, `MarkerCoverage`, `CachedReportingSource`,
/// `LocalReportingEngine`, `Pnl.compute`, the Slice 3 `DashboardEngine`, the Slice 2
/// comparison, trend and Top-N rules, `PropertyComparison`, and the Slice 5 charts.
///
/// What is substituted, and only this: the remote reporting transport and the instant the
/// surface treats as "now". **A test never hands a section a figure** in the rendered
/// path: every paisa is synchronised into the cache and read back by the engine. The one
/// group that builds a view by hand does so through the real domain functions, to reach
/// the refusals a reconciling fixture cannot produce.
///
/// The numbers in test names are the Slice 8 brief's.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
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
import 'package:krishna_mis/data/reporting/dashboard_engine.dart';
import 'package:krishna_mis/data/reporting/reporting_engine.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
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
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_providers.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_drill.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_navigation.dart';
import 'package:krishna_mis/features/analytics/presentation/analytics_page.dart';
import 'package:krishna_mis/features/analytics/presentation/business_comparison.dart';
import 'package:krishna_mis/features/analytics/presentation/expense_analysis.dart';
import 'package:krishna_mis/features/analytics/presentation/revenue_analysis.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/profit_and_loss_page.dart';
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
    // The kitchen department has its own section and category. A cost booked to a
    // department must carry a category that really lives under it: the server's composite
    // hierarchy keys make any other row impossible (D-040), and the embedded P&L keys its
    // category lines on that guarantee.
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
                Expanded(child: AnalyticsPage(shellKind: AppShellKind.desktop)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(AnalyticsPage)),
    );
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

  /// Opens a section the way a reader does: by pressing its segment.
  Future<void> open(WidgetTester tester, AnalyticsSection section) async {
    await tester.tap(find.byKey(Key('analytics-section-${section.name}')));
    await tester.pumpAndSettle();
  }

  Future<ProviderContainer> pumpAt(
    WidgetTester tester,
    AnalyticsSection section, {
    List<CapabilityGrant>? grants,
    _Session? session,
    Size size = _laptop,
    DateTime? instant,
  }) async {
    final c = await pump(
      tester,
      grants: grants,
      session: session,
      size: size,
      instant: instant,
    );
    await open(tester, section);
    return c;
  }

  void moreCategories() {
    // Four more kitchen categories: with Kirana and Water that is six lines, so the
    // domain's Top 5 has a real, exact Others.
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
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // General · 1 … 10
  // ═══════════════════════════════════════════════════════════════════════════

  group('the workspace', () {
    uiTest('1 · Profit & Loss is the existing Phase 5 page, and opens first', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));

      expect(c.read(analyticsSectionProvider), AnalyticsSection.profitAndLoss);
      expect(find.byType(ProfitAndLossPage), findsOneWidget);
      expect(find.byKey(const Key('pnl-page')), findsOneWidget);
      // Its periods are the P&L's own whole-month presets, not the dashboard's.
      expect(
        AnalyticsSection.profitAndLoss.periodModel,
        AnalyticsPeriodModel.pnlPresets,
      );
      for (final section in [
        AnalyticsSection.revenue,
        AnalyticsSection.expenses,
        AnalyticsSection.businessComparison,
      ]) {
        expect(section.periodModel, AnalyticsPeriodModel.dashboardToDate);
      }

      // The P&L is kept, not rebuilt, while the reader looks at another section.
      final before = tester.state(find.byType(ProfitAndLossPage));
      await open(tester, AnalyticsSection.revenue);
      expect(find.byKey(const Key('analytics-revenue')), findsOneWidget);
      expect(find.byKey(const Key('pnl-page')), findsNothing);
      await open(tester, AnalyticsSection.profitAndLoss);
      expect(tester.state(find.byType(ProfitAndLossPage)), same(before));
      expect(find.byKey(const Key('pnl-page')), findsOneWidget);
    });

    uiTest(
      'the analysis sections run under the dashboard periods, and say so',
      (tester) async {
        crystalCanopySeptember();
        await pumpAt(tester, AnalyticsSection.revenue, grants: _d2(_ccr));

        expect(find.byKey(const Key('analytics-period-model')), findsOneWidget);
        for (final kind in DashboardPeriodKind.values) {
          expect(find.text(kind.label), findsOneWidget, reason: kind.name);
        }
        expect(find.text('This Month'), findsNothing);
      },
    );

    uiTest('switching sections reads nothing again', (tester) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pumpAt(tester, AnalyticsSection.revenue);
      final first = await readyOf(c);
      final snapshots = gateway.snapshots;

      await open(tester, AnalyticsSection.expenses);
      await open(tester, AnalyticsSection.businessComparison);
      await open(tester, AnalyticsSection.revenue);

      expect(
        await readyOf(c),
        same(first),
        reason: 'every section is an arrangement of one prepared view',
      );
      expect(gateway.snapshots, snapshots);
    });

    uiTest('4 · business comparison needs consolidated authority', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      await pumpAt(
        tester,
        AnalyticsSection.businessComparison,
        grants: _d2(_ccr),
      );

      expect(
        find.byKey(const Key('analytics-comparison-not-authorised')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('analytics-comparison')), findsNothing);
      // It names no property the reader may not see.
      expect(find.textContaining('Hotel Krishna Imperial'), findsNothing);
    });

    uiTest('26 · a single-property scope cannot show it, even with authority', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pump(tester);
      c
          .read(dashboardSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(_ccr));
      await tester.pumpAndSettle();
      await open(tester, AnalyticsSection.businessComparison);

      expect(
        find.byKey(const Key('analytics-comparison-needs-both')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('analytics-comparison')), findsNothing);

      await tester.tap(find.text('Compare both properties'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analytics-comparison')), findsOneWidget);
      expect(
        c.read(dashboardSelectionProvider).scope,
        const PnlConsolidatedScope(),
      );
    });

    uiTest('5 · no Owner Accounts figure appears in any section', (
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
      for (final section in AnalyticsSection.values) {
        await open(tester, section);
        for (final word in const [
          'Owner Settlement',
          'Due to owner',
          'Recoverable from owner',
          'Entitlement',
          'Withdrawals',
          'Non-chargeable',
        ]) {
          expect(
            find.textContaining(word),
            findsNothing,
            reason: '$word in ${section.name}',
          );
        }
      }
    });

    uiTest('6 · a different person never sees the previous analysis', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final session = _Session(readySession(authority: _authority(_d2())));
      final c = await pumpAt(
        tester,
        AnalyticsSection.revenue,
        session: session,
      );
      expect(
        amountAt(tester, 'analytics-revenue-net-sales-value').paise,
        16638300,
      );
      final owners = await readyOf(c);

      session.become(
        readySession(authority: _authority(_d2(_ccr), userId: _other)),
      );
      await tester.pump();
      final next = c.read(sessionProvider).principal;
      expect(
        dashboardPresentation(
          state: AsyncData<DashboardState>(owners),
          sync: c.read(dashboardSyncProvider),
          principal: next,
        ),
        isA<DashboardLoading>(),
      );
      await tester.pumpAndSettle();

      // A new person opens on the Profit & Loss, and the workspace behind it no longer
      // holds the Owner's consolidated analysis.
      expect(c.read(analyticsSectionProvider), AnalyticsSection.profitAndLoss);
      expect(
        find.textContaining('₹1,66,383.00', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.textContaining('Hotel Krishna Imperial', skipOffstage: false),
        findsNothing,
      );
    });

    uiTest('7 · a revoked capability takes the analysis away at once', (
      tester,
    ) async {
      crystalCanopySeptember();
      final session = _Session(readySession(authority: _authority(_d2(_ccr))));
      final c = await pumpAt(
        tester,
        AnalyticsSection.revenue,
        session: session,
      );
      expect(find.byKey(const Key('analytics-body')), findsOneWidget);

      // The same person, without revenue.view.
      session.become(
        readySession(
          authority: _authority(const [
            CapabilityGrant(Capability.reportsView, businessUnitId: _ccr),
            CapabilityGrant(Capability.expenseViewAll, businessUnitId: _ccr),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(c.read(analyticsSectionProvider), AnalyticsSection.profitAndLoss);
      expect(
        find.byKey(const Key('analytics-body'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const Key('dashboard-not-authorised'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('₹1,26,040.00', skipOffstage: false),
        findsNothing,
      );
    });

    uiTest('8 · missing data is never a zero', (tester) async {
      crystalCanopySeptember();
      final c = await pumpAt(
        tester,
        AnalyticsSection.revenue,
        grants: _d2(_ccr),
      );
      c
          .read(dashboardSelectionProvider.notifier)
          .selectCustom(
            BusinessDate.of(2024, 5, 1),
            BusinessDate.of(2024, 5, 31),
          );
      await tester.pumpAndSettle();

      for (final section in const [
        AnalyticsSection.revenue,
        AnalyticsSection.expenses,
      ]) {
        await open(tester, section);
        expect(
          find.byKey(const Key('dashboard-not-downloaded')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('analytics-body')), findsNothing);
        expect(find.textContaining('₹0.00'), findsNothing);
        expect(find.byType(TrendLineChart), findsNothing);
        expect(find.byType(RankedBarChart), findsNothing);
      }
    });

    uiTest('9 · a failed refresh keeps the complete analysis on screen', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pumpAt(
        tester,
        AnalyticsSection.expenses,
        grants: _d2(_ccr),
      );
      expect(amountAt(tester, 'analytics-expense-total-value').paise, 9540343);

      gateway
        ..snapshotUnreachable = RemoteFailure.offline
        ..newerUnreachable = RemoteFailure.offline;
      await c.read(dashboardSyncProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(amountAt(tester, 'analytics-expense-total-value').paise, 9540343);
      expect(find.byKey(const Key('dashboard-offline')), findsOneWidget);
      expect(find.byKey(const Key('analytics-body')), findsOneWidget);
    });

    uiTest('10 · two synchronisations invent no single as-of time', (
      tester,
    ) async {
      crystalCanopySeptember();
      gateway
        ..revenue.add(_sale(_ccr, '2025-03-10', gross: 2100000, tax: 100000))
        ..revenue.add(_sale(_ccr, '2025-04-12', gross: 1050000, tax: 50000))
        ..expense.add(_cost(_ccr, '2025-04-15', 300000));
      final c = await pumpAt(
        tester,
        AnalyticsSection.revenue,
        grants: _d2(_ccr),
      );
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

      expect((await readyOf(c)).freshness, isNull);
      expect(find.byKey(const Key('dashboard-freshness-none')), findsOneWidget);
      expect(find.textContaining('Synchronised as of'), findsNothing);
      expect(find.byKey(const Key('analytics-body')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Revenue · 11 … 18
  // ═══════════════════════════════════════════════════════════════════════════

  group('revenue analysis', () {
    uiTest('2, 11 · Gross, GST and Net Sales are the canonical result', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pumpAt(tester, AnalyticsSection.revenue);
      final result = (await readyOf(c)).view.resultOrNull!;

      final gross = amountAt(tester, 'analytics-revenue-gross-sales-value');
      final gst = amountAt(tester, 'analytics-revenue-gst-value');
      final net = amountAt(tester, 'analytics-revenue-net-sales-value');
      expect(gross, result.grossSales);
      expect(gst, result.gst);
      expect(net, result.netSales);
      // Hand-worked: 13234200 + 4034300 gross, 630200 GST, 16638300 net.
      expect(gross.paise, 17268500);
      expect(gst.paise, 630200);
      expect(net.paise, 16638300);
      expect(gross, gst + net, reason: 'Gross = GST + Net, as shown');
    });

    uiTest('13 · the revenue mix is the prepared rows in the domain order', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pumpAt(tester, AnalyticsSection.revenue);
      final mix = (await readyOf(c)).view.topRevenueCategories! as TopNGrouped;

      expect(find.byKey(const Key('analytics-revenue-mix')), findsOneWidget);
      for (var i = 0; i < mix.top.length; i++) {
        expect(
          rowTextAt(
            tester,
            'analytics-revenue-mix',
            RankedBarChart.valueKey(i),
          ),
          MoneyFormatter.standard.format(mix.top[i].amount),
        );
      }
      expect(
        rowTextAt(tester, 'analytics-revenue-mix', RankedBarChart.labelKey(0)),
        'Crystal Canopy Rooftop · Restaurant',
      );
      expect(
        rowTextAt(tester, 'analytics-revenue-mix', RankedBarChart.labelKey(1)),
        'Hotel Krishna Imperial · Banquet',
      );
      // The rows add up to Net Sales exactly: the domain checked before grouping.
      expect(mix.total, amountAt(tester, 'analytics-revenue-net-sales-value'));
    });

    uiTest("14 · the Net Sales trend follows the planner's grain", (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pumpAt(
        tester,
        AnalyticsSection.revenue,
        grants: _d2(_ccr),
      );

      TrendSeries netSales(DashboardReady r) =>
          r.view.trends.firstWhere((s) => s.measure == TrendMeasure.netSales);
      expect(netSales(await readyOf(c)).grain, TrendGrain.daily);
      expect(
        find.descendant(
          of: find.byKey(const Key('analytics-revenue-trend')),
          matching: find.byType(TrendLineChart),
        ),
        findsOneWidget,
      );

      await choosePeriod(c, tester, DashboardPeriodKind.financialYearToDate);
      expect(netSales(await readyOf(c)).grain, TrendGrain.monthly);

      // A 40-day custom range is weekly (D-263).
      c
          .read(dashboardSelectionProvider.notifier)
          .selectCustom(
            BusinessDate.of(2026, 8, 1),
            BusinessDate.of(2026, 9, 9),
          );
      await tester.pumpAndSettle();
      expect(netSales(await readyOf(c)).grain, TrendGrain.weekly);

      // Today so far is one business date: no trend, and the section says why.
      await choosePeriod(c, tester, DashboardPeriodKind.today);
      expect(
        find.byKey(const Key('analytics-revenue-no-trend')),
        findsOneWidget,
      );
      expect(find.byType(TrendLineChart), findsNothing);
    });

    test('15 · a missing bucket reaches the chart as a gap, never a zero', () {
      ReportRange range(int day) => switch (CustomRangePeriod(
        from: BusinessDate.of(2026, 9, day),
        to: BusinessDate.of(2026, 9, day),
      ).resolve()) {
        ReportRangeResolved(:final range) => range,
        _ => throw StateError('range'),
      };
      final buckets = [
        for (var day = 1; day <= 3; day++)
          TrendBucket(range: range(day), partial: false),
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
      // The same composition the sections use.
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
      expect(chart.axis.maxPaise, 700000);
    });

    uiTest('16 · a clipped bucket stays marked partial', (tester) async {
      crystalCanopySeptember();
      final c = await pumpAt(
        tester,
        AnalyticsSection.revenue,
        grants: _d2(_ccr),
      );
      await choosePeriod(c, tester, DashboardPeriodKind.financialYearToDate);

      final series = (await readyOf(
        c,
      )).view.trends.firstWhere((s) => s.measure == TrendMeasure.netSales);
      expect(series.points.last.bucket.partial, isTrue);
      expect(
        find.descendant(
          of: find.byKey(const Key('analytics-revenue-trend')),
          matching: find.textContaining('partial period'),
        ),
        findsWidgets,
      );
    });

    uiTest('17 · each movement is exactly the one the domain decided', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pumpAt(
        tester,
        AnalyticsSection.revenue,
        grants: _d2(_ccr),
      );
      final comparison = (await readyOf(c)).view.comparison;

      for (final (key, figure) in [
        ('revenue-gross-sales', comparison.grossSales),
        ('revenue-gst', comparison.gst),
        ('revenue-net-sales', comparison.netSales),
      ]) {
        expect(
          textAt(tester, 'analytics-$key-movement'),
          dashboardMoneyMovement(figure).text,
          reason: key,
        );
      }
      // Hand-worked: 12604000 − 9523810.
      expect(
        textAt(tester, 'analytics-revenue-net-sales-movement'),
        startsWith('+₹30,801.90'),
      );
      expect(
        textAt(tester, 'analytics-compared-with'),
        contains('1 AUG 2026 – 19 AUG 2026'),
      );
    });

    uiTest('18 · a nil or unavailable previous period gives no percentage', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pumpAt(
        tester,
        AnalyticsSection.revenue,
        grants: _d2(_ccr),
      );
      await choosePeriod(c, tester, DashboardPeriodKind.financialYearToDate);

      // Not downloaded is "not available", never nil and never ₹0.
      expect(
        textAt(tester, 'analytics-revenue-net-sales-movement'),
        'No comparison — the previous period is not available.',
      );

      // Fetched, the previous year is a real nil: a rupee movement, no percentage.
      await c.read(dashboardSyncProvider.notifier).refresh();
      await tester.pumpAndSettle();
      final movement = textAt(tester, 'analytics-revenue-net-sales-movement');
      expect(movement, startsWith('+₹'));
      expect(movement, isNot(contains('%')));
      expect(
        textAt(tester, 'analytics-revenue-net-sales-movement-note'),
        'No percentage: the previous period was nil.',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Expense & Department · 19 … 25
  // ═══════════════════════════════════════════════════════════════════════════

  group('expense and department analysis', () {
    uiTest('3, 19 · Operating Expenses is the canonical figure', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pumpAt(tester, AnalyticsSection.expenses);
      final ready = await readyOf(c);

      expect(
        amountAt(tester, 'analytics-expense-total-value'),
        ready.view.resultOrNull!.expenses,
      );
      expect(amountAt(tester, 'analytics-expense-total-value').paise, 12540343);
      expect(
        textAt(tester, 'analytics-expense-total-movement'),
        dashboardMoneyMovement(ready.view.comparison.expenses).text,
      );
    });

    uiTest('20, 21 · the expense trend is monthly, and never daily', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pumpAt(
        tester,
        AnalyticsSection.expenses,
        grants: _d2(_ccr),
      );

      // Month to date offers expenses no grain at all (D-255): a statement, no plot.
      final mtd = await readyOf(c);
      expect(
        mtd.view.trends.where((s) => s.measure == TrendMeasure.expenses),
        isEmpty,
      );
      expect(
        find.byKey(const Key('analytics-expense-no-trend')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('analytics-expense-trend')),
          matching: find.byType(TrendLineChart),
        ),
        findsNothing,
      );

      await choosePeriod(c, tester, DashboardPeriodKind.financialYearToDate);
      final fytd = await readyOf(c);
      final expenses = fytd.view.trends
          .where((s) => s.measure == TrendMeasure.expenses)
          .toList();
      expect(expenses.single.grain, TrendGrain.monthly);
      expect(
        find.descendant(
          of: find.byKey(const Key('analytics-expense-trend')),
          matching: find.byType(TrendLineChart),
        ),
        findsOneWidget,
      );
      // No series carries expenses or profit at a daily or weekly grain.
      for (final series in fytd.view.trends) {
        if (series.measure != TrendMeasure.netSales) {
          expect(series.grain, TrendGrain.monthly);
        }
      }
    });

    uiTest("22, 24 · top categories are the domain's Top N and exact Others", (
      tester,
    ) async {
      crystalCanopySeptember();
      moreCategories();
      final c = await pumpAt(
        tester,
        AnalyticsSection.expenses,
        grants: _d2(_ccr),
      );
      final top = (await readyOf(c)).view.topExpenseCategories! as TopNGrouped;

      expect(find.byKey(const Key('analytics-top-expenses')), findsOneWidget);
      for (var i = 0; i < top.top.length; i++) {
        expect(
          rowTextAt(
            tester,
            'analytics-top-expenses',
            RankedBarChart.valueKey(i),
          ),
          MoneyFormatter.standard.format(top.top[i].amount),
        );
      }
      expect(top.total, amountAt(tester, 'analytics-expense-total-value'));
      expect(top.top.length, 5);
      expect(top.othersCount, 1);
      // Others is drawn as the domain handed it over, as the last row: the smallest
      // line, Vegetables & Fruits at ₹1,000.00.
      final others = top.others!;
      expect(others.paise, 100000);
      {
        final last = top.top.length;
        expect(
          rowTextAt(
            tester,
            'analytics-top-expenses',
            RankedBarChart.valueKey(last),
          ),
          MoneyFormatter.standard.format(others),
        );
        expect(
          rowTextAt(
            tester,
            'analytics-top-expenses',
            RankedBarChart.labelKey(last),
          ),
          startsWith('Others'),
        );
      }
    });

    uiTest('23 · department spending is the prepared department lines', (
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
      final c = await pumpAt(
        tester,
        AnalyticsSection.expenses,
        grants: _d2(_ccr),
      );
      final departments =
          (await readyOf(c)).view.departmentSpending! as TopNGrouped;

      expect(find.byKey(const Key('analytics-departments')), findsOneWidget);
      expect(departments.top.length, 2);
      for (var i = 0; i < departments.top.length; i++) {
        expect(
          rowTextAt(
            tester,
            'analytics-departments',
            RankedBarChart.valueKey(i),
          ),
          MoneyFormatter.standard.format(departments.top[i].amount),
        );
      }
      expect(find.text(_longDepartment), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Business Comparison · 27 … 31
  // ═══════════════════════════════════════════════════════════════════════════

  group('business comparison', () {
    uiTest('27, 29 · every cell is the prepared per-property figure', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pumpAt(tester, AnalyticsSection.businessComparison);
      final split =
          (await readyOf(c)).view.propertyComparison!
              as PropertyComparisonReady;

      expect(split.properties.map((p) => p.businessUnitId), [_ccr, _hki]);
      for (final property in split.properties) {
        final id = property.businessUnitId;
        expect(
          amountAt(tester, 'analytics-comparison-$id-net-sales'),
          property.netSales,
        );
        expect(
          amountAt(tester, 'analytics-comparison-$id-expenses'),
          property.expenses,
        );
        expect(
          amountAt(tester, 'analytics-comparison-$id-operating'),
          property.operatingProfit,
        );
        expect(
          textAt(tester, 'analytics-comparison-$id-margin'),
          property.result.margin.displayTwoDecimals,
        );
      }
      // The combined column is the consolidated result itself.
      expect(
        amountAt(tester, 'analytics-comparison-total-net-sales'),
        split.total.netSales,
      );
      expect(
        textAt(tester, 'analytics-comparison-total-margin'),
        split.total.margin.displayTwoDecimals,
      );
      // Hand-worked: 3063657 ÷ 12604000 and 1034300 ÷ 4034300.
      expect(textAt(tester, 'analytics-comparison-$_ccr-margin'), '24.31%');
      expect(textAt(tester, 'analytics-comparison-$_hki-margin'), '25.64%');
      expect(
        find.byKey(const Key('analytics-comparison-chart')),
        findsOneWidget,
      );
    });

    uiTest('28 · an Operating Loss is said in words, not by colour', (
      tester,
    ) async {
      crystalCanopySeptember();
      gateway
        ..revenue.add(
          _sale(
            _hki,
            '2026-09-15',
            gross: 1000000,
            tax: 0,
            category: 'banquet',
          ),
        )
        ..expense.add(
          _cost(_hki, '2026-09-16', 3000000, category: 'electricity'),
        );
      await pumpAt(tester, AnalyticsSection.businessComparison);

      expect(
        amountAt(tester, 'analytics-comparison-$_hki-operating').paise,
        -2000000,
      );
      expect(
        textAt(tester, 'analytics-comparison-$_hki-operating-word'),
        'Loss',
      );
      expect(
        textAt(tester, 'analytics-comparison-$_ccr-operating-word'),
        'Profit',
      );
      // Neutral ink for every figure: no property is painted good or bad.
      for (final id in const [_ccr, _hki]) {
        expect(
          tester
              .widget<MoneyText>(
                find.byKey(Key('analytics-comparison-$id-operating')),
              )
              .emphasis,
          MoneyEmphasis.neutral,
        );
      }
    });

    uiTest('30 · no property is called a winner, better or best', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      await pumpAt(tester, AnalyticsSection.businessComparison);

      for (final word in const [
        'Winner',
        'winner',
        'Best',
        'best',
        'Better',
        'better',
        'Worse',
        'worst',
        'Leading',
        'outperform',
        'Top property',
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      expect(
        find.byKey(const Key('analytics-comparison-order-note')),
        findsOneWidget,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Refusals a reconciling fixture cannot reach · 12, 25
  // ═══════════════════════════════════════════════════════════════════════════

  group('a set that does not reconcile draws nothing', () {
    ReportRange range(BusinessDate from, BusinessDate to) =>
        switch (CustomRangePeriod(from: from, to: to).resolve()) {
          ReportRangeResolved(:final range) => range,
          _ => throw StateError('range'),
        };

    /// A consolidated result whose category lines add up to **less** than its headline
    /// figures — the shape a missing line would leave. Every outcome below is the real
    /// domain function's answer to it.
    DashboardReady unreconciled() {
      final current = range(
        BusinessDate.of(2026, 9, 1),
        BusinessDate.of(2026, 9, 19),
      );
      final previous = range(
        BusinessDate.of(2026, 8, 1),
        BusinessDate.of(2026, 8, 19),
      );
      final pair = DashboardPeriodPair.forTesting(
        current: current,
        comparison: previous,
        comparisonCapped: false,
        kind: DashboardPeriodKind.monthToDate,
      );
      final result = PnlResult(
        range: current,
        grossSales: Money.fromPaise(2000000),
        gst: Money.fromPaise(100000),
        netSales: Money.fromPaise(1900000),
        expenses: Money.fromPaise(900000),
        revenueByCategory: [
          RevenueCategoryLine(
            businessUnitId: _ccr,
            revenueCategoryId: '$_ccr-restaurant',
            totals: RevenueTotals(
              gross: Money.fromPaise(1050000),
              tax: Money.fromPaise(50000),
              net: Money.fromPaise(1000000),
              contributions: 1,
            ),
          ),
        ],
        expenseByHierarchy: [
          ExpenseHierarchyLine(
            businessUnitId: _ccr,
            departmentId: '$_ccr-dept',
            sectionId: '$_ccr-section',
            categoryId: '$_ccr-kirana',
            totals: ExpenseTotals(
              amount: Money.fromPaise(400000),
              contributions: 1,
            ),
          ),
        ],
      );
      final scope = ReportingScope(const [_ccr, _hki]);
      final now = PnlComputed(result);
      const before = PnlRefused(PnlRefusal.bothSidesUnavailable);
      ReportEnvelope envelope(PnlOutcome outcome, ReportRange r) =>
          ReportEnvelope(
            outcome: outcome,
            range: r,
            scope: scope,
            revenueCoverage: ReportingCoverage.complete,
            expenseCoverage: ReportingCoverage.complete,
          );
      return DashboardReady(
        'crafted',
        view: DashboardView(
          pair: pair,
          scope: scope,
          current: envelope(now, current),
          previous: envelope(before, previous),
          comparison: PnlComparison.compare(
            pair: pair,
            current: now,
            previous: before,
          ),
          trends: const [],
          revenueCoverage: ReportingCoverage.complete,
          expenseCoverage: ReportingCoverage.complete,
          stats: const DashboardReadStats(rangesRead: 2, trendPoints: 0),
          topRevenueCategories: TopN.revenueCategories(result, n: 5),
          topExpenseCategories: TopN.expenseCategories(result, n: 5),
          departmentSpending: TopN.departments(result, n: 5),
          propertyComparison: PropertyComparison.of(result),
        ),
        scope: const PnlConsolidatedScope(),
        neededYears: const [],
        retainedYears: const [],
      );
    }

    Future<void> render(WidgetTester tester, Widget section) async {
      await tester.binding.setSurfaceSize(_laptop);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            sessionProvider.overrideWith(
              () => _Session(readySession(authority: _authority(_d2()))),
            ),
            reportingClockProvider.overrideWithValue(() => _agreeing),
          ],
          child: MaterialApp(
            home: Scaffold(body: ListView(children: [section])),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    test('the domain refuses every grouping of it', () {
      final view = unreconciled().view;
      expect(view.topRevenueCategories, isA<TopNRefused>());
      expect(view.topExpenseCategories, isA<TopNRefused>());
      expect(view.departmentSpending, isA<TopNRefused>());
      expect(view.propertyComparison, isA<PropertyComparisonRefused>());
    });

    uiTest('12 · revenue categories that do not reconcile draw no rows', (
      tester,
    ) async {
      await render(tester, RevenueAnalysisSection(ready: unreconciled()));

      expect(
        find.descendant(
          of: find.byKey(const Key('analytics-revenue-mix')),
          matching: find.byKey(ChartUnavailable.findKey),
        ),
        findsOneWidget,
      );
      expect(find.byKey(RankedBarChart.valueKey(0)), findsNothing);
      // The headline figures are the result's own, and still shown.
      expect(
        amountAt(tester, 'analytics-revenue-net-sales-value').paise,
        1900000,
      );
    });

    uiTest(
      '25 · categories and departments that do not reconcile draw no rows',
      (tester) async {
        await render(tester, ExpenseAnalysisSection(ready: unreconciled()));

        for (final section in const [
          'analytics-top-expenses',
          'analytics-departments',
        ]) {
          expect(
            find.descendant(
              of: find.byKey(Key(section)),
              matching: find.byKey(ChartUnavailable.findKey),
            ),
            findsOneWidget,
            reason: section,
          );
        }
        expect(find.byKey(RankedBarChart.valueKey(0)), findsNothing);
        expect(find.textContaining('Others'), findsNothing);
      },
    );

    uiTest('a property split that does not reconcile is a stated refusal', (
      tester,
    ) async {
      await render(tester, BusinessComparisonSection(ready: unreconciled()));

      expect(
        find.byKey(const Key('analytics-comparison-does-not-reconcile')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('analytics-comparison-table')), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Windows layout · 32 … 38
  // ═══════════════════════════════════════════════════════════════════════════

  group('the Windows layout', () {
    for (final (name, size) in [
      ('1366×768', _laptop),
      ('a narrower window', _narrow),
      ('maximised', _wide),
    ]) {
      uiTest('32, 33, 34 · $name renders every section without overflow', (
        tester,
      ) async {
        crystalCanopySeptember();
        hotelKrishnaSeptember();
        moreCategories();
        final c = await pump(tester, size: size);
        c
            .read(dashboardSelectionProvider.notifier)
            .selectPeriod(DashboardPeriodKind.financialYearToDate);

        for (final (section, keys) in const [
          (
            AnalyticsSection.revenue,
            [
              'analytics-revenue-summary',
              'analytics-revenue-trend',
              'analytics-revenue-mix',
            ],
          ),
          (
            AnalyticsSection.expenses,
            [
              'analytics-expense-summary',
              'analytics-expense-trend',
              'analytics-top-expenses',
              'analytics-departments',
            ],
          ),
          (
            AnalyticsSection.businessComparison,
            ['analytics-comparison-table', 'analytics-comparison-chart'],
          ),
        ]) {
          await open(tester, section);
          expect(tester.takeException(), isNull, reason: '$section at $name');
          await expectEveryAmountWholeWhileScrolling(
            tester,
            '$section at $name',
          );
          for (final key in keys) {
            expect(
              find.byKey(Key(key)),
              findsOneWidget,
              reason: '$key at $name',
            );
          }
          for (final scrollable in tester.widgetList<Scrollable>(
            find.byType(Scrollable),
          )) {
            expect(scrollable.axisDirection, isNot(AxisDirection.right));
            expect(scrollable.axisDirection, isNot(AxisDirection.left));
          }
        }
        // And the section selector itself stays on the page.
        final selector = tester.getRect(
          find.byKey(const Key('analytics-sections')),
        );
        expect(selector.right, lessThanOrEqualTo(size.width));
      });
    }

    uiTest('34 · a maximised window keeps its ranked panels side by side', (
      tester,
    ) async {
      crystalCanopySeptember();
      moreCategories();
      await pumpAt(
        tester,
        AnalyticsSection.expenses,
        grants: _d2(_ccr),
        size: _wide,
      );
      // Two ranked panels side by side rather than one list stretched across the page.
      final categories = tester.getRect(
        find.byKey(const Key('analytics-top-expenses')),
      );
      final departments = tester.getRect(
        find.byKey(const Key('analytics-departments')),
      );
      expect(categories.top, departments.top);
      expect(categories.width, lessThan(_wide.width / 2));
    });

    uiTest('35, 36 · a long name stays readable and money is never truncated', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pumpAt(
        tester,
        AnalyticsSection.expenses,
        grants: _d2(_ccr),
        size: _narrow,
      );
      final top = (await readyOf(c)).view.topExpenseCategories! as TopNGrouped;

      final label = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('analytics-top-expenses')),
          matching: find.byKey(RankedBarChart.labelKey(0)),
        ),
      );
      expect(label.data, contains('Kirana'));
      final value = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('analytics-top-expenses')),
          matching: find.byKey(RankedBarChart.valueKey(0)),
        ),
      );
      expect(value.data, MoneyFormatter.standard.format(top.top.first.amount));
      expect(value.overflow, TextOverflow.visible);
      expect(value.maxLines, 1);

      // A summary figure keeps its own size: never shrunk, ellipsised or wrapped
      // (D-286).
      final summary = tester.widget<MoneyText>(
        find.byKey(const Key('analytics-expense-total-value')),
      );
      expect(summary.amount.paise, 9540343);
      expect(
        find.ancestor(
          of: find.byKey(const Key('analytics-expense-total-value')),
          matching: find.byType(FittedBox),
        ),
        findsNothing,
      );
      expectMoneyWholeAndUnshrunk(tester, 'the narrow analytics window');
      expect(tester.takeException(), isNull);
    });

    uiTest('37 · the keyboard reaches and changes the section selector', (
      tester,
    ) async {
      crystalCanopySeptember();
      final c = await pump(tester, grants: _d2(_ccr));

      final label = find.byKey(const Key('analytics-section-revenue'));
      bool focusedOnRevenue() {
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused == null) return false;
        return find
            .descendant(
              of: find.byWidgetPredicate((w) => identical(w, focused.widget)),
              matching: label,
            )
            .evaluate()
            .isNotEmpty;
      }

      var reached = false;
      for (var i = 0; i < 30 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        reached = focusedOnRevenue();
      }
      expect(reached, isTrue, reason: 'Tab never reached the Revenue segment');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.read(analyticsSectionProvider), AnalyticsSection.revenue);
      expect(find.byKey(const Key('analytics-revenue')), findsOneWidget);
    });

    uiTest('38 · a hovered row reads its exact prepared figure', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      final c = await pumpAt(tester, AnalyticsSection.revenue);
      final mix = (await readyOf(c)).view.topRevenueCategories! as TopNGrouped;

      final row = find.descendant(
        of: find.byKey(const Key('analytics-revenue-mix')),
        matching: find.byKey(RankedBarChart.rowKey(1)),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(row));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.descendant(
            of: find.byKey(const Key('analytics-revenue-mix')),
            matching: find.byKey(ChartReadout.findKey),
          ),
          matching: find.text(
            MoneyFormatter.standard.format(mix.top[1].amount),
          ),
        ),
        findsOneWidget,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // What a row means — Slice 8's meaning, now the one shared adapter (Slice 9)
  // ═══════════════════════════════════════════════════════════════════════════

  group('what a row means', () {
    uiTest('every ranked row maps to its line, and Others to nothing', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      moreCategories();
      final c = await pumpAt(tester, AnalyticsSection.expenses);
      final ready = await readyOf(c);
      final view = ready.view;
      final targets = DashboardDrillTargets.of(
        ready,
        c.read(principalProvider),
      );
      final anchor = PnlDrillAnchor.dashboard(
        viewerUserId: _me,
        scope: view.scope,
        range: ready.pair.current,
      );

      final revenue = DashboardDrillTargets.ranked(
        view.topRevenueCategories!,
        targets.revenueCategory,
      );
      expect(
        revenue.first,
        DashboardDrillLevel(
          PnlRevenueDocumentsAt(
            anchor,
            businessUnitId: _ccr,
            revenueCategoryId: '$_ccr-restaurant',
          ),
        ),
      );

      final grouped =
          view.topExpenseCategories! as TopNGrouped<ExpenseHierarchyLine>;
      final categories = DashboardDrillTargets.ranked(
        grouped,
        targets.expenseCategory,
      );
      expect(grouped.others, isNotNull, reason: 'six lines: a real Others');
      expect(categories.length, grouped.top.length + 1);
      expect(categories.last, isNull, reason: 'Others opens nothing');
      final first = grouped.top.first.line;
      expect(
        categories.first,
        DashboardDrillLevel(
          PnlExpenseDocumentsAt(
            anchor,
            businessUnitId: first.businessUnitId,
            departmentId: first.departmentId!,
            sectionId: first.sectionId!,
            categoryId: first.categoryId!,
          ),
        ),
      );

      final departments = DashboardDrillTargets.ranked(
        view.departmentSpending!,
        targets.department,
      );
      expect(departments.whereType<DashboardDrillLevel>(), isNotEmpty);
      for (final target in departments.whereType<DashboardDrillLevel>()) {
        expect(target.location, isA<PnlExpenseSectionsAt>());
      }

      final split = view.propertyComparison! as PropertyComparisonReady;
      expect(
        [for (final p in split.properties) targets.property(p.businessUnitId)],
        [
          DashboardPnlHandoff(
            scope: const PnlUnitScope(_ccr),
            range: ready.pair.current,
          ),
          DashboardPnlHandoff(
            scope: const PnlUnitScope(_hki),
            range: ready.pair.current,
          ),
        ],
      );
      expect(
        DashboardDrillTargets.ranked<ExpenseHierarchyLine>(
          const TopNRefused(TopNRefusal.doesNotReconcile),
          targets.expenseCategory,
        ),
        isEmpty,
      );
    });
  });

  group('periods', () {
    uiTest('a period the properties disagree about is refused, not guessed', (
      tester,
    ) async {
      crystalCanopySeptember();
      hotelKrishnaSeptember();
      await pumpAt(tester, AnalyticsSection.revenue, instant: _disagreeing);

      expect(find.byKey(const Key('dashboard-periods-differ')), findsOneWidget);
      expect(find.byKey(const Key('analytics-body')), findsNothing);
      expect(find.textContaining('Use Custom'), findsOneWidget);
    });
  });
}
