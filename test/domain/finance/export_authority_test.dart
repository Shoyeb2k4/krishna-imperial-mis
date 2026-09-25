/// Who may export or print (Phase 7 Slice 2; D-291, D-292).
///
///     export = view authority for the exact scope AND reports.export for that scope
///     print  = view authority for the exact scope AND reports.print  for that scope
///
/// A consolidated scope needs the action capability for every included property. An action
/// capability never grants visibility. No role name is read — the seeded bundles are used
/// only as data, to show what the shipped roles are offered.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/export_authority.dart';

const _ccr = 'ccr';
const _hki = 'hki';

Principal _p(Iterable<CapabilityGrant> grants) =>
    Principal(userId: 'u', grants: grants);

List<CapabilityGrant> _view(String? unit) => [
  CapabilityGrant(Capability.reportsView, businessUnitId: unit),
  CapabilityGrant(Capability.revenueView, businessUnitId: unit),
  CapabilityGrant(Capability.expenseViewAll, businessUnitId: unit),
];

List<CapabilityGrant> _bundle(Set<Capability> bundle, String? unit) => [
  for (final c in bundle) CapabilityGrant(c, businessUnitId: unit),
];

final _unitCcr = ExportScope.unit(_ccr);
final _unitHki = ExportScope.unit(_hki);
final _both = ExportScope({_ccr, _hki});

ExportDecision _decide(
  Principal p,
  ExportScope scope, {
  ExportAction action = ExportAction.export,
  ExportReport report = ExportReport.profitAndLoss,
}) => ExportAuthority.decide(p, action: action, report: report, scope: scope);

ExportRefusal? _refusal(ExportDecision d) => switch (d) {
  ExportPermitted() => null,
  ExportRefused(:final reason) => reason,
};

void main() {
  group('view authority AND the action capability, for the exact scope', () {
    for (final action in ExportAction.values) {
      test('${action.name}: both held for the property → permitted', () {
        final p = _p([
          ..._view(_ccr),
          CapabilityGrant(action.capability, businessUnitId: _ccr),
        ]);
        expect(_decide(p, _unitCcr, action: action), isA<ExportPermitted>());
      });

      test('${action.name}: view without the action capability → refused', () {
        final p = _p(_view(_ccr));
        expect(
          _refusal(_decide(p, _unitCcr, action: action)),
          ExportRefusal.noActionCapability,
        );
      });

      test(
        '${action.name}: the action capability alone grants no visibility',
        () {
          // Held unscoped, and still nothing: reports.export is not a way to see figures.
          final p = _p([CapabilityGrant(action.capability)]);
          expect(
            _refusal(_decide(p, _unitCcr, action: action)),
            ExportRefusal.noViewAuthority,
          );
          expect(
            _refusal(_decide(p, _both, action: action)),
            ExportRefusal.noViewAuthority,
          );
        },
      );

      test(
        '${action.name}: the action capability for another property does not '
        'count',
        () {
          final p = _p([
            ..._view(_ccr),
            CapabilityGrant(action.capability, businessUnitId: _hki),
          ]);
          expect(
            _refusal(_decide(p, _unitCcr, action: action)),
            ExportRefusal.noActionCapability,
          );
        },
      );
    }

    test('export and print are independent capabilities', () {
      final p = _p([
        ..._view(_ccr),
        const CapabilityGrant(Capability.reportsExport, businessUnitId: _ccr),
      ]);
      expect(
        _decide(p, _unitCcr, action: ExportAction.export),
        isA<ExportPermitted>(),
      );
      expect(
        _refusal(_decide(p, _unitCcr, action: ExportAction.print)),
        ExportRefusal.noActionCapability,
      );
    });

    test('view authority for one property does not reach the other', () {
      final p = _p([
        ..._view(_ccr),
        const CapabilityGrant(Capability.reportsExport),
      ]);
      expect(_refusal(_decide(p, _unitHki)), ExportRefusal.noViewAuthority);
    });

    for (final missing in [
      Capability.reportsView,
      Capability.revenueView,
      Capability.expenseViewAll,
    ]) {
      test('missing ${missing.code} is missing view authority', () {
        final p = _p([
          ..._view(_ccr).where((g) => g.capability != missing),
          const CapabilityGrant(Capability.reportsExport, businessUnitId: _ccr),
        ]);
        expect(_refusal(_decide(p, _unitCcr)), ExportRefusal.noViewAuthority);
      });
    }

    test('expense.view.own never substitutes for expense.view.all', () {
      final p = _p([
        const CapabilityGrant(Capability.reportsView, businessUnitId: _ccr),
        const CapabilityGrant(Capability.revenueView, businessUnitId: _ccr),
        const CapabilityGrant(Capability.expenseViewOwn, businessUnitId: _ccr),
        const CapabilityGrant(Capability.reportsExport, businessUnitId: _ccr),
      ]);
      expect(_refusal(_decide(p, _unitCcr)), ExportRefusal.noViewAuthority);
    });
  });

  group('a consolidated scope', () {
    test('unscoped view and unscoped action → permitted', () {
      final p = _p([
        ..._view(null),
        const CapabilityGrant(Capability.reportsExport),
      ]);
      expect(_decide(p, _both), isA<ExportPermitted>());
    });

    test(
      'scoped action grants covering every included property → permitted',
      () {
        final p = _p([
          ..._view(null),
          const CapabilityGrant(Capability.reportsExport, businessUnitId: _ccr),
          const CapabilityGrant(Capability.reportsExport, businessUnitId: _hki),
        ]);
        expect(_decide(p, _both), isA<ExportPermitted>());
      },
    );

    test(
      'the action capability missing for one included property → refused',
      () {
        final p = _p([
          ..._view(null),
          const CapabilityGrant(Capability.reportsExport, businessUnitId: _ccr),
        ]);
        expect(_refusal(_decide(p, _both)), ExportRefusal.noActionCapability);
        // …while that same person may still export the property they do cover.
        expect(_decide(p, _unitCcr), isA<ExportPermitted>());
        expect(
          _refusal(_decide(p, _unitHki)),
          ExportRefusal.noActionCapability,
        );
      },
    );

    test(
      'two scoped view grants do not add up to consolidated view authority',
      () {
        final p = _p([
          ..._view(_ccr),
          ..._view(_hki),
          const CapabilityGrant(Capability.reportsExport),
        ]);
        expect(_refusal(_decide(p, _both)), ExportRefusal.noViewAuthority);
        expect(_decide(p, _unitCcr), isA<ExportPermitted>());
        expect(_decide(p, _unitHki), isA<ExportPermitted>());
      },
    );
  });

  group('the report and the scope shape', () {
    final owner = _p([
      ..._view(null),
      const CapabilityGrant(Capability.reportsExport),
      const CapabilityGrant(Capability.reportsPrint),
    ]);

    test('Business Comparison is offered only for a consolidated scope', () {
      expect(
        _refusal(
          _decide(owner, _unitCcr, report: ExportReport.businessComparison),
        ),
        ExportRefusal.requiresConsolidatedScope,
      );
      expect(
        _decide(owner, _both, report: ExportReport.businessComparison),
        isA<ExportPermitted>(),
      );
    });

    test(
      'the other three reports work for one property and for consolidated',
      () {
        for (final report in ExportReport.values) {
          if (report.requiresConsolidated) continue;
          expect(
            _decide(owner, _unitCcr, report: report),
            isA<ExportPermitted>(),
          );
          expect(_decide(owner, _both, report: report), isA<ExportPermitted>());
        }
      },
    );

    test('an empty scope builds nothing', () {
      expect(
        _refusal(_decide(owner, ExportScope(const []))),
        ExportRefusal.noProperties,
      );
    });

    test('a person without view authority is told that, whatever the scope '
        'shape', () {
      // The shape check for Business Comparison comes before view authority, but it
      // reveals nothing: it is a property of the report, not of any figure.
      final nobody = _p(const []);
      expect(_refusal(_decide(nobody, _both)), ExportRefusal.noViewAuthority);
    });

    test('offers() gives exactly the decide() answer', () {
      final manager = _p(_view(_ccr));
      for (final action in ExportAction.values) {
        for (final report in ExportReport.values) {
          for (final scope in [_unitCcr, _unitHki, _both]) {
            expect(
              ExportAuthority.offers(
                manager,
                action: action,
                report: report,
                scope: scope,
              ),
              _decide(manager, scope, action: action, report: report)
                  is ExportPermitted,
            );
          }
        }
      }
    });
  });

  group('the seeded bundles, used only as data (D-292)', () {
    test('Owner (unscoped, everything): export and print every report', () {
      final p = _p(_bundle(RoleTemplates.owner, null));
      for (final action in ExportAction.values) {
        expect(_decide(p, _both, action: action), isA<ExportPermitted>());
        expect(
          _decide(
            p,
            _both,
            action: action,
            report: ExportReport.businessComparison,
          ),
          isA<ExportPermitted>(),
        );
      }
    });

    test('Accountant scoped to one property: its own property only', () {
      final p = _p(_bundle(RoleTemplates.accountant, _ccr));
      for (final action in ExportAction.values) {
        expect(_decide(p, _unitCcr, action: action), isA<ExportPermitted>());
        expect(
          _refusal(_decide(p, _unitHki, action: action)),
          ExportRefusal.noViewAuthority,
        );
        expect(
          _refusal(_decide(p, _both, action: action)),
          ExportRefusal.noViewAuthority,
        );
      }
    });

    test('Manager: reads the P&L, is offered neither export nor print', () {
      final p = _p(_bundle(RoleTemplates.manager, _ccr));
      for (final action in ExportAction.values) {
        expect(
          _refusal(_decide(p, _unitCcr, action: action)),
          ExportRefusal.noActionCapability,
          reason:
              'D-292: the Manager bundle holds reports.view without the action '
              'capabilities; granting one is ordinary capability administration',
        );
      }
    });

    test('Data Entry: nothing', () {
      final p = _p(_bundle(RoleTemplates.dataEntry, _ccr));
      for (final action in ExportAction.values) {
        expect(
          _refusal(_decide(p, _unitCcr, action: action)),
          ExportRefusal.noViewAuthority,
        );
      }
    });

    test('a Manager explicitly granted reports.export exports, with no role '
        'exception', () {
      final p = _p([
        ..._bundle(RoleTemplates.manager, _ccr),
        const CapabilityGrant(Capability.reportsExport, businessUnitId: _ccr),
      ]);
      expect(_decide(p, _unitCcr), isA<ExportPermitted>());
      expect(
        _refusal(_decide(p, _unitCcr, action: ExportAction.print)),
        ExportRefusal.noActionCapability,
      );
    });
  });

  group('structure', () {
    final source = File(
      'lib/domain/finance/export_authority.dart',
    ).readAsStringSync();
    final code = source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('///'))
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('names no role and reads no role bundle', () {
      for (final token in const [
        'RoleTemplates',
        "'owner'",
        "'manager'",
        "'accountant'",
        "'data_entry'",
        'roleCode',
        '.role',
      ]) {
        expect(
          code,
          isNot(contains(token)),
          reason: 'role-name branch: $token',
        );
      }
    });

    test('decides view authority through PnlAuthority, not a copy of it', () {
      expect(code, contains('PnlAuthority.mayReadConsolidated('));
      expect(code, contains('PnlAuthority.mayReadUnit('));
      // A second statement of the D2 intersection here would drift from the first.
      expect(code, isNot(contains('Capability.revenueView')));
      expect(code, isNot(contains('Capability.expenseViewAll')));
    });

    test('checks the action capability per included property', () {
      expect(code, contains('scope.businessUnitIds.every('));
      expect(code, isNot(contains('canAnywhere')));
    });

    test('makes no claim of server enforcement', () {
      expect(source, contains('evaluated on the client by design (D-291)'));
      expect(source, contains('Nothing on the server evaluates'));
    });
  });
}
