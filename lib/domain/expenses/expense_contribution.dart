/// The reporting interface for expenses: one contribution per allocation line per
/// accounting period.
///
/// Phase 5 Slice 1. This is the **expense half of one reporting vocabulary** — the
/// deliberate mirror of `revenue_contribution.dart`, so the Phase 5 engines sum one shape
/// per side of the P&L rather than two shapes that agree by coincidence.
///
/// ## Stored, not derived — and that is the asymmetry, not an inconsistency
///
/// `revenue_period_contributions` is a view over the components because a revenue
/// contribution carries no decision of its own (D-157). An expense contribution does:
/// `expense_period_allocations` is a physical table because a cross-period split is
/// something a person chose and it exists nowhere else (D-034, D-060). Take the row away
/// and the information is gone.
///
/// So the two sides differ in where the rows live and agree in every way a report cares
/// about: `org_id`, `business_unit_id`, a `pnl_period_key` in `YYYY-MM`, integer minor
/// units, and `voided_at` with the same meaning — the row stays, the aggregate excludes.
///
/// ## What contributes (D-168)
///
/// One canonical reporting semantic, shared with revenue and applied before any filter:
///
///   * **canonical** — the server has accepted it. `txn_number` is the marker, issued on
///     acceptance and by nothing else, `NULL` on every locally created document and
///     impossible for a client to invent (D-008).
///   * **not voided** — a voided expense contributes nothing and stays inspectable
///     (D-006).
///   * **not scope-revoked** — a retained unsent attempt over a property this user no
///     longer holds is nobody's cost (D-070, D-074).
///
/// Before D-168 the expense side applied the last two and not the first, while revenue
/// applied all three. Combined into a P&L that subtracts costs the server has never
/// accepted from sales it has, which understates Operating Profit silently and in one
/// direction. Pending, rejected, conflicted and quarantined work stays visible in the
/// transaction surfaces, where somebody can act on it, and contributes zero here (D-167).
///
/// ## Gross cost, including GST
///
/// An expense amount is what was actually incurred, GST included (spec §6.1, D-018).
/// There is no input-tax-credit engine and nothing here nets tax out of a cost, so an
/// expense contribution carries **one** amount where a revenue contribution carries gross,
/// tax and net.
library;

import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// One accepted expense period contribution, as reporting sees it.
final class ExpenseContribution {
  const ExpenseContribution({
    required this.contributionId,
    required this.expenseId,
    required this.allocationId,
    required this.orgId,
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
    required this.amount,
    required this.pnlDate,
    required this.pnlPeriodKey,
    required this.businessDate,
    required this.isDerived,
    this.accountingPeriodStart,
    this.accountingPeriodEnd,
    this.vendorId,
    this.txnNumber,
    this.voidedAt,
  });

  final String contributionId;
  final String expenseId;
  final String allocationId;
  final String orgId;

  /// The property this share of the cost belongs to. On a shared bill the same document
  /// contributes to two properties through two allocation lines (D-003), which is what
  /// makes a shared cost attributable at all.
  final String businessUnitId;
  final String departmentId;
  final String sectionId;
  final String categoryId;

  /// Gross cost in paise, GST included (D-018).
  final Money amount;

  /// The accrual date this amount is attributed to, and the `YYYY-MM` key derived from it
  /// once and stored. Not recomputed here: re-deriving an attribution rule at read time is
  /// how a later configuration change silently restates closed history (spec §5.2).
  final BusinessDate pnlDate;
  final String pnlPeriodKey;

  /// The document's operational date (D-019, D-067). The ledger and the edit window use
  /// this; profitability uses [pnlDate], and the two legitimately differ for an accrual.
  final BusinessDate businessDate;

  /// The optional service period this contribution covers, where one was stated.
  final BusinessDate? accountingPeriodStart;
  final BusinessDate? accountingPeriodEnd;

  /// False only where a person deliberately split the line across periods (D-034). A
  /// derived contribution is the whole line in its own period and is the ordinary case.
  final bool isDerived;

  final String? vendorId;

  /// The server-issued number. `null` means the document has not been accepted, and such
  /// a contribution is excluded from every canonical total (D-168).
  final String? txnNumber;

  /// Set when the parent document is voided. Retained, inspectable, contributing nothing.
  final DateTime? voidedAt;

  bool get isCanonical => txnNumber != null;
  bool get isActive => voidedAt == null;
}

/// What an expense report asks for. The mirror of `RevenueContributionQuery`.
///
/// [businessUnitIds] is **authority** and [businessUnitId] is a **choice** — the
/// distinction the ledger already draws (D-121). Authority is applied in SQL and cannot be
/// cleared by a filter; a report computed over rows the reader may not have is not a
/// narrower report, it is a leak.
final class ExpenseContributionQuery {
  const ExpenseContributionQuery({
    this.periodKey,
    this.from,
    this.to,
    this.businessUnitId,
    this.departmentId,
    this.sectionId,
    this.categoryId,
    this.vendorId,
    this.businessUnitIds,
  });

  /// `YYYY-MM`. Usable together with [from]/[to]; both narrow.
  final String? periodKey;

  /// Inclusive range over the **P&L date**, which is the accrual basis profitability uses
  /// (spec §5.3). A ledger range would filter the business date instead, and mixing the
  /// two in one report is the thing spec §5 exists to prevent.
  final BusinessDate? from;
  final BusinessDate? to;

  final String? businessUnitId;
  final String? departmentId;
  final String? sectionId;
  final String? categoryId;
  final String? vendorId;

  /// Every unit this reader may see at all. `null` means an unscoped grant (D-025).
  final Set<String>? businessUnitIds;
}

/// Summed paise for one grouping. No percentage, no margin, no derived arithmetic —
/// engines return primitives and the domain computes everything derived, once (D-020).
final class ExpenseTotals {
  const ExpenseTotals({required this.amount, required this.contributions});

  static const zero = ExpenseTotals(amount: Money.zero, contributions: 0);

  final Money amount;

  /// How many contribution rows were summed. A total of zero over 0 rows and a total of
  /// zero over 40 rows are different facts, and a report that cannot tell them apart will
  /// eventually present the first as the second.
  final int contributions;

  ExpenseTotals operator +(ExpenseTotals other) => ExpenseTotals(
    amount: amount + other.amount,
    contributions: contributions + other.contributions,
  );

  @override
  String toString() => 'ExpenseTotals(amount: $amount, n: $contributions)';
}

/// Totals for one property and one expense category, which is the grain spec §10's target
/// report shape needs: expense lines by category, then Total Expenses, per property.
///
/// The department and section travel with it so a breakdown can roll up the hierarchy
/// without a second query (spec §28's department analysis).
final class ExpenseCategoryTotals {
  const ExpenseCategoryTotals({
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
    required this.totals,
  });

  final String businessUnitId;
  final String departmentId;
  final String sectionId;
  final String categoryId;
  final ExpenseTotals totals;

  @override
  String toString() =>
      'ExpenseCategoryTotals($businessUnitId/$categoryId: $totals)';
}
