/// Relative report presets, resolved independently for every property (Phase 5 Slice 8).
///
/// Spec §10 names Today, Yesterday, This Week, Last Week, This Month, Last Month and
/// Financial Year. Each is relative to a **business date**, and a business date belongs to a
/// property: it is derived under that property's IANA timezone and cut-off (D-019, D-067).
/// Two properties can therefore be on different trading days at the same instant.
///
/// ## The ruling this file implements
///
/// A relative preset is resolved **independently under each included property's own
/// business date**. For a single property that is simply its own date. For a consolidated
/// report the preset is usable only when every property resolves to exactly the same
/// inclusive range; otherwise it is refused and the reader is sent to Custom, whose explicit
/// P&L dates need nobody's calendar.
///
/// No property is the master calendar, and this file consults **no clock at all** — not the
/// device, not UTC, not a database's `current_date`. It is handed each property's business
/// date and answers from those.
library;

import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

/// A period named relative to a business date.
enum RelativePreset {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This Week'),
  lastWeek('Last Week'),
  thisMonth('This Month'),
  lastMonth('Last Month'),
  financialYear('Financial Year');

  const RelativePreset(this.label);

  final String label;

  /// The period this preset names, for a property whose current business date is [date].
  ReportingPeriod periodFor(BusinessDate date) => switch (this) {
    RelativePreset.today => SingleDayPeriod(date),
    RelativePreset.yesterday => SingleDayPeriod(date.addDays(-1)),
    RelativePreset.thisWeek => WeekPeriod(date),
    RelativePreset.lastWeek => WeekPeriod(date.addDays(-7)),
    RelativePreset.thisMonth => MonthPeriod.of(date),
    // The day before the first of this month is always in last month.
    RelativePreset.lastMonth => MonthPeriod.of(
      BusinessDate.of(date.year, date.month, 1).addDays(-1),
    ),
    RelativePreset.financialYear => FinancialYearPeriod.of(date),
  };
}

/// What resolving a preset across a report's properties produced.
sealed class PresetResolution {
  const PresetResolution();
}

/// Every property resolved to the same range, so the preset describes one period.
final class PresetResolved extends PresetResolution {
  const PresetResolved({required this.period, required this.range});

  /// The period as the first property (in id order) named it. Every other property named a
  /// period with the identical range, which is the only thing a report reads.
  final ReportingPeriod period;
  final ReportRange range;
}

/// The properties disagree about what the preset means today. Refused, never resolved to
/// any one of them.
final class PresetRangesDiffer extends PresetResolution {
  const PresetRangesDiffer(this.rangeByUnit);
  final Map<String, ReportRange> rangeByUnit;
}

/// A property's business-date rules are not known on this device, or there is no property.
///
/// Refused rather than defaulted: assuming `Asia/Kolkata` and 05:00 for a property whose
/// configuration is absent would be inventing the business fact that decides the date.
final class PresetCalendarUnavailable extends PresetResolution {
  const PresetCalendarUnavailable(this.unitIds);
  final Set<String> unitIds;
}

/// Resolves [preset] for every property in [todayByUnit], each under its own business date.
///
/// [unitsWithoutCalendar] names properties in the report whose business date could not be
/// derived. Any such property refuses the whole resolution.
PresetResolution resolvePresetForUnits(
  RelativePreset preset,
  Map<String, BusinessDate> todayByUnit, {
  Set<String> unitsWithoutCalendar = const {},
}) {
  if (unitsWithoutCalendar.isNotEmpty || todayByUnit.isEmpty) {
    return PresetCalendarUnavailable(Set.unmodifiable(unitsWithoutCalendar));
  }

  final units = todayByUnit.keys.toList()..sort();
  final periods = <String, ReportingPeriod>{};
  final ranges = <String, ReportRange>{};
  for (final unit in units) {
    final period = preset.periodFor(todayByUnit[unit]!);
    periods[unit] = period;
    // Every relative preset resolves; only a custom range can be rejected.
    ranges[unit] = (period.resolve() as ReportRangeResolved).range;
  }

  final first = ranges[units.first]!;
  if (ranges.values.any((range) => range != first)) {
    return PresetRangesDiffer(Map.unmodifiable(ranges));
  }
  return PresetResolved(period: periods[units.first]!, range: first);
}
