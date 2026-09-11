/// The two pulls a settlement preview needs, in the order and size the rulings require.
///
/// Phase 5 OA-3. Real `OwnerSettlementSync`, real `ReportingSync` and `ReportingCache` over
/// SQLite; the two transports answer from fixtures, as the existing reporting-sync suite's
/// fake does.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/owner_settlement_refresh.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';

final class _Reporting extends ReportingGateway {
  _Reporting() : super(SupabaseClient('http://localhost', 'test-key'));

  int snapshots = 0;
  RemoteFailure? unreachableWith;

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> snapshot({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
  }) async {
    if (unreachableWith case final failure?) return RemoteUnreachable(failure);
    snapshots++;
    return RemoteOk({
      'snapshot_id': 'rep-$snapshots',
      'server_time': '2026-09-11T08:00:00.000Z',
      'units': [
        for (final unit in businessUnitIds)
          {'business_unit_id': unit, 'reporting_authorised': true},
      ],
      'revenue': const <Map<String, dynamic>>[],
      'expense': const <Map<String, dynamic>>[],
    });
  }
}

final class _Owner implements OwnerSnapshotSource {
  _Owner(this.answer);
  RemoteOutcome<Map<String, dynamic>> Function() answer;
  @override
  Future<RemoteOutcome<Map<String, dynamic>>> fetchSettlementSnapshot() async =>
      answer();
}

Map<String, dynamic> _owner({String? start, bool authorised = true}) => {
  'snapshot_id': 'own-1',
  'server_time': '2026-09-11T08:00:00.000Z',
  'settlement_authorised': authorised,
  'ownership_start_date': authorised ? start : null,
  'movements': authorised ? const [] : null,
  'owners': authorised ? const [] : null,
  'ownership_shares': authorised ? const [] : null,
  'family_members': authorised ? const [] : null,
};

void main() {
  late AppDatabase db;
  late ReportingCache cache;
  late _Reporting reporting;
  late _Owner owner;
  late OwnerSettlementRefresher refresher;

  final today = BusinessDate.of(
    2026,
    9,
    11,
  ); // FY 2026-27; retention keeps 25-26 too

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cache = ReportingCache(db);
    reporting = _Reporting();
    owner = _Owner(() => RemoteOk(_owner(start: '2026-04-01')));
    refresher = OwnerSettlementRefresher(
      ownerSync: OwnerSettlementSync(
        database: db,
        gateway: owner,
        ownerUserId: 'user-1',
      ),
      reportingSync: ReportingSync(
        cache: cache,
        gateway: reporting,
        ownerUserId: 'user-1',
        orgId: 'org-1',
      ),
      repository: OwnerSettlementRepository(db, ownerUserId: 'user-1'),
    );
  });
  tearDown(() => db.close());

  Future<Map<int, bool>> certifiedYears() async => {
    for (final m in await cache.markersFor('user-1'))
      m.financialYear: m.onDemand,
  };

  test('both pulls run, owner history first, and both are reported', () async {
    final report = await refresher.refresh(
      businessUnitIds: {_ccr, _hki},
      periodEnd: BusinessDate.of(2026, 6, 30),
      today: today,
    );

    expect(report.ownerSucceeded, isTrue);
    expect(report.reportingSucceeded, isTrue);
    expect(report.succeeded, isTrue);
    expect(
      await certifiedYears(),
      {2026: false},
      reason:
          'sized by the start date the owner pull just delivered: 2026-04-01 to June is '
          'one financial year, and it is within retention',
    );
  });

  test(
    'years before retention are fetched on demand, so they are not pruned again',
    () async {
      owner.answer = () => RemoteOk(_owner(start: '2024-04-01'));
      final report = await refresher.refresh(
        businessUnitIds: {_ccr, _hki},
        periodEnd: BusinessDate.of(2026, 6, 30),
        today: today,
      );

      expect(report.reporting, hasLength(2), reason: 'two runs, two snapshots');
      expect(await certifiedYears(), {2024: true, 2025: false, 2026: false});
    },
  );

  test(
    'a not-authorised owner answer stops there: no P&L is fetched for it',
    () async {
      owner.answer = () => RemoteOk(_owner(authorised: false));
      final report = await refresher.refresh(
        businessUnitIds: {_ccr, _hki},
        periodEnd: BusinessDate.of(2026, 6, 30),
        today: today,
      );

      expect(report.owner, isA<OwnerSettlementSyncNotAuthorised>());
      expect(report.reporting, isNull);
      expect(reporting.snapshots, 0);
      expect(report.succeeded, isFalse);
    },
  );

  test(
    'an unreachable P&L is reported as not succeeded, and certifies nothing',
    () async {
      reporting.unreachableWith = RemoteFailure.offline;
      final report = await refresher.refresh(
        businessUnitIds: {_ccr, _hki},
        periodEnd: BusinessDate.of(2026, 6, 30),
        today: today,
      );
      expect(report.ownerSucceeded, isTrue);
      expect(report.reportingSucceeded, isFalse);
      expect(await certifiedYears(), isEmpty);
    },
  );

  test(
    'with no start date configured, only the month own year is fetched',
    () async {
      owner.answer = () => RemoteOk(_owner());
      await refresher.refresh(
        businessUnitIds: {_ccr, _hki},
        periodEnd: BusinessDate.of(2026, 6, 30),
        today: today,
      );
      expect(await certifiedYears(), {2026: false});
    },
  );
}
