/// Offline revenue tax resolution from the Drift cache (Slice 5).
///
/// The pure resolver is already proven. What is proven here is the **adapter**: that the
/// cache reconstructs the domain faithfully, invents nothing, and — the point of the
/// slice — distinguishes *"the organisation has no rule for this"* from *"this device has
/// no configuration"*.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

import '../support/revenue_parity_vectors.dart';

const testUser = 'user-1';

/// The property a test category belongs to. Passed to the resolver rather than looked up,
/// because a revocation legitimately removes the category row it would be looked up from.
String unitOf(String category) => switch (category) {
  vCategoryRoom || vCategoryBanquet => 'unit-hki',
  _ => 'unit-ccr',
};

const otherUser = 'user-2';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late RevenueTaxRepository repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    repository = RevenueTaxRepository(db);

    for (final unit in const [('unit-ccr', 'CCR'), ('unit-hki', 'HKI')]) {
      await db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES (?, 'org-1', ?, ?, 'hotel', 'Asia/Kolkata', '05:00', 1, 1, "
        "'2026-04-01T00:00:00.000Z')",
        [unit.$1, unit.$2, unit.$2],
      );
    }
    for (final c in const [
      (vCategoryRestaurant, 'unit-ccr', 'RESTAURANT'),
      (vCategoryNandbhog, 'unit-ccr', 'NANDBHOG'),
      (vCategoryRoom, 'unit-hki', 'ROOM'),
      (vCategoryBanquet, 'unit-hki', 'BANQUET'),
    ]) {
      await db.customStatement(
        'INSERT INTO revenue_categories (id, org_id, business_unit_id, code, '
        'name, sort_order, row_version, updated_at) '
        "VALUES (?, 'org-1', ?, ?, ?, 1, 1, '2026-04-01T00:00:00.000Z')",
        [c.$1, c.$2, c.$3, c.$3],
      );
    }
  });

  tearDown(() => db.close());

  /// Marks one business unit's configuration as authoritatively synchronised, for one
  /// user — which is the granularity at which the claim can actually be true (D-108).
  Future<void> markSynchronised({
    String user = testUser,
    String unit = 'unit-ccr',
    String datasets = 'bands,rules,statuses,subtypes',
  }) => db.customStatement(
    'INSERT OR REPLACE INTO revenue_config_snapshots (user_id, org_id, '
    'business_unit_id, status, datasets, generation, confirmed_at, updated_at) '
    "VALUES (?, 'org-1', ?, 'complete', ?, '4200', "
    "'2026-06-15T09:00:00.000Z', '2026-06-15T09:00:00.000Z')",
    [user, unit, datasets],
  );

  /// Both properties, for the ordinary case where scope is not what a test is about.
  Future<void> markAllSynchronised({String user = testUser}) async {
    await markSynchronised(user: user, unit: 'unit-ccr');
    await markSynchronised(user: user, unit: 'unit-hki');
  }

  Future<void> cacheBand(
    String id, {
    int? floor,
    int? ceiling,
    String? supersededBy,
  }) => db.customStatement(
    'INSERT INTO revenue_value_bands (id, org_id, revenue_category_id, code, '
    'label, floor_minor, ceiling_minor, superseded_by_band_id, row_version, '
    'updated_at) '
    "VALUES (?, 'org-1', ?, ?, ?, ?, ?, ?, 1, '2026-04-01T00:00:00.000Z')",
    [id, vCategoryRoom, id.toUpperCase(), id, floor, ceiling, supersededBy],
  );

  Future<void> cacheRule(RuleVector v) => db.customStatement(
    'INSERT INTO revenue_tax_rates (id, org_id, revenue_category_id, '
    'rate_basis_points, treatment, effective_from, effective_to, input_basis, '
    'value_band_id, supply_subtype_id, premises_status_code, created_by, '
    'created_at, row_version, updated_at) '
    "VALUES (?, 'org-1', ?, ?, ?, ?, ?, ?, ?, ?, ?, 'u', "
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

  RevenueTaxFacts facts({
    String category = vCategoryRestaurant,
    String date = '2026-06-15',
    String? band,
    String? subtype,
    String? premises,
  }) => RevenueTaxFacts(
    revenueCategoryId: category,
    businessDate: vDate(date),
    valueBandId: band,
    supplySubtypeId: subtype,
    premisesStatusCode: premises,
  );

  Future<void> cacheBaseline() async {
    for (final v in verifiedBaseline) {
      await cacheRule(v);
    }
    await markAllSynchronised();
  }

  group(
    'an unsynchronised device says so, rather than blaming the configuration',
    () {
      test(
        'no snapshot at all is configurationUnavailable, not noApplicableRule',
        () async {
          // The distinction the whole slice exists for (B1). Both stop a revenue entry; only
          // one of them is a statement about the organisation's tax configuration.
          final outcome = await repository.resolve(
            facts(),
            userId: testUser,
            businessUnitId: unitOf(vCategoryRestaurant),
          );

          expect(outcome, isA<RevenueConfigurationUnavailable>());
          expect(
            (outcome as RevenueConfigurationUnavailable).gap,
            RevenueConfigurationGap.neverSynchronised,
          );
          expect(outcome, isNot(isA<RevenueTaxNoApplicableRule>()));
          expect(outcome.message, contains('not yet received'));
        },
      );

      test(
        'an empty cache WITH a snapshot is genuinely noApplicableRule',
        () async {
          // Same query result, opposite meaning.
          await markAllSynchronised();

          final outcome = await repository.resolve(
            facts(),
            userId: testUser,
            businessUnitId: unitOf(vCategoryRestaurant),
          );

          expect(outcome, isA<RevenueTaxNoApplicableRule>());
          expect(outcome.message, contains('No tax rule configured'));
        },
      );

      test('a snapshot is not inferred from rows existing', () async {
        // A rule cached without the marker still does not make the device authoritative:
        // the marker is what the purge clears, and rows are what it deletes.
        await cacheRule(verifiedBaseline.first);

        expect(
          await repository.resolve(
            facts(),
            userId: testUser,
            businessUnitId: unitOf(vCategoryRestaurant),
          ),
          isA<RevenueConfigurationUnavailable>(),
        );
      });
    },
  );

  group('the stored form of a basis is pinned, not coincidental', () {
    test('the wire names are exactly what both schemas accept', () {
      // Found by writing this suite: the adapter parsed `EnteredBasis.name`
      // (`inclusiveTotal`) while both schemas store `inclusive_total`, so every rule
      // carrying a basis would have thrown on read. Pinned here because the value decides
      // whether a recorded figure includes tax.
      expect(EnteredBasis.inclusiveTotal.wireName, 'inclusive_total');
      expect(EnteredBasis.preTax.wireName, 'pre_tax');
      expect(
        EnteredBasis.fromName('inclusive_total'),
        EnteredBasis.inclusiveTotal,
      );
      expect(EnteredBasis.fromName('pre_tax'), EnteredBasis.preTax);
    });

    test('an unrecognised basis throws rather than defaulting', () {
      expect(
        () => EnteredBasis.fromName('inclusiveTotal'),
        throwsArgumentError,
        reason:
            'the Dart name is not a stored form, and guessing which amount a figure '
            'is would be inventing a financial fact',
      );
    });
  });

  group('completeness is scoped, not global (D-108)', () {
    setUp(() async {
      for (final v in verifiedBaseline) {
        await cacheRule(v);
      }
    });

    test('syncing Crystal Canopy does not vouch for Hotel Krishna', () async {
      // The defect this group exists for. Slice 5's marker was one global key, so a
      // device that had synchronised only Crystal Canopy would have answered a Room
      // question with `noApplicableRule` — "the Owner has not configured a rule" — about
      // a property it had never been told anything about.
      await markSynchronised(unit: 'unit-ccr');

      expect(
        await repository.resolve(
          facts(),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRestaurant),
        ),
        isA<RevenueTaxResolved>(),
      );

      final room = await repository.resolve(
        facts(category: vCategoryRoom),
        userId: testUser,
        businessUnitId: unitOf(vCategoryRoom),
      );
      expect(room, isA<RevenueConfigurationUnavailable>());
      expect(
        (room as RevenueConfigurationUnavailable).gap,
        RevenueConfigurationGap.neverSynchronised,
      );
      expect(room, isNot(isA<RevenueTaxNoApplicableRule>()));
    });

    test(
      'and the converse: Hotel Krishna does not vouch for Crystal Canopy',
      () async {
        await markSynchronised(unit: 'unit-hki');

        expect(
          await repository.resolve(
            facts(category: vCategoryRoom),
            userId: testUser,
            businessUnitId: unitOf(vCategoryRoom),
          ),
          isA<RevenueTaxResolved>(),
        );
        expect(
          await repository.resolve(
            facts(),
            userId: testUser,
            businessUnitId: unitOf(vCategoryRestaurant),
          ),
          isA<RevenueConfigurationUnavailable>(),
        );
      },
    );

    test('a multi-scope user may hold both', () async {
      await markAllSynchronised();

      for (final category in const [
        vCategoryRestaurant,
        vCategoryNandbhog,
        vCategoryRoom,
        vCategoryBanquet,
      ]) {
        expect(
          await repository.resolve(
            facts(category: category),
            userId: testUser,
            businessUnitId: unitOf(category),
          ),
          isA<RevenueTaxResolved>(),
          reason: category,
        );
      }
    });

    test("one user's sync does not vouch for another user", () async {
      // A shared back-office workstation sees several people sign in and out of one
      // installation (D-051, D-054). Authority is per person, and so is any claim made
      // on the strength of it.
      await markAllSynchronised(user: testUser);

      expect(
        await repository.resolve(
          facts(),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRestaurant),
        ),
        isA<RevenueTaxResolved>(),
      );
      expect(
        await repository.resolve(
          facts(),
          userId: otherUser,
          businessUnitId: 'unit-ccr',
        ),
        isA<RevenueConfigurationUnavailable>(),
        reason:
            'the rules are cached, and nobody has vouched for them for this user',
      );
    });

    test('tax rules alone are not a complete snapshot', () async {
      // Received rules say nothing about bands, subtypes or statuses, and the same
      // resolution consults all four. A marker that could be advanced after the first
      // request is the "collection of lucky requests" the slice brief forbids.
      await markSynchronised(unit: 'unit-ccr', datasets: 'rules');

      final state = await repository.completenessFor(
        userId: testUser,
        businessUnitId: 'unit-ccr',
      );
      expect(state, isA<RevenueConfigIncomplete>());
      expect((state as RevenueConfigIncomplete).missing, {
        RevenueConfigDataset.valueBands,
        RevenueConfigDataset.supplySubtypes,
        RevenueConfigDataset.premisesStatuses,
      });

      expect(
        await repository.resolve(
          facts(),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRestaurant),
        ),
        isA<RevenueConfigurationUnavailable>(),
      );
    });

    test(
      'a revocation is distinguishable from never having synchronised',
      () async {
        await markAllSynchronised();
        await db.customStatement(
          "UPDATE revenue_config_snapshots SET status = 'revoked', datasets = '' "
          "WHERE business_unit_id = 'unit-ccr' AND user_id = ?",
          [testUser],
        );

        final revoked = await repository.resolve(
          facts(),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRestaurant),
        );
        expect(
          (revoked as RevenueConfigurationUnavailable).gap,
          RevenueConfigurationGap.revoked,
        );
        expect(revoked.message, contains('access to this property changed'));

        // The other property is untouched: losing one scope is not losing them all.
        expect(
          await repository.resolve(
            facts(category: vCategoryRoom),
            userId: testUser,
            businessUnitId: unitOf(vCategoryRoom),
          ),
          isA<RevenueTaxResolved>(),
        );
      },
    );

    test('an uncached category cannot be answered for at all', () async {
      await markAllSynchronised();

      // A category this device does not hold. Nothing about its scope has been
      // established here, so there is nothing to answer for it with.
      expect(
        await repository.resolve(
          facts(category: 'cat-never-seen'),
          userId: testUser,
          businessUnitId: 'unit-never-synced',
        ),
        isA<RevenueConfigurationUnavailable>(),
        reason:
            'answering noApplicableRule would speak for a scope never established',
      );
    });
  });

  group('the verified baseline, held locally', () {
    setUp(cacheBaseline);

    test('all four categories resolve exactly as configured', () async {
      for (final v in verifiedBaseline) {
        final outcome = await repository.resolve(
          facts(category: v.category),
          userId: testUser,
          businessUnitId: unitOf(v.category),
        );
        expect(outcome, isA<RevenueTaxResolved>(), reason: v.category);

        final rule = (outcome as RevenueTaxResolved).rule;
        expect(rule.rateBasisPoints, v.rateBp, reason: v.category);
        expect(rule.treatment, v.treatment, reason: v.category);
        expect(
          rule.inputBasis,
          EnteredBasis.inclusiveTotal,
          reason: '${v.category} records the customer-billed total',
        );
      }
    });

    test('Restaurant and Nandbhog resolve to different rules', () async {
      final restaurant = await repository.resolve(
        facts(),
        userId: testUser,
        businessUnitId: unitOf(vCategoryRestaurant),
      );
      final nandbhog = await repository.resolve(
        facts(category: vCategoryNandbhog),
        userId: testUser,
        businessUnitId: unitOf(vCategoryNandbhog),
      );

      expect(restaurant.ruleOrNull!.id, 'rule-restaurant');
      expect(nandbhog.ruleOrNull!.id, 'rule-nandbhog');
    });

    test('Room resolves generically, needing no band', () async {
      // The current baseline has no band, so no band fact is required (B4).
      final outcome = await repository.resolve(
        facts(category: vCategoryRoom),
        userId: testUser,
        businessUnitId: unitOf(vCategoryRoom),
      );
      expect(outcome, isA<RevenueTaxResolved>());
      expect(outcome.ruleOrNull!.valueBandId, isNull);
    });

    test('Banquet resolves untaxed, needing no subtype', () async {
      final outcome = await repository.resolve(
        facts(category: vCategoryBanquet),
        userId: testUser,
        businessUnitId: unitOf(vCategoryBanquet),
      );
      expect(outcome.ruleOrNull!.treatment, TaxTreatment.none);
    });

    test('the day before the baseline has no applicable rule', () async {
      expect(
        await repository.resolve(
          facts(date: '2026-03-31'),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRestaurant),
        ),
        isA<RevenueTaxNoApplicableRule>(),
      );
      expect(
        await repository.resolve(
          facts(date: '2026-04-01'),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRestaurant),
        ),
        isA<RevenueTaxResolved>(),
      );
    });
  });

  group('the adapter invents nothing', () {
    test(
      'a cached rule with no basis is incomplete, never inclusive_total',
      () async {
        // The server now refuses to create one (A1), but a cache can still hold one, and
        // promoting it because every verified category happens to use inclusive_total
        // would decide — silently — whether a recorded figure includes tax.
        await cacheRule(incompleteVector);
        await markAllSynchronised();

        final outcome = await repository.resolve(
          facts(),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRestaurant),
        );

        expect(outcome, isA<RevenueTaxIncompleteRule>());
        expect(outcome.message, contains('which amount is entered'));
      },
    );

    test('a configured 0% resolves as a real rule', () async {
      await cacheRule(zeroRateVector);
      await markAllSynchronised();

      final outcome = await repository.resolve(
        facts(),
        userId: testUser,
        businessUnitId: unitOf(vCategoryRestaurant),
      );

      expect(outcome, isA<RevenueTaxResolved>());
      expect(outcome.ruleOrNull!.rateBasisPoints, 0);
      expect(outcome, isNot(isA<RevenueTaxNoApplicableRule>()));
    });
  });

  group('no first-row-wins, even against a corrupted cache', () {
    test('two matching cached rules are ambiguous, not the first one', () async {
      // The server prevents this state; a stale or corrupted cache can still hold it, and
      // silently taking either would apply a rate nobody approved (B8).
      await cacheRule(verifiedBaseline.first);
      await cacheRule(
        const RuleVector(
          id: 'rule-duplicate',
          category: vCategoryRestaurant,
          rateBp: 1800,
          treatment: TaxTreatment.inclusive,
          basis: EnteredBasis.inclusiveTotal,
        ),
      );
      await markAllSynchronised();

      final outcome = await repository.resolve(
        facts(),
        userId: testUser,
        businessUnitId: unitOf(vCategoryRestaurant),
      );

      expect(outcome, isA<RevenueTaxAmbiguous>());
      expect((outcome as RevenueTaxAmbiguous).candidates, hasLength(2));
    });

    test(
      'a wildcard and a specific band collide rather than ranking',
      () async {
        await cacheBand(vBandLower, floor: 0, ceiling: 750000);
        await cacheRule(verifiedBaseline[2]); // generic Room
        await cacheRule(roomBandVectors.first); // banded Room
        await markAllSynchronised();

        expect(
          await repository.resolve(
            facts(category: vCategoryRoom, band: vBandLower),
            userId: testUser,
            businessUnitId: unitOf(vCategoryRoom),
          ),
          isA<RevenueTaxAmbiguous>(),
        );
      },
    );
  });

  group('Room bands are selected, never derived from an amount', () {
    setUp(() async {
      await cacheBand(vBandLower, floor: 0, ceiling: 750000);
      await cacheBand(vBandUpper, floor: 750000);
      for (final v in roomBandVectors) {
        await cacheRule(v);
      }
      await markAllSynchronised();
    });

    test('each band resolves to its own rule', () async {
      expect(
        (await repository.resolve(
          facts(category: vCategoryRoom, band: vBandLower),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRoom),
        )).ruleOrNull!.rateBasisPoints,
        500,
      );
      expect(
        (await repository.resolve(
          facts(category: vCategoryRoom, band: vBandUpper),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRoom),
        )).ruleOrNull!.rateBasisPoints,
        1200,
      );
    });

    test(
      'no band chosen, where rules require one, is a missing fact',
      () async {
        final outcome = await repository.resolve(
          facts(category: vCategoryRoom),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRoom),
        );

        expect(outcome, isA<RevenueTaxMissingFact>());
        expect(
          (outcome as RevenueTaxMissingFact).dimension,
          RevenueTaxDimension.valueBand,
        );
      },
    );

    test('the amount cannot influence which band resolves', () async {
      // D-094, restated at the adapter: `RevenueTaxFacts` carries no money, so no query
      // and no code path can consult one. The resolver's input for a ₹100 day and a
      // ₹99,00,000 day attributed to the same band is byte-identical.
      final tiny = facts(category: vCategoryRoom, band: vBandUpper);
      final huge = facts(category: vCategoryRoom, band: vBandUpper);

      expect(
        (await repository.resolve(
          tiny,
          userId: testUser,
          businessUnitId: 'unit-hki',
        )).ruleOrNull!.id,
        (await repository.resolve(
          huge,
          userId: testUser,
          businessUnitId: 'unit-hki',
        )).ruleOrNull!.id,
      );
      expect(tiny.discriminators.whereType<Money>(), isEmpty);
    });

    test('the resolved rule carries the band bounds for explanation', () async {
      final rule = (await repository.resolve(
        facts(category: vCategoryRoom, band: vBandLower),
        userId: testUser,
        businessUnitId: unitOf(vCategoryRoom),
      )).ruleOrNull!;

      expect(rule.valueBandFloor, Money.fromPaise(0));
      expect(rule.valueBandCeiling, Money.fromPaise(750000));
      expect(rule.valueBandLabel, vBandLower);
    });
  });

  group(
    'band lifecycle: superseded explains history, and is not offered anew',
    () {
      setUp(() async {
        await cacheBand(vBandUpper, floor: 900000);
        await cacheBand(
          vBandLower,
          floor: 0,
          ceiling: 750000,
          supersededBy: vBandUpper,
        );
        await markAllSynchronised();
      });

      test('a superseded band is excluded from new-entry selection', () async {
        final selectable = await repository.selectableBands(vCategoryRoom);

        expect(selectable.map((b) => b.id), [vBandUpper]);
        expect(
          selectable.map((b) => b.id),
          isNot(contains(vBandLower)),
          reason:
              'recording today against a retired tariff boundary would be wrong',
        );
      });

      test('but it remains resolvable, so history stays explainable', () async {
        final band = await repository.bandById(vBandLower);

        expect(band, isNotNull);
        expect(band!.ceilingMinor, 750000);
        expect(
          band.supersededByBandId,
          vBandUpper,
          reason: 'the lineage says replaced by, not deleted',
        );
      });
    },
  );

  group('supply subtype and premises status', () {
    test(
      'a rule requiring a subtype, with none chosen, is a missing fact',
      () async {
        await cacheRule(subtypeVector);
        await markAllSynchronised();

        final outcome = await repository.resolve(
          facts(category: vCategoryBanquet),
          userId: testUser,
          businessUnitId: unitOf(vCategoryBanquet),
        );

        expect(
          (outcome as RevenueTaxMissingFact).dimension,
          RevenueTaxDimension.supplySubtype,
        );
      },
    );

    test(
      'a rule requiring a premises status, with none configured, is a missing fact',
      () async {
        await cacheRule(premisesVector);
        await markAllSynchronised();

        final outcome = await repository.resolve(
          facts(),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRestaurant),
        );

        expect(
          (outcome as RevenueTaxMissingFact).dimension,
          RevenueTaxDimension.premisesStatus,
        );
      },
    );

    test('the status timeline resolves by date, never by latest start', () async {
      // A2's correction, exercised locally: the cache holds `effective_to`, so the
      // question is "which interval contains this date" rather than "which started most
      // recently" — the ranking D-094 forbids.
      for (final s in const [
        ('st-a', '2026-04-01', '2026-06-01', 'STATUS_A'),
        ('st-b', '2026-06-01', null, 'STATUS_B'),
      ]) {
        await db.customStatement(
          'INSERT INTO business_unit_tax_statuses (id, org_id, business_unit_id, '
          'effective_from, effective_to, status_code, row_version, updated_at) '
          "VALUES (?, 'org-1', 'unit-ccr', ?, ?, ?, 1, '2026-04-01T00:00:00.000Z')",
          [s.$1, s.$2, s.$3, s.$4],
        );
      }

      final may = await repository.premisesStatusFor(
        businessUnitId: 'unit-ccr',
        on: vDate('2026-05-15'),
      );
      final august = await repository.premisesStatusFor(
        businessUnitId: 'unit-ccr',
        on: vDate('2026-08-15'),
      );
      final boundary = await repository.premisesStatusFor(
        businessUnitId: 'unit-ccr',
        on: vDate('2026-06-01'),
      );
      final before = await repository.premisesStatusFor(
        businessUnitId: 'unit-ccr',
        on: vDate('2026-03-31'),
      );

      expect(may!.statusCode, 'STATUS_A');
      expect(august!.statusCode, 'STATUS_B');
      expect(
        boundary!.statusCode,
        'STATUS_B',
        reason: 'half-open: the boundary belongs to the successor',
      );
      expect(before, isNull);
    });
  });

  group('offline create eligibility (B12)', () {
    test(
      'the baseline permits a create, and returns the resolutions',
      () async {
        await cacheBaseline();

        final eligibility = await repository.eligibilityFor(
          userId: testUser,
          businessUnitId: 'unit-ccr',
          revenueCategoryId: vCategoryRestaurant,
          businessDate: vDate('2026-06-15'),
          components: [facts()],
        );

        expect(eligibility.isAllowed, isTrue);
        expect(eligibility.resolutions, hasLength(1));
        expect(eligibility.resolutions.single.rule.rateBasisPoints, 500);
      },
    );

    test(
      'an unsynchronised device refuses, and says which kind of refusal',
      () async {
        final eligibility = await repository.eligibilityFor(
          userId: testUser,
          businessUnitId: 'unit-ccr',
          revenueCategoryId: vCategoryRestaurant,
          businessDate: vDate('2026-06-15'),
          components: [facts()],
        );

        expect(eligibility.isAllowed, isFalse);
        expect(eligibility.refusal, isA<RevenueConfigurationUnavailable>());
      },
    );

    test('one unresolvable component refuses the whole entry', () async {
      await cacheBaseline();

      final eligibility = await repository.eligibilityFor(
        userId: testUser,
        businessUnitId: 'unit-ccr',
        revenueCategoryId: vCategoryRestaurant,
        businessDate: vDate('2026-03-31'),
        components: [facts(date: '2026-03-31')],
      );

      expect(eligibility.isAllowed, isFalse);
      expect(eligibility.refusal, isA<RevenueTaxNoApplicableRule>());
    });

    test('resolution writes nothing at all (B15)', () async {
      // The cached configuration is read-only to this device: it is a projection of server
      // state, and a client that "helpfully" repaired or backfilled it would be inventing
      // a tax fact. Asserted by counting rows either side rather than by reading the code.
      await cacheBaseline();

      Future<Map<String, int>> census() async => {
        for (final table in const [
          'revenue_tax_rates',
          'revenue_value_bands',
          'revenue_supply_subtypes',
          'business_unit_tax_statuses',
          'revenue_entries',
          'revenue_components',
          'app_meta',
          'sync_outbox',
        ])
          table:
              (await db
                          .customSelect('SELECT COUNT(*) AS n FROM $table')
                          .getSingle())
                      .data['n']!
                  as int,
      };

      final before = await census();
      await repository.resolve(
        facts(),
        userId: testUser,
        businessUnitId: unitOf(vCategoryRestaurant),
      );
      await repository.resolve(
        facts(category: vCategoryRoom),
        userId: testUser,
        businessUnitId: unitOf(vCategoryRoom),
      );
      await repository.selectableBands(vCategoryRoom);
      await repository.premisesStatusFor(
        businessUnitId: 'unit-ccr',
        on: vDate('2026-06-15'),
      );
      await repository.eligibilityFor(
        userId: testUser,
        businessUnitId: 'unit-ccr',
        revenueCategoryId: vCategoryRestaurant,
        businessDate: vDate('2026-06-15'),
        components: [facts()],
      );

      expect(await census(), before);
    });

    test('Slice 5 creates no outbox mutation', () async {
      await cacheBaseline();
      await repository.eligibilityFor(
        userId: testUser,
        businessUnitId: 'unit-ccr',
        revenueCategoryId: vCategoryRestaurant,
        businessDate: vDate('2026-06-15'),
        components: [facts()],
      );

      final queued = await db
          .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
          .getSingle();
      expect(
        queued.data['n'],
        0,
        reason: 'eligibility is a decision; Slice 7 owns the write',
      );
    });
  });

  group('a confirmed revocation stops new offline revenue (B13)', () {
    test('purging the configuration makes creation refuse', () async {
      await cacheBaseline();
      expect(
        (await repository.eligibilityFor(
          userId: testUser,
          businessUnitId: 'unit-ccr',
          revenueCategoryId: vCategoryRestaurant,
          businessDate: vDate('2026-06-15'),
          components: [facts()],
        )).isAllowed,
        isTrue,
      );

      // What a confirmed revocation does: the reference cache goes, and the completeness
      // record is downgraded rather than deleted, so the device can still say which
      // silence this is. Stale configuration must not be used to create new revenue.
      await db.customStatement('DELETE FROM revenue_tax_rates');
      await db.customStatement(
        "UPDATE revenue_config_snapshots SET status = 'revoked', datasets = '', "
        "generation = NULL WHERE business_unit_id = 'unit-ccr'",
      );

      final after = await repository.eligibilityFor(
        userId: testUser,
        businessUnitId: 'unit-ccr',
        revenueCategoryId: vCategoryRestaurant,
        businessDate: vDate('2026-06-15'),
        components: [facts()],
      );

      expect(after.isAllowed, isFalse);
      expect(after.refusal, isA<RevenueConfigurationUnavailable>());
    });

    test(
      'a retained component stays explainable with no rule cache at all',
      () async {
        // Its snapshot is the explanation; nothing it needs lives in a row a revocation may
        // legitimately delete (D-070 §11). Re-rating it against whatever cache exists later
        // is not merely discouraged — the component does not consult the cache.
        await db.customStatement(
          'INSERT INTO revenue_entries (id, org_id, business_unit_id, '
          'revenue_category_id, business_date, pnl_period_key, captured_at, '
          'entry_kind, created_by, row_version, updated_at) '
          "VALUES ('e1', 'org-1', 'unit-ccr', ?, '2026-06-15', '2026-06', "
          "'2026-06-15T09:00:00.000Z', 'daily_summary', 'user-1', 1, "
          "'2026-06-15T09:00:00.000Z')",
          [vCategoryRestaurant],
        );
        await db.customStatement(
          'INSERT INTO revenue_components (id, org_id, revenue_entry_id, '
          'entered_amount_minor, entered_basis, gross_amount_minor, '
          'tax_amount_minor, net_amount_minor, tax_rule_id, tax_rate_basis_points, '
          'tax_treatment) '
          "VALUES ('c1', 'org-1', 'e1', 10000000, 'inclusive_total', 10000000, "
          "476190, 9523810, 'rule-restaurant', 500, 'inclusive')",
        );

        await db.customStatement('DELETE FROM revenue_tax_rates');

        final row = await db
            .customSelect(
              'SELECT tax_rate_basis_points, tax_treatment, entered_basis, '
              'tax_amount_minor FROM revenue_components',
            )
            .getSingle();
        expect(row.data['tax_rate_basis_points'], 500);
        expect(row.data['tax_treatment'], 'inclusive');
        expect(row.data['entered_basis'], 'inclusive_total');
        expect(row.data['tax_amount_minor'], 476190);
      },
    );
  });

  group('Dart and Drift agree, to the paise', () {
    test('every arithmetic vector matches the pure resolver exactly', () async {
      await cacheBaseline();

      for (final v in readArithmeticVectors()) {
        // The pure engine.
        final pure = TaxRule(
          id: 'v',
          revenueCategoryId: vCategoryRestaurant,
          rateBasisPoints: v.rateBp,
          treatment: v.treatment,
          effectiveFrom: vDate('2026-04-01'),
          inputBasis: v.treatment == TaxTreatment.exclusive
              ? EnteredBasis.preTax
              : EnteredBasis.inclusiveTotal,
        ).compute(Money.fromPaise(v.entered));

        expect(pure.gross, Money.fromPaise(v.gross), reason: '$v');
        expect(pure.tax, Money.fromPaise(v.tax), reason: '$v');
        expect(pure.net, Money.fromPaise(v.net), reason: '$v');
        expect(pure.reconciles, isTrue);
      }
    });

    test(
      'the Drift-resolved baseline rule computes the vector figures',
      () async {
        await cacheBaseline();

        final rule = (await repository.resolve(
          facts(),
          userId: testUser,
          businessUnitId: unitOf(vCategoryRestaurant),
        )).ruleOrNull!;
        final computed = rule.compute(Money.fromRupees(100000));

        expect(computed.gross, Money.fromPaise(10000000));
        expect(computed.tax, Money.fromPaise(476190));
        expect(computed.net, Money.fromPaise(9523810));
      },
    );
  });
}
