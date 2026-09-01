/// The resolution doctrine, made executable.
///
/// > For any fact set at a business date, **zero or exactly one** rule may match.
///
/// Every test here exists to pin one half of that: what must resolve, and — more
/// importantly — what must be **refused**. A resolver that has quietly stopped refusing
/// reports success exactly as confidently as one that works, which is the shape of defect
/// D-069, D-071 and D-077 each turned out to be.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/revenue/revenue_tax_resolution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

const _restaurant = 'cat-restaurant';
const _nandbhog = 'cat-nandbhog';
const _room = 'cat-room';
const _banquet = 'cat-banquet';

BusinessDate on(String iso) {
  final parts = iso.split('-').map(int.parse).toList();
  return BusinessDate.of(parts[0], parts[1], parts[2]);
}

TaxRule rule({
  required String id,
  String category = _restaurant,
  int rateBp = 500,
  TaxTreatment treatment = TaxTreatment.inclusive,
  EnteredBasis? basis = EnteredBasis.inclusiveTotal,
  String from = '2026-04-01',
  String? to,
  String? bandId,
  String? bandLabel,
  Money? bandFloor,
  Money? bandCeiling,
  String? subtypeId,
  String? premisesStatus,
}) => TaxRule(
  id: id,
  revenueCategoryId: category,
  rateBasisPoints: rateBp,
  treatment: treatment,
  effectiveFrom: on(from),
  effectiveTo: to == null ? null : on(to),
  inputBasis: basis,
  valueBandId: bandId,
  valueBandLabel: bandLabel,
  valueBandFloor: bandFloor,
  valueBandCeiling: bandCeiling,
  supplySubtypeId: subtypeId,
  premisesStatusCode: premisesStatus,
);

RevenueTaxFacts facts({
  String category = _restaurant,
  String date = '2026-06-15',
  String? bandId,
  String? subtypeId,
  String? premisesStatus,
}) => RevenueTaxFacts(
  revenueCategoryId: category,
  businessDate: on(date),
  valueBandId: bandId,
  supplySubtypeId: subtypeId,
  premisesStatusCode: premisesStatus,
);

void main() {
  group('exactly one rule resolves', () {
    test('a simple category and date rule resolves', () {
      final set = RevenueTaxRuleSet([rule(id: 'r1')]);

      final outcome = set.resolve(facts());

      expect(outcome, isA<RevenueTaxResolved>());
      expect(outcome.ruleOrNull!.id, 'r1');
    });

    test('a configured 0% is a real rule, not an absent one', () {
      // Financially different from "no rule configured", and the difference is the whole
      // of D-084: one is a decision, the other is a gap.
      final set = RevenueTaxRuleSet([rule(id: 'zero', rateBp: 0)]);

      final outcome = set.resolve(facts());

      expect(outcome, isA<RevenueTaxResolved>());
      expect(outcome.ruleOrNull!.rateBasisPoints, 0);
      expect(outcome, isNot(isA<RevenueTaxNoApplicableRule>()));
    });

    test('a configured `none` treatment is a real rule too', () {
      final set = RevenueTaxRuleSet([
        rule(id: 'banquet', category: _banquet, treatment: TaxTreatment.none),
      ]);

      final outcome = set.resolve(facts(category: _banquet));

      expect(outcome, isA<RevenueTaxResolved>());
      expect(outcome.ruleOrNull!.treatment, TaxTreatment.none);
    });
  });

  group('nothing resolves', () {
    test('no rule at all is a no-rule refusal, never a zero rate', () {
      final outcome = RevenueTaxRuleSet(const []).resolve(facts());

      expect(outcome, isA<RevenueTaxNoApplicableRule>());
      expect(outcome.ruleOrNull, isNull);
      expect(outcome.message, contains('No tax rule configured'));
    });

    test('a rule for another category does not leak across', () {
      // Restaurant and Nandbhog never inherit from one another (D-089).
      final set = RevenueTaxRuleSet([rule(id: 'r1', category: _restaurant)]);

      expect(
        set.resolve(facts(category: _nandbhog)),
        isA<RevenueTaxNoApplicableRule>(),
      );
    });

    test('an archived rule does not resolve', () {
      final archived = TaxRule(
        id: 'gone',
        revenueCategoryId: _restaurant,
        rateBasisPoints: 500,
        treatment: TaxTreatment.inclusive,
        effectiveFrom: on('2026-04-01'),
        inputBasis: EnteredBasis.inclusiveTotal,
        archivedAt: DateTime.utc(2026, 5, 1),
      );

      expect(
        RevenueTaxRuleSet([archived]).resolve(facts()),
        isA<RevenueTaxNoApplicableRule>(),
      );
    });
  });

  group('effective dates', () {
    test('the day before a rule begins does not resolve', () {
      final set = RevenueTaxRuleSet([rule(id: 'r1', from: '2026-04-01')]);

      expect(
        set.resolve(facts(date: '2026-03-31')),
        isA<RevenueTaxNoApplicableRule>(),
      );
      expect(set.resolve(facts(date: '2026-04-01')), isA<RevenueTaxResolved>());
    });

    test('the period is half-open, so a successor takes its first day', () {
      final set = RevenueTaxRuleSet([
        rule(id: 'old', from: '2026-04-01', to: '2026-10-01', rateBp: 500),
        rule(id: 'new', from: '2026-10-01', rateBp: 1200),
      ]);

      expect(set.resolve(facts(date: '2026-09-30')).ruleOrNull!.id, 'old');
      expect(set.resolve(facts(date: '2026-10-01')).ruleOrNull!.id, 'new');
    });

    test('disjoint dates are legal configuration', () {
      final set = RevenueTaxRuleSet([
        rule(id: 'old', from: '2026-04-01', to: '2026-10-01'),
      ]);

      expect(set.conflictFor(rule(id: 'new', from: '2026-10-01')), isNull);
    });
  });

  group('ambiguity is refused, never ranked', () {
    test('two identical applicable rules refuse', () {
      final set = RevenueTaxRuleSet([rule(id: 'a'), rule(id: 'b')]);

      final outcome = set.resolve(facts());

      expect(outcome, isA<RevenueTaxAmbiguous>());
      expect((outcome as RevenueTaxAmbiguous).candidates, hasLength(2));
      expect(outcome.ruleOrNull, isNull);
    });

    test(
      'a wildcard rule and a specific rule are ambiguous, not most-specific-wins',
      () {
        // The doctrine's sharpest edge. `null` means "does not depend on that dimension",
        // which means it matches EVERY value of it — so both of these match a component
        // carrying band B. There is no specificity ranking to break the tie, by design.
        final set = RevenueTaxRuleSet([
          rule(id: 'wildcard', category: _room),
          rule(id: 'specific', category: _room, bandId: 'band-b'),
        ]);

        final outcome = set.resolve(facts(category: _room, bandId: 'band-b'));

        expect(
          outcome,
          isA<RevenueTaxAmbiguous>(),
          reason: 'a wildcard must collide with a specific, not lose to it',
        );
      },
    );

    test('and the same pair is refused at configuration time', () {
      final set = RevenueTaxRuleSet([rule(id: 'wildcard', category: _room)]);

      expect(
        set.conflictFor(rule(id: 'specific', category: _room, bandId: 'b')),
        RevenueRuleConflict.overlappingApplicability,
      );
    });

    test('two rules with no discriminators over the same dates conflict', () {
      final set = RevenueTaxRuleSet([rule(id: 'a')]);

      expect(
        set.conflictFor(rule(id: 'b')),
        RevenueRuleConflict.overlappingApplicability,
      );
    });

    test('a rule does not conflict with itself on update', () {
      final set = RevenueTaxRuleSet([rule(id: 'a')]);

      expect(set.conflictFor(rule(id: 'a', rateBp: 1200)), isNull);
    });
  });

  group('room value bands', () {
    test('disjoint bands over the same dates are legal', () {
      // This is the configuration D-093 exists to permit: two Room rules, same category,
      // same dates, separated only by which band they govern.
      final set = RevenueTaxRuleSet([
        rule(id: 'lower', category: _room, bandId: 'band-lower'),
      ]);

      expect(
        set.conflictFor(
          rule(id: 'upper', category: _room, bandId: 'band-upper'),
        ),
        isNull,
      );
    });

    test('and each resolves to its own rule', () {
      final set = RevenueTaxRuleSet([
        rule(id: 'lower', category: _room, bandId: 'band-lower', rateBp: 500),
        rule(id: 'upper', category: _room, bandId: 'band-upper', rateBp: 1200),
      ]);

      expect(
        set
            .resolve(facts(category: _room, bandId: 'band-lower'))
            .ruleOrNull!
            .id,
        'lower',
      );
      expect(
        set
            .resolve(facts(category: _room, bandId: 'band-upper'))
            .ruleOrNull!
            .id,
        'upper',
      );
    });

    test('the same band twice over the same dates conflicts', () {
      final set = RevenueTaxRuleSet([
        rule(id: 'a', category: _room, bandId: 'band-lower'),
      ]);

      expect(
        set.conflictFor(rule(id: 'b', category: _room, bandId: 'band-lower')),
        RevenueRuleConflict.overlappingApplicability,
      );
    });

    test('bands separated in time do not conflict', () {
      final set = RevenueTaxRuleSet([
        rule(
          id: 'a',
          category: _room,
          bandId: 'band-lower',
          from: '2026-04-01',
          to: '2026-10-01',
        ),
      ]);

      expect(
        set.conflictFor(
          rule(
            id: 'b',
            category: _room,
            bandId: 'band-lower',
            from: '2026-10-01',
          ),
        ),
        isNull,
      );
    });

    test(
      'a component that names no band, where rules require one, says so',
      () {
        final set = RevenueTaxRuleSet([
          rule(id: 'lower', category: _room, bandId: 'band-lower'),
          rule(id: 'upper', category: _room, bandId: 'band-upper'),
        ]);

        final outcome = set.resolve(facts(category: _room));

        expect(outcome, isA<RevenueTaxMissingFact>());
        expect(
          (outcome as RevenueTaxMissingFact).dimension,
          RevenueTaxDimension.valueBand,
        );
        expect(outcome.message, contains('value band'));
      },
    );

    test('a band the configuration does not know is a no-rule refusal', () {
      final set = RevenueTaxRuleSet([
        rule(id: 'lower', category: _room, bandId: 'band-lower'),
      ]);

      expect(
        set.resolve(facts(category: _room, bandId: 'band-unknown')),
        isA<RevenueTaxNoApplicableRule>(),
      );
    });

    test(
      'THE AGGREGATE AMOUNT CANNOT DETERMINE THE BAND — there is no amount to read',
      () {
        // D-094. A day's room revenue attributable to a band is not a per-room-per-night
        // tariff, and comparing the two would be arithmetic nonsense that compiles.
        //
        // The guarantee here is structural rather than behavioural: `RevenueTaxFacts`
        // carries no monetary field at all, so no resolver code path can consult one. The
        // proof is that two components with wildly different amounts and the same band
        // resolve to the same rule — because the amount was never an input.
        final set = RevenueTaxRuleSet([
          rule(id: 'lower', category: _room, bandId: 'band-lower', rateBp: 500),
          rule(
            id: 'upper',
            category: _room,
            bandId: 'band-upper',
            rateBp: 1200,
          ),
        ]);

        final tiny = facts(category: _room, bandId: 'band-upper');
        final huge = facts(category: _room, bandId: 'band-upper');

        expect(set.resolve(tiny).ruleOrNull!.id, 'upper');
        expect(set.resolve(huge).ruleOrNull!.id, 'upper');

        // And the fact set exposes nothing money-shaped to be tempted by.
        expect(
          tiny.discriminators.whereType<Money>(),
          isEmpty,
          reason: 'a monetary discriminator would reopen D-094',
        );
      },
    );
  });

  group('supply subtype and premises status', () {
    test(
      'different subtypes over the same dates are legal and resolve apart',
      () {
        final set = RevenueTaxRuleSet([
          rule(id: 'hall', category: _banquet, subtypeId: 'sub-hall'),
          rule(
            id: 'food',
            category: _banquet,
            subtypeId: 'sub-food',
            rateBp: 1800,
          ),
        ]);

        expect(
          set.conflictFor(
            rule(id: 'x', category: _banquet, subtypeId: 'sub-other'),
          ),
          isNull,
        );
        expect(
          set
              .resolve(facts(category: _banquet, subtypeId: 'sub-food'))
              .ruleOrNull!
              .id,
          'food',
        );
      },
    );

    test('a required subtype not chosen is a missing fact', () {
      final set = RevenueTaxRuleSet([
        rule(id: 'hall', category: _banquet, subtypeId: 'sub-hall'),
      ]);

      final outcome = set.resolve(facts(category: _banquet));

      expect(outcome, isA<RevenueTaxMissingFact>());
      expect(
        (outcome as RevenueTaxMissingFact).dimension,
        RevenueTaxDimension.supplySubtype,
      );
    });

    test('premises status distinguishes two otherwise identical rules', () {
      final set = RevenueTaxRuleSet([
        rule(id: 'sched-a', premisesStatus: 'STATUS_A'),
        rule(id: 'sched-b', premisesStatus: 'STATUS_B', rateBp: 1800),
      ]);

      expect(
        set.resolve(facts(premisesStatus: 'STATUS_B')).ruleOrNull!.id,
        'sched-b',
      );
    });

    test(
      'a required premises status that is not configured is a missing fact',
      () {
        final set = RevenueTaxRuleSet([
          rule(id: 'sched-a', premisesStatus: 'STATUS_A'),
        ]);

        final outcome = set.resolve(facts());

        expect(outcome, isA<RevenueTaxMissingFact>());
        expect(
          (outcome as RevenueTaxMissingFact).dimension,
          RevenueTaxDimension.premisesStatus,
        );
      },
    );
  });

  group('incomplete or incoherent configuration is refused', () {
    test('a rule with no input basis does not resolve', () {
      final set = RevenueTaxRuleSet([rule(id: 'legacy', basis: null)]);

      final outcome = set.resolve(facts());

      expect(outcome, isA<RevenueTaxIncompleteRule>());
      expect(outcome.message, contains('which amount is entered'));
    });

    test('an inclusive treatment with a pre-tax basis is incoherent', () {
      // "Type the pre-tax amount, and the tax is already inside it" is not a thing.
      final set = RevenueTaxRuleSet([
        rule(id: 'bad', basis: EnteredBasis.preTax),
      ]);

      expect(set.resolve(facts()), isA<RevenueTaxIncompleteRule>());
      expect(
        set.conflictFor(rule(id: 'bad2', basis: EnteredBasis.preTax)),
        RevenueRuleConflict.incoherentBasis,
      );
    });

    test('treatment none is coherent with any basis', () {
      // Arithmetically inert, and inclusive_total is still the better record (D-091).
      for (final basis in EnteredBasis.values) {
        expect(basis.coherentWith(TaxTreatment.none), isTrue);
      }
    });

    test('an exclusive treatment requires a pre-tax basis', () {
      expect(EnteredBasis.preTax.coherentWith(TaxTreatment.exclusive), isTrue);
      expect(
        EnteredBasis.inclusiveTotal.coherentWith(TaxTreatment.exclusive),
        isFalse,
      );
    });

    test('a rate outside 0–100% is refused', () {
      final set = RevenueTaxRuleSet(const []);

      expect(
        set.conflictFor(rule(id: 'x', rateBp: 10001)),
        RevenueRuleConflict.ratePercentOutOfRange,
      );
      expect(
        set.conflictFor(rule(id: 'y', rateBp: -1)),
        RevenueRuleConflict.ratePercentOutOfRange,
      );
    });

    test('a rule ending before it starts is refused', () {
      expect(
        RevenueTaxRuleSet(
          const [],
        ).conflictFor(rule(id: 'x', from: '2026-10-01', to: '2026-04-01')),
        RevenueRuleConflict.endsBeforeItStarts,
      );
    });

    test('band bounds without a band identity are refused', () {
      // The bounds are explanation for a band; without one they are a number nothing
      // selects on, which is exactly the shape D-094 warns about.
      expect(
        RevenueTaxRuleSet(
          const [],
        ).conflictFor(rule(id: 'x', bandFloor: Money.fromRupees(7500))),
        RevenueRuleConflict.bandWithoutIdentity,
      );
    });
  });

  group('the arithmetic is the existing canonical implementation', () {
    test('5% inclusive of ₹1,00,000 extracts ₹4,761.90 and nets ₹95,238.10', () {
      // 10000000 × 500 ÷ 10500 = 476190.476… → 476190 paise, half-up at the record.
      final resolved =
          RevenueTaxRuleSet([rule(id: 'r1')]).resolve(facts())
              as RevenueTaxResolved;

      final computed = resolved.rule.compute(Money.fromRupees(100000));

      expect(computed.gross, Money.fromRupees(100000));
      expect(computed.tax, Money.fromPaise(476190));
      expect(computed.net, Money.fromPaise(9523810));
      expect(computed.reconciles, isTrue);
    });

    test('treatment none leaves the entered amount whole', () {
      final resolved =
          RevenueTaxRuleSet([
                rule(
                  id: 'banquet',
                  category: _banquet,
                  treatment: TaxTreatment.none,
                ),
              ]).resolve(facts(category: _banquet))
              as RevenueTaxResolved;

      final computed = resolved.rule.compute(Money.fromPaise(4034300));

      expect(computed.gross, Money.fromPaise(4034300));
      expect(computed.tax, Money.zero);
      expect(computed.net, Money.fromPaise(4034300));
    });

    test('an odd amount still reconciles exactly', () {
      final resolved =
          RevenueTaxRuleSet([rule(id: 'r1')]).resolve(facts())
              as RevenueTaxResolved;

      for (final paise in [1, 7, 33, 12345, 999999, 100000001]) {
        final c = resolved.rule.compute(Money.fromPaise(paise));
        expect(
          c.reconciles,
          isTrue,
          reason: '$paise paise must reconcile to the paisa',
        );
      }
    });
  });

  test('a snapshot is independent of later rule mutation', () {
    // Historical stability (spec §8.1): the figures and the rule identity are frozen onto
    // the component, so re-rating from today's table is not merely discouraged — the
    // component does not consult the table at all.
    final original = rule(id: 'r1', rateBp: 500);
    final computed = original.compute(Money.fromRupees(100000));

    // The configuration changes: the old rule is end-dated and a new rate takes over.
    final set = RevenueTaxRuleSet([
      original.copyWith(effectiveTo: on('2026-07-01')),
      rule(id: 'r2', from: '2026-07-01', rateBp: 1800),
    ]);

    expect(set.resolve(facts(date: '2026-08-01')).ruleOrNull!.id, 'r2');
    expect(
      computed.tax,
      Money.fromPaise(476190),
      reason: 'the recorded figure must not move when configuration does',
    );
    expect(computed.rateBasisPoints, 500);
    expect(computed.ruleId, 'r1');
  });
}
