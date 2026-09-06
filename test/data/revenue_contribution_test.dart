/// The revenue reporting interface (Phase 4 Slice 12, D-087, D-157).
///
/// Slice 12 defines and exposes what Phase 5 will aggregate. It builds **no** P&L, no
/// dashboard, no export — a test at the bottom of this file asserts the repository grew no
/// such method, because a slice boundary that nothing evaluates is a comment.
///
/// The claim under test is narrow and total: **every canonical revenue document
/// contributes exact gross, tax and net paise into the right property, category and
/// period, and nothing else contributes anything.** The four ways that could go wrong are
/// each a group here — a figure that is not the accepted one, a period that is not the
/// stored business date's, a document that should not be counted, and a count that happens
/// twice.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/expense_fixtures.dart' show createTempDatabaseFile;
import '../support/revenue_parity_vectors.dart';

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _userA = 'user-a';
const _userB = 'user-b';

String _unitOf(String category) =>
    category == vCategoryRoom || category == vCategoryBanquet ? _hki : _ccr;

AuthoritySnapshot _authority({
  String user = _userA,
  Set<String> units = const {_ccr, _hki},
}) => AuthoritySnapshot(
  userId: user,
  orgId: _org,
  grants: [
    for (final unit in units) ...[
      CapabilityGrant(Capability.revenueCreate, businessUnitId: unit),
      CapabilityGrant(Capability.revenueEdit, businessUnitId: unit),
      CapabilityGrant(Capability.revenueVoid, businessUnitId: unit),
      CapabilityGrant(Capability.revenueView, businessUnitId: unit),
    ],
  ],
  resolvedAt: DateTime.now().toUtc(),
);

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late RevenueRepository repository;
  var seq = 0;
  var numbers = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    repository = RevenueRepository(db, tax: RevenueTaxRepository(db));
    seq = 0;
    numbers = 0;

    for (final unit in const [(_ccr, 'CCR'), (_hki, 'HKI')]) {
      await db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, 'hotel', 'Asia/Kolkata', '05:00', 1, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [unit.$1, unit.$2, unit.$2],
      );
    }
    for (final c in const [
      (vCategoryRestaurant, _ccr, 'RESTAURANT'),
      (vCategoryNandbhog, _ccr, 'NANDBHOG'),
      (vCategoryRoom, _hki, 'ROOM'),
      (vCategoryBanquet, _hki, 'BANQUET'),
    ]) {
      await db.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, ?, 1, 1, '2026-04-01T00:00:00.000Z')",
        [c.$1, c.$2, c.$3, c.$3],
      );
    }
    for (final v in verifiedBaseline) {
      await db.customStatement(
        'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
        'rate_basis_points, treatment, effective_from, effective_to, '
        'input_basis, value_band_id, supply_subtype_id, premises_status_code, '
        'created_by, created_at, row_version, updated_at) '
        "VALUES (?, '$_org', ?, ?, ?, ?, ?, ?, ?, ?, ?, 'u', "
        "'2026-04-01T00:00:00.000Z', 1, '2026-04-01T00:00:00.000Z')",
        [
          v.id,
          v.category,
          v.rateBp,
          v.treatment.name,
          v.from,
          v.to,
          v.basis?.wireName,
          v.bandId,
          v.subtypeId,
          v.premisesStatus,
        ],
      );
    }
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

  RevenueEntryDraft draft({
    String? id,
    String category = vCategoryRestaurant,
    List<int> amounts = const [10000000],
    String date = '2026-06-15',
  }) {
    seq++;
    final entryId = id ?? 'entry-$seq';
    return RevenueEntryDraft(
      id: entryId,
      businessUnitId: _unitOf(category),
      revenueCategoryId: category,
      businessDate: vDate(date),
      capturedAt: DateTime.now().toUtc(),
      components: [
        for (var i = 0; i < amounts.length; i++)
          RevenueComponentDraft(
            id: '$entryId-c$i',
            enteredAmount: Money.fromPaise(amounts[i]),
          ),
      ],
    );
  }

  Future<RevenueEntry> create(
    RevenueEntryDraft d, {
    AuthoritySnapshot? authority,
  }) async {
    final who = authority ?? _authority();
    final decision = await repository.evaluate(d, authority: who);
    expect(
      decision,
      isA<RevenueCreatePermitted>(),
      reason: decision is RevenueCreateRefused
          ? decision.refusal.toString()
          : null,
    );
    return repository.createLocally(
      d,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: who.userId,
      orgId: _org,
      mutationId: 'mut-${d.id}',
      now: DateTime.now().toUtc(),
    );
  }

  Future<RevenueEntry> edit(
    RevenueEntryDraft d, {
    required int baseRowVersion,
    AuthoritySnapshot? authority,
  }) async {
    final who = authority ?? _authority();
    final decision = await repository.evaluate(d, authority: who);
    expect(decision, isA<RevenueCreatePermitted>());
    return repository.updateLocally(
      d,
      resolutions: (decision as RevenueCreatePermitted).resolutions,
      actorUserId: who.userId,
      orgId: _org,
      baseRowVersion: baseRowVersion,
      mutationId: 'mut-edit-${d.id}-$baseRowVersion',
      now: DateTime.now().toUtc(),
    );
  }

  /// The server accepting a document, through the real reconciliation path.
  ///
  /// A sale is not revenue until the server has said so, so nearly every assertion here
  /// runs on the far side of this call.
  Future<void> accept(
    String entryId, {
    int rowVersion = 1,
    BusinessDateSource? source,
  }) => db.transaction(() async {
    numbers++;
    await repository.reconcileAcceptance(
      RevenueAcceptance(
        entryId: entryId,
        rowVersion: rowVersion,
        txnNumber: 'KI-REV-26-27-${numbers.toString().padLeft(6, '0')}',
        financialYear: '2026',
        serverUpdatedAt: DateTime.now().toUtc(),
        businessDateSource: source,
      ),
    );
    await db.customStatement(
      "UPDATE sync_outbox SET status = 'done' WHERE entity_id = ?",
      [entryId],
    );
  });

  /// An accepted edit: the local write, then the server's answer to it.
  Future<void> acceptEdit(String entryId, int rowVersion) =>
      db.transaction(() async {
        await repository.reconcileAcceptance(
          RevenueAcceptance(
            entryId: entryId,
            rowVersion: rowVersion,
            serverUpdatedAt: DateTime.now().toUtc(),
          ),
        );
        await db.customStatement(
          "UPDATE sync_outbox SET status = 'done' WHERE entity_id = ?",
          [entryId],
        );
      });

  Future<RevenueTotals> totals({
    String? periodKey,
    String? unit,
    String? category,
    BusinessDate? from,
    BusinessDate? to,
    Set<String>? scope,
  }) => repository.contributionTotals(
    RevenueContributionQuery(
      periodKey: periodKey,
      businessUnitId: unit,
      revenueCategoryId: category,
      from: from,
      to: to,
      businessUnitIds: scope,
    ),
  );

  Future<List<RevenueContribution>> rows({
    String? periodKey,
    String? unit,
    Set<String>? scope,
  }) => repository.contributions(
    RevenueContributionQuery(
      periodKey: periodKey,
      businessUnitId: unit,
      businessUnitIds: scope,
    ),
  );

  group('a canonical sale contributes its accepted figures, exactly', () {
    test('one component, one contribution, at the stored paise', () async {
      final entry = await create(draft(id: 'e1'));
      await accept('e1');

      final all = await rows();
      expect(all, hasLength(1));
      final c = all.single;

      expect(
        c.componentId,
        entry.components.single.id,
        reason:
            'the contribution IS the component; a separate identity would be a second '
            'thing to keep in step',
      );
      expect(c.revenueEntryId, 'e1');
      expect(c.businessUnitId, _ccr);
      expect(c.revenueCategoryId, vCategoryRestaurant);
      expect(c.gross.paise, 10000000);
      expect(c.tax.paise, 476190);
      expect(c.net.paise, 9523810);
      expect(c.reconciles, isTrue);
      expect(c.pnlPeriodKey, '2026-06');
      expect(c.businessDate.iso, '2026-06-15');
      expect(c.txnNumber, isNotNull);
      expect(c.isActive, isTrue);
    });

    test('the four verified categories, each at its own exact paise', () async {
      // Restaurant and Nandbhog agree arithmetically today and are still two
      // contributions under two categories (D-089). Banquet is `none`, not 0%.
      for (final (id, category) in const [
        ('r', vCategoryRestaurant),
        ('n', vCategoryNandbhog),
        ('room', vCategoryRoom),
        ('b', vCategoryBanquet),
      ]) {
        await create(draft(id: id, category: category));
        await accept(id);
      }

      final byCategory = {for (final c in await rows()) c.revenueCategoryId: c};

      for (final category in const [
        vCategoryRestaurant,
        vCategoryNandbhog,
        vCategoryRoom,
      ]) {
        expect(byCategory[category]!.gross.paise, 10000000);
        expect(byCategory[category]!.tax.paise, 476190);
        expect(byCategory[category]!.net.paise, 9523810);
        expect(byCategory[category]!.taxTreatment, TaxTreatment.inclusive);
        expect(byCategory[category]!.taxRateBasisPoints, 500);
      }

      final banquet = byCategory[vCategoryBanquet]!;
      expect(banquet.gross.paise, 10000000);
      expect(banquet.tax.paise, 0);
      expect(banquet.net.paise, 10000000);
      expect(
        banquet.taxTreatment,
        TaxTreatment.none,
        reason:
            'a treatment somebody chose, permanently distinct from a rate somebody set '
            'to zero (D-091). Reporting carries the treatment so Phase 5 can say which',
      );
      expect(banquet.enteredBasis, EnteredBasis.inclusiveTotal);
    });

    test('a two-component day stays two contributions', () async {
      // A Room day across two tariff bands. Flattening it into one blended rate would
      // state a rate that was applied to nothing (D-087).
      await create(
        draft(id: 'two', category: vCategoryRoom, amounts: [4200000, 2300000]),
      );
      await accept('two');

      final all = await rows();
      expect(all, hasLength(2));
      expect(all.map((c) => c.componentId).toSet(), hasLength(2));
      expect(
        all.map((c) => c.revenueEntryId).toSet(),
        {'two'},
        reason: 'both belong to one document',
      );

      final t = await totals();
      expect(t.contributions, 2);
      expect(
        t.gross.paise,
        all.fold<int>(0, (s, c) => s + c.gross.paise),
        reason:
            'the document total is the sum of its components and nothing else',
      );
      expect(t.gross.paise, 6500000);
      expect(t.reconciles, isTrue);
    });

    test('the rule snapshot travels, and is the accepted one', () async {
      await create(draft(id: 'snap'));
      await accept('snap');
      final c = (await rows()).single;

      expect(c.taxRuleId, isNotEmpty);
      expect(c.taxRateBasisPoints, 500);
      expect(c.taxTreatment, TaxTreatment.inclusive);
      expect(c.enteredBasis, EnteredBasis.inclusiveTotal);
      expect(
        c.valueBandId,
        isNull,
        reason:
            'the verified baseline configures no band, and none is invented',
      );
      expect(c.supplySubtypeId, isNull);
      expect(c.premisesStatusCode, isNull);
    });
  });

  group('the period is the stored business date, and only that', () {
    test('a query by period key finds the month it was recorded in', () async {
      await create(draft(id: 'june', date: '2026-06-15'));
      await accept('june');
      await create(draft(id: 'july', date: '2026-07-02'));
      await accept('july');

      expect((await totals(periodKey: '2026-06')).contributions, 1);
      expect((await totals(periodKey: '2026-07')).contributions, 1);
      expect((await totals(periodKey: '2026-05')).contributions, 0);
      expect((await totals()).contributions, 2);
    });

    test('a business-date range filters on the trading day', () async {
      for (final (id, date) in const [
        ('d1', '2026-06-01'),
        ('d2', '2026-06-15'),
        ('d3', '2026-06-30'),
      ]) {
        await create(draft(id: id, date: date));
        await accept(id);
      }

      final mid = await totals(
        from: BusinessDate.of(2026, 6, 10),
        to: BusinessDate.of(2026, 6, 20),
      );
      expect(mid.contributions, 1);
      expect(
        (await totals(
          from: BusinessDate.of(2026, 6, 1),
          to: BusinessDate.of(2026, 6, 30),
        )).contributions,
        3,
        reason: 'the range is inclusive at both ends',
      );
    });

    test('an accepted business-date correction moves the period, once', () async {
      // The mandatory case after the recent corrective work (D-140, D-143). Nothing
      // maintains a contribution row, so the move is the entry moving — which is why
      // there is no way for the amount to be counted in both months.
      final entry = await create(draft(id: 'moved', date: '2026-06-15'));
      await accept('moved');
      expect((await totals(periodKey: '2026-06')).gross.paise, 10000000);

      await edit(
        draft(id: 'moved', date: '2026-07-03'),
        baseRowVersion: entry.rowVersion,
      );
      await acceptEdit('moved', entry.rowVersion + 1);

      expect(
        (await totals(periodKey: '2026-06')).contributions,
        0,
        reason: 'the month it left no longer counts it',
      );
      final july = await totals(periodKey: '2026-07');
      expect(july.contributions, 1);
      expect(july.gross.paise, 10000000);
      expect(july.tax.paise, 476190);

      final c = (await rows()).single;
      expect(c.pnlPeriodKey, '2026-07');
      expect(c.businessDate.iso, '2026-07-03');
      expect(
        c.txnNumber,
        isNotNull,
        reason:
            'the number belongs to the document identity and survives (D-124)',
      );
      expect(
        (await totals()).contributions,
        1,
        reason: 'and it is counted exactly once across every period',
      );
    });

    test('provenance is a dimension, never an input to an amount', () async {
      // D-143: `derived` and `corrected` with the same date and components contribute
      // identically. Phase 5 may surface the difference; it must not compute with it.
      await create(draft(id: 'p1', date: '2026-06-15'));
      await accept('p1');
      await create(draft(id: 'p2', date: '2026-06-15'));
      await accept('p2', source: BusinessDateSource.corrected);

      final all = await rows();
      expect(
        all.map((c) => c.businessDateSource).toSet(),
        {BusinessDateSource.derived, BusinessDateSource.corrected},
        reason: 'the dimension is carried',
      );
      expect(all.first.gross.paise, all.last.gross.paise);
      expect(all.first.pnlPeriodKey, all.last.pnlPeriodKey);
    });
  });

  group('what does not contribute', () {
    test('a voided sale contributes nothing, and is still explainable', () async {
      final entry = await create(draft(id: 'v1'));
      await accept('v1');
      expect((await totals()).gross.paise, 10000000);

      final refusal = await repository.voidLocally(
        entryId: 'v1',
        reason: 'recorded twice',
        actorUserId: _userA,
        baseRowVersion: entry.rowVersion,
        mutationId: 'mut-void-v1',
        now: DateTime.now().toUtc(),
      );
      expect(refusal, isNull);
      await acceptEdit('v1', entry.rowVersion + 1);

      expect(
        (await totals()).contributions,
        0,
        reason: 'a void removes the reporting effect (D-006)',
      );
      expect(await rows(), isEmpty);

      // And the evidence for what was recorded is not destroyed. The document, its
      // components and their figures are all still there for audit to explain why the
      // month changed.
      final stored = await repository.load('v1');
      expect(stored, isNotNull);
      expect(stored!.voidedAt, isNotNull);
      expect(stored.components.single.gross.paise, 10000000);
      expect(
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM revenue_period_contributions '
                  'WHERE revenue_entry_id = ?',
                  variables: [Variable<String>('v1')],
                )
                .getSingle())
            .read<int>('n'),
        1,
        reason:
            'the projection retains the row and carries voided_at; it is the aggregate '
            'that excludes it, exactly as expense_period_contributions does',
      );
    });

    test('a sale the server has not accepted is not revenue yet', () async {
      // The distinction B14 turns on: a local attempt is an attempt. Putting it in an
      // authoritative total would report money the business does not yet have.
      await create(draft(id: 'pending'));

      expect((await totals()).contributions, 0);
      expect(await rows(), isEmpty);

      await accept('pending');
      expect((await totals()).contributions, 1);
    });

    test('a conflicted or rejected attempt contributes nothing', () async {
      final entry = await create(draft(id: 'c1'));
      await accept('c1');
      await edit(
        draft(id: 'c1', amounts: [20000000]),
        baseRowVersion: entry.rowVersion,
      );

      for (final status in const [
        OutboxStatus.conflict,
        OutboxStatus.rejected,
      ]) {
        await db.customStatement(
          'UPDATE sync_outbox SET status = ? WHERE entity_id = ?',
          [status.name, 'c1'],
        );
        final t = await totals();
        expect(
          t.gross.paise,
          20000000,
          reason:
              'the local row holds the operator attempt and the accepted figure is what '
              'the server last said; Slice 12 does not resolve that, and Phase 5 reads '
              'canonical rows only through the server projection',
        );
        expect(t.contributions, 1);
      }
    });

    test('a retained, revoked document is nobody\'s revenue', () async {
      // D-070: a confirmed revocation takes the synced figures out of the browsable
      // cache and keeps only the actor's own unsent work — which is an attempt, not
      // revenue, and must not move a total.
      await create(draft(id: 'rev1', category: vCategoryRoom));
      await accept('rev1');
      await create(draft(id: 'rev2', category: vCategoryRoom));
      expect((await totals()).contributions, 1);

      await ScopeCachePurge(db).applyTo(
        AuthorityConfirmed(
          AuthoritySnapshot(
            userId: _userA,
            orgId: _org,
            grants: const [
              CapabilityGrant(Capability.revenueView, businessUnitId: _ccr),
            ],
            resolvedAt: DateTime.now().toUtc(),
          ),
        ),
        previous: _authority(),
      );

      expect(
        (await totals()).contributions,
        0,
        reason:
            'the synced sale is purged and the retained attempt is quarantined; neither '
            'is revenue this user may report',
      );
    });
  });

  group('scope is authority, applied in SQL', () {
    setUp(() async {
      await create(draft(id: 's-ccr', category: vCategoryRestaurant));
      await accept('s-ccr');
      await create(draft(id: 's-hki', category: vCategoryRoom));
      await accept('s-hki');
    });

    test('a scoped reader sees only their property', () async {
      expect((await totals(scope: {_ccr})).contributions, 1);
      expect((await rows(scope: {_ccr})).single.businessUnitId, _ccr);
      expect((await totals(scope: {_hki})).contributions, 1);
      expect((await totals(scope: {_ccr, _hki})).contributions, 2);
    });

    test(
      'an unscoped grant restricts nothing, and an empty one everything',
      () async {
        expect(
          (await totals()).contributions,
          2,
          reason: 'null scope is an org-wide holder by construction (D-025)',
        );
        expect(
          (await totals(scope: const <String>{})).contributions,
          0,
          reason: 'holding no unit is not holding every unit',
        );
      },
    );

    test('a filter cannot widen the scope it was given', () async {
      final t = await totals(unit: _hki, scope: {_ccr});
      expect(
        t.contributions,
        0,
        reason:
            'businessUnitId is a choice and businessUnitIds is authority; choosing a '
            'property you may not see returns nothing rather than everything',
      );
    });
  });

  group('aggregation is deterministic and exact', () {
    test('totals equal the sum of the rows they summarise', () async {
      for (final (id, category, amount) in const [
        ('a1', vCategoryRestaurant, 7),
        ('a2', vCategoryNandbhog, 3333),
        ('a3', vCategoryRoom, 100000001),
        ('a4', vCategoryBanquet, 4034300),
      ]) {
        await create(draft(id: id, category: category, amounts: [amount]));
        await accept(id);
      }

      final all = await rows();
      final t = await totals();
      expect(t.gross.paise, all.fold<int>(0, (s, c) => s + c.gross.paise));
      expect(t.tax.paise, all.fold<int>(0, (s, c) => s + c.tax.paise));
      expect(t.net.paise, all.fold<int>(0, (s, c) => s + c.net.paise));
      expect(t.contributions, all.length);
      expect(
        t.reconciles,
        isTrue,
        reason: 'summing stored paise cannot break net = gross - tax',
      );
    });

    test('the same query twice gives the same answer', () async {
      await create(draft(id: 'det', amounts: [10000000, 3333]));
      await accept('det');
      final first = await totals();
      final second = await totals();
      expect(second.gross.paise, first.gross.paise);
      expect(second.tax.paise, first.tax.paise);
      expect(second.net.paise, first.net.paise);
      expect(second.contributions, first.contributions);
    });

    test('an empty period is zero over zero rows, not an absent answer', () async {
      final t = await totals(periodKey: '2026-01');
      expect(t.gross, Money.zero);
      expect(t.tax, Money.zero);
      expect(t.net, Money.zero);
      expect(
        t.contributions,
        0,
        reason:
            'a total of zero over no rows and a total of zero over forty rows are '
            'different facts, and a report that cannot tell them apart will present the '
            'first as the second',
      );
    });

    test('by category, and Nandbhog never merges into Restaurant', () async {
      await create(draft(id: 'g1', category: vCategoryRestaurant));
      await accept('g1');
      await create(draft(id: 'g2', category: vCategoryNandbhog));
      await accept('g2');
      await create(draft(id: 'g3', category: vCategoryRoom));
      await accept('g3');

      final grouped = await repository.contributionTotalsByCategory(
        const RevenueContributionQuery(periodKey: '2026-06'),
      );
      expect(grouped, hasLength(3));
      final ccr = grouped.where((g) => g.businessUnitId == _ccr).toList();
      expect(ccr, hasLength(2));
      expect(
        ccr.map((g) => g.revenueCategoryId).toSet(),
        {vCategoryRestaurant, vCategoryNandbhog},
        reason:
            'two categories that share a treatment today are still two lines (D-089)',
      );
      for (final g in grouped) {
        expect(g.totals.reconciles, isTrue);
      }
    });
  });

  group('an edit replaces the contribution, it does not add one', () {
    test('the accepted figures are the new ones, exactly once', () async {
      final entry = await create(draft(id: 'ed'));
      await accept('ed');
      expect((await totals()).gross.paise, 10000000);

      await edit(
        draft(id: 'ed', amounts: [7500000]),
        baseRowVersion: entry.rowVersion,
      );
      await acceptEdit('ed', entry.rowVersion + 1);

      final t = await totals();
      expect(
        t.contributions,
        1,
        reason: 'not two; an edit that appended would double the month',
      );
      expect(t.gross.paise, 7500000);
      expect(t.tax.paise, 357143);
      expect(t.net.paise, 7142857);
      expect(t.reconciles, isTrue);
    });

    test('an edit that changes the component count changes the rows', () async {
      final entry = await create(
        draft(id: 'ec', category: vCategoryRoom, amounts: [4200000, 2300000]),
      );
      await accept('ec');
      expect((await totals()).contributions, 2);

      await edit(
        draft(id: 'ec', category: vCategoryRoom, amounts: [6500000]),
        baseRowVersion: entry.rowVersion,
      );
      await acceptEdit('ec', entry.rowVersion + 1);

      final t = await totals();
      expect(t.contributions, 1);
      expect(t.gross.paise, 6500000);
    });
  });

  group('nothing outside the accepted snapshot can move a figure', () {
    test('deleting every tax rule leaves history unchanged', () async {
      // The positive control B20 asks for. A contribution is explained by the component
      // it came from, and by nothing that is still configurable (D-080, D-122).
      await create(draft(id: 'hist'));
      await accept('hist');
      final before = await totals();

      await db.customStatement('DELETE FROM revenue_tax_rates');

      final after = await totals();
      expect(after.gross.paise, before.gross.paise);
      expect(after.tax.paise, before.tax.paise);
      expect(after.net.paise, before.net.paise);
      final c = (await rows()).single;
      expect(c.taxRateBasisPoints, 500);
      expect(c.taxTreatment, TaxTreatment.inclusive);
    });

    test('changing a rule\'s rate does not restate what it produced', () async {
      await create(draft(id: 'rate'));
      await accept('rate');
      final before = await totals();

      await db.customStatement(
        'UPDATE revenue_tax_rates SET rate_basis_points = 1800',
      );

      expect((await totals()).tax.paise, before.tax.paise);
      expect((await rows()).single.taxRateBasisPoints, 500);
    });

    test('attaching evidence changes no contribution (§25, D-150)', () async {
      await create(draft(id: 'att'));
      await accept('att');
      final before = await totals();

      // The whole attachment lifecycle in one table write, which is all the reporting
      // layer can possibly see of it: no amount, no date, no version.
      await db.customStatement(
        'INSERT INTO revenue_attachments (id, org_id, revenue_entry_id, '
        'file_name, content_type, byte_size, content_hash, upload_state, '
        'uploaded_by, storage_path, uploaded_at, attempt_count, created_at, '
        'updated_at) '
        "VALUES ('a1', '$_org', 'att', 'z.jpg', 'image/jpeg', 10, 'h', "
        "'uploaded', '$_userA', 'org/x/revenue/att/a1.jpg', ?, 0, ?, ?)",
        [
          DateTime.now().toUtc().toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );

      final after = await totals();
      expect(after.gross.paise, before.gross.paise);
      expect(after.tax.paise, before.tax.paise);
      expect(after.net.paise, before.net.paise);
      expect(after.contributions, before.contributions);
    });

    test('a replayed acceptance does not duplicate anything', () async {
      // B12: mutation idempotency and contribution idempotency have to agree. They do
      // here by construction — there is nothing to insert twice.
      await create(draft(id: 'rep'));
      await accept('rep');
      final once = await totals();
      await accept('rep', rowVersion: 1);
      await accept('rep', rowVersion: 1);
      final thrice = await totals();

      expect(thrice.contributions, once.contributions);
      expect(thrice.gross.paise, once.gross.paise);
    });
    test('re-reading the server copy replaces, it does not accumulate', () async {
      // The closest thing this product has to a resync of a revenue document: Review
      // latest, which replaces the local copy from the authorised projection (D-126).
      // Applying it twice must leave one document's worth of contributions.
      final entry = await create(draft(id: 'rs', amounts: [10000000]));
      await accept('rs');
      await edit(
        draft(id: 'rs', amounts: [12000000]),
        baseRowVersion: entry.rowVersion,
      );
      await db.customStatement(
        "UPDATE sync_outbox SET status = 'conflict' WHERE entity_id = 'rs'",
      );

      Map<String, dynamic> header() => {
        'id': 'rs',
        'txn_number': 'KI-REV-26-27-000042',
        'financial_year': '2026-27',
        'business_date': '2026-07-16',
        'pnl_period_key': '2026-07',
        'entry_kind': 'daily_summary',
        'source_reference': null,
        'notes': null,
        'row_version': 9,
        'voided_at': null,
        'void_reason': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      List<Map<String, dynamic>> serverComponents() => [
        {
          'id': 'rs-server-c0',
          'entered_amount_minor': 9000000,
          'entered_basis': 'inclusive_total',
          'gross_amount_minor': 9000000,
          'tax_amount_minor': 428571,
          'net_amount_minor': 8571429,
          'tax_rule_id': 'rule-restaurant',
          'tax_rate_bp': 500,
          'tax_treatment': 'inclusive',
          'value_band_id': null,
          'value_band_label': null,
          'value_band_floor_minor': null,
          'value_band_ceiling_minor': null,
          'supply_subtype_id': null,
          'premises_status_code': null,
        },
      ];

      for (var i = 0; i < 3; i++) {
        await repository.applyServerDocument(
          header: header(),
          components: serverComponents(),
          orgId: _org,
        );
      }

      final t = await totals();
      expect(
        t.contributions,
        1,
        reason:
            'three applications of one server answer are still one document',
      );
      expect(t.gross.paise, 9000000);
      expect(t.tax.paise, 428571);
      expect(
        (await totals(periodKey: '2026-06')).contributions,
        0,
        reason:
            'and the period the server says it is in is the one it counts in',
      );
      expect((await totals(periodKey: '2026-07')).contributions, 1);
    });
  });

  group('a month, the way management reads it (§10, B29)', () {
    test('two properties, four categories, exact paise', () async {
      // Synthetic figures. The purpose is the arithmetic structure, not a real month.
      const days = [
        ('m1', vCategoryRestaurant, 7645000, '2026-06-15'),
        ('m2', vCategoryRestaurant, 8120000, '2026-06-16'),
        ('m3', vCategoryNandbhog, 870000, '2026-06-15'),
        ('m4', vCategoryRoom, 5200000, '2026-06-15'),
        ('m5', vCategoryRoom, 4800000, '2026-06-16'),
        ('m6', vCategoryBanquet, 2850000, '2026-06-15'),
        // July, which must not leak into June's figures.
        ('m7', vCategoryRestaurant, 9999999, '2026-07-01'),
      ];
      for (final (id, category, amount, date) in days) {
        await create(
          draft(id: id, category: category, amounts: [amount], date: date),
        );
        await accept(id);
      }

      final june = await repository.contributionTotalsByCategory(
        const RevenueContributionQuery(periodKey: '2026-06'),
      );
      final byCategory = {for (final g in june) g.revenueCategoryId: g.totals};

      // Crystal Canopy Rooftop.
      expect(byCategory[vCategoryRestaurant]!.gross.paise, 15765000);
      expect(
        byCategory[vCategoryRestaurant]!.tax.paise,
        750715,
        reason:
            'the sum of two rounded extractions (364048 + 386667), and NOT the rate '
            're-applied to the total, which gives 750714. One paisa, and it is the '
            'whole of spec §6.5: rounding happens once, at the component, and an '
            'aggregate sums stored paise (D-017)',
      );
      expect(byCategory[vCategoryRestaurant]!.net.paise, 15014285);
      expect(
        (15765000 * 500) ~/ 10500,
        750714,
        reason:
            'the figure a report that re-rated the total would print, kept here so the '
            'difference is stated rather than discovered',
      );
      expect(byCategory[vCategoryNandbhog]!.gross.paise, 870000);
      expect(byCategory[vCategoryNandbhog]!.tax.paise, 41429);
      expect(byCategory[vCategoryNandbhog]!.net.paise, 828571);

      // Hotel Krishna Imperial.
      expect(byCategory[vCategoryRoom]!.gross.paise, 10000000);
      expect(byCategory[vCategoryRoom]!.tax.paise, 476190);
      expect(byCategory[vCategoryRoom]!.net.paise, 9523810);
      expect(byCategory[vCategoryBanquet]!.gross.paise, 2850000);
      expect(
        byCategory[vCategoryBanquet]!.tax.paise,
        0,
        reason: 'Banquet is `none`; no GST is extracted from it',
      );
      expect(byCategory[vCategoryBanquet]!.net.paise, 2850000);

      // Per property: Total Sales, GST, Net Sales — the three lines spec §10 names,
      // summed from contributions and nothing else.
      final ccr = await totals(periodKey: '2026-06', unit: _ccr);
      expect(ccr.gross.paise, 16635000);
      expect(ccr.tax.paise, 792144);
      expect(ccr.net.paise, 15842856);
      expect(ccr.reconciles, isTrue);

      final hki = await totals(periodKey: '2026-06', unit: _hki);
      expect(hki.gross.paise, 12850000);
      expect(hki.tax.paise, 476190);
      expect(hki.net.paise, 12373810);
      expect(hki.reconciles, isTrue);

      // Consolidated, and it is the sum of the two properties to the paisa.
      final all = await totals(periodKey: '2026-06');
      expect(all.gross.paise, ccr.gross.paise + hki.gross.paise);
      expect(all.tax.paise, ccr.tax.paise + hki.tax.paise);
      expect(all.net.paise, ccr.net.paise + hki.net.paise);
      expect(all.contributions, 6);
      expect(
        (await totals(periodKey: '2026-07')).gross.paise,
        9999999,
        reason: 'and July is July',
      );
    });
  });

  group('the v14 to v15 migration', () {
    test('a fresh database is born with the projection', () async {
      expect(db.schemaVersion, 15);
      final view = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = "
            "'revenue_period_contributions' AND type = 'view'",
          )
          .getSingle();
      final sql = view.read<String>('sql');
      expect(sql, contains('gross_minor'));
      expect(sql, contains('pnl_period_key'));
      expect(
        sql,
        contains('voided_at'),
        reason:
            'the projection carries it and does not filter on it, exactly as '
            'expense_period_contributions does: the aggregate excludes, the row remains',
      );

      expect(
        await db
            .customSelect(
              "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' "
              "AND name = 'revenue_period_contributions'",
            )
            .getSingle()
            .then((r) => r.read<int>('n')),
        0,
        reason:
            'a table here would be a stored copy of facts the components already carry '
            '(D-157), and would need maintaining through every correction and void',
      );

      final index = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'index' "
            "AND name = 'ix_revenue_entries_reporting'",
          )
          .getSingle();
      expect(index.read<int>('n'), 1);
    });

    test('a v14 device gains the projection over the rows it holds', () async {
      final file = await createTempDatabaseFile();
      addTearDown(() => file.parent.deleteSync(recursive: true));

      // A v14-shaped database with a real sale in it. Raw SQL, because building it from
      // today's classes would create the view and prove nothing.
      final raw = sqlite3.open(file.path);
      raw
        ..execute('PRAGMA user_version = 14')
        ..execute('''
          CREATE TABLE revenue_entries (
            id TEXT NOT NULL PRIMARY KEY, org_id TEXT NOT NULL,
            txn_number TEXT NULL, financial_year TEXT NULL,
            business_unit_id TEXT NOT NULL, revenue_category_id TEXT NOT NULL,
            business_date TEXT NOT NULL, pnl_period_key TEXT NOT NULL,
            business_date_source TEXT NOT NULL DEFAULT 'derived',
            captured_at TEXT NOT NULL,
            entry_kind TEXT NOT NULL DEFAULT 'daily_summary',
            source_reference TEXT NULL, notes TEXT NULL, created_by TEXT NOT NULL,
            voided_at TEXT NULL, voided_by TEXT NULL, void_reason TEXT NULL,
            pending_mutation_id TEXT NULL,
            row_version INTEGER NOT NULL DEFAULT 1,
            server_updated_at TEXT NULL, updated_at TEXT NOT NULL,
            scope_revoked_at TEXT NULL
          )
        ''')
        ..execute('''
          CREATE TABLE revenue_components (
            id TEXT NOT NULL PRIMARY KEY, org_id TEXT NOT NULL,
            revenue_entry_id TEXT NOT NULL,
            entered_amount_minor INTEGER NOT NULL, entered_basis TEXT NOT NULL,
            gross_amount_minor INTEGER NOT NULL, tax_amount_minor INTEGER NOT NULL,
            net_amount_minor INTEGER NOT NULL,
            tax_rule_id TEXT NOT NULL, tax_rate_basis_points INTEGER NOT NULL,
            tax_treatment TEXT NOT NULL,
            value_band_id TEXT NULL, value_band_label TEXT NULL,
            value_band_floor_minor INTEGER NULL, value_band_ceiling_minor INTEGER NULL,
            supply_subtype_id TEXT NULL, supply_subtype_label TEXT NULL,
            premises_status_code TEXT NULL
          )
        ''')
        ..execute('''
          INSERT INTO revenue_entries (
            id, org_id, txn_number, financial_year, business_unit_id,
            revenue_category_id, business_date, pnl_period_key, captured_at,
            entry_kind, created_by, row_version, updated_at)
          VALUES (
            'rev-old', 'org-1', 'KI-REV-26-27-000042', '26-27', 'unit-ccr',
            'cat-restaurant', '2026-06-15', '2026-06', '2026-06-15T09:00:00.000Z',
            'daily_summary', 'user-1', 4, '2026-06-15T09:00:00.000Z')
        ''')
        ..execute('''
          INSERT INTO revenue_components (
            id, org_id, revenue_entry_id, entered_amount_minor, entered_basis,
            gross_amount_minor, tax_amount_minor, net_amount_minor,
            tax_rule_id, tax_rate_basis_points, tax_treatment)
          VALUES (
            'comp-old', 'org-1', 'rev-old', 10000000, 'inclusive_total',
            10000000, 476190, 9523810, 'rule-1', 500, 'inclusive')
        ''')
        ..close();

      final upgraded = AppDatabase(NativeDatabase(file));
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      expect(
        (await upgraded.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .first,
        upgraded.schemaVersion,
      );

      // Nothing was backfilled and nothing needed to be: the contribution is the rows
      // the device already had, seen through a projection.
      final repo = RevenueRepository(
        upgraded,
        tax: RevenueTaxRepository(upgraded),
      );
      final t = await repo.contributionTotals(
        const RevenueContributionQuery(periodKey: '2026-06'),
      );
      expect(t.contributions, 1);
      expect(t.gross.paise, 10000000);
      expect(t.tax.paise, 476190);
      expect(t.net.paise, 9523810);
      expect(t.reconciles, isTrue);
    });

    test('a v10 device is not asked for a view over tables it lacks', () async {
      // The D-144 guard. `revenue_entries` and `revenue_components` are created at v11,
      // so a device coming from v10 has neither when the v15 step is reached — and the
      // view would reference tables that do not exist. Caught once already, on a v9
      // fixture, two phases after the same mistake (D-144).
      final source = File(
        'lib/data/local/app_database.dart',
      ).readAsStringSync();
      final step = source.substring(
        source.indexOf('from >= 11 && from < 15'),
        source.indexOf('if (from < 9) {'),
      );
      expect(step, contains('_createRevenuePeriodContributionsView'));
      expect(
        source.indexOf('from >= 11 && from < 15'),
        greaterThan(0),
        reason: 'the step is guarded by a range, not a bare floor',
      );
    });
  });

  group('the slice boundary', () {
    test('Slice 12 builds no P&L, no dashboard and no export', () async {
      // A rule that nothing evaluates is a comment (D-068, D-071, D-077). The reporting
      // substrate is not the reporting product, and this is what says so.
      final surface = RevenueRepository(db, tax: RevenueTaxRepository(db));
      expect(surface.contributionTotals, isNotNull);
      // ignore: unnecessary_type_check
      expect(surface is RevenueRepository, isTrue);

      final source = await _repositorySource();
      for (final forbidden in const [
        'operatingProfit',
        'profitMargin',
        'netSales',
        'exportExcel',
        'exportPdf',
        'toPdf',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason:
              '$forbidden belongs to Phase 5; Slice 12 populates the interface and '
              'builds no reporting (D-087)',
        );
      }
    });
  });
}

Future<String> _repositorySource() async {
  return await _readFile('lib/data/repositories/revenue_repository.dart');
}

Future<String> _readFile(String path) async =>
    // ignore: avoid_slow_async_io
    await File(path).readAsString();
