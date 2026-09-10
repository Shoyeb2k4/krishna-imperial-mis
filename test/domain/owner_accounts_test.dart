/// The Owner Accounts domain: shares, family attribution and ledger movements.
///
/// Phase 5 OA-1. Pure domain tests — no database, no network, no widgets.
///
/// The controls that matter here are the ones OA-1 §38, §39, §42 and §43 name, and they
/// are written to fail for the right reason rather than to describe what the code does.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/owner_accounts/owner.dart';
import 'package:krishna_mis/domain/owner_accounts/owner_family.dart';
import 'package:krishna_mis/domain/owner_accounts/owner_ledger.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

const ownerA = 'owner-a';
const ownerB = 'owner-b';

BusinessDate d(int y, int m, int day) => BusinessDate.of(y, m, day);

OwnershipShare share(
  String ownerId,
  int bp, {
  required BusinessDate from,
  BusinessDate? to,
}) => OwnershipShare(
  id: '$ownerId-${from.iso}',
  ownerId: ownerId,
  shareBasisPoints: bp,
  effectiveFrom: from,
  effectiveTo: to,
);

/// The current, binding configuration: two owners, 50:50 (OA-D1).
OwnershipShareSet fiftyFifty({BusinessDate? from}) {
  final start = from ?? d(2026, 4, 1);
  return OwnershipShareSet([
    share(ownerA, 5000, from: start),
    share(ownerB, 5000, from: start),
  ]);
}

OwnerLedgerEntry movement({
  required String ownerId,
  required OwnerMovementType type,
  required int paise,
  OwnerLedgerDirection? direction,
  String businessUnitId = 'ccr',
  BusinessDate? date,
  String? familyMemberId,
  String? collectedBy,
  String? reason,
  String? txnNumber = 'KI-OWN-26-27-000001',
  DateTime? voidedAt,
  DateTime? scopeRevokedAt,
}) => OwnerLedgerEntry(
  id: 'entry-${DateTime.now().microsecondsSinceEpoch}-$paise-${type.wireName}',
  orgId: 'org',
  ownerId: ownerId,
  businessUnitId: businessUnitId,
  businessDate: date ?? d(2026, 6, 15),
  movementType: type,
  direction: direction ?? type.fixedDirection ?? OwnerLedgerDirection.debit,
  amount: Money.fromPaise(paise),
  createdByUserId: 'user-1',
  capturedAt: DateTime.utc(2026, 6, 15, 12),
  txnNumber: txnNumber,
  financialYear: txnNumber == null ? null : '26-27',
  familyMemberId: familyMemberId,
  collectedByFamilyMemberId: collectedBy,
  reason: reason,
  voidedAt: voidedAt,
  voidReason: voidedAt == null ? null : 'entered twice',
  scopeRevokedAt: scopeRevokedAt,
);

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('ownership shares · the 50:50 model, exactly (§38)', () {
    test('two owners at 5000 bp each resolve, and total exactly 10000', () {
      final outcome = fiftyFifty().resolveFor(d(2026, 6, 1), d(2026, 6, 30));

      expect(outcome, isA<OwnershipResolved>());
      final resolved = outcome as OwnershipResolved;
      expect(resolved.shares, hasLength(2));
      expect(resolved.totalBasisPoints, 10000);
      expect(
        resolved.shares.map((s) => s.shareBasisPoints),
        everyElement(5000),
        reason:
            'basis points, never 49.999 or 50.001 — there is no double here',
      );
    });

    test('a set that does not total 10000 is refused, never rescaled', () {
      // 5000 + 4000. Silently normalising this to 10000 would allocate profit by a ratio
      // nobody approved, and every figure downstream would reconcile perfectly.
      final lopsided = OwnershipShareSet([
        share(ownerA, 5000, from: d(2026, 4, 1)),
        share(ownerB, 4000, from: d(2026, 4, 1)),
      ]);

      final outcome = lopsided.resolveFor(d(2026, 6, 1), d(2026, 6, 30));
      expect(outcome, isA<OwnershipRefused>());
      expect(
        (outcome as OwnershipRefused).refusal,
        OwnershipRefusal.sharesDoNotTotalOneHundredPercent,
      );
      expect(outcome.detail, contains('9000'));
    });

    test('an over-100% set is refused too', () {
      final over = OwnershipShareSet([
        share(ownerA, 6000, from: d(2026, 4, 1)),
        share(ownerB, 5000, from: d(2026, 4, 1)),
      ]);
      expect(
        (over.resolveFor(d(2026, 6, 1), d(2026, 6, 30)) as OwnershipRefused)
            .refusal,
        OwnershipRefusal.sharesDoNotTotalOneHundredPercent,
      );
    });

    test('no configuration at all is its own refusal, not a zero share', () {
      final none = OwnershipShareSet(const []);
      expect(
        (none.resolveFor(d(2026, 6, 1), d(2026, 6, 30)) as OwnershipRefused)
            .refusal,
        OwnershipRefusal.noShareConfigured,
      );
    });

    test(
      'a share that begins after the period starts does not apply to it',
      () {
        final later = fiftyFifty(from: d(2026, 7, 1));
        expect(
          (later.resolveFor(d(2026, 6, 1), d(2026, 6, 30)) as OwnershipRefused)
              .refusal,
          OwnershipRefusal.noShareConfigured,
        );
      },
    );

    test(
      'one owner holding two shares on one date is refused, not tiebroken',
      () {
        final duplicated = OwnershipShareSet([
          share(ownerA, 5000, from: d(2026, 4, 1)),
          OwnershipShare(
            id: 'a-second',
            ownerId: ownerA,
            shareBasisPoints: 5000,
            effectiveFrom: d(2026, 5, 1),
          ),
        ]);
        expect(
          (duplicated.resolveFor(d(2026, 6, 1), d(2026, 6, 30))
                  as OwnershipRefused)
              .refusal,
          OwnershipRefusal.overlappingShares,
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //
  // **The V1 ownership vector is fixed at [5000, 5000]** — the project lead's ruling of
  // 2026-09-10 (D-204), proven here as the eight properties it names.
  //
  // The general `resolveFor` is deliberately left alone and still resolves any
  // date-effective ratio, because that is what keeps historical records readable
  // (property 7). The ruling is applied on top of it, in one place, so an authorised
  // future 60/40 lifts one rule rather than requiring an audit of every caller.
  //
  // Proven red before it was written: the shipped resolver accepted 60/40, 70/30, a
  // three-owner split and a single owner holding 10000 — every shape the ruling forbids,
  // each of which totals exactly 10000 and so passes a total-only check.
  group('the V1 ownership vector is exactly two owners at 5000 bp (D-204)', () {
    BusinessDate d(int y, int m, int day) => BusinessDate.of(y, m, day);

    OwnershipShare share(
      String owner,
      int basisPoints, {
      int fromYear = 2026,
      int fromMonth = 4,
      BusinessDate? to,
    }) => OwnershipShare(
      id: 'share-$owner-$fromYear-$fromMonth',
      ownerId: owner,
      shareBasisPoints: basisPoints,
      effectiveFrom: d(fromYear, fromMonth, 1),
      effectiveTo: to,
    );

    final june = (d(2026, 6, 1), d(2026, 6, 30));

    OwnershipResolution resolve(List<OwnershipShare> shares) =>
        OwnershipShareSet(shares).resolveV1For(june.$1, june.$2);

    // ── 1, 2, 3 ──────────────────────────────────────────────────────────────
    test('exactly two shares resolve, both 5000 bp, totalling 10000', () {
      final resolved = resolve([share('a', 5000), share('b', 5000)]);

      expect(resolved, isA<OwnershipResolved>());
      final vector = (resolved as OwnershipResolved).shares;

      expect(vector, hasLength(v1OwnerCount));
      expect(
        vector.map((s) => s.shareBasisPoints),
        everyElement(v1ShareBasisPoints),
      );
      expect(resolved.totalBasisPoints, totalOwnershipBasisPoints);
      expect(
        vector.map((s) => s.ownerId),
        ['a', 'b'],
        reason:
            'ordered by owner id, so two identical vectors compare identical',
      );
    });

    // ── 4 ────────────────────────────────────────────────────────────────────
    test('one missing owner refuses', () {
      // A single 5000 share fails the total first, which is the older and stricter
      // rule; a single 10000 share passes the total and is caught by the count. Both
      // are asserted, because only the second needs D-204 to exist.
      expect(
        (resolve([share('a', 5000)]) as OwnershipRefused).refusal,
        OwnershipRefusal.sharesDoNotTotalOneHundredPercent,
      );
      expect(
        (resolve([share('a', 10000)]) as OwnershipRefused).refusal,
        OwnershipRefusal.notExactlyTwoOwners,
      );
    });

    // ── 5 ────────────────────────────────────────────────────────────────────
    test('any non-5000 share refuses, including one that totals 10000', () {
      // This is the case the shipped resolver accepted, and the reason a total-only
      // check is not the rule: 60/40 adds up perfectly and is not the V1 model.
      for (final split in [
        (6000, 4000),
        (4000, 6000),
        (7000, 3000),
        (9999, 1),
        (5001, 4999),
      ]) {
        final refused = resolve([share('a', split.$1), share('b', split.$2)]);
        expect(
          (refused as OwnershipRefused).refusal,
          OwnershipRefusal.shareIsNotHalf,
          reason: '${split.$1}/${split.$2} is not the V1 vector',
        );
        expect(
          refused.detail,
          contains('not $v1ShareBasisPoints'),
          reason:
              'the refusal names the value it expected, not merely that it failed',
        );
      }
    });

    // ── 6 ────────────────────────────────────────────────────────────────────
    test('more than two active shares refuses', () {
      // 4000/3000/3000 totals exactly 10000 and is a three-owner allocation, which the
      // ruling forbids outright — so the count is checked before the values.
      final three = resolve([
        share('a', 4000),
        share('b', 3000),
        share('c', 3000),
      ]);
      expect(
        (three as OwnershipRefused).refusal,
        OwnershipRefusal.notExactlyTwoOwners,
      );
      expect(three.detail, contains('3 of 2'));

      // And a total above 100% is refused by the older rule rather than being scaled
      // to fit — three owners at 5000 each is 150%, and normalising it would allocate
      // profit by a ratio nobody approved.
      expect(
        (resolve([share('a', 5000), share('b', 5000), share('c', 5000)])
                as OwnershipRefused)
            .refusal,
        OwnershipRefusal.sharesDoNotTotalOneHundredPercent,
      );
    });

    test('an inactive owner does not satisfy the count, when the caller says so', () {
      // The ruling says two **active** owners. A share set does not know which owners
      // are archived, so this is enforced only when the caller supplies the fact —
      // inferring it would be guessing, and defaulting to "all active" is what makes
      // an open share left behind on an archived owner satisfy a bare count.
      final shares = OwnershipShareSet([share('a', 5000), share('b', 5000)]);

      expect(
        shares.resolveV1For(june.$1, june.$2, activeOwnerIds: {'a', 'b'}),
        isA<OwnershipResolved>(),
      );
      expect(
        (shares.resolveV1For(june.$1, june.$2, activeOwnerIds: {'a'})
                as OwnershipRefused)
            .refusal,
        OwnershipRefusal.shareBelongsToInactiveOwner,
      );
    });

    // ── 7 ────────────────────────────────────────────────────────────────────
    test('historical records stay readable, and stay what they were', () {
      // A period that really was 60/40 is still stored, still readable, and still
      // resolves under the general rule. What V1 refuses is *settling* it — which is
      // the correct consequence of a ruling that says V1 does not do variable
      // ownership, and is not the same as erasing or restating the record.
      final set = OwnershipShareSet([
        share('a', 6000, fromYear: 2025, fromMonth: 4, to: d(2026, 3, 31)),
        share('b', 4000, fromYear: 2025, fromMonth: 4, to: d(2026, 3, 31)),
        share('a', 5000),
        share('b', 5000),
      ]);

      final historical = set.applicableOn(d(2025, 9, 15));
      expect(historical, hasLength(2));
      expect(historical.map((s) => s.shareBasisPoints), [6000, 4000]);

      expect(
        set.resolveFor(d(2025, 9, 1), d(2025, 9, 30)),
        isA<OwnershipResolved>(),
        reason:
            'the general rule still reads history exactly as it was recorded',
      );
      expect(
        (set.resolveV1For(d(2025, 9, 1), d(2025, 9, 30)) as OwnershipRefused)
            .refusal,
        OwnershipRefusal.shareIsNotHalf,
        reason: 'V1 refuses to settle it rather than pretending it was 50:50',
      );

      // And the current period is unaffected by the presence of history.
      expect(set.resolveV1For(june.$1, june.$2), isA<OwnershipResolved>());
    });

    test(
      'a mid-range ratio change is still refused before the V1 rule is reached',
      () {
        // The §5 policy is not superseded by D-204: a ratio that moves inside a
        // settlement range refuses for that reason, and saying "not 5000" instead would
        // send somebody to look at the wrong thing.
        final set = OwnershipShareSet([
          share('a', 5000, to: d(2026, 6, 30)),
          share('b', 5000, to: d(2026, 6, 30)),
          share('a', 5000, fromMonth: 7),
          share('b', 5000, fromMonth: 7),
        ]);

        expect(
          (set.resolveV1For(d(2026, 6, 1), d(2026, 7, 31)) as OwnershipRefused)
              .refusal,
          OwnershipRefusal.ratioChangesWithinRange,
        );
      },
    );

    test('the V1 constants are stated, not derived from each other', () {
      // If 5000 were computed as half of 10000, a future authorised change would be a
      // change to an expression rather than to a value somebody chose.
      expect(v1OwnerCount, 2);
      expect(v1ShareBasisPoints, 5000);
      expect(
        v1OwnerCount * v1ShareBasisPoints,
        totalOwnershipBasisPoints,
        reason: 'the three agree, and each is written down',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('ownership shares · mid-period changes are refused (§5)', () {
    test('a ratio that lapses inside the range refuses rather than apportions', () {
      // A splits into two halves mid-June. Apportioning would need Operating Profit to
      // accrue evenly through the month, which nothing in this system establishes.
      final changing = OwnershipShareSet([
        share(ownerA, 5000, from: d(2026, 4, 1), to: d(2026, 6, 14)),
        share(ownerA, 6000, from: d(2026, 6, 15)),
        share(ownerB, 5000, from: d(2026, 4, 1), to: d(2026, 6, 14)),
        share(ownerB, 4000, from: d(2026, 6, 15)),
      ]);

      final outcome = changing.resolveFor(d(2026, 6, 1), d(2026, 6, 30));
      expect(outcome, isA<OwnershipRefused>());
      expect(
        (outcome as OwnershipRefused).refusal,
        OwnershipRefusal.ratioChangesWithinRange,
      );
    });

    test(
      'a third owner arriving mid-range is caught, not only an existing one lapsing',
      () {
        // The start-of-range set is complete and totals 10000, so a check that looked only
        // at the first day would resolve happily — and a third owner would appear in the
        // middle of the month with nothing saying so.
        final arriving = OwnershipShareSet([
          share(ownerA, 5000, from: d(2026, 4, 1)),
          share(ownerB, 5000, from: d(2026, 4, 1)),
          share('owner-c', 1000, from: d(2026, 6, 15)),
        ]);

        expect(
          (arriving.resolveFor(d(2026, 6, 1), d(2026, 6, 30))
                  as OwnershipRefused)
              .refusal,
          OwnershipRefusal.ratioChangesWithinRange,
        );
      },
    );

    test(
      'a change aligned to the period boundary resolves for each side of it',
      () {
        final aligned = OwnershipShareSet([
          share(ownerA, 5000, from: d(2026, 4, 1), to: d(2026, 6, 30)),
          share(ownerB, 5000, from: d(2026, 4, 1), to: d(2026, 6, 30)),
          share(ownerA, 6000, from: d(2026, 7, 1)),
          share(ownerB, 4000, from: d(2026, 7, 1)),
        ]);

        // June keeps 50:50 — the historical settlement is untouched by the later change.
        final june =
            aligned.resolveFor(d(2026, 6, 1), d(2026, 6, 30))
                as OwnershipResolved;
        expect(june.shares.map((s) => s.shareBasisPoints), [5000, 5000]);

        // July is the new ratio.
        final july =
            aligned.resolveFor(d(2026, 7, 1), d(2026, 7, 31))
                as OwnershipResolved;
        expect(july.shares.map((s) => s.shareBasisPoints), [6000, 4000]);
        expect(july.totalBasisPoints, 10000);
      },
    );

    test(
      'the legal effective dates are the first and last days of a month',
      () {
        expect(OwnershipShareSet.isLegalEffectiveFrom(d(2026, 7, 1)), isTrue);
        expect(OwnershipShareSet.isLegalEffectiveFrom(d(2026, 7, 15)), isFalse);

        expect(OwnershipShareSet.isLegalEffectiveTo(d(2026, 6, 30)), isTrue);
        expect(OwnershipShareSet.isLegalEffectiveTo(d(2026, 2, 28)), isTrue);
        expect(
          OwnershipShareSet.isLegalEffectiveTo(d(2028, 2, 29)),
          isTrue,
          reason: 'a leap February ends on the 29th',
        );
        expect(OwnershipShareSet.isLegalEffectiveTo(d(2028, 2, 28)), isFalse);
        expect(OwnershipShareSet.isLegalEffectiveTo(d(2026, 6, 15)), isFalse);
      },
    );

    test(
      'an operator proposing a mid-month date is offered the next boundary',
      () {
        expect(
          OwnershipShareSet.nextLegalEffectiveFrom(d(2026, 7, 15)).iso,
          '2026-08-01',
        );
        expect(
          OwnershipShareSet.nextLegalEffectiveFrom(d(2026, 12, 20)).iso,
          '2027-01-01',
          reason: 'and it crosses a year boundary correctly',
        );
        expect(
          OwnershipShareSet.nextLegalEffectiveFrom(d(2026, 8, 1)).iso,
          '2026-08-01',
          reason:
              'a date already on the boundary is not pushed forward a month',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the 50:50 allocation is exact (§38, OA-D1)', () {
    test('a round profit splits evenly and reconciles', () {
      final parts = Money.fromPaise(
        100000000,
      ).allocateByBasisPoints([5000, 5000]);
      expect(parts.map((p) => p.paise), [50000000, 50000000]);
      expect(Money.sum(parts).paise, 100000000);
    });

    test('an odd paisa is distributed, never lost and never invented', () {
      // 100000001 / 2 is 50000000.5 each. Truncation loses a paisa; rounding both up
      // invents one. Largest-remainder gives one part the extra and reconciles exactly.
      final parts = Money.fromPaise(
        100000001,
      ).allocateByBasisPoints([5000, 5000]);
      expect(parts.map((p) => p.paise), [50000001, 50000000]);
      expect(
        Money.sum(parts).paise,
        100000001,
        reason: 'sum of entitlements == distributable profit, to the paisa',
      );
    });

    test('a loss is allocated too, and is not clamped at zero (§19)', () {
      final parts = Money.fromPaise(
        -100000001,
      ).allocateByBasisPoints([5000, 5000]);
      expect(parts.map((p) => p.paise), [-50000001, -50000000]);
      expect(Money.sum(parts).paise, -100000001);
    });

    test(
      'a set that does not total 10000 cannot be used to allocate at all',
      () {
        expect(
          () => Money.fromPaise(100000000).allocateByBasisPoints([5000, 4000]),
          throwsArgumentError,
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('family attribution (§39)', () {
    final spouse = OwnerFamilyMember(
      id: 'fam-a1',
      orgId: 'org',
      ownerId: ownerA,
      displayName: "Owner A's spouse",
      relationshipLabel: 'spouse',
      effectiveFrom: d(2026, 4, 1),
    );
    final son = OwnerFamilyMember(
      id: 'fam-a2',
      orgId: 'org',
      ownerId: ownerA,
      displayName: "Owner A's son",
      relationshipLabel: 'son',
      effectiveFrom: d(2026, 4, 1),
    );
    final bDaughter = OwnerFamilyMember(
      id: 'fam-b1',
      orgId: 'org',
      ownerId: ownerB,
      displayName: "Owner B's daughter",
      effectiveFrom: d(2026, 4, 1),
    );
    final notApproved = OwnerFamilyMember(
      id: 'fam-a3',
      orgId: 'org',
      ownerId: ownerA,
      displayName: "Owner A's cousin",
      effectiveFrom: d(2026, 4, 1),
      mayUseNc: false,
    );

    final mapping = FamilyOwnerMapping([spouse, son, bDaughter, notApproved]);

    test('A1 and A2 both resolve to Owner A; B1 to Owner B', () {
      expect(
        (mapping.attribute('fam-a1', d(2026, 6, 15)) as FamilyAttributed)
            .ownerId,
        ownerA,
      );
      expect(
        (mapping.attribute('fam-a2', d(2026, 6, 15)) as FamilyAttributed)
            .ownerId,
        ownerA,
      );
      expect(
        (mapping.attribute('fam-b1', d(2026, 6, 15)) as FamilyAttributed)
            .ownerId,
        ownerB,
      );
    });

    test(
      'A1 declared against Owner B is refused, never silently re-attributed',
      () {
        final outcome = mapping.attribute(
          'fam-a1',
          d(2026, 6, 15),
          declaredOwnerId: ownerB,
        );
        expect(outcome, isA<FamilyAttributionRefused>());
        expect(
          (outcome as FamilyAttributionRefused).refusal,
          FamilyAttributionRefusal.declaredOwnerMismatch,
        );
        expect(outcome.detail, contains(ownerA));
      },
    );

    test('a declared owner that agrees resolves normally', () {
      expect(
        mapping.attribute('fam-a1', d(2026, 6, 15), declaredOwnerId: ownerA),
        isA<FamilyAttributed>(),
      );
    });

    test('a person not approved for NC is refused with its own reason', () {
      expect(
        (mapping.attribute('fam-a3', d(2026, 6, 15))
                as FamilyAttributionRefused)
            .refusal,
        FamilyAttributionRefusal.notApprovedForNc,
      );
    });

    test('an unapproved person is not offered on the entry surface at all', () {
      final offered = mapping.ncConsumersOn(d(2026, 6, 15)).map((m) => m.id);
      expect(offered, containsAll(['fam-a1', 'fam-a2', 'fam-b1']));
      expect(offered, isNot(contains('fam-a3')));
    });

    test('the mapping is read as at the business date, not as at today', () {
      // The son's link ended in May. A June bill cannot be his.
      final ended = FamilyOwnerMapping([
        OwnerFamilyMember(
          id: 'fam-a2',
          orgId: 'org',
          ownerId: ownerA,
          displayName: "Owner A's son",
          effectiveFrom: d(2026, 4, 1),
          effectiveTo: d(2026, 5, 31),
        ),
      ]);
      expect(
        ended.attribute('fam-a2', d(2026, 5, 20)),
        isA<FamilyAttributed>(),
      );
      expect(
        (ended.attribute('fam-a2', d(2026, 6, 15)) as FamilyAttributionRefused)
            .refusal,
        FamilyAttributionRefusal.unknownPerson,
      );
    });

    test('reassigning a person later does not restate an accepted NC attribution', () {
      // The guarantee is structural, not procedural: the accepted movement carries the
      // owner it resolved to, and reporting never re-joins the mapping. So the mapping
      // can change however it likes and the recorded fact does not move.
      final accepted = movement(
        ownerId: ownerA,
        type: OwnerMovementType.ncConsumption,
        paise: 500000,
        familyMemberId: 'fam-a1',
      );

      // A1 is ended under Owner A and recreated under Owner B, which is the only
      // reassignment the schema permits.
      final reassigned = FamilyOwnerMapping([
        OwnerFamilyMember(
          id: 'fam-a1',
          orgId: 'org',
          ownerId: ownerA,
          displayName: 'spouse',
          effectiveFrom: d(2026, 4, 1),
          effectiveTo: d(2026, 6, 30),
        ),
        OwnerFamilyMember(
          id: 'fam-a1-b',
          orgId: 'org',
          ownerId: ownerB,
          displayName: 'spouse',
          effectiveFrom: d(2026, 7, 1),
        ),
      ]);

      expect(
        accepted.ownerId,
        ownerA,
        reason: 'the recorded attribution is a fact on the row, not a join',
      );
      expect(
        OwnerLedgerTotals.of(ownerA, [accepted]).ncConsumption.paise,
        500000,
      );
      expect(
        OwnerLedgerTotals.of(ownerB, [accepted]).ncConsumption,
        Money.zero,
      );

      // And the mapping really did change, so the test is about the snapshot rather
      // than about nothing having happened.
      expect(
        (reassigned.attribute('fam-a1-b', d(2026, 7, 5)) as FamilyAttributed)
            .ownerId,
        ownerB,
      );
    });

    test('a family member has no share and no account of their own (OA-D7)', () {
      // Stated as a property of the types: there is nowhere to put a family share, and
      // totals are only ever computed for an owner id.
      expect(
        fiftyFifty().shares.map((s) => s.ownerId),
        isNot(contains('fam-a1')),
      );
      expect(
        OwnerLedgerTotals.of('fam-a1', [
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.ncConsumption,
            paise: 500000,
            familyMemberId: 'fam-a1',
          ),
        ]).movementCount,
        0,
        reason: 'a consumer is not an account holder',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('movement types and direction (§43)', () {
    test('the three fixed-direction types are debits', () {
      expect(
        OwnerMovementType.withdrawal.fixedDirection,
        OwnerLedgerDirection.debit,
      );
      expect(
        OwnerMovementType.ncConsumption.fixedDirection,
        OwnerLedgerDirection.debit,
      );
      expect(
        OwnerMovementType.settlementPaid.fixedDirection,
        OwnerLedgerDirection.debit,
      );
    });

    test('the two that can go either way must state a direction', () {
      expect(OwnerMovementType.openingBalance.requiresStatedDirection, isTrue);
      expect(
        OwnerMovementType.manualAdjustment.requiresStatedDirection,
        isTrue,
      );
      expect(OwnerMovementType.withdrawal.requiresStatedDirection, isFalse);
    });

    test('a withdrawal stored as a credit is refused at construction', () {
      expect(
        () => movement(
          ownerId: ownerA,
          type: OwnerMovementType.withdrawal,
          paise: 5000000,
          direction: OwnerLedgerDirection.credit,
        ),
        throwsArgumentError,
        reason: 'one event must have one representation',
      );
    });

    test('a negative amount is refused; the type decides the sign', () {
      expect(
        () => OwnerLedgerEntry(
          id: 'x',
          orgId: 'org',
          ownerId: ownerA,
          businessUnitId: 'hki',
          businessDate: d(2026, 6, 15),
          movementType: OwnerMovementType.withdrawal,
          direction: OwnerLedgerDirection.debit,
          amount: Money.fromPaise(-5000000),
          createdByUserId: 'u',
          capturedAt: DateTime.utc(2026, 6, 15),
        ),
        throwsArgumentError,
      );
    });

    test(
      'a manual adjustment without a reason is refused, whitespace included',
      () {
        for (final blank in [null, '', '   ', '\t', '\n', ' \t\r\n ']) {
          expect(
            () => movement(
              ownerId: ownerA,
              type: OwnerMovementType.manualAdjustment,
              paise: 100,
              direction: OwnerLedgerDirection.credit,
              reason: blank,
            ),
            throwsArgumentError,
            reason: 'a reason of "$blank" is not a reason (spec §14.1)',
          );
        }
        expect(
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.manualAdjustment,
            paise: 100,
            direction: OwnerLedgerDirection.credit,
            reason: 'agreed correction to the April opening figure',
          ).reason,
          isNotEmpty,
        );
      },
    );

    test('only a consumption names a consumer', () {
      expect(
        () => movement(
          ownerId: ownerA,
          type: OwnerMovementType.withdrawal,
          paise: 5000000,
          familyMemberId: 'fam-a2',
        ),
        throwsArgumentError,
        reason: 'a collector is a different fact and is set separately',
      );
      expect(
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.withdrawal,
          paise: 5000000,
          collectedBy: 'fam-a2',
        ).collectedByFamilyMemberId,
        'fam-a2',
      );
    });

    test(
      'the stored wire names are pinned, not taken from the enum name (D-104)',
      () {
        expect(OwnerMovementType.openingBalance.wireName, 'opening_balance');
        expect(OwnerMovementType.ncConsumption.wireName, 'nc_consumption');
        expect(OwnerMovementType.settlementPaid.wireName, 'settlement_paid');
        expect(
          OwnerMovementType.manualAdjustment.wireName,
          'manual_adjustment',
        );
        expect(OwnerMovementType.withdrawal.wireName, 'withdrawal');
        expect(OwnerLedgerDirection.credit.wireName, 'credit');
        expect(OwnerLedgerDirection.debit.wireName, 'debit');

        for (final t in OwnerMovementType.values) {
          expect(OwnerMovementType.fromWire(t.wireName), t);
        }
        expect(
          () => OwnerMovementType.fromWire('drawing'),
          throwsArgumentError,
        );
        expect(
          () => OwnerLedgerDirection.fromWire('DEBIT'),
          throwsArgumentError,
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('ledger totals · the five types stay apart (§42)', () {
    test('each type sums separately and nothing is blended', () {
      final entries = [
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.openingBalance,
          paise: 1000000,
          direction: OwnerLedgerDirection.credit,
        ),
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.withdrawal,
          paise: 5000000,
        ),
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.ncConsumption,
          paise: 800000,
          familyMemberId: 'fam-a0',
        ),
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.ncConsumption,
          paise: 700000,
          familyMemberId: 'fam-a1',
        ),
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.ncConsumption,
          paise: 500000,
          familyMemberId: 'fam-a2',
        ),
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.settlementPaid,
          paise: 250000,
        ),
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.manualAdjustment,
          paise: 100,
          direction: OwnerLedgerDirection.credit,
          reason: 'rounding agreed with the accountant',
        ),
      ];

      final totals = OwnerLedgerTotals.of(ownerA, entries);

      expect(totals.movementCount, 7);
      expect(totals.openingBalance.paise, 1000000);
      expect(totals.withdrawals.paise, 5000000);
      expect(
        totals.ncConsumption.paise,
        2000000,
        reason: 'owner 8,000 + spouse 7,000 + son 5,000 = 20,000 (§18)',
      );
      expect(totals.settlementPaid.paise, 250000);
      expect(totals.manualAdjustment.paise, 100);

      // Signed: opening credit + adjustment credit − withdrawal − NC − settlement.
      expect(
        totals.netMovement.paise,
        1000000 + 100 - 5000000 - 2000000 - 250000,
      );
      expect(
        totals.netMovementExcludingOpening.paise,
        100 - 5000000 - 2000000 - 250000,
      );
    });

    test("one owner's totals contain nothing of the other's", () {
      final entries = [
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.withdrawal,
          paise: 5000000,
        ),
        movement(
          ownerId: ownerB,
          type: OwnerMovementType.withdrawal,
          paise: 9900000,
        ),
      ];
      expect(OwnerLedgerTotals.of(ownerA, entries).withdrawals.paise, 5000000);
      expect(OwnerLedgerTotals.of(ownerB, entries).withdrawals.paise, 9900000);
    });

    test('Owner B with no movements totals zero rather than being absent', () {
      final totals = OwnerLedgerTotals.of(ownerB, [
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.withdrawal,
          paise: 5000000,
        ),
      ]);
      expect(totals.movementCount, 0);
      expect(totals.netMovement, Money.zero);
      expect(totals.withdrawals, Money.zero);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('canonical acceptance · only accepted movements count (§17, §27)', () {
    test('a pending movement contributes nothing and is not counted', () {
      final pending = movement(
        ownerId: ownerA,
        type: OwnerMovementType.withdrawal,
        paise: 5000000,
        txnNumber: null,
      );
      expect(pending.isAccepted, isFalse);
      expect(pending.isCanonical, isFalse);

      final totals = OwnerLedgerTotals.of(ownerA, [pending]);
      expect(
        totals.withdrawals,
        Money.zero,
        reason:
            'a pending Rs 50,000 withdrawal must not read as though the balance '
            'had already moved',
      );
      expect(totals.movementCount, 0);
    });

    test('a voided movement contributes nothing and the row survives', () {
      final voided = movement(
        ownerId: ownerA,
        type: OwnerMovementType.ncConsumption,
        paise: 500000,
        familyMemberId: 'fam-a1',
        voidedAt: DateTime.utc(2026, 6, 20),
      );
      expect(voided.isVoided, isTrue);
      expect(voided.isCanonical, isFalse);
      expect(OwnerLedgerTotals.of(ownerA, [voided]).ncConsumption, Money.zero);
    });

    test('voiding restores the balance by exactly the amount (§29)', () {
      final live = movement(
        ownerId: ownerA,
        type: OwnerMovementType.ncConsumption,
        paise: 500000,
        familyMemberId: 'fam-a1',
      );
      final before = OwnerLedgerTotals.of(ownerA, [live]).netMovement;

      final after = OwnerLedgerTotals.of(ownerA, [
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.ncConsumption,
          paise: 500000,
          familyMemberId: 'fam-a1',
          voidedAt: DateTime.utc(2026, 6, 20),
        ),
      ]).netMovement;

      expect(
        (after - before).paise,
        500000,
        reason: 'exactly Rs 5,000 restored — not approximately',
      );
    });

    test('a scope-revoked movement contributes nothing (D-070, D-074)', () {
      final quarantined = movement(
        ownerId: ownerA,
        type: OwnerMovementType.withdrawal,
        paise: 5000000,
        scopeRevokedAt: DateTime.utc(2026, 7, 1),
      );
      expect(quarantined.isCanonical, isFalse);
      expect(
        OwnerLedgerTotals.of(ownerA, [quarantined]).withdrawals,
        Money.zero,
      );
    });

    test(
      'a correction of the amount moves the position by exactly the difference',
      () {
        // 50,000 corrected to 45,000. The accepted state is one movement at the new figure.
        final before = OwnerLedgerTotals.of(ownerA, [
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.withdrawal,
            paise: 5000000,
          ),
        ]).netMovement;
        final after = OwnerLedgerTotals.of(ownerA, [
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.withdrawal,
            paise: 4500000,
          ),
        ]).netMovement;

        expect((after - before).paise, 500000);
      },
    );

    test('re-attributing an NC moves exactly the amount between two owners', () {
      // Owner A's Rs 5,000 becomes Owner B's. Not duplicated, not approximated.
      final beforeA = OwnerLedgerTotals.of(ownerA, [
        movement(
          ownerId: ownerA,
          type: OwnerMovementType.ncConsumption,
          paise: 500000,
          familyMemberId: 'fam-a1',
        ),
      ]);
      final beforeB = OwnerLedgerTotals.of(ownerB, const []);

      final corrected = [
        movement(
          ownerId: ownerB,
          type: OwnerMovementType.ncConsumption,
          paise: 500000,
          familyMemberId: 'fam-b1',
        ),
      ];
      final afterA = OwnerLedgerTotals.of(ownerA, corrected);
      final afterB = OwnerLedgerTotals.of(ownerB, corrected);

      expect((afterA.netMovement - beforeA.netMovement).paise, 500000);
      expect((afterB.netMovement - beforeB.netMovement).paise, -500000);
      expect(
        afterA.ncConsumption.paise + afterB.ncConsumption.paise,
        500000,
        reason: 'moved, not duplicated',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the collector is never an attribution (§13)', () {
    test(
      'a withdrawal collected by a family member still debits the owner',
      () {
        final entry = movement(
          ownerId: ownerA,
          type: OwnerMovementType.withdrawal,
          paise: 5000000,
          businessUnitId: 'hki',
          collectedBy: 'fam-a2',
        );

        expect(entry.ownerId, ownerA);
        expect(entry.collectedByFamilyMemberId, 'fam-a2');
        expect(
          OwnerLedgerTotals.of(ownerA, [entry]).withdrawals.paise,
          5000000,
          reason: "the son collected it; Owner A's account carries it",
        );
        expect(
          OwnerLedgerTotals.of('fam-a2', [entry]).movementCount,
          0,
          reason: 'there is no family current account',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group(
    'source attribution is preserved and does not decide the share (§10, §35)',
    () {
      test('movements keep the property they came from', () {
        final entries = [
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.withdrawal,
            paise: 5000000,
            businessUnitId: 'hki',
          ),
          movement(
            ownerId: ownerA,
            type: OwnerMovementType.ncConsumption,
            paise: 2000000,
            businessUnitId: 'ccr',
            familyMemberId: 'fam-a1',
          ),
        ];

        expect(
          entries.where((e) => e.businessUnitId == 'hki').single.amount.paise,
          5000000,
        );
        expect(
          entries.where((e) => e.businessUnitId == 'ccr').single.amount.paise,
          2000000,
        );
        // The account total is the same however the movements are attributed.
        expect(
          OwnerLedgerTotals.of(ownerA, entries).netMovement.paise,
          -7000000,
        );
      });

      test('the profit share is organisation-wide and names no property', () {
        final resolved =
            fiftyFifty().resolveFor(d(2026, 6, 1), d(2026, 6, 30))
                as OwnershipResolved;
        // Structural: there is no business unit on a share at all, so a per-property ratio
        // is unavailable rather than merely unused.
        expect(resolved.shares.first.toString(), isNot(contains('ccr')));
        expect(resolved.shares.first.toString(), isNot(contains('hki')));
      });
    },
  );

  // ═══════════════════════════════════════════════════════════════════════════
  group('an owner is not a user (§3, §7)', () {
    test('neither an owner nor a family member carries a user id', () {
      const owner = Owner(
        id: 'owner-a',
        orgId: 'org',
        code: 'OWNER_A',
        displayName: 'Owner A',
      );
      // Asserted through the public surface: there is no field to set, so the mistake is
      // unavailable rather than discouraged.
      expect(owner.toString(), isNot(contains('user')));

      final member = OwnerFamilyMember(
        id: 'fam-a1',
        orgId: 'org',
        ownerId: ownerA,
        displayName: 'spouse',
        effectiveFrom: d(2026, 4, 1),
      );
      expect(member.toString(), isNot(contains('user')));
    });
  });
}
