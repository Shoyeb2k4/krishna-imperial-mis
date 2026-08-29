/// The client and the server derive a business date from the same instant, and this is
/// the test that says so out of one source rather than two (D-067, §14.2).
///
/// D-067 fixed a real defect: the edit window compared against `current_date`, which is
/// the *database session's* calendar date in UTC, while the properties keep
/// `Asia/Kolkata` time with an 05:00 cut-off. For half an hour every night the two
/// disagreed, and an entry that was D+8 old was accepted for edit as though it were D+7.
///
/// The fix put the rule in two places on purpose — `BusinessDate.fromInstant` in Dart and
/// `app.business_date_at` in SQL — because the client must derive a date offline and the
/// server must not trust one. Two implementations of one rule is exactly the situation
/// that drifts, and "both were written from the same prose" is not evidence.
///
/// So this test does not restate the boundary cases. It **reads the table the migration
/// asserts against** and requires Dart to agree at every instant in it. Editing either
/// side alone fails here:
///
///   * add a case to the migration → Dart is checked against it automatically;
///   * change an expected date in the migration → Dart must change to match;
///   * change the Dart derivation → the migration's cases catch it.
///
/// The instants are property-local wall clock with an explicit `+05:30` offset, so the
/// same absolute moment reaches both implementations. Neither side reads a clock: the
/// instant is an argument, which is what makes 04:59 testable without waiting for 04:59.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:timezone/data/latest.dart' as tzdata;

/// One row of the migration's assertion table.
typedef _BoundaryCase = ({DateTime instant, String expected, String why});

void main() {
  setUpAll(tzdata.initializeTimeZones);

  const migrationPath =
      'supabase/migrations/20260829110000_edit_window_property_date.sql';

  late List<_BoundaryCase> cases;

  setUpAll(() {
    cases = _parseBoundaryCases(File(migrationPath).readAsStringSync());
  });

  group('the property business date, from one table of instants', () {
    test('the migration still contains the cases this test reads', () {
      // A parser that quietly finds nothing would let every assertion below pass while
      // proving nothing at all — the D-069 lesson, applied to a test rather than a scan.
      expect(
        cases,
        hasLength(greaterThanOrEqualTo(6)),
        reason:
            'the boundary table in $migrationPath could not be read. Either it moved, '
            'or its shape changed — do not delete this test to make it pass',
      );
      expect(
        cases.map((c) => c.why),
        containsAll(<String>[
          'one minute before cut-off',
          'exactly at the cut-off',
          'the window UTC got wrong',
        ]),
      );
    });

    test('Dart agrees with the server at every asserted instant', () {
      for (final boundary in cases) {
        final derived = BusinessDate.fromInstant(
          boundary.instant,
          timeZoneId: 'Asia/Kolkata',
          cutoff: const BusinessDayCutoff(hour: 5, minute: 0),
        );
        expect(
          derived.iso,
          boundary.expected,
          reason:
              'at ${boundary.instant.toIso8601String()} (${boundary.why}) the server '
              'asserts ${boundary.expected} and the client derived ${derived.iso}. '
              'One of the two layers has moved',
        );
      }
    });

    test('the three instants the project lead named are among them', () {
      // 04:59 → previous day, 05:00 → new day, 05:15 → new day. Named explicitly so
      // the requirement is legible here and does not depend on reading the SQL.
      String derive(int hour, int minute) => BusinessDate.fromInstant(
        DateTime.utc(
          2026,
          6,
          16,
          hour,
          minute,
        ).subtract(const Duration(hours: 5, minutes: 30)),
        timeZoneId: 'Asia/Kolkata',
        cutoff: const BusinessDayCutoff(hour: 5, minute: 0),
      ).iso;

      expect(derive(4, 59), '2026-06-15', reason: 'before the cut-off');
      expect(derive(5, 0), '2026-06-16', reason: 'at the cut-off');
      expect(derive(5, 15), '2026-06-16', reason: 'after the cut-off');
    });

    test('the UTC calendar date is not the property business date at 05:15', () {
      // The defect itself, restated on the client side. If this ever stops being true,
      // the coincidence D-067 warns about has changed and the reasoning must be re-read.
      final instant = DateTime.utc(
        2026,
        6,
        16,
        5,
        15,
      ).subtract(const Duration(hours: 5, minutes: 30));
      final property = BusinessDate.fromInstant(
        instant,
        timeZoneId: 'Asia/Kolkata',
        cutoff: const BusinessDayCutoff(hour: 5, minute: 0),
      );
      final utcCalendarDate =
          '${instant.year.toString().padLeft(4, '0')}-'
          '${instant.month.toString().padLeft(2, '0')}-'
          '${instant.day.toString().padLeft(2, '0')}';

      expect(property.iso, '2026-06-16');
      expect(utcCalendarDate, '2026-06-15');
      expect(
        property.iso,
        isNot(utcCalendarDate),
        reason:
            'this half hour is why current_date appears nowhere in the schema (D-067)',
      );
    });
  });

  group('the edit window counts in property business dates', () {
    // The window rule (D-065) is `elapsed = today − business_date`, in whole calendar
    // days, permitted while `elapsed <= edit_window_days`. What D-067 changed is what
    // "today" means. These assert the arithmetic on that basis, so D+7 and D+8 are
    // pinned to the property's day and not to the device's or the database session's.
    const windowDays = 7;

    int elapsedAt(DateTime instant, String businessDate) {
      final today = BusinessDate.fromInstant(
        instant,
        timeZoneId: 'Asia/Kolkata',
        cutoff: const BusinessDayCutoff(hour: 5, minute: 0),
      );
      return today.differenceInDays(BusinessDate.tryParse(businessDate)!);
    }

    test('an entry recorded this second has spent none of its window', () {
      // Deriving "today" through the cut-off, rather than from the plain calendar date,
      // is what makes this zero instead of one.
      final instant = DateTime.utc(
        2026,
        6,
        16,
        5,
        15,
      ).subtract(const Duration(hours: 5, minutes: 30));
      expect(elapsedAt(instant, '2026-06-16'), 0);
    });

    test('D+7 is inside the window and D+8 is outside it', () {
      final atNoonOnTheSeventh = DateTime.utc(
        2026,
        6,
        23,
        12,
      ).subtract(const Duration(hours: 5, minutes: 30));
      expect(elapsedAt(atNoonOnTheSeventh, '2026-06-16'), windowDays);
      expect(elapsedAt(atNoonOnTheSeventh, '2026-06-16') <= windowDays, isTrue);

      final atNoonOnTheEighth = DateTime.utc(
        2026,
        6,
        24,
        12,
      ).subtract(const Duration(hours: 5, minutes: 30));
      expect(elapsedAt(atNoonOnTheEighth, '2026-06-16'), windowDays + 1);
      expect(elapsedAt(atNoonOnTheEighth, '2026-06-16') <= windowDays, isFalse);
    });

    test('the half hour that used to grant an eighth day no longer does', () {
      // 05:15 IST on 24 June. The property's business date is the 24th, so an entry
      // dated the 16th is D+8 and refused. Under `current_date` the session's UTC date
      // was still the 23rd, making it look like D+7 — the defect D-067 fixed.
      final instant = DateTime.utc(
        2026,
        6,
        24,
        5,
        15,
      ).subtract(const Duration(hours: 5, minutes: 30));
      expect(
        elapsedAt(instant, '2026-06-16'),
        windowDays + 1,
        reason: 'D+8, measured under the property date',
      );

      final utcDate = DateTime.utc(
        2026,
        6,
        24,
        5,
        15,
      ).subtract(const Duration(hours: 5, minutes: 30));
      expect(
        utcDate.day,
        23,
        reason:
            'the session date UTC would have used, one day behind — this is the gap, '
            'and it is why the comparison is derived and not read from a clock',
      );
    });

    test(
      'a midnight cut-off would widen the gap, which is why it is configuration',
      () {
        // D-067's point: thirty minutes is an accident of +05:30 cancelling an 05:00
        // cut-off. With a midnight cut-off the same instant lands on a different day for
        // five and a half hours a day. Asserted so the reasoning is not just prose.
        final instant = DateTime.utc(
          2026,
          6,
          16,
          2,
          0,
        ).subtract(const Duration(hours: 5, minutes: 30));
        expect(
          BusinessDate.fromInstant(
            instant,
            timeZoneId: 'Asia/Kolkata',
            cutoff: const BusinessDayCutoff(hour: 0, minute: 0),
          ).iso,
          '2026-06-16',
          reason: 'with no cut-off, 02:00 belongs to its own calendar day',
        );
        expect(
          BusinessDate.fromInstant(
            instant,
            timeZoneId: 'Asia/Kolkata',
            cutoff: const BusinessDayCutoff(hour: 5, minute: 0),
          ).iso,
          '2026-06-15',
          reason:
              'with the 05:00 cut-off it belongs to the previous trading day',
        );
      },
    );
  });

  group('per-unit semantics survive a second timezone', () {
    // Both properties are Asia/Kolkata today. The rule is per unit, and D-067 warns that
    // a property west of UTC reverses the sign of the error, so the derivation is
    // exercised with another zone to keep that a property of the code and not of the
    // fixture.
    test('the same instant is a different business date in another zone', () {
      // 06:00 UTC on 16 June: 11:30 in Kolkata, 02:00 in New York (EDT). Both use an
      // 05:00 cut-off, and they land on different trading days — Kolkata is past its
      // cut-off, New York has not reached its own.
      final instant = DateTime.utc(2026, 6, 16, 6);

      expect(
        BusinessDate.fromInstant(
          instant,
          timeZoneId: 'Asia/Kolkata',
          cutoff: const BusinessDayCutoff(hour: 5, minute: 0),
        ).iso,
        '2026-06-16',
        reason: '11:30 local, past the cut-off',
      );
      expect(
        BusinessDate.fromInstant(
          instant,
          timeZoneId: 'America/New_York',
          cutoff: const BusinessDayCutoff(hour: 5, minute: 0),
        ).iso,
        '2026-06-15',
        reason: '02:00 local, still the previous trading day',
      );
    });

    test('a property west of UTC reverses the sign of the old defect', () {
      // D-067's warning, asserted. East of UTC the UTC calendar date lagged the
      // property's; west of UTC it runs ahead, so `current_date` would have *refused*
      // edits that were still inside the window rather than granting an extra day.
      final instant = DateTime.utc(2026, 6, 16, 3);
      final property = BusinessDate.fromInstant(
        instant,
        timeZoneId: 'America/New_York',
        cutoff: const BusinessDayCutoff(hour: 5, minute: 0),
      );

      expect(property.iso, '2026-06-15', reason: '23:00 on the 15th, local');
      expect(
        instant.day,
        16,
        reason:
            'the UTC date is already the 16th — a day ahead of the property, the '
            'opposite direction to the Kolkata case, and equally wrong',
      );
    });
  });
}

/// Reads the `(timestamptz '…', date '…', '…')` rows out of the migration's assertion
/// table.
///
/// Deliberately strict: anything it cannot parse it skips, and the first test asserts a
/// minimum count so an over-strict parser fails loudly instead of finding nothing and
/// letting the suite pass on an empty list.
List<_BoundaryCase> _parseBoundaryCases(String sql) {
  final pattern = RegExp(
    r"\(timestamptz\s+'([^']+)',\s*date\s+'([^']+)',\s*'([^']+)'\)",
  );
  return [
    for (final match in pattern.allMatches(sql))
      (
        instant: DateTime.parse(match.group(1)!.replaceFirst(' ', 'T')),
        expected: match.group(2)!,
        why: match.group(3)!,
      ),
  ];
}
