/// Dashboard periods and their comparators (Phase 6 Slice 2, D-251, D-252, D-254).
///
/// The project lead's rulings, asserted rather than described:
///
/// * a dashboard period in progress ends at the current business date — Today so far, Week
///   to date, Month to date, Financial year to date (D-252);
/// * it is compared with the **same stretch** of the previous period, never the whole of
///   it, and a shorter previous month or a missing 29 February caps the comparator and
///   says so (D-251);
/// * a custom range is compared with the immediately preceding range of equal length;
/// * a consolidated dashboard needs every property to agree on **both** ranges (D-254).
///
/// No clock and no timestamp appears anywhere in this file: every range is derived from a
/// business date the caller already holds.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/finance/dashboard_periods.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

BusinessDate _d(int y, int m, int d) => BusinessDate.of(y, m, d);

DashboardPeriodPair _pair(DashboardPeriodKind kind, BusinessDate today) {
  final outcome = DashboardPeriods.forToday(kind, today);
  expect(outcome, isA<DashboardPairResolved>(), reason: '$kind on $today');
  return (outcome as DashboardPairResolved).pair;
}

void _expectRange(ReportRange range, BusinessDate from, BusinessDate to) {
  expect(range.from, from, reason: 'from of $range');
  expect(range.to, to, reason: 'to of $range');
}

void main() {
  group('labels say the period is not finished (additional rule)', () {
    test('each relative kind names itself as "so far" or "to date"', () {
      expect(DashboardPeriodKind.today.label, 'Today so far');
      expect(DashboardPeriodKind.weekToDate.label, 'Week to date');
      expect(DashboardPeriodKind.monthToDate.label, 'Month to date');
      expect(
        DashboardPeriodKind.financialYearToDate.label,
        'Financial year to date',
      );
      expect(DashboardPeriodKind.custom.label, 'Custom');
    });

    test('custom has no relative resolution — it needs two dates', () {
      expect(
        () => DashboardPeriods.forToday(
          DashboardPeriodKind.custom,
          _d(2026, 9, 17),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Today so far vs the previous business date', () {
    test('a single day against the day before', () {
      final pair = _pair(DashboardPeriodKind.today, _d(2026, 9, 17));
      _expectRange(pair.current, _d(2026, 9, 17), _d(2026, 9, 17));
      _expectRange(pair.comparison, _d(2026, 9, 16), _d(2026, 9, 16));
      expect(pair.comparisonCapped, isFalse);
    });

    test('across a month and a financial-year boundary', () {
      final pair = _pair(DashboardPeriodKind.today, _d(2026, 4, 1));
      _expectRange(pair.comparison, _d(2026, 3, 31), _d(2026, 3, 31));
    });
  });

  group('Week to date vs the same weekdays of last week (D-165)', () {
    test('Thursday: Monday to Thursday, against last Monday to Thursday', () {
      // Thursday 17 September 2026. Monday is the 14th.
      final pair = _pair(DashboardPeriodKind.weekToDate, _d(2026, 9, 17));
      _expectRange(pair.current, _d(2026, 9, 14), _d(2026, 9, 17));
      _expectRange(pair.comparison, _d(2026, 9, 7), _d(2026, 9, 10));
      expect(pair.current.days, pair.comparison.days);
    });

    test('Monday is one day against last Monday', () {
      final pair = _pair(DashboardPeriodKind.weekToDate, _d(2026, 9, 14));
      _expectRange(pair.current, _d(2026, 9, 14), _d(2026, 9, 14));
      _expectRange(pair.comparison, _d(2026, 9, 7), _d(2026, 9, 7));
    });

    test('Sunday is the whole week against the whole of last week', () {
      final pair = _pair(DashboardPeriodKind.weekToDate, _d(2026, 9, 20));
      _expectRange(pair.current, _d(2026, 9, 14), _d(2026, 9, 20));
      _expectRange(pair.comparison, _d(2026, 9, 7), _d(2026, 9, 13));
    });

    test('a week that straddles a month keeps its Monday', () {
      // Wednesday 2 September 2026 — its Monday is 31 August.
      final pair = _pair(DashboardPeriodKind.weekToDate, _d(2026, 9, 2));
      _expectRange(pair.current, _d(2026, 8, 31), _d(2026, 9, 2));
      _expectRange(pair.comparison, _d(2026, 8, 24), _d(2026, 8, 26));
    });
  });

  group('Month to date vs the same ordinal days of last month', () {
    test('17 September against 1–17 August', () {
      final pair = _pair(DashboardPeriodKind.monthToDate, _d(2026, 9, 17));
      _expectRange(pair.current, _d(2026, 9, 1), _d(2026, 9, 17));
      _expectRange(pair.comparison, _d(2026, 8, 1), _d(2026, 8, 17));
      expect(pair.comparisonCapped, isFalse);
    });

    test('31 March against February, capped at 28 February', () {
      final pair = _pair(DashboardPeriodKind.monthToDate, _d(2027, 3, 31));
      _expectRange(pair.current, _d(2027, 3, 1), _d(2027, 3, 31));
      _expectRange(pair.comparison, _d(2027, 2, 1), _d(2027, 2, 28));
      expect(pair.comparisonCapped, isTrue);
      expect(pair.current.days, 31);
      expect(pair.comparison.days, 28);
    });

    test('30 March in a leap year is capped at 29 February', () {
      final pair = _pair(DashboardPeriodKind.monthToDate, _d(2028, 3, 30));
      _expectRange(pair.comparison, _d(2028, 2, 1), _d(2028, 2, 29));
      expect(pair.comparisonCapped, isTrue);
    });

    test('29 March in a leap year is exact, not capped', () {
      final pair = _pair(DashboardPeriodKind.monthToDate, _d(2028, 3, 29));
      _expectRange(pair.comparison, _d(2028, 2, 1), _d(2028, 2, 29));
      expect(pair.comparisonCapped, isFalse);
    });

    test('31 July against 1–30 June, capped', () {
      final pair = _pair(DashboardPeriodKind.monthToDate, _d(2026, 7, 31));
      _expectRange(pair.comparison, _d(2026, 6, 1), _d(2026, 6, 30));
      expect(pair.comparisonCapped, isTrue);
    });

    test('January compares with December of the previous year', () {
      final pair = _pair(DashboardPeriodKind.monthToDate, _d(2027, 1, 10));
      _expectRange(pair.current, _d(2027, 1, 1), _d(2027, 1, 10));
      _expectRange(pair.comparison, _d(2026, 12, 1), _d(2026, 12, 10));
    });

    test('the first of the month is one day against the first of last', () {
      final pair = _pair(DashboardPeriodKind.monthToDate, _d(2026, 9, 1));
      _expectRange(pair.current, _d(2026, 9, 1), _d(2026, 9, 1));
      _expectRange(pair.comparison, _d(2026, 8, 1), _d(2026, 8, 1));
    });
  });

  group('Financial year to date vs the same stretch of last FY', () {
    test('17 September 2026 against 1 April – 17 September 2025', () {
      final pair = _pair(
        DashboardPeriodKind.financialYearToDate,
        _d(2026, 9, 17),
      );
      _expectRange(pair.current, _d(2026, 4, 1), _d(2026, 9, 17));
      _expectRange(pair.comparison, _d(2025, 4, 1), _d(2025, 9, 17));
      expect(pair.comparisonCapped, isFalse);
    });

    test('a date in January belongs to the FY that opened last April', () {
      final pair = _pair(
        DashboardPeriodKind.financialYearToDate,
        _d(2027, 1, 15),
      );
      _expectRange(pair.current, _d(2026, 4, 1), _d(2027, 1, 15));
      _expectRange(pair.comparison, _d(2025, 4, 1), _d(2026, 1, 15));
    });

    test('1 April is the first day against last 1 April', () {
      final pair = _pair(
        DashboardPeriodKind.financialYearToDate,
        _d(2026, 4, 1),
      );
      _expectRange(pair.current, _d(2026, 4, 1), _d(2026, 4, 1));
      _expectRange(pair.comparison, _d(2025, 4, 1), _d(2025, 4, 1));
    });

    test('31 March is the whole FY against the whole previous FY', () {
      final pair = _pair(
        DashboardPeriodKind.financialYearToDate,
        _d(2027, 3, 31),
      );
      _expectRange(pair.current, _d(2026, 4, 1), _d(2027, 3, 31));
      _expectRange(pair.comparison, _d(2025, 4, 1), _d(2026, 3, 31));
    });

    test('29 February 2028 is capped at 28 February 2027', () {
      final pair = _pair(
        DashboardPeriodKind.financialYearToDate,
        _d(2028, 2, 29),
      );
      _expectRange(pair.current, _d(2027, 4, 1), _d(2028, 2, 29));
      _expectRange(pair.comparison, _d(2026, 4, 1), _d(2027, 2, 28));
      expect(pair.comparisonCapped, isTrue);
    });

    test('28 February 2029 compares with 28 February 2028, not capped', () {
      final pair = _pair(
        DashboardPeriodKind.financialYearToDate,
        _d(2029, 2, 28),
      );
      _expectRange(pair.comparison, _d(2027, 4, 1), _d(2028, 2, 28));
      expect(pair.comparisonCapped, isFalse);
      expect(pair.current.days, 334);
      expect(pair.comparison.days, 334);
    });

    test('1 March 2028 compares with 1 March 2027: the current side holds the '
        'leap day, so it is one day longer, and the pair says so', () {
      final pair = _pair(
        DashboardPeriodKind.financialYearToDate,
        _d(2028, 3, 1),
      );
      _expectRange(pair.comparison, _d(2026, 4, 1), _d(2027, 3, 1));
      expect(pair.comparisonCapped, isFalse);
      expect(pair.current.days, 336);
      expect(pair.comparison.days, 335);
    });

    test(
      '1 March 2029 compares with 1 March 2028: now the comparator holds the '
      'leap day and is the longer side',
      () {
        final pair = _pair(
          DashboardPeriodKind.financialYearToDate,
          _d(2029, 3, 1),
        );
        _expectRange(pair.comparison, _d(2027, 4, 1), _d(2028, 3, 1));
        expect(pair.comparisonCapped, isFalse);
        expect(pair.current.days, 335);
        expect(pair.comparison.days, 336);
      },
    );
  });

  group('Custom vs the immediately preceding range of equal length', () {
    test('10–17 September (8 days) against 2–9 September', () {
      final outcome = DashboardPeriods.forCustom(
        from: _d(2026, 9, 10),
        to: _d(2026, 9, 17),
      );
      final pair = (outcome as DashboardPairResolved).pair;
      _expectRange(pair.current, _d(2026, 9, 10), _d(2026, 9, 17));
      _expectRange(pair.comparison, _d(2026, 9, 2), _d(2026, 9, 9));
      expect(pair.current.days, 8);
      expect(pair.comparison.days, 8);
      expect(pair.comparisonCapped, isFalse);
    });

    test('a single custom day compares with the day before', () {
      final pair =
          (DashboardPeriods.forCustom(from: _d(2026, 3, 1), to: _d(2026, 3, 1))
                  as DashboardPairResolved)
              .pair;
      _expectRange(pair.comparison, _d(2026, 2, 28), _d(2026, 2, 28));
    });

    test('a range crossing a leap day keeps an equal day count', () {
      final pair =
          (DashboardPeriods.forCustom(from: _d(2028, 3, 1), to: _d(2028, 3, 31))
                  as DashboardPairResolved)
              .pair;
      _expectRange(pair.comparison, _d(2028, 1, 30), _d(2028, 2, 29));
      expect(pair.comparison.days, 31);
    });

    test('a reversed custom range is refused, never swapped', () {
      final outcome = DashboardPeriods.forCustom(
        from: _d(2026, 9, 17),
        to: _d(2026, 9, 10),
      );
      expect(outcome, isA<DashboardPairRejected>());
      expect(
        (outcome as DashboardPairRejected).reason,
        DashboardPairRefusal.endBeforeStart,
      );
    });
  });

  group('invariants over every day of four years', () {
    test('comparators end before the current range starts, and never '
        'exceed the current range in length except for leap FYTD', () {
      var day = _d(2026, 1, 1);
      final end = _d(2029, 12, 31);
      while (day <= end) {
        for (final kind in const [
          DashboardPeriodKind.today,
          DashboardPeriodKind.weekToDate,
          DashboardPeriodKind.monthToDate,
          DashboardPeriodKind.financialYearToDate,
        ]) {
          final pair = _pair(kind, day);
          expect(pair.current.to, day, reason: '$kind ends at today');
          expect(pair.comparison.to < pair.current.from, isTrue);
          if (kind == DashboardPeriodKind.financialYearToDate) {
            expect(
              pair.comparisonCapped,
              day.month == 2 && day.day == 29,
              reason: 'FYTD is capped only on a leap day: $day',
            );
          } else {
            expect(
              pair.comparison.days <= pair.current.days,
              isTrue,
              reason: '$kind on $day',
            );
            expect(
              pair.comparisonCapped,
              pair.comparison.days < pair.current.days,
              reason: 'capped is stated exactly when days differ: $kind $day',
            );
          }
        }
        day = day.addDays(1);
      }
    });
  });

  group('consolidated: both sides must agree across properties (D-254)', () {
    const ccr = 'unit-ccr';
    const hki = 'unit-hki';

    test('the same business date everywhere resolves one pair', () {
      final outcome = DashboardPeriods.forUnits(
        DashboardPeriodKind.monthToDate,
        {ccr: _d(2026, 9, 17), hki: _d(2026, 9, 17)},
      );
      expect(outcome, isA<DashboardPairResolved>());
      final pair = (outcome as DashboardPairResolved).pair;
      _expectRange(pair.current, _d(2026, 9, 1), _d(2026, 9, 17));
    });

    test('properties on different business dates refuse the current side, '
        'and name no master calendar', () {
      final outcome = DashboardPeriods.forUnits(
        DashboardPeriodKind.monthToDate,
        {ccr: _d(2026, 9, 17), hki: _d(2026, 9, 16)},
      );
      expect(outcome, isA<DashboardPairRejected>());
      final rejected = outcome as DashboardPairRejected;
      expect(rejected.reason, DashboardPairRefusal.currentRangesDiffer);
      expect(rejected.currentByUnit.keys, unorderedEquals([ccr, hki]));
    });

    test('the comparison side is checked on its own, independently', () {
      // For relative kinds the comparator is a function of the current end, so agreeing
      // current ranges imply agreeing comparators. The check still runs, through the
      // same entry point, with an injected comparator that disagrees.
      final outcome = DashboardPeriods.pairForUnits(
        {ccr: _d(2026, 9, 17), hki: _d(2026, 9, 17)},
        pairFor: (unit, today) {
          final base = _pair(DashboardPeriodKind.monthToDate, today);
          if (unit == ccr) return base;
          return DashboardPeriodPair.forTesting(
            current: base.current,
            comparison: _pair(
              DashboardPeriodKind.monthToDate,
              today.addDays(-1),
            ).comparison,
            comparisonCapped: false,
          );
        },
      );
      expect(outcome, isA<DashboardPairRejected>());
      expect(
        (outcome as DashboardPairRejected).reason,
        DashboardPairRefusal.comparisonRangesDiffer,
      );
      expect(outcome.comparisonByUnit.keys, unorderedEquals([ccr, hki]));
    });

    test('a property whose calendar is unknown refuses, never defaulted', () {
      final outcome = DashboardPeriods.forUnits(
        DashboardPeriodKind.today,
        {ccr: _d(2026, 9, 17)},
        unitsWithoutCalendar: {hki},
      );
      expect(outcome, isA<DashboardPairRejected>());
      expect(
        (outcome as DashboardPairRejected).reason,
        DashboardPairRefusal.calendarUnavailable,
      );
    });

    test('no property at all is refused', () {
      final outcome = DashboardPeriods.forUnits(
        DashboardPeriodKind.today,
        const {},
      );
      expect(
        (outcome as DashboardPairRejected).reason,
        DashboardPairRefusal.calendarUnavailable,
      );
    });

    test('custom needs no calendar agreement — its dates are explicit', () {
      final outcome = DashboardPeriods.forCustom(
        from: _d(2026, 9, 1),
        to: _d(2026, 9, 17),
      );
      expect(outcome, isA<DashboardPairResolved>());
    });
  });
}
