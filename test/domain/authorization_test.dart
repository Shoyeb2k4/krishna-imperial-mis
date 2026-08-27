/// Authorisation depends on five things at once: user, capability, business-unit scope,
/// record state and period state. These tests exist to stop any one of them being
/// quietly forgotten.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/auth/authorizer.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/period/period_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

const String ccr = 'bu-crystal-canopy';
const String hki = 'bu-hotel-krishna';

Principal scoped(
  String userId,
  Set<Capability> capabilities,
  List<String> units,
) => Principal(
  userId: userId,
  grants: [
    for (final unit in units)
      for (final capability in capabilities)
        CapabilityGrant(capability, businessUnitId: unit),
  ],
);

Principal owner(String userId) => Principal(
  userId: userId,
  grants: [for (final c in RoleTemplates.owner) CapabilityGrant(c)],
);

void main() {
  final today = BusinessDate.of(2026, 6, 20);
  final recent = BusinessDate.of(2026, 6, 18);
  final old = BusinessDate.of(2026, 6, 1);

  Authorizer open() =>
      Authorizer(periodRegistry: InMemoryPeriodRegistry.allOpen());

  Authorizer withClosed(String periodKey, {String? unit}) => Authorizer(
    periodRegistry: InMemoryPeriodRegistry([
      PeriodLock(
        periodKey: periodKey,
        businessUnitId: unit,
        state: PeriodState.closed,
        closedBy: 'owner',
        closedAt: DateTime.utc(2026, 7, 1),
      ),
    ]),
  );

  group('a Manager never means "can access everything"', () {
    test('a manager scoped to one property cannot act on the other', () {
      final manager = scoped('u-manager', RoleTemplates.manager, [ccr]);

      expect(
        open()
            .authorizeCreate(
              principal: manager,
              capability: Capability.expenseCreate,
              businessUnitId: ccr,
              businessDate: today,
            )
            .isAllowed,
        isTrue,
      );

      final denied = open().authorizeCreate(
        principal: manager,
        capability: Capability.expenseCreate,
        businessUnitId: hki,
        businessDate: today,
      );
      expect(denied.isAllowed, isFalse);
      expect((denied as Denied).reason, DenialReason.outOfUnitScope);
      expect(denied.message, contains('this business unit'));
    });

    test('covering both properties takes two explicit grants', () {
      final both = scoped('u-manager', RoleTemplates.manager, [ccr, hki]);
      for (final unit in [ccr, hki]) {
        expect(
          open()
              .authorizeCreate(
                principal: both,
                capability: Capability.expenseCreate,
                businessUnitId: unit,
                businessDate: today,
              )
              .isAllowed,
          isTrue,
        );
      }
    });

    test('an owner holds capabilities org-wide, with no unit enumerated', () {
      final shoyeb = owner('u-owner');
      expect(shoyeb.scopedUnitsFor(Capability.expenseVoid), isNull);
      for (final unit in [ccr, hki, 'bu-future-outlet']) {
        expect(
          shoyeb.can(Capability.expenseVoid, businessUnitId: unit),
          isTrue,
        );
      }
    });

    test('a scoped principal enumerates exactly its units', () {
      final manager = scoped('u-manager', RoleTemplates.manager, [ccr]);
      expect(manager.scopedUnitsFor(Capability.expenseCreate), {ccr});
    });

    test('a principal with nothing granted fails closed', () {
      final decision = open().authorizeCreate(
        principal: Principal.anonymous,
        capability: Capability.expenseCreate,
        businessUnitId: ccr,
        businessDate: today,
      );
      expect((decision as Denied).reason, DenialReason.missingCapability);
    });

    test('missing entirely is distinguished from wrong property', () {
      final dataEntry = scoped('u-de', RoleTemplates.dataEntry, [ccr]);
      // Data Entry has no void capability anywhere.
      final noCapability = open().authorizeCreate(
        principal: dataEntry,
        capability: Capability.expenseVoid,
        businessUnitId: ccr,
        businessDate: today,
      );
      expect((noCapability as Denied).reason, DenialReason.missingCapability);

      // It does have create, but not for the other property.
      final wrongUnit = open().authorizeCreate(
        principal: dataEntry,
        capability: Capability.expenseCreate,
        businessUnitId: hki,
        businessDate: today,
      );
      expect((wrongUnit as Denied).reason, DenialReason.outOfUnitScope);
    });
  });

  group('record ownership', () {
    test('own-scoped edit reaches only the user\'s own entries', () {
      final dataEntry = scoped('u-de', RoleTemplates.dataEntry, [ccr]);

      final mine = open().authorizeMutation(
        principal: dataEntry,
        capability: Capability.expenseEditAll,
        ownScopedCapability: Capability.expenseEditOwn,
        businessUnitId: ccr,
        record: RecordContext(createdByUserId: 'u-de', businessDate: recent),
        today: today,
      );
      expect(mine.isAllowed, isTrue);

      final someoneElses = open().authorizeMutation(
        principal: dataEntry,
        capability: Capability.expenseEditAll,
        ownScopedCapability: Capability.expenseEditOwn,
        businessUnitId: ccr,
        record: RecordContext(createdByUserId: 'u-other', businessDate: recent),
        today: today,
      );
      expect((someoneElses as Denied).reason, DenialReason.notRecordOwner);
    });

    test('an accountant edits anyone\'s entry', () {
      final accountant = scoped('u-acc', RoleTemplates.accountant, [ccr]);
      final decision = open().authorizeMutation(
        principal: accountant,
        capability: Capability.expenseEditAll,
        ownScopedCapability: Capability.expenseEditOwn,
        businessUnitId: ccr,
        record: RecordContext(createdByUserId: 'u-other', businessDate: recent),
        today: today,
      );
      expect(decision.isAllowed, isTrue);
    });
  });

  group('voided records are immutable', () {
    test('even an owner cannot edit a voided entry', () {
      final decision = open().authorizeMutation(
        principal: owner('u-owner'),
        capability: Capability.expenseEditAll,
        businessUnitId: ccr,
        record: RecordContext(
          createdByUserId: 'u-owner',
          businessDate: recent,
          isVoided: true,
        ),
        today: today,
      );
      expect((decision as Denied).reason, DenialReason.recordVoided);
      expect(decision.message, contains('new entry'));
    });
  });

  group('period locks', () {
    test('a closed period refuses every write, owner included', () {
      final decision = withClosed('2026-06').authorizeMutation(
        principal: owner('u-owner'),
        capability: Capability.expenseEditAll,
        businessUnitId: ccr,
        record: RecordContext(createdByUserId: 'u-owner', businessDate: recent),
        today: today,
      );
      expect((decision as Denied).reason, DenialReason.periodClosed);
      expect(decision.message, contains('reopen'));
    });

    test('back-dating a new entry into a closed period is refused too', () {
      final decision = withClosed('2026-06').authorizeCreate(
        principal: owner('u-owner'),
        capability: Capability.expenseCreate,
        businessUnitId: ccr,
        businessDate: recent,
      );
      expect((decision as Denied).reason, DenialReason.periodClosed);
    });

    test('a closed period reports itself, not a permissions problem', () {
      // The distinction matters: telling a manager "no permission" when the real reason
      // is a closed month sends them to the wrong person.
      final manager = scoped('u-manager', RoleTemplates.manager, [ccr]);
      final decision = withClosed('2026-06').authorizeCreate(
        principal: manager,
        capability: Capability.expenseCreate,
        businessUnitId: ccr,
        businessDate: recent,
      );
      expect((decision as Denied).reason, DenialReason.periodClosed);
    });

    test('a unit-scoped close leaves the other property open', () {
      final authorizer = withClosed('2026-06', unit: ccr);
      expect(
        authorizer
            .authorizeCreate(
              principal: owner('u-owner'),
              capability: Capability.expenseCreate,
              businessUnitId: hki,
              businessDate: recent,
            )
            .isAllowed,
        isTrue,
      );
      expect(
        authorizer
            .authorizeCreate(
              principal: owner('u-owner'),
              capability: Capability.expenseCreate,
              businessUnitId: ccr,
              businessDate: recent,
            )
            .isAllowed,
        isFalse,
      );
    });

    test('an open period after the closed one is unaffected', () {
      expect(
        withClosed('2026-06')
            .authorizeCreate(
              principal: owner('u-owner'),
              capability: Capability.expenseCreate,
              businessUnitId: ccr,
              businessDate: BusinessDate.of(2026, 7, 2),
            )
            .isAllowed,
        isTrue,
      );
    });

    test('nothing reopens a period implicitly', () {
      final registry = InMemoryPeriodRegistry([
        const PeriodLock(
          periodKey: '2026-06',
          state: PeriodState.closed,
          closedBy: 'u-owner',
        ),
      ]);
      final authorizer = Authorizer(periodRegistry: registry);

      // Repeated attempts must not wear the lock down.
      for (var i = 0; i < 5; i++) {
        expect(
          authorizer
              .authorizeCreate(
                principal: owner('u-owner'),
                capability: Capability.expenseCreate,
                businessUnitId: ccr,
                businessDate: recent,
              )
              .isAllowed,
          isFalse,
        );
      }
      expect(
        registry.stateFor(periodKey: '2026-06', businessUnitId: ccr),
        PeriodState.closed,
      );
    });

    test('reopening demands a reason', () {
      final authorizer = withClosed('2026-06');
      expect(
        () => authorizer.authorizePeriodReopen(
          principal: owner('u-owner'),
          businessUnitId: ccr,
          reason: '   ',
        ),
        throwsArgumentError,
      );
      expect(
        authorizer
            .authorizePeriodReopen(
              principal: owner('u-owner'),
              businessUnitId: ccr,
              reason: 'Vendor invoice arrived after close',
            )
            .isAllowed,
        isTrue,
      );
    });

    test('only the owner may close or reopen', () {
      final accountant = scoped('u-acc', RoleTemplates.accountant, [ccr]);
      expect(
        open()
            .authorizePeriodClose(principal: accountant, businessUnitId: ccr)
            .isAllowed,
        isFalse,
      );
      expect(
        open()
            .authorizePeriodReopen(
              principal: accountant,
              businessUnitId: ccr,
              reason: 'because',
            )
            .isAllowed,
        isFalse,
      );
    });

    test('the lock object itself refuses a reasonless reopen', () {
      const lock = PeriodLock(periodKey: '2026-06', state: PeriodState.closed);
      expect(
        () => lock.reopenedByActor('u-owner', DateTime.utc(2026, 7, 5), ''),
        throwsArgumentError,
      );
      final reopened = lock.reopenedByActor(
        'u-owner',
        DateTime.utc(2026, 7, 5),
        'Late electricity invoice',
      );
      expect(reopened.state, PeriodState.open);
      expect(reopened.reopenedBy, 'u-owner');
      expect(reopened.reopenReason, 'Late electricity invoice');
    });
  });

  group('edit window', () {
    test('a manager may edit inside the seven-day window', () {
      final manager = scoped('u-manager', RoleTemplates.manager, [ccr]);
      final decision = open().authorizeMutation(
        principal: manager,
        capability: Capability.expenseEditAll,
        ownScopedCapability: Capability.expenseEditOwn,
        businessUnitId: ccr,
        record: RecordContext(
          createdByUserId: 'u-manager',
          businessDate: recent,
        ),
        today: today,
      );
      expect(decision.isAllowed, isTrue);
    });

    test('the boundary is inclusive at exactly seven days', () {
      final manager = scoped('u-manager', RoleTemplates.manager, [ccr]);
      AuthorizationDecision at(BusinessDate date) => open().authorizeMutation(
        principal: manager,
        capability: Capability.expenseEditAll,
        ownScopedCapability: Capability.expenseEditOwn,
        businessUnitId: ccr,
        record: RecordContext(createdByUserId: 'u-manager', businessDate: date),
        today: today,
      );

      expect(at(BusinessDate.of(2026, 6, 13)).isAllowed, isTrue); // 7 days
      expect(at(BusinessDate.of(2026, 6, 12)).isAllowed, isFalse); // 8 days
    });

    test('beyond the window a manager is refused with the real reason', () {
      final manager = scoped('u-manager', RoleTemplates.manager, [ccr]);
      final decision = open().authorizeMutation(
        principal: manager,
        capability: Capability.expenseEditAll,
        ownScopedCapability: Capability.expenseEditOwn,
        businessUnitId: ccr,
        record: RecordContext(createdByUserId: 'u-manager', businessDate: old),
        today: today,
      );
      expect((decision as Denied).reason, DenialReason.outsideEditWindow);
      expect(decision.message, contains('accountant'));
    });

    test(
      'an accountant corrects beyond the window while the period is open',
      () {
        final accountant = scoped('u-acc', RoleTemplates.accountant, [ccr]);
        final decision = open().authorizeMutation(
          principal: accountant,
          capability: Capability.expenseEditAll,
          businessUnitId: ccr,
          record: RecordContext(
            createdByUserId: 'u-manager',
            businessDate: old,
          ),
          today: today,
        );
        expect(decision.isAllowed, isTrue);
      },
    );

    test('the window length is configuration, not a constant', () {
      final manager = scoped('u-manager', RoleTemplates.manager, [ccr]);
      final generous = Authorizer(
        periodRegistry: InMemoryPeriodRegistry.allOpen(),
        editWindowDays: 30,
      );
      expect(
        generous
            .authorizeMutation(
              principal: manager,
              capability: Capability.expenseEditAll,
              ownScopedCapability: Capability.expenseEditOwn,
              businessUnitId: ccr,
              record: RecordContext(
                createdByUserId: 'u-manager',
                businessDate: old,
              ),
              today: today,
            )
            .isAllowed,
        isTrue,
      );
    });

    test('a closed period beats the edit window in the message shown', () {
      // Both would refuse; the user must hear the one they can act on.
      final accountant = scoped('u-acc', RoleTemplates.accountant, [ccr]);
      final decision = withClosed('2026-06').authorizeMutation(
        principal: accountant,
        capability: Capability.expenseEditAll,
        businessUnitId: ccr,
        record: RecordContext(createdByUserId: 'u-acc', businessDate: old),
        today: today,
      );
      expect((decision as Denied).reason, DenialReason.periodClosed);
    });
  });

  group('cross-period allocation (D-034)', () {
    test('requires its own capability, which a manager does not hold', () {
      final manager = scoped('u-manager', RoleTemplates.manager, [ccr]);
      final decision = open().authorizePeriodAllocation(
        principal: manager,
        businessUnitId: ccr,
        periodKey: '2026-05',
      );
      expect((decision as Denied).reason, DenialReason.missingCapability);
    });

    test('an accountant may allocate across open periods', () {
      final accountant = scoped('u-acc', RoleTemplates.accountant, [ccr]);
      for (final period in ['2026-05', '2026-06']) {
        expect(
          open()
              .authorizePeriodAllocation(
                principal: accountant,
                businessUnitId: ccr,
                periodKey: period,
              )
              .isAllowed,
          isTrue,
        );
      }
    });

    test('each target period is checked separately', () {
      // The electricity case: 15 May – 14 June, with May already closed.
      final accountant = scoped('u-acc', RoleTemplates.accountant, [ccr]);
      final authorizer = withClosed('2026-05');

      expect(
        authorizer
            .authorizePeriodAllocation(
              principal: accountant,
              businessUnitId: ccr,
              periodKey: '2026-06',
            )
            .isAllowed,
        isTrue,
      );
      final may = authorizer.authorizePeriodAllocation(
        principal: accountant,
        businessUnitId: ccr,
        periodKey: '2026-05',
      );
      expect((may as Denied).reason, DenialReason.periodClosed);
    });
  });

  group('enforce()', () {
    test('allowed passes through, denied throws with the reason intact', () {
      const AuthorizationDecision.allowed().enforce();
      expect(
        () => const AuthorizationDecision.denied(
          DenialReason.periodClosed,
        ).enforce(),
        throwsA(
          isA<AuthorizationFailure>().having(
            (e) => e.reason,
            'reason',
            DenialReason.periodClosed,
          ),
        ),
      );
    });
  });

  group('capability catalogue', () {
    test('codes are stable and round-trip', () {
      for (final capability in Capability.values) {
        expect(Capability.fromCode(capability.code), capability);
      }
      expect(Capability.expenseCreate.code, 'expense.create');
      expect(Capability.periodReopen.code, 'period.reopen');
    });

    test('role bundles reflect the specified separation of duties', () {
      expect(RoleTemplates.manager.contains(Capability.expenseVoid), isFalse);
      expect(RoleTemplates.manager.contains(Capability.periodClose), isFalse);
      expect(
        RoleTemplates.manager.contains(Capability.expenseAllocatePeriods),
        isFalse,
      );
      expect(RoleTemplates.accountant.contains(Capability.expenseVoid), isTrue);
      expect(
        RoleTemplates.accountant.contains(Capability.periodClose),
        isFalse,
      );
      expect(RoleTemplates.owner.contains(Capability.periodReopen), isTrue);
      expect(RoleTemplates.dataEntry.contains(Capability.reportsView), isFalse);
    });

    test('only the owner role may go unscoped', () {
      expect(RoleTemplates.requiresUnitScope(RoleTemplates.ownerCode), isFalse);
      for (final role in [
        RoleTemplates.managerCode,
        RoleTemplates.accountantCode,
        RoleTemplates.dataEntryCode,
      ]) {
        expect(RoleTemplates.requiresUnitScope(role), isTrue);
      }
    });
  });
}
