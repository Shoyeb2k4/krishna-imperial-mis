/// Date-effective tax rules.
///
/// The two things that must never happen: a rate change silently restating history, and
/// two rules both claiming one date. Boundary dates are tested exactly, not approximately.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

TaxRule rule({
  String id = 'r1',
  String category = 'cat-restaurant',
  int rateBp = 500,
  TaxTreatment treatment = TaxTreatment.inclusive,
  String from = '2026-04-01',
  String? to,
  DateTime? archivedAt,
}) => TaxRule(
  id: id,
  revenueCategoryId: category,
  rateBasisPoints: rateBp,
  treatment: treatment,
  effectiveFrom: BusinessDate.tryParse(from)!,
  effectiveTo: to == null ? null : BusinessDate.tryParse(to),
  archivedAt: archivedAt,
);

BusinessDate on(String iso) => BusinessDate.tryParse(iso)!;

void main() {
  group('inclusive extraction — the normal case for both properties', () {
    test('5% inclusive on the specification example', () {
      // Restaurant sales of ₹76,450 recorded tax-inclusive at 5%.
      final result = rule().compute(const Money.fromRupees(76450));

      expect(result.gross, const Money.fromRupees(76450));
      // 7645000 × 500 ÷ 10500 = 364047.6... → 364048 paise
      expect(result.tax, const Money.fromPaise(364048));
      expect(result.net, const Money.fromPaise(7280952));
      expect(result.reconciles, isTrue);
    });

    test('a round figure divides cleanly', () {
      // ₹1,050 inclusive of 5% is ₹1,000 + ₹50.
      final result = rule().compute(const Money.fromRupees(1050));
      expect(result.tax, const Money.fromRupees(50));
      expect(result.net, const Money.fromRupees(1000));
    });

    test('net plus tax always equals gross, across many awkward amounts', () {
      for (final paise in [1, 7, 99, 12345, 7645000, 999999999]) {
        for (final rateBp in [0, 100, 500, 1200, 1800, 2800]) {
          final result = rule(rateBp: rateBp).compute(Money.fromPaise(paise));
          expect(
            result.reconciles,
            isTrue,
            reason: 'did not reconcile: $paise paise at $rateBp bp',
          );
          expect(result.gross, Money.fromPaise(paise));
        }
      }
    });

    test('zero revenue produces zero tax, not a division problem', () {
      final result = rule().compute(Money.zero);
      expect(result.tax, Money.zero);
      expect(result.net, Money.zero);
    });

    test('a zero rate leaves the amount untouched', () {
      final result = rule(rateBp: 0).compute(const Money.fromRupees(1000));
      expect(result.tax, Money.zero);
      expect(result.net, const Money.fromRupees(1000));
    });
  });

  group('exclusive and none', () {
    test('exclusive adds tax on top', () {
      final result = rule(
        treatment: TaxTreatment.exclusive,
        rateBp: 1800,
      ).compute(const Money.fromRupees(1000));

      expect(result.net, const Money.fromRupees(1000));
      expect(result.tax, const Money.fromRupees(180));
      expect(result.gross, const Money.fromRupees(1180));
      expect(result.reconciles, isTrue);
    });

    test('none passes the figure straight through', () {
      final result = rule(
        treatment: TaxTreatment.none,
        rateBp: 500,
      ).compute(const Money.fromRupees(8700));
      expect(result.tax, Money.zero);
      expect(result.gross, const Money.fromRupees(8700));
      expect(result.net, const Money.fromRupees(8700));
      expect(result.rateBasisPoints, 0);
    });

    test('negative revenue is refused rather than quietly taxed', () {
      expect(
        () => rule().compute(const Money.fromRupees(-100)),
        throwsArgumentError,
      );
    });
  });

  group('effective periods are half-open', () {
    final r = rule(from: '2026-04-01', to: '2026-07-01');

    test('the start date is included', () {
      expect(r.coversDate(on('2026-04-01')), isTrue);
    });

    test('the day before the start is not', () {
      expect(r.coversDate(on('2026-03-31')), isFalse);
    });

    test('the last day inside the period is included', () {
      expect(r.coversDate(on('2026-06-30')), isTrue);
    });

    test(
      'the end date itself is NOT included — it belongs to the next rule',
      () {
        expect(r.coversDate(on('2026-07-01')), isFalse);
      },
    );

    test('an open-ended rule covers everything from its start', () {
      final open = rule(from: '2026-04-01');
      expect(open.coversDate(on('2026-04-01')), isTrue);
      expect(open.coversDate(on('2030-12-31')), isTrue);
      expect(open.coversDate(on('2026-03-31')), isFalse);
    });

    test('an archived rule covers nothing', () {
      final archived = rule(archivedAt: DateTime.utc(2026, 5, 1));
      expect(archived.coversDate(on('2026-04-15')), isFalse);
    });
  });

  group('overlap detection', () {
    test('adjacent periods do not overlap', () {
      final first = rule(id: 'a', from: '2026-04-01', to: '2026-07-01');
      final second = rule(id: 'b', from: '2026-07-01');
      expect(first.overlaps(second), isFalse);
      expect(second.overlaps(first), isFalse);
    });

    test('a one-day intrusion is an overlap', () {
      final first = rule(id: 'a', from: '2026-04-01', to: '2026-07-02');
      final second = rule(id: 'b', from: '2026-07-01');
      expect(first.overlaps(second), isTrue);
      expect(second.overlaps(first), isTrue);
    });

    test('two open-ended rules always overlap', () {
      expect(
        rule(
          id: 'a',
          from: '2026-04-01',
        ).overlaps(rule(id: 'b', from: '2027-04-01')),
        isTrue,
      );
    });

    test('a rule enclosed by another overlaps', () {
      final outer = rule(id: 'a', from: '2026-01-01', to: '2027-01-01');
      final inner = rule(id: 'b', from: '2026-06-01', to: '2026-07-01');
      expect(outer.overlaps(inner), isTrue);
    });

    test('different categories never overlap', () {
      expect(
        rule(
          id: 'a',
          category: 'restaurant',
        ).overlaps(rule(id: 'b', category: 'room')),
        isFalse,
      );
    });

    test('a rule does not overlap itself', () {
      final r = rule();
      expect(r.overlaps(r), isFalse);
    });

    test('an archived rule does not block a new one', () {
      final archived = rule(id: 'a', archivedAt: DateTime.utc(2026, 5, 1));
      expect(archived.overlaps(rule(id: 'b')), isFalse);
    });
  });

  group('rule sets', () {
    test('resolve the rule in force on a date', () {
      final set = TaxRuleSet([
        rule(id: 'old', rateBp: 500, from: '2025-04-01', to: '2026-04-01'),
        rule(id: 'new', rateBp: 1200, from: '2026-04-01'),
      ]);

      expect(set.ruleFor(on('2025-06-15'))!.id, 'old');
      expect(set.ruleFor(on('2026-03-31'))!.id, 'old');
      // Exactly at the changeover the new rule takes effect.
      expect(set.ruleFor(on('2026-04-01'))!.id, 'new');
      expect(set.ruleFor(on('2027-01-01'))!.id, 'new');
      // Before any rule exists there is no rule — not a silent zero.
      expect(set.ruleFor(on('2024-01-01')), isNull);
    });

    test('a historical report resolves the rate that was in force then', () {
      final set = TaxRuleSet([
        rule(id: 'old', rateBp: 500, from: '2025-04-01', to: '2026-04-01'),
        rule(id: 'new', rateBp: 1200, from: '2026-04-01'),
      ]);

      // Re-running last year's report must still use last year's 5%, not today's 12%.
      final historical = set.ruleFor(on('2025-06-15'))!;
      final result = historical.compute(const Money.fromRupees(1050));
      expect(result.tax, const Money.fromRupees(50));
    });

    test('refuses an overlapping addition', () {
      final set = TaxRuleSet([rule(id: 'a', from: '2026-04-01')]);
      final refusal = set.refusalFor(rule(id: 'b', from: '2026-06-01'));
      expect(refusal, TaxRuleRefusal.overlapsExistingPeriod);
      expect(refusal!.message, contains('already covers'));
    });

    test('accepts a properly adjacent addition', () {
      final set = TaxRuleSet([
        rule(id: 'a', from: '2026-04-01', to: '2026-07-01'),
      ]);
      expect(set.refusalFor(rule(id: 'b', from: '2026-07-01')), isNull);
    });

    test('refuses an end date at or before the start', () {
      final set = TaxRuleSet(const []);
      expect(
        set.refusalFor(rule(from: '2026-07-01', to: '2026-07-01')),
        TaxRuleRefusal.endsBeforeItStarts,
      );
      expect(
        set.refusalFor(rule(from: '2026-07-01', to: '2026-06-01')),
        TaxRuleRefusal.endsBeforeItStarts,
      );
    });

    test('refuses an impossible rate', () {
      final set = TaxRuleSet(const []);
      expect(set.refusalFor(rule(rateBp: -1)), TaxRuleRefusal.rateOutOfRange);
      expect(
        set.refusalFor(rule(rateBp: 10001)),
        TaxRuleRefusal.rateOutOfRange,
      );
      expect(set.refusalFor(rule(rateBp: 10000)), isNull);
    });

    test(
      'reports gaps so an uncovered period is visible before revenue lands in it',
      () {
        final set = TaxRuleSet([
          rule(id: 'a', from: '2026-04-01', to: '2026-06-01'),
          rule(id: 'b', from: '2026-07-01', to: '2026-09-01'),
        ]);

        final gaps = set.gaps();
        expect(gaps.length, 2);
        expect(gaps.first.from.iso, '2026-06-01');
        expect(gaps.first.to!.iso, '2026-07-01');
        // The trailing open period after the last rule ends.
        expect(gaps.last.from.iso, '2026-09-01');
        expect(gaps.last.to, isNull);
      },
    );

    test('an open-ended final rule leaves no trailing gap', () {
      final set = TaxRuleSet([
        rule(id: 'a', from: '2026-04-01', to: '2026-07-01'),
        rule(id: 'b', from: '2026-07-01'),
      ]);
      expect(set.gaps(), isEmpty);
    });
  });

  group('display', () {
    test('renders rates for people, not basis points', () {
      expect(rule(rateBp: 500).ratePercent, '5%');
      expect(rule(rateBp: 1800).ratePercent, '18%');
      expect(rule(rateBp: 1250).ratePercent, '12.5%');
      expect(rule(rateBp: 1205).ratePercent, '12.5%');
      expect(rule(rateBp: 0).ratePercent, '0%');
    });

    test('treatments explain what the user should type', () {
      expect(TaxTreatment.inclusive.entryHint, contains('tax included'));
      expect(TaxTreatment.exclusive.entryHint, contains('before tax'));
    });
  });
}
