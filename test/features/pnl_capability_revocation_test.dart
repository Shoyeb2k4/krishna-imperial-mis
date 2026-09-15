/// A confirmed capability loss while a P&L, a drill-down and a document are open.
///
/// Phase 5 Slice 11. Slices 7 to 10 proved that a *new person* sees nothing of the previous
/// person's report, drill-down or document, and that a confirmed revocation purges the
/// canonical cache. None proved the case in between: the **same person**, still signed in,
/// with the report open, loses one of the capabilities the report rests on while keeping their
/// business-unit access.
///
/// What is real: both P&L pages, their providers, the drill-down providers and view, the
/// canonical reporting cache, `ReportingSync` and `ScopeCachePurge`. What is substituted: the
/// network, "now", and the authority answer the server would have given.
library;

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/app/routing/app_routes.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
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

const _laptop = Size(1366, 768);

AuthoritySnapshot _authority(List<CapabilityGrant> grants) => AuthoritySnapshot(
  userId: pnlMe,
  orgId: 'test-org',
  resolvedAt: DateTime.utc(2026, 9, 19),
  grants: grants,
);

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late AppDatabase db;
  late FakeReportingGateway gateway;
  late FakeRevenueDocuments revenueDocs;
  late FakeExpenseDocuments expenseDocs;
  late Map<String, dynamic> sale;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeReportingGateway();
    revenueDocs = FakeRevenueDocuments();
    expenseDocs = FakeExpenseDocuments();
    await seedPnlMasters(db);
    sale = pnlSale(pnlCcr, '2026-09-10', gross: 1050000, tax: 50000);
    gateway
      ..revenue.add(sale)
      ..revenue.add(
        pnlSale(
          pnlHki,
          '2026-09-11',
          gross: 400000,
          tax: 0,
          category: 'banquet',
        ),
      )
      ..expense.add(pnlCost(pnlCcr, '2026-09-12', 200000));
    revenueDocs.addFromSale(sale, txnNumber: 'KI-REV-26-27-000901');
  });
  tearDown(() => db.close());

  List<Override> overrides(SwitchableSession session) => [
    databaseProvider.overrideWithValue(db),
    sessionProvider.overrideWith(() => session),
    reportingClockProvider.overrideWithValue(() => pnlInstant),
    reportingGatewayProvider.overrideWithValue(gateway),
    expenseGatewayProvider.overrideWithValue(expenseDocs),
    revenueGatewayProvider.overrideWithValue(revenueDocs),
  ];

  Future<(ProviderContainer, SwitchableSession)> pumpWindows(
    WidgetTester tester,
    List<CapabilityGrant> grants,
  ) async {
    final session = SwitchableSession(pnlSession(grants: grants));
    await tester.binding.setSurfaceSize(_laptop);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(session),
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
    await tester.pumpAndSettle();
    return (
      ProviderScope.containerOf(tester.element(find.byType(ProfitAndLossPage))),
      session,
    );
  }

  Future<(ProviderContainer, SwitchableSession)> pumpPhone(
    WidgetTester tester,
    List<CapabilityGrant> grants,
  ) async {
    final session = SwitchableSession(pnlSession(grants: grants));
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844)
      ..padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    final GoRouter router = AppRouter.create(
      shellKind: AppShellKind.mobile,
      initialLocation: AppRoutes.reports,
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(session),
        child: MaterialApp.router(theme: AppTheme.mobile, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return (
      ProviderScope.containerOf(
        tester.element(find.byType(MobileProfitAndLossPage)),
      ),
      session,
    );
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    expect(finder, findsOneWidget, reason: key);
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<int> reportingRowsForMe(
    WidgetTester tester,
  ) async => (await tester.runAsync(() async {
    var total = 0;
    for (final table in const [
      'reporting_revenue_contributions',
      'reporting_expense_contributions',
      'reporting_coverage_markers',
    ]) {
      total +=
          (await db
                  .customSelect(
                    'SELECT COUNT(*) AS c FROM $table WHERE owner_user_id = ?',
                    variables: [Variable<String>(pnlMe)],
                  )
                  .getSingle())
              .read<int>('c');
    }
    return total;
  }))!;

  /// What the server says, applied the way `ReferenceSync` applies it: the purge first,
  /// then the session moves to the new authority.
  Future<void> confirmAuthority(
    WidgetTester tester,
    SwitchableSession session, {
    required List<CapabilityGrant> from,
    required List<CapabilityGrant> to,
  }) async {
    await tester.runAsync(
      () => ScopeCachePurge(db).applyTo(
        AuthorityRefresh.confirmed(_authority(to)),
        previous: _authority(from),
      ),
    );
    session.switchTo(pnlSession(grants: to));
    await tester.pumpAndSettle();
  }

  Future<void> openDocument(WidgetTester tester) async {
    await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
    await tapKey(tester, 'pnl-drill-doc-${sale['revenue_entry_id']}');
  }

  const lost = [
    Capability.reportsView,
    Capability.revenueView,
    Capability.expenseViewAll,
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  group('Windows', () {
    for (final capability in lost) {
      uiTest(
        'losing ${capability.code} closes the report, the drill-down and the document',
        (tester) async {
          final (container, session) = await pumpWindows(tester, pnlD2());
          expect(find.byKey(const Key('pnl-gross')), findsOneWidget);
          await openDocument(tester);
          expect(find.byKey(const Key('pnl-document-revenue')), findsOneWidget);
          expect(await reportingRowsForMe(tester), greaterThan(0));

          await confirmAuthority(
            tester,
            session,
            from: pnlD2(),
            to: [
              for (final g in pnlD2())
                if (g.capability != capability) g,
            ],
          );

          expect(
            container.read(pnlDrillProvider),
            isNull,
            reason:
                'the drill-down stayed open for a person who may no longer read the report '
                'beneath it',
          );
          expect(find.byKey(const Key('pnl-drill-layout')), findsNothing);
          expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
          expect(find.text('KI-REV-26-27-000901'), findsNothing);
          expect(find.byKey(const Key('pnl-gross')), findsNothing);
          expect(find.byKey(const Key('pnl-not-authorised')), findsOneWidget);
          expect(
            await reportingRowsForMe(tester),
            0,
            reason:
                'a confirmed loss purges the canonical reporting cache (D-070)',
          );
        },
      );
    }

    uiTest(
      'losing unscoped authority closes consolidated, and each property still reports',
      (tester) async {
        final scoped = [...pnlD2(pnlCcr), ...pnlD2(pnlHki)];
        final (container, session) = await pumpWindows(tester, pnlD2());
        expect(find.byKey(const Key('pnl-gross')), findsOneWidget);
        await openDocument(tester);

        await confirmAuthority(tester, session, from: pnlD2(), to: scoped);

        expect(container.read(pnlDrillProvider), isNull);
        expect(find.byKey(const Key('pnl-drill-layout')), findsNothing);
        expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
        expect(find.byKey(const Key('pnl-scope-consolidated')), findsNothing);
        expect(
          find.byKey(const Key('pnl-gross')),
          findsOneWidget,
          reason: 'a property the person still holds keeps reporting',
        );
        expect(
          await reportingRowsForMe(tester),
          greaterThan(0),
          reason:
              'every property stays reportable one at a time, so nothing is purged',
        );
      },
    );

    uiTest(
      'a refresh that could not reach the server changes nothing that is open',
      (tester) async {
        final (container, _) = await pumpWindows(tester, pnlD2());
        await openDocument(tester);
        final rows = await reportingRowsForMe(tester);

        await tester.runAsync(
          () => ScopeCachePurge(db).applyTo(
            const AuthorityRefresh.unavailable(
              AuthorityUnavailableReason.offline,
            ),
            previous: _authority(pnlD2()),
          ),
        );
        await tester.pumpAndSettle();

        expect(container.read(pnlDrillProvider), isNotNull);
        expect(find.byKey(const Key('pnl-document-revenue')), findsOneWidget);
        expect(await reportingRowsForMe(tester), rows);
      },
    );
  });

  group('an authority refresh that could not reach the server', () {
    uiTest(
      'the session goes stale for the same person, and the open drill-down stays open',
      (tester) async {
        final (container, session) = await pumpWindows(tester, pnlD2());
        await openDocument(tester);
        expect(find.byKey(const Key('pnl-document-revenue')), findsOneWidget);
        final rows = await reportingRowsForMe(tester);

        // What `refreshAuthority()` leaves behind when the server is unreachable: the same
        // person, the same cached authority, marked stale. Nothing was confirmed, so nothing
        // may be purged and nothing that is open may close.
        session.switchTo(
          SessionState.ready(
            authority: _authority(pnlD2()),
            freshness: AuthorityFreshness.stale,
            email: 'me@example.test',
          ),
        );
        await tester.pumpAndSettle();

        expect(
          container.read(pnlDrillProvider),
          isNotNull,
          reason: 'a refresh that proved nothing closed the drill-down',
        );
        expect(find.byKey(const Key('pnl-drill-layout')), findsOneWidget);
        expect(find.byKey(const Key('pnl-not-authorised')), findsNothing);
        expect(
          find.byKey(const Key('pnl-document-revenue')).evaluate().isNotEmpty ||
              find.text(pnlDocumentNotDownloadedText).evaluate().isNotEmpty,
          isTrue,
          reason:
              'the pane shows the document, or says detail needs a connection — never '
              'a refusal and never nothing',
        );
        expect(await reportingRowsForMe(tester), rows);
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Android', () {
    for (final capability in lost) {
      uiTest('losing ${capability.code} returns every drill page to the P&L', (
        tester,
      ) async {
        final (_, session) = await pumpPhone(tester, pnlD2());
        await openDocument(tester);
        expect(find.byType(MobilePnlDocumentPage), findsOneWidget);

        await confirmAuthority(
          tester,
          session,
          from: pnlD2(),
          to: [
            for (final g in pnlD2())
              if (g.capability != capability) g,
          ],
        );

        expect(
          find.byType(MobilePnlDocumentPage),
          findsNothing,
          reason:
              'a read-only document stayed on screen after ${capability.code} was lost',
        );
        expect(find.byType(MobilePnlDrillPage), findsNothing);
        expect(find.byType(MobileProfitAndLossPage), findsOneWidget);
        expect(find.byKey(const Key('pnl-gross')), findsNothing);
        expect(await reportingRowsForMe(tester), 0);
      });
    }
  });
}
