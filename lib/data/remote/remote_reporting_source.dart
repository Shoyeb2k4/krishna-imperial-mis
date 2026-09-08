/// The authoritative reporting facts, read from the server.
///
/// Phase 5 Slice 5. The second adapter behind [ReportingFactsSource], and the one the
/// D-020 parity suite measures the offline cache against.
///
/// ## What it is for, and what it is not for
///
/// It answers *"what does the server say this property earned and spent over this range?"*
/// and nothing else. It **does not fill the cache, and must not** — filling it is
/// `ReportingSync`'s, and a remote read that quietly synchronised on the way past would
/// make the two sources agree because one had just overwritten the other, which is the
/// opposite of a parity proof (§30). This class writes no local row of any kind and holds
/// no database.
///
/// It is also **not** what an offline screen falls back from. [LocalReportingEngine] reads
/// the synchronised cache and is never gated on the network; nothing here is consulted to
/// produce a local report.
///
/// ## Why the mapping lives here rather than beside the engine
///
/// Turning wire integers into `Money` is exactly the arithmetic the Slice 3 structural
/// guard keeps out of `lib/data/reporting/` — D-182 moved three files for the same reason.
/// This is transport mapping, so it sits with the gateway, and the reporting layer stays
/// free of paise.
///
/// ## An unreachable server is not a figure
///
/// A refusal or a transport failure produces [ReportingCoverage.notDownloaded] on both
/// sides, which the engine turns into a refusal. Nothing here converts "I could not ask"
/// into a zero (D-048 §1, applied to reads).
library;

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart' show TaxTreatment;
import 'package:krishna_mis/domain/value_objects/money.dart';

/// Reads `public.reporting_primitives`.
final class RemoteReportingSource implements ReportingFactsSource {
  const RemoteReportingSource(this.gateway, {this.breakdown = true});

  final ReportingGateway gateway;

  /// Whether to ask for the category and hierarchy lines. On by default because the parity
  /// suite compares them; a caller that only needs headline figures can turn them off and
  /// the headline sums are identical either way.
  final bool breakdown;

  @override
  Future<UnitReportingFacts> factsFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingScope scope,
  }) async {
    // A property outside the requested scope is not asked for, exactly as the cached source
    // refuses to read one: the scope is authority, not a filter (D-121).
    if (!scope.businessUnitIds.contains(businessUnitId)) {
      return UnitReportingFacts.uncovered(
        businessUnitId: businessUnitId,
        coverage: ReportingCoverage.notDownloaded,
      );
    }
    final all = await factsForScope(
      range: range,
      scope: ReportingScope.unit(businessUnitId),
    );
    return all.single;
  }

  @override
  Future<List<UnitReportingFacts>> factsForScope({
    required ReportRange range,
    required ReportingScope scope,
  }) async {
    final units = scope.ordered;
    if (units.isEmpty) return const [];

    final outcome = await gateway.primitives(
      businessUnitIds: units,
      fromIsoDate: range.from.iso,
      toIsoDate: range.to.iso,
      breakdown: breakdown,
    );

    if (outcome is! RemoteOk<Map<String, dynamic>>) {
      // Refused or unreachable. Either way nothing is established, and an unestablished
      // side is never a zero.
      return [
        for (final unit in units)
          UnitReportingFacts.uncovered(
            businessUnitId: unit,
            coverage: ReportingCoverage.notDownloaded,
          ),
      ];
    }

    final answered = <String, Map<String, dynamic>>{
      for (final row in (outcome.value['units'] as List? ?? const []))
        (row as Map)['business_unit_id'] as String: Map<String, dynamic>.from(
          row,
        ),
    };

    return [for (final unit in units) _factsFrom(unit, answered[unit])];
  }

  UnitReportingFacts _factsFrom(String unit, Map<String, dynamic>? row) {
    if (row == null) {
      // The server did not answer for a property that was asked about. Not a figure, and
      // not silently a zero.
      return UnitReportingFacts.uncovered(
        businessUnitId: unit,
        coverage: ReportingCoverage.notDownloaded,
      );
    }

    // `null`, never zero, is what an unauthorised side comes back as, and the two are read
    // as different facts here as well as sent as different facts there (D-163).
    final revenue = row['revenue'] as Map?;
    final expense = row['expense'] as Map?;

    return UnitReportingFacts(
      businessUnitId: unit,
      revenueCoverage: revenue == null
          ? ReportingCoverage.notAuthorised
          : ReportingCoverage.complete,
      expenseCoverage: expense == null
          ? ReportingCoverage.notAuthorised
          : ReportingCoverage.complete,
      revenue: revenue == null
          ? RevenueTotals.zero
          : RevenueTotals(
              gross: Money.fromPaise(_int(revenue['gross_minor'])),
              tax: Money.fromPaise(_int(revenue['tax_minor'])),
              net: Money.fromPaise(_int(revenue['net_minor'])),
              contributions: _int(revenue['contributions']),
            ),
      expenses: expense == null
          ? ExpenseTotals.zero
          : ExpenseTotals(
              amount: Money.fromPaise(_int(expense['amount_minor'])),
              contributions: _int(expense['contributions']),
            ),
      revenueByCategory: [
        for (final line in (row['revenue_by_category'] as List? ?? const []))
          RevenueCategoryTotals(
            businessUnitId: unit,
            revenueCategoryId: (line as Map)['revenue_category_id'] as String,
            treatment: switch (line['tax_treatment']) {
              final String name => TaxTreatment.fromName(name),
              _ => null,
            },
            totals: RevenueTotals(
              gross: Money.fromPaise(_int(line['gross_minor'])),
              tax: Money.fromPaise(_int(line['tax_minor'])),
              net: Money.fromPaise(_int(line['net_minor'])),
              contributions: _int(line['contributions']),
            ),
          ),
      ],
      expensesByCategory: [
        for (final line in (row['expense_by_hierarchy'] as List? ?? const []))
          ExpenseCategoryTotals(
            businessUnitId: unit,
            departmentId: (line as Map)['department_id'] as String,
            sectionId: line['section_id'] as String,
            categoryId: line['category_id'] as String,
            totals: ExpenseTotals(
              amount: Money.fromPaise(_int(line['amount_minor'])),
              contributions: _int(line['contributions']),
            ),
          ),
      ],
    );
  }

  /// Money arrives as an integer and is read as one.
  ///
  /// A `double` here would be the one place a JSON decode could quietly round a paisa, so
  /// a non-integer is refused rather than truncated: the server casts every sum to
  /// `bigint` precisely so this can never be a judgement call.
  static int _int(Object? value) => switch (value) {
    final int v => v,
    _ => throw ArgumentError.value(
      value,
      'value',
      'a reporting figure arrived as ${value.runtimeType} rather than an integer '
          'number of paise; binary floating point never touches a stored or computed '
          'currency amount',
    ),
  };
}
