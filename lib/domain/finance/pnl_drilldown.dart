/// The P&L breakdown beneath a computed report, and the read-only drill-down to a source
/// document (Phase 5 Slice 10, D-166 as reconciled with D-171 by D-233).
///
/// ## The hierarchy, as the canonical model defines it
///
/// ```
///     Revenue    →  Revenue Category  →  Documents  →  read-only detail
///     Expenses   →  Department  →  Section  →  Category  →  Documents  →  detail
/// ```
///
/// Department and Section sit **above** Category (D-040's foreign-key ladder), so there is no
/// organisational level below a category — only the documents that contribute to it. Entry
/// kind, value band and supply subtype are not levels (Q5).
///
/// ## Nothing here is a second reporting model
///
/// The department and section figures are exact groupings of the category lines the P&L was
/// already built from, and the document figures are the same canonical cache rows summed at
/// a finer grain. Every level is shown only when its children add up **exactly** to the
/// parent on screen — gross, GST and net for revenue, amount for expenses, and the row
/// counts beside them. There is no "Other", "Unallocated" or rounding bucket: a level that
/// does not reconcile is not shown.
///
/// ## A document row is a contribution, not a document total
///
/// An expense can be split across properties, lines and periods. Its row in a bucket is
/// what it contributes **to that bucket in that range**, and is never presented as the
/// invoice total.
///
/// ## Fetched detail explains a cached row only when it provably matches it
///
/// Full document detail is not in the reporting cache and is fetched on demand, in memory
/// only. The cached report is one snapshot; the fetched document may be newer. It is shown
/// as the explanation of a row only when its canonical contribution to the selected bucket
/// equals the cached row exactly — otherwise the reader is told the transaction changed.
library;

import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart'
    show ReportingCoverage;
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

// ── Document rows ───────────────────────────────────────────────────────────

/// One revenue document's contribution to one property's revenue category over a range.
///
/// A revenue entry belongs to exactly one property, category and business date, so this
/// is the whole of the document — but it is still read as "what this bucket holds of it".
final class RevenueDocumentLine {
  const RevenueDocumentLine({
    required this.businessUnitId,
    required this.revenueCategoryId,
    required this.revenueEntryId,
    required this.pnlDate,
    required this.totals,
  });

  final String businessUnitId;
  final String revenueCategoryId;
  final String revenueEntryId;

  /// The stored accrual date. For revenue it is the stored business date (D-157).
  final BusinessDate pnlDate;

  /// Summed from the cached component rows. `contributions` is the component count.
  final RevenueTotals totals;

  @override
  bool operator ==(Object other) =>
      other is RevenueDocumentLine &&
      other.businessUnitId == businessUnitId &&
      other.revenueCategoryId == revenueCategoryId &&
      other.revenueEntryId == revenueEntryId &&
      other.pnlDate == pnlDate &&
      _sameRevenue(other.totals, totals);

  @override
  int get hashCode => Object.hash(
    businessUnitId,
    revenueCategoryId,
    revenueEntryId,
    pnlDate,
    totals.gross.paise,
    totals.tax.paise,
    totals.net.paise,
    totals.contributions,
  );

  @override
  String toString() =>
      'RevenueDocumentLine($revenueEntryId ${pnlDate.iso} $totals)';
}

/// One expense document's contribution to one exact Department + Section + Category bucket
/// of one property, over a range.
///
/// **Not the expense total.** A document split across properties, allocation lines or
/// accounting periods contributes only part of itself here, and the surface says so.
final class ExpenseDocumentLine {
  const ExpenseDocumentLine({
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
    required this.expenseId,
    required this.firstPnlDate,
    required this.lastPnlDate,
    required this.totals,
    this.vendorId,
  });

  final String businessUnitId;
  final String departmentId;
  final String sectionId;
  final String categoryId;
  final String expenseId;

  /// The earliest and latest accrual dates among the rows summed. Equal unless the document
  /// contributes to more than one accounting period inside the range.
  final BusinessDate firstPnlDate;
  final BusinessDate lastPnlDate;

  final String? vendorId;

  /// Summed from the cached period-contribution rows. `contributions` is the row count.
  final ExpenseTotals totals;

  bool get spansPeriods => firstPnlDate != lastPnlDate;

  @override
  bool operator ==(Object other) =>
      other is ExpenseDocumentLine &&
      other.businessUnitId == businessUnitId &&
      other.departmentId == departmentId &&
      other.sectionId == sectionId &&
      other.categoryId == categoryId &&
      other.expenseId == expenseId &&
      other.firstPnlDate == firstPnlDate &&
      other.lastPnlDate == lastPnlDate &&
      other.vendorId == vendorId &&
      other.totals.amount.paise == totals.amount.paise &&
      other.totals.contributions == totals.contributions;

  @override
  int get hashCode => Object.hash(
    businessUnitId,
    departmentId,
    sectionId,
    categoryId,
    expenseId,
    firstPnlDate,
    lastPnlDate,
    vendorId,
    totals.amount.paise,
    totals.contributions,
  );

  @override
  String toString() =>
      'ExpenseDocumentLine($expenseId ${firstPnlDate.iso} $totals)';
}

bool _sameRevenue(RevenueTotals a, RevenueTotals b) =>
    a.gross.paise == b.gross.paise &&
    a.tax.paise == b.tax.paise &&
    a.net.paise == b.net.paise &&
    a.contributions == b.contributions;

/// Document rows a source could stand behind, or why it could not.
sealed class DrilldownRows<T> {
  const DrilldownRows();
}

final class DrilldownRowsAvailable<T> extends DrilldownRows<T> {
  const DrilldownRowsAvailable(this.rows);
  final List<T> rows;
}

/// Never an empty list standing in for "could not read": a refusal is its own answer.
final class DrilldownRowsUnavailable<T> extends DrilldownRows<T> {
  const DrilldownRowsUnavailable(this.reason);

  /// [ReportingCoverage.notAuthorised] or [ReportingCoverage.notDownloaded].
  final ReportingCoverage reason;
}

// ── What an on-demand fetch established ─────────────────────────────────────

/// The canonical facts a fetched revenue document states about its reporting effect.
final class RevenueDocumentFacts {
  const RevenueDocumentFacts({
    required this.businessUnitId,
    required this.revenueCategoryId,
    required this.businessDate,
    required this.accepted,
    required this.voided,
    required this.components,
  });

  final String businessUnitId;
  final String revenueCategoryId;
  final BusinessDate businessDate;

  /// Server-issued number present (D-168).
  final bool accepted;
  final bool voided;

  /// Each component's stored gross, tax and net, one entry per component.
  final List<({Money gross, Money tax, Money net})> components;
}

/// One canonical expense period contribution a fetched document states.
final class ExpenseContributionFact {
  const ExpenseContributionFact({
    required this.businessUnitId,
    required this.departmentId,
    required this.sectionId,
    required this.categoryId,
    required this.pnlDate,
    required this.amount,
  });

  final String businessUnitId;
  final String departmentId;
  final String sectionId;
  final String categoryId;
  final BusinessDate pnlDate;
  final Money amount;
}

/// The canonical facts a fetched expense document states about its reporting effect.
final class ExpenseDocumentFacts {
  const ExpenseDocumentFacts({
    required this.accepted,
    required this.voided,
    required this.contributions,
  });

  final bool accepted;
  final bool voided;

  /// Every period contribution the server returned **to this caller**. A scoped reader is
  /// never given another property's lines (D-062), which is correct: only this bucket's
  /// share is compared.
  final List<ExpenseContributionFact> contributions;
}

/// The outcome of opening a document from a report.
sealed class ReportDocumentDetail<T> {
  const ReportDocumentDetail();
}

/// Fetched, and its contribution to the selected bucket equals the cached row exactly.
final class ReportDocumentReady<T> extends ReportDocumentDetail<T> {
  const ReportDocumentReady(this.document);
  final T document;
}

/// Fetched, and it no longer explains the cached row. The fresh values are **not** shown in
/// place of the report's: the report is refreshed instead.
final class ReportDocumentChanged<T> extends ReportDocumentDetail<T> {
  const ReportDocumentChanged();
}

/// The server withheld it, or returned nothing: not available to this person.
final class ReportDocumentNotAvailable<T> extends ReportDocumentDetail<T> {
  const ReportDocumentNotAvailable();
}

/// No answer: offline, unreachable, or no backend. Detail is not on this device.
final class ReportDocumentNotDownloaded<T> extends ReportDocumentDetail<T> {
  const ReportDocumentNotDownloaded();
}

// ── The rules ───────────────────────────────────────────────────────────────

abstract final class PnlDrilldown {
  // ── Expense hierarchy, grouped from the category lines the P&L already holds ──

  /// Every department, per property, in id order. Totals are exact sums of the leaves.
  static List<ExpenseHierarchyLine> departments(
    Iterable<ExpenseHierarchyLine> leaves,
  ) => _group(
    leaves,
    keyOf: (l) => (l.businessUnitId, l.departmentId, null, null),
  );

  /// The sections of one department.
  static List<ExpenseHierarchyLine> sections(
    Iterable<ExpenseHierarchyLine> leaves, {
    required String businessUnitId,
    required String departmentId,
  }) => _group(
    leaves.where(
      (l) =>
          l.businessUnitId == businessUnitId && l.departmentId == departmentId,
    ),
    keyOf: (l) => (l.businessUnitId, l.departmentId, l.sectionId, null),
  );

  /// The categories of one section.
  static List<ExpenseHierarchyLine> categories(
    Iterable<ExpenseHierarchyLine> leaves, {
    required String businessUnitId,
    required String departmentId,
    required String sectionId,
  }) => _group(
    leaves.where(
      (l) =>
          l.businessUnitId == businessUnitId &&
          l.departmentId == departmentId &&
          l.sectionId == sectionId,
    ),
    keyOf: (l) => (l.businessUnitId, l.departmentId, l.sectionId, l.categoryId),
  );

  /// The department line for one bucket path, or null when the report holds none.
  static ExpenseHierarchyLine? department(
    Iterable<ExpenseHierarchyLine> leaves, {
    required String businessUnitId,
    required String departmentId,
  }) => departments(leaves)
      .where(
        (l) =>
            l.businessUnitId == businessUnitId &&
            l.departmentId == departmentId,
      )
      .firstOrNull;

  /// The section line for one bucket path, or null.
  static ExpenseHierarchyLine? section(
    Iterable<ExpenseHierarchyLine> leaves, {
    required String businessUnitId,
    required String departmentId,
    required String sectionId,
  }) => sections(
    leaves,
    businessUnitId: businessUnitId,
    departmentId: departmentId,
  ).where((l) => l.sectionId == sectionId).firstOrNull;

  /// The exact Department + Section + Category bucket, or null.
  static ExpenseHierarchyLine? category(
    Iterable<ExpenseHierarchyLine> leaves, {
    required String businessUnitId,
    required String departmentId,
    required String sectionId,
    required String categoryId,
  }) => categories(
    leaves,
    businessUnitId: businessUnitId,
    departmentId: departmentId,
    sectionId: sectionId,
  ).where((l) => l.categoryId == categoryId).firstOrNull;

  /// One property's revenue category line, or null.
  static RevenueCategoryLine? revenueCategory(
    Iterable<RevenueCategoryLine> lines, {
    required String businessUnitId,
    required String revenueCategoryId,
  }) => lines
      .where(
        (l) =>
            l.businessUnitId == businessUnitId &&
            l.revenueCategoryId == revenueCategoryId,
      )
      .firstOrNull;

  /// The headline revenue figures as a parent for the revenue category level — the three
  /// canonical sums as the result holds them, with the rows behind them (Phase 6 Slice 9).
  static RevenueTotals revenueOf(PnlResult result) => RevenueTotals(
    gross: result.grossSales,
    tax: result.gst,
    net: result.netSales,
    contributions: result.revenueContributions,
  );

  /// The headline expense figure as a parent for the department level.
  static ExpenseTotals expensesOf(PnlResult result) => ExpenseTotals(
    amount: result.expenses,
    contributions: result.expenseContributions,
  );

  static List<ExpenseHierarchyLine> _group(
    Iterable<ExpenseHierarchyLine> lines, {
    required (String, String?, String?, String?) Function(ExpenseHierarchyLine)
    keyOf,
  }) {
    final totals = <(String, String?, String?, String?), ExpenseTotals>{};
    for (final line in lines) {
      final key = keyOf(line);
      totals[key] = (totals[key] ?? ExpenseTotals.zero) + line.totals;
    }
    final keys = totals.keys.toList()
      ..sort((a, b) {
        for (final (x, y) in [
          (a.$1, b.$1),
          (a.$2, b.$2),
          (a.$3, b.$3),
          (a.$4, b.$4),
        ]) {
          final c = (x ?? '').compareTo(y ?? '');
          if (c != 0) return c;
        }
        return 0;
      });
    return [
      for (final key in keys)
        ExpenseHierarchyLine(
          businessUnitId: key.$1,
          departmentId: key.$2,
          sectionId: key.$3,
          categoryId: key.$4,
          totals: totals[key]!,
        ),
    ];
  }

  // ── Exact reconciliation. No tolerance, no residual bucket ───────────────

  /// `Σ children == parent` on amount **and** row count.
  static bool expenseChildrenReconcile(
    ExpenseTotals parent,
    Iterable<ExpenseTotals> children,
  ) {
    var amount = 0;
    var rows = 0;
    for (final child in children) {
      amount += child.amount.paise;
      rows += child.contributions;
    }
    return amount == parent.amount.paise && rows == parent.contributions;
  }

  /// `Σ children == parent` on gross, GST and net, each on its own, **and** row count.
  static bool revenueChildrenReconcile(
    RevenueTotals parent,
    Iterable<RevenueTotals> children,
  ) {
    var gross = 0;
    var tax = 0;
    var net = 0;
    var rows = 0;
    for (final child in children) {
      gross += child.gross.paise;
      tax += child.tax.paise;
      net += child.net.paise;
      rows += child.contributions;
    }
    return gross == parent.gross.paise &&
        tax == parent.tax.paise &&
        net == parent.net.paise &&
        rows == parent.contributions;
  }

  // ── A fetched document against the cached row it is meant to explain ─────

  /// Whether a fetched revenue document states exactly the contribution the cached [line]
  /// holds, in the selected property, category and range.
  static bool revenueDocumentExplains(
    RevenueDocumentLine line, {
    required ReportRange range,
    required RevenueDocumentFacts fetched,
  }) {
    if (!fetched.accepted || fetched.voided) return false;
    if (fetched.businessUnitId != line.businessUnitId ||
        fetched.revenueCategoryId != line.revenueCategoryId ||
        fetched.businessDate != line.pnlDate ||
        !range.contains(fetched.businessDate)) {
      return false;
    }
    var gross = 0;
    var tax = 0;
    var net = 0;
    for (final c in fetched.components) {
      gross += c.gross.paise;
      tax += c.tax.paise;
      net += c.net.paise;
    }
    return gross == line.totals.gross.paise &&
        tax == line.totals.tax.paise &&
        net == line.totals.net.paise &&
        fetched.components.length == line.totals.contributions;
  }

  /// Whether a fetched expense document contributes exactly what the cached [line] holds to
  /// its Department + Section + Category bucket of its property, inside the range.
  static bool expenseDocumentExplains(
    ExpenseDocumentLine line, {
    required ReportRange range,
    required ExpenseDocumentFacts fetched,
  }) {
    if (!fetched.accepted || fetched.voided) return false;
    final bucket = [
      for (final c in fetched.contributions)
        if (c.businessUnitId == line.businessUnitId &&
            c.departmentId == line.departmentId &&
            c.sectionId == line.sectionId &&
            c.categoryId == line.categoryId &&
            range.contains(c.pnlDate))
          c,
    ];
    if (bucket.isEmpty) return false;
    var amount = 0;
    var first = bucket.first.pnlDate;
    var last = bucket.first.pnlDate;
    for (final c in bucket) {
      amount += c.amount.paise;
      if (c.pnlDate < first) first = c.pnlDate;
      if (c.pnlDate > last) last = c.pnlDate;
    }
    return amount == line.totals.amount.paise &&
        bucket.length == line.totals.contributions &&
        first == line.firstPnlDate &&
        last == line.lastPnlDate;
  }
}
