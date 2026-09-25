/// Who may export or print a report (Phase 7 Slice 2; D-291, D-292).
///
/// ```
///     export   =  view authority for the exact scope  AND  reports.export for that scope
///     print    =  view authority for the exact scope  AND  reports.print  for that scope
/// ```
///
/// **View authority** is the report's own rule: [PnlAuthority] for one property, or
/// consolidated (all three P&L capabilities unscoped) for more than one. A consolidated
/// scope also needs the **action** capability for every property it includes — either
/// unscoped, or held for each of them.
///
/// An action capability grants **no visibility**: `reports.export` without view authority
/// refuses. **No role name appears here** — a Manager is not offered Export because the
/// seeded Manager bundle does not hold `reports.export`, not because of what it is called
/// (D-292).
///
/// **This is a product-action control, evaluated on the client by design (D-291).** The
/// confidentiality boundary for financial data is the server's reporting authorization
/// (`reporting_primitives`, `reporting_snapshot` and the RLS behind them), which already
/// decides which figures reach the device. Nothing on the server evaluates
/// `reports.export` or `reports.print`, and nothing here claims otherwise.
library;

import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';

/// What the person wants to do with a report.
enum ExportAction {
  /// Save a PDF or Excel file (Windows), or share a PDF (Android).
  export(Capability.reportsExport),

  /// Send the report's PDF to the native print dialog (Windows).
  print(Capability.reportsPrint);

  const ExportAction(this.capability);

  /// The action capability this act requires, beside view authority.
  final Capability capability;
}

/// The four V1 exportable reports (D-290).
enum ExportReport {
  profitAndLoss,
  revenueAnalysis,
  expenseAnalysis,

  /// Only for a consolidated scope (D-278, D-290).
  businessComparison;

  /// Whether this report exists only for a consolidated scope.
  bool get requiresConsolidated => this == ExportReport.businessComparison;
}

/// The properties a report covers.
///
/// One property is a property report; more than one is the consolidated organisation
/// report, whose view authority is the unscoped form (D-164, D-187). Two scoped view
/// grants never add up to consolidated authority.
final class ExportScope {
  ExportScope(Iterable<String> businessUnitIds)
    : businessUnitIds = Set.unmodifiable(businessUnitIds);

  ExportScope.unit(String businessUnitId)
    : businessUnitIds = Set.unmodifiable({businessUnitId});

  final Set<String> businessUnitIds;

  bool get isEmpty => businessUnitIds.isEmpty;
  bool get isConsolidated => businessUnitIds.length > 1;

  @override
  bool operator ==(Object other) =>
      other is ExportScope &&
      other.businessUnitIds.length == businessUnitIds.length &&
      other.businessUnitIds.containsAll(businessUnitIds);

  @override
  int get hashCode => Object.hashAllUnordered(businessUnitIds);
}

/// Why an export or print is not offered.
enum ExportRefusal {
  /// The scope names no property. Nothing is built for nobody.
  noProperties,

  /// Business Comparison was asked for one property.
  requiresConsolidatedScope,

  /// The person may not read this report for this scope. The action capability is not
  /// even consulted: it grants no visibility.
  noViewAuthority,

  /// The person may read the report but does not hold the action capability for every
  /// property in the scope.
  noActionCapability,
}

/// The answer, decided before any document model, file or print job exists.
sealed class ExportDecision {
  const ExportDecision();
}

/// Permission for one action on one report for one scope.
///
/// It can be made only by [ExportAuthority.decide], so a document builder that requires one
/// cannot be reached without the decision having been taken — and the permit names exactly
/// what it permits, so a builder can refuse one issued for a different report or scope.
final class ExportPermitted extends ExportDecision {
  const ExportPermitted._({
    required this.action,
    required this.report,
    required this.scope,
  });

  final ExportAction action;
  final ExportReport report;
  final ExportScope scope;
}

final class ExportRefused extends ExportDecision {
  const ExportRefused(this.reason);
  final ExportRefusal reason;
}

abstract final class ExportAuthority {
  /// Whether [principal] may perform [action] on [report] for [scope].
  ///
  /// The order is deliberate and stable: scope shape, then view authority, then the
  /// action capability — so a person who may not see a report is told that, and never
  /// learns anything from which action capabilities they happen to hold.
  static ExportDecision decide(
    Principal principal, {
    required ExportAction action,
    required ExportReport report,
    required ExportScope scope,
  }) {
    if (scope.isEmpty) return const ExportRefused(ExportRefusal.noProperties);
    if (report.requiresConsolidated && !scope.isConsolidated) {
      return const ExportRefused(ExportRefusal.requiresConsolidatedScope);
    }
    if (!mayView(principal, scope)) {
      return const ExportRefused(ExportRefusal.noViewAuthority);
    }
    if (!holdsAction(principal, action, scope)) {
      return const ExportRefused(ExportRefusal.noActionCapability);
    }
    return ExportPermitted._(action: action, report: report, scope: scope);
  }

  /// Whether the action is offered at all. The same answer as [decide], so a surface
  /// can never offer a button the pipeline would then refuse.
  static bool offers(
    Principal principal, {
    required ExportAction action,
    required ExportReport report,
    required ExportScope scope,
  }) =>
      decide(principal, action: action, report: report, scope: scope)
          is ExportPermitted;

  /// View authority for [scope]: [PnlAuthority] per property, or consolidated.
  static bool mayView(Principal principal, ExportScope scope) {
    if (scope.isEmpty) return false;
    if (scope.isConsolidated) {
      return PnlAuthority.mayReadConsolidated(principal);
    }
    return PnlAuthority.mayReadUnit(principal, scope.businessUnitIds.single);
  }

  /// Whether [action]'s capability covers every property in [scope] — unscoped, or held
  /// for each included property.
  static bool holdsAction(
    Principal principal,
    ExportAction action,
    ExportScope scope,
  ) =>
      scope.businessUnitIds.isNotEmpty &&
      scope.businessUnitIds.every(
        (unit) => principal.can(action.capability, businessUnitId: unit),
      );
}
