/// The Windows revenue surfaces, driven as a finance user drives them.
///
/// The assertions that matter are about what the screen is willing to claim: a tax
/// snapshot read from the sale rather than re-resolved from today's rules, an untaxed
/// category distinguished from a configured 0%, a status column that cannot overflow, and
/// a ledger that never shows retained work belonging to somebody else.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_ledger_page.dart';
import 'package:krishna_mis/features/transactions/presentation/transactions_page.dart';

import '../support/test_session.dart';
import '../support/ui_harness.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _restaurant = 'cat-restaurant';
const _room = 'cat-room';
const _banquet = 'cat-banquet';
const _userA = 'user-a';
const _userB = 'user-b';

final _june15 = BusinessDate.of(2026, 6, 15);

/// A laptop, a resized window, and a maximised screen.
const _laptop = Size(1366, 768);
const _narrow = Size(1100, 720);
const _wide = Size(1920, 1080);

Principal _principal({
  String user = _userA,
  Set<String> units = const {_ccr, _hki},
}) => Principal(
  userId: user,
  grants: [
    for (final unit in units)
      for (final capability in const [
        Capability.revenueCreate,
        Capability.revenueView,
        Capability.mastersView,
      ])
        CapabilityGrant(capability, businessUnitId: unit),
  ],
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  var seq = 0;

  setUp(() async {
    seq = 0;
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');

    for (final unit in const [
      (_ccr, 'CCR', 'Crystal Canopy Rooftop'),
      (_hki, 'HKI', 'Hotel Krishna Imperial'),
    ]) {
      await db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, 'hotel', 'Asia/Kolkata', '05:00', 1, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [unit.$1, unit.$2, unit.$3],
      );
    }
    for (final c in const [
      (_restaurant, _ccr, 'RESTAURANT', 'Restaurant'),
      (_room, _hki, 'ROOM', 'Room'),
      (_banquet, _hki, 'BANQUET', 'Banquet'),
    ]) {
      await db.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, ?, 1, 1, '2026-04-01T00:00:00.000Z')",
        [c.$1, c.$2, c.$3, c.$4],
      );
    }
  });

  tearDown(() => db.close());

  Future<void> cacheRule({
    required String id,
    required String category,
    int rateBp = 500,
    String treatment = 'inclusive',
  }) => db.customStatement(
    'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
    'rate_basis_points, treatment, effective_from, input_basis, created_by, '
    'created_at, row_version, updated_at) '
    "VALUES (?, '$_org', ?, ?, ?, '2026-04-01', 'inclusive_total', 'u', "
    "'2026-04-01T00:00:00.000Z', 1, '2026-04-01T00:00:00.000Z')",
    [id, category, rateBp, treatment],
  );

  /// Marks one user's configuration complete for both properties.
  ///
  /// Separate from [baseline] because the rules are organisation-wide and the
  /// completeness record is per user (D-108) — inserting the rules again for a second
  /// user would be claiming they are somehow that user's.
  Future<void> markComplete({
    String user = _userA,
    Duration age = const Duration(hours: 1),
  }) async {
    for (final unit in const [_ccr, _hki]) {
      await db.customStatement(
        'INSERT OR REPLACE INTO revenue_config_snapshots (user_id, org_id, '
        'business_unit_id, status, datasets, generation, confirmed_at, '
        'updated_at) '
        "VALUES (?, '$_org', ?, 'complete', 'bands,rules,statuses,subtypes', "
        "'900', ?, ?)",
        [
          user,
          unit,
          DateTime.now().toUtc().subtract(age).toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
    }
  }

  Future<void> baseline({
    String user = _userA,
    Duration age = const Duration(hours: 1),
  }) async {
    await cacheRule(id: 'rule-restaurant', category: _restaurant);
    await cacheRule(id: 'rule-room', category: _room);
    await cacheRule(
      id: 'rule-banquet',
      category: _banquet,
      rateBp: 0,
      treatment: 'none',
    );
    await markComplete(user: user, age: age);
  }

  Future<String> seedSale({
    String category = _restaurant,
    String unit = _ccr,
    String date = '2026-06-15',
    int amount = 10000000,
    int rateBp = 500,
    String treatment = 'inclusive',
    String actor = _userA,
    String? txnNumber,
    bool quarantined = false,
    String? outboxStatus,
    int components = 1,
  }) async {
    seq++;
    final id = 'entry-${seq.toString().padLeft(3, '0')}';
    await db.customStatement(
      'INSERT INTO revenue_entries (id, org_id, business_unit_id, '
      'revenue_category_id, business_date, pnl_period_key, captured_at, '
      'entry_kind, created_by, txn_number, financial_year, scope_revoked_at, '
      'pending_mutation_id, row_version, updated_at) '
      "VALUES (?, '$_org', ?, ?, ?, ?, ?, 'daily_summary', ?, ?, ?, ?, ?, 1, ?)",
      [
        id,
        unit,
        category,
        date,
        date.substring(0, 7),
        '2026-06-15T${(9 + seq % 12).toString().padLeft(2, '0')}:00:00.000Z',
        actor,
        txnNumber,
        txnNumber == null ? null : '2026-27',
        quarantined ? '2026-06-21T00:00:00.000Z' : null,
        outboxStatus == null ? null : 'mut-$id',
        '2026-06-15T09:00:00.000Z',
      ],
    );
    for (var i = 0; i < components; i++) {
      final share = amount ~/ components;
      final tax = treatment == 'none'
          ? 0
          : (2 * share * rateBp + (10000 + rateBp)) ~/ (2 * (10000 + rateBp));
      await db.customStatement(
        'INSERT INTO revenue_components (id, org_id, revenue_entry_id, '
        'entered_amount_minor, entered_basis, gross_amount_minor, '
        'tax_amount_minor, net_amount_minor, tax_rule_id, tax_rate_basis_points, '
        'tax_treatment, value_band_id, value_band_label, '
        'value_band_floor_minor, value_band_ceiling_minor) '
        "VALUES (?, '$_org', ?, ?, 'inclusive_total', ?, ?, ?, 'rule-x', ?, ?, "
        '?, ?, ?, ?)',
        [
          '$id-c$i',
          id,
          share,
          share,
          tax,
          share - tax,
          rateBp,
          treatment,
          // Bounds without an identity are meaningless, and the schema says so. The
          // fixture obeys the rule rather than working around it.
          components > 1 ? (i == 0 ? 'band-lower' : 'band-upper') : null,
          components > 1 ? (i == 0 ? 'Lower band' : 'Upper band') : null,
          components > 1 ? (i == 0 ? 0 : 750000) : null,
          components > 1 ? (i == 0 ? 750000 : null) : null,
        ],
      );
    }
    if (outboxStatus != null) {
      await db.customStatement(
        'INSERT INTO sync_outbox (mutation_id, actor_user_id, entity_type, '
        'entity_id, op, payload, next_attempt_at, status, created_at, '
        'attempt_count) '
        "VALUES (?, ?, ?, ?, 'create', '{}', ?, ?, ?, 0)",
        [
          'mut-$id',
          actor,
          revenueEntityType,
          id,
          '2026-06-15T09:00:00.000Z',
          outboxStatus,
          '2026-06-15T09:00:00.000Z',
        ],
      );
    }
    return id;
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Principal? principal,
    Size size = _laptop,
  }) async {
    final actor = principal ?? _principal();
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          outboxProvider.overrideWithValue(OutboxRepository(db)),
          sessionProvider.overrideWith(
            () => StubSession(
              readySession(
                authority: AuthoritySnapshot(
                  userId: actor.userId,
                  orgId: _org,
                  grants: actor.grants,
                  resolvedAt: DateTime.now().toUtc(),
                ),
              ),
            ),
          ),
          principalProvider.overrideWithValue(actor),
          currentBusinessDateProvider.overrideWithValue(_june15),
        ],
        child: MaterialApp(
          theme: AppTheme.desktop,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const ledger = RevenueLedgerPage(shellKind: AppShellKind.desktop);

  group('Transactions holds both ledgers', () {
    uiTest('Expenses is the default, Sales is one click away', (tester) async {
      await baseline();
      await pump(
        tester,
        const TransactionsPage(shellKind: AppShellKind.desktop),
      );

      expect(find.byKey(const Key('transactions-tabs')), findsOneWidget);
      expect(find.byKey(const Key('add-expense')), findsOneWidget);

      await tester.tap(find.text('Sales'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add-revenue')), findsOneWidget);
    });

    uiTest('switching tabs does not rebuild the other ledger from scratch', (
      tester,
    ) async {
      // `IndexedStack` keeps both mounted, so a filter a finance user spent a minute
      // assembling survives a glance at the other ledger.
      await baseline();
      await seedSale(txnNumber: 'KI-REV-26-27-000001');
      await pump(
        tester,
        const TransactionsPage(shellKind: AppShellKind.desktop),
      );

      await tester.tap(find.text('Sales'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('revenue-filter-search')),
        'nothing-matches-this',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('revenue-ledger-no-matches')),
        findsOneWidget,
      );

      await tester.tap(find.text('Expenses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sales'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('revenue-ledger-no-matches')),
        findsOneWidget,
        reason: 'the filter survived the trip to the other tab',
      );
    });
  });

  group('the ledger table', () {
    uiTest('renders a sale with its money and its number', (tester) async {
      await baseline();
      await seedSale(txnNumber: 'KI-REV-26-27-000001');
      await pump(tester, ledger);

      expect(find.byKey(const Key('revenue-ledger-table')), findsOneWidget);
      expect(find.text('KI-REV-26-27-000001'), findsOneWidget);
      expect(find.text('Crystal Canopy Rooftop'), findsWidgets);
      expect(find.text('Restaurant'), findsWidgets);
      expect(find.text('₹1,00,000.00'), findsOneWidget);
      expect(find.text('₹4,761.90'), findsOneWidget);
      expect(find.text('₹95,238.10'), findsOneWidget);
    });

    uiTest('an unnumbered sale shows a pending reference', (tester) async {
      await baseline();
      await seedSale(outboxStatus: 'pending');
      await pump(tester, ledger);

      expect(find.textContaining('Pending number'), findsOneWidget);
      expect(find.textContaining('KI-REV-'), findsNothing);
    });

    uiTest('empty and no-match states are different sentences', (tester) async {
      await baseline();
      await pump(tester, ledger);
      expect(find.byKey(const Key('revenue-ledger-empty')), findsOneWidget);

      await seedSale(txnNumber: 'KI-REV-26-27-000001');
      await pump(tester, ledger);
      await tester.enterText(
        find.byKey(const Key('revenue-filter-search')),
        'zzz',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('revenue-ledger-no-matches')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('revenue-ledger-empty')), findsNothing);
    });

    uiTest('a user with no permitted property is told so', (tester) async {
      await baseline();
      await pump(
        tester,
        ledger,
        principal: Principal(userId: _userA, grants: const []),
      );

      expect(find.byKey(const Key('revenue-ledger-no-scope')), findsOneWidget);
      expect(find.byKey(const Key('add-revenue')), findsNothing);
    });
  });

  group('filters, on the screen', () {
    uiTest('Clear filters appears only once something is filtered', (
      tester,
    ) async {
      await baseline();
      await seedSale(txnNumber: 'KI-REV-26-27-000001');
      await pump(tester, ledger);

      expect(find.byKey(const Key('revenue-filter-reset')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('revenue-filter-search')),
        'KI-REV',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('revenue-filter-reset')), findsOneWidget);

      await tester.tap(find.byKey(const Key('revenue-filter-reset')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('revenue-filter-reset')), findsNothing);
      expect(find.text('KI-REV-26-27-000001'), findsOneWidget);
    });

    uiTest('include voided is a toggle, and voided rows say so', (
      tester,
    ) async {
      await baseline();
      final id = await seedSale(txnNumber: 'KI-REV-26-27-000001');
      await db.customStatement(
        "UPDATE revenue_entries SET voided_at = ?, voided_by = ?, "
        "void_reason = 'Recorded twice' WHERE id = ?",
        ['2026-06-20T00:00:00.000Z', _userA, id],
      );

      await pump(tester, ledger);
      expect(find.byKey(const Key('revenue-ledger-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('revenue-filter-voided')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('revenue-voided-chip')), findsOneWidget);
      expect(find.text('Voided'), findsOneWidget);
    });
  });

  group('the detail panel explains the sale from its own snapshot', () {
    uiTest('a taxed sale shows the rate it was recorded under', (tester) async {
      await baseline();
      final id = await seedSale(txnNumber: 'KI-REV-26-27-000001');
      await pump(tester, ledger);

      await tester.tap(find.byKey(Key('revenue-ledger-row-$id')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('revenue-detail-panel')), findsOneWidget);
      expect(find.text('KI-REV-26-27-000001'), findsWidgets);
      expect(find.text('GST at 5%'), findsOneWidget);
      expect(find.textContaining('5% inclusive rule'), findsOneWidget);
    });

    uiTest('the snapshot survives the configuration being deleted', (
      tester,
    ) async {
      // The whole reason the snapshot exists. A panel that re-resolved today's rules
      // would quietly restate history the moment a rate changed (D-080).
      await baseline();
      final id = await seedSale(txnNumber: 'KI-REV-26-27-000001');
      await db.customStatement('DELETE FROM revenue_tax_rates');

      await pump(tester, ledger);
      await tester.tap(find.byKey(Key('revenue-ledger-row-$id')));
      await tester.pumpAndSettle();

      expect(find.text('GST at 5%'), findsOneWidget);
      expect(find.text('₹4,761.90'), findsWidgets);
    });

    uiTest('an untaxed sale says No GST, never 0%', (tester) async {
      await baseline();
      final id = await seedSale(
        category: _banquet,
        unit: _hki,
        amount: 4034300,
        rateBp: 0,
        treatment: 'none',
        txnNumber: 'KI-REV-26-27-000002',
      );

      await pump(tester, ledger);
      await tester.tap(find.byKey(Key('revenue-ledger-row-$id')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('revenue-component-no-gst-0')),
        findsOneWidget,
      );
      expect(find.text('No GST'), findsOneWidget);
      expect(find.text('GST at 0%'), findsNothing);
      expect(
        find.textContaining('no GST'),
        findsWidgets,
        reason: 'the rule line says the treatment, not a rate',
      );
    });

    uiTest('a configured 0% is shown as a rate, not as No GST', (tester) async {
      // The distinction the panel exists to keep. Both give ₹0 and they are different
      // statements: one is a treatment somebody chose, the other a rate somebody set.
      await baseline();
      final id = await seedSale(
        amount: 4034300,
        rateBp: 0,
        txnNumber: 'KI-REV-26-27-000003',
      );

      await pump(tester, ledger);
      await tester.tap(find.byKey(Key('revenue-ledger-row-$id')));
      await tester.pumpAndSettle();

      expect(find.text('GST at 0%'), findsOneWidget);
      expect(find.text('No GST'), findsNothing);
    });

    uiTest('a multi-component sale shows each band and then the totals', (
      tester,
    ) async {
      await baseline();
      final id = await seedSale(
        category: _room,
        unit: _hki,
        amount: 6000000,
        components: 2,
        txnNumber: 'KI-REV-26-27-000004',
      );

      await pump(tester, ledger);
      await tester.tap(find.byKey(Key('revenue-ledger-row-$id')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('revenue-component-0')), findsOneWidget);
      expect(find.byKey(const Key('revenue-component-1')), findsOneWidget);
      expect(find.text('Lower band'), findsOneWidget);
      expect(find.text('Upper band'), findsOneWidget);

      // The panel is a lazy list, so the totals block is built when it is reached.
      await tester.scrollUntilVisible(
        find.byKey(const Key('revenue-detail-totals')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('revenue-detail-panel')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.byKey(const Key('revenue-detail-totals')),
        findsOneWidget,
        reason: 'two rates are never flattened into one misleading figure',
      );
    });

    uiTest('a single-component sale shows no redundant totals block', (
      tester,
    ) async {
      await baseline();
      final id = await seedSale(txnNumber: 'KI-REV-26-27-000005');
      await pump(tester, ledger);
      await tester.tap(find.byKey(Key('revenue-ledger-row-$id')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('revenue-detail-totals')), findsNothing);
    });

    uiTest('no edit or void control is offered — that is Slice 10', (
      tester,
    ) async {
      await baseline();
      final id = await seedSale(txnNumber: 'KI-REV-26-27-000006');
      await pump(tester, ledger);
      await tester.tap(find.byKey(Key('revenue-ledger-row-$id')));
      await tester.pumpAndSettle();

      for (final label in const ['Edit', 'Void', 'Correct', 'Delete']) {
        expect(
          find.widgetWithText(FilledButton, label),
          findsNothing,
          reason: 'a control implying a feature that does not exist is D-077',
        );
        expect(find.widgetWithText(TextButton, label), findsNothing);
      }
    });
  });

  group('quarantined work never reaches the desktop ledger', () {
    uiTest('a retained attempt is absent, and the row still exists', (
      tester,
    ) async {
      await baseline();
      await seedSale(txnNumber: 'KI-REV-26-27-000001');
      await seedSale(quarantined: true, outboxStatus: 'pending');

      await pump(tester, ledger);

      expect(find.byKey(const Key('revenue-ledger-table')), findsOneWidget);
      expect(find.text('KI-REV-26-27-000001'), findsOneWidget);
      expect(find.textContaining('Pending number'), findsNothing);

      final stored = await db
          .customSelect('SELECT COUNT(*) AS n FROM revenue_entries')
          .getSingle();
      expect(stored.data['n'], 2, reason: 'hidden, not destroyed');
    });

    uiTest("a second user sees the canonical history and none of A's work", (
      tester,
    ) async {
      // The accumulated-database shape that exposed D-074 on Windows: a workstation
      // where somebody else has already worked.
      await baseline();
      await markComplete(user: _userB);
      await seedSale(actor: _userA, txnNumber: 'KI-REV-26-27-000001');
      await seedSale(actor: _userA, quarantined: true, outboxStatus: 'pending');

      await pump(tester, ledger, principal: _principal(user: _userB));

      expect(
        find.text('KI-REV-26-27-000001'),
        findsOneWidget,
        reason: 'canonical scoped history is theirs to see',
      );
      expect(
        find.textContaining('Pending number'),
        findsNothing,
        reason: "holding the same property is not authorship of A's attempt",
      );
    });
  });

  group('layout at real Windows sizes', () {
    for (final (name, size) in const [
      ('a laptop', _laptop),
      ('a resized window', _narrow),
      ('maximised', _wide),
    ]) {
      uiTest('no overflow on $name, in every status', (tester) async {
        // The Slice 8 defect was a status chip overflowing only in the conflict state,
        // which a screenshot would have shown as correct because the money still fitted.
        // Every state is rendered here, at three widths.
        await baseline();
        await seedSale(txnNumber: 'KI-REV-26-27-000001');
        await seedSale(outboxStatus: 'pending');
        await seedSale(outboxStatus: 'conflict');
        await seedSale(outboxStatus: 'rejected');
        await seedSale(outboxStatus: 'failed');

        await pump(tester, ledger, size: size);

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('revenue-ledger-table')), findsOneWidget);
      });
    }

    uiTest('a financial value is never truncated to fit', (tester) async {
      await baseline();
      await seedSale(amount: 100000001, txnNumber: 'KI-REV-26-27-000001');

      await pump(tester, ledger, size: _narrow);

      // Ten lakh and one paisa, in full. A narrow window scrolls rather than eliding.
      expect(find.text('₹10,00,000.01'), findsOneWidget);
    });
  });

  group('paging on the screen', () {
    uiTest('the pager advances and returns, and reports the page', (
      tester,
    ) async {
      await baseline();
      for (var i = 0; i < 60; i++) {
        await seedSale(
          txnNumber: 'KI-REV-26-27-${i.toString().padLeft(6, '0')}',
        );
      }

      await pump(tester, ledger);

      expect(find.text('Page 1'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('revenue-page-previous')))
            .onPressed,
        isNull,
        reason: 'there is no page before the first',
      );

      await tester.tap(find.byKey(const Key('revenue-page-next')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('revenue-page-previous')));
      await tester.pumpAndSettle();
      expect(find.text('Page 1'), findsOneWidget);
    });

    uiTest('a filter change returns to the first page', (tester) async {
      await baseline();
      for (var i = 0; i < 60; i++) {
        await seedSale(
          txnNumber: 'KI-REV-26-27-${i.toString().padLeft(6, '0')}',
        );
      }

      await pump(tester, ledger);
      await tester.tap(find.byKey(const Key('revenue-page-next')));
      await tester.pumpAndSettle();
      expect(find.text('Page 2'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('revenue-filter-search')),
        '000001',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Page 1'),
        findsOneWidget,
        reason:
            'staying on page four of a result set with one page shows nothing '
            'and looks broken',
      );
    });
  });
}
