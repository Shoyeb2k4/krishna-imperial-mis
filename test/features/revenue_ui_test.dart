/// The Android revenue surfaces, driven as an operator drives them.
///
/// The assertions that matter are the ones about money and about what the screen is
/// willing to claim: a GST figure extracted rather than added, an untaxed category that
/// is never labelled as GST-inclusive, a Save button that cannot be pressed twice, and a
/// retained attempt that does not appear in a list somebody else is looking at.
///
/// Everything here goes through the real repository against a real (in-memory) database
/// and the real providers. Nothing stubs the create path — that is the whole point, and
/// the lesson D-077 paid for.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_entry_page.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_recent_page.dart';

import '../support/test_session.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _restaurant = 'cat-restaurant';
const _nandbhog = 'cat-nandbhog';
const _room = 'cat-room';
const _banquet = 'cat-banquet';
const _userA = 'user-a';
const _userB = 'user-b';

final _june15 = BusinessDate.of(2026, 6, 15);

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

  setUp(() async {
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
      (_restaurant, _ccr, 'RESTAURANT', 'Restaurant', 1),
      (_nandbhog, _ccr, 'NANDBHOG', 'Nandbhog', 2),
      (_room, _hki, 'ROOM', 'Room', 1),
      (_banquet, _hki, 'BANQUET', 'Banquet', 2),
    ]) {
      await db.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, ?, ?, 1, '2026-04-01T00:00:00.000Z')",
        [c.$1, c.$2, c.$3, c.$4, c.$5],
      );
    }
  });

  tearDown(() => db.close());

  Future<void> cacheRule({
    required String id,
    required String category,
    int rateBp = 500,
    String treatment = 'inclusive',
    String? basis = 'inclusive_total',
    String? bandId,
  }) => db.customStatement(
    'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
    'rate_basis_points, treatment, effective_from, input_basis, value_band_id, '
    'created_by, created_at, row_version, updated_at) '
    "VALUES (?, '$_org', ?, ?, ?, '2026-04-01', ?, ?, 'u', "
    "'2026-04-01T00:00:00.000Z', 1, '2026-04-01T00:00:00.000Z')",
    [id, category, rateBp, treatment, basis, bandId],
  );

  Future<void> markComplete({
    String user = _userA,
    String unit = _ccr,
    Duration age = const Duration(hours: 1),
  }) => db.customStatement(
    'INSERT OR REPLACE INTO revenue_config_snapshots (user_id, org_id, '
    'business_unit_id, status, datasets, generation, confirmed_at, updated_at) '
    "VALUES (?, '$_org', ?, 'complete', 'bands,rules,statuses,subtypes', '900', "
    '?, ?)',
    [
      user,
      unit,
      DateTime.now().toUtc().subtract(age).toIso8601String(),
      DateTime.now().toUtc().toIso8601String(),
    ],
  );

  /// The verified FY 2026-27 baseline, cached and fresh for both properties.
  Future<void> baseline({
    String user = _userA,
    Duration age = const Duration(hours: 1),
  }) async {
    await cacheRule(id: 'rule-restaurant', category: _restaurant);
    await cacheRule(id: 'rule-nandbhog', category: _nandbhog);
    await cacheRule(id: 'rule-room', category: _room);
    await cacheRule(
      id: 'rule-banquet',
      category: _banquet,
      rateBp: 0,
      treatment: 'none',
    );
    await markComplete(user: user, unit: _ccr, age: age);
    await markComplete(user: user, unit: _hki, age: age);
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Principal? principal,
  }) async {
    final actor = principal ?? _principal();
    await tester.binding.setSurfaceSize(const Size(430, 932));
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
        child: MaterialApp(theme: AppTheme.mobile, home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  /// Types into the nth amount field. `AmountField` renders its label above the box
  /// rather than inside the decoration, so the fields are addressed by position.
  Future<void> typeAmount(
    WidgetTester tester,
    String value, {
    int index = 0,
  }) async {
    await tester.enterText(find.byType(TextField).at(index), value);
    await tester.pumpAndSettle();
  }

  group('choosing where the money came from', () {
    testWidgets('a two-property user is asked which one', (tester) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());

      expect(find.byKey(const Key('revenue-unit-CCR')), findsOneWidget);
      expect(find.byKey(const Key('revenue-unit-HKI')), findsOneWidget);
    });

    testWidgets('a one-property user is not asked at all', (tester) async {
      await baseline();
      await pump(
        tester,
        const RevenueEntryPage(),
        principal: _principal(units: {_ccr}),
      );

      expect(
        find.byKey(const Key('revenue-unit-CCR')),
        findsNothing,
        reason: 'a choice with one answer is not a choice',
      );
      // And the categories for that property are already offered.
      expect(
        find.byKey(const Key('revenue-category-RESTAURANT')),
        findsOneWidget,
      );
    });

    testWidgets('only the chosen property\'s categories are offered', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');

      expect(
        find.byKey(const Key('revenue-category-RESTAURANT')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('revenue-category-NANDBHOG')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('revenue-category-ROOM')), findsNothing);
      expect(find.byKey(const Key('revenue-category-BANQUET')), findsNothing);
    });

    testWidgets('changing property clears the category selection', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');
      expect(find.byKey(const Key('revenue-breakdown-empty')), findsOneWidget);

      await choose(tester, 'revenue-unit-HKI');

      expect(
        find.byKey(const Key('revenue-breakdown-empty')),
        findsNothing,
        reason: 'no category is selected, so there is nothing to break down',
      );
      expect(find.byKey(const Key('revenue-category-ROOM')), findsOneWidget);
    });

    testWidgets('a user with no permitted property is told so', (tester) async {
      await baseline();
      await pump(
        tester,
        const RevenueEntryPage(),
        principal: Principal(userId: _userA, grants: const []),
      );

      expect(find.byKey(const Key('revenue-entry-no-scope')), findsOneWidget);
      expect(find.byKey(const Key('revenue-save')), findsNothing);
    });
  });

  group('the four verified categories', () {
    testWidgets('Restaurant extracts GST rather than adding it', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');
      await typeAmount(tester, '100000');

      expect(find.text('₹1,00,000'), findsWidgets);
      expect(find.text('₹4,761.90'), findsOneWidget);
      expect(find.text('₹95,238.10'), findsOneWidget);
      expect(find.text('GST included'), findsOneWidget);
      expect(
        find.text('₹1,05,000'),
        findsNothing,
        reason: '5% is inside the figure, never added on top (D-088)',
      );
    });

    testWidgets('Nandbhog computes the same way and stays its own category', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-NANDBHOG');
      await typeAmount(tester, '12500');

      expect(find.text('₹595.24'), findsOneWidget);
      expect(find.text('₹11,904.76'), findsOneWidget);
    });

    testWidgets('Room is one plain field today, with no invented band picker', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-HKI');
      await choose(tester, 'revenue-category-ROOM');

      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.byKey(const Key('revenue-band-label-null')),
        findsNothing,
        reason:
            'the architecture supports bands; the configuration does not use one, '
            'and a picker for a choice nobody has to make is noise',
      );

      await typeAmount(tester, '65000');
      expect(find.text('₹3,095.24'), findsOneWidget);
      expect(find.text('₹61,904.76'), findsOneWidget);
    });

    testWidgets('Banquet says No GST and never claims tax is inside', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-HKI');
      await choose(tester, 'revenue-category-BANQUET');

      // The label follows the treatment as well as the basis (D-097).
      // `AmountField` renders its label as an uppercase overline above the box, which is
      // the established convention on both entry screens.
      expect(find.text('AMOUNT BILLED TO THE CUSTOMER'), findsOneWidget);
      expect(find.text('CUSTOMER TOTAL (INCL. GST)'), findsNothing);

      await typeAmount(tester, '40343');

      expect(find.byKey(const Key('revenue-preview-no-gst')), findsOneWidget);
      expect(find.text('No GST'), findsOneWidget);
      expect(
        find.text('₹40,343'),
        findsWidgets,
        reason: 'net equals the entered amount when no tax applies',
      );
    });

    testWidgets('two configured bands render two labelled fields', (
      tester,
    ) async {
      // A synthetic configuration, because no Room threshold has been verified and
      // inventing one to make a test convenient would be inventing a business fact.
      await db.customStatement(
        'INSERT INTO revenue_value_bands (id, org_id, revenue_category_id, '
        'code, label, floor_minor, ceiling_minor, row_version, updated_at) '
        "VALUES ('b1', '$_org', ?, 'LOWER', 'Up to 7500', 0, 750000, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [_room],
      );
      await db.customStatement(
        'INSERT INTO revenue_value_bands (id, org_id, revenue_category_id, '
        'code, label, floor_minor, ceiling_minor, row_version, updated_at) '
        "VALUES ('b2', '$_org', ?, 'UPPER', 'Above 7500', 750000, NULL, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [_room],
      );
      await cacheRule(id: 'r-lower', category: _room, bandId: 'b1');
      await cacheRule(
        id: 'r-upper',
        category: _room,
        rateBp: 1200,
        bandId: 'b2',
      );
      await cacheRule(id: 'rule-restaurant', category: _restaurant);
      await markComplete(unit: _ccr);
      await markComplete(unit: _hki);

      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-HKI');
      await choose(tester, 'revenue-category-ROOM');

      expect(
        find.byType(TextField),
        findsNWidgets(2),
        reason: 'the form shape came from the configuration, with no release',
      );
      expect(find.text('Up to 7500'), findsOneWidget);
      expect(find.text('Above 7500'), findsOneWidget);
    });
  });

  group('the business date', () {
    testWidgets(
      'is shown, and is the trading day rather than the calendar one',
      (tester) async {
        await baseline();
        await pump(tester, const RevenueEntryPage());

        expect(find.byKey(const Key('revenue-business-date')), findsOneWidget);
        expect(
          find.text('15 June 2026'),
          findsOneWidget,
          reason: 'written out, not an ISO string and not a debug toString',
        );
        expect(
          find.text('This is the trading day these sales belong to.'),
          findsOneWidget,
          reason:
              'the fixture date differs from the device calendar, so the screen '
              'explains itself rather than looking wrong',
        );
      },
    );
  });

  group('configuration freshness (D-112)', () {
    testWidgets('fresh configuration warns about nothing', (tester) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');

      expect(find.byKey(const Key('revenue-refusal')), findsNothing);
    });

    testWidgets('expired configuration refuses, and offers a refresh', (
      tester,
    ) async {
      await baseline(age: const Duration(hours: 25));
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');

      expect(find.byKey(const Key('revenue-refusal')), findsOneWidget);
      expect(find.textContaining('more than 24 hours old'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsNothing,
        reason:
            'there is nothing to type into until the configuration is usable',
      );
    });

    testWidgets(
      'a never-synchronised device says so, not that tax is unconfigured',
      (tester) async {
        await cacheRule(id: 'rule-restaurant', category: _restaurant);
        // No completeness record at all.
        await pump(tester, const RevenueEntryPage());
        await choose(tester, 'revenue-unit-CCR');
        await choose(tester, 'revenue-category-RESTAURANT');

        expect(find.textContaining('not yet received'), findsOneWidget);
        expect(
          find.textContaining('No tax rule configured'),
          findsNothing,
          reason:
              'that would be a statement about the organisation, made on the '
              'strength of a network condition (D-106)',
        );
      },
    );

    testWidgets('a revoked scope says the access changed', (tester) async {
      await baseline();
      await db.customStatement(
        "UPDATE revenue_config_snapshots SET status = 'revoked', datasets = ''",
      );

      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');

      expect(
        find.textContaining('access to this property changed'),
        findsOneWidget,
      );
    });

    testWidgets('no refusal message leaks an internal name', (tester) async {
      await baseline(age: const Duration(hours: 25));
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');

      for (final forbidden in const [
        'KM0',
        'D-112',
        'snapshot',
        'SQL',
        'Exception',
        'revenue_config_snapshots',
      ]) {
        expect(
          find.textContaining(forbidden),
          findsNothing,
          reason: 'a user must never be shown "$forbidden"',
        );
      }
    });
  });

  group('missing configuration is a gap, not a zero rate', () {
    testWidgets('no rule for the category refuses rather than showing ₹0 GST', (
      tester,
    ) async {
      await cacheRule(id: 'rule-restaurant', category: _restaurant);
      await markComplete(unit: _ccr);
      await markComplete(unit: _hki);

      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-HKI');
      await choose(tester, 'revenue-category-ROOM');

      expect(find.textContaining('No tax rule configured'), findsOneWidget);
      expect(find.byKey(const Key('revenue-breakdown')), findsNothing);
    });
  });

  group('saving', () {
    testWidgets('a valid sale saves offline and reports pending sync', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');
      await typeAmount(tester, '100000');

      await tester.tap(find.byKey(const Key('revenue-save')));
      await tester.pumpAndSettle();

      final entries = await db
          .customSelect('SELECT COUNT(*) AS n FROM revenue_entries')
          .getSingle();
      final queued = await db
          .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
          .getSingle();
      expect(entries.data['n'], 1);
      expect(
        queued.data['n'],
        1,
        reason: 'written and queued in one transaction',
      );

      final component = await db
          .customSelect(
            'SELECT gross_amount_minor, tax_amount_minor, net_amount_minor '
            'FROM revenue_components',
          )
          .getSingle();
      expect(
        component.data['tax_amount_minor'],
        476190,
        reason: 'exactly the figure the preview showed before Save',
      );
      expect(component.data['net_amount_minor'], 9523810);
    });

    testWidgets('Save is disabled until every field is readable', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('revenue-save')),
      );
      expect(button.onPressed, isNull);

      await typeAmount(tester, '5000');
      final enabled = tester.widget<FilledButton>(
        find.byKey(const Key('revenue-save')),
      );
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets('a double tap records one sale, not two', (tester) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');
      await typeAmount(tester, '100000');

      // Two presses with no settle between them: the second lands while the first
      // transaction is still running, which is exactly what a slow phone produces.
      await tester.tap(find.byKey(const Key('revenue-save')));
      await tester.pump();
      final second = find.byKey(const Key('revenue-save'));
      if (second.evaluate().isNotEmpty) {
        await tester.tap(second, warnIfMissed: false);
      }
      await tester.pumpAndSettle();

      final entries = await db
          .customSelect('SELECT COUNT(*) AS n FROM revenue_entries')
          .getSingle();
      expect(
        entries.data['n'],
        1,
        reason: 'one act, one financial record — and one mutation id behind it',
      );
    });

    testWidgets(
      'an expired configuration refuses the save and writes nothing',
      (tester) async {
        await baseline();
        await pump(tester, const RevenueEntryPage());
        await choose(tester, 'revenue-unit-CCR');
        await choose(tester, 'revenue-category-RESTAURANT');
        await typeAmount(tester, '100000');

        // The configuration goes stale between typing and pressing Save.
        await db.customStatement(
          'UPDATE revenue_config_snapshots SET confirmed_at = ?',
          [
            DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 30))
                .toIso8601String(),
          ],
        );

        await tester.tap(find.byKey(const Key('revenue-save')));
        await tester.pumpAndSettle();

        final entries = await db
            .customSelect('SELECT COUNT(*) AS n FROM revenue_entries')
            .getSingle();
        expect(entries.data['n'], 0);
        expect(find.byKey(const Key('revenue-refusal')), findsOneWidget);
        expect(
          find.byKey(const Key('revenue-refresh-configuration')),
          findsOneWidget,
          reason:
              'a refresh is what would change this answer, so it is offered',
        );
      },
    );
  });

  group('recent sales', () {
    testWidgets('an empty list says so rather than showing nothing', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueRecentPage());

      expect(find.byKey(const Key('revenue-recent-empty')), findsOneWidget);
    });

    testWidgets('a saved sale appears, pending, with no invented number', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');
      await typeAmount(tester, '100000');
      await tester.tap(find.byKey(const Key('revenue-save')));
      await tester.pumpAndSettle();

      await pump(tester, const RevenueRecentPage());

      expect(find.byKey(const Key('revenue-recent-list')), findsOneWidget);
      expect(find.text('Restaurant'), findsOneWidget);
      expect(find.text('Pending Sync'), findsOneWidget);
      expect(
        find.textContaining('KI-REV-'),
        findsNothing,
        reason: 'the server issues the number; the client never invents one',
      );
    });

    testWidgets('reconciliation shows the KI-REV number and Synced', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');
      await typeAmount(tester, '100000');
      await tester.tap(find.byKey(const Key('revenue-save')));
      await tester.pumpAndSettle();

      // What the worker does when the server accepts.
      await db.customStatement(
        "UPDATE revenue_entries SET txn_number = 'KI-REV-26-27-000001', "
        "financial_year = '2026-27', pending_mutation_id = NULL",
      );
      await db.customStatement("UPDATE sync_outbox SET status = 'done'");

      await pump(tester, const RevenueRecentPage());

      expect(find.textContaining('KI-REV-26-27-000001'), findsOneWidget);
      expect(find.text('Synced'), findsOneWidget);
    });

    testWidgets('a conflict reads as review, never as a repriced amount', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');
      await typeAmount(tester, '100000');
      await tester.tap(find.byKey(const Key('revenue-save')));
      await tester.pumpAndSettle();

      await db.customStatement("UPDATE sync_outbox SET status = 'conflict'");

      await pump(tester, const RevenueRecentPage());

      expect(
        find.textContaining('tax configuration changed'),
        findsOneWidget,
        reason:
            'a financial disagreement is explained, never silently resolved',
      );
      // The figures the operator approved are still the ones displayed. Nothing has
      // been repriced to whatever the server would have computed (D-114).
      expect(find.text('₹1,00,000.00'), findsOneWidget);
      expect(find.text('Net ₹95,238.10'), findsOneWidget);
    });

    testWidgets('a quarantined attempt is absent from the ordinary list', (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');
      await typeAmount(tester, '100000');
      await tester.tap(find.byKey(const Key('revenue-save')));
      await tester.pumpAndSettle();

      // What a confirmed revocation does: stamped, not destroyed (D-070).
      await db.customStatement(
        'UPDATE revenue_entries SET scope_revoked_at = ?',
        [DateTime.now().toUtc().toIso8601String()],
      );

      await pump(tester, const RevenueRecentPage());

      expect(find.byKey(const Key('revenue-recent-empty')), findsOneWidget);
      final still = await db
          .customSelect('SELECT COUNT(*) AS n FROM revenue_entries')
          .getSingle();
      expect(still.data['n'], 1, reason: 'hidden, and not deleted');
    });

    testWidgets("another user does not see the first user's work", (
      tester,
    ) async {
      await baseline();
      await pump(tester, const RevenueEntryPage());
      await choose(tester, 'revenue-unit-CCR');
      await choose(tester, 'revenue-category-RESTAURANT');
      await typeAmount(tester, '100000');
      await tester.tap(find.byKey(const Key('revenue-save')));
      await tester.pumpAndSettle();

      // Quarantined by a revocation, then a different person signs in on the same
      // installation — the shared back-office workstation D-074 exists for.
      await db.customStatement(
        'UPDATE revenue_entries SET scope_revoked_at = ?',
        [DateTime.now().toUtc().toIso8601String()],
      );

      await pump(
        tester,
        const RevenueRecentPage(),
        principal: _principal(user: _userB),
      );

      expect(find.byKey(const Key('revenue-recent-empty')), findsOneWidget);
      expect(find.text('Restaurant'), findsNothing);
    });
  });
}
