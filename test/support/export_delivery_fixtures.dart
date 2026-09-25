/// Fixtures for the Phase 7 delivery tests (Slices 6–9): the reports a screen holds, the
/// principals who hold them, and the bundled fonts read from the repository.
///
/// Every figure is still the canonical calculator's ([fxResult], [Pnl.compute]); these
/// only wrap them the way `pnlViewProvider` and `dashboardViewProvider` do.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:krishna_mis/core/export/pdf/pdf_fonts.dart';
import 'package:krishna_mis/data/reporting/dashboard_engine.dart';
import 'package:krishna_mis/data/reporting/reporting_engine.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/finance/dashboard_analytics.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/pnl_authority.dart';
import 'package:krishna_mis/domain/finance/property_comparison.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/features/dashboard/presentation/dashboard_providers.dart';
import 'package:krishna_mis/features/profit_and_loss/presentation/pnl_providers.dart';

import 'export_fixtures.dart';

ByteData _asset(String path) =>
    ByteData.sublistView(File(path).readAsBytesSync());

/// The bundled Noto Sans, read from the repository the way the app reads the bundle.
final fxFonts = ExportPdfFonts.fromBytes(
  regular: _asset(exportPdfRegularFontAsset),
  bold: _asset(exportPdfBoldFontAsset),
);

// ── Principals, by capability — never by role name in the rule under test ──

Principal fxPrincipal(String userId, List<CapabilityGrant> grants) =>
    Principal(userId: userId, grants: grants);

/// The seeded Manager bundle, scoped to Crystal Canopy: reads, does not export (D-292).
final fxManager = fxPrincipal('user-manager', [
  for (final c in RoleTemplates.manager)
    CapabilityGrant(c, businessUnitId: fxCcr),
]);

/// P&L view authority for Crystal Canopy, and the action capabilities too.
final fxCcrExporter = fxPrincipal('user-ccr-exporter', [
  for (final c in PnlAuthority.required)
    CapabilityGrant(c, businessUnitId: fxCcr),
  const CapabilityGrant(Capability.reportsExport, businessUnitId: fxCcr),
  const CapabilityGrant(Capability.reportsPrint, businessUnitId: fxCcr),
]);

/// Holds the action capabilities and no view authority at all.
final fxActionOnly = fxPrincipal('user-action-only', const [
  CapabilityGrant(Capability.reportsExport),
  CapabilityGrant(Capability.reportsPrint),
]);

/// Unscoped view authority, but export and print for Crystal Canopy only — so a
/// consolidated action is not covered for Hotel Krishna.
final fxConsolidatedViewerExportsOneProperty = fxPrincipal('user-partial', [
  for (final c in PnlAuthority.required) CapabilityGrant(c),
  const CapabilityGrant(Capability.reportsExport, businessUnitId: fxCcr),
  const CapabilityGrant(Capability.reportsPrint, businessUnitId: fxCcr),
]);

// ── Reports as the screens hold them ────────────────────────────────────────

ReportEnvelope fxEnvelope(
  PnlResult result, {
  ReportingFreshness? freshness,
  bool computed = true,
}) => ReportEnvelope(
  outcome: computed
      ? PnlComputed(result)
      : const PnlRefused(PnlRefusal.bothSidesUnavailable),
  range: result.range,
  scope: result.isConsolidated
      ? ReportingScope({fxCcr, fxHki})
      : ReportingScope.unit(result.businessUnitId!),
  revenueCoverage: computed
      ? ReportingCoverage.complete
      : ReportingCoverage.notDownloaded,
  expenseCoverage: computed
      ? ReportingCoverage.complete
      : ReportingCoverage.notDownloaded,
  freshness: freshness,
);

/// The P&L view `pnlViewProvider` would hold for [viewer].
PnlReportView fxPnlView(
  PnlResult result, {
  required Principal viewer,
  ReportingFreshness? freshness,
  bool computed = true,
}) => PnlReportView(
  envelope: fxEnvelope(result, freshness: freshness, computed: computed),
  scope: result.isConsolidated
      ? const PnlConsolidatedScope()
      : PnlUnitScope(result.businessUnitId!),
  range: result.range,
  neededYears: const [],
  retainedYears: const [],
  viewerUserId: viewer.userId,
);

/// The consolidated dashboard `dashboardViewProvider` would hold for [viewer].
DashboardReady fxDashboard({
  required Principal viewer,
  PnlResult? current,
  ReportingFreshness? freshness,
  bool computed = true,
}) {
  final result = current ?? fxConsolidated();
  final previous = fxConsolidatedAugust();
  return DashboardReady(
    PnlAuthority.readKey(viewer),
    view: DashboardView(
      pair: fxPair,
      scope: ReportingScope({fxCcr, fxHki}),
      current: fxEnvelope(result, freshness: freshness, computed: computed),
      previous: fxEnvelope(previous),
      comparison: fxComparison(
        current: computed
            ? PnlComputed(result)
            : const PnlRefused(PnlRefusal.bothSidesUnavailable),
      ),
      trends: [fxNetSalesTrendWithGap(), fxMonthlyExpenseTrend()],
      revenueCoverage: ReportingCoverage.complete,
      expenseCoverage: ReportingCoverage.complete,
      stats: const DashboardReadStats(rangesRead: 2, trendPoints: 5),
      topExpenseCategories: TopN.expenseCategories(result, n: 3),
      topRevenueCategories: TopN.revenueCategories(result, n: 3),
      departmentSpending: TopN.departments(result, n: 3),
      propertyComparison: PropertyComparison.of(result),
      freshness: freshness,
    ),
    scope: const PnlConsolidatedScope(),
    neededYears: const [],
    retainedYears: const [],
  );
}
