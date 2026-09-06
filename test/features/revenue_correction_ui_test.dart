/// The correction and void surfaces, on both platforms (Slice 10 §28–§32).
///
/// Two things are being held in place here.
///
/// **What is offered is decided by capability, never by a role name.** A widget that read
/// `role == 'accountant'` would be a second authorisation model the server never
/// consults, and the first thing to drift. The server refuses regardless (D-037); these
/// controls exist so the interface does not offer what would be refused.
///
/// **A voided sale offers nothing, and a conflict offers exactly one thing.** Nothing is
/// merged, nothing is auto-applied, and there is no "overwrite anyway".
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_detail_page.dart';
import 'package:krishna_mis/features/revenue/presentation/revenue_entry_page.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_actions.dart';
import 'package:krishna_mis/features/revenue/presentation/widgets/revenue_detail_panel.dart';

import '../support/test_session.dart';
import '../support/ui_harness.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _restaurant = 'cat-restaurant';
const _banquet = 'cat-banquet';
const _userA = 'user-a';
const _userB = 'user-b';

final _june15 = BusinessDate.of(2026, 6, 15);

/// The capability bundles that matter here, expressed the way the roles do.
Principal _principal({
  String user = _userA,
  Set<String> units = const {_ccr, _hki},
  Set<Capability> capabilities = const {
    Capability.revenueView,
    Capability.revenueCreate,
    Capability.revenueEdit,
    Capability.mastersView,
  },
}) => Principal(
  userId: user,
  grants: [
    for (final unit in units)
      for (final capability in capabilities)
        CapabilityGrant(capability, businessUnitId: unit),
  ],
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late RevenueRepository repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    repository = RevenueRepository(db);

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
      (_banquet, _hki, 'BANQUET', 'Banquet', 2),
    ]) {
      await db.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, ?, ?, 1, '2026-04-01T00:00:00.000Z')",
        [c.$1, c.$2, c.$3, c.$4, c.$5],
      );
    }

    await db.customStatement(
      'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
      'rate_basis_points, treatment, effective_from, input_basis, created_by, '
      "created_at, row_version, updated_at) "
      "VALUES ('rule-restaurant', '$_org', '$_restaurant', 500, 'inclusive', "
      "'2026-04-01', 'inclusive_total', 'u', '2026-04-01T00:00:00.000Z', 1, "
      "'2026-04-01T00:00:00.000Z')",
    );
    await db.customStatement(
      'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
      'rate_basis_points, treatment, effective_from, input_basis, created_by, '
      "created_at, row_version, updated_at) "
      "VALUES ('rule-banquet', '$_org', '$_banquet', 0, 'none', "
      "'2026-04-01', 'inclusive_total', 'u', '2026-04-01T00:00:00.000Z', 1, "
      "'2026-04-01T00:00:00.000Z')",
    );
    for (final user in const [_userA, _userB]) {
      for (final unit in const [_ccr, _hki]) {
        await db.customStatement(
          'INSERT OR REPLACE INTO revenue_config_snapshots (user_id, org_id, '
          'business_unit_id, status, datasets, generation, confirmed_at, '
          'updated_at) '
          "VALUES (?, '$_org', ?, 'complete', "
          "'bands,rules,statuses,subtypes', '900', ?, ?)",
          [
            user,
            unit,
            DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
            DateTime.now().toUtc().toIso8601String(),
          ],
        );
      }
    }
  });

  tearDown(() => db.close());

  /// Records a sale through the real repository, as the entry screen does.
  Future<RevenueEntry> recorded({
    String id = 'entry-1',
    String category = _restaurant,
    String unit = _ccr,
    int paise = 10000000,
    String actor = _userA,
    bool accepted = true,
  }) async {
    final draft = RevenueEntryDraft(
      id: id,
      businessUnitId: unit,
      revenueCategoryId: category,
      businessDate: _june15,
      capturedAt: DateTime.now().toUtc(),
      components: [
        RevenueComponentDraft(
          id: '$id-c0',
          enteredAmount: Money.fromPaise(paise),
        ),
      ],
    );
    final decision = await repository.evaluate(
      draft,
      authority: AuthoritySnapshot(
        userId: actor,
        orgId: _org,
        grants: [
          CapabilityGrant(Capability.revenueCreate, businessUnitId: unit),
        ],
        resolvedAt: DateTime.now().toUtc(),
      ),
    );
    final entry = await repository.createLocally(
      draft,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: actor,
      orgId: _org,
      mutationId: 'mut-$id',
      now: DateTime.now().toUtc(),
    );

    if (accepted) {
      await repository.reconcileAcceptance(
        RevenueAcceptance(
          entryId: id,
          rowVersion: 2,
          txnNumber: 'KI-REV-26-27-000001',
          financialYear: '2026-27',
          serverUpdatedAt: DateTime.now().toUtc(),
        ),
      );
      await db.customStatement(
        "UPDATE sync_outbox SET status = 'done' WHERE entity_id = ?",
        [id],
      );
    }
    return entry;
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Principal? principal,
    Size size = const Size(430, 932),
    ThemeData? theme,
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
        child: MaterialApp(theme: theme ?? AppTheme.mobile, home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('who is offered what (§6, §19, §31)', () {
    test(
      'revenue.edit reaches only your own; revenue.edit.all reaches anybody\'s',
      () {
        final entry = RevenueEntry(
          id: 'e',
          businessUnitId: _ccr,
          revenueCategoryId: _restaurant,
          businessDate: _june15,
          capturedAt: DateTime.now().toUtc(),
          createdBy: _userA,
          components: [
            RevenueComponent(
              id: 'c',
              enteredAmount: Money.fromPaise(100),
              enteredBasis: EnteredBasis.inclusiveTotal,
              gross: Money.fromPaise(100),
              tax: Money.zero,
              net: Money.fromPaise(100),
              taxRuleId: 'r',
              taxRateBasisPoints: 0,
              taxTreatment: TaxTreatment.none,
            ),
          ],
        );

        // The Manager bundle: their own, yes.
        expect(mayEditRevenue(_principal(user: _userA), entry), isTrue);
        // Somebody else's, no — the same split D-072a draws for expenses.
        expect(mayEditRevenue(_principal(user: _userB), entry), isFalse);
        // The Accountant bundle: anybody's, within the same window and period rules.
        expect(
          mayEditRevenue(
            _principal(
              user: _userB,
              capabilities: const {Capability.revenueEditAll},
            ),
            entry,
          ),
          isTrue,
        );
        // Scope is still scope: the capability is held for a property.
        expect(
          mayEditRevenue(
            _principal(
              user: _userB,
              units: {_hki},
              capabilities: const {Capability.revenueEditAll},
            ),
            entry,
          ),
          isFalse,
        );
      },
    );

    test('recording a sale does not entitle somebody to void it', () {
      final entry = RevenueEntry(
        id: 'e',
        businessUnitId: _ccr,
        revenueCategoryId: _restaurant,
        businessDate: _june15,
        capturedAt: DateTime.now().toUtc(),
        createdBy: _userA,
        components: [
          RevenueComponent(
            id: 'c',
            enteredAmount: Money.fromPaise(100),
            enteredBasis: EnteredBasis.inclusiveTotal,
            gross: Money.fromPaise(100),
            tax: Money.zero,
            net: Money.fromPaise(100),
            taxRuleId: 'r',
            taxRateBasisPoints: 0,
            taxTreatment: TaxTreatment.none,
          ),
        ],
      );
      expect(mayVoidRevenue(_principal(user: _userA), entry), isFalse);
      expect(
        mayVoidRevenue(
          _principal(
            user: _userA,
            capabilities: const {Capability.revenueVoid},
          ),
          entry,
        ),
        isTrue,
      );
    });

    uiTest('a user without either capability is offered neither control', (
      tester,
    ) async {
      await recorded();
      await pump(
        tester,
        const RevenueDetailPage(entryId: 'entry-1'),
        principal: _principal(
          capabilities: const {Capability.revenueView, Capability.mastersView},
        ),
      );

      expect(find.byKey(const Key('revenue-edit')), findsNothing);
      expect(find.byKey(const Key('revenue-void')), findsNothing);
    });

    uiTest('a user scoped to the other property is offered neither', (
      tester,
    ) async {
      await recorded();
      await pump(
        tester,
        const RevenueDetailPage(entryId: 'entry-1'),
        principal: _principal(
          units: {_hki},
          capabilities: const {
            Capability.revenueView,
            Capability.revenueEditAll,
            Capability.revenueVoid,
            Capability.mastersView,
          },
        ),
      );

      expect(find.byKey(const Key('revenue-edit')), findsNothing);
      expect(find.byKey(const Key('revenue-void')), findsNothing);
    });
  });

  group('the Android correction flow (§28)', () {
    uiTest('Edit opens the same form, on the sale, labelled as a correction', (
      tester,
    ) async {
      await recorded();
      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));

      await tester.tap(find.byKey(const Key('revenue-edit')));
      await tester.pumpAndSettle();

      // One form, two modes (D-072a). Not a second implementation of the arithmetic
      // behind company revenue.
      expect(find.byType(RevenueEntryPage), findsOneWidget);
      expect(find.text('Correct this sale'), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
      expect(find.text('Save sales'), findsNothing);
    });

    uiTest('a correction is queued and the figures are re-derived', (
      tester,
    ) async {
      await recorded();
      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));

      await tester.tap(find.byKey(const Key('revenue-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '2,10,000');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('revenue-save')));
      await tester.pumpAndSettle();

      final reloaded = await repository.load('entry-1');
      expect(reloaded!.gross.paise, 21000000);
      expect(reloaded.tax.paise, 1000000);
      // The number the server issued is the document's and survives the correction.
      expect(reloaded.txnNumber, 'KI-REV-26-27-000001');

      final queued = await db
          .customSelect(
            "SELECT op, base_row_version FROM sync_outbox "
            "WHERE entity_id = 'entry-1' AND status <> 'done'",
          )
          .get();
      expect(queued, hasLength(1));
      expect(queued.single.data['op'], 'update');
      // The version the form opened on, not one re-read at save time (§4).
      expect(queued.single.data['base_row_version'], 2);
    });
  });

  group('the Windows correction flow (§29)', () {
    uiTest('the panel offers the same controls at a desktop size', (
      tester,
    ) async {
      await recorded();
      await pump(
        tester,
        const Scaffold(body: RevenueDetailPanel(entryId: 'entry-1')),
        principal: _principal(
          capabilities: const {
            Capability.revenueView,
            Capability.revenueEditAll,
            Capability.revenueVoid,
            Capability.mastersView,
          },
        ),
        size: const Size(1366, 768),
        theme: AppTheme.desktop,
      );

      expect(find.byKey(const Key('revenue-edit')), findsOneWidget);
      expect(find.byKey(const Key('revenue-void')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('void (§21, §30)', () {
    uiTest('the reason is mandatory, and Void stays disabled without one', (
      tester,
    ) async {
      await recorded();
      await pump(
        tester,
        const RevenueDetailPage(entryId: 'entry-1'),
        principal: _principal(
          capabilities: const {
            Capability.revenueView,
            Capability.revenueVoid,
            Capability.mastersView,
          },
        ),
      );

      await tester.tap(find.byKey(const Key('revenue-void')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('revenue-void-dialog')), findsOneWidget);

      final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('revenue-void-confirm')),
      );
      expect(confirm.onPressed, isNull);

      // Whitespace is not a reason.
      await tester.enterText(
        find.byKey(const Key('revenue-void-reason')),
        '  ',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('revenue-void-confirm')))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('revenue-void-reason')),
        'entered twice',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('revenue-void-confirm')))
            .onPressed,
        isNotNull,
      );
    });

    uiTest('voiding keeps the sale, its reason and its components', (
      tester,
    ) async {
      await recorded();
      await pump(
        tester,
        const RevenueDetailPage(entryId: 'entry-1'),
        principal: _principal(
          capabilities: const {
            Capability.revenueView,
            Capability.revenueVoid,
            Capability.mastersView,
          },
        ),
      );

      await tester.tap(find.byKey(const Key('revenue-void')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('revenue-void-reason')),
        'entered twice',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('revenue-void-confirm')));
      await tester.pumpAndSettle();

      final reloaded = await repository.load('entry-1');
      // Void, never delete (D-006).
      expect(reloaded, isNotNull);
      expect(reloaded!.components, isNotEmpty);
      expect(reloaded.voidReason, 'entered twice');
    });

    uiTest('a voided sale offers neither control, and says why', (
      tester,
    ) async {
      await recorded();
      await repository.voidLocally(
        entryId: 'entry-1',
        reason: 'entered twice',
        actorUserId: _userA,
        baseRowVersion: 2,
        mutationId: 'mut-void',
        now: DateTime.now().toUtc(),
      );

      await pump(
        tester,
        const RevenueDetailPage(entryId: 'entry-1'),
        principal: _principal(
          capabilities: const {
            Capability.revenueView,
            Capability.revenueEditAll,
            Capability.revenueVoid,
            Capability.mastersView,
          },
        ),
      );

      expect(find.byKey(const Key('revenue-edit')), findsNothing);
      expect(find.byKey(const Key('revenue-void')), findsNothing);
      expect(find.byKey(const Key('revenue-voided-note')), findsOneWidget);
      // The reason stays with the document, for ever.
      expect(find.text('entered twice'), findsOneWidget);
      expect(find.byKey(const Key('revenue-void-when')), findsOneWidget);
    });
  });

  group('conflict (§25, §26, §27)', () {
    uiTest('a conflict offers Review latest and nothing that merges', (
      tester,
    ) async {
      await recorded();
      await db.customStatement(
        "UPDATE sync_outbox SET status = 'conflict' WHERE entity_id = 'entry-1'",
      );
      await db.customStatement(
        "UPDATE revenue_entries SET pending_mutation_id = 'mut-entry-1' "
        "WHERE id = 'entry-1'",
      );

      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));

      expect(find.byKey(const Key('revenue-conflict-banner')), findsOneWidget);
      expect(
        find.byKey(const Key('revenue-conflict-review-latest')),
        findsOneWidget,
      );
      // No overwrite-anyway, anywhere.
      expect(find.textContaining('Overwrite'), findsNothing);
      expect(find.textContaining('overwrite anyway'), findsNothing);
    });

    uiTest('with no backend the conflict path says so and changes nothing', (
      tester,
    ) async {
      await recorded();
      await db.customStatement(
        "UPDATE sync_outbox SET status = 'conflict' WHERE entity_id = 'entry-1'",
      );
      await db.customStatement(
        "UPDATE revenue_entries SET pending_mutation_id = 'mut-entry-1' "
        "WHERE id = 'entry-1'",
      );
      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));

      await tester.tap(find.byKey(const Key('revenue-conflict-review-latest')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('revenue-conflict-offline')), findsOneWidget);
      // Nothing was replaced, and the attempt is untouched.
      expect((await repository.load('entry-1'))!.gross.paise, 10000000);
    });

    uiTest('a rejected entry is not dressed up as a conflict', (tester) async {
      await recorded();
      await db.customStatement(
        "UPDATE sync_outbox SET status = 'rejected' WHERE entity_id = 'entry-1'",
      );
      await db.customStatement(
        "UPDATE revenue_entries SET pending_mutation_id = 'mut-entry-1' "
        "WHERE id = 'entry-1'",
      );
      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));

      // Terminal, and there is nothing for a person to choose between — so no
      // Review latest is offered (§27).
      expect(find.byKey(const Key('revenue-rejected-banner')), findsOneWidget);
      expect(find.byKey(const Key('revenue-conflict-banner')), findsNothing);
      expect(
        find.byKey(const Key('revenue-conflict-review-latest')),
        findsNothing,
      );
    });
  });

  group('the surface does not grow into later slices (§49)', () {
    // Attachments were on this list until Slice 11 built them, and the list is edited
    // rather than deleted: reporting is still ahead. Removing the attachment half
    // matters — the original assertion searched for the word "Attach", which the
    // evidence surface does not use, so leaving it would have gone on passing while
    // saying nothing. A check that passes for the wrong reason is the shape this project
    // keeps recording (D-068, D-071, D-077).
    uiTest('no reporting on the detail surface', (tester) async {
      await recorded();
      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));

      for (final absent in const [
        'Profit',
        'Net Sales',
        'Export',
        'Operating',
      ]) {
        expect(
          find.textContaining(absent),
          findsNothing,
          reason: '$absent belongs to Slice 12 or Phase 5',
        );
      }
    });

    uiTest('evidence is on the detail surface, and it is Slice 11', (
      tester,
    ) async {
      await recorded();
      await pump(tester, const RevenueDetailPage(entryId: 'entry-1'));

      expect(find.byKey(const Key('revenue-evidence')), findsOneWidget);
      expect(find.text('EVIDENCE'), findsOneWidget);
    });
  });
}
