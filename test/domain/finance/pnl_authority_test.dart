/// Who may read a P&L, stated once for the surfaces (Phase 5 Slice 8).
///
/// The project lead's refinement: a property qualifies for the P&L scope selector only when
/// the principal holds the **full** D2 intersection for it — `reports.view`, `revenue.view`
/// and `expense.view.all` — and the consolidated option only with all three unscoped
/// (D-164, D-187). Business-unit membership, `expense.view.own`, or two scoped grants never
/// qualify. Nothing here names a role.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';

const _ccr = 'ccr';
const _hki = 'hki';

Principal _p(Iterable<CapabilityGrant> grants) =>
    Principal(userId: 'u', grants: grants);

List<CapabilityGrant> _d2(String? unit) => [
  CapabilityGrant(Capability.reportsView, businessUnitId: unit),
  CapabilityGrant(Capability.revenueView, businessUnitId: unit),
  CapabilityGrant(Capability.expenseViewAll, businessUnitId: unit),
];

void main() {
  test('all three capabilities unscoped: every unit, and consolidated', () {
    final p = _p(_d2(null));
    expect(PnlAuthority.mayReadUnit(p, _ccr), isTrue);
    expect(PnlAuthority.mayReadUnit(p, _hki), isTrue);
    expect(PnlAuthority.mayReadConsolidated(p), isTrue);
    expect(PnlAuthority.permittedUnits(p, const [_hki, _ccr]), [_ccr, _hki]);
  });

  test('complete authority for one property only', () {
    final p = _p(_d2(_ccr));
    expect(PnlAuthority.mayReadUnit(p, _ccr), isTrue);
    expect(PnlAuthority.mayReadUnit(p, _hki), isFalse);
    expect(PnlAuthority.mayReadConsolidated(p), isFalse);
    expect(PnlAuthority.permittedUnits(p, const [_ccr, _hki]), [_ccr]);
  });

  for (final missing in [
    Capability.reportsView,
    Capability.revenueView,
    Capability.expenseViewAll,
  ]) {
    test('missing ${missing.code} disqualifies the property', () {
      final p = _p(_d2(_ccr).where((g) => g.capability != missing));
      expect(PnlAuthority.mayReadUnit(p, _ccr), isFalse);
      expect(PnlAuthority.permittedUnits(p, const [_ccr]), isEmpty);
    });

    test('missing an unscoped ${missing.code} refuses consolidated', () {
      final p = _p([
        ..._d2(null).where((g) => g.capability != missing),
        CapabilityGrant(missing, businessUnitId: _ccr),
        CapabilityGrant(missing, businessUnitId: _hki),
      ]);
      expect(PnlAuthority.mayReadConsolidated(p), isFalse);
      // Each property is still fully readable on its own.
      expect(PnlAuthority.mayReadUnit(p, _ccr), isTrue);
      expect(PnlAuthority.mayReadUnit(p, _hki), isTrue);
    });
  }

  test('expense.view.own never substitutes for expense.view.all', () {
    final p = _p([
      const CapabilityGrant(Capability.reportsView, businessUnitId: _ccr),
      const CapabilityGrant(Capability.revenueView, businessUnitId: _ccr),
      const CapabilityGrant(Capability.expenseViewOwn, businessUnitId: _ccr),
    ]);
    expect(PnlAuthority.mayReadUnit(p, _ccr), isFalse);
  });

  test('two complete scoped grants do not add up to consolidated', () {
    final p = _p([..._d2(_ccr), ..._d2(_hki)]);
    expect(PnlAuthority.mayReadUnit(p, _ccr), isTrue);
    expect(PnlAuthority.mayReadUnit(p, _hki), isTrue);
    expect(PnlAuthority.mayReadConsolidated(p), isFalse);
  });

  test('a capability split across properties qualifies neither', () {
    final p = _p([
      const CapabilityGrant(Capability.reportsView, businessUnitId: _ccr),
      const CapabilityGrant(Capability.revenueView, businessUnitId: _ccr),
      const CapabilityGrant(Capability.expenseViewAll, businessUnitId: _hki),
    ]);
    expect(PnlAuthority.permittedUnits(p, const [_ccr, _hki]), isEmpty);
  });

  test('the anonymous principal may read nothing', () {
    expect(PnlAuthority.mayReadUnit(Principal.anonymous, _ccr), isFalse);
    expect(PnlAuthority.mayReadConsolidated(Principal.anonymous), isFalse);
  });

  test('the Manager bundle, scoped, qualifies only where it is scoped', () {
    // A convenient fixture, asserted on capability and scope — never on the role name.
    final p = _p([
      for (final c in RoleTemplates.manager)
        CapabilityGrant(c, businessUnitId: _ccr),
    ]);
    expect(PnlAuthority.permittedUnits(p, const [_ccr, _hki]), [_ccr]);
    expect(PnlAuthority.mayReadConsolidated(p), isFalse);
  });
}
