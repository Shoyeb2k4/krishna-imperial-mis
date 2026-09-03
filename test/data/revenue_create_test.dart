/// The revenue create path (Slice 7): eligibility, one atomic write, and the queued
/// intent that carries it.
///
/// Two things are being proved here, and they pull in opposite directions.
///
/// The first is that a defensible revenue figure can be recorded with no network at all.
/// The second is that a device which cannot produce a defensible figure says so, at the
/// time, in a sentence somebody can act on — rather than saving something that will be
/// refused later, when the person who typed it has gone home.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:timezone/data/latest.dart' as tzdata;

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
  bool orgWide = false,
}) => AuthoritySnapshot(
  userId: user,
  orgId: _org,
  grants: orgWide
      ? [const CapabilityGrant(Capability.revenueCreate)]
      : [
          for (final unit in units)
            CapabilityGrant(Capability.revenueCreate, businessUnitId: unit),
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
  late RevenueTaxRepository tax;

  // Reset per test, so an assertion may name the id it just created.
  var draftSeq = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    draftSeq = 0;
    tax = RevenueTaxRepository(db);
    repository = RevenueRepository(db, tax: tax);

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
  });

  tearDown(() => db.close());

  Future<void> cacheRule(RuleVector v) => db.customStatement(
    'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
    'rate_basis_points, treatment, effective_from, effective_to, input_basis, '
    'value_band_id, supply_subtype_id, premises_status_code, created_by, '
    'created_at, row_version, updated_at) '
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

  Future<void> markComplete({
    String user = _userA,
    String unit = _ccr,
    Duration age = const Duration(hours: 1),
    String datasets = 'bands,rules,statuses,subtypes',
  }) => db.customStatement(
    'INSERT OR REPLACE INTO revenue_config_snapshots (user_id, org_id, '
    'business_unit_id, status, datasets, generation, confirmed_at, updated_at) '
    "VALUES (?, '$_org', ?, 'complete', ?, '900', ?, ?)",
    [
      user,
      unit,
      datasets,
      DateTime.now().toUtc().subtract(age).toIso8601String(),
      DateTime.now().toUtc().toIso8601String(),
    ],
  );

  Future<void> configured({Duration age = const Duration(hours: 1)}) async {
    for (final v in verifiedBaseline) {
      await cacheRule(v);
    }
    await markComplete(unit: _ccr, age: age);
    await markComplete(unit: _hki, age: age);
  }

  RevenueEntryDraft draft({
    String category = vCategoryRestaurant,
    List<int> amounts = const [10000000],
    List<String?> bands = const [null],
    String date = '2026-06-15',
  }) {
    draftSeq++;
    return RevenueEntryDraft(
      id: 'entry-$draftSeq',
      businessUnitId: _unitOf(category),
      revenueCategoryId: category,
      businessDate: vDate(date),
      capturedAt: DateTime.now().toUtc(),
      components: [
        for (var i = 0; i < amounts.length; i++)
          RevenueComponentDraft(
            id: 'comp-$draftSeq-$i',
            enteredAmount: Money.fromPaise(amounts[i]),
            valueBandId: i < bands.length ? bands[i] : null,
          ),
      ],
    );
  }

  /// Evaluate then save, which is the only supported order.
  Future<RevenueEntry> save(
    RevenueEntryDraft d, {
    AuthoritySnapshot? authority,
    DateTime? now,
    String? mutationId,
  }) async {
    final decision = await repository.evaluate(
      d,
      authority: authority ?? _authority(),
      now: now,
    );
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
      actorUserId: (authority ?? _authority()).userId,
      orgId: _org,
      mutationId: mutationId ?? 'mut-${d.id}',
      now: DateTime.now().toUtc(),
    );
  }

  Future<RevenueRefusal> refusalFor(
    RevenueEntryDraft d, {
    AuthoritySnapshot? authority,
    bool anonymous = false,
    DateTime? now,
  }) async {
    final decision = await repository.evaluate(
      d,
      authority: anonymous ? null : (authority ?? _authority()),
      now: now,
    );
    expect(decision, isA<RevenueCreateRefused>());
    return (decision as RevenueCreateRefused).refusal;
  }

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']!
          as int;

  group('the four verified categories, recorded offline', () {
    setUp(configured);

    test(
      'each resolves and stores exactly the paise the parity vectors state',
      () async {
        for (final expected in const [
          (vCategoryRestaurant, 10000000, 10000000, 476190, 9523810),
          (vCategoryNandbhog, 1250000, 1250000, 59524, 1190476),
          (vCategoryRoom, 6500000, 6500000, 309524, 6190476),
          (vCategoryBanquet, 4034300, 4034300, 0, 4034300),
        ]) {
          final entry = await save(
            draft(category: expected.$1, amounts: [expected.$2]),
          );
          final component = entry.components.single;

          expect(component.gross.paise, expected.$3, reason: expected.$1);
          expect(component.tax.paise, expected.$4, reason: expected.$1);
          expect(component.net.paise, expected.$5, reason: expected.$1);
          expect(
            component.net.paise + component.tax.paise,
            component.gross.paise,
            reason: '${expected.$1} reconciles',
          );
          expect(
            component.enteredBasis,
            EnteredBasis.inclusiveTotal,
            reason: '${expected.$1} records the customer-billed total (D-090)',
          );
        }
      },
    );

    test(
      'Banquet is untaxed, and that is a decision rather than a gap',
      () async {
        final entry = await save(
          draft(category: vCategoryBanquet, amounts: [4034300]),
        );
        final component = entry.components.single;

        expect(component.taxTreatment, TaxTreatment.none);
        expect(component.tax, Money.zero);
        expect(component.taxRuleId, 'rule-banquet');
        expect(
          component.gross,
          component.net,
          reason:
              'with no tax the customer total and the pre-tax amount coincide',
        );
      },
    );

    test('Restaurant and Nandbhog snapshot different rules', () async {
      final restaurant = await save(draft());
      final nandbhog = await save(draft(category: vCategoryNandbhog));

      expect(restaurant.components.single.taxRuleId, 'rule-restaurant');
      expect(nandbhog.components.single.taxRuleId, 'rule-nandbhog');
    });
  });

  group('one atomic transaction (§6)', () {
    setUp(configured);

    test(
      'the entry, its components and the outbox intent all arrive together',
      () async {
        await save(draft(amounts: [10000000]));

        expect(await count('revenue_entries'), 1);
        expect(await count('revenue_components'), 1);
        expect(await count('sync_outbox'), 1);

        final queued = await db
            .customSelect('SELECT * FROM sync_outbox')
            .getSingle();
        expect(queued.data['entity_type'], revenueEntityType);
        expect(queued.data['entity_id'], 'entry-1');
        expect(queued.data['op'], 'create');
        expect(
          queued.data['actor_user_id'],
          _userA,
          reason: 'no unattributed revenue intent may exist (D-050, D-074)',
        );
        expect(queued.data['status'], 'pending');
      },
    );

    test('a failing component write leaves nothing behind', () async {
      // Two components sharing one id: the second insert violates the primary key, which
      // is the same shape of forced mid-transaction failure the expense suite uses. What
      // matters is not the cause but that the rollback is total.
      final d = RevenueEntryDraft(
        id: 'entry-rollback',
        businessUnitId: _ccr,
        revenueCategoryId: vCategoryRestaurant,
        businessDate: vDate('2026-06-15'),
        capturedAt: DateTime.now().toUtc(),
        components: [
          RevenueComponentDraft(
            id: 'duplicate',
            enteredAmount: Money.fromPaise(100000),
          ),
          RevenueComponentDraft(
            id: 'duplicate',
            enteredAmount: Money.fromPaise(200000),
          ),
        ],
      );

      final decision = await repository.evaluate(d, authority: _authority());
      await expectLater(
        repository.createLocally(
          d,
          resolutions: (decision as RevenueCreatePermitted).resolutions,
          actorUserId: _userA,
          orgId: _org,
          mutationId: 'mut-rollback',
          now: DateTime.now().toUtc(),
        ),
        throwsA(anything),
      );

      expect(await count('revenue_entries'), 0, reason: 'no orphan header');
      expect(await count('revenue_components'), 0);
      expect(
        await count('sync_outbox'),
        0,
        reason: 'and no intent pointing at a document that does not exist',
      );
    });

    test('no transaction number is invented locally', () async {
      final entry = await save(draft());

      expect(entry.txnNumber, isNull);
      final row = await db
          .customSelect(
            'SELECT txn_number, pending_mutation_id FROM revenue_entries',
          )
          .getSingle();
      expect(
        row.data['txn_number'],
        isNull,
        reason: 'two offline devices would both claim the same one (spec §8.4)',
      );
      expect(row.data['pending_mutation_id'], 'mut-entry-1');
    });
  });

  group('multi-component documents (§17)', () {
    setUp(() async {
      // Synthetic bands, on a test-only configuration. The production Room rule has no
      // band and no threshold has been verified — inventing one to make this test
      // convenient would be inventing a business fact (D-096).
      await db.customStatement(
        'INSERT INTO revenue_value_bands (id, org_id, revenue_category_id, code, '
        'label, floor_minor, ceiling_minor, row_version, updated_at) '
        "VALUES (?, '$_org', ?, 'LOWER', 'Lower', 0, 750000, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [vBandLower, vCategoryRoom],
      );
      await db.customStatement(
        'INSERT INTO revenue_value_bands (id, org_id, revenue_category_id, code, '
        'label, floor_minor, ceiling_minor, row_version, updated_at) '
        "VALUES (?, '$_org', ?, 'UPPER', 'Upper', 750000, NULL, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [vBandUpper, vCategoryRoom],
      );
      for (final v in roomBandVectors) {
        await cacheRule(v);
      }
      for (final v in verifiedBaseline.where(
        (v) => v.category != vCategoryRoom,
      )) {
        await cacheRule(v);
      }
      await markComplete(unit: _ccr);
      await markComplete(unit: _hki);
    });

    test('a two-band room day stores two components and sums exactly', () async {
      final entry = await save(
        draft(
          category: vCategoryRoom,
          amounts: [4200000, 2300000],
          bands: [vBandLower, vBandUpper],
        ),
      );

      expect(entry.components, hasLength(2));
      expect(await count('revenue_components'), 2);

      // Lower band: 5% inclusive. Upper band: 12% inclusive. Two treatments, one day,
      // one category — the fact the document model exists for (D-078).
      final lower = entry.components[0];
      final upper = entry.components[1];
      expect(lower.taxRateBasisPoints, 500);
      expect(upper.taxRateBasisPoints, 1200);
      expect(lower.taxRuleId, isNot(upper.taxRuleId));

      expect(lower.gross.paise, 4200000);
      expect(lower.tax.paise, 200000);
      expect(lower.net.paise, 4000000);
      expect(upper.gross.paise, 2300000);
      expect(upper.tax.paise, 246429);
      expect(upper.net.paise, 2053571);

      // The header is the exact sum of its parts, derived and never stored (D-078).
      expect(entry.gross.paise, 6500000);
      expect(entry.tax.paise, 446429);
      expect(entry.net.paise, 6053571);
      expect(entry.net.paise + entry.tax.paise, entry.gross.paise);
    });

    test(
      'the band identity and its bounds are snapshotted for explanation',
      () async {
        final entry = await save(
          draft(
            category: vCategoryRoom,
            amounts: [4200000],
            bands: [vBandLower],
          ),
        );
        final component = entry.components.single;

        expect(component.valueBandId, vBandLower);
        expect(component.valueBandFloor, Money.fromPaise(0));
        expect(component.valueBandCeiling, Money.fromPaise(750000));
      },
    );

    test('the payload carries every component and no rate', () async {
      final entry = await save(
        draft(
          category: vCategoryRoom,
          amounts: [4200000, 2300000],
          bands: [vBandLower, vBandUpper],
        ),
      );
      final payload = RevenueRepository.createPayload(entry);
      final components = payload['p_components']! as List<Object?>;

      expect(components, hasLength(2));
      for (final raw in components) {
        final component = raw! as Map<String, Object?>;
        expect(component.containsKey('entered_amount_minor'), isTrue);
        expect(component.containsKey('declared_gross_minor'), isTrue);
        expect(
          component.containsKey('tax_rate_bp'),
          isFalse,
          reason: 'the server resolves the rule; the client never dictates one',
        );
        expect(component.containsKey('tax_rule_id'), isFalse);
      }
    });
  });

  group('D-112 — configuration freshness for NEW revenue', () {
    setUp(() async {
      for (final v in verifiedBaseline) {
        await cacheRule(v);
      }
    });

    test('just under 24 hours is permitted', () async {
      await markComplete(age: const Duration(hours: 23, minutes: 59));

      final decision = await repository.evaluate(
        draft(),
        authority: _authority(),
      );
      expect(decision, isA<RevenueCreatePermitted>());
    });

    test('exactly 24 hours is permitted — the boundary is inclusive', () async {
      // Written down rather than left to an operator: "24 hours" is ambiguous until
      // somebody states which side the boundary falls on, and a rule nobody has stated
      // is a rule two readers will implement differently.
      final confirmed = DateTime.now().toUtc().subtract(
        const Duration(hours: 24),
      );
      await markComplete(age: const Duration(hours: 24));

      final decision = await repository.evaluate(
        draft(),
        authority: _authority(),
        now: confirmed.add(revenueConfigMaxAge),
      );
      expect(decision, isA<RevenueCreatePermitted>());
    });

    test('one second past 24 hours refuses', () async {
      await markComplete(age: const Duration(hours: 24, seconds: 1));

      final refusal = await refusalFor(draft());

      expect(refusal.reason, RevenueRefusalReason.configurationExpired);
      expect(refusal.message, contains('24 hours'));
      expect(
        refusal.refreshMayResolve,
        isTrue,
        reason: 'a refresh is exactly what would change this answer',
      );
    });

    test(
      'an expired snapshot refuses rather than quietly using a stale rate',
      () async {
        await markComplete(age: const Duration(days: 3));

        expect(await count('revenue_entries'), 0);
        final refusal = await refusalFor(draft());
        expect(refusal.reason, RevenueRefusalReason.configurationExpired);
        expect(
          await count('revenue_entries'),
          0,
          reason:
              'nothing is written, and nothing is queued for the server to refuse later',
        );
        expect(await count('sync_outbox'), 0);
      },
    );

    test(
      'a device clock earlier than the server confirmation fails closed',
      () async {
        // A backwards clock would otherwise make every snapshot look newly fresh, which is
        // the one direction the error must not go. Reported as its own reason, because
        // "your clock is wrong" sends somebody to fix a different thing from "your
        // configuration is old".
        await markComplete(age: Duration.zero);

        final refusal = await refusalFor(
          draft(),
          now: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        );

        expect(refusal.reason, RevenueRefusalReason.clockUnreliable);
        expect(refusal.message, contains('date and time'));
      },
    );

    test('ordinary skew of a few minutes is tolerated', () async {
      await markComplete(age: Duration.zero);

      final decision = await repository.evaluate(
        draft(),
        authority: _authority(),
        now: DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
      );
      expect(
        decision,
        isA<RevenueCreatePermitted>(),
        reason: 'two machines disagreeing slightly is not evidence of anything',
      );
    });

    test(
      'freshness is per unit: a fresh CCR does not carry a stale HKI',
      () async {
        await markComplete(unit: _ccr, age: const Duration(hours: 1));
        await markComplete(unit: _hki, age: const Duration(days: 2));

        expect(
          await repository.evaluate(draft(), authority: _authority()),
          isA<RevenueCreatePermitted>(),
        );
        expect(
          (await refusalFor(draft(category: vCategoryRoom))).reason,
          RevenueRefusalReason.configurationExpired,
        );
      },
    );

    test("freshness is per user: A's snapshot does not carry B", () async {
      await markComplete(user: _userA, unit: _ccr);

      expect(
        await repository.evaluate(draft(), authority: _authority(user: _userA)),
        isA<RevenueCreatePermitted>(),
      );
      expect(
        (await refusalFor(draft(), authority: _authority(user: _userB))).reason,
        RevenueRefusalReason.configurationNeverSynchronised,
      );
    });

    test('expiry does not touch an attempt that already exists (§16)', () async {
      // The distinction the rule turns on. D-112 governs *creating* a new attempt; an
      // attempt created while the configuration was fresh already carries its own tax
      // snapshot, and deleting or re-rating it because a window has since closed would
      // destroy work nobody asked to lose.
      await markComplete(age: const Duration(hours: 10));
      final entry = await save(draft(amounts: [10000000]));

      await markComplete(age: const Duration(hours: 30));

      expect(await count('revenue_entries'), 1);
      expect(await count('sync_outbox'), 1);

      final reloaded = await repository.load(entry.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.components.single.tax.paise, 476190);
      expect(reloaded.components.single.taxRuleId, 'rule-restaurant');

      // And a *new* attempt is refused, which is the whole of the rule.
      expect(
        (await refusalFor(draft())).reason,
        RevenueRefusalReason.configurationExpired,
      );
    });
  });

  group('eligibility refusals are specific (§4, §5)', () {
    test('not signed in', () async {
      await configured();
      final refusal = await refusalFor(draft(), anonymous: true);
      expect(refusal.reason, RevenueRefusalReason.notAuthenticated);
    });

    test('authorised for the other property only', () async {
      await configured();
      final refusal = await refusalFor(
        draft(category: vCategoryRoom),
        authority: _authority(units: {_ccr}),
      );
      expect(refusal.reason, RevenueRefusalReason.notAuthorisedForUnit);
      expect(refusal.message, contains('permission'));
    });

    test('an org-wide grant covers every property (D-025)', () async {
      await configured();
      final decision = await repository.evaluate(
        draft(category: vCategoryRoom),
        authority: _authority(orgWide: true),
      );
      expect(decision, isA<RevenueCreatePermitted>());
    });

    test('a category belonging to the other property', () async {
      await configured();
      final d = RevenueEntryDraft(
        id: 'entry-mismatch',
        businessUnitId: _ccr,
        // A real category id, under Hotel Krishna. The composite check is what the
        // server's own foreign-key ladder enforces (D-040).
        revenueCategoryId: vCategoryRoom,
        businessDate: vDate('2026-06-15'),
        capturedAt: DateTime.now().toUtc(),
        components: [
          RevenueComponentDraft(
            id: 'c',
            enteredAmount: Money.fromPaise(100000),
          ),
        ],
      );

      final refusal = await refusalFor(d);
      expect(refusal.reason, RevenueRefusalReason.invalidCategory);
    });

    test('a closed period', () async {
      await configured();
      await db.customStatement(
        'INSERT INTO period_locks (id, org_id, business_unit_id, period_key, '
        'state, row_version) '
        "VALUES ('lock-1', ?, ?, '2026-06', 'closed', 1)",
        [_org, _ccr],
      );

      final refusal = await refusalFor(draft());
      expect(refusal.reason, RevenueRefusalReason.periodClosed);
      expect(refusal.detail?['period'], '2026-06');
      expect(await count('revenue_entries'), 0);
    });

    test('no components', () async {
      await configured();
      final refusal = await refusalFor(
        RevenueEntryDraft(
          id: 'entry-empty',
          businessUnitId: _ccr,
          revenueCategoryId: vCategoryRestaurant,
          businessDate: vDate('2026-06-15'),
          capturedAt: DateTime.now().toUtc(),
          components: const [],
        ),
      );
      expect(refusal.reason, RevenueRefusalReason.noComponents);
    });

    test('configuration never synchronised', () async {
      for (final v in verifiedBaseline) {
        await cacheRule(v);
      }
      final refusal = await refusalFor(draft());
      expect(
        refusal.reason,
        RevenueRefusalReason.configurationNeverSynchronised,
      );
      expect(refusal.refreshMayResolve, isTrue);
    });

    test('configuration revoked', () async {
      await configured();
      await db.customStatement(
        "UPDATE revenue_config_snapshots SET status = 'revoked', datasets = '' "
        "WHERE business_unit_id = '$_ccr'",
      );
      final refusal = await refusalFor(draft());
      expect(refusal.reason, RevenueRefusalReason.configurationRevoked);
      expect(refusal.message, contains('access to this property changed'));
    });

    test('configuration incomplete', () async {
      await configured();
      await db.customStatement(
        "UPDATE revenue_config_snapshots SET datasets = 'rules' "
        "WHERE business_unit_id = '$_ccr'",
      );
      final refusal = await refusalFor(draft());
      expect(refusal.reason, RevenueRefusalReason.configurationIncomplete);
    });

    test('no applicable rule is a gap, not a zero rate', () async {
      await configured();
      final refusal = await refusalFor(draft(date: '2026-03-31'));

      expect(refusal.reason, RevenueRefusalReason.noApplicableRule);
      expect(
        await count('revenue_entries'),
        0,
        reason: 'recording it at 0% would silently overstate Net Sales (D-084)',
      );
    });

    test('an incomplete rule refuses rather than assuming a basis', () async {
      await cacheRule(incompleteVector);
      await markComplete(unit: _ccr);

      final refusal = await refusalFor(draft());
      expect(refusal.reason, RevenueRefusalReason.incompleteRule);
    });

    test('ambiguous configuration is refused, never tiebroken', () async {
      await configured();
      await cacheRule(
        const RuleVector(
          id: 'rule-duplicate',
          category: vCategoryRestaurant,
          rateBp: 1800,
          treatment: TaxTreatment.inclusive,
          basis: EnteredBasis.inclusiveTotal,
        ),
      );

      final refusal = await refusalFor(draft());
      expect(refusal.reason, RevenueRefusalReason.ambiguousConfiguration);
      expect(
        (refusal.detail?['candidates']! as List).length,
        2,
        reason:
            'both are named, because a person has to look at the configuration',
      );
    });

    test('a required room band that was not chosen', () async {
      await db.customStatement(
        'INSERT INTO revenue_value_bands (id, org_id, revenue_category_id, code, '
        'label, floor_minor, ceiling_minor, row_version, updated_at) '
        "VALUES (?, '$_org', ?, 'LOWER', 'Lower', 0, 750000, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [vBandLower, vCategoryRoom],
      );
      await cacheRule(roomBandVectors.first);
      await markComplete(unit: _hki);

      final refusal = await refusalFor(draft(category: vCategoryRoom));
      expect(refusal.reason, RevenueRefusalReason.missingValueBand);
    });

    test('a required supply subtype that was not chosen', () async {
      await db.customStatement(
        'INSERT INTO revenue_supply_subtypes (id, org_id, revenue_category_id, '
        'code, label, row_version, updated_at) '
        "VALUES (?, '$_org', ?, 'HALL', 'Hall', 1, '2026-04-01T00:00:00.000Z')",
        [vSubtypeHall, vCategoryBanquet],
      );
      await cacheRule(subtypeVector);
      await markComplete(unit: _hki);

      final refusal = await refusalFor(draft(category: vCategoryBanquet));
      expect(refusal.reason, RevenueRefusalReason.missingSupplySubtype);
    });

    test('a required premises status that is not configured', () async {
      await cacheRule(premisesVector);
      await markComplete(unit: _ccr);

      final refusal = await refusalFor(draft());
      expect(refusal.reason, RevenueRefusalReason.missingPremisesStatus);
    });

    test('no refusal message leaks an exception or an internal name', () async {
      await configured();
      final refusals = <RevenueRefusal>[
        await refusalFor(draft(), anonymous: true),
        await refusalFor(draft(date: '2026-03-31')),
        await refusalFor(
          draft(category: vCategoryRoom),
          authority: _authority(units: {_ccr}),
        ),
      ];

      for (final refusal in refusals) {
        for (final forbidden in const [
          'Exception',
          'SQLSTATE',
          'SqliteException',
          'revenue_tax_rates',
          'null',
          'KM0',
        ]) {
          expect(
            refusal.message,
            isNot(contains(forbidden)),
            reason: '${refusal.reason.name}: "${refusal.message}"',
          );
        }
      }
    });
  });

  group('business date (§19)', () {
    setUp(configured);

    test('the persisted date and period key are the ones submitted', () async {
      final entry = await save(draft(date: '2026-06-15'));

      final row = await db
          .customSelect(
            'SELECT business_date, pnl_period_key FROM revenue_entries',
          )
          .getSingle();
      expect(row.data['business_date'], '2026-06-15');
      expect(row.data['pnl_period_key'], '2026-06');

      final payload = RevenueRepository.createPayload(entry);
      expect(payload['p_business_date'], '2026-06-15');
    });

    test('a 01:00 rooftop instant belongs to the previous trading day', () async {
      // The D-067 rule, exercised through the create path rather than restated: the
      // client derives the date and submits it, and the server measures the same rule
      // from the same instant.
      final instant = DateTime.utc(
        2026,
        6,
        16,
        1,
        0,
      ).subtract(const Duration(hours: 5, minutes: 30));
      final derived = BusinessDate.fromInstant(
        instant,
        timeZoneId: 'Asia/Kolkata',
      );
      expect(derived.iso, '2026-06-15');

      final entry = await save(draft(date: derived.iso));
      expect(
        RevenueRepository.createPayload(entry)['p_business_date'],
        '2026-06-15',
      );
    });

    test('04:59 and 05:00 fall on different trading days', () async {
      BusinessDate at(int hour, int minute) => BusinessDate.fromInstant(
        DateTime.utc(
          2026,
          6,
          16,
          hour,
          minute,
        ).subtract(const Duration(hours: 5, minutes: 30)),
        timeZoneId: 'Asia/Kolkata',
      );

      expect(at(4, 59).iso, '2026-06-15');
      expect(at(5, 0).iso, '2026-06-16');
    });
  });

  group('reconciliation and the local read model (§10, §21)', () {
    setUp(configured);

    test(
      'acceptance writes the transaction number onto the same document',
      () async {
        final entry = await save(draft());
        expect(await count('revenue_entries'), 1);

        await repository.reconcileAcceptance(
          RevenueAcceptance(
            entryId: entry.id,
            rowVersion: 1,
            txnNumber: 'KI-REV-26-27-000001',
            financialYear: '2026-27',
          ),
        );

        expect(
          await count('revenue_entries'),
          1,
          reason:
              'the server allocating a number does not create a second document',
        );
        final reloaded = await repository.load(entry.id);
        expect(reloaded!.txnNumber, 'KI-REV-26-27-000001');
        expect(reloaded.rowVersion, 1);
        expect(
          reloaded.components.single.tax.paise,
          476190,
          reason: 'the components are untouched by reconciliation',
        );
      },
    );

    test(
      'a replay reconciles to the same number rather than a second one',
      () async {
        final entry = await save(draft());
        const acceptance = 'KI-REV-26-27-000042';

        for (var i = 0; i < 3; i++) {
          await repository.reconcileAcceptance(
            RevenueAcceptance(
              entryId: entry.id,
              rowVersion: 1,
              txnNumber: acceptance,
              financialYear: '2026-27',
            ),
          );
        }

        expect(await count('revenue_entries'), 1);
        expect((await repository.load(entry.id))!.txnNumber, acceptance);
      },
    );

    test('an answer that restates nothing leaves the number alone', () async {
      // D-072a: writing every field back erased the server-issued number on every edit,
      // because the update RPC returns only a row version. A field the server did not
      // mention is left as it was.
      final entry = await save(draft());
      await repository.reconcileAcceptance(
        RevenueAcceptance(
          entryId: entry.id,
          rowVersion: 1,
          txnNumber: 'KI-REV-26-27-000007',
          financialYear: '2026-27',
        ),
      );

      await repository.reconcileAcceptance(
        RevenueAcceptance(entryId: entry.id, rowVersion: 2),
      );

      final reloaded = await repository.load(entry.id);
      expect(reloaded!.txnNumber, 'KI-REV-26-27-000007');
      expect(reloaded.rowVersion, 2);
    });

    test(
      'the ledger reports pending before acceptance and synced after',
      () async {
        final entry = await save(draft());

        var rows = await repository.list();
        expect(rows, hasLength(1));
        expect(rows.single.syncState, SyncState.pendingSync);
        expect(rows.single.txnNumber, isNull);
        expect(rows.single.gross.paise, 10000000);
        expect(rows.single.tax.paise, 476190);
        expect(rows.single.componentCount, 1);

        await db.customStatement(
          "UPDATE sync_outbox SET status = 'done' WHERE entity_id = ?",
          [entry.id],
        );
        await repository.reconcileAcceptance(
          RevenueAcceptance(
            entryId: entry.id,
            rowVersion: 1,
            txnNumber: 'KI-REV-26-27-000001',
            financialYear: '2026-27',
          ),
        );

        rows = await repository.list();
        expect(rows.single.syncState, SyncState.synced);
        expect(rows.single.txnNumber, 'KI-REV-26-27-000001');
      },
    );

    test('a rejected intent surfaces as rejected, not as pending', () async {
      final entry = await save(draft());
      await db.customStatement(
        "UPDATE sync_outbox SET status = 'rejected' WHERE entity_id = ?",
        [entry.id],
      );

      final rows = await repository.list();
      expect(rows.single.syncState, SyncState.rejected);
    });

    test('the ledger totals are derived, never a stored header', () async {
      await save(draft(amounts: [10000000]));

      final columns = await db
          .customSelect("SELECT * FROM pragma_table_info('revenue_entries')")
          .get();
      final names = {for (final c in columns) c.data['name'] as String};
      for (final forbidden in const [
        'gross_amount_minor',
        'tax_amount_minor',
        'net_amount_minor',
        'total_minor',
      ]) {
        expect(
          names,
          isNot(contains(forbidden)),
          reason:
              'a second copy of the money is a second copy to drift (D-078)',
        );
      }
    });
  });

  group('revocation and ownership (§15, §20)', () {
    setUp(configured);

    test(
      'a quarantined attempt leaves the ordinary ledger and is not destroyed',
      () async {
        final entry = await save(draft());
        expect(await repository.list(), hasLength(1));

        // What a confirmed revocation does to an entry whose intent is still queued: it is
        // stamped and hidden, never deleted, because it exists nowhere else (D-070).
        await db.customStatement(
          'UPDATE revenue_entries SET scope_revoked_at = ? WHERE id = ?',
          [DateTime.now().toUtc().toIso8601String(), entry.id],
        );

        expect(
          await repository.list(),
          isEmpty,
          reason: 'quarantined work is not browsable through the normal ledger',
        );
        expect(
          await count('revenue_entries'),
          1,
          reason: 'and it still exists',
        );
        expect(await count('sync_outbox'), 1, reason: 'with its intent intact');

        expect(await repository.listRetainedAfterRevocation(_userA), [
          entry.id,
        ]);
      },
    );

    test('another user does not inherit it (D-074)', () async {
      final entry = await save(draft());
      await db.customStatement(
        'UPDATE revenue_entries SET scope_revoked_at = ? WHERE id = ?',
        [DateTime.now().toUtc().toIso8601String(), entry.id],
      );

      expect(await repository.listRetainedAfterRevocation(_userA), [entry.id]);
      expect(
        await repository.listRetainedAfterRevocation(_userB),
        isEmpty,
        reason:
            'holding the same property is not evidence of having authored somebody '
            "else's queued work",
      );
    });

    test('a completed intent stops being retained work', () async {
      final entry = await save(draft());
      await db.customStatement(
        'UPDATE revenue_entries SET scope_revoked_at = ? WHERE id = ?',
        [DateTime.now().toUtc().toIso8601String(), entry.id],
      );
      await db.customStatement(
        "UPDATE sync_outbox SET status = 'done' WHERE entity_id = ?",
        [entry.id],
      );

      expect(
        await repository.listRetainedAfterRevocation(_userA),
        isEmpty,
        reason:
            'the server can hand back a synced document; it can never hand back an '
            'intent it never received',
      );
    });

    test('the actor on the intent survives a reopen of the database', () async {
      final entry = await save(draft());
      final path = await db
          .customSelect('SELECT actor_user_id FROM sync_outbox')
          .getSingle();
      expect(path.data['actor_user_id'], _userA);
      expect(entry.createdBy, _userA);
    });
  });
}
