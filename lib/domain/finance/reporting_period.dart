/// What period a report covers, normalised to one inclusive range of P&L dates.
///
/// Phase 5 Slice 2. Spec §10 names Today, Yesterday, This Week, Last Week, This Month,
/// Last Month, Financial Year and Custom Range. This file turns every one of them into
/// the **same** shape — an inclusive `from`, an inclusive `to` — so the local and remote
/// engines consume one boundary contract instead of growing five period implementations
/// that agree until somebody edits one (D-020).
///
/// ## These are report-selection semantics, not a second accounting-period model
///
/// Nothing here is persisted, and nothing here decides which period an amount *belongs*
/// to. That is already settled and stored: `pnl_date` and `pnl_period_key` are computed
/// once at write time from `COALESCE(accounting_period_end, business_date)` and never
/// re-derived at read time (spec §5.2, D-016). A range selects over those stored dates.
///
/// The consequence worth stating, because it is the one that would silently misreport: an
/// expense's reporting month comes from its **contribution's** `pnl_date`, which for an
/// accrual is not its business date and is never its payment date. A June salary paid on
/// 5 July is a June cost. This file receives P&L dates and does not reinterpret them.
///
/// ## The week is Monday to Sunday, on the business date (D-165)
///
/// Spec §10 named the week and nothing in the repository defined it, so the project lead
/// did: **Monday through Sunday**, over canonical business dates. Never a UTC timestamp —
/// a sale rung up at 01:00 on a Monday has a business date of Sunday under the property's
/// 05:00 cut-off (D-019, D-067) and belongs to the week that is closing.
library;

import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// An inclusive range of P&L dates. Both ends are part of the report.
///
/// The only way to build one is by resolving a [ReportingPeriod], so a range whose end
/// precedes its start cannot exist — a caller cannot construct the invalid case and then
/// forget to check it (§17).
final class ReportRange {
  const ReportRange._(this.from, this.to);

  final BusinessDate from;
  final BusinessDate to;

  /// Whole days covered, both ends included. A single-day range covers one day.
  int get days => to.differenceInDays(from) + 1;

  bool contains(BusinessDate date) => date >= from && date <= to;

  /// `YYYY-MM` when this range is exactly one whole calendar month, otherwise null.
  ///
  /// Both contribution projections store `pnl_period_key`, and both index it. A range that
  /// happens to be a whole month can therefore be answered by an indexed equality rather
  /// than a scan — and, crucially, **the caller does not choose**: the optimisation is a
  /// property of the range, derived here, so a month asked for as a month and the same
  /// month asked for as a custom range take the same path and cannot give different
  /// answers (§7 of the Slice 3 brief).
  String? get wholeMonthKey {
    if (from.year != to.year || from.month != to.month) return null;
    if (from.day != 1) return null;
    final nextMonthFirst = from.month == 12
        ? BusinessDate.of(from.year + 1, 1, 1)
        : BusinessDate.of(from.year, from.month + 1, 1);
    return to == nextMonthFirst.addDays(-1) ? from.periodKey : null;
  }

  @override
  bool operator ==(Object other) =>
      other is ReportRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'ReportRange(${from.iso} … ${to.iso})';
}

/// Why a period could not be resolved.
///
/// An enum rather than a message: this layer states what is wrong and the surface decides
/// how to say it. A user-facing sentence compiled into the finance domain is a sentence
/// that cannot be translated, reworded, or given the context the screen has (§30).
enum ReportRangeProblem {
  /// A custom range whose end precedes its start. Not silently swapped — somebody asked
  /// for something that does not describe a period, and guessing which end they meant is
  /// how a report quietly covers a different month from the one on screen.
  endBeforeStart,
}

/// The result of resolving a period.
sealed class ReportRangeOutcome {
  const ReportRangeOutcome();
}

final class ReportRangeResolved extends ReportRangeOutcome {
  const ReportRangeResolved(this.range);
  final ReportRange range;
}

final class ReportRangeRejected extends ReportRangeOutcome {
  const ReportRangeRejected(this.problem);
  final ReportRangeProblem problem;
}

/// A period a manager can ask for.
sealed class ReportingPeriod {
  const ReportingPeriod();

  /// The inclusive P&L-date range this period covers.
  ReportRangeOutcome resolve();
}

/// One trading day.
final class SingleDayPeriod extends ReportingPeriod {
  const SingleDayPeriod(this.day);
  final BusinessDate day;

  @override
  ReportRangeOutcome resolve() => ReportRangeResolved(ReportRange._(day, day));
}

/// The Monday-to-Sunday week containing [anyDayWithin] (D-165).
final class WeekPeriod extends ReportingPeriod {
  const WeekPeriod(this.anyDayWithin);
  final BusinessDate anyDayWithin;

  @override
  ReportRangeOutcome resolve() {
    final start = anyDayWithin.addDays(1 - weekdayOf(anyDayWithin));
    return ReportRangeResolved(ReportRange._(start, start.addDays(6)));
  }
}

/// A calendar month, which is also the grain `pnl_period_key` stores (`YYYY-MM`).
final class MonthPeriod extends ReportingPeriod {
  const MonthPeriod(this.year, this.month);

  /// The month a P&L date falls in.
  factory MonthPeriod.of(BusinessDate date) =>
      MonthPeriod(date.year, date.month);

  final int year;
  final int month;

  /// `YYYY-MM` — the very key both contribution projections store, so a month report can
  /// be pushed down to an indexed equality rather than a range scan.
  String get periodKey => BusinessDate.of(year, month, 1).periodKey;

  @override
  ReportRangeOutcome resolve() {
    final first = BusinessDate.of(year, month, 1);
    final nextMonthFirst = month == 12
        ? BusinessDate.of(year + 1, 1, 1)
        : BusinessDate.of(year, month + 1, 1);
    return ReportRangeResolved(
      ReportRange._(first, nextMonthFirst.addDays(-1)),
    );
  }
}

/// An Indian financial year, 1 April to 31 March.
///
/// [FinancialYear] is reused rather than reimplemented: it is the same type the expense
/// and revenue numbering already use, and it agrees with `app.financial_year_of` and
/// `app.revenue_financial_year` on the server. A second FY algorithm written for reports
/// would be a second answer to "which year is this" (§15).
final class FinancialYearPeriod extends ReportingPeriod {
  const FinancialYearPeriod(this.financialYear);

  factory FinancialYearPeriod.of(BusinessDate date) =>
      FinancialYearPeriod(FinancialYear.of(date));

  final FinancialYear financialYear;

  @override
  ReportRangeOutcome resolve() => ReportRangeResolved(
    ReportRange._(financialYear.startsOn, financialYear.endsOn),
  );
}

/// Any two dates a manager picked. The only period that can be rejected.
final class CustomRangePeriod extends ReportingPeriod {
  const CustomRangePeriod({required this.from, required this.to});
  final BusinessDate from;
  final BusinessDate to;

  @override
  ReportRangeOutcome resolve() => to < from
      ? const ReportRangeRejected(ReportRangeProblem.endBeforeStart)
      : ReportRangeResolved(ReportRange._(from, to));
}

/// ISO weekday of a business date: Monday is 1, Sunday is 7.
///
/// `DateTime.utc` is used here as a **calendar**, not as an instant. A [BusinessDate] is
/// already a trading day with no time and no zone — it was derived from the property's
/// timezone and cut-off when the record was written, and persisted (D-019, D-067). Naming
/// UTC is what stops the host machine's zone from shifting the day; nothing here reads a
/// clock, and no timestamp is involved.
int weekdayOf(BusinessDate date) =>
    DateTime.utc(date.year, date.month, date.day).weekday;
