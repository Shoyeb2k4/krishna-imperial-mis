/// The capability catalogue and the grants that carry it.
///
/// Authorisation is expressed as capabilities, never as role names (master spec §13.1).
/// `Manager` on its own never means "can access everything": a capability is only ever
/// meaningful together with a **business-unit scope**.
///
/// Role names must not appear in any conditional in the application. Roles exist only as
/// bundles that hand out the capabilities below.
library;

import 'package:meta/meta.dart';

enum Capability {
  // ── Expenses ──────────────────────────────────────────────────────────────
  expenseViewOwn('expense.view.own'),
  expenseViewAll('expense.view.all'),
  expenseCreate('expense.create'),
  expenseEditOwn('expense.edit.own'),
  expenseEditAll('expense.edit.all'),
  expenseVoid('expense.void'),

  /// Split one expense across accounting periods (D-034). Finance and owner only.
  expenseAllocatePeriods('expense.allocate_periods'),

  /// Charge one expense to more than one business unit (D-061).
  ///
  /// Scope over every unit named is necessary and deliberately not sufficient. A
  /// cross-unit split decides how a shared cost is apportioned between two businesses,
  /// which moves both properties' profitability — it is an act of finance, not of data
  /// entry, and somebody who happens to hold both properties operationally should not
  /// acquire it as a side effect.
  expenseAllocateCrossUnit('expense.allocate_cross_unit'),

  // ── Revenue ───────────────────────────────────────────────────────────────
  revenueView('revenue.view'),
  revenueCreate('revenue.create'),

  /// Correct revenue you recorded yourself, within the window and while the period is
  /// open.
  revenueEdit('revenue.edit'),

  /// Correct revenue recorded by anybody, under the same window and period rules.
  ///
  /// The split expenses have had since D-072a, mirrored for revenue in Slice 10: without
  /// it there is no configured basis for the distinction spec §13.2 draws between a
  /// Manager, who records their property's takings, and an Accountant, who exists to
  /// correct them.
  revenueEditAll('revenue.edit.all'),

  revenueVoid('revenue.void'),

  // ── Corrections ───────────────────────────────────────────────────────────
  /// Edit a transaction after the edit window has closed (spec §13.3).
  correctBeyondWindow('transaction.correct.beyond_window'),

  /// Change a derived business date. Always audited (spec §9).
  correctBusinessDate('transaction.correct.business_date'),

  // ── Attachments ───────────────────────────────────────────────────────────
  attachmentView('attachment.view'),
  attachmentUpload('attachment.upload'),

  // ── Reporting ─────────────────────────────────────────────────────────────
  reportsView('reports.view'),
  reportsExport('reports.export'),
  reportsPrint('reports.print'),

  // ── Master data ───────────────────────────────────────────────────────────
  mastersView('masters.view'),
  mastersManage('masters.manage'),
  taxManage('tax.manage'),

  // ── Administration ────────────────────────────────────────────────────────
  usersManage('users.manage'),
  rolesManage('roles.manage'),
  auditView('audit.view'),
  settingsManage('settings.manage'),
  periodClose('period.close'),
  periodReopen('period.reopen');

  const Capability(this.code);

  /// The stable string stored in `role_permissions`. Renaming an enum constant must
  /// never change this — history and grants key on it.
  final String code;

  static Capability fromCode(String code) => Capability.values.firstWhere(
    (c) => c.code == code,
    orElse: () => throw ArgumentError.value(code, 'code', 'unknown capability'),
  );
}

/// One capability held over one scope.
///
/// A null [businessUnitId] means "every unit" and is reserved for the Owner role. Every
/// other role must name its unit explicitly, so a Manager can never quietly acquire the
/// second property (D-025).
@immutable
final class CapabilityGrant {
  const CapabilityGrant(this.capability, {this.businessUnitId});

  final Capability capability;
  final String? businessUnitId;

  bool get isOrgWide => businessUnitId == null;

  bool covers(Capability wanted, String unitId) =>
      capability == wanted && (isOrgWide || businessUnitId == unitId);

  @override
  bool operator ==(Object other) =>
      other is CapabilityGrant &&
      other.capability == capability &&
      other.businessUnitId == businessUnitId;

  @override
  int get hashCode => Object.hash(capability, businessUnitId);

  @override
  String toString() =>
      'CapabilityGrant(${capability.code}@${businessUnitId ?? 'all-units'})';
}

/// The authenticated user as the authorisation layer sees them.
///
/// Deliberately holds no role name. Everything downstream reasons about capabilities
/// and scope, which is what makes "Manager" impossible to misread as "can do anything".
@immutable
final class Principal {
  Principal({required this.userId, required Iterable<CapabilityGrant> grants})
    : grants = Set.unmodifiable(grants);

  /// A principal with nothing granted. The safe default — used before sign-in and in
  /// tests, so an un-populated principal fails closed rather than open.
  static final Principal anonymous = Principal(userId: '', grants: const []);

  final String userId;
  final Set<CapabilityGrant> grants;

  /// Whether this user holds [capability] for [businessUnitId].
  bool can(Capability capability, {required String businessUnitId}) =>
      grants.any((g) => g.covers(capability, businessUnitId));

  /// Whether this user holds [capability] for *any* unit. Use only to decide whether a
  /// menu entry is worth showing — never to authorise a write, which always names a unit.
  bool canAnywhere(Capability capability) =>
      grants.any((g) => g.capability == capability);

  /// The units this capability covers, or null when it is held org-wide.
  ///
  /// Returning null rather than "all known units" keeps the caller honest: an org-wide
  /// grant is not a list to be enumerated, it is an absence of restriction.
  Set<String>? scopedUnitsFor(Capability capability) {
    final matching = grants.where((g) => g.capability == capability);
    if (matching.any((g) => g.isOrgWide)) return null;
    return {for (final g in matching) g.businessUnitId!};
  }

  @override
  String toString() => 'Principal($userId, ${grants.length} grants)';
}

/// The four seeded roles, expressed as capability bundles (spec §13.2).
///
/// These are seed data, not code that authorises anything. A deployment may add roles or
/// adjust bundles; nothing in the application branches on these names.
abstract final class RoleTemplates {
  static const String ownerCode = 'owner';
  static const String managerCode = 'manager';
  static const String accountantCode = 'accountant';
  static const String dataEntryCode = 'data_entry';

  /// Full control, and the only role permitted to hold an unscoped, all-units grant.
  static const Set<Capability> owner = {...Capability.values};

  /// Operational entry and permitted operational reporting, for assigned units only.
  static const Set<Capability> manager = {
    Capability.expenseViewAll,
    Capability.expenseCreate,
    Capability.expenseEditOwn,
    Capability.revenueView,
    Capability.revenueCreate,
    Capability.revenueEdit,
    Capability.attachmentView,
    Capability.attachmentUpload,
    Capability.reportsView,
    Capability.mastersView,
  };

  /// Finance operations and corrections, for assigned financial units.
  static const Set<Capability> accountant = {
    Capability.expenseViewAll,
    Capability.expenseCreate,
    Capability.expenseEditAll,
    Capability.expenseVoid,
    Capability.expenseAllocatePeriods,
    Capability.expenseAllocateCrossUnit,
    Capability.revenueView,
    Capability.revenueCreate,
    Capability.revenueEdit,
    Capability.revenueEditAll,
    Capability.revenueVoid,
    Capability.correctBeyondWindow,
    Capability.correctBusinessDate,
    Capability.attachmentView,
    Capability.attachmentUpload,
    Capability.reportsView,
    Capability.reportsExport,
    Capability.reportsPrint,
    Capability.mastersView,
    Capability.auditView,
  };

  /// Restricted entry only.
  static const Set<Capability> dataEntry = {
    Capability.expenseViewOwn,
    Capability.expenseCreate,
    Capability.expenseEditOwn,
    Capability.revenueCreate,
    Capability.attachmentUpload,
    Capability.mastersView,
  };

  static Set<Capability> forRole(String roleCode) => switch (roleCode) {
    ownerCode => owner,
    managerCode => manager,
    accountantCode => accountant,
    dataEntryCode => dataEntry,
    _ => throw ArgumentError.value(roleCode, 'roleCode', 'unknown role'),
  };

  /// Whether a grant of this role must name a business unit.
  ///
  /// True for everything except Owner. Enforced by a database trigger as well, so the
  /// safe default is structural rather than remembered (D-025).
  static bool requiresUnitScope(String roleCode) => roleCode != ownerCode;
}
