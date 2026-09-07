/// Report period normalisation (Phase 5 Slice 2).
///
/// Every period a manager can ask for becomes one inclusive range of P&L dates, so the
/// local and remote engines consume one boundary contract rather than five (D-020).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:timezone/data/latest.dart' as tzdata;

ReportRange _resolve(ReportingPeriod period) =>
    (period.resolve() as ReportRangeResolved).range;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('a single day', () {
    test('is a range of one day, both ends the same', () {
      final range = _resolve(SingleDayPeriod(BusinessDate.of(2026, 6, 15)));
      expect(range.from, BusinessDate.of(2026, 6, 15));
      expect(range.to, BusinessDate.of(2026, 6, 15));
      expect(range.days, 1);
      expect(range.contains(BusinessDate.of(2026, 6, 15)), isTrue);
      expect(range.contains(BusinessDate.of(2026, 6, 14)), isFalse);
    });
  });

  // ── D-165 · the week is Monday to Sunday, on the business date ────────────
  group('the reporting week runs Monday to Sunday (D-165)', () {
    // 2026-06-15 is a Monday. 2026-06-21 is the Sunday that closes the same week.
    final monday = BusinessDate.of(2026, 6, 15);
    final sunday = BusinessDate.of(2026, 6, 21);
    final nextMonday = BusinessDate.of(2026, 6, 22);

    test('the calendar anchors are what this test assumes them to be', () {
      expect(weekdayOf(monday), DateTime.monday);
      expect(weekdayOf(sunday), DateTime.sunday);
      expect(weekdayOf(nextMonday), DateTime.monday);
    });

    test('a Monday starts its own week', () {
      final range = _resolve(WeekPeriod(monday));
      expect(range.from, monday);
      expect(range.to, sunday);
      expect(range.days, 7);
    });

    test('a Sunday ends the same week, and does not start a new one', () {
      final range = _resolve(WeekPeriod(sunday));
      expect(range.from, monday);
      expect(range.to, sunday);
    });

    test('the Monday immediately after that Sunday is the next week', () {
      final range = _resolve(WeekPeriod(nextMonday));
      expect(range.from, nextMonday);
      expect(range.to, BusinessDate.of(2026, 6, 28));
      expect(
        range.from > sunday,
        isTrue,
        reason: 'consecutive days, different reporting weeks',
      );
    });

    test('every day of one week resolves to the same range', () {
      final expected = _resolve(WeekPeriod(monday));
      for (var i = 0; i < 7; i++) {
        expect(_resolve(WeekPeriod(monday.addDays(i))), expected);
      }
    });

    test('a week may span a month boundary, and does', () {
      // 2026-06-29 is a Monday; the week closes on 2026-07-05.
      final range = _resolve(WeekPeriod(BusinessDate.of(2026, 6, 29)));
      expect(range.from, BusinessDate.of(2026, 6, 29));
      expect(range.to, BusinessDate.of(2026, 7, 5));
      expect(range.days, 7);
    });

    test('a week may span a year boundary', () {
      // 2026-12-28 is a Monday; the week closes on 2027-01-03.
      final range = _resolve(WeekPeriod(BusinessDate.of(2026, 12, 31)));
      expect(range.from, BusinessDate.of(2026, 12, 28));
      expect(range.to, BusinessDate.of(2027, 1, 3));
    });

    test('the week is derived from the business date, never from a timestamp', () {
      // The property's cut-off already decided this. A sale rung up at 01:00 on Monday
      // 22 June carries a business date of Sunday 21 June (D-019, D-067), so it belongs
      // to the week that is closing — and this file only ever sees the business date, so
      // it cannot get that wrong.
      final lateNightSale = BusinessDate.fromInstant(
        DateTime.utc(2026, 6, 21, 19, 30), // 01:00 IST on Monday 22 June
        timeZoneId: 'Asia/Kolkata',
      );
      expect(lateNightSale, sunday);
      expect(_resolve(WeekPeriod(lateNightSale)).to, sunday);
    });
  });

  group('a month', () {
    test('runs from the first to the last day', () {
      final range = _resolve(MonthPeriod(2026, 6));
      expect(range.from, BusinessDate.of(2026, 6, 1));
      expect(range.to, BusinessDate.of(2026, 6, 30));
      expect(range.days, 30);
    });

    test('December rolls into the next year correctly', () {
      final range = _resolve(MonthPeriod(2026, 12));
      expect(range.from, BusinessDate.of(2026, 12, 1));
      expect(range.to, BusinessDate.of(2026, 12, 31));
      expect(range.days, 31);
    });

    test('February knows about leap years', () {
      expect(_resolve(MonthPeriod(2026, 2)).to, BusinessDate.of(2026, 2, 28));
      expect(_resolve(MonthPeriod(2028, 2)).to, BusinessDate.of(2028, 2, 29));
      expect(_resolve(MonthPeriod(2028, 2)).days, 29);
    });

    test('its period key is the one both projections already store', () {
      expect(MonthPeriod(2026, 6).periodKey, '2026-06');
      expect(MonthPeriod(2026, 12).periodKey, '2026-12');
      expect(
        MonthPeriod.of(BusinessDate.of(2026, 6, 15)).periodKey,
        BusinessDate.of(2026, 6, 15).periodKey,
        reason: 'one period vocabulary, not a second one for reports',
      );
    });
  });

  // ── §15 · the established financial year, reused ──────────────────────────
  group('the financial year is the projects own, not a new one', () {
    test('1 April to 31 March, named by its opening year', () {
      final range = _resolve(FinancialYearPeriod(const FinancialYear(2026)));
      expect(range.from, BusinessDate.of(2026, 4, 1));
      expect(range.to, BusinessDate.of(2027, 3, 31));
    });

    test('the last day of one FY belongs to the old year', () {
      final lastDay = BusinessDate.of(2027, 3, 31);
      expect(FinancialYear.of(lastDay), const FinancialYear(2026));
      expect(_resolve(FinancialYearPeriod.of(lastDay)).to, lastDay);
      expect(
        _resolve(FinancialYearPeriod.of(lastDay)).from,
        BusinessDate.of(2026, 4, 1),
      );
    });

    test('the first day of the next FY belongs to the new year', () {
      final firstDay = BusinessDate.of(2027, 4, 1);
      expect(FinancialYear.of(firstDay), const FinancialYear(2027));
      expect(_resolve(FinancialYearPeriod.of(firstDay)).from, firstDay);
      expect(
        _resolve(FinancialYearPeriod.of(firstDay)).to,
        BusinessDate.of(2028, 3, 31),
      );
    });

    test('consecutive days across the boundary are different years', () {
      final closing = FinancialYearPeriod.of(BusinessDate.of(2027, 3, 31));
      final opening = FinancialYearPeriod.of(BusinessDate.of(2027, 4, 1));
      expect(closing.financialYear, isNot(opening.financialYear));
      expect(closing.financialYear.next, opening.financialYear);
      expect(closing.financialYear.label, '26-27');
      expect(opening.financialYear.label, '27-28');
    });

    test('it is the same semantics KI-EXP and KI-REV numbering rely on', () {
      // FinancialYear is imported from expense_number.dart rather than restated. The
      // label it produces is the one printed on every document number, and it agrees
      // with app.financial_year_of and app.revenue_financial_year on the server.
      expect(FinancialYear.of(BusinessDate.of(2026, 6, 15)).label, '26-27');
      expect(FinancialYear.of(BusinessDate.of(2027, 2, 10)).label, '26-27');
      expect(FinancialYear.of(BusinessDate.of(2026, 3, 31)).label, '25-26');
    });
  });

  group('a custom range', () {
    test('same-day start and end is valid', () {
      final outcome = CustomRangePeriod(
        from: BusinessDate.of(2026, 6, 15),
        to: BusinessDate.of(2026, 6, 15),
      ).resolve();
      expect(outcome, isA<ReportRangeResolved>());
      expect((outcome as ReportRangeResolved).range.days, 1);
    });

    test('an ordinary range keeps both ends inclusive', () {
      final range = _resolve(
        CustomRangePeriod(
          from: BusinessDate.of(2026, 6, 1),
          to: BusinessDate.of(2026, 6, 15),
        ),
      );
      expect(range.days, 15);
      expect(range.contains(BusinessDate.of(2026, 6, 1)), isTrue);
      expect(range.contains(BusinessDate.of(2026, 6, 15)), isTrue);
      expect(range.contains(BusinessDate.of(2026, 6, 16)), isFalse);
    });

    test('end before start is rejected, and not silently swapped', () {
      final outcome = CustomRangePeriod(
        from: BusinessDate.of(2026, 6, 30),
        to: BusinessDate.of(2026, 6, 1),
      ).resolve();

      expect(outcome, isA<ReportRangeRejected>());
      expect(
        (outcome as ReportRangeRejected).problem,
        ReportRangeProblem.endBeforeStart,
        reason:
            'guessing which end was meant is how a report quietly covers a different '
            'period from the one on screen',
      );
    });

    test('a rejected range yields no ReportRange at all', () {
      // The type is the guard: there is no public constructor, so a caller cannot build
      // an invalid range and forget to check it.
      final outcome = CustomRangePeriod(
        from: BusinessDate.of(2026, 6, 30),
        to: BusinessDate.of(2026, 6, 1),
      ).resolve();
      expect(outcome, isNot(isA<ReportRangeResolved>()));
    });
  });

  group('ranges compare by value', () {
    test('two resolutions of the same period are equal', () {
      expect(_resolve(MonthPeriod(2026, 6)), _resolve(MonthPeriod(2026, 6)));
      expect(
        _resolve(MonthPeriod(2026, 6)).hashCode,
        _resolve(MonthPeriod(2026, 6)).hashCode,
      );
    });

    test('a month and a custom range covering it are the same range', () {
      expect(
        _resolve(MonthPeriod(2026, 6)),
        _resolve(
          CustomRangePeriod(
            from: BusinessDate.of(2026, 6, 1),
            to: BusinessDate.of(2026, 6, 30),
          ),
        ),
        reason:
            'one normalised contract: how the period was chosen does not change what it '
            'covers, so an engine needs one query shape rather than five',
      );
    });
  });
}
