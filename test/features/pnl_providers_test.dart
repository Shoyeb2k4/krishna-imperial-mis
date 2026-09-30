/// The Windows P&L surface's state, through the real provider chain (Phase 5 Slice 8).
///
/// What is real: the session-derived principal, the master graph and business-day rules
/// read from SQLite, the canonical reporting cache, `ReportingSync`, `MarkerCoverage`,
/// `CachedReportingSource`, the local reporting engine and `Pnl.compute`.
///
/// What is substituted, and only this: the remote reporting transport (a gateway that
/// answers from rows the test holds, or fails the way a network does) and the instant the
/// screen treats as "now". No figure is handed to the providers by a test — every paisa
/// arrives through a synchronisation into the cache and is read back by the engine.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/test_session.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _me = 'user-me';

/// 21:00 UTC on Saturday 19 September 2026 is 02:30 IST on Sunday the 20th. Crystal
/// Canopy's 05:00 cut-off keeps it on the 19th; the midnight cut-off configured for Hotel
/// Krishna below puts it on the 20th.
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

  /// When set, the snapshot waits here before answering.
  Completer<void>? gate;

  final askedUnits = <Set<String>>[];
  int snapshots = 0;
  DateTime serverTime = DateTime.utc(2026, 9, 19, 20, 30);

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

AuthoritySnapshot _authority(Iterable<CapabilityGrant> grants) =>
    AuthoritySnapshot(
      userId: _me,
      orgId: 'test-org',
      resolvedAt: DateTime.utc(2026, 9, 19),
      grants: grants,
    );

List<CapabilityGrant> _d2([String? unit]) => [
  CapabilityGrant(Capability.reportsView, businessUnitId: unit),
  CapabilityGrant(Capability.revenueView, businessUnitId: unit),
  CapabilityGrant(Capability.expenseViewAll, businessUnitId: unit),
];

class _Session extends StubSession {
  _Session(super.initial);
  void become(SessionState next) => state = next;
}

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late _Gateway gateway;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = _Gateway();
    for (final (id, code, name, cutoff) in const [
      (_ccr, 'CCR', 'Crystal Canopy Rooftop', '05:00'),
      (_hki, 'HKI', 'Hotel Krishna Imperial', '00:00'),
    ]) {
      await db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES (?, 'test-org', ?, ?, 'hotel', 'Asia/Kolkata', ?, 1, 1, "
        "'2026-06-01T00:00:00.000Z')",
        [id, code, name, cutoff],
      );
    }
  });
  tearDown(() => db.close());

  ProviderContainer containerFor(
    Iterable<CapabilityGrant> grants, {
    _Session? session,
    bool withGateway = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionProvider.overrideWith(
          () =>
              session ?? _Session(readySession(authority: _authority(grants))),
        ),
        reportingClockProvider.overrideWithValue(() => _instant),
        if (withGateway) reportingGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<PnlView> view(ProviderContainer c) => c.read(pnlViewProvider.future);

  PnlSelectionController selection(ProviderContainer c) =>
      c.read(pnlSelectionProvider.notifier);

  PnlSyncController sync(ProviderContainer c) =>
      c.read(pnlSyncProvider.notifier);

  PnlResult computed(PnlView v) {
    expect(v, isA<PnlReportView>());
    final outcome = (v as PnlReportView).envelope.outcome;
    expect(outcome, isA<PnlComputed>(), reason: '$outcome');
    return (outcome as PnlComputed).result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  group('which scopes are offered, and what a direct read may obtain', () {
    test(
      'unscoped P&L authority offers both properties and consolidated',
      () async {
        final c = containerFor(_d2());
        final options = await c.read(pnlScopeOptionsProvider.future);
        expect(options.units.map((u) => u.id), [_ccr, _hki]);
        expect(options.consolidatedAllowed, isTrue);
        expect(options.defaultScope, isA<PnlConsolidatedScope>());
      },
    );

    test(
      'complete authority for one property offers only that property',
      () async {
        final c = containerFor(_d2(_ccr));
        final options = await c.read(pnlScopeOptionsProvider.future);
        expect(options.units.map((u) => u.id), [_ccr]);
        expect(options.consolidatedAllowed, isFalse);
        expect((options.defaultScope! as PnlUnitScope).businessUnitId, _ccr);
      },
    );

    test(
      'property membership without the D2 intersection offers nothing',
      () async {
        final c = containerFor([
          const CapabilityGrant(Capability.reportsView, businessUnitId: _ccr),
          const CapabilityGrant(Capability.revenueView, businessUnitId: _ccr),
          const CapabilityGrant(
            Capability.expenseViewOwn,
            businessUnitId: _ccr,
          ),
          const CapabilityGrant(Capability.mastersView, businessUnitId: _ccr),
        ]);
        final options = await c.read(pnlScopeOptionsProvider.future);
        expect(options.units, isEmpty);
        expect(options.consolidatedAllowed, isFalse);
        expect(await view(c), isA<PnlNotAuthorised>());
      },
    );

    test(
      'a directly selected unauthorised property is refused before any read',
      () async {
        gateway.revenue.add(
          _sale(_hki, '2026-09-10', gross: 105000, tax: 5000),
        );
        final c = containerFor(_d2(_ccr));
        selection(c).selectScope(const PnlUnitScope(_hki));
        await sync(c).refresh();

        expect(await view(c), isA<PnlNotAuthorised>());
        // Nothing about Hotel Krishna was even requested.
        expect(
          gateway.askedUnits.every((units) => !units.contains(_hki)),
          isTrue,
        );
      },
    );

    test(
      'a directly selected consolidated scope is refused without unscoped authority',
      () async {
        final c = containerFor([..._d2(_ccr), ..._d2(_hki)]);
        selection(c).selectScope(const PnlConsolidatedScope());
        expect(await view(c), isA<PnlNotAuthorised>());
      },
    );

    test(
      'the permitted property still reports for the same principal',
      () async {
        gateway.revenue.add(
          _sale(_ccr, '2026-09-10', gross: 105000, tax: 5000),
        );
        final c = containerFor(_d2(_ccr));
        selection(c).selectPreset(RelativePreset.thisMonth);
        await sync(c).refresh();
        expect(computed(await view(c)).grossSales.paise, 105000);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('relative presets, under each property\'s own business date', () {
    test('a single property uses its own business date', () async {
      final c = containerFor(_d2());
      selection(c)
        ..selectScope(const PnlUnitScope(_ccr))
        ..selectPreset(RelativePreset.today);
      var v = await view(c) as PnlReportView;
      expect(v.range.from, BusinessDate.of(2026, 9, 19));

      selection(c).selectScope(const PnlUnitScope(_hki));
      v = await view(c) as PnlReportView;
      expect(v.range.from, BusinessDate.of(2026, 9, 20));
    });

    test(
      'consolidated Today is refused when the properties are on different days',
      () async {
        final c = containerFor(_d2());
        selection(c)
          ..selectScope(const PnlConsolidatedScope())
          ..selectPreset(RelativePreset.today);
        final v = await view(c);
        expect(v, isA<PnlPresetUnavailable>());
        expect(
          (v as PnlPresetUnavailable).resolution,
          isA<PresetRangesDiffer>(),
        );
        expect(
          await c.read(pnlPresetAvailabilityProvider.future),
          containsPair(RelativePreset.today, false),
        );
      },
    );

    test(
      'consolidated This Month is allowed when both resolve to the same month',
      () async {
        final c = containerFor(_d2());
        selection(c)
          ..selectScope(const PnlConsolidatedScope())
          ..selectPreset(RelativePreset.thisMonth);
        final v = await view(c) as PnlReportView;
        expect(v.range.from, BusinessDate.of(2026, 9, 1));
        expect(v.range.to, BusinessDate.of(2026, 9, 30));
        expect(
          await c.read(pnlPresetAvailabilityProvider.future),
          containsPair(RelativePreset.thisMonth, true),
        );
      },
    );

    test(
      'Custom needs no property calendar, even when the properties disagree',
      () async {
        final c = containerFor(_d2());
        selection(c)
          ..selectScope(const PnlConsolidatedScope())
          ..selectCustom(
            BusinessDate.of(2026, 9, 1),
            BusinessDate.of(2026, 9, 19),
          );
        final v = await view(c) as PnlReportView;
        expect(v.range.to, BusinessDate.of(2026, 9, 19));
      },
    );

    test(
      'a custom range ending before it starts is refused, not swapped',
      () async {
        final c = containerFor(_d2());
        selection(c).selectCustom(
          BusinessDate.of(2026, 9, 19),
          BusinessDate.of(2026, 9, 1),
        );
        expect(await view(c), isA<PnlInvalidRange>());
      },
    );

    test(
      'a property whose rules are unreadable refuses a preset for it',
      () async {
        await db.customStatement(
          "UPDATE business_units SET business_day_cutoff = 'soon' WHERE id = ?",
          [_hki],
        );
        final c = containerFor(_d2());
        selection(c)
          ..selectScope(const PnlUnitScope(_hki))
          ..selectPreset(RelativePreset.today);
        final v = await view(c);
        expect(v, isA<PnlPresetUnavailable>());
        expect(
          (v as PnlPresetUnavailable).resolution,
          isA<PresetCalendarUnavailable>(),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('a computed report', () {
    test(
      'figures come from the synchronised cache, and the breakdown reconciles',
      () async {
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
        final c = containerFor(_d2());
        selection(c).selectCustom(
          BusinessDate.of(2026, 6, 1),
          BusinessDate.of(2026, 6, 30),
        );
        await sync(c).refresh();

        final v = await view(c) as PnlReportView;
        final result = computed(v);
        expect(result.grossSales.paise, 14904300);
        expect(result.gst.paise, 517619);
        expect(result.netSales.paise, 14386681);
        expect(result.expenses.paise, 7500000);
        expect(result.operatingProfit.paise, 6886681);
        expect(result.revenueByCategory, hasLength(3));
        expect(result.expenseByHierarchy, hasLength(2));
        expect(result.breakdownReconciles, isTrue);
        expect(
          v.envelope.freshness!.state,
          ReportingFreshnessState.synchronised,
        );
        expect(
          v.envelope.freshness!.synchronisedAt,
          DateTime.utc(2026, 9, 19, 20, 30),
        );
        expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.succeeded);
      },
    );

    test(
      'a synchronised period with no trade is a genuine zero, margin N/A',
      () async {
        final c = containerFor(_d2());
        selection(c).selectPreset(RelativePreset.thisMonth);
        await sync(c).refresh();
        final result = computed(await view(c));
        expect(result.grossSales.paise, 0);
        expect(result.expenses.paise, 0);
        expect(result.margin.displayTwoDecimals, 'N/A');
      },
    );

    test(
      'before any synchronisation the report is not downloaded, never ₹0',
      () async {
        final c = containerFor(_d2(), withGateway: false);
        selection(c).selectPreset(RelativePreset.thisMonth);
        final v = await view(c) as PnlReportView;
        expect(v.envelope.outcome, isA<PnlRefused>());
        expect(v.envelope.revenueCoverage, ReportingCoverage.notDownloaded);
        expect(v.envelope.expenseCoverage, ReportingCoverage.notDownloaded);
        await sync(c).refresh();
        expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.unavailable);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('older financial years, downloaded on demand', () {
    test(
      'an older year is not downloaded by a refresh, and is offered for download',
      () async {
        gateway.revenue.add(
          _sale(_ccr, '2023-06-10', gross: 210000, tax: 10000),
        );
        final c = containerFor(_d2());
        selection(c).selectCustom(
          BusinessDate.of(2023, 6, 1),
          BusinessDate.of(2023, 6, 30),
        );
        await sync(c).refresh();

        final v = await view(c) as PnlReportView;
        expect(v.envelope.outcome, isA<PnlRefused>());
        expect(v.envelope.revenueCoverage, ReportingCoverage.notDownloaded);
        expect(v.olderYears.map((y) => y.openingYear), [2023]);
        expect(v.offersDownload, isTrue);

        await sync(c).download();
        final after = await view(c);
        expect(computed(after).grossSales.paise, 210000);

        final markers = await ReportingCache(db).markersFor(_me);
        expect(
          markers
              .where((m) => m.financialYear == 2023)
              .every((m) => m.onDemand),
          isTrue,
        );
      },
    );

    test(
      'a range across several missing years computes only when all are covered',
      () async {
        gateway.revenue.addAll([
          _sale(_ccr, '2023-03-20', gross: 100000, tax: 0), // FY 2022
          _sale(_ccr, '2023-12-20', gross: 200000, tax: 0), // FY 2023
          _sale(_ccr, '2024-04-05', gross: 300000, tax: 0), // FY 2024
        ]);
        final c = containerFor(_d2(_ccr));
        selection(c).selectCustom(
          BusinessDate.of(2023, 3, 15),
          BusinessDate.of(2024, 4, 10),
        );
        final before = await view(c) as PnlReportView;
        expect(before.neededYears.map((y) => y.openingYear), [
          2022,
          2023,
          2024,
        ]);
        expect(before.olderYears.map((y) => y.openingYear), [2022, 2023, 2024]);

        await sync(c).download();
        expect(computed(await view(c)).grossSales.paise, 600000);
        final years = {
          for (final m in await ReportingCache(db).markersFor(_me))
            m.financialYear,
        };
        expect(years, containsAll([2022, 2023, 2024]));
      },
    );

    test('a failed download stays not downloaded and says it failed', () async {
      gateway
        ..revenue.add(_sale(_ccr, '2023-06-10', gross: 210000, tax: 10000))
        ..snapshotUnreachable = RemoteFailure.offline;
      final c = containerFor(_d2());
      selection(
        c,
      ).selectCustom(BusinessDate.of(2023, 6, 1), BusinessDate.of(2023, 6, 30));
      await sync(c).download();

      final status = c.read(pnlSyncProvider);
      expect(status.phase, PnlSyncPhase.failed);
      expect(status.lastAction, PnlSyncAction.download);
      expect(status.failure, RemoteFailure.offline);
      final v = await view(c) as PnlReportView;
      expect(v.envelope.outcome, isA<PnlRefused>());
      expect(v.envelope.revenueCoverage, ReportingCoverage.notDownloaded);
    });

    test('a downloaded older year stays readable offline', () async {
      gateway.revenue.add(_sale(_ccr, '2023-06-10', gross: 210000, tax: 10000));
      final c = containerFor(_d2());
      selection(
        c,
      ).selectCustom(BusinessDate.of(2023, 6, 1), BusinessDate.of(2023, 6, 30));
      await sync(c).download();
      gateway
        ..snapshotUnreachable = RemoteFailure.offline
        ..newerUnreachable = RemoteFailure.offline;
      await sync(c).refresh();
      expect(computed(await view(c)).grossSales.paise, 210000);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('offline and freshness', () {
    test(
      'an unreachable server leaves a complete report readable and dated',
      () async {
        gateway.revenue.add(
          _sale(_ccr, '2026-09-10', gross: 105000, tax: 5000),
        );
        final c = containerFor(_d2());
        selection(c).selectPreset(RelativePreset.thisMonth);
        await sync(c).refresh();
        final first = await view(c) as PnlReportView;

        gateway
          ..snapshotUnreachable = RemoteFailure.offline
          ..newerUnreachable = RemoteFailure.offline;
        await sync(c).refresh();

        final status = c.read(pnlSyncProvider);
        expect(status.phase, PnlSyncPhase.failed);
        expect(status.failure, RemoteFailure.offline);
        final after = await view(c) as PnlReportView;
        expect(computed(after).grossSales.paise, 105000);
        expect(
          after.envelope.freshness!.evidence,
          first.envelope.freshness!.evidence,
        );
        expect(
          after.envelope.freshness!.state,
          ReportingFreshnessState.synchronised,
        );
      },
    );

    test(
      'a confirmed newer server marks the report, without moving a figure',
      () async {
        gateway.revenue.add(
          _sale(_ccr, '2026-09-10', gross: 105000, tax: 5000),
        );
        final c = containerFor(_d2());
        selection(c).selectPreset(RelativePreset.thisMonth);
        await sync(c).refresh();

        gateway
          ..revenue.add(_sale(_ccr, '2026-09-12', gross: 21000, tax: 1000))
          ..snapshotUnreachable = RemoteFailure.serverUnreachable;
        await sync(c).refresh();

        final v = await view(c) as PnlReportView;
        expect(computed(v).grossSales.paise, 105000);
        expect(
          v.envelope.freshness!.state,
          ReportingFreshnessState.serverHasNewer,
        );

        // A successful synchronisation clears it and moves the figure once.
        gateway.snapshotUnreachable = null;
        await sync(c).refresh();
        final after = await view(c) as PnlReportView;
        expect(computed(after).grossSales.paise, 126000);
        expect(
          after.envelope.freshness!.state,
          ReportingFreshnessState.synchronised,
        );
      },
    );

    test('an unreachable head check claims nothing about the server', () async {
      gateway.revenue.add(_sale(_ccr, '2026-09-10', gross: 105000, tax: 5000));
      final c = containerFor(_d2());
      selection(c).selectPreset(RelativePreset.thisMonth);
      await sync(c).refresh();
      gateway
        ..snapshotUnreachable = RemoteFailure.offline
        ..newerUnreachable = RemoteFailure.offline;
      await sync(c).refresh();
      final v = await view(c) as PnlReportView;
      expect(v.envelope.freshness!.state, ReportingFreshnessState.synchronised);
      expect(c.read(pnlSyncProvider).serverHasNewer, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  test(
    'a report read never interleaves with a synchronisation writing the cache',
    () async {
      gateway.revenue.add(_sale(_ccr, '2026-09-10', gross: 105000, tax: 5000));
      final c = containerFor(_d2());
      selection(c).selectPreset(RelativePreset.thisMonth);
      await sync(c).refresh();
      await view(c);

      gateway
        ..revenue.add(_sale(_ccr, '2026-09-11', gross: 21000, tax: 1000))
        ..gate = Completer<void>();
      final running = sync(c).refresh();
      // Let the refresh reach the gateway and hold the lock.
      for (var i = 0; i < 20 && gateway.askedUnits.length < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      c.invalidate(pnlViewProvider);
      var read = false;
      final pending = view(c).then((v) {
        read = true;
        return v;
      });
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        read,
        isFalse,
        reason: 'a read must wait for the snapshot to land',
      );

      gateway.gate!.complete();
      await running;
      final v = await pending;
      expect(computed(v).grossSales.paise, 126000);
    },
  );

  test(
    'a user switch resets the selection and the synchronisation status',
    () async {
      final session = _Session(readySession(authority: _authority(_d2())));
      final c = containerFor(_d2(), session: session);
      selection(c).selectPreset(RelativePreset.lastMonth);
      await sync(c).refresh();
      expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.succeeded);

      session.become(
        readySession(
          authority: AuthoritySnapshot(
            userId: 'user-next',
            orgId: 'test-org',
            resolvedAt: DateTime.utc(2026, 9, 19),
            grants: _d2(_ccr),
          ),
        ),
      );
      expect(c.read(pnlSyncProvider).phase, PnlSyncPhase.idle);
      expect(c.read(pnlSelectionProvider).period, isA<PnlPresetPeriod>());
      expect(
        (c.read(pnlSelectionProvider).period as PnlPresetPeriod).preset,
        RelativePreset.thisMonth,
      );
      expect(c.read(pnlSelectionProvider).scope, isNull);
    },
  );
}
