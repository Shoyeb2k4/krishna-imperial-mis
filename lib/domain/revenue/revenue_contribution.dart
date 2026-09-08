/// The reporting interface for revenue: one contribution per accepted component.
///
/// Phase 4 Slice 12 defines and exposes this. **It builds no P&L** — that is Phase 5, with
/// the parity suite D-020 requires (D-087). What is settled here is the shape Phase 5 sums
/// and the guarantee that summing it is exact.
///
/// ## Derived, never stored (D-157)
///
/// `expense_period_allocations` is a physical table because a cross-period split is a
/// decision a person made that exists nowhere else (D-034, D-060) — take it away and the
/// information is gone. A revenue contribution carries **no such decision**: its period is
/// the entry's own stored `pnl_period_key`, and its money is the component's own stored
/// gross, tax and net. Every field is already canonical somewhere.
///
/// So `revenue_period_contributions` is a projection over the components on both sides —
/// a `security_barrier` view in Postgres, a view in SQLite — and the whole class of
/// maintenance hazard disappears with the store: a business-date correction moves the
/// period because the entry moved, a void removes the effect because the entry is voided,
/// an edit replaces the figures because the components were replaced, and a replayed
/// mutation has nothing extra to be idempotent about. None of those is a rule anybody has
/// to remember to apply.
///
/// ## Component grain, deliberately
///
/// A two-band Room day is **two** contributions even though the document totals aggregate
/// them (D-087). Flattening them into one blended rate would state a rate that was applied
/// to nothing, and would destroy the only structure that makes *"why did room tax change
/// this month?"* answerable.
///
/// ## Nothing here is re-rated
///
/// Every rate, treatment, basis and band on a contribution is the snapshot the component
/// recorded when the server accepted it. Nothing joins to today's tax configuration, so
/// deleting every rule in the organisation leaves historical reporting unchanged — which
/// is asserted rather than argued (D-080, D-122).
library;

import 'package:krishna_mis/domain/revenue/revenue_entry.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

/// One accepted revenue component, as reporting sees it.
final class RevenueContribution {
  const RevenueContribution({
    required this.componentId,
    required this.revenueEntryId,
    required this.orgId,
    required this.businessUnitId,
    required this.revenueCategoryId,
    required this.businessDate,
    required this.pnlPeriodKey,
    required this.gross,
    required this.tax,
    required this.net,
    required this.taxRuleId,
    required this.taxRateBasisPoints,
    required this.taxTreatment,
    required this.enteredBasis,
    required this.entryKind,
    required this.businessDateSource,
    this.supplySubtypeId,
    this.valueBandId,
    this.valueBandMinMinor,
    this.valueBandMaxMinor,
    this.premisesStatusCode,
    this.txnNumber,
    this.voidedAt,
  });

  final String componentId;
  final String revenueEntryId;
  final String orgId;
  final String businessUnitId;
  final String revenueCategoryId;

  /// The stored business date (D-067). Never `captured_at`, never a device date: a sale
  /// rung up at 02:00 belongs to the previous trading day, and a report that used the
  /// capture instant would put it in the wrong month.
  final BusinessDate businessDate;

  /// `YYYY-MM`, the key the entry itself stores. Not recomputed here — the server holds a
  /// CHECK that it agrees with the business date, and re-deriving it at read time is how a
  /// later change silently restates history (spec §5.2).
  final String pnlPeriodKey;

  final Money gross;
  final Money tax;
  final Money net;

  /// The rule that produced the figures, snapshotted onto the component.
  final String taxRuleId;
  final int taxRateBasisPoints;
  final TaxTreatment taxTreatment;
  final EnteredBasis enteredBasis;

  /// The conditional facts that selected the rule, where they applied.
  final String? supplySubtypeId;
  final String? valueBandId;
  final int? valueBandMinMinor;
  final int? valueBandMaxMinor;
  final String? premisesStatusCode;

  final RevenueEntryKind entryKind;

  /// Present-state provenance (D-143). A reporting **dimension**, never an input to an
  /// amount: `derived` and `corrected` entries with the same business date and the same
  /// components contribute identically.
  final BusinessDateSource businessDateSource;

  final String? txnNumber;

  /// Set when the parent sale is voided. Such a row is retained and inspectable and
  /// contributes nothing: every aggregate excludes it (D-006).
  final DateTime? voidedAt;

  bool get isActive => voidedAt == null;

  /// The invariant every contribution holds, restated where a caller can assert it.
  bool get reconciles => net.paise == gross.paise - tax.paise;
}

/// What a report asks for. Deliberately not a chart DTO (§25 of the Slice 12 brief).
///
/// [businessUnitIds] is **authority** and [businessUnitId] is a **choice** — the same
/// distinction the ledger draws (D-121). Authority is applied in SQL and cannot be cleared
/// by a filter; a report computed over rows the reader may not have is not a narrower
/// report, it is a leak.
final class RevenueContributionQuery {
  const RevenueContributionQuery({
    this.periodKey,
    this.from,
    this.to,
    this.businessUnitId,
    this.revenueCategoryId,
    this.businessUnitIds,
  });

  /// `YYYY-MM`. Mutually usable with [from]/[to]; both narrow.
  final String? periodKey;

  /// Inclusive range over the **business date**.
  final BusinessDate? from;
  final BusinessDate? to;

  final String? businessUnitId;
  final String? revenueCategoryId;

  /// Every unit this reader may see at all. `null` means an unscoped grant (D-025).
  final Set<String>? businessUnitIds;
}

/// Summed paise for one grouping. No percentage, no margin, no derived arithmetic.
///
/// The engines return primitives and the domain computes everything derived, once
/// (D-020). Net Sales, Operating Profit and margin are Phase 5's, out of these.
final class RevenueTotals {
  const RevenueTotals({
    required this.gross,
    required this.tax,
    required this.net,
    required this.contributions,
  });

  static const zero = RevenueTotals(
    gross: Money.zero,
    tax: Money.zero,
    net: Money.zero,
    contributions: 0,
  );

  final Money gross;
  final Money tax;
  final Money net;

  /// How many component rows were summed. A total of zero over 0 rows and a total of zero
  /// over 40 rows are different facts, and a report that cannot tell them apart will
  /// eventually present the first as the second.
  final int contributions;

  bool get reconciles => net.paise == gross.paise - tax.paise;

  RevenueTotals operator +(RevenueTotals other) => RevenueTotals(
    gross: gross + other.gross,
    tax: tax + other.tax,
    net: net + other.net,
    contributions: contributions + other.contributions,
  );

  @override
  String toString() =>
      'RevenueTotals(gross: $gross, tax: $tax, net: $net, n: $contributions)';
}

/// Totals for one business unit and revenue category, which is the grain the target
/// report shape needs (spec §10): revenue lines by category, then Gross Sales, then GST,
/// then Net Sales, per property.
final class RevenueCategoryTotals {
  const RevenueCategoryTotals({
    required this.businessUnitId,
    required this.revenueCategoryId,
    required this.totals,
    this.treatment,
  });

  final String businessUnitId;
  final String revenueCategoryId;
  final RevenueTotals totals;

  /// The treatment every component in this group recorded, or `null` where the group spans
  /// more than one.
  ///
  /// It travels because `none` and a configured `0%` both produce ₹0 of tax and are **not
  /// the same fact** (D-091, D-122). The headline P&L sums `tax` and does not care; a
  /// breakdown that dropped this would answer *"why is Banquet's GST nil?"* with the wrong
  /// reason. Collapsed to `null` rather than to whichever came first, because a group of
  /// mixed treatments is described by neither of them.
  final TaxTreatment? treatment;

  @override
  String toString() =>
      'RevenueCategoryTotals($businessUnitId/$revenueCategoryId '
      '${treatment?.name ?? 'mixed'}: $totals)';
}
