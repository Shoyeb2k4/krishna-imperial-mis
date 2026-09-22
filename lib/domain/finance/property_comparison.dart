/// Comparing one consolidated P&L's properties with each other (Phase 6 Slice 6).
///
/// The Windows Overview shows Net Sales, Expenses and Operating Profit **per property**
/// beside each other. Those figures are not a second report: they are an exact grouping of
/// the category lines the consolidated result was already built from, which is the same
/// thing [PnlDrilldown.departments] does one level down.
///
/// ## Why it lives here rather than in a widget
///
/// Grouping lines by property and taking a difference is arithmetic over money, and this
/// project keeps every piece of that in `domain/finance` (D-020, spec §21.1). A surface
/// that summed its own per-property totals would be a second answer to *what did Crystal
/// Canopy earn*, and the two would agree until somebody edited one.
///
/// ## And why each property's figures come from `Pnl.compute`
///
/// A property's Operating Profit and margin are **not** written out again here. The per
/// property primitives are handed to the one canonical calculator, so `netSales − expenses`
/// and the exact margin ratio have exactly one definition in this product rather than a
/// copy that reads the same today (D-119, D-131).
///
/// ## It refuses rather than showing a split it cannot stand behind
///
/// * a result for **one** property has nothing to compare, and is refused rather than
///   drawn as a chart of one bar;
/// * a breakdown that does not reconcile exactly with its headline is refused, because a
///   property whose lines are missing would simply appear smaller than it is — the D-236
///   rule, applied to the dimension a reader is least able to check;
/// * and the per-property figures are checked to add back to the headline **after** they
///   are grouped, so the grouping itself is proven rather than assumed.
///
/// Nothing is ever substituted with zero, and no property is labelled a winner.
library;

import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// Why a consolidated result was not split into its properties.
enum PropertyComparisonRefusal {
  /// The report covers one property, so there is nothing to compare it with.
  singleProperty,

  /// The category lines do not add up exactly to the headline figures, so a per-property
  /// grouping of them would understate whichever property is missing a line (D-236).
  doesNotReconcile,
}

/// One property's figures inside a consolidated report.
final class PropertyFigures {
  const PropertyFigures({required this.businessUnitId, required this.result});

  final String businessUnitId;

  /// That property's P&L over the same range, computed by [Pnl.compute] from its own
  /// grouped primitives. Operating Profit and the margin are therefore the canonical ones.
  final PnlResult result;

  Money get netSales => result.netSales;
  Money get expenses => result.expenses;
  Money get operatingProfit => result.operatingProfit;

  @override
  String toString() => 'PropertyFigures($businessUnitId: $result)';
}

sealed class PropertyComparisonOutcome {
  const PropertyComparisonOutcome();
}

/// No split, and the reason. Never an empty list standing in for one.
final class PropertyComparisonRefused extends PropertyComparisonOutcome {
  const PropertyComparisonRefused(this.reason);
  final PropertyComparisonRefusal reason;

  @override
  String toString() => 'PropertyComparisonRefused(${reason.name})';
}

/// Every property in the report, in business-unit id order.
final class PropertyComparisonReady extends PropertyComparisonOutcome {
  const PropertyComparisonReady({
    required this.properties,
    required this.total,
  });

  /// In id order — never in figure order. A dashboard that reordered its properties as
  /// the month went on would make two readings of the same screen hard to compare, and
  /// ranking two businesses against each other is not a statement this product makes.
  final List<PropertyFigures> properties;

  /// The consolidated result these add back to, exactly.
  final PnlResult total;

  @override
  String toString() =>
      'PropertyComparisonReady(${properties.length} properties)';
}

abstract final class PropertyComparison {
  /// Splits a consolidated [result] into its properties, or refuses.
  static PropertyComparisonOutcome of(PnlResult result) {
    if (!result.isConsolidated) {
      return const PropertyComparisonRefused(
        PropertyComparisonRefusal.singleProperty,
      );
    }
    if (!result.breakdownReconciles) {
      return const PropertyComparisonRefused(
        PropertyComparisonRefusal.doesNotReconcile,
      );
    }

    // Both sides, so a property with costs and no takings is still a property — and a
    // property with takings and no costs likewise. Dropping either would silently remove
    // it from the comparison.
    final revenue = <String, RevenueTotals>{};
    final expenses = <String, ExpenseTotals>{};
    for (final line in result.revenueByCategory) {
      revenue[line.businessUnitId] =
          (revenue[line.businessUnitId] ?? RevenueTotals.zero) + line.totals;
    }
    for (final line in result.expenseByHierarchy) {
      expenses[line.businessUnitId] =
          (expenses[line.businessUnitId] ?? ExpenseTotals.zero) + line.totals;
    }

    final ids = <String>{...revenue.keys, ...expenses.keys}.toList()..sort();
    if (ids.length < 2) {
      return const PropertyComparisonRefused(
        PropertyComparisonRefusal.singleProperty,
      );
    }

    final period = CustomRangePeriod(
      from: result.range.from,
      to: result.range.to,
    );
    final properties = <PropertyFigures>[];
    for (final id in ids) {
      final outcome = Pnl.compute(
        period: period,
        businessUnitId: id,
        revenue: SideAvailable(revenue[id] ?? RevenueTotals.zero),
        expenses: SideAvailable(expenses[id] ?? ExpenseTotals.zero),
        revenueByCategory: [
          for (final l in result.revenueByCategory)
            if (l.businessUnitId == id) l,
        ],
        expenseByHierarchy: [
          for (final l in result.expenseByHierarchy)
            if (l.businessUnitId == id) l,
        ],
      );
      // Both sides are supplied and the range came from a computed result, so the only
      // way here is a computed one. Refusing rather than asserting keeps a future change
      // to the calculator from turning into a crash on a dashboard.
      if (outcome is! PnlComputed) {
        return const PropertyComparisonRefused(
          PropertyComparisonRefusal.doesNotReconcile,
        );
      }
      properties.add(
        PropertyFigures(businessUnitId: id, result: outcome.result),
      );
    }

    // The grouping is proven, not assumed: the parts must add back to the whole on every
    // primitive, exactly. It follows from the reconciliation above — which is why a
    // failure here would mean the grouping itself is wrong.
    if (Money.sum(properties.map((p) => p.result.grossSales)) !=
            result.grossSales ||
        Money.sum(properties.map((p) => p.result.gst)) != result.gst ||
        Money.sum(properties.map((p) => p.netSales)) != result.netSales ||
        Money.sum(properties.map((p) => p.expenses)) != result.expenses) {
      return const PropertyComparisonRefused(
        PropertyComparisonRefusal.doesNotReconcile,
      );
    }

    return PropertyComparisonReady(
      properties: List.unmodifiable(properties),
      total: result,
    );
  }
}
