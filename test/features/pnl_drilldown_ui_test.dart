/// The read-only drill-down beneath the P&L, on Windows and Android (Phase 5 Slice 10).
///
/// What is real: both P&L pages, their providers, the drill-down providers and view, the
/// immutable document bodies, `ReportDocumentReader`, the canonical reporting cache,
/// `ReportingSync`, `MarkerCoverage`, `CachedDrilldownSource` and the domain rules. What is
/// substituted: only the network — the reporting snapshot and the document projections —
/// and "now". A test never hands a widget a figure.
///
/// The principal in the read-only tests **holds every mutation capability** a ledger would
/// act on. Nothing on the report path may offer any of them.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
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
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/pnl_drilldown.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/attachments/presentation/attachment_strip.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_pnl_drilldown_pages.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/mobile_profit_and_loss_page.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_drilldown_view.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/profit_and_loss_page.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/money_layout.dart';
import '../support/pnl_fixture.dart';
import '../support/report_detail_fakes.dart';
import '../support/ui_harness.dart';

const _laptop = Size(1366, 768);
const _narrow = Size(1024, 700);
const _phone390 = Size(390, 844);
const _phone360 = Size(360, 740);

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
  setUpAll(loadRealFonts);
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

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    gateway = FakeReportingGateway();
    revenueDocs = FakeRevenueDocuments();
    expenseDocs = FakeExpenseDocuments();
    await seedPnlMasters(db);
  });
  tearDown(() => db.close());

  List<Override> overrides({
    List<CapabilityGrant>? grants,
    bool withDetail = true,
  }) => [
    databaseProvider.overrideWithValue(db),
    sessionProvider.overrideWith(
      () => SwitchableSession(pnlSession(grants: grants)),
    ),
    reportingClockProvider.overrideWithValue(() => pnlInstant),
    reportingGatewayProvider.overrideWithValue(gateway),
    if (withDetail) ...[
      expenseGatewayProvider.overrideWithValue(expenseDocs),
      revenueGatewayProvider.overrideWithValue(revenueDocs),
    ],
  ];

  Future<ProviderContainer> pumpWindows(
    WidgetTester tester, {
    List<CapabilityGrant>? grants,
    Size size = _laptop,
    bool withDetail = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(grants: grants, withDetail: withDetail),
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
    return ProviderScope.containerOf(
      tester.element(find.byType(ProfitAndLossPage)),
    );
  }

  Future<ProviderContainer> pumpPhone(
    WidgetTester tester, {
    List<CapabilityGrant>? grants,
    Size size = _phone390,
    double textScale = 1,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = size
      ..padding = const FakeViewPadding(top: 24);
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
        overrides: overrides(grants: grants),
        child: MaterialApp.router(theme: AppTheme.mobile, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(MobileProfitAndLossPage)),
    );
  }

  int paise(WidgetTester tester, String key) =>
      tester.widget<MoneyText>(find.byKey(Key(key))).amount.paise;

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    expect(finder, findsOneWidget, reason: key);
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<Map<String, int>> localCounts() async => {
    for (final table in const [
      'expenses',
      'expense_allocations',
      'expense_period_allocations',
      'revenue_entries',
      'revenue_components',
      'sync_outbox',
    ])
      table:
          (await db
                  .customSelect('SELECT COUNT(*) AS c FROM $table')
                  .getSingle())
              .read<int>('c'),
  };

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
  group('Windows', () {
    uiTest(
      'revenue → category → documents → read-only detail, exact and unwritten',
      (tester) async {
        final sale = pnlSale(
          pnlCcr,
          '2026-09-10',
          gross: 12364200,
          tax: 588771,
        );
        final other = pnlSale(pnlCcr, '2026-09-12', gross: 870000, tax: 41429);
        gateway.revenue.addAll([sale, other]);
        revenueDocs
          ..addFromSale(sale, txnNumber: 'KI-REV-26-27-000501')
          ..addFromSale(other);
        await pumpWindows(tester, grants: _mutationCapable());
        final before = await localCounts();

        await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
        expect(find.byKey(const Key('pnl-drill-layout')), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('pnl-crumb-revenue-category')))
              .data,
          'Restaurant',
        );
        final saleId = sale['revenue_entry_id'];
        expect(paise(tester, 'pnl-drill-doc-$saleId-gross'), 12364200);
        expect(paise(tester, 'pnl-drill-doc-$saleId-gst'), 588771);
        expect(paise(tester, 'pnl-drill-doc-$saleId-net'), 11775429);
        // The total under the documents is the category line on the P&L, exactly.
        expect(paise(tester, 'pnl-drill-total-gross'), 13234200);
        expect(paise(tester, 'pnl-drill-total-gst'), 630200);
        expect(paise(tester, 'pnl-drill-total-net'), 12604000);

        await tapKey(tester, 'pnl-drill-doc-$saleId');
        expect(find.byKey(const Key('pnl-document-revenue')), findsOneWidget);
        expect(find.text('KI-REV-26-27-000501'), findsOneWidget);
        expect(paise(tester, 'pnl-document-contribution-gross'), 12364200);
        expectNoMutationSurface();

        // Fetched and shown; nothing persisted anywhere, nothing queued.
        expect(revenueDocs.reads, greaterThan(0));
        expect(await localCounts(), before);
        expect(before.values.every((n) => n == 0), isTrue);

        await tapKey(tester, 'pnl-document-close');
        expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
        await tapKey(tester, 'pnl-crumb-report');
        expect(find.byKey(const Key('pnl-drill-layout')), findsNothing);
        expect(find.byKey(const Key('pnl-statement')), findsOneWidget);
      },
    );

    uiTest(
      'expenses → department → section → category → documents, each level exact',
      (tester) async {
        // A document with two allocation lines in one bucket, and a bill shared with HKI.
        final line1 = pnlCost(pnlCcr, '2026-09-11', 1845000);
        final line2 = pnlCost(pnlCcr, '2026-09-11', 420001)
          ..['expense_id'] = line1['expense_id'];
        final shared = pnlCost(pnlCcr, '2026-09-14', 2500000);
        final sharedHki = pnlCost(
          pnlHki,
          '2026-09-14',
          3300000,
          category: 'electricity',
        )..['expense_id'] = shared['expense_id'];
        gateway.expense.addAll([line1, line2, shared, sharedHki]);
        expenseDocs
          ..addFromCosts([line1, line2], complete: true, visibleMinor: 2265001)
          ..addFromCosts(
            [shared, sharedHki],
            complete: true,
            visibleMinor: 5800000,
          );
        await pumpWindows(tester, grants: _mutationCapable());
        final before = await localCounts();

        await tapKey(tester, 'pnl-exp-by-department');
        expect(
          paise(tester, 'pnl-drill-dept-$pnlCcr-$pnlCcr-dept-amount'),
          4765001,
        );
        expect(
          paise(tester, 'pnl-drill-dept-$pnlHki-$pnlHki-dept-amount'),
          3300000,
        );
        expect(paise(tester, 'pnl-drill-total-amount'), 8065001);

        await tapKey(tester, 'pnl-drill-dept-$pnlCcr-$pnlCcr-dept');
        expect(
          paise(tester, 'pnl-drill-section-$pnlCcr-$pnlCcr-section-amount'),
          4765001,
        );
        expect(paise(tester, 'pnl-drill-total-amount'), 4765001);

        await tapKey(tester, 'pnl-drill-section-$pnlCcr-$pnlCcr-section');
        expect(
          paise(tester, 'pnl-drill-category-$pnlCcr-$pnlCcr-kirana-amount'),
          4765001,
        );

        await tapKey(tester, 'pnl-drill-category-$pnlCcr-$pnlCcr-kirana');
        expect(
          find.byKey(const Key('pnl-drill-contribution-note')),
          findsOneWidget,
        );
        expect(
          paise(tester, 'pnl-drill-doc-${line1['expense_id']}-amount'),
          2265001,
        );
        expect(
          paise(tester, 'pnl-drill-doc-${shared['expense_id']}-amount'),
          2500000,
        );
        expect(paise(tester, 'pnl-drill-total-amount'), 4765001);

        await tapKey(tester, 'pnl-drill-doc-${shared['expense_id']}');
        expect(find.byKey(const Key('pnl-document-expense')), findsOneWidget);
        // The row is the bucket's share; the body states the whole bill to this reader.
        expect(paise(tester, 'pnl-document-contribution-amount'), 2500000);
        expect(paise(tester, 'detail-visible-amount'), 5800000);
        expect(
          tester.widget<Text>(find.byKey(const Key('amount-label'))).data,
          'TOTAL',
        );
        expectNoMutationSurface();
        expect(await localCounts(), before);

        // Up a level through the breadcrumb.
        await tapKey(tester, 'pnl-crumb-department');
        expect(
          find.byKey(Key('pnl-drill-section-$pnlCcr-$pnlCcr-section')),
          findsOneWidget,
        );
      },
    );

    uiTest('a scoped reader opens only their allocation of a shared bill', (
      tester,
    ) async {
      final shared = pnlCost(pnlCcr, '2026-09-14', 2500000);
      gateway.expense.add(shared);
      expenseDocs.addFromCosts(
        [shared],
        complete: false,
        visibleMinor: 2500000,
      );
      await pumpWindows(tester, grants: _mutationCapable(pnlCcr));

      // The category row is a shortcut to its exact Department + Section + Category bucket.
      await tapKey(tester, 'pnl-exp-open-$pnlCcr-$pnlCcr-kirana');
      expect(find.byKey(const Key('pnl-crumb-department')), findsOneWidget);
      expect(find.byKey(const Key('pnl-crumb-section')), findsOneWidget);
      await tapKey(tester, 'pnl-drill-doc-${shared['expense_id']}');
      expect(
        tester.widget<Text>(find.byKey(const Key('amount-label'))).data,
        'YOUR ALLOCATION',
      );
      expect(find.byKey(const Key('scoped-explanation')), findsOneWidget);
      expect(find.textContaining('58,000'), findsNothing);
      expectNoMutationSurface();
    });

    uiTest(
      'a transaction that changed since the report is refused, then refreshed',
      (tester) async {
        final sale = pnlSale(pnlCcr, '2026-09-10', gross: 500000, tax: 23810);
        gateway.revenue.add(sale);
        revenueDocs.addFromSale(sale);
        // The server now says something different from the synchronised report.
        revenueDocs.components[sale['revenue_entry_id']]!.single
          ..['gross_amount_minor'] = 600000
          ..['tax_amount_minor'] = 28571
          ..['net_amount_minor'] = 571429;
        final container = await pumpWindows(tester);

        await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
        await tapKey(tester, 'pnl-drill-doc-${sale['revenue_entry_id']}');
        expect(find.byKey(const Key('pnl-document-changed')), findsOneWidget);
        expect(find.text(pnlDocumentChangedText), findsOneWidget);
        // The fresher figure is not substituted into the view.
        expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
        expect(
          paise(tester, 'pnl-drill-doc-${sale['revenue_entry_id']}-gross'),
          500000,
        );

        final snapshots = gateway.snapshots;
        await tapKey(tester, 'pnl-document-refresh');
        expect(gateway.snapshots, greaterThan(snapshots));
        expect(container.read(pnlSyncProvider).phase, PnlSyncPhase.succeeded);
      },
    );

    uiTest(
      'with no connection, rows stay and detail says it is not downloaded',
      (tester) async {
        final sale = pnlSale(pnlCcr, '2026-09-10', gross: 500000, tax: 23810);
        gateway.revenue.add(sale);
        await pumpWindows(tester, withDetail: false);
        await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
        expect(
          paise(tester, 'pnl-drill-doc-${sale['revenue_entry_id']}-gross'),
          500000,
        );
        await tapKey(tester, 'pnl-drill-doc-${sale['revenue_entry_id']}');
        expect(find.text(pnlDocumentNotDownloadedText), findsOneWidget);
      },
    );

    uiTest(
      'an offline server answer is not downloaded; a withheld one is not available',
      (tester) async {
        final sale = pnlSale(pnlCcr, '2026-09-10', gross: 500000, tax: 23810);
        final hidden = pnlSale(pnlCcr, '2026-09-11', gross: 100000, tax: 4762);
        gateway.revenue.addAll([sale, hidden]);
        revenueDocs.addFromSale(sale);
        await pumpWindows(tester);
        await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');

        await tapKey(tester, 'pnl-drill-doc-${hidden['revenue_entry_id']}');
        expect(find.text(pnlDocumentNotAvailableText), findsOneWidget);

        revenueDocs.offline = true;
        await tapKey(tester, 'pnl-drill-doc-${sale['revenue_entry_id']}');
        expect(find.text(pnlDocumentNotDownloadedText), findsOneWidget);
      },
    );

    uiTest(
      'a document closed and reopened is fetched again, never shown from the last copy',
      (tester) async {
        final sale = pnlSale(pnlCcr, '2026-09-10', gross: 500000, tax: 23810);
        gateway.revenue.add(sale);
        revenueDocs.addFromSale(sale);
        final container = await pumpWindows(tester);
        await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
        final row = 'pnl-drill-doc-${sale['revenue_entry_id']}';

        await tapKey(tester, row);
        expect(find.byKey(const Key('pnl-document-revenue')), findsOneWidget);
        // In the real Windows executable the fetched copy was still held when the row was
        // tapped again, and no request was made at all (D-239). Hold it here too.
        final held = container.listen(
          pnlDocumentDetailProvider(
            container.read(pnlDrillProvider)!.selected!,
          ),
          (_, _) {},
        );
        addTearDown(held.close);

        // Close and reopen at once, as a person does, then with no connection: reopening is
        // a new request to the server, never the copy held from the last one.
        await tester.tap(find.byKey(const Key('pnl-document-close')));
        await tester.pump();
        revenueDocs.offline = true;
        final reads = revenueDocs.reads;
        await tester.tap(find.byKey(Key(row)));
        await tester.pumpAndSettle();

        expect(revenueDocs.reads, greaterThan(reads));
        expect(find.text(pnlDocumentNotDownloadedText), findsOneWidget);
        expect(find.byKey(const Key('pnl-document-revenue')), findsNothing);
      },
    );

    uiTest('children that do not add up exactly are not shown (positive control)', (
      tester,
    ) async {
      gateway.revenue.add(
        pnlSale(pnlCcr, '2026-09-10', gross: 500000, tax: 23810),
      );
      await pumpWindows(tester);
      // One paisa appears in the cache under the report on screen. Nothing may paper over it.
      await db.customStatement(
        'UPDATE reporting_revenue_contributions SET gross_minor = gross_minor + 1',
      );
      await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
      expect(find.byKey(const Key('pnl-drill-unreconciled')), findsOneWidget);
      expect(find.text(pnlDrillUnreconciledText), findsOneWidget);
      expect(find.textContaining('Other'), findsNothing);
      expect(find.byKey(const Key('pnl-drill-total-gross')), findsNothing);
    });

    uiTest('a new person, or a new scope, closes the drill-down', (
      tester,
    ) async {
      gateway.revenue.add(
        pnlSale(pnlCcr, '2026-09-10', gross: 500000, tax: 23810),
      );
      final container = await pumpWindows(tester);
      await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
      expect(container.read(pnlDrillProvider), isNotNull);

      container
          .read(pnlSelectionProvider.notifier)
          .selectScope(const PnlUnitScope(pnlCcr));
      await tester.pumpAndSettle();
      expect(container.read(pnlDrillProvider), isNull);
      expect(find.byKey(const Key('pnl-drill-layout')), findsNothing);

      await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
      expect(container.read(pnlDrillProvider), isNotNull);
      (container.read(sessionProvider.notifier) as SwitchableSession).switchTo(
        pnlSession(userId: 'user-next', grants: pnlD2(pnlCcr)),
      );
      await tester.pumpAndSettle();
      expect(container.read(pnlDrillProvider), isNull);
      expect(find.byKey(const Key('pnl-drill-layout')), findsNothing);
    });

    uiTest(
      'a level and a document are refused outside the current viewer, scope and bucket',
      (tester) async {
        final sale = pnlSale(pnlCcr, '2026-09-10', gross: 500000, tax: 23810);
        gateway.revenue.add(sale);
        revenueDocs.addFromSale(sale);
        final container = await pumpWindows(tester, grants: pnlD2(pnlCcr));
        final view = container.read(pnlViewProvider).value! as PnlReportView;
        final anchor = PnlDrillAnchor.of(view);

        Future<PnlDrillView> level(PnlDrillLocation l) =>
            container.read(pnlDrillLevelProvider(l).future);

        // Another person's anchor.
        final elsewhere = PnlDrillAnchor(
          viewerUserId: 'someone-else',
          businessUnitIds: anchor.businessUnitIds,
          range: anchor.range,
        );
        expect(
          await level(PnlExpenseDepartmentsAt(elsewhere)),
          isA<PnlDrillRefused>().having(
            (r) => r.reason,
            'reason',
            PnlDrillRefusal.reportChanged,
          ),
        );
        // A property outside the report's scope.
        expect(
          await level(
            PnlExpenseSectionsAt(
              anchor,
              businessUnitId: pnlHki,
              departmentId: '$pnlHki-dept',
            ),
          ),
          isA<PnlDrillRefused>().having(
            (r) => r.reason,
            'reason',
            PnlDrillRefusal.notAuthorised,
          ),
        );

        // A request carrying a row the bucket did not produce is refused before any fetch.
        final location = PnlRevenueDocumentsAt(
          anchor,
          businessUnitId: pnlCcr,
          revenueCategoryId: '$pnlCcr-restaurant',
        );
        final forged = RevenueDocumentLine(
          businessUnitId: pnlCcr,
          revenueCategoryId: '$pnlCcr-restaurant',
          revenueEntryId: sale['revenue_entry_id'] as String,
          pnlDate: BusinessDate.of(2026, 9, 10),
          totals: RevenueTotals(
            gross: Money.fromPaise(999),
            tax: Money.zero,
            net: Money.fromPaise(999),
            contributions: 1,
          ),
        );
        final sub = container.listen(
          pnlDocumentDetailProvider(
            PnlRevenueDocumentRequest(location, forged),
          ),
          (_, _) {},
        );
        addTearDown(sub.close);
        expect(
          await container.read(
            pnlDocumentDetailProvider(
              PnlRevenueDocumentRequest(location, forged),
            ).future,
          ),
          isA<PnlDocumentRefused>().having(
            (r) => r.reason,
            'reason',
            PnlDocumentRefusal.reportChanged,
          ),
        );
        expect(revenueDocs.reads, 0);
        // The unused import guard: the expense line type participates in the same rule.
        expect(ExpenseTotals.zero.contributions, 0);
      },
    );

    for (final size in [_laptop, _narrow]) {
      uiTest('the pane and an open document fit at ${size.width.toInt()}px', (
        tester,
      ) async {
        final sale = pnlSale(
          pnlCcr,
          '2026-09-10',
          gross: 12364200,
          tax: 588771,
        );
        gateway.revenue.add(sale);
        revenueDocs.addFromSale(sale);
        await pumpWindows(tester, size: size);
        await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
        await tapKey(tester, 'pnl-drill-doc-${sale['revenue_entry_id']}');
        expect(find.byKey(const Key('pnl-document-revenue')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('Android', () {
    // D-286: the drill-down pages give way at a large system font, never the money.
    for (final (label, size) in const [
      ('320 × 640', Size(320, 640)),
      ('360 × 740', Size(360, 740)),
      ('411 × 891', Size(411, 891)),
    ]) {
      for (final scale in const [1.6, 2.0]) {
        uiTest('at $label and $scale× every drill-down amount is whole', (
          tester,
        ) async {
          final sale = pnlSale(
            pnlCcr,
            '2026-09-10',
            gross: 1236420000,
            tax: 58877143,
          );
          gateway.revenue.add(sale);
          revenueDocs.addFromSale(sale, txnNumber: 'KI-REV-26-27-000778');
          await pumpPhone(tester, size: size, textScale: scale);
          final where = '$label ×$scale';
          await expectEveryAmountWholeWhileScrolling(tester, '$where, P&L');

          await scrollUntilBuilt(
            tester,
            find.byKey(Key('pnl-rev-open-$pnlCcr-$pnlCcr-restaurant')),
          );
          await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
          expectNoLayoutError(tester, '$where, documents');
          await expectEveryAmountWholeWhileScrolling(
            tester,
            '$where, documents',
          );

          await scrollUntilBuilt(
            tester,
            find.byKey(Key('pnl-drill-doc-${sale['revenue_entry_id']}')),
          );
          await tapKey(tester, 'pnl-drill-doc-${sale['revenue_entry_id']}');
          expectNoLayoutError(tester, '$where, document');
          await expectEveryAmountWholeWhileScrolling(
            tester,
            '$where, document',
          );
        });
      }
    }

    uiTest('Reports → category → documents → read-only detail, and back', (
      tester,
    ) async {
      final sale = pnlSale(pnlCcr, '2026-09-10', gross: 12364200, tax: 588771);
      gateway.revenue.add(sale);
      revenueDocs.addFromSale(sale, txnNumber: 'KI-REV-26-27-000777');
      await pumpPhone(tester, grants: _mutationCapable());
      final before = await localCounts();

      await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
      expect(find.byType(MobilePnlDrillPage), findsOneWidget);
      expect(
        paise(tester, 'pnl-drill-doc-${sale['revenue_entry_id']}-gross'),
        12364200,
      );
      expect(paise(tester, 'pnl-drill-total-gross'), 12364200);

      await tapKey(tester, 'pnl-drill-doc-${sale['revenue_entry_id']}');
      expect(find.byType(MobilePnlDocumentPage), findsOneWidget);
      expect(find.text('KI-REV-26-27-000777'), findsOneWidget);
      expectNoMutationSurface();
      expect(await localCounts(), before);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MobilePnlDocumentPage), findsNothing);
      expect(find.byType(MobilePnlDrillPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MobilePnlDrillPage), findsNothing);
      expect(find.byType(MobileProfitAndLossPage), findsOneWidget);
    });

    uiTest('expenses by department down to a document, at 360px', (
      tester,
    ) async {
      final cost = pnlCost(pnlCcr, '2026-09-11', 1845000);
      gateway.expense.add(cost);
      expenseDocs.addFromCosts([cost], complete: true, visibleMinor: 1845000);
      await pumpPhone(tester, grants: _mutationCapable(), size: _phone360);

      await tapKey(tester, 'pnl-exp-by-department');
      await tapKey(tester, 'pnl-drill-dept-$pnlCcr-$pnlCcr-dept');
      await tapKey(tester, 'pnl-drill-section-$pnlCcr-$pnlCcr-section');
      await tapKey(tester, 'pnl-drill-category-$pnlCcr-$pnlCcr-kirana');
      expect(
        paise(tester, 'pnl-drill-doc-${cost['expense_id']}-amount'),
        1845000,
      );
      expect(paise(tester, 'pnl-drill-total-amount'), 1845000);
      await tapKey(tester, 'pnl-drill-doc-${cost['expense_id']}');
      expect(find.byKey(const Key('pnl-document-expense')), findsOneWidget);
      expectNoMutationSurface();
      expect(tester.takeException(), isNull);
    });

    uiTest(
      'a document page backed out of and reopened is fetched again, never shown from the last copy',
      (tester) async {
        final cost = pnlCost(pnlCcr, '2026-09-11', 1845000);
        gateway.expense.add(cost);
        expenseDocs.addFromCosts([cost], complete: true, visibleMinor: 1845000);
        final container = await pumpPhone(tester);

        await tapKey(tester, 'pnl-exp-open-$pnlCcr-$pnlCcr-kirana');
        final row = 'pnl-drill-doc-${cost['expense_id']}';
        await tapKey(tester, row);
        expect(find.byKey(const Key('pnl-document-expense')), findsOneWidget);
        // Hold the fetched copy, as the real application still may when the row is tapped
        // again (D-239).
        final held = container.listen(
          pnlDocumentDetailProvider(
            tester
                .widget<MobilePnlDocumentPage>(
                  find.byType(MobilePnlDocumentPage),
                )
                .request,
          ),
          (_, _) {},
        );
        addTearDown(held.close);

        // Back out and reopen at once, then with no connection: a new request to the server.
        await tester.binding.handlePopRoute();
        await tester.pump();
        expenseDocs.offline = true;
        final reads = expenseDocs.reads;
        await tester.pumpAndSettle();
        expect(find.byType(MobilePnlDocumentPage), findsNothing);
        await tester.tap(find.byKey(Key(row)));
        await tester.pumpAndSettle();

        expect(expenseDocs.reads, greaterThan(reads));
        expect(find.text(pnlDocumentNotDownloadedText), findsOneWidget);
        expect(find.byKey(const Key('pnl-document-expense')), findsNothing);
      },
    );

    uiTest('a new person returns every drill-down page to the P&L', (
      tester,
    ) async {
      gateway.revenue.add(
        pnlSale(pnlCcr, '2026-09-10', gross: 500000, tax: 23810),
      );
      final container = await pumpPhone(tester);
      await tapKey(tester, 'pnl-rev-open-$pnlCcr-$pnlCcr-restaurant');
      expect(find.byType(MobilePnlDrillPage), findsOneWidget);

      (container.read(sessionProvider.notifier) as SwitchableSession).switchTo(
        pnlSession(userId: 'user-next', grants: pnlD2(pnlCcr)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobilePnlDrillPage), findsNothing);
      expect(find.byType(MobileProfitAndLossPage), findsOneWidget);
    });
  });
}
