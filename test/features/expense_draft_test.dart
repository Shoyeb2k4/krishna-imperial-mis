/// The rules a user experiences as "why is Save greyed out".
///
/// Tested here rather than through a widget, because they are the same rules on Android
/// and on Windows and they are about money, not about pixels.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/masters/master_hierarchy.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_draft.dart';

const _ccr = 'ccr';
const _hki = 'hki';
final _june15 = BusinessDate.of(2026, 6, 15);

MasterNode _node(
  String id,
  String name, {
  String? parent,
  bool archived = false,
}) => MasterNode(
  id: id,
  code: id.toUpperCase(),
  name: name,
  parentId: parent,
  archivedAt: archived ? DateTime.utc(2026, 1, 1) : null,
);

/// Two properties, each with one department, section and category, plus an archived
/// category to prove it is never offered.
MasterGraph _graph() => MasterGraph(
  businessUnits: [
    _node(_ccr, 'Crystal Canopy Rooftop'),
    _node(_hki, 'Hotel Krishna Imperial'),
  ],
  departments: [
    _node('ccr-kitchen', 'Kitchen', parent: _ccr),
    _node('hki-util', 'Utilities', parent: _hki),
  ],
  sections: [
    _node('ccr-food', 'Food Production', parent: 'ccr-kitchen'),
    _node('hki-power', 'Power & Fuel', parent: 'hki-util'),
  ],
  expenseCategories: [
    _node('ccr-veg', 'Vegetables & Fruits', parent: 'ccr-food'),
    _node('ccr-kirana', 'Kirana & Pulses', parent: 'ccr-food'),
    _node('ccr-old', 'Discontinued', parent: 'ccr-food', archived: true),
    _node('hki-elec', 'Electricity', parent: 'hki-power'),
  ],
);

Principal _principal(Set<Capability> bundle, Set<String?> units) => Principal(
  userId: 'u',
  grants: [
    for (final unit in units)
      for (final capability in bundle)
        CapabilityGrant(capability, businessUnitId: unit),
  ],
);

Principal get _ccrManager => _principal(RoleTemplates.manager, const {_ccr});
Principal get _bothManager =>
    _principal(RoleTemplates.manager, const {_ccr, _hki});
Principal get _accountant =>
    _principal(RoleTemplates.accountant, const {_ccr, _hki});

ExpenseDraft _classifiedCcr({Money? amount}) {
  var draft = ExpenseDraft.blank(businessDate: _june15, id: 'exp-1');
  final line = draft.allocations.first.id;
  draft = draft
      .withClassification(line, businessUnitId: _ccr)
      .withClassification(line, departmentId: 'ccr-kitchen')
      .withClassification(line, sectionId: 'ccr-food')
      .withClassification(line, categoryId: 'ccr-kirana');
  return amount == null ? draft : draft.withTotal(amount);
}

void main() {
  group('the routine case is one number and one classification', () {
    test('a simple expense keeps its single line in step with the total', () {
      final draft = _classifiedCcr(amount: Money.fromRupees(8500));

      expect(draft.isSimple, isTrue);
      expect(draft.allocations, hasLength(1));
      expect(draft.allocations.single.amount, Money.fromRupees(8500));
      expect(draft.total, Money.fromRupees(8500));
      expect(draft.remaining, Money.zero);
      expect(draft.reconciles, isTrue);
      expect(draft.canSave(_ccrManager), isTrue);
    });

    test('it produces one allocation and one derived contribution', () {
      final document = _classifiedCcr(amount: Money.fromRupees(8500))
          .toDocument(
            orgId: 'org',
            createdByUserId: 'u',
            capturedAt: DateTime.utc(2026, 6, 15, 9),
            labelFor: (_) => 'Kirana & Pulses',
          );

      expect(document.allocations, hasLength(1));
      expect(document.reportingRows, hasLength(1));
      expect(document.reportedTotal, Money.fromRupees(8500));
      expect(
        document.allocations.single.periodContributions.single.isDerived,
        isTrue,
        reason: 'the user never had to think about accounting periods',
      );
    });

    test('an incomplete classification cannot be saved', () {
      var draft = ExpenseDraft.blank(businessDate: _june15);
      draft = draft.withTotal(Money.fromRupees(500));

      expect(
        draft.problemsFor(_ccrManager),
        contains(DraftProblem.classificationIncomplete),
      );
      expect(draft.canSave(_ccrManager), isFalse);
    });

    test('zero and negative are refused', () {
      for (final amount in [Money.zero, Money.fromRupees(-100)]) {
        final draft = _classifiedCcr(amount: amount);
        expect(
          draft.problemsFor(_ccrManager),
          contains(DraftProblem.amountNotPositive),
        );
      }
    });

    test('a missing amount is its own message, not a validation shrug', () {
      final draft = _classifiedCcr();
      expect(
        draft.problemsFor(_ccrManager),
        contains(DraftProblem.amountMissing),
      );
      expect(DraftProblem.amountMissing.message, 'Enter the amount.');
    });
  });

  group('changing a parent invalidates its children', () {
    test('switching property clears department, section and category', () {
      var draft = _classifiedCcr(amount: Money.fromRupees(500));
      final line = draft.allocations.first.id;

      draft = draft.withClassification(line, businessUnitId: _hki);
      final updated = draft.allocations.single;

      expect(updated.businessUnitId, _hki);
      expect(
        updated.departmentId,
        isNull,
        reason: 'a Crystal Canopy department under Hotel Krishna is impossible',
      );
      expect(updated.sectionId, isNull);
      expect(updated.categoryId, isNull);
    });

    test('switching department clears section and category only', () {
      var draft = _classifiedCcr(amount: Money.fromRupees(500));
      final line = draft.allocations.first.id;

      draft = draft.withClassification(line, departmentId: 'ccr-other');
      final updated = draft.allocations.single;

      expect(updated.businessUnitId, _ccr);
      expect(updated.departmentId, 'ccr-other');
      expect(updated.sectionId, isNull);
      expect(updated.categoryId, isNull);
    });

    test('switching section clears the category only', () {
      var draft = _classifiedCcr(amount: Money.fromRupees(500));
      final line = draft.allocations.first.id;

      draft = draft.withClassification(line, sectionId: 'ccr-other-section');
      expect(draft.allocations.single.departmentId, 'ccr-kitchen');
      expect(draft.allocations.single.categoryId, isNull);
    });

    test('re-selecting the same parent changes nothing', () {
      final draft = _classifiedCcr(amount: Money.fromRupees(500));
      final line = draft.allocations.first.id;

      final same = draft.withClassification(line, businessUnitId: _ccr);
      expect(same.allocations.single.categoryId, 'ccr-kirana');
    });

    test('the amount survives a reclassification', () {
      var draft = _classifiedCcr(amount: Money.fromRupees(500));
      final line = draft.allocations.first.id;
      draft = draft.withClassification(line, businessUnitId: _hki);

      expect(
        draft.allocations.single.amount,
        Money.fromRupees(500),
        reason: 'the figure was right; only where it is charged changed',
      );
    });
  });

  group('the picker offers nothing impossible', () {
    test('only properties this user may charge', () {
      expect(
        ExpenseDraft.selectableUnits(_graph(), _ccrManager).map((u) => u.id),
        [_ccr],
      );
      expect(
        ExpenseDraft.selectableUnits(_graph(), _bothManager).map((u) => u.id),
        [_ccr, _hki],
      );
    });

    test('archived categories are not offered for a new entry', () {
      // Sorted for the picker, so the assertion is about membership, not order.
      final categories = _graph().categoriesOf('ccr-food');
      expect(categories.map((c) => c.id).toSet(), {'ccr-veg', 'ccr-kirana'});
      expect(
        categories.map((c) => c.id),
        isNot(contains('ccr-old')),
        reason: 'archived masters stay valid for history, not for new entries',
      );
    });

    test('children come only from the chosen parent', () {
      expect(_graph().departmentsOf(_ccr).map((d) => d.id), ['ccr-kitchen']);
      expect(_graph().sectionsOf('ccr-kitchen').map((s) => s.id), ['ccr-food']);
      expect(_graph().categoriesOf('hki-power').map((c) => c.id), ['hki-elec']);
    });
  });

  group('splitting between properties', () {
    ExpenseDraft sharedBill({int ccrRupees = 25000, int hkiRupees = 33000}) {
      var draft = _classifiedCcr().copyWith(total: Money.fromRupees(58000));
      draft = draft.asSplit();
      final first = draft.allocations.first.id;
      draft = draft.withAllocationAmount(first, Money.fromRupees(ccrRupees));

      draft = draft.addAllocation();
      final second = draft.allocations.last.id;
      draft = draft
          .withClassification(second, businessUnitId: _hki)
          .withClassification(second, departmentId: 'hki-util')
          .withClassification(second, sectionId: 'hki-power')
          .withClassification(second, categoryId: 'hki-elec')
          .withAllocationAmount(second, Money.fromRupees(hkiRupees));
      return draft;
    }

    test('₹25,000 + ₹33,000 against ₹58,000 reconciles exactly', () {
      final draft = sharedBill();

      expect(draft.allocated, Money.fromRupees(58000));
      expect(draft.remaining, Money.zero);
      expect(draft.reconciles, isTrue);
      expect(draft.isCrossUnit, isTrue);
      expect(draft.canSave(_accountant), isTrue);
    });

    test('₹25,000 + ₹32,000 leaves ₹1,000 remaining and will not save', () {
      final draft = sharedBill(hkiRupees: 32000);

      expect(draft.remaining, Money.fromRupees(1000));
      expect(draft.reconciles, isFalse);
      expect(
        draft.problemsFor(_accountant),
        contains(DraftProblem.allocationsDoNotReconcile),
      );
      expect(
        draft.allocations,
        hasLength(2),
        reason: 'no hidden adjustment line is invented to make it balance',
      );
    });

    test('over-allocating shows a negative remainder, not a silent trim', () {
      final draft = sharedBill(hkiRupees: 40000);
      expect(draft.remaining, Money.fromRupees(-7000));
      expect(draft.reconciles, isFalse);
    });

    test('a manager holding both scopes still may not split', () {
      final draft = sharedBill();
      expect(
        draft.problemsFor(_bothManager),
        contains(DraftProblem.crossUnitNotPermitted),
      );
      expect(ExpenseDraft.mayUseSplit(_bothManager), isFalse);
      expect(ExpenseDraft.mayUseSplit(_accountant), isTrue);
    });

    test('a Crystal Canopy manager cannot even name Hotel Krishna', () {
      final draft = sharedBill();
      expect(
        draft.problemsFor(_ccrManager),
        contains(DraftProblem.unitOutsideScope),
      );
      expect(
        ExpenseDraft.selectableUnits(_graph(), _ccrManager).map((u) => u.id),
        isNot(contains(_hki)),
      );
    });

    test('a line can be added copying the previous classification', () {
      var draft = _classifiedCcr(amount: Money.fromRupees(500));
      draft = draft.addAllocation(copyClassification: true);

      final added = draft.allocations.last;
      expect(added.businessUnitId, _ccr);
      expect(added.categoryId, 'ccr-kirana');
      expect(added.amount, isNull, reason: 'the figure is always deliberate');
    });

    test('the last line can never be removed', () {
      final draft = _classifiedCcr(amount: Money.fromRupees(500));
      expect(
        draft.removeAllocation(draft.allocations.first.id).allocations,
        hasLength(1),
      );
    });

    test('removing a line leaves the total alone, and the remainder shows', () {
      var draft = sharedBill();
      draft = draft.removeAllocation(draft.allocations.last.id);

      expect(draft.total, Money.fromRupees(58000));
      expect(draft.allocated, Money.fromRupees(25000));
      expect(draft.remaining, Money.fromRupees(33000));
      expect(draft.canSave(_accountant), isFalse);
    });

    test('the produced document balances to the paisa', () {
      final document = sharedBill().toDocument(
        orgId: 'org',
        createdByUserId: 'u',
        capturedAt: DateTime.utc(2026, 6, 15),
        labelFor: (id) => id,
      );
      expect(document.total, Money.fromRupees(58000));
      expect(document.reportedTotal, Money.fromRupees(58000));
      expect(document.businessUnitIds, {_ccr, _hki});
    });
  });

  group('splitting across accounting periods', () {
    ExpenseDraft withProposal() {
      var draft = _classifiedCcr(amount: Money.fromRupees(60000));
      final line = draft.allocations.first.id;
      return draft = draft.proposePeriodSplit(line, [
        (
          start: BusinessDate.of(2026, 5, 15),
          end: BusinessDate.of(2026, 5, 31),
        ),
        (start: BusinessDate.of(2026, 6, 1), end: BusinessDate.of(2026, 6, 14)),
      ]);
    }

    test('the proposal already reconciles, and is visible before saving', () {
      final draft = withProposal();
      final line = draft.allocations.single;

      expect(line.periodSplits, hasLength(2));
      expect(line.splitTotal, Money.fromRupees(60000));
      expect(line.splitRemaining, Money.zero);
      expect(line.splitReconciles, isTrue);
      expect(line.periodSplits.map((s) => s.amount), [
        Money.fromRupees(30000),
        Money.fromRupees(30000),
      ]);
      expect(line.periodSplits.map((s) => s.periodKey), ['2026-05', '2026-06']);
    });

    test('the user may change a proposed figure, and must rebalance it', () {
      var draft = withProposal();
      final line = draft.allocations.first.id;
      final first = draft.allocations.first.periodSplits.first.id;

      draft = draft.withPeriodAmount(line, first, Money.fromRupees(20000));
      expect(draft.allocations.single.splitRemaining, Money.fromRupees(10000));
      expect(
        draft.problemsFor(_accountant),
        contains(DraftProblem.periodSplitDoesNotReconcile),
      );

      final second = draft.allocations.first.periodSplits.last.id;
      draft = draft.withPeriodAmount(line, second, Money.fromRupees(40000));
      expect(draft.allocations.single.splitReconciles, isTrue);
      expect(draft.canSave(_accountant), isTrue);
    });

    test('an odd amount proposes a split that still adds up', () {
      var draft = _classifiedCcr(amount: Money.fromPaise(100001));
      final line = draft.allocations.first.id;
      draft = draft.proposePeriodSplit(line, [
        (start: BusinessDate.of(2026, 4, 1), end: BusinessDate.of(2026, 4, 30)),
        (start: BusinessDate.of(2026, 5, 1), end: BusinessDate.of(2026, 5, 31)),
        (start: BusinessDate.of(2026, 6, 1), end: BusinessDate.of(2026, 6, 30)),
      ]);

      final splits = draft.allocations.single.periodSplits;
      expect(splits, hasLength(3));
      expect(
        Money.sum(splits.map((s) => s.amount!)),
        Money.fromPaise(100001),
        reason: 'largest remainder, so the proposal reconciles exactly',
      );
      expect(splits.map((s) => s.amount!.paise).toSet().length, greaterThan(1));
    });

    test('a manager may not split across periods', () {
      final draft = withProposal();
      expect(
        draft.problemsFor(_ccrManager),
        contains(DraftProblem.periodSplitNotPermitted),
      );
      expect(ExpenseDraft.mayUsePeriodSplit(_ccrManager), isFalse);
      expect(ExpenseDraft.mayUsePeriodSplit(_accountant), isTrue);
    });

    test('clearing the split returns the line to the ordinary rule', () {
      var draft = withProposal();
      draft = draft.clearPeriodSplit(draft.allocations.first.id);

      expect(draft.allocations.single.hasPeriodSplit, isFalse);
      expect(draft.hasAnyPeriodSplit, isFalse);
      expect(draft.canSave(_ccrManager), isTrue);
    });

    test('a split line contributes to each month and nowhere else', () {
      final document = withProposal().toDocument(
        orgId: 'org',
        createdByUserId: 'u',
        capturedAt: DateTime.utc(2026, 6, 15),
        labelFor: (id) => id,
      );

      final byPeriod = <String, Money>{};
      for (final row in document.reportingRows) {
        byPeriod[row.periodKey] =
            (byPeriod[row.periodKey] ?? Money.zero) + row.amount;
      }
      expect(byPeriod, {
        '2026-05': Money.fromRupees(30000),
        '2026-06': Money.fromRupees(30000),
      });
      expect(document.reportedTotal, Money.fromRupees(60000));
    });
  });

  group('payment', () {
    test('unpaid is the default and needs nothing else', () {
      final draft = _classifiedCcr(amount: Money.fromRupees(500));
      expect(draft.paymentStatus, PaymentStatus.unpaid);
      expect(draft.canSave(_ccrManager), isTrue);
    });

    test('paid without a date or a method cannot be saved', () {
      final draft = _classifiedCcr(
        amount: Money.fromRupees(500),
      ).copyWith(paymentStatus: PaymentStatus.paid);

      expect(
        draft.problemsFor(_ccrManager),
        contains(DraftProblem.paymentIncomplete),
      );
    });

    test('paid with both is fine, and does not move the accounting period', () {
      final draft = _classifiedCcr(amount: Money.fromRupees(80000)).copyWith(
        businessDate: BusinessDate.of(2026, 6, 30),
        accountingPeriodStart: BusinessDate.of(2026, 6, 1),
        accountingPeriodEnd: BusinessDate.of(2026, 6, 30),
        paymentStatus: PaymentStatus.paid,
        paymentDate: BusinessDate.of(2026, 7, 5),
        paymentMethodId: 'bank',
      );

      expect(draft.canSave(_ccrManager), isTrue);

      final document = draft.toDocument(
        orgId: 'org',
        createdByUserId: 'u',
        capturedAt: DateTime.utc(2026, 7, 5),
        labelFor: (id) => id,
      );
      expect(document.periodKeys, {'2026-06'});
      expect(document.paymentDate, BusinessDate.of(2026, 7, 5));
    });
  });

  group('what the form remembers between expenses', () {
    test('a still-valid chain is offered again in full', () {
      final last = LastUsedClassification.from(
        _classifiedCcr(amount: Money.fromRupees(500)),
      );
      final valid = last.validAgainst(_graph(), _ccrManager);

      expect(valid.businessUnitId, _ccr);
      expect(valid.categoryId, 'ccr-kirana');
    });

    test('an archived category is dropped, and its parents are kept', () {
      const last = LastUsedClassification(
        businessUnitId: _ccr,
        departmentId: 'ccr-kitchen',
        sectionId: 'ccr-food',
        categoryId: 'ccr-old',
      );
      final valid = last.validAgainst(_graph(), _ccrManager);

      expect(valid.sectionId, 'ccr-food');
      expect(
        valid.categoryId,
        isNull,
        reason: 'an archived master is never pre-filled for a new entry',
      );
    });

    test('a property outside scope is dropped entirely', () {
      const last = LastUsedClassification(
        businessUnitId: _hki,
        departmentId: 'hki-util',
        sectionId: 'hki-power',
        categoryId: 'hki-elec',
      );
      final valid = last.validAgainst(_graph(), _ccrManager);

      expect(valid.businessUnitId, isNull);
      expect(valid.departmentId, isNull);
      expect(valid.categoryId, isNull);
    });

    test('a chain whose parentage no longer holds is truncated', () {
      // The section was re-parented, or the department was replaced. Either way the
      // remembered category no longer hangs where it did.
      const last = LastUsedClassification(
        businessUnitId: _ccr,
        departmentId: 'ccr-kitchen',
        sectionId: 'hki-power',
        categoryId: 'hki-elec',
      );
      final valid = last.validAgainst(_graph(), _ccrManager);

      expect(valid.departmentId, 'ccr-kitchen');
      expect(valid.sectionId, isNull);
    });
  });

  group('amount parsing is exact or refused', () {
    test('reads what a user would type', () {
      expect(Money.tryParse('12500'), Money.fromRupees(12500));
      expect(Money.tryParse('12500.50'), Money.fromPaise(1250050));
      expect(Money.tryParse('₹12,500.50'), Money.fromPaise(1250050));
      expect(Money.tryParse('  8500 '), Money.fromRupees(8500));
    });

    test('refuses what it cannot read exactly', () {
      for (final bad in ['', 'abc', '12.345', '1.2.3', '12,5x0']) {
        expect(
          Money.tryParse(bad),
          isNull,
          reason: '"$bad" must not be silently rounded or guessed at',
        );
      }
    });
  });
}
