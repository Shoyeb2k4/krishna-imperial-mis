/// The D-020 parity comparison, written once and used by every suite that needs it.
///
/// Spec §21.3: *"identical report requests are executed against each engine and the suite
/// asserts **exact equality in integer paise**"*. Exact means exact — every comparison here
/// is between integers and identifiers, there is no tolerance anywhere, and nothing is
/// rounded on the way in.
///
/// ## What parity does and does not claim
///
/// Both engines are the same orchestration over two sources (D-185), so what this compares
/// is the thing that can actually differ: **did the synchronised offline cache sum the same
/// rows the authoritative server did?** That is the question Slice 5 exists to answer, and
/// a comparison of two copies of the arithmetic would not have answered it.
///
/// ## The one asymmetry that is not a failure (§27)
///
/// The remote engine can answer a range the device has never downloaded; the local engine
/// says `notDownloaded` for it, correctly (D-170). That is two engines disagreeing about
/// *coverage*, not about money, and it is the designed behaviour rather than a defect. So
/// parity is asserted **only where local coverage is complete**, and
/// [expectLocalUncoveredWhileRemoteAnswers] states the other case explicitly rather than
/// leaving it as an untested gap — because a harness that silently skipped disagreements
/// would skip real ones too.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/reporting/reporting_engine.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';

/// Asserts that two envelopes are the same report, to the paisa.
void expectParity(
  ReportEnvelope local,
  ReportEnvelope remote, {
  required String context,
}) {
  String why(String what) => '$context: $what';

  expect(local.range, remote.range, reason: why('the range differs'));
  expect(
    local.scope.ordered,
    remote.scope.ordered,
    reason: why('the business-unit scope differs'),
  );

  // Coverage is deliberately *not* compared: it is a statement about how each engine came
  // by its figures, and the whole point of the remote engine is that it comes by them
  // differently. What must match is the money.
  expect(
    local.isComputed,
    remote.isComputed,
    reason: why(
      'one engine produced a report and the other refused — '
      'local ${local.refusalOrNull ?? 'computed'}, '
      'remote ${remote.refusalOrNull ?? 'computed'}',
    ),
  );

  if (!local.isComputed) {
    expect(
      local.refusalOrNull,
      remote.refusalOrNull,
      reason: why('the two engines refused for different reasons'),
    );
    return;
  }

  expectResultParity(
    local.resultOrNull!,
    remote.resultOrNull!,
    context: context,
  );
}

/// The figures themselves.
void expectResultParity(
  PnlResult local,
  PnlResult remote, {
  required String context,
}) {
  String why(String what) => '$context: $what';

  expect(local.range, remote.range, reason: why('the range differs'));
  expect(
    local.businessUnitId,
    remote.businessUnitId,
    reason: why('one result is consolidated and the other is not'),
  );

  // Integer paise, no tolerance, and each figure named so a failure says which one moved.
  expect(
    local.grossSales.paise,
    remote.grossSales.paise,
    reason: why('Gross Sales'),
  );
  expect(local.gst.paise, remote.gst.paise, reason: why('GST'));
  expect(local.netSales.paise, remote.netSales.paise, reason: why('Net Sales'));
  expect(local.expenses.paise, remote.expenses.paise, reason: why('Expenses'));
  expect(
    local.operatingProfit.paise,
    remote.operatingProfit.paise,
    reason: why('Operating Profit'),
  );

  // A right sum over the wrong set of rows is the failure the counts exist to catch.
  expect(
    local.revenueContributions,
    remote.revenueContributions,
    reason: why('the number of revenue contributions summed'),
  );
  expect(
    local.expenseContributions,
    remote.expenseContributions,
    reason: why('the number of expense contributions summed'),
  );

  // Both sides must reconcile independently. Two engines that agreed on three wrong
  // figures would still fail this.
  expect(local.reconciles, isTrue, reason: why('local gross != GST + net'));
  expect(remote.reconciles, isTrue, reason: why('remote gross != GST + net'));

  expect(
    _revenueLines(local),
    _revenueLines(remote),
    reason: why(
      'the revenue category breakdown differs. Restaurant and Nandbhog, and Room and '
      'Banquet, are independent categories and no query may flatten them before the '
      'comparison (D-089)',
    ),
  );
  expect(
    _expenseLines(local),
    _expenseLines(remote),
    reason: why('the expense hierarchy breakdown differs'),
  );
}

/// The permitted asymmetry, stated rather than skipped (§27).
void expectLocalUncoveredWhileRemoteAnswers(
  ReportEnvelope local,
  ReportEnvelope remote, {
  required String context,
}) {
  expect(
    local.isComputed,
    isFalse,
    reason:
        '$context: the device was expected not to hold this range, and reported a figure '
        'for it anyway',
  );
  expect(
    local.refusalOrNull,
    anyOf(
      PnlRefusal.revenueUnavailable,
      PnlRefusal.expensesUnavailable,
      PnlRefusal.bothSidesUnavailable,
    ),
    reason:
        '$context: an undownloaded range must refuse, never report zero (D-170)',
  );
  expect(
    local.coverage,
    ReportingCoverage.notDownloaded,
    reason: '$context: the refusal must say the range is not here',
  );
  expect(
    remote.isComputed,
    isTrue,
    reason: '$context: the server holds every range and was expected to answer',
  );
}

/// Comparable, ordered, and integer-only.
List<String> _revenueLines(PnlResult r) => [
  for (final line in r.revenueByCategory)
    '${line.businessUnitId}/${line.revenueCategoryId}'
        '/${line.treatment?.name ?? 'mixed'}'
        ' g=${line.totals.gross.paise}'
        ' t=${line.totals.tax.paise}'
        ' n=${line.totals.net.paise}'
        ' c=${line.totals.contributions}',
]..sort();

List<String> _expenseLines(PnlResult r) => [
  for (final line in r.expenseByHierarchy)
    '${line.businessUnitId}/${line.departmentId}/${line.sectionId}'
        '/${line.categoryId}'
        ' a=${line.totals.amount.paise}'
        ' c=${line.totals.contributions}',
]..sort();
