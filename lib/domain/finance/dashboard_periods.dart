/// Dashboard periods and the period each is compared with (Phase 6, D-251, D-252, D-254).
///
/// ## These are dashboard semantics, not the P&L screen's
///
/// The Phase 5 P&L screen resolves *This Month* to the whole calendar month and *Financial
/// Year* to the whole financial year (`reporting_presets.dart`, D-225). That is unchanged.
/// A dashboard answers a different question — *how are we doing so far, against the same
/// stretch last time?* — so its periods are **to date** and end at the property's current
/// business date (D-252). A future-dated accrual therefore appears on the dashboard only
/// once its P&L date has arrived.
///
/// ## Comparable periods (D-251)
///
/// ```
///   Today so far            today                 vs  the previous business date
///   Week to date            Monday .. today       vs  last Monday .. same weekday
///   Month to date           1st .. today          vs  last month's 1st .. same ordinal
///                                                     day, capped at that month's end
///   Financial year to date  1 April .. today      vs  last 1 April .. same date a year
///                                                     earlier; 29 Feb caps at 28 Feb
///   Custom                  from .. to (n days)   vs  the n days immediately before
/// ```
///
/// Where the comparator had to be capped the pair says so, and both ranges carry their own
/// day counts, so a surface can state a 31-day month against a 28-day one truthfully. A
/// financial year to date can also differ by one day in the other direction — when the
/// current stretch holds a 29 February and the previous one does not, or the reverse — and
/// that is not a cap: the equivalent date existed. The day counts say it.
///
/// Every range here is derived from a business date the caller already holds. No clock, no
/// UTC instant and no transaction timestamp is read.
library;

import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// The periods a dashboard offers. Every relative one is named as unfinished.
enum DashboardPeriodKind {
  today('Today so far'),
  weekToDate('Week to date'),
  monthToDate('Month to date'),
  financialYearToDate('Financial year to date'),
  custom('Custom');

  const DashboardPeriodKind(this.label);

  /// A label that never makes an incomplete period look complete.
  final String label;
}

/// A dashboard period and the period it is compared with.
final class DashboardPeriodPair {
  const DashboardPeriodPair._({
    required this.kind,
    required this.current,
    required this.comparison,
    required this.comparisonCapped,
  });

  /// A pair built by hand, for testing the cross-property agreement check only.
  const DashboardPeriodPair.forTesting({
    required this.current,
    required this.comparison,
    required this.comparisonCapped,
    this.kind = DashboardPeriodKind.custom,
  });

  final DashboardPeriodKind kind;
  final ReportRange current;
  final ReportRange comparison;

  /// The equivalent end date did not exist in the comparison period — a shorter previous
  /// month, or a 29 February with no counterpart — so the comparator stops at that
  /// period's last day instead.
  final bool comparisonCapped;

  @override
  bool operator ==(Object other) =>
      other is DashboardPeriodPair &&
      other.kind == kind &&
      other.current == current &&
      other.comparison == comparison &&
      other.comparisonCapped == comparisonCapped;

  @override
  int get hashCode => Object.hash(kind, current, comparison, comparisonCapped);

  @override
  String toString() =>
      'DashboardPeriodPair(${kind.name} $current vs $comparison'
      '${comparisonCapped ? ', capped' : ''})';
}

/// Why no pair could be produced.
enum DashboardPairRefusal {
  /// A custom range whose end precedes its start. Never swapped.
  endBeforeStart,

  /// A property's business-date rules are unknown on this device, or there is no
  /// property. Refused rather than defaulted (D-225).
  calendarUnavailable,

  /// The properties disagree about the current range. The reader is sent to Custom.
  currentRangesDiffer,

  /// The properties disagree about the comparison range (D-254).
  comparisonRangesDiffer,
}

sealed class DashboardPairOutcome {
  const DashboardPairOutcome();
}

final class DashboardPairResolved extends DashboardPairOutcome {
  const DashboardPairResolved(this.pair);
  final DashboardPeriodPair pair;
}

final class DashboardPairRejected extends DashboardPairOutcome {
  const DashboardPairRejected(
    this.reason, {
    this.currentByUnit = const {},
    this.comparisonByUnit = const {},
    this.unitsWithoutCalendar = const {},
  });

  final DashboardPairRefusal reason;

  /// What each property resolved, when the refusal is a disagreement. No property's
  /// answer is preferred; they are all reported.
  final Map<String, ReportRange> currentByUnit;
  final Map<String, ReportRange> comparisonByUnit;
  final Set<String> unitsWithoutCalendar;
}

abstract final class DashboardPeriods {
  /// The pair for a relative [kind], for a property whose current business date is
  /// [today]. [DashboardPeriodKind.custom] has no relative meaning and is refused as a
  /// programming error — use [forCustom].
  static DashboardPairOutcome forToday(
    DashboardPeriodKind kind,
    BusinessDate today,
  ) => DashboardPairResolved(switch (kind) {
    DashboardPeriodKind.today => DashboardPeriodPair._(
      kind: kind,
      current: _range(today, today),
      comparison: _range(today.addDays(-1), today.addDays(-1)),
      comparisonCapped: false,
    ),
    DashboardPeriodKind.weekToDate => _weekToDate(today),
    DashboardPeriodKind.monthToDate => _monthToDate(today),
    DashboardPeriodKind.financialYearToDate => _financialYearToDate(today),
    DashboardPeriodKind.custom => throw ArgumentError.value(
      kind,
      'kind',
      'a custom period needs explicit dates: use forCustom',
    ),
  });

  /// A custom range, against the immediately preceding range of equal length.
  static DashboardPairOutcome forCustom({
    required BusinessDate from,
    required BusinessDate to,
  }) {
    if (to < from) {
      return const DashboardPairRejected(DashboardPairRefusal.endBeforeStart);
    }
    final current = _range(from, to);
    return DashboardPairResolved(
      DashboardPeriodPair._(
        kind: DashboardPeriodKind.custom,
        current: current,
        comparison: _range(from.addDays(-current.days), from.addDays(-1)),
        comparisonCapped: false,
      ),
    );
  }

  /// A relative [kind] across every property in [todayByUnit], each under its own business
  /// date. Resolves only when every property agrees on **both** ranges (D-254).
  static DashboardPairOutcome forUnits(
    DashboardPeriodKind kind,
    Map<String, BusinessDate> todayByUnit, {
    Set<String> unitsWithoutCalendar = const {},
  }) => pairForUnits(
    todayByUnit,
    unitsWithoutCalendar: unitsWithoutCalendar,
    pairFor: (_, today) =>
        (forToday(kind, today) as DashboardPairResolved).pair,
  );

  /// The agreement check itself, over any per-property pairing.
  ///
  /// The two sides are checked **independently**. For every relative kind the comparator is
  /// a function of the current range's end, so agreeing current ranges imply agreeing
  /// comparators today; the check does not rely on that, so a future pairing rule that
  /// breaks the implication is refused rather than silently resolved.
  static DashboardPairOutcome pairForUnits(
    Map<String, BusinessDate> todayByUnit, {
    required DashboardPeriodPair Function(String unit, BusinessDate today)
    pairFor,
    Set<String> unitsWithoutCalendar = const {},
  }) {
    if (unitsWithoutCalendar.isNotEmpty || todayByUnit.isEmpty) {
      return DashboardPairRejected(
        DashboardPairRefusal.calendarUnavailable,
        unitsWithoutCalendar: Set.unmodifiable(unitsWithoutCalendar),
      );
    }

    final units = todayByUnit.keys.toList()..sort();
    final pairs = {for (final u in units) u: pairFor(u, todayByUnit[u]!)};
    final currentByUnit = {for (final u in units) u: pairs[u]!.current};
    final comparisonByUnit = {for (final u in units) u: pairs[u]!.comparison};

    final first = pairs[units.first]!;
    if (currentByUnit.values.any((r) => r != first.current)) {
      return DashboardPairRejected(
        DashboardPairRefusal.currentRangesDiffer,
        currentByUnit: Map.unmodifiable(currentByUnit),
        comparisonByUnit: Map.unmodifiable(comparisonByUnit),
      );
    }
    if (comparisonByUnit.values.any((r) => r != first.comparison)) {
      return DashboardPairRejected(
        DashboardPairRefusal.comparisonRangesDiffer,
        currentByUnit: Map.unmodifiable(currentByUnit),
        comparisonByUnit: Map.unmodifiable(comparisonByUnit),
      );
    }
    return DashboardPairResolved(first);
  }

  static DashboardPeriodPair _weekToDate(BusinessDate today) {
    final monday = today.addDays(1 - weekdayOf(today));
    return DashboardPeriodPair._(
      kind: DashboardPeriodKind.weekToDate,
      current: _range(monday, today),
      comparison: _range(monday.addDays(-7), today.addDays(-7)),
      comparisonCapped: false,
    );
  }

  static DashboardPeriodPair _monthToDate(BusinessDate today) {
    final first = BusinessDate.of(today.year, today.month, 1);
    final previousEnd = first.addDays(-1);
    final previousFirst = BusinessDate.of(
      previousEnd.year,
      previousEnd.month,
      1,
    );
    final capped = today.day > previousEnd.day;
    return DashboardPeriodPair._(
      kind: DashboardPeriodKind.monthToDate,
      current: _range(first, today),
      comparison: _range(
        previousFirst,
        capped ? previousEnd : previousFirst.addDays(today.day - 1),
      ),
      comparisonCapped: capped,
    );
  }

  static DashboardPeriodPair _financialYearToDate(BusinessDate today) {
    final year = FinancialYear.of(today);
    // The same calendar date one year earlier. Only 29 February can be missing, and it
    // caps to 28 February rather than rolling into March.
    final leapDay = today.month == 2 && today.day == 29;
    final equivalent = leapDay
        ? BusinessDate.of(today.year - 1, 2, 28)
        : BusinessDate.of(today.year - 1, today.month, today.day);
    return DashboardPeriodPair._(
      kind: DashboardPeriodKind.financialYearToDate,
      current: _range(year.startsOn, today),
      comparison: _range(year.previous.startsOn, equivalent),
      comparisonCapped: leapDay,
    );
  }

  /// A range built through the one validated constructor there is.
  static ReportRange _range(BusinessDate from, BusinessDate to) =>
      switch (CustomRangePeriod(from: from, to: to).resolve()) {
        ReportRangeResolved(:final range) => range,
        ReportRangeRejected() => throw StateError(
          'a dashboard range ended before it began: $from .. $to',
        ),
      };
}
