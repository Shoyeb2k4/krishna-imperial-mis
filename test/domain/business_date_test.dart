/// The business-day cut-off decides which trading day a late-night sale belongs to.
/// Getting it wrong moves revenue between days — and therefore between months.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const String kolkata = 'Asia/Kolkata';

/// Builds the UTC instant corresponding to a wall-clock time at a property.
DateTime instantAt(String zone, int y, int m, int d, int hour, int minute) {
  final location = tz.getLocation(zone);
  return tz.TZDateTime(location, y, m, d, hour, minute).toUtc();
}

void main() {
  setUpAll(tz_data.initializeTimeZones);

  group('the four boundary cases required by the owner (05:00 cut-off)', () {
    BusinessDate at(int hour, int minute, {int day = 16}) =>
        BusinessDate.fromInstant(
          instantAt(kolkata, 2026, 6, day, hour, minute),
          timeZoneId: kolkata,
        );

    test('04:59 belongs to the previous business date', () {
      expect(at(4, 59).iso, '2026-06-15');
    });

    test('05:00 starts the new business date', () {
      expect(at(5, 0).iso, '2026-06-16');
    });

    test('23:59 is still the same business date', () {
      expect(at(23, 59).iso, '2026-06-16');
    });

    test('00:01 belongs to the previous business date', () {
      expect(at(0, 1).iso, '2026-06-15');
    });
  });

  test(
    'the specification example: 01:00 on 16 June is business date 15 June',
    () {
      final businessDate = BusinessDate.fromInstant(
        instantAt(kolkata, 2026, 6, 16, 1, 0),
        timeZoneId: kolkata,
        cutoff: BusinessDayCutoff.defaultCutoff,
      );
      expect(businessDate.iso, '2026-06-15');
    },
  );

  group('the cut-off is configurable per business unit', () {
    test('midnight cut-off makes business date equal the local date', () {
      final businessDate = BusinessDate.fromInstant(
        instantAt(kolkata, 2026, 6, 16, 1, 0),
        timeZoneId: kolkata,
        cutoff: BusinessDayCutoff.midnight,
      );
      expect(businessDate.iso, '2026-06-16');
    });

    test('a 03:00 cut-off moves the boundary accordingly', () {
      const threeAm = BusinessDayCutoff(hour: 3, minute: 0);
      expect(
        BusinessDate.fromInstant(
          instantAt(kolkata, 2026, 6, 16, 2, 59),
          timeZoneId: kolkata,
          cutoff: threeAm,
        ).iso,
        '2026-06-15',
      );
      expect(
        BusinessDate.fromInstant(
          instantAt(kolkata, 2026, 6, 16, 3, 0),
          timeZoneId: kolkata,
          cutoff: threeAm,
        ).iso,
        '2026-06-16',
      );
    });

    test('parses and renders the stored HH:mm form', () {
      expect(
        BusinessDayCutoff.tryParse('05:00'),
        BusinessDayCutoff.defaultCutoff,
      );
      expect(BusinessDayCutoff.tryParse('23:30')?.minutesFromMidnight, 1410);
      expect(BusinessDayCutoff.defaultCutoff.formatted, '05:00');
      expect(BusinessDayCutoff.tryParse('24:00'), isNull);
      expect(BusinessDayCutoff.tryParse('nonsense'), isNull);
    });
  });

  group('month and year boundaries', () {
    test('01:00 on the 1st belongs to the last day of the previous month', () {
      final businessDate = BusinessDate.fromInstant(
        instantAt(kolkata, 2026, 7, 1, 1, 0),
        timeZoneId: kolkata,
      );
      expect(businessDate.iso, '2026-06-30');
      // This is exactly why the period key must follow the business date and not the
      // raw timestamp: this sale belongs to June's P&L, not July's.
      expect(businessDate.periodKey, '2026-06');
    });

    test('new year rollover', () {
      expect(
        BusinessDate.fromInstant(
          instantAt(kolkata, 2027, 1, 1, 2, 30),
          timeZoneId: kolkata,
        ).iso,
        '2026-12-31',
      );
    });

    test('leap day', () {
      expect(
        BusinessDate.fromInstant(
          instantAt(kolkata, 2028, 3, 1, 4, 0),
          timeZoneId: kolkata,
        ).iso,
        '2028-02-29',
      );
    });
  });

  group('DST safety', () {
    // Asia/Kolkata has no DST, but the architecture must be correct anyway — the rule
    // is written once and a future property could sit anywhere.
    const newYork = 'America/New_York';

    test(
      'the spring-forward morning still resolves to the previous trading day',
      () {
        // 2026-03-08: US clocks jump 02:00 → 03:00. A 01:30 transaction is before the
        // 05:00 cut-off and must land on the 7th.
        expect(
          BusinessDate.fromInstant(
            instantAt(newYork, 2026, 3, 8, 1, 30),
            timeZoneId: newYork,
          ).iso,
          '2026-03-07',
        );
      },
    );

    test('after the spring-forward gap the new trading day has started', () {
      expect(
        BusinessDate.fromInstant(
          instantAt(newYork, 2026, 3, 8, 6, 0),
          timeZoneId: newYork,
        ).iso,
        '2026-03-08',
      );
    });

    test(
      'the autumn fall-back day, where 01:30 happens twice, still lands on the 31st',
      () {
        // 2026-11-01: 02:00 → 01:00. Both 01:30s are before the cut-off, so both belong
        // to the previous trading day. The rule must not depend on which one it saw.
        expect(
          BusinessDate.fromInstant(
            instantAt(newYork, 2026, 11, 1, 1, 30),
            timeZoneId: newYork,
          ).iso,
          '2026-10-31',
        );
      },
    );

    test('a day is stepped by the calendar, not by subtracting 24 hours', () {
      // A naive `instant - 24h` implementation would drift by an hour across a DST
      // change and could report the wrong date. It must not.
      expect(
        BusinessDate.fromInstant(
          instantAt(newYork, 2026, 3, 8, 4, 59),
          timeZoneId: newYork,
        ).iso,
        '2026-03-07',
      );
    });
  });

  group('timezone matters, not just the instant', () {
    test('one instant is a different trading day at two properties', () {
      // 22:00 UTC = 03:30 next day in Kolkata (before cut-off → previous day),
      // and 17:00 same day in New York (after cut-off → same day).
      final instant = DateTime.utc(2026, 6, 15, 22, 0);
      expect(
        BusinessDate.fromInstant(instant, timeZoneId: kolkata).iso,
        '2026-06-15',
      );
      expect(
        BusinessDate.fromInstant(instant, timeZoneId: 'America/New_York').iso,
        '2026-06-15',
      );
    });

    test('neither the device clock nor UTC can change the answer', () {
      // The instant migration 0033 exists for: 23:45 UTC on 15 June is 05:15 on the
      // 16th in Kolkata, which is *after* the 05:00 cut-off. So the property's business
      // date is the 16th while the UTC calendar date is still the 15th.
      //
      // The server used to measure the 7-day edit window with Postgres `current_date`,
      // evaluated in a UTC session, and therefore counted one day fewer than the
      // property had actually lived through — accepting an edit on D+8 as though it
      // were D+7. It now derives the comparison date with exactly the rule below, so
      // the two layers agree at this instant rather than merely near it.
      final instant = DateTime.utc(2026, 6, 15, 23, 45);

      expect(
        instant.toUtc().toIso8601String().substring(0, 10),
        '2026-06-15',
        reason: 'the UTC calendar date',
      );
      expect(
        BusinessDate.fromInstant(instant, timeZoneId: kolkata).iso,
        '2026-06-16',
        reason: 'the property has already begun the 16th',
      );

      // And it is a function of the instant, not of how that instant is expressed.
      // `fromInstant` takes the absolute moment and the *property's* zone; the zone the
      // recording device happens to be set to is not an input and cannot become one.
      expect(
        BusinessDate.fromInstant(instant.toLocal(), timeZoneId: kolkata).iso,
        BusinessDate.fromInstant(instant, timeZoneId: kolkata).iso,
        reason: 'an Android phone and a Windows desktop must agree',
      );
    });
  });

  group('value semantics', () {
    test('parses and rejects the ISO form', () {
      expect(BusinessDate.tryParse('2026-06-15')?.iso, '2026-06-15');
      expect(
        BusinessDate.tryParse('2026-02-31'),
        isNull,
      ); // never silently rolls over
      expect(BusinessDate.tryParse('2026-13-01'), isNull);
      expect(BusinessDate.tryParse('not-a-date'), isNull);
    });

    test('produces the P&L period key', () {
      expect(BusinessDate.of(2026, 6, 5).periodKey, '2026-06');
      expect(BusinessDate.of(2026, 12, 31).periodKey, '2026-12');
    });

    test('day arithmetic and comparison support the edit window', () {
      final start = BusinessDate.of(2026, 6, 15);
      expect(start.addDays(7).iso, '2026-06-22');
      expect(start.addDays(-1).iso, '2026-06-14');
      expect(BusinessDate.of(2026, 6, 22).differenceInDays(start), 7);
      expect(start < BusinessDate.of(2026, 6, 16), isTrue);
      expect(start == BusinessDate.of(2026, 6, 15), isTrue);
    });

    test('day arithmetic crosses month and year ends', () {
      expect(BusinessDate.of(2026, 6, 30).addDays(1).iso, '2026-07-01');
      expect(BusinessDate.of(2026, 12, 31).addDays(1).iso, '2027-01-01');
      expect(BusinessDate.of(2026, 3, 1).addDays(-1).iso, '2026-02-28');
    });
  });
}
