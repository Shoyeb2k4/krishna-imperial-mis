/// The token lists and source helpers every reporting-surface guard shares
/// (Phase 6, Slices 6–8).
///
/// Written for the dashboard guard in Slice 6 and moved here in Slice 8, so the Analytics
/// workspace guard enforces **the same** rules rather than a copy that could drift from
/// them — the discipline D-232 applies to wording, applied to the guards themselves.
library;

import 'dart:io';

/// Source with comments stripped: prose legitimately names charts, screens, capabilities
/// and the rules these files delegate to.
String surfaceCode(String source) => source
    .split('\n')
    .where(
      (l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'),
    )
    .join('\n');

String surfaceFileCode(String path) =>
    surfaceCode(File(path).readAsStringSync());

/// Runs of whitespace collapsed to one space.
///
/// A phrase assertion must survive the formatter reflowing the line it sits on. That is
/// how D-153's documentation invariant went red for an encoding change, and it is how a
/// guard starts reporting a defect that is only a line break.
String surfacePhrases(String code) => code.replaceAll(RegExp(r'\s+'), ' ');

/// Source with every whitespace character removed.
///
/// Collapsing runs to one space is not enough for a phrase the formatter may wrap
/// *inside* a call: the wrap introduces a space that was never written, so the two
/// forms of one expression stop matching each other.
String surfaceDense(String code) => code.replaceAll(RegExp(r'\s'), '');

/// A figure on a dashboard is never worked out by the thing that draws it.
const surfaceCalculation = [
  '.paise',
  'Money.sum(',
  'Money.fromPaise(',
  'Pnl.compute(',
  'Pnl.consolidate(',
  'PnlComparison.compare(',
  'DashboardTrends.buckets(',
  'DashboardTrends.series(',
  'DashboardTrends.grainsFor(',
  'DailyNetSalesRanking.',
  'TopN.',
  'PropertyComparison.of(',
  'percentageScaled(',
  'pointsScaled(',
  'double ',
  '.sort(',
  'reduce(',
  'fold(',
];

/// Routing a dashboard may not do. The one approved destination is checked separately.
const surfaceNavigation = [
  'context.go(',
  'context.push(',
  'GoRouter',
  'GoRoute(',
  'AppRoutes.',
  'Navigator.push',
  'MaterialPageRoute',
];

/// A report is read-only, and this one is a summary of reports.
const surfaceMutation = [
  'expenseRepositoryProvider',
  'revenueRepositoryProvider',
  'ownerLedgerRepositoryProvider',
  'createLocally(',
  'updateLocally(',
  'voidLocally(',
  'attachLocally(',
  'ExpenseEntryPage',
  'RevenueEntryPage',
];

/// Owner Accounts is its own surface behind its own capability (D-212).
const surfaceOwnerAccounts = [
  'ownerSettlement',
  'OwnerSettlement',
  'ownerLedger',
  'OwnerLedger',
];

/// Phase 7's, and it does not exist.
const surfaceExports = ['Excel', 'pdf', 'Printing', 'printReport', 'exportTo'];

const surfaceStorage = [
  'AppDatabase',
  // Called with their parentheses: `customSelected`, a local on the Overview's period
  // bar, is not a Drift query, and a token that matched it would be the false positive
  // D-069 records.
  'customStatement(',
  'customSelect(',
  'applySnapshot(',
  'applyYear(',
  'ReportingGateway',
  'SupabaseClient',
];

List<String> surfaceViolations(String code, List<String> forbidden) => [
  for (final token in forbidden)
    if (code.contains(token)) token,
];
