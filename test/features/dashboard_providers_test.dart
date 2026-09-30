/// The dashboard's application state, through the real provider chain (Phase 6 Slice 4).
///
/// Written **before** the providers existed. Everything real below is real: the
/// session-derived principal, `PnlAuthority`, the master graph and business-day rules read
/// from SQLite, the canonical reporting cache, `ReportingSync`, `MarkerCoverage`,
/// `CachedReportingSource`, `LocalReportingEngine`, `Pnl.compute` and the Slice 3
/// `DashboardEngine`. Substituted, and only this: the remote reporting transport and the
/// instant the surface treats as "now".
///
/// **There is no second authorization model here.** A dashboard scope qualifies on exactly
/// the D2 intersection `PnlAuthority` already decides for the P&L (D-164, D-187), and the
/// scope options are literally the same provider.
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
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_comparison.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/test_session.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _me = 'user-me';
const _other = 'user-other';

/// 21:00 UTC on Saturday 19 September 2026 is 02:30 IST on the 20th. Crystal Canopy's
/// 05:00 cut-off keeps it on the 19th; Hotel Krishna's midnight cut-off puts it on the
/// 20th — so the two properties disagree, which is what a consolidated preset must refuse.
final _instant = DateTime.utc(2026, 9, 19, 21);

/// The same instant with both properties on 05:00, so they agree.
final _agreeingInstant = DateTime.utc(2026, 9, 19, 12);

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

  /// Completes the moment a snapshot request is entered, so a test can be sure a run
  /// has reached the gate before it moves anything underneath it.
  final reachedSnapshot = Completer<void>();
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
    if (!reachedSnapshot.isCompleted) reachedSnapshot.complete();
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

AuthoritySnapshot _authority(
  Iterable<CapabilityGrant> grants, {
  String userId = _me,
}) => AuthoritySnapshot(
  userId: userId,
  orgId: 'test-org',
  resolvedAt: DateTime.utc(2026, 9, 19),
  grants: grants,
);

/// The qualifying intersection, for one property or (with no unit) unscoped.
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
    DateTime? instant,
    bool withGateway = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionProvider.overrideWith(
          () =>
              session ?? _Session(readySession(authority: _authority(grants))),
        ),
        reportingClockProvider.overrideWithValue(() => instant ?? _instant),
        if (withGateway) reportingGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<DashboardState> state(ProviderContainer c) =>
      c.read(dashboardViewProvider.future);

  Future<void> refresh(ProviderContainer c) =>
      c.read(dashboardSyncProvider.notifier).refresh();

  // ── 1 … 7, 18: what qualifies ─────────────────────────────────────────────

  group(
    'a dashboard scope qualifies on the P&L intersection and nothing else',
    () {
      test(
        '1 · one property: that property alone, and it is selected',
        () async {
          final c = containerFor(_d2(_ccr));
          final options = await c.read(pnlScopeOptionsProvider.future);
          expect(options.units.map((u) => u.id), [_ccr]);
          expect(options.consolidatedAllowed, isFalse);

          // Exactly one permitted property is selected automatically.
          final s = await state(c);
          expect(s, isA<DashboardReady>());
          expect((s as DashboardReady).scope, const PnlUnitScope(_ccr));
        },
      );

      test(
        '2 · two scoped properties: both offered, consolidated is not',
        () async {
          final c = containerFor([..._d2(_ccr), ..._d2(_hki)]);
          final options = await c.read(pnlScopeOptionsProvider.future);
          expect(options.units.map((u) => u.id), [_ccr, _hki]);
          expect(
            options.consolidatedAllowed,
            isFalse,
            reason:
                'two scoped grants do not add up to unscoped authority (D-187)',
          );
        },
      );

      test(
        '3 · unscoped authority offers consolidated, and it is the default',
        () async {
          final c = containerFor(_d2());
          final options = await c.read(pnlScopeOptionsProvider.future);
          expect(options.consolidatedAllowed, isTrue);
          expect(options.defaultScope, const PnlConsolidatedScope());
        },
      );

      for (final (label, grants) in <(String, List<CapabilityGrant>)>[
        (
          '4 · expense.view.own never qualifies',
          [
            CapabilityGrant(Capability.reportsView, businessUnitId: _ccr),
            CapabilityGrant(Capability.revenueView, businessUnitId: _ccr),
            CapabilityGrant(Capability.expenseViewOwn, businessUnitId: _ccr),
          ],
        ),
        (
          '5 · reports.view alone does not qualify',
          [CapabilityGrant(Capability.reportsView, businessUnitId: _ccr)],
        ),
        (
          '6 · revenue.view alone does not qualify',
          [
            CapabilityGrant(Capability.revenueView, businessUnitId: _ccr),
            CapabilityGrant(Capability.expenseViewAll, businessUnitId: _ccr),
          ],
        ),
        (
          '7 · expense.view.all alone does not qualify',
          [
            CapabilityGrant(Capability.reportsView, businessUnitId: _ccr),
            CapabilityGrant(Capability.expenseViewAll, businessUnitId: _ccr),
          ],
        ),
        (
          '18 · Owner Accounts capabilities alone grant nothing here',
          [
            CapabilityGrant(Capability.ownerSettlementView),
            CapabilityGrant(Capability.ownerLedgerView),
            CapabilityGrant(Capability.ownerMastersManage),
            CapabilityGrant(Capability.mastersView, businessUnitId: _ccr),
          ],
        ),
      ]) {
        test(label, () async {
          final c = containerFor(grants);
          final options = await c.read(pnlScopeOptionsProvider.future);
          expect(options.units, isEmpty);
          expect(options.consolidatedAllowed, isFalse);
          expect(await state(c), isA<DashboardNotAuthorised>());
        });
      }

      test(
        '12 · a principal with no qualifying scope receives no financial result',
        () async {
          final c = containerFor(const [
            CapabilityGrant(Capability.mastersView, businessUnitId: _ccr),
          ]);
          final s = await state(c);
          expect(s, isA<DashboardNotAuthorised>());

          // Nothing that could be mistaken for a figure, an empty chart or a property name.
          final presentation = dashboardPresentation(
            state: AsyncData<DashboardState>(s),
            sync: c.read(dashboardSyncProvider),
            principal: c.read(sessionProvider).principal,
          );
          expect(presentation, isA<DashboardUnavailable>());
          expect(
            (presentation as DashboardUnavailable).reason,
            DashboardUnavailableReason.notAuthorised,
          );
        },
      );

      test(
        'a scope nobody may read is refused without reading the cache',
        () async {
          final c = containerFor(_d2(_ccr));
          // Chosen directly, bypassing the selector.
          c
              .read(dashboardSelectionProvider.notifier)
              .selectScope(const PnlUnitScope(_hki));
          expect(await state(c), isA<DashboardNotAuthorised>());
        },
      );
    },
  );

  // ── 13, 14: periods come from the planner ─────────────────────────────────

  group('periods come from the Slice 2 planner, not from provider arithmetic', () {
    setUp(() async {
      gateway
        ..revenue.add(_sale(_ccr, '2026-09-18', gross: 1050000, tax: 50000))
        ..expense.add(_cost(_ccr, '2026-09-18', 200000));
    });

    test('13 · the resolved pair is exactly DashboardPeriods\' answer', () async {
      final c = containerFor(_d2(_ccr));
      await refresh(c);
      final s = await state(c) as DashboardReady;

      // Crystal Canopy's own business date at the fixed instant is 19 September.
      final expected =
          DashboardPeriods.forToday(
                DashboardPeriodKind.monthToDate,
                BusinessDate.of(2026, 9, 19),
              )
              as DashboardPairResolved;
      expect(s.pair, expected.pair);
      expect(s.pair.current.from, BusinessDate.of(2026, 9, 1));
      expect(s.pair.current.to, BusinessDate.of(2026, 9, 19));
      expect(s.pair.comparison.from, BusinessDate.of(2026, 8, 1));
      expect(s.pair.comparison.to, BusinessDate.of(2026, 8, 19));
    });

    test('each kind resolves to the planner\'s own pair', () async {
      final c = containerFor(_d2(_ccr));
      await refresh(c);
      for (final kind in const [
        DashboardPeriodKind.today,
        DashboardPeriodKind.weekToDate,
        DashboardPeriodKind.monthToDate,
        DashboardPeriodKind.financialYearToDate,
      ]) {
        c.read(dashboardSelectionProvider.notifier).selectPeriod(kind);
        final s = await state(c) as DashboardReady;
        final expected =
            DashboardPeriods.forToday(kind, BusinessDate.of(2026, 9, 19))
                as DashboardPairResolved;
        expect(s.pair, expected.pair, reason: kind.name);
      }
    });

    test(
      '14 · a consolidated preset the properties disagree about is refused',
      () async {
        // At the fixed instant Crystal Canopy is on the 19th and Hotel Krishna on the 20th.
        final c = containerFor(_d2());
        final s = await state(c);
        expect(s, isA<DashboardPeriodUnavailable>());
        expect(
          (s as DashboardPeriodUnavailable).refusal,
          DashboardPairRefusal.currentRangesDiffer,
        );

        // And it is not a zero report.
        final presentation = dashboardPresentation(
          state: AsyncData<DashboardState>(s),
          sync: c.read(dashboardSyncProvider),
          principal: c.read(sessionProvider).principal,
        );
        expect(
          (presentation as DashboardUnavailable).reason,
          DashboardUnavailableReason.periodUnavailable,
        );
      },
    );

    test(
      '14 · availability says which presets a consolidated reader may use',
      () async {
        final c = containerFor(_d2());
        final availability = await c.read(
          dashboardPeriodAvailabilityProvider.future,
        );
        // The properties disagree on every relative period at this instant.
        expect(availability[DashboardPeriodKind.today], isFalse);
        expect(availability[DashboardPeriodKind.monthToDate], isFalse);
        // Custom needs no calendar and is always offerable.
        expect(availability[DashboardPeriodKind.custom], isTrue);
      },
    );

    test('when the properties agree, a consolidated preset resolves', () async {
      final c = containerFor(_d2(), instant: _agreeingInstant);
      final availability = await c.read(
        dashboardPeriodAvailabilityProvider.future,
      );
      expect(availability[DashboardPeriodKind.monthToDate], isTrue);
      expect(await state(c), isA<DashboardReady>());
    });

    test(
      'a custom range whose end precedes its start is refused, never swapped',
      () async {
        final c = containerFor(_d2(_ccr));
        c
            .read(dashboardSelectionProvider.notifier)
            .selectCustom(
              BusinessDate.of(2026, 9, 20),
              BusinessDate.of(2026, 9, 1),
            );
        final s = await state(c);
        expect(s, isA<DashboardPeriodUnavailable>());
        expect(
          (s as DashboardPeriodUnavailable).refusal,
          DashboardPairRefusal.endBeforeStart,
        );
      },
    );
  });

  // ── the engine is the one path ────────────────────────────────────────────

  group('the dashboard is assembled by the Slice 3 engine', () {
    setUp(() async {
      gateway
        // September, Crystal Canopy: net 10,000.00 and 6,000.00; costs 2,000.00 + 1,500.00.
        ..revenue.add(_sale(_ccr, '2026-09-03', gross: 1050000, tax: 50000))
        ..revenue.add(_sale(_ccr, '2026-09-09', gross: 630000, tax: 30000))
        ..expense.add(_cost(_ccr, '2026-09-04', 200000))
        ..expense.add(_cost(_ccr, '2026-09-09', 150000))
        // August comparator, 1–19: net 8,000.00, cost 2,000.00.
        ..revenue.add(_sale(_ccr, '2026-08-05', gross: 840000, tax: 40000))
        ..expense.add(_cost(_ccr, '2026-08-06', 200000));
    });

    test(
      'the headline, the comparison and a trend all come from one view',
      () async {
        final c = containerFor(_d2(_ccr));
        await refresh(c);
        final s = await state(c) as DashboardReady;

        expect(s.view.resultOrNull!.netSales, Money.fromPaise(1600000));
        expect(s.view.resultOrNull!.operatingProfit, Money.fromPaise(1250000));
        expect(s.view.previous.resultOrNull!.netSales, Money.fromPaise(800000));
        expect(s.view.comparison.netSales, isA<MoneyComparisonAvailable>());
        // Month to date offers a daily Net Sales trend and a ranking.
        expect(s.view.trends, isNotEmpty);
        expect(s.view.trends.single.grain, TrendGrain.daily);
        expect(s.view.trends.single.measure, TrendMeasure.netSales);
        expect(s.view.ranking, isA<DailyRanked>());
        expect(s.view.topExpenseCategories, isNotNull);
        expect(s.view.topRevenueCategories, isNotNull);
      },
    );

    test('a financial year to date trends monthly, and ranks no day', () async {
      final c = containerFor(_d2(_ccr));
      await refresh(c);
      c
          .read(dashboardSelectionProvider.notifier)
          .selectPeriod(DashboardPeriodKind.financialYearToDate);
      final s = await state(c) as DashboardReady;
      expect(
        s.view.trends.map((t) => (t.measure, t.grain)),
        containsAll(const [
          (TrendMeasure.netSales, TrendGrain.monthly),
          (TrendMeasure.expenses, TrendGrain.monthly),
          (TrendMeasure.operatingProfit, TrendGrain.monthly),
        ]),
      );
      expect(
        s.view.ranking,
        isNull,
        reason: 'no daily grain, so no best or worst day (D-255)',
      );
    });

    test('16 · missing data is unavailable, never zero', () async {
      // Nothing synchronised.
      final c = containerFor(_d2(_ccr), withGateway: false);
      final s = await state(c) as DashboardReady;
      expect(s.view.isComputed, isFalse);
      expect(s.view.refusalOrNull, PnlRefusal.bothSidesUnavailable);
      expect(s.view.revenueCoverage, ReportingCoverage.notDownloaded);

      final presentation = dashboardPresentation(
        state: AsyncData<DashboardState>(s),
        sync: c.read(dashboardSyncProvider),
        principal: c.read(sessionProvider).principal,
      );
      expect(presentation, isA<DashboardUnavailable>());
      expect(
        (presentation as DashboardUnavailable).reason,
        DashboardUnavailableReason.requiredDataUnavailable,
      );
    });
  });

  // ── 17: freshness ─────────────────────────────────────────────────────────

  group('17 · freshness is the engine\'s answer, passed through', () {
    setUp(() {
      gateway
        ..revenue.add(_sale(_ccr, '2026-09-03', gross: 1050000, tax: 50000))
        ..expense.add(_cost(_ccr, '2026-09-04', 200000));
    });

    test(
      'one synchronisation gives the view\'s own claim, unchanged',
      () async {
        final c = containerFor(_d2(_ccr));
        await refresh(c);
        final s = await state(c) as DashboardReady;
        expect(s.view.freshness, isNotNull);
        expect(s.freshness, same(s.view.freshness));
        expect(
          s.freshness!.evidence.serverConfirmedAt,
          gateway.serverTime.toUtc(),
        );
      },
    );

    test('no coherent claim from the engine means no claim here', () async {
      final c = containerFor(_d2(_ccr));
      // A financial year to date whose comparator reaches into the previous year, which
      // this device has never certified: the engine can name no one snapshot.
      await refresh(c);
      c
          .read(dashboardSelectionProvider.notifier)
          .selectPeriod(DashboardPeriodKind.financialYearToDate);
      final s = await state(c) as DashboardReady;
      expect(s.view.freshness, isNull);
      expect(
        s.freshness,
        isNull,
        reason: 'the provider must not invent a claim the engine withheld',
      );
    });

    test(
      'a confirmed head check marks the claim without moving a figure',
      () async {
        final c = containerFor(_d2(_ccr));
        await refresh(c);
        final before = await state(c) as DashboardReady;
        expect(before.freshness!.state, ReportingFreshnessState.synchronised);
        final netBefore = before.view.resultOrNull!.netSales;

        // The server moves, and the fetch that would bring it down cannot reach it. The head
        // check still answers, so the dashboard learns it is behind without learning what by.
        gateway.revenue.add(
          _sale(_ccr, '2026-09-05', gross: 2100000, tax: 100000),
        );
        gateway.snapshotUnreachable = RemoteFailure.offline;
        await refresh(c);
        expect(c.read(dashboardSyncProvider).serverHasNewer, isTrue);

        final after = await state(c) as DashboardReady;
        expect(after.freshness!.state, ReportingFreshnessState.serverHasNewer);
        expect(
          after.view.resultOrNull!.netSales,
          netBefore,
          reason: 'the figures stay the last complete canonical snapshot',
        );
      },
    );
  });

  // ── 8 … 11: session and authority isolation ───────────────────────────────

  group('authority identity is part of dashboard identity', () {
    setUp(() {
      gateway
        ..revenue.add(_sale(_ccr, '2026-09-03', gross: 1050000, tax: 50000))
        ..revenue.add(_sale(_hki, '2026-09-03', gross: 4200000, tax: 200000))
        ..expense.add(_cost(_ccr, '2026-09-04', 200000));
    });

    test('8 · user A\'s dashboard is never shown to user B', () async {
      final session = _Session(readySession(authority: _authority(_d2())));
      final c = containerFor(
        const [],
        session: session,
        instant: _agreeingInstant,
      );
      await refresh(c);
      final mine = await state(c) as DashboardReady;
      expect(mine.view.isComputed, isTrue);
      expect(
        mine.authorityKey,
        PnlAuthority.readKey(c.read(sessionProvider).principal),
      );

      // B signs in. A's dashboard is still the last value the provider holds.
      session.become(
        readySession(authority: _authority(_d2(), userId: _other)),
      );
      final principalB = c.read(sessionProvider).principal;
      expect(
        dashboardShownTo(AsyncData<DashboardState>(mine), principalB),
        isNull,
        reason:
            'A\'s figures must not be shown to B while B\'s first read runs',
      );
      expect(
        dashboardPresentation(
          state: AsyncData<DashboardState>(mine),
          sync: c.read(dashboardSyncProvider),
          principal: principalB,
        ),
        isA<DashboardLoading>(),
      );
    });

    test(
      '9 · a confirmed capability revocation invalidates the dashboard',
      () async {
        final session = _Session(readySession(authority: _authority(_d2())));
        final c = containerFor(
          const [],
          session: session,
          instant: _agreeingInstant,
        );
        await refresh(c);
        final before = await state(c) as DashboardReady;
        expect(before.view.isComputed, isTrue);

        // The same person loses revenue.view. Everything else is unchanged.
        session.become(
          readySession(
            authority: _authority(const [
              CapabilityGrant(Capability.reportsView),
              CapabilityGrant(Capability.expenseViewAll),
            ]),
          ),
        );
        final principal = c.read(sessionProvider).principal;
        expect(
          dashboardShownTo(AsyncData<DashboardState>(before), principal),
          isNull,
          reason:
              'the dashboard belonged to an authority that is no longer current',
        );
        expect(await state(c), isA<DashboardNotAuthorised>());
      },
    );

    test(
      '10 · a selected property whose authority is lost cannot stay active',
      () async {
        final session = _Session(
          readySession(authority: _authority([..._d2(_ccr), ..._d2(_hki)])),
        );
        final c = containerFor(
          const [],
          session: session,
          instant: _agreeingInstant,
        );
        c
            .read(dashboardSelectionProvider.notifier)
            .selectScope(const PnlUnitScope(_hki));
        await refresh(c);
        expect(
          (await state(c) as DashboardReady).scope,
          const PnlUnitScope(_hki),
        );

        // Hotel Krishna's authority is withdrawn; Crystal Canopy's remains.
        session.become(readySession(authority: _authority(_d2(_ccr))));
        final s = await state(c);
        expect(s, isA<DashboardReady>());
        expect(
          (s as DashboardReady).scope,
          const PnlUnitScope(_ccr),
          reason: 'the selection resolves to a still-permitted scope',
        );
        expect(
          s.view.scope.businessUnitIds,
          {_ccr},
          reason: 'and the revoked property is not read',
        );
      },
    );

    test(
      '10 · losing the only permitted property leaves no scope at all',
      () async {
        final session = _Session(
          readySession(authority: _authority(_d2(_ccr))),
        );
        final c = containerFor(const [], session: session);
        await refresh(c);
        expect(await state(c), isA<DashboardReady>());

        session.become(
          readySession(
            authority: _authority(const [
              CapabilityGrant(Capability.mastersView, businessUnitId: _ccr),
            ]),
          ),
        );
        expect(await state(c), isA<DashboardNotAuthorised>());
      },
    );

    test('11 · while the next authority\'s assembly is in flight, the previous '
        'authority\'s dashboard is not the visible one', () async {
      // The real mechanism, with the real lock: a dashboard is several cache reads taken
      // inside one CanonicalCacheLock span, so holding that lock keeps an assembly
      // genuinely in flight. Meanwhile the provider retains its previous value — which is
      // exactly the situation D-231 recorded, and exactly what must not be shown.
      final session = _Session(readySession(authority: _authority(_d2())));
      final c = containerFor(
        const [],
        session: session,
        instant: _agreeingInstant,
      );
      await refresh(c);
      final underA = await state(c) as DashboardReady;
      expect(underA.view.isComputed, isTrue);
      final keyA = underA.authorityKey;

      // Hold the lock, so the next assembly cannot finish.
      final gate = Completer<void>();
      final holding = c.read(canonicalCacheLockProvider).run(() => gate.future);
      addTearDown(() async {
        if (!gate.isCompleted) gate.complete();
        await holding;
      });

      // The same person, now qualifying for Crystal Canopy only: a different authority,
      // still authorised, so the assembly really does reach the lock.
      session.become(readySession(authority: _authority(_d2(_ccr))));
      final principalB = c.read(sessionProvider).principal;
      expect(PnlAuthority.readKey(principalB), isNot(keyA));

      c.read(dashboardViewProvider); // starts the new assembly
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final held = c.read(dashboardViewProvider);
      expect(
        held.isLoading,
        isTrue,
        reason: 'the new assembly is still running',
      );
      expect(
        held.value,
        isNotNull,
        reason:
            'the provider does retain the previous value — that is the hazard',
      );
      expect(held.value!.authorityKey, keyA);
      expect(
        dashboardShownTo(held, principalB),
        isNull,
        reason:
            'the previous authority\'s dashboard must not be the visible one while the '
            'current authority\'s assembly is still in flight',
      );

      gate.complete();
      await holding;
      final settled = await state(c);
      expect(settled.authorityKey, PnlAuthority.readKey(principalB));
      expect(dashboardShownTo(AsyncData(settled), principalB), isNotNull);
    });
  });

  // ── the selection's own rules ─────────────────────────────────────────────

  group('what a selection survives', () {
    test('the same person and authority keep their scope and period', () async {
      final session = _Session(readySession(authority: _authority(_d2())));
      final c = containerFor(
        const [],
        session: session,
        instant: _agreeingInstant,
      );
      c.read(dashboardSelectionProvider.notifier)
        ..selectScope(const PnlUnitScope(_hki))
        ..selectPeriod(DashboardPeriodKind.weekToDate);
      final before = c.read(dashboardSelectionProvider);

      // A refresh that changed nothing: a new session state, the same authority.
      session.become(readySession(authority: _authority(_d2())));
      final after = c.read(dashboardSelectionProvider);
      expect(after.scope, before.scope);
      expect(after.period, before.period);
    });

    test('a different person starts from a clean selection', () async {
      final session = _Session(readySession(authority: _authority(_d2())));
      final c = containerFor(
        const [],
        session: session,
        instant: _agreeingInstant,
      );
      c
          .read(dashboardSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(_hki));
      session.become(
        readySession(authority: _authority(_d2(), userId: _other)),
      );
      expect(
        c.read(dashboardSelectionProvider).scope,
        isNull,
        reason: 'the next person does not inherit the last person\'s property',
      );
    });

    test('a capability change starts from a clean selection', () async {
      final session = _Session(
        readySession(authority: _authority([..._d2(_ccr), ..._d2(_hki)])),
      );
      final c = containerFor(const [], session: session);
      c
          .read(dashboardSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(_hki));
      session.become(readySession(authority: _authority(_d2(_ccr))));
      expect(c.read(dashboardSelectionProvider).scope, isNull);
    });
  });

  // ── 15: refresh failure ───────────────────────────────────────────────────

  group('15 · a failed refresh keeps the dashboard that was already complete', () {
    setUp(() {
      gateway
        ..revenue.add(_sale(_ccr, '2026-09-03', gross: 1050000, tax: 50000))
        ..expense.add(_cost(_ccr, '2026-09-04', 200000));
    });

    test('the figures stay, and the failure is reported separately', () async {
      final c = containerFor(_d2(_ccr));
      await refresh(c);
      final complete = await state(c) as DashboardReady;
      expect(complete.view.isComputed, isTrue);

      gateway.snapshotUnreachable = RemoteFailure.offline;
      await refresh(c);
      final sync = c.read(dashboardSyncProvider);
      expect(sync.phase, DashboardSyncPhase.failed);

      final after = await state(c) as DashboardReady;
      expect(
        after.view.resultOrNull!.netSales,
        complete.view.resultOrNull!.netSales,
        reason:
            'a failed run writes nothing, so the figures do not move (D-048)',
      );

      final presentation = dashboardPresentation(
        state: AsyncData<DashboardState>(after),
        sync: sync,
        principal: c.read(sessionProvider).principal,
      );
      expect(presentation, isA<DashboardAvailable>());
      final available = presentation as DashboardAvailable;
      expect(available.dashboard.view.isComputed, isTrue);
      expect(available.refreshFailure, isNotNull);
    });

    test(
      'a failed refresh with no complete dashboard is unavailable, not zero',
      () async {
        gateway.snapshotUnreachable = RemoteFailure.offline;
        final c = containerFor(_d2(_ccr));
        await refresh(c);
        final s = await state(c) as DashboardReady;
        expect(s.view.isComputed, isFalse);

        final presentation = dashboardPresentation(
          state: AsyncData<DashboardState>(s),
          sync: c.read(dashboardSyncProvider),
          principal: c.read(sessionProvider).principal,
        );
        expect(presentation, isA<DashboardUnavailable>());
        expect(
          (presentation as DashboardUnavailable).reason,
          DashboardUnavailableReason.requiredDataUnavailable,
        );
      },
    );

    test('a superseded run is neither a success nor a failure', () async {
      // D-240's shape at the provider: a run belongs to the authority that started it.
      final session = _Session(readySession(authority: _authority(_d2(_ccr))));
      final c = containerFor(const [], session: session);
      final waiting = Completer<void>();
      gateway.gate = waiting;

      final running = refresh(c);
      // Wait until the run is genuinely inside the fetch before moving anything.
      await gateway.reachedSnapshot.future;
      expect(c.read(dashboardSyncProvider).isRunning, isTrue);

      // The same person, now qualifying for nothing: a different authority.
      session.become(
        readySession(
          authority: _authority(const [
            CapabilityGrant(Capability.mastersView, businessUnitId: _ccr),
          ]),
        ),
      );
      waiting.complete();
      await running;

      final phase = c.read(dashboardSyncProvider).phase;
      expect(
        phase,
        isNot(DashboardSyncPhase.failed),
        reason: "a superseded run is not this authority's failure",
      );
      expect(
        phase,
        isNot(DashboardSyncPhase.succeeded),
        reason:
            'nor its success: it asked about a scope this authority has not',
      );
      expect(
        c.read(dashboardSyncProvider).isRunning,
        isFalse,
        reason: 'and it leaves no phantom run blocking the next one',
      );
    });
  });

  // ── loading ───────────────────────────────────────────────────────────────

  test('a dashboard that has not resolved yet is loading, not empty', () {
    final c = containerFor(_d2(_ccr));
    expect(
      dashboardPresentation(
        state: const AsyncLoading<DashboardState>(),
        sync: c.read(dashboardSyncProvider),
        principal: c.read(sessionProvider).principal,
      ),
      isA<DashboardLoading>(),
    );
  });
}
