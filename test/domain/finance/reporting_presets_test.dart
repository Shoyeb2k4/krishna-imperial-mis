/// Relative report presets, resolved per property (Phase 5 Slice 8).
///
/// The project lead's ruling: a relative preset is resolved **independently under each
/// included property's own business date**, and a consolidated report may use it only when
/// every property resolves to exactly the same inclusive range. Otherwise the preset is
/// refused and the reader is sent to Custom. No property is the master calendar, and no
/// device, UTC or database calendar date is consulted — this file never reads a clock.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_presets.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

ReportRange _range(ReportingPeriod period) =>
    (period.resolve() as ReportRangeResolved).range;

void main() {
  // Sunday 20 September 2026. Monday is the 14th, so This Week is 14–20 Sept.
  final today = BusinessDate.of(2026, 9, 20);

  group('each preset, for one trading day', () {
    test('Today is that single business date', () {
      final r = _range(RelativePreset.today.periodFor(today));
      expect(r.from, today);
      expect(r.to, today);
    });

    test('Yesterday is the business date before it', () {
      final r = _range(RelativePreset.yesterday.periodFor(today));
      expect(r.from, BusinessDate.of(2026, 9, 19));
      expect(r.to, BusinessDate.of(2026, 9, 19));
    });

    test(
      'This Week is Monday to Sunday, containing the business date (D-165)',
      () {
        final r = _range(RelativePreset.thisWeek.periodFor(today));
        expect(r.from, BusinessDate.of(2026, 9, 14));
        expect(r.to, BusinessDate.of(2026, 9, 20));
      },
    );

    test('Last Week is the Monday-to-Sunday week before it', () {
      final r = _range(RelativePreset.lastWeek.periodFor(today));
      expect(r.from, BusinessDate.of(2026, 9, 7));
      expect(r.to, BusinessDate.of(2026, 9, 13));
    });

    test('This Month is the calendar month', () {
      final r = _range(RelativePreset.thisMonth.periodFor(today));
      expect(r.from, BusinessDate.of(2026, 9, 1));
      expect(r.to, BusinessDate.of(2026, 9, 30));
    });

    test('Last Month crosses a year boundary correctly', () {
      final r = _range(
        RelativePreset.lastMonth.periodFor(BusinessDate.of(2027, 1, 3)),
      );
      expect(r.from, BusinessDate.of(2026, 12, 1));
      expect(r.to, BusinessDate.of(2026, 12, 31));
    });

    test('Financial Year is the Indian financial year containing it', () {
      final march = _range(
        RelativePreset.financialYear.periodFor(BusinessDate.of(2027, 3, 31)),
      );
      expect(march.from, BusinessDate.of(2026, 4, 1));
      expect(march.to, BusinessDate.of(2027, 3, 31));

      final april = _range(
        RelativePreset.financialYear.periodFor(BusinessDate.of(2027, 4, 1)),
      );
      expect(april.from, BusinessDate.of(2027, 4, 1));
      expect(april.to, BusinessDate.of(2028, 3, 31));
    });
  });

  group('resolving a preset across the properties in a report', () {
    test('one property uses its own business date', () {
      final outcome = resolvePresetForUnits(RelativePreset.today, {
        'ccr': BusinessDate.of(2026, 9, 19),
      });
      expect(outcome, isA<PresetResolved>());
      final range = (outcome as PresetResolved).range;
      expect(range.from, BusinessDate.of(2026, 9, 19));
      expect(range.to, BusinessDate.of(2026, 9, 19));
    });

    test('two properties on the same business date resolve to one range', () {
      final outcome = resolvePresetForUnits(RelativePreset.thisWeek, {
        'ccr': today,
        'hki': today,
      });
      expect(outcome, isA<PresetResolved>());
      expect((outcome as PresetResolved).range, _range(WeekPeriod(today)));
    });

    test('different business dates that still give the same range are allowed', () {
      // One property has passed its cut-off into the 20th, the other is still on the
      // 19th. Both are in the same week and the same month, so those presets agree.
      final dates = {
        'ccr': BusinessDate.of(2026, 9, 19),
        'hki': BusinessDate.of(2026, 9, 20),
      };
      expect(
        resolvePresetForUnits(RelativePreset.thisWeek, dates),
        isA<PresetResolved>(),
      );
      expect(
        resolvePresetForUnits(RelativePreset.thisMonth, dates),
        isA<PresetResolved>(),
      );
    });

    test('different ranges are refused, never resolved to one property', () {
      final dates = {
        'ccr': BusinessDate.of(2026, 9, 19),
        'hki': BusinessDate.of(2026, 9, 20),
      };
      final outcome = resolvePresetForUnits(RelativePreset.today, dates);
      expect(outcome, isA<PresetRangesDiffer>());
      final differ = outcome as PresetRangesDiffer;
      expect(differ.rangeByUnit['ccr']!.from, BusinessDate.of(2026, 9, 19));
      expect(differ.rangeByUnit['hki']!.from, BusinessDate.of(2026, 9, 20));
    });

    test('a month boundary between the properties refuses This Month', () {
      final outcome = resolvePresetForUnits(RelativePreset.thisMonth, {
        'ccr': BusinessDate.of(2026, 9, 30),
        'hki': BusinessDate.of(2026, 10, 1),
      });
      expect(outcome, isA<PresetRangesDiffer>());
    });

    test('a financial-year boundary between them refuses Financial Year', () {
      final outcome = resolvePresetForUnits(RelativePreset.financialYear, {
        'ccr': BusinessDate.of(2027, 3, 31),
        'hki': BusinessDate.of(2027, 4, 1),
      });
      expect(outcome, isA<PresetRangesDiffer>());
    });

    test('the refusal does not depend on which property is listed first', () {
      final a = resolvePresetForUnits(RelativePreset.yesterday, {
        'ccr': BusinessDate.of(2026, 9, 19),
        'hki': BusinessDate.of(2026, 9, 20),
      });
      final b = resolvePresetForUnits(RelativePreset.yesterday, {
        'hki': BusinessDate.of(2026, 9, 20),
        'ccr': BusinessDate.of(2026, 9, 19),
      });
      expect(a, isA<PresetRangesDiffer>());
      expect(b, isA<PresetRangesDiffer>());
    });

    test('a property whose business-date rules are unknown refuses', () {
      final outcome = resolvePresetForUnits(
        RelativePreset.today,
        {'ccr': today},
        unitsWithoutCalendar: const {'hki'},
      );
      expect(outcome, isA<PresetCalendarUnavailable>());
      expect((outcome as PresetCalendarUnavailable).unitIds, {'hki'});
    });

    test('no property at all refuses rather than inventing a date', () {
      expect(
        resolvePresetForUnits(RelativePreset.today, const {}),
        isA<PresetCalendarUnavailable>(),
      );
    });
  });

  test('every preset has a label and none says "custom"', () {
    for (final preset in RelativePreset.values) {
      expect(preset.label, isNotEmpty);
      expect(preset.label.toLowerCase(), isNot(contains('custom')));
    }
  });
}
