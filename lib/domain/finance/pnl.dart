/// The canonical management P&L, and the only place its arithmetic lives.
///
/// Phase 5 Slice 2, and the directive's §21.1 obligation: *"all derived financial
/// arithmetic lives once, in `domain/finance/`"*. Nothing in this file knows what a
/// database, a network, a widget or a sync state is.
///
/// ## The division of labour, which is the whole point
///
/// ```
///         LocalReportingEngine  ─┐
///                                ├─ primitive summed paise ──► domain/finance ──► PnlResult
///         RemoteReportingEngine ─┘
/// ```
///
/// An engine's entire job is to select and sum the right canonical rows. **Neither engine
/// may compute Net Sales, Operating Profit or margin** — if both did, they would agree
/// until somebody edited one, and the parity suite exists because that is not a risk worth
/// carrying (spec §21.2, D-020). The divergence surface is deliberately shrunk from "the
/// whole P&L" to "did you sum the right rows".
///
/// ## What this layer is not allowed to care about
///
/// **Sync state.** Slice 1 established one canonical reporting predicate — accepted, not
/// voided, not scope-revoked — and it belongs to the repository, in SQL, before any figure
/// reaches here (D-168). A filter in the calculator would be a second place for it to be
/// forgotten. What arrives here is already canonical, and the type system says nothing
/// about pending work because this layer has no business having an opinion about it.
///
/// **Tax rates.** A P&L sums the tax each component recorded when the server accepted it.
/// The calculator is given `tax` and never a rate, so it *cannot* re-rate an aggregate —
/// which is the mistake that costs a paisa a day and cannot be found afterwards. See the
/// one-paisa control in the tests.
///
/// **Freshness.** Slice 6's. [PnlResult] is composable with it and hardwires none of it.
///
/// ## The identities
///
/// ```
///         Gross Sales      = Σ accepted revenue gross      (summed, never Net + GST)
///         GST              = Σ accepted revenue tax
///         Net Sales        = Σ accepted revenue net
///         Gross Sales      = GST + Net Sales               exactly, no tolerance
///
///         Expenses         = Σ accepted expense contributions
///                            gross cost including GST, no input credit (spec §6.1, D-018)
///
///         Operating Profit = Net Sales − Expenses          may be negative
/// ```
library;

import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/operating_margin.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

// ── Unavailable is not zero (D-163) ─────────────────────────────────────────

/// Why a side of the P&L could not be established.
enum ReportingSideUnavailable {
  /// The caller may not read this side at all. The reporting boundary decides that and
  /// refuses; this value is how the refusal travels without becoming a figure.
  notAuthorised,

  /// The range predates what this device holds and it could not be fetched (D-170).
  /// Distinct from "there was no trade": nobody knows yet.
  notDownloaded,
}

/// One side of a P&L: either the summed facts, or a statement that there are none to be
/// had.
///
/// **This exists so that `unavailable` cannot be spelled `₹0`.** A nullable field defaulted
/// to zero is the shape D-163 forbids, because a P&L that renders Expenses against a
/// revenue side the reader may not see reports a large loss that never happened — and it
/// looks exactly like a real one. Actual zero is a perfectly good answer and is
/// [SideAvailable] carrying zeroes; the two are different values of different variants.
sealed class ReportingSide<T> {
  const ReportingSide();
}

final class SideAvailable<T> extends ReportingSide<T> {
  const SideAvailable(this.facts);
  final T facts;
}

final class SideUnavailable<T> extends ReportingSide<T> {
  const SideUnavailable(this.reason);
  final ReportingSideUnavailable reason;
}

// ── Breakdown lines ─────────────────────────────────────────────────────────

/// Revenue for one property and category, carrying the treatment that produced it.
///
/// The treatment travels because `none` and a configured `0%` both yield ₹0 of tax and are
/// **not the same fact**: one is a decision somebody made about a supply, the other a rate
/// somebody set (D-091, D-122). The headline P&L sums `tax` and does not care; a breakdown
/// that flattened them would answer *"why is Banquet's GST nil?"* with the wrong reason.
///
/// `null` means the grain covers more than one treatment and no single one describes it —
/// stated rather than defaulted to whichever came first.
final class RevenueCategoryLine {
  const RevenueCategoryLine({
    required this.businessUnitId,
    required this.revenueCategoryId,
    required this.totals,
    this.treatment,
  });

  final String businessUnitId;
  final String revenueCategoryId;
  final RevenueTotals totals;
  final TaxTreatment? treatment;

  @override
  String toString() =>
      'RevenueCategoryLine($businessUnitId/$revenueCategoryId, '
      '${treatment?.name ?? 'mixed'}: $totals)';
}

/// Expenses for one point in the hierarchy, at whatever grain the caller grouped to.
///
/// Identities only. Display names are not resolved here: a master may have been renamed
/// since the transaction was recorded, and which label a report shows is a policy question
/// with its own rules (D-035, D-038) that a calculator has no way to answer.
final class ExpenseHierarchyLine {
  const ExpenseHierarchyLine({
    required this.businessUnitId,
    required this.totals,
    this.departmentId,
    this.sectionId,
    this.categoryId,
    this.vendorId,
  });

  final String businessUnitId;
  final String? departmentId;
  final String? sectionId;
  final String? categoryId;
  final String? vendorId;
  final ExpenseTotals totals;

  @override
  String toString() =>
      'ExpenseHierarchyLine($businessUnitId/${categoryId ?? '*'}: $totals)';
}

// ── The result ──────────────────────────────────────────────────────────────

/// A computed management P&L for one range, and for one property or the organisation.
///
/// Every figure is integer paise. Nothing here is a percentage except [margin], which is
/// an exact ratio and is not divided until something prints it.
final class PnlResult {
  const PnlResult({
    required this.range,
    required this.grossSales,
    required this.gst,
    required this.netSales,
    required this.expenses,
    this.businessUnitId,
    this.revenueByCategory = const [],
    this.expenseByHierarchy = const [],
  });

  final ReportRange range;

  /// The property, or `null` for a consolidated result across every permitted unit.
  final String? businessUnitId;

  final Money grossSales;
  final Money gst;
  final Money netSales;
  final Money expenses;

  final List<RevenueCategoryLine> revenueByCategory;
  final List<ExpenseHierarchyLine> expenseByHierarchy;

  bool get isConsolidated => businessUnitId == null;

  /// Net Sales − Expenses. **Negative when the property lost money**, and deliberately not
  /// clamped: this is a management P&L, not a counter that only goes up.
  Money get operatingProfit => netSales - expenses;

  /// Exact, undivided, and [MarginNotApplicable] when net sales are zero (spec §10).
  OperatingMargin get margin => netSales.isZero
      ? const MarginNotApplicable()
      : MarginRatio(
          operatingProfitPaise: operatingProfit.paise,
          netSalesPaise: netSales.paise,
        );

  /// `Gross Sales == GST + Net Sales`, exactly.
  ///
  /// It holds because all three are summed independently from stored component snapshots
  /// that each satisfy it, never because one was derived from the other two. Asserted
  /// rather than assumed, so a future engine that computed gross as `net + tax` would be
  /// caught by the identity it broke somewhere else.
  bool get reconciles => grossSales.paise == gst.paise + netSales.paise;

  @override
  String toString() =>
      'PnlResult(${businessUnitId ?? 'consolidated'} $range '
      'gross: $grossSales, gst: $gst, net: $netSales, '
      'expenses: $expenses, profit: $operatingProfit)';
}

/// Why a P&L could not be produced.
enum PnlRefusal {
  /// The range does not describe a period (§17).
  invalidDateRange,

  /// The revenue side could not be established. **Never substituted with zero** (D-163).
  revenueUnavailable,

  /// The expense side could not be established.
  expensesUnavailable,

  /// Neither side could be.
  bothSidesUnavailable,
}

/// The outcome of asking for a P&L.
sealed class PnlOutcome {
  const PnlOutcome();
}

final class PnlComputed extends PnlOutcome {
  const PnlComputed(this.result);
  final PnlResult result;
}

final class PnlRefused extends PnlOutcome {
  const PnlRefused(this.refusal, {this.sideReason});
  final PnlRefusal refusal;

  /// Why the unavailable side was unavailable, when exactly one side was.
  final ReportingSideUnavailable? sideReason;
}

// ── The calculator ──────────────────────────────────────────────────────────

/// The one canonical P&L computation.
///
/// Both sides are **required**, and neither is nullable. That is D-163 expressed in the
/// type rather than in a comment: there is no argument a caller can omit and have read as
/// zero, and the only way to say "I could not get this" is a [SideUnavailable] that this
/// function refuses on.
abstract final class Pnl {
  /// Computes a P&L for one property, or for the organisation when [businessUnitId] is
  /// null.
  static PnlOutcome compute({
    required ReportingPeriod period,
    required ReportingSide<RevenueTotals> revenue,
    required ReportingSide<ExpenseTotals> expenses,
    String? businessUnitId,
    List<RevenueCategoryLine> revenueByCategory = const [],
    List<ExpenseHierarchyLine> expenseByHierarchy = const [],
  }) {
    final resolved = period.resolve();
    if (resolved is ReportRangeRejected) {
      return const PnlRefused(PnlRefusal.invalidDateRange);
    }
    final range = (resolved as ReportRangeResolved).range;

    // Refuse before computing anything, and do it exhaustively. A half-P&L is not a
    // narrower report; it is a wrong one, and wrong in a direction a reader cannot detect
    // from the figure. The switch is over both sides at once so the compiler, not a
    // reviewer, is what guarantees every combination is answered (D-163).
    return switch ((revenue, expenses)) {
      (SideUnavailable<RevenueTotals>(), SideUnavailable<ExpenseTotals>()) =>
        const PnlRefused(PnlRefusal.bothSidesUnavailable),

      (SideUnavailable<RevenueTotals>(:final reason), _) => PnlRefused(
        PnlRefusal.revenueUnavailable,
        sideReason: reason,
      ),

      (_, SideUnavailable<ExpenseTotals>(:final reason)) => PnlRefused(
        PnlRefusal.expensesUnavailable,
        sideReason: reason,
      ),

      (
        SideAvailable<RevenueTotals>(facts: final sales),
        SideAvailable<ExpenseTotals>(facts: final costs),
      ) =>
        PnlComputed(
          PnlResult(
            range: range,
            businessUnitId: businessUnitId,
            // Summed from stored snapshots. Gross is **not** net + tax: the three are
            // three independent sums of figures the server accepted, and deriving one
            // from the others is how a rounding difference becomes invisible.
            grossSales: sales.gross,
            gst: sales.tax,
            netSales: sales.net,
            expenses: costs.amount,
            revenueByCategory: List.unmodifiable(revenueByCategory),
            expenseByHierarchy: List.unmodifiable(expenseByHierarchy),
          ),
        ),
    };
  }

  /// Adds per-property results into one organisation result.
  ///
  /// Every figure is an exact sum of the figures beneath it, so
  /// `Σ per-unit == consolidated` holds for gross, GST, net and expenses — and Operating
  /// Profit follows from the consolidated net and expenses rather than being summed
  /// separately, which is the same number by associativity and one fewer place to drift.
  ///
  /// **Percentages are never averaged.** The consolidated margin is computed from the
  /// consolidated ratio; averaging two properties' margins would weight a small property
  /// equally with a large one and produce a figure that is not any property's and not the
  /// organisation's.
  static PnlResult consolidate(Iterable<PnlResult> parts) {
    final list = parts.toList(growable: false);
    if (list.isEmpty) {
      throw ArgumentError.value(
        parts,
        'parts',
        'consolidating nothing has no range and no meaning; a report over no '
            'permitted property is a refusal, not a result of zero',
      );
    }
    final range = list.first.range;
    for (final part in list) {
      if (part.range != range) {
        throw ArgumentError.value(
          parts,
          'parts',
          'consolidating results over different ranges would present one period as '
              'another: ${part.range} against $range',
        );
      }
    }
    return PnlResult(
      range: range,
      grossSales: Money.sum(list.map((p) => p.grossSales)),
      gst: Money.sum(list.map((p) => p.gst)),
      netSales: Money.sum(list.map((p) => p.netSales)),
      expenses: Money.sum(list.map((p) => p.expenses)),
      revenueByCategory: List.unmodifiable(
        list.expand((p) => p.revenueByCategory),
      ),
      expenseByHierarchy: List.unmodifiable(
        list.expand((p) => p.expenseByHierarchy),
      ),
    );
  }
}
