/// Who may read a P&L, for the surfaces that offer one (Phase 5 Slice 8).
///
/// The rule is D-164 as corrected by D-187, stated once so a scope selector, a direct
/// provider read and a navigation entry all ask the same question:
///
/// ```
///     one property   reports.view AND revenue.view AND expense.view.all   for that property
///     consolidated   all three, unscoped
/// ```
///
/// Business-unit membership alone never qualifies, `expense.view.own` never substitutes for
/// `expense.view.all`, and two complete scoped grants do not add up to consolidated
/// authority. **No role name appears here**: an Owner, a Manager and an Accountant behave
/// differently only because of the capabilities their bundles hold.
///
/// This is not the security boundary. The server refuses in `reporting_primitives` and
/// `reporting_snapshot`, and the canonical cache adapter refuses at the read (Slice 7). This
/// decides what a surface offers, and lets a direct provider read refuse before it reads.
library;

import 'package:krishna_mis/domain/auth/capability.dart';

abstract final class PnlAuthority {
  /// The capabilities a P&L needs, for one property or unscoped for the organisation.
  static const required = [
    Capability.reportsView,
    Capability.revenueView,
    Capability.expenseViewAll,
  ];

  /// Whether [principal] may read the P&L for [businessUnitId].
  static bool mayReadUnit(Principal principal, String businessUnitId) =>
      required.every((c) => principal.can(c, businessUnitId: businessUnitId));

  /// Whether [principal] may read the consolidated organisation P&L.
  static bool mayReadConsolidated(Principal principal) => required.every(
    (c) => principal.canAnywhere(c) && principal.scopedUnitsFor(c) == null,
  );

  /// Who is reading, and exactly which P&L read grants they hold, for every scope.
  ///
  /// It changes when the person changes, and when any of the three capabilities is gained or
  /// lost for any property or unscoped — and **only** then. A session state change for the
  /// same person with the same authority (a stale refresh, a confirmed refresh that changed
  /// nothing) leaves it identical, so a surface keyed on it keeps the person's chosen
  /// property, period and open drill-down (Slice 11).
  static String readKey(Principal principal) {
    final grants = <String>{
      for (final grant in principal.grants)
        if (required.contains(grant.capability))
          '${grant.capability.code}@${grant.businessUnitId ?? '*'}',
    }.toList()..sort();
    return '${principal.userId}|${grants.join(',')}';
  }

  /// The properties among [candidateUnitIds] this principal may report on, in id order.
  static List<String> permittedUnits(
    Principal principal,
    Iterable<String> candidateUnitIds,
  ) => [
    for (final unit in {...candidateUnitIds}.toList()..sort())
      if (mayReadUnit(principal, unit)) unit,
  ];
}
