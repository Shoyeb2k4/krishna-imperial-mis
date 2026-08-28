/// Who may record, correct and void an expense — the rules an expense adds on top of
/// the general authoriser, every one of them because an expense can touch more than one
/// property and more than one month at once.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/auth/authorizer.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/domain/expenses/expense_authorization.dart';
import 'package:krishna_mis/domain/period/period_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

const _ccr = 'ccr';
const _hki = 'hki';
final _june15 = BusinessDate.of(2026, 6, 15);
final _today = BusinessDate.of(2026, 6, 18);

Principal _principal({
  required String userId,
  required Set<Capability> bundle,
  required Set<String?> units,
}) => Principal(
  userId: userId,
  grants: [
    for (final unit in units)
      for (final capability in bundle)
        CapabilityGrant(capability, businessUnitId: unit),
  ],
);

Principal get _ccrManager => _principal(
  userId: 'manager',
  bundle: RoleTemplates.manager,
  units: const {_ccr},
);

Principal get _bothManager => _principal(
  userId: 'manager-both',
  bundle: RoleTemplates.manager,
  units: const {_ccr, _hki},
);

Principal get _accountant => _principal(
  userId: 'accountant',
  bundle: RoleTemplates.accountant,
  units: const {_ccr, _hki},
);

Principal get _dataEntry => _principal(
  userId: 'data-entry',
  bundle: RoleTemplates.dataEntry,
  units: const {_ccr},
);

Principal get _owner => _principal(
  userId: 'owner',
  bundle: RoleTemplates.owner,
  units: const {null},
);

ExpenseAllocation _line(String unit, int rupees, {BusinessDate? date}) =>
    ExpenseAllocation.wholePeriod(
      id: '$unit-line',
      businessUnitId: unit,
      departmentId: '$unit-d',
      sectionId: '$unit-s',
      categoryId: '$unit-c',
      amount: Money.fromRupees(rupees),
      businessDate: date ?? _june15,
    );

ExpenseDocument _expense(
  List<ExpenseAllocation> lines, {
  String createdBy = 'manager',
  BusinessDate? businessDate,
}) => ExpenseDocument(
  id: 'exp-1',
  orgId: 'org-1',
  businessDate: businessDate ?? _june15,
  businessDateSource: BusinessDateSource.derived,
  total: Money.sum(lines.map((l) => l.amount)),
  allocations: lines,
  paymentStatus: PaymentStatus.unpaid,
  createdByUserId: createdBy,
  capturedAt: DateTime.utc(2026, 6, 15, 9),
);

/// [closed] is `periodKey` → `businessUnitId`, so a test names exactly which month of
/// which property is shut.
ExpenseAuthorizer _authorizer({Map<String, String> closed = const {}}) =>
    ExpenseAuthorizer(
      Authorizer(
        periodRegistry: InMemoryPeriodRegistry([
          for (final entry in closed.entries)
            PeriodLock(
              periodKey: entry.key,
              businessUnitId: entry.value,
              state: PeriodState.closed,
            ),
        ]),
      ),
    );

RecordContext _record({String createdBy = 'manager', BusinessDate? date}) =>
    RecordContext(createdByUserId: createdBy, businessDate: date ?? _june15);

void main() {
  group('scope over every unit the expense charges', () {
    test('a single-unit expense in scope is allowed', () {
      final decision = _authorizer().authorizeCreate(
        principal: _ccrManager,
        expense: _expense([_line(_ccr, 200)]),
      );
      expect(decision.isAllowed, isTrue);
    });

    test('a single-unit expense outside scope is refused', () {
      final decision = _authorizer().authorizeCreate(
        principal: _ccrManager,
        expense: _expense([_line(_hki, 200)]),
      );
      expect(decision, isA<ExpenseDenied>());
      expect(
        (decision as ExpenseDenied).reason,
        ExpenseDenialReason.unitOutsideScope,
      );
      expect(decision.detail, _hki);
    });

    test('a Crystal Canopy manager can never charge anything to Hotel Krishna, '
        'even alongside a line they may charge', () {
      // The check that matters: scope over the *first* unit must not be mistaken for
      // scope over the expense.
      final decision = _authorizer().authorizeCreate(
        principal: _ccrManager,
        expense: _expense([_line(_ccr, 25000), _line(_hki, 33000)]),
      );

      expect(decision, isA<ExpenseDenied>());
      expect(
        (decision as ExpenseDenied).reason,
        ExpenseDenialReason.unitOutsideScope,
      );
      expect(decision.detail, _hki);
    });
  });

  group('a cross-unit split needs its own permission (D-061)', () {
    test('holding both scopes is not enough on its own', () {
      // This manager may record against either property. Apportioning one cost between
      // them is a different act, and moves both properties' profitability.
      final decision = _authorizer().authorizeCreate(
        principal: _bothManager,
        expense: _expense([_line(_ccr, 25000), _line(_hki, 33000)]),
      );

      expect(decision, isA<ExpenseDenied>());
      expect(
        (decision as ExpenseDenied).reason,
        ExpenseDenialReason.crossUnitNotPermitted,
      );
      expect(decision.message, isNot(contains('Manager')));
    });

    test(
      'the same manager may still record a single-unit expense in either',
      () {
        for (final unit in [_ccr, _hki]) {
          expect(
            _authorizer()
                .authorizeCreate(
                  principal: _bothManager,
                  expense: _expense([_line(unit, 1000)]),
                )
                .isAllowed,
            isTrue,
          );
        }
      },
    );

    test('an accountant scoped to both may split', () {
      final decision = _authorizer().authorizeCreate(
        principal: _accountant,
        expense: _expense([_line(_ccr, 25000), _line(_hki, 33000)]),
      );
      expect(decision.isAllowed, isTrue);
    });

    test('the Owner role may split', () {
      final decision = _authorizer().authorizeCreate(
        principal: _owner,
        expense: _expense([_line(_ccr, 25000), _line(_hki, 33000)]),
      );
      expect(decision.isAllowed, isTrue);
    });

    test('the capability is not in the operational bundles', () {
      expect(
        RoleTemplates.manager,
        isNot(contains(Capability.expenseAllocateCrossUnit)),
      );
      expect(
        RoleTemplates.dataEntry,
        isNot(contains(Capability.expenseAllocateCrossUnit)),
      );
      expect(
        RoleTemplates.accountant,
        contains(Capability.expenseAllocateCrossUnit),
      );
      expect(
        RoleTemplates.owner,
        contains(Capability.expenseAllocateCrossUnit),
      );
    });
  });

  group('a deliberate period split needs its own permission (D-034)', () {
    ExpenseDocument split(BusinessDate mayEnd, BusinessDate junEnd) =>
        _expense([
          ExpenseAllocation(
            id: 'l1',
            businessUnitId: _ccr,
            departmentId: 'd',
            sectionId: 's',
            categoryId: 'c',
            amount: Money.fromRupees(60000),
            periodContributions: [
              PeriodContribution(
                id: 'p1',
                periodStart: BusinessDate.of(2026, 5, 15),
                periodEnd: mayEnd,
                amount: Money.fromRupees(30000),
                isDerived: false,
              ),
              PeriodContribution(
                id: 'p2',
                periodStart: BusinessDate.of(2026, 6, 1),
                periodEnd: junEnd,
                amount: Money.fromRupees(30000),
                isDerived: false,
              ),
            ],
          ),
        ]);

    test('a manager may not split a cost across months', () {
      final decision = _authorizer().authorizeCreate(
        principal: _ccrManager,
        expense: split(
          BusinessDate.of(2026, 5, 31),
          BusinessDate.of(2026, 6, 14),
        ),
      );
      expect(
        (decision as ExpenseDenied).reason,
        ExpenseDenialReason.periodSplitNotPermitted,
      );
    });

    test('an accountant may', () {
      expect(
        _authorizer()
            .authorizeCreate(
              principal: _accountant,
              expense: split(
                BusinessDate.of(2026, 5, 31),
                BusinessDate.of(2026, 6, 14),
              ),
            )
            .isAllowed,
        isTrue,
      );
    });

    test('an ordinary expense does not need the split permission, even though its '
        'contribution is generated for it', () {
      // Every line carries contributions now (D-060). A data-entry user recording a
      // ₹200 grocery bill must not be asked for `expense.allocate_periods` because the
      // system filled one in on their behalf.
      expect(
        RoleTemplates.dataEntry,
        isNot(contains(Capability.expenseAllocatePeriods)),
      );
      expect(
        _authorizer()
            .authorizeCreate(
              principal: _dataEntry,
              expense: _expense([_line(_ccr, 200)]),
            )
            .isAllowed,
        isTrue,
      );
    });

    test('a closed month refuses the whole document, not half of it', () {
      final decision = _authorizer(closed: const {'2026-05': _ccr})
          .authorizeCreate(
            principal: _accountant,
            expense: split(
              BusinessDate.of(2026, 5, 31),
              BusinessDate.of(2026, 6, 14),
            ),
          );

      expect(
        (decision as ExpenseDenied).reason,
        ExpenseDenialReason.periodClosed,
      );
      expect(decision.detail, contains('2026-05'));
    });
  });

  group('voiding (project-lead decision)', () {
    test('Data Entry and Manager cannot void at all', () {
      for (final principal in [_dataEntry, _ccrManager]) {
        final decision = _authorizer().authorizeVoid(
          principal: principal,
          expense: _expense([_line(_ccr, 200)]),
          record: _record(createdBy: principal.userId),
          today: _today,
          reason: 'Entered twice',
        );
        expect(
          decision.isAllowed,
          isFalse,
          reason: '${principal.userId} must not be able to void',
        );
      }
      expect(RoleTemplates.manager, isNot(contains(Capability.expenseVoid)));
      expect(RoleTemplates.dataEntry, isNot(contains(Capability.expenseVoid)));
    });

    test('an accountant may void while the period is open', () {
      expect(
        _authorizer()
            .authorizeVoid(
              principal: _accountant,
              expense: _expense([_line(_ccr, 200)]),
              record: _record(),
              today: _today,
              reason: 'Duplicate of KI-EXP-26-27-000012',
            )
            .isAllowed,
        isTrue,
      );
    });

    test('there is no age limit while the period is open', () {
      // Three months old, far beyond the seven-day edit window, and still voidable.
      final old = BusinessDate.of(2026, 3, 2);
      final decision = _authorizer().authorizeVoid(
        principal: _accountant,
        expense: _expense([_line(_ccr, 200, date: old)], businessDate: old),
        record: _record(date: old),
        today: BusinessDate.of(2026, 6, 18),
        reason: 'Wrong vendor',
      );

      expect(decision.isAllowed, isTrue);
      expect(VoidPolicy.respectsEditWindow, isFalse);
    });

    test(
      'a closed period refuses the void, and the lock is never bypassed',
      () {
        final decision = _authorizer(closed: const {'2026-06': _ccr})
            .authorizeVoid(
              principal: _owner,
              expense: _expense([_line(_ccr, 200)]),
              record: _record(),
              today: _today,
              reason: 'Wrong vendor',
            );

        expect(decision.isAllowed, isFalse);
        expect(
          (decision as ExpenseDenied).message,
          isNot(contains('permission')),
          reason: 'the Owner has permission; the period is what refused',
        );
      },
    );

    test('a void without a reason is refused, whoever asks', () {
      for (final reason in [null, '', '   ']) {
        final decision = _authorizer().authorizeVoid(
          principal: _owner,
          expense: _expense([_line(_ccr, 200)]),
          record: _record(),
          today: _today,
          reason: reason,
        );
        expect(
          (decision as ExpenseDenied).reason,
          ExpenseDenialReason.voidReasonMissing,
        );
      }
    });

    test('an already voided document is immutable', () {
      final decision = _authorizer().authorizeVoid(
        principal: _owner,
        expense: _expense([_line(_ccr, 200)]),
        record: RecordContext(
          createdByUserId: 'manager',
          businessDate: _june15,
          isVoided: true,
        ),
        today: _today,
        reason: 'Again',
      );
      expect(decision.isAllowed, isFalse);
    });
  });

  group('editing', () {
    test('the edit window still governs an ordinary edit', () {
      final old = BusinessDate.of(2026, 6, 1);
      final decision = _authorizer().authorizeEdit(
        principal: _ccrManager,
        expense: _expense(
          [_line(_ccr, 200, date: old)],
          createdBy: 'manager',
          businessDate: old,
        ),
        record: _record(date: old),
        today: BusinessDate.of(2026, 6, 30),
      );
      expect(
        decision.isAllowed,
        isFalse,
        reason: 'twenty-nine days is well past the seven-day window',
      );
    });

    test('an edit cannot smuggle in a cross-unit split', () {
      final decision = _authorizer().authorizeEdit(
        principal: _bothManager,
        expense: _expense([_line(_ccr, 25000), _line(_hki, 33000)]),
        record: _record(createdBy: 'manager-both'),
        today: _today,
      );
      expect(
        (decision as ExpenseDenied).reason,
        ExpenseDenialReason.crossUnitNotPermitted,
      );
    });

    test('an edit cannot move a line into a closed month', () {
      final decision = _authorizer(closed: const {'2026-06': _ccr})
          .authorizeEdit(
            principal: _accountant,
            expense: _expense([_line(_ccr, 200)]),
            record: _record(),
            today: _today,
          );
      expect(decision.isAllowed, isFalse);
    });
  });
}
