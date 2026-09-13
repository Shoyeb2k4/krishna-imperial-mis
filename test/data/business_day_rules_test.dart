/// Each property's business-date rules, read from the cached masters (Phase 5 Slice 8).
///
/// A relative report preset is resolved under every property's **own** timezone and cut-off.
/// Those are stored per business unit (D-019), so they are read per business unit — and a
/// property whose rules are unreadable is reported as such, never defaulted to
/// `Asia/Kolkata` and 05:00.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/master_repository.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;

  Future<void> unit(String id, String code, String zone, String cutoff) =>
      db.customStatement(
        'INSERT INTO business_units (id, org_id, code, name, kind, timezone, '
        'business_day_cutoff, sort_order, row_version, updated_at) '
        "VALUES (?, 'test-org', ?, ?, 'hotel', ?, ?, 1, 1, "
        "'2026-06-01T00:00:00.000Z')",
        [id, code, code, zone, cutoff],
      );

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('each property keeps its own timezone and cut-off', () async {
    await unit('ccr', 'CCR', 'Asia/Kolkata', '05:00');
    await unit('hki', 'HKI', 'Asia/Kolkata', '00:00');

    final rules = await MasterRepository(db).businessDayRules();
    expect(rules['ccr']!.timeZoneId, 'Asia/Kolkata');
    expect(rules['ccr']!.cutoff, BusinessDayCutoff.defaultCutoff);
    expect(rules['hki']!.cutoff, BusinessDayCutoff.midnight);
  });

  test('the same instant gives each property its own business date', () async {
    await unit('ccr', 'CCR', 'Asia/Kolkata', '05:00');
    await unit('hki', 'HKI', 'Asia/Kolkata', '00:00');
    final rules = await MasterRepository(db).businessDayRules();

    // 21:00 UTC on 19 Sept is 02:30 IST on the 20th: before CCR's 05:00 cut-off, after
    // HKI's midnight one.
    final instant = DateTime.utc(2026, 9, 19, 21);
    expect(rules['ccr']!.businessDateAt(instant), BusinessDate.of(2026, 9, 19));
    expect(rules['hki']!.businessDateAt(instant), BusinessDate.of(2026, 9, 20));
  });

  test('an unreadable cut-off is absent, not defaulted', () async {
    await unit('ccr', 'CCR', 'Asia/Kolkata', '05:00');
    await unit('bad', 'BAD', 'Asia/Kolkata', 'late evening');

    final rules = await MasterRepository(db).businessDayRules();
    expect(rules.containsKey('ccr'), isTrue);
    expect(rules.containsKey('bad'), isFalse);
  });

  test('an unknown timezone is absent, not defaulted', () async {
    await unit('bad', 'BAD', 'Mars/Olympus_Mons', '05:00');
    final rules = await MasterRepository(db).businessDayRules();
    expect(rules.containsKey('bad'), isFalse);
  });
}
