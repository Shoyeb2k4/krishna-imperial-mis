/// The Windows P&L surface, rendered through the real provider chain (Phase 5 Slice 8).
///
/// What is real: the page, its providers, the master graph and business-day rules read from
/// SQLite, the canonical reporting cache, `ReportingSync`, `MarkerCoverage`,
/// `CachedReportingSource`, the local reporting engine and `Pnl.compute`.
///
/// What is substituted, and only this: the remote reporting transport and the instant the
/// surface treats as "now". A test never hands the widget a figure: every paisa is
/// synchronised into the cache and read back by the engine.
///
/// The page is rendered beside a 240-pixel strip standing in for the desktop sidebar, at the
/// three Windows sizes the other desktop surfaces are tested at.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/core/formatting/money_formatter.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/profit_and_loss_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/test_session.dart';
import '../support/ui_harness.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _me = 'user-me';

const _laptop = Size(1366, 768);
const _narrow = Size(1024, 700);
const _wide = Size(1920, 1080);

/// Saturday 19 September 2026, 21:00 UTC: 02:30 IST on the 20th. Crystal Canopy's 05:00
/// cut-off keeps it on the 19th; Hotel Krishna's midnight cut-off puts it on the 20th.
final _instant = DateTime.utc(2026, 9, 19, 21);

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
  final askedUnits = <Set<String>>[];
  int snapshots = 0;

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> snapshot({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
    List<int> financialYears = const [],
    ReportingPageCursor after = const ReportingPageCursor.start(),
    int pageDocuments = ReportingPageCursor.defaultPageDocuments,
  }) async {
    askedUnits.add(businessUnitIds.toSet());
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
      'server_time': '2026-09-19T20:30:00.000Z',
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
      'server_time': '2026-09-19T20:31:00.000Z',
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

void main() {
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
      (_ccr, 'kirana', 'Kirana & Pulses'),
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

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<CapabilityGrant>? grants,
    Size size = _laptop,
    bool withGateway = true,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(
            () => StubSession(
              readySession(
                authority: AuthoritySnapshot(
                  userId: _me,
                  orgId: 'test-org',
                  resolvedAt: DateTime.utc(2026, 9, 19),
                  grants: grants ?? _d2(),
                ),
              ),
            ),
          ),
          reportingClockProvider.overrideWithValue(() => _instant),
          if (withGateway) reportingGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(width: 240),
                Expanded(
                  child: ProfitAndLossPage(shellKind: AppShellKind.desktop),
                ),
              ],
            ),
          ),
        ),
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
      tester.element(find.byType(ProfitAndLossPage)),
    );
  }

  Money amountAt(WidgetTester tester, String key) =>
      tester.widget<MoneyText>(find.byKey(Key(key))).amount;

  String textAt(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key))).data!;

  Future<void> selectCustom(
    ProviderContainer container,
    WidgetTester tester,
    BusinessDate from,
    BusinessDate to,
  ) async {
    container.read(pnlSelectionProvider.notifier).selectCustom(from, to);
    await tester.pumpAndSettle();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  group('a computed report', () {
    uiTest('a profit shows the headline, a two-decimal margin and its basis', (
      tester,
    ) async {
      gateway
        ..revenue.add(_sale(_ccr, '2026-09-10', gross: 12364200, tax: 588771))
        ..expense.add(_cost(_ccr, '2026-09-11', 9420343));
      await pump(tester);

      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
      expect(amountAt(tester, 'pnl-gross').paise, 12364200);
      expect(amountAt(tester, 'pnl-gst').paise, 588771);
      expect(amountAt(tester, 'pnl-net').paise, 11775429);
      expect(amountAt(tester, 'pnl-expenses').paise, 9420343);
      expect(amountAt(tester, 'pnl-operating-result').paise, 2355086);
      expect(textAt(tester, 'pnl-operating-label'), 'Operating Profit');
      expect(textAt(tester, 'pnl-margin'), '20.00%');
      // Indian digit grouping, through the one formatter the figure is displayed with.
      final formatter = tester
          .widget<MoneyText>(find.byKey(const Key('pnl-gross')))
          .formatter;
      expect(
        formatter.format(amountAt(tester, 'pnl-gross')),
        contains('1,23,642'),
      );
      expect(find.byKey(const Key('pnl-basis')), findsOneWidget);
      expect(
        textAt(tester, 'pnl-freshness-synchronised'),
        contains('20 Sep 2026, 02:00'),
      );
    });

    uiTest('category lines reconcile exactly with the headline totals', (
      tester,
    ) async {
      gateway
        ..revenue.addAll([
          _sale(_ccr, '2026-06-10', gross: 10000000, tax: 476190),
          _sale(
            _ccr,
            '2026-06-11',
            gross: 870000,
            tax: 41429,
            category: 'nandbhog',
          ),
          _sale(
            _hki,
            '2026-06-12',
            gross: 4034300,
            tax: 0,
            category: 'banquet',
          ),
        ])
        ..expense.addAll([
          _cost(_ccr, '2026-06-10', 4500000),
          _cost(_hki, '2026-06-15', 3000000, category: 'electricity'),
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
      expect(find.text('Crystal Canopy Rooftop · No GST'), findsNothing);
      expect(find.text('Hotel Krishna Imperial · No GST'), findsOneWidget);

      var gross = 0;
      var tax = 0;
      var net = 0;
      for (final line in [
        '$_ccr-$_ccr-restaurant',
        '$_ccr-$_ccr-nandbhog',
        '$_hki-$_hki-banquet',
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
          amountAt(tester, 'pnl-exp-$_ccr-$_ccr-kirana-amount').paise +
          amountAt(tester, 'pnl-exp-$_hki-$_hki-electricity-amount').paise;
      expect(expenses, amountAt(tester, 'pnl-expenses').paise);
      expect(amountAt(tester, 'pnl-exp-total-amount').paise, expenses);
      expect(gross, 14904300);
      expect(expenses, 7500000);
    });

    uiTest('a loss is labelled Operating Loss and keeps its sign', (
      tester,
    ) async {
      gateway
        ..revenue.add(_sale(_ccr, '2026-09-10', gross: 105000, tax: 5000))
        ..expense.add(_cost(_ccr, '2026-09-10', 150000));
      await pump(tester);

      expect(textAt(tester, 'pnl-operating-label'), 'Operating Loss');
      expect(amountAt(tester, 'pnl-operating-result').paise, -50000);
      expect(textAt(tester, 'pnl-margin'), '-50.00%');
    });

    uiTest('a period with no trade is a genuine zero, and the margin is N/A', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
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
          CapabilityGrant(Capability.reportsView, businessUnitId: _ccr),
          CapabilityGrant(Capability.revenueView, businessUnitId: _ccr),
          CapabilityGrant(Capability.expenseViewOwn, businessUnitId: _ccr),
        ],
      );
      expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
      expect(find.byKey(const Key('pnl-statement')), findsNothing);
      expect(find.byKey(const Key('pnl-scope-bar')), findsNothing);
      expect(gateway.askedUnits, isEmpty);
    });

    uiTest('one property\'s authority offers it alone, and a direct read of '
        'another scope is refused on screen', (tester) async {
      gateway.revenue.addAll([
        _sale(_ccr, '2026-09-10', gross: 105000, tax: 5000),
        _sale(_hki, '2026-09-10', gross: 999000, tax: 0, category: 'banquet'),
      ]);
      final container = await pump(tester, grants: _d2(_ccr));

      expect(find.byKey(const Key('pnl-scope-$_ccr')), findsOneWidget);
      expect(find.byKey(const Key('pnl-scope-$_hki')), findsNothing);
      expect(find.byKey(const Key('pnl-scope-consolidated')), findsNothing);
      expect(amountAt(tester, 'pnl-gross').paise, 105000);
      expect(gateway.askedUnits.every((u) => !u.contains(_hki)), isTrue);

      container
          .read(pnlSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(_hki));
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

      container
          .read(pnlSelectionProvider.notifier)
          .selectPreset(RelativePreset.today);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-preset-unavailable')), findsOneWidget);
      expect(find.textContaining('Use Custom'), findsOneWidget);

      // One property has one business date, so Today is available for it.
      await tester.tap(find.byKey(const Key('pnl-scope-$_ccr')));
      await tester.pumpAndSettle();
      expect(chip('today').onSelected, isNotNull);
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
    });

    uiTest('custom dates: unreadable input and a reversed range are refused', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('pnl-preset-custom')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('pnl-custom-from')), 'soon');
      await tester.enterText(
        find.byKey(const Key('pnl-custom-to')),
        '2026-09-01',
      );
      await tester.tap(find.byKey(const Key('pnl-custom-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-custom-error')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('pnl-custom-from')),
        '2026-09-19',
      );
      await tester.tap(find.byKey(const Key('pnl-custom-apply')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-invalid-range')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('older history', () {
    uiTest('not downloaded is offered for download, and then computes', (
      tester,
    ) async {
      gateway.revenue.add(_sale(_ccr, '2023-06-10', gross: 210000, tax: 10000));
      final container = await pump(tester);
      await selectCustom(
        container,
        tester,
        BusinessDate.of(2023, 6, 1),
        BusinessDate.of(2023, 6, 30),
      );

      expect(find.byKey(const Key('pnl-not-downloaded')), findsOneWidget);
      expect(find.byKey(const Key('pnl-statement')), findsNothing);
      await tester.tap(find.byKey(const Key('pnl-download')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
      expect(amountAt(tester, 'pnl-gross').paise, 210000);
    });

    uiTest('downloading required history is shown while it runs', (
      tester,
    ) async {
      gateway.revenue.add(_sale(_ccr, '2023-06-10', gross: 210000, tax: 10000));
      final container = await pump(tester);
      await selectCustom(
        container,
        tester,
        BusinessDate.of(2023, 6, 1),
        BusinessDate.of(2023, 6, 30),
      );

      gateway.gate = Completer<void>();
      await tester.tap(find.byKey(const Key('pnl-download')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byKey(const Key('pnl-downloading')), findsOneWidget);

      gateway.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
    });

    uiTest(
      'a failed download says a connection is required, and shows no figure',
      (tester) async {
        gateway.revenue.add(
          _sale(_ccr, '2023-06-10', gross: 210000, tax: 10000),
        );
        final container = await pump(tester);
        await selectCustom(
          container,
          tester,
          BusinessDate.of(2023, 6, 1),
          BusinessDate.of(2023, 6, 30),
        );

        gateway.snapshotUnreachable = RemoteFailure.offline;
        await tester.tap(find.byKey(const Key('pnl-download')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pnl-download-failed')), findsOneWidget);
        expect(find.textContaining('connection is required'), findsOneWidget);
        expect(find.byKey(const Key('pnl-statement')), findsNothing);
      },
    );

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
        ..revenue.add(_sale(_ccr, '2026-09-10', gross: 105000, tax: 5000))
        ..gate = Completer<void>();
      await pump(tester, settle: false);
      expect(find.byKey(const Key('pnl-synchronising')), findsOneWidget);

      gateway.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
    });

    uiTest('an unreachable server leaves the complete report readable', (
      tester,
    ) async {
      gateway.revenue.add(_sale(_ccr, '2026-09-10', gross: 105000, tax: 5000));
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
          _sale(_ccr, '2026-09-10', gross: 105000, tax: 5000),
        );
        await pump(tester);
        gateway
          ..revenue.add(_sale(_ccr, '2026-09-12', gross: 21000, tax: 1000))
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
      for (final (unit, snapshot) in const [(_ccr, 'run-a'), (_hki, 'run-b')]) {
        await cache.applySnapshot(
          ownerUserId: _me,
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
      final container = await pump(tester, withGateway: false);
      expect(find.byKey(const Key('pnl-freshness-none')), findsOneWidget);

      container
          .read(pnlSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(_ccr));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('pnl-freshness-synchronised')),
        findsOneWidget,
      );
    });

    for (final (missing, key) in const [
      (ReportingDataset.revenue, 'pnl-revenue-unavailable'),
      (ReportingDataset.expense, 'pnl-expense-unavailable'),
    ]) {
      uiTest(
        'a missing ${missing.wireName} side is named, never shown as zero',
        (tester) async {
          await ReportingCache(db).applySnapshot(
            ownerUserId: _me,
            orgId: 'test-org',
            snapshotId: 'one-side',
            serverConfirmedAt: DateTime.utc(2026, 9, 19, 20),
            businessUnitIds: const {_ccr},
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
              .selectScope(const PnlUnitScope(_ccr));
          await tester.pumpAndSettle();
          expect(find.byKey(Key(key)), findsOneWidget);
          expect(find.byKey(const Key('pnl-statement')), findsNothing);
        },
      );
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('layout at Windows sizes, in every state', () {
    final states = <String, Future<void> Function(WidgetTester, Size)>{
      'profit with categories': (tester, size) async {
        gateway
          ..revenue.addAll([
            _sale(_ccr, '2026-09-10', gross: 1236420000, tax: 58877143),
            _sale(
              _hki,
              '2026-09-11',
              gross: 403430000,
              tax: 0,
              category: 'banquet',
            ),
          ])
          ..expense.addAll([
            _cost(_ccr, '2026-09-10', 450000000),
            _cost(_hki, '2026-09-11', 300000000, category: 'electricity'),
          ]);
        await pump(tester, size: size);
        expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
      },
      'loss': (tester, size) async {
        gateway
          ..revenue.add(_sale(_ccr, '2026-09-10', gross: 105000, tax: 5000))
          ..expense.add(_cost(_ccr, '2026-09-10', 987654321));
        await pump(tester, size: size);
        expect(find.text('Operating Loss'), findsOneWidget);
      },
      'not authorised': (tester, size) async {
        await pump(tester, size: size, grants: const []);
        expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
      },
      'preset unavailable': (tester, size) async {
        final container = await pump(tester, size: size);
        container
            .read(pnlSelectionProvider.notifier)
            .selectPreset(RelativePreset.today);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pnl-preset-unavailable')), findsOneWidget);
      },
      'not downloaded': (tester, size) async {
        final container = await pump(tester, size: size);
        await selectCustom(
          container,
          tester,
          BusinessDate.of(2023, 6, 1),
          BusinessDate.of(2023, 6, 30),
        );
        expect(find.byKey(const Key('pnl-not-downloaded')), findsOneWidget);
      },
      'download failed': (tester, size) async {
        final container = await pump(tester, size: size);
        await selectCustom(
          container,
          tester,
          BusinessDate.of(2023, 6, 1),
          BusinessDate.of(2023, 6, 30),
        );
        gateway.snapshotUnreachable = RemoteFailure.offline;
        await tester.tap(find.byKey(const Key('pnl-download')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pnl-download-failed')), findsOneWidget);
      },
      'offline and readable': (tester, size) async {
        gateway.revenue.add(
          _sale(_ccr, '2026-09-10', gross: 105000, tax: 5000),
        );
        await pump(tester, size: size);
        gateway
          ..snapshotUnreachable = RemoteFailure.offline
          ..newerUnreachable = RemoteFailure.offline;
        await tester.tap(find.byKey(const Key('pnl-refresh')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pnl-offline')), findsOneWidget);
      },
      'custom range editor': (tester, size) async {
        await pump(tester, size: size);
        await tester.tap(find.byKey(const Key('pnl-preset-custom')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pnl-custom-from')), findsOneWidget);
      },
    };

    for (final (label, size) in const [
      ('laptop', _laptop),
      ('narrow window', _narrow),
      ('maximised', _wide),
    ]) {
      for (final entry in states.entries) {
        uiTest('${entry.key} at $label renders without overflow', (
          tester,
        ) async {
          await entry.value(tester, size);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  test('the formatter in use groups digits the Indian way', () {
    expect(
      MoneyFormatter.standard.format(Money.fromPaise(123642000)),
      contains('12,36,420'),
    );
  });
}
