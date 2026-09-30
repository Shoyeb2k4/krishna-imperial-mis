/// The Owner Settlement surface, through the real provider chain (Phase 5 OA-3).
///
/// What is real: the preview provider, the preview service, the owner-keyed repository
/// filled by the real `OwnerSettlementSync`, the `LocalReportingEngine`, `Pnl.compute`,
/// `OwnerSettlement.compute`, the master graph read from SQLite, and — for the refresh
/// states — the real `OwnerSettlementRefresher` and `ReportingSync`.
///
/// What is substituted, and only this: the reporting-facts port (a source that sums
/// fixture rows) and the two remote transports. The widget itself is never handed a
/// figure by a test.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/sync/canonical_cache_lock.dart';
import 'package:krishna_mis/app/app.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/owner_settlement_refresh.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_preview.dart';
import 'package:krishna_mis/features/owner_settlement/presentation/owner_settlement_providers.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import '../support/cache_principal.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/owner_settlement/presentation/owner_settlement_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/test_session.dart';
import '../support/ui_harness.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';

typedef _Row = ({String unit, BusinessDate date, int net, int expense});

/// April 10,00,000 · May 20,00,000 · June 30,00,001 paise of Operating Profit.
final _rows = <_Row>[
  (
    unit: _ccr,
    date: BusinessDate.of(2026, 4, 10),
    net: 800000,
    expense: 200000,
  ),
  (
    unit: _hki,
    date: BusinessDate.of(2026, 4, 20),
    net: 600000,
    expense: 200000,
  ),
  (unit: _ccr, date: BusinessDate.of(2026, 5, 10), net: 1500000, expense: 0),
  (unit: _hki, date: BusinessDate.of(2026, 5, 20), net: 500000, expense: 0),
  (unit: _ccr, date: BusinessDate.of(2026, 6, 10), net: 2000001, expense: 0),
  (
    unit: _hki,
    date: BusinessDate.of(2026, 6, 20),
    net: 1500000,
    expense: 500000,
  ),
];

final class _Facts implements ReportingFactsSource {
  _Facts(this.rows, {this.coverage = const {}});
  final List<_Row> rows;
  final Map<String, ReportingCoverage> coverage;

  @override
  Future<UnitReportingFacts> factsFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingScope scope,
  }) async {
    final state = coverage[businessUnitId] ?? ReportingCoverage.complete;
    if (state != ReportingCoverage.complete) {
      return UnitReportingFacts.uncovered(
        businessUnitId: businessUnitId,
        coverage: state,
      );
    }
    var net = 0;
    var expense = 0;
    for (final row in rows) {
      if (row.unit == businessUnitId && range.contains(row.date)) {
        net += row.net;
        expense += row.expense;
      }
    }
    return UnitReportingFacts(
      businessUnitId: businessUnitId,
      revenueCoverage: ReportingCoverage.complete,
      expenseCoverage: ReportingCoverage.complete,
      revenue: RevenueTotals(
        gross: Money.fromPaise(net),
        tax: Money.zero,
        net: Money.fromPaise(net),
        contributions: 1,
      ),
      expenses: ExpenseTotals(
        amount: Money.fromPaise(expense),
        contributions: 1,
      ),
    );
  }

  @override
  Future<ReportingScopeFacts> factsForScope({
    required ReportRange range,
    required ReportingScope scope,
  }) async => ReportingScopeFacts(
    units: [
      for (final unit in scope.ordered)
        await factsFor(businessUnitId: unit, range: range, scope: scope),
    ],
    snapshot: ReportingSnapshotEvidence(
      snapshotId: 'rep-snap',
      serverConfirmedAt: DateTime.utc(2026, 7, 1, 8),
    ),
  );
}

class _OwnerSource implements OwnerSnapshotSource {
  _OwnerSource(this.answer);
  Future<RemoteOutcome<Map<String, dynamic>>> Function() answer;
  @override
  Future<RemoteOutcome<Map<String, dynamic>>> fetchSettlementSnapshot() =>
      answer();
}

final class _Reporting extends ReportingGateway {
  // Auto-refresh off: this client is built inside the widget-test zone, where GoTrue's
  // periodic token timer would outlive the test. It never makes a call either way —
  // `snapshot` is overridden.
  _Reporting()
    : super(
        SupabaseClient(
          'http://localhost',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  @override
  Future<RemoteOutcome<Map<String, dynamic>>> snapshot({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
    List<int> financialYears = const [],
    ReportingPageCursor after = const ReportingPageCursor.start(),
    int pageDocuments = ReportingPageCursor.defaultPageDocuments,
  }) async => RemoteOk({
    'snapshot_id': 'rep-1',
    'server_time': '2026-07-01T08:00:00.000Z',
    'units': [
      for (final u in businessUnitIds)
        {'business_unit_id': u, 'reporting_authorised': true},
    ],
    'revenue': const <Map<String, dynamic>>[],
    'expense': const <Map<String, dynamic>>[],
  });
}

Map<String, dynamic> _ownerSnapshot({
  String? start = '2026-04-01',
  List<Map<String, dynamic>> movements = const [],
}) => {
  'snapshot_id': 'own-snap',
  'server_time': '2026-07-01T09:00:00.000Z',
  'settlement_authorised': true,
  'ownership_start_date': start,
  'movements': movements,
  'owners': [
    for (final (id, name) in const [
      ('owner-a', 'Partner Alpha'),
      ('owner-b', 'Partner Beta'),
    ])
      {
        'id': id,
        'org_id': 'org-1',
        'code': id.toUpperCase(),
        'display_name': name,
        'active': true,
        'archived_at': null,
        'row_version': 1,
        'change_seq': 1,
      },
  ],
  'ownership_shares': [
    for (final o in const ['owner-a', 'owner-b'])
      {
        'id': 'share-$o',
        'org_id': 'org-1',
        'owner_id': o,
        'share_basis_points': 5000,
        'effective_from': '2026-04-01',
        'effective_to': null,
        'note': null,
        'row_version': 1,
        'change_seq': 1,
      },
  ],
  'family_members': const [],
};

Map<String, dynamic> _withdrawal(String owner, int amount) => {
  'id': 'w-$owner-$amount',
  'org_id': 'org-1',
  'business_unit_id': _hki,
  'owner_id': owner,
  'txn_number': 'KI-OWN-$owner-$amount',
  'financial_year': '26-27',
  'business_date': '2026-06-12',
  'business_date_source': 'derived',
  'pnl_period_key': '2026-06',
  'movement_type': 'withdrawal',
  'direction': 'debit',
  'amount_minor': amount,
  'family_member_id': null,
  'collected_by_family_member_id': null,
  'nc_bill_reference': null,
  'reference_number': null,
  'remarks': null,
  'reason': null,
  'created_by': 'someone',
  'captured_at': '2026-06-12T10:00:00.000Z',
  'row_version': 1,
  'change_seq': 1,
  'voided_at': null,
  'void_reason': null,
};

AuthoritySnapshot _ownerAuthority([String userId = 'owner-user']) =>
    fullAuthority(userId: userId);

AuthoritySnapshot _accountantAuthority() => AuthoritySnapshot(
  userId: 'accountant-user',
  orgId: 'test-org',
  resolvedAt: DateTime.utc(2026, 8, 28),
  grants: [
    for (final c in RoleTemplates.accountant)
      CapabilityGrant(c, businessUnitId: _ccr),
  ],
);

/// A session a test can move between people, as a sign-out and sign-in would.
class _Session extends StubSession {
  _Session(super.initial);
  void become(SessionState next) => state = next;
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;

  Future<void> units() async {
    for (final (id, code, name) in const [
      (_ccr, 'CCR', 'Crystal Canopy Rooftop'),
      (_hki, 'HKI', 'Hotel Krishna Imperial'),
    ]) {
      await db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES (?, 'test-org', ?, ?, 'hotel', 'Asia/Kolkata', '05:00', 1, 1, "
        "'2026-06-01T00:00:00.000Z')",
        [id, code, name],
      );
    }
  }

  Future<void> synchroniseFor(String userId, Map<String, dynamic> body) async {
    final result = await OwnerSettlementSync(
      database: db,
      gateway: _OwnerSource(() async => RemoteOk(body)),
      ownerUserId: userId,
    ).synchronise();
    expect(result, isA<OwnerSettlementSynchronised>());
  }

  /// The page as a phone or the workstation shows it, through the real providers.
  Future<_Session> pump(
    WidgetTester tester, {
    required AuthoritySnapshot authority,
    AppShellKind shell = AppShellKind.desktop,
    Size size = const Size(1366, 768),
    ReportingFactsSource? facts,
    OwnerSettlementRefresher Function()? refresher,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _Session(readySession(authority: authority));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionProvider.overrideWith(() => session),
          currentBusinessDateProvider.overrideWithValue(
            BusinessDate.of(2026, 6, 20),
          ),
          localReportingSourceProvider.overrideWith(
            (ref) async => facts ?? _Facts(_rows),
          ),
          if (refresher != null)
            ownerSettlementRefresherProvider.overrideWith((ref) => refresher()),
        ],
        child: MaterialApp(
          home: Scaffold(body: OwnerSettlementPage(shellKind: shell)),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // A running refresh animates a progress indicator indefinitely, so there is nothing
      // to settle to. Pump the frames that resolve the providers instead.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    return session;
  }

  String textOf(WidgetTester tester, String key) {
    final widget = tester.widget(find.byKey(Key(key)));
    return switch (widget) {
      Text(:final data) => data!,
      MoneyText(:final amount, :final formatter) => formatter.format(amount),
      _ => throw StateError('no text at $key'),
    };
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await units();
  });
  tearDown(() => db.close());

  // ═══════════════════════════════════════════════════════════════════════════
  group('a complete preview', () {
    uiTest('shows the OA-2 result, labelled as a preview', (tester) async {
      await synchroniseFor(
        'owner-user',
        _ownerSnapshot(movements: [_withdrawal('owner-a', 500000)]),
      );
      await pump(tester, authority: _ownerAuthority());

      expect(
        find.byKey(const Key('owner-settlement-preview-banner')),
        findsOneWidget,
      );
      expect(find.textContaining('not a finalized statement'), findsOneWidget);
      expect(find.text('June 2026'), findsOneWidget);

      expect(textOf(tester, 'owner-settlement-op-consolidated'), '₹30,000.01');
      expect(textOf(tester, 'owner-settlement-op-$_ccr'), '₹20,000.01');
      expect(textOf(tester, 'owner-settlement-op-$_hki'), '₹10,000.00');
      expect(find.text('Crystal Canopy Rooftop'), findsOneWidget);
      expect(textOf(tester, 'owner-settlement-remainder'), '₹0.01');

      expect(find.text('Partner Alpha'), findsOneWidget);
      expect(textOf(tester, 'owner-settlement-opening-owner-a'), '₹15,000.00');
      expect(
        textOf(tester, 'owner-settlement-entitlement-owner-a'),
        '₹15,000.00',
      );
      expect(
        textOf(tester, 'owner-settlement-withdrawals-owner-a'),
        '₹5,000.00',
      );
      expect(textOf(tester, 'owner-settlement-nc-owner-a'), '₹0.00');
      expect(textOf(tester, 'owner-settlement-paid-owner-a'), '₹0.00');
      expect(textOf(tester, 'owner-settlement-closing-owner-a'), '₹25,000.00');
      expect(
        textOf(tester, 'owner-settlement-closing-label-owner-a'),
        'Due to owner',
      );
      expect(textOf(tester, 'owner-settlement-closing-owner-b'), '₹30,000.00');
    });

    uiTest(
      'dates each synchronisation separately, and claims no combined time',
      (tester) async {
        await synchroniseFor('owner-user', _ownerSnapshot());
        await pump(tester, authority: _ownerAuthority());

        expect(
          textOf(tester, 'owner-settlement-owner-evidence'),
          'Owner history · synchronised as of 1 Jul 2026, 14:30 IST',
        );
        expect(
          textOf(tester, 'owner-settlement-reporting-evidence'),
          'Profit & loss · synchronised as of 1 Jul 2026, 13:30 IST',
        );
        expect(find.textContaining('No single combined time'), findsOneWidget);
      },
    );

    uiTest('a negative position is recoverable from the owner, in words', (
      tester,
    ) async {
      await synchroniseFor(
        'owner-user',
        _ownerSnapshot(movements: [_withdrawal('owner-b', 4000000)]),
      );
      await pump(tester, authority: _ownerAuthority());

      expect(textOf(tester, 'owner-settlement-closing-owner-b'), '-₹10,000.00');
      expect(
        textOf(tester, 'owner-settlement-closing-label-owner-b'),
        'Recoverable from owner',
        reason: 'never told apart by colour alone (spec section 20)',
      );
    });

    uiTest('a real zero is shown as a computed nil, not a refusal', (
      tester,
    ) async {
      await synchroniseFor('owner-user', _ownerSnapshot());
      await pump(tester, authority: _ownerAuthority(), facts: _Facts(const []));

      expect(textOf(tester, 'owner-settlement-op-consolidated'), '₹0.00');
      expect(textOf(tester, 'owner-settlement-closing-owner-a'), '₹0.00');
      expect(
        textOf(tester, 'owner-settlement-closing-label-owner-a'),
        'Nil — nothing due either way',
      );
      expect(find.byKey(const Key('owner-settlement-remainder')), findsNothing);
    });

    uiTest('the month moves back, and never forward past the current one', (
      tester,
    ) async {
      await synchroniseFor('owner-user', _ownerSnapshot());
      await pump(tester, authority: _ownerAuthority());

      final next = tester.widget<IconButton>(
        find.byKey(const Key('owner-settlement-next-month')),
      );
      expect(next.onPressed, isNull);

      await tester.tap(
        find.byKey(const Key('owner-settlement-previous-month')),
      );
      await tester.pumpAndSettle();
      expect(find.text('May 2026'), findsOneWidget);
      expect(textOf(tester, 'owner-settlement-opening-owner-a'), '₹5,000.00');
      expect(textOf(tester, 'owner-settlement-closing-owner-a'), '₹15,000.00');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('every unavailable state is named, and none is ₹0', () {
    Future<void> expectRefusal(WidgetTester tester, String reason) async {
      expect(
        find.byKey(Key('owner-settlement-unavailable-$reason')),
        findsOneWidget,
      );
      expect(
        find.byType(MoneyText),
        findsNothing,
        reason: 'a missing side is never replaced with ₹0 (D-163)',
      );
      expect(find.byKey(const Key('owner-settlement-statement')), findsNothing);
    }

    uiTest('settlement start date not configured', (tester) async {
      await synchroniseFor('owner-user', _ownerSnapshot(start: null));
      await pump(tester, authority: _ownerAuthority());
      await expectRefusal(tester, 'startDateNotConfigured');
      expect(find.text('Settlement start date not configured'), findsOneWidget);
    });

    uiTest('owner history not downloaded', (tester) async {
      await pump(tester, authority: _ownerAuthority());
      await expectRefusal(tester, 'ownerHistoryNotDownloaded');
    });

    uiTest('reporting data not downloaded', (tester) async {
      await synchroniseFor('owner-user', _ownerSnapshot());
      await pump(
        tester,
        authority: _ownerAuthority(),
        facts: _Facts(_rows, coverage: {_hki: ReportingCoverage.notDownloaded}),
      );
      await expectRefusal(tester, 'reportingNotDownloaded');
    });

    uiTest('before the settlement start date', (tester) async {
      await synchroniseFor('owner-user', _ownerSnapshot(start: '2026-07-01'));
      await pump(tester, authority: _ownerAuthority());
      await expectRefusal(tester, 'beforeStartDate');
    });

    uiTest('not authorised: the Accountant, reaching the page directly', (
      tester,
    ) async {
      // Reached without the navigation entry, as a route or a deep link could. The page
      // itself refuses, because the decision is the service's and not the menu's.
      await synchroniseFor('accountant-user', _ownerSnapshot());
      await pump(tester, authority: _accountantAuthority());
      await expectRefusal(tester, 'notAuthorised');
      expect(find.text('Partner Alpha'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('refresh states', () {
    OwnerSettlementRefresher refresherWith(
      _OwnerSource source,
      String userId,
    ) => OwnerSettlementRefresher(
      lock: CanonicalCacheLock(),
      ownerSync: OwnerSettlementSync(
        database: db,
        gateway: source,
        ownerUserId: userId,
      ),
      reportingSync: ReportingSync(
        cache: ReportingCache(db),
        gateway: _Reporting(),
        ownerUserId: userId,
        orgId: 'test-org',
      ),
      repository: OwnerSettlementRepository(
        db,
        principal: canonicalCachePrincipal(userId),
      ),
    );

    uiTest('synchronising, with nothing yet on the device', (tester) async {
      final pending = Completer<RemoteOutcome<Map<String, dynamic>>>();
      await pump(
        tester,
        authority: _ownerAuthority(),
        refresher: () =>
            refresherWith(_OwnerSource(() => pending.future), 'owner-user'),
        settle: false,
      );
      expect(
        find.byKey(const Key('owner-settlement-synchronising')),
        findsOneWidget,
      );
      expect(find.byType(MoneyText), findsNothing);
      pending.complete(const RemoteUnreachable(RemoteFailure.offline));
      await tester.pumpAndSettle();
    });

    uiTest(
      'a failed pull with nothing on the device is a sync failure, not ₹0',
      (tester) async {
        await pump(
          tester,
          authority: _ownerAuthority(),
          refresher: () => refresherWith(
            _OwnerSource(
              () async => const RemoteUnreachable(RemoteFailure.offline),
            ),
            'owner-user',
          ),
        );
        expect(
          find.byKey(const Key('owner-settlement-sync-failed')),
          findsOneWidget,
        );
        expect(find.byType(MoneyText), findsNothing);
      },
    );

    uiTest('offline but complete: the last synchronised figures, said so', (
      tester,
    ) async {
      await synchroniseFor('owner-user', _ownerSnapshot());
      await pump(
        tester,
        authority: _ownerAuthority(),
        refresher: () => refresherWith(
          _OwnerSource(
            () async => const RemoteUnreachable(RemoteFailure.offline),
          ),
          'owner-user',
        ),
      );
      expect(find.byKey(const Key('owner-settlement-offline')), findsOneWidget);
      expect(
        find.byKey(const Key('owner-settlement-statement')),
        findsOneWidget,
      );
      expect(textOf(tester, 'owner-settlement-closing-owner-a'), '₹30,000.00');
    });

    uiTest('a successful refresh shows the statement without a notice', (
      tester,
    ) async {
      await pump(
        tester,
        authority: _ownerAuthority(),
        refresher: () => refresherWith(
          _OwnerSource(() async => RemoteOk(_ownerSnapshot())),
          'owner-user',
        ),
      );
      expect(
        find.byKey(const Key('owner-settlement-statement')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('owner-settlement-offline')), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('user switch (D-074, D-208)', () {
    uiTest('the next person sees nothing of the previous person owner data', (
      tester,
    ) async {
      await synchroniseFor('owner-user', _ownerSnapshot());
      final session = await pump(tester, authority: _ownerAuthority());
      expect(find.text('Partner Alpha'), findsOneWidget);

      // Another person with the very same authority: their owner-keyed cache is empty.
      session.become(readySession(authority: _ownerAuthority('second-owner')));
      await tester.pumpAndSettle();
      expect(find.text('Partner Alpha'), findsNothing);
      expect(
        find.byKey(
          const Key('owner-settlement-unavailable-ownerHistoryNotDownloaded'),
        ),
        findsOneWidget,
      );

      // And a reader without the capability sees a refusal, not the figures.
      session.become(readySession(authority: _accountantAuthority()));
      await tester.pumpAndSettle();
      expect(find.text('Partner Alpha'), findsNothing);
      expect(
        find.byKey(const Key('owner-settlement-unavailable-notAuthorised')),
        findsOneWidget,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('layout, in every state, at the sizes the app is used at', () {
    for (final (name, size, shell) in const [
      ('laptop', Size(1366, 768), AppShellKind.desktop),
      ('narrow window', Size(1024, 700), AppShellKind.desktop),
      ('maximised', Size(1920, 1080), AppShellKind.desktop),
      ('phone', Size(360, 740), AppShellKind.mobile),
    ]) {
      uiTest('$name: complete, negative and refused without overflow', (
        tester,
      ) async {
        await synchroniseFor(
          'owner-user',
          _ownerSnapshot(movements: [_withdrawal('owner-b', 4000000)]),
        );
        await pump(
          tester,
          authority: _ownerAuthority(),
          size: size,
          shell: shell,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('owner-settlement-statement')),
          findsOneWidget,
        );

        await synchroniseFor('owner-user', _ownerSnapshot(start: null));
        await pump(
          tester,
          authority: _ownerAuthority(),
          size: size,
          shell: shell,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the navigation entry is shown only to owner_settlement.view', () {
    Future<void> pumpApp(
      WidgetTester tester,
      AppShellKind shell,
      AuthoritySnapshot authority,
    ) async {
      await tester.binding.setSurfaceSize(
        shell == AppShellKind.desktop
            ? const Size(1440, 900)
            : const Size(390, 844),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            sessionProvider.overrideWith(
              () => StubSession(readySession(authority: authority)),
            ),
          ],
          child: KrishnaMisApp(shellKind: shell),
        ),
      );
      await tester.pumpAndSettle();
    }

    uiTest('Windows: the Owner bundle sees it in the sidebar', (tester) async {
      await pumpApp(tester, AppShellKind.desktop, _ownerAuthority());
      expect(find.text('Owner Settlement'), findsOneWidget);

      await tester.tap(find.text('Owner Settlement'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-settlement-page')), findsOneWidget);
    });

    uiTest('Windows: the Accountant does not', (tester) async {
      await pumpApp(tester, AppShellKind.desktop, _accountantAuthority());
      expect(find.text('Owner Settlement'), findsNothing);
    });

    uiTest('Android: the Owner bundle finds it under More', (tester) async {
      await pumpApp(tester, AppShellKind.mobile, _ownerAuthority());
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('more-owner-settlement')), findsOneWidget);

      await tester.tap(find.byKey(const Key('more-owner-settlement')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('owner-settlement-page')), findsOneWidget);
    });

    uiTest('Android: the Accountant does not', (tester) async {
      await pumpApp(tester, AppShellKind.mobile, _accountantAuthority());
      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('more-owner-settlement')), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group(
    'the same person, the same authority, a new session state (Slice 11)',
    () {
      for (final (name, freshness) in const [
        ('an unreachable refresh leaves it stale', AuthorityFreshness.stale),
        ('a confirmed refresh changes nothing', AuthorityFreshness.confirmed),
      ]) {
        uiTest('$name: the chosen month stays', (tester) async {
          await synchroniseFor('owner-user', _ownerSnapshot());
          final session = await pump(tester, authority: _ownerAuthority());
          final container = ProviderScope.containerOf(
            tester.element(find.byType(OwnerSettlementPage)),
          );
          final current = container.read(settlementMonthProvider);
          await tester.tap(
            find.byKey(const Key('owner-settlement-previous-month')),
          );
          await tester.pumpAndSettle();
          final chosen = container.read(settlementMonthProvider);
          expect((
            chosen.year,
            chosen.month,
          ), isNot((current.year, current.month)));

          session.become(
            readySession(authority: _ownerAuthority(), freshness: freshness),
          );
          await tester.pumpAndSettle();

          final after = container.read(settlementMonthProvider);
          expect(
            (after.year, after.month),
            (chosen.year, chosen.month),
            reason:
                'a session state change for the same person and authority moved the '
                'chosen month back to the current one',
          );
        });
      }
    },
  );

  group(
    'a confirmed loss of owner_settlement.view for the same person (Slice 11)',
    () {
      AuthoritySnapshot withoutSettlement() => AuthoritySnapshot(
        userId: 'owner-user',
        orgId: 'test-org',
        resolvedAt: DateTime.utc(2026, 8, 28),
        grants: [
          for (final g in _ownerAuthority().grants)
            if (g.capability != Capability.ownerSettlementView) g,
        ],
      );

      Future<int> ownerRows(
        WidgetTester tester,
      ) async => (await tester.runAsync(() async {
        var total = 0;
        for (final table in const [
          'canonical_owner_movements',
          'canonical_owners',
          'canonical_ownership_shares',
          'owner_settlement_coverage',
        ]) {
          total +=
              (await db
                      .customSelect(
                        'SELECT COUNT(*) AS c FROM $table WHERE owner_user_id = ?',
                        variables: [Variable<String>('owner-user')],
                      )
                      .getSingle())
                  .read<int>('c');
        }
        return total;
      }))!;

      uiTest(
        'the open preview refuses, the owner cache is purged, and a direct read refuses',
        (tester) async {
          await synchroniseFor('owner-user', _ownerSnapshot());
          final session = await pump(tester, authority: _ownerAuthority());
          expect(find.text('Partner Alpha'), findsOneWidget);
          expect(await ownerRows(tester), greaterThan(0));

          await tester.runAsync(
            () => ScopeCachePurge(db).applyTo(
              AuthorityRefresh.confirmed(withoutSettlement()),
              previous: _ownerAuthority(),
            ),
          );
          session.become(readySession(authority: withoutSettlement()));
          await tester.pumpAndSettle();

          expect(find.text('Partner Alpha'), findsNothing);
          expect(
            find.byKey(const Key('owner-settlement-unavailable-notAuthorised')),
            findsOneWidget,
          );
          expect(await ownerRows(tester), 0);

          final container = ProviderScope.containerOf(
            tester.element(find.byType(OwnerSettlementPage)),
          );
          final direct = container.read(ownerSettlementPreviewProvider).value;
          expect(direct, isA<OwnerSettlementPreviewUnavailable>());
          expect(
            (direct! as OwnerSettlementPreviewUnavailable).reason,
            OwnerSettlementUnavailableReason.notAuthorised,
          );
          expect(
            await tester.runAsync(
              () => OwnerSettlementRepository(
                db,
                principal: withoutSettlement().principal,
              ).coverage(),
            ),
            isNull,
            reason: 'the repository refuses on its own, whoever reaches it',
          );
        },
      );

      uiTest('a network failure purges nothing and leaves the preview open', (
        tester,
      ) async {
        await synchroniseFor('owner-user', _ownerSnapshot());
        await pump(tester, authority: _ownerAuthority());
        final rows = await ownerRows(tester);

        await tester.runAsync(
          () => ScopeCachePurge(db).applyTo(
            const AuthorityRefresh.unavailable(
              AuthorityUnavailableReason.offline,
            ),
            previous: _ownerAuthority(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Partner Alpha'), findsOneWidget);
        expect(await ownerRows(tester), rows);
      });

      for (final shell in const [AppShellKind.desktop, AppShellKind.mobile]) {
        uiTest(
          '${shell.name}: the navigation entry disappears when it is lost',
          (tester) async {
            await tester.binding.setSurfaceSize(
              shell == AppShellKind.desktop
                  ? const Size(1440, 900)
                  : const Size(390, 844),
            );
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final session = _Session(
              readySession(authority: _ownerAuthority()),
            );
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  databaseProvider.overrideWithValue(db),
                  sessionProvider.overrideWith(() => session),
                ],
                child: KrishnaMisApp(shellKind: shell),
              ),
            );
            await tester.pumpAndSettle();

            Finder entry() => shell == AppShellKind.desktop
                ? find.text('Owner Settlement')
                : find.byKey(const Key('more-owner-settlement'));

            if (shell == AppShellKind.mobile) {
              await tester.tap(find.text('More').last);
              await tester.pumpAndSettle();
            }
            expect(entry(), findsOneWidget);

            session.become(readySession(authority: withoutSettlement()));
            await tester.pumpAndSettle();
            expect(entry(), findsNothing);
          },
        );
      }
    },
  );
}
