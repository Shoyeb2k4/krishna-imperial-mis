/// Business date — the operational trading day a transaction belongs to.
///
/// A rooftop bill rung up at 01:00 belongs to the previous trading day. The business
/// date is therefore **derived** from the capture instant, the property's timezone and
/// the property's configurable cut-off (default 05:00), and is then **persisted**.
/// It is never recomputed at read time, so changing a cut-off tomorrow cannot silently
/// restate history. See master spec §9 and docs/DECISIONS.md D-019.
///
/// The device clock is not authoritative for anything else — server timestamps govern
/// `created_at`, `updated_at` and ordering.
library;

import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

/// The local time at which one trading day ends and the next begins.
@immutable
final class BusinessDayCutoff {
  const BusinessDayCutoff({required this.hour, required this.minute})
    : assert(hour >= 0 && hour < 24, 'hour must be 0..23'),
      assert(minute >= 0 && minute < 60, 'minute must be 0..59');

  final int hour;
  final int minute;

  /// The organisation-wide default agreed with the owner: 05:00 local property time.
  static const BusinessDayCutoff defaultCutoff = BusinessDayCutoff(
    hour: 5,
    minute: 0,
  );

  /// Plain calendar days — the business date equals the local date.
  static const BusinessDayCutoff midnight = BusinessDayCutoff(
    hour: 0,
    minute: 0,
  );

  int get minutesFromMidnight => hour * 60 + minute;

  /// Parses `HH:mm` as stored in `business_units.business_day_cutoff`.
  static BusinessDayCutoff? tryParse(String value) {
    final parts = value.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return BusinessDayCutoff(hour: hour, minute: minute);
  }

  String get formatted =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is BusinessDayCutoff &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'BusinessDayCutoff($formatted)';
}

/// How a stored business date came to hold its value.
///
/// Persisted alongside the date so an auditor can always tell an automatic derivation
/// from a human decision.
/// How a financial document's **current** business date came to be what it is.
///
/// Shared by the expense and revenue engines rather than duplicated per engine: it is one
/// concept and one stored vocabulary, and a second enum would be two things to keep in
/// step. Revenue produces only [derived] and [corrected] — it has no path that lets an
/// operator choose a trading day while recording — and its server-side CHECK says so.
///
/// The stored form is stated **explicitly** and is not `.name`. It happens to agree today,
/// and that is exactly the trap D-104 recorded: `EnteredBasis` was written and read through
/// `.name` while both schemas stored the snake-case form, and every rule carrying one would
/// have thrown on read. A wire name that is a coincidence is a wire name waiting to break.
enum BusinessDateSource {
  /// Derived from the capture instant under the unit's timezone and cut-off.
  derived('derived'),

  /// Entered explicitly by the user at the time of recording (e.g. yesterday's bill).
  ///
  /// Expense only. Revenue's schema does not admit it, because no revenue surface offers
  /// a date at entry.
  manual('manual'),

  /// Changed after the fact by a privileged user. Always audited, always with a reason.
  corrected('corrected');

  const BusinessDateSource(this.wireName);

  /// The exact string both schemas store. Pinned by a host test.
  final String wireName;

  /// Parses the stored form, and throws on anything else.
  ///
  /// There is no safe default: guessing between "the cut-off derived this" and "somebody
  /// moved it" would answer a financial provenance question with a shrug.
  static BusinessDateSource fromWire(String value) => values.firstWhere(
    (source) => source.wireName == value,
    orElse: () => throw ArgumentError.value(
      value,
      'value',
      'unknown business date source',
    ),
  );
}

/// A calendar date with no time and no zone: the trading day itself.
@immutable
final class BusinessDate implements Comparable<BusinessDate> {
  const BusinessDate._(this.year, this.month, this.day);

  /// An explicit calendar date. Normalises overflow (e.g. day 32) the way
  /// [DateTime] does, so callers cannot construct an impossible date.
  factory BusinessDate.of(int year, int month, int day) {
    final normalised = DateTime.utc(year, month, day);
    return BusinessDate._(normalised.year, normalised.month, normalised.day);
  }

  /// Derives the trading day for an instant at a property.
  ///
  /// ```
  /// local      = instant converted to the property's timezone
  /// businessDate = local.time < cutoff ? local.date − 1 day : local.date
  /// ```
  ///
  /// [timeZoneId] is an IANA zone such as `Asia/Kolkata`. IANA zones — rather than
  /// fixed offsets — are what make this DST-safe, even though the current properties
  /// observe no DST. `tz.initializeTimeZones()` must have run first.
  factory BusinessDate.fromInstant(
    DateTime instant, {
    required String timeZoneId,
    BusinessDayCutoff cutoff = BusinessDayCutoff.defaultCutoff,
  }) {
    final location = tz.getLocation(timeZoneId);
    final local = tz.TZDateTime.from(instant, location);

    final localMinutes = local.hour * 60 + local.minute;
    if (localMinutes >= cutoff.minutesFromMidnight) {
      return BusinessDate._(local.year, local.month, local.day);
    }

    // Step back one *calendar* day, not 24 hours. Doing this on a UTC-anchored
    // DateTime keeps it a pure calendar operation, so a DST transition in the
    // property's zone can never turn 01:00 on the 16th into the 14th.
    final previous = DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).subtract(const Duration(days: 1));
    return BusinessDate._(previous.year, previous.month, previous.day);
  }

  /// Parses the `YYYY-MM-DD` form used in storage and transport.
  static BusinessDate? tryParse(String value) {
    final parts = value.trim().split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final normalised = DateTime.utc(year, month, day);
    // Reject dates that only exist through overflow, e.g. 2026-02-31.
    if (normalised.month != month || normalised.day != day) return null;
    return BusinessDate._(year, month, day);
  }

  final int year;
  final int month;
  final int day;

  /// `YYYY-MM-DD`. The storage and transport form.
  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// `YYYY-MM`. The P&L period key (master spec §5.2).
  String get periodKey =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  BusinessDate addDays(int days) {
    final shifted = DateTime.utc(year, month, day).add(Duration(days: days));
    return BusinessDate._(shifted.year, shifted.month, shifted.day);
  }

  /// Whole calendar days from [other] to this date. Used by the edit window.
  int differenceInDays(BusinessDate other) => DateTime.utc(
    year,
    month,
    day,
  ).difference(DateTime.utc(other.year, other.month, other.day)).inDays;

  bool operator >(BusinessDate other) => compareTo(other) > 0;
  bool operator >=(BusinessDate other) => compareTo(other) >= 0;
  bool operator <(BusinessDate other) => compareTo(other) < 0;
  bool operator <=(BusinessDate other) => compareTo(other) <= 0;

  @override
  int compareTo(BusinessDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is BusinessDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => 'BusinessDate($iso)';
}
