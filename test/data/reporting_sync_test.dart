/// `ReportingSync` — the delta that closes the cross-device reporting gap (Phase 5 Slice 4).
///
/// These drive a **real** SQLite database through the real cache and the real
/// synchroniser, against a gateway that answers as a server projection would. What is
/// faked is one HTTP call; every decision under test — the watermark, the document-grain
/// replacement, the year boundary, the void, the marker — is the shipped code.
///
/// The scenarios are chosen where a wrong implementation still produces a plausible
/// figure, because that is the failure mode of a reporting cache: it does not raise, it
/// reconciles against itself, and it is wrong.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:timezone/data/latest.dart' as tzdata;

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _me = 'user-me';
const _colleague = 'user-colleague';

/// A gateway answering out of a table of projection rows, exactly as the server view
/// would: everything above the generation asked for, in generation order, voided rows
/// included and carrying `voided_at`.
///
/// It never opens a socket — the Supabase client is constructed and not used, because
/// both methods are overridden. The pattern the revenue transport suite established.
final class _FakeReportingGateway extends ReportingGateway {
  _FakeReportingGateway()
    : super(SupabaseClient('http://localhost', 'test-key'));

  final Map<ReportingDataset, List<Map<String, dynamic>>> rows = {
    ReportingDataset.revenue: [],
    ReportingDataset.expense: [],
  };

  /// Every `sinceGeneration` the synchroniser asked from, in order.
  final List<({ReportingDataset dataset, int since})> asked = [];

  /// What RLS lets this caller see. Both projections are scoped by the reader's own
  /// grants — `has_capability('revenue.view', unit)` on one side, `expense_visible_units`
  /// on the other — so a gateway that answered for every property would not be modelling
  /// the server at the one point where authority decides the answer.
  Set<String> visibleUnits = {_ccr, _hki};

  RemoteFailure? unreachableWith;

  /// Which snapshot the next run gets. Bumped per call, exactly as a real server issues a
  /// new MVCC snapshot per statement.
  int snapshots = 0;

  /// The server's own clock. Never the device's — the whole point of the evidence.
  DateTime serverTime = DateTime.utc(2027, 1, 14, 9, 30);

  /// One authoritative snapshot: both datasets, one identity, one server time.
  ///
  /// Modelled on `public.reporting_snapshot`, including the part that matters — the two
  /// datasets are answered **together**, so nothing can be written between them.
  @override
  Future<RemoteOutcome<Map<String, dynamic>>> snapshot({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
  }) async {
    asked.add((dataset: ReportingDataset.revenue, since: revenueSince));
    asked.add((dataset: ReportingDataset.expense, since: expenseSince));
    if (unreachableWith case final failure?) return RemoteUnreachable(failure);

    snapshots++;
    final authorised = businessUnitIds.where(visibleUnits.contains).toSet();

    List<Map<String, dynamic>> matching(ReportingDataset dataset, int since) =>
        (rows[dataset]!
                .where(
                  (r) =>
                      (r['change_seq'] as int) > since &&
                      authorised.contains(r['business_unit_id']),
                )
                .toList()
              ..sort(
                (a, b) =>
                    (a['change_seq'] as int).compareTo(b['change_seq'] as int),
              ))
            .map(Map<String, dynamic>.from)
            .toList();

    return RemoteOk({
      'snapshot_id': 'snapshot-$snapshots',
      'server_time': serverTime.toIso8601String(),
      'units': [
        for (final unit in businessUnitIds)
          {
            'business_unit_id': unit,
            'reporting_authorised': visibleUnits.contains(unit),
          },
      ],
      'revenue': matching(ReportingDataset.revenue, revenueSince),
      'expense': matching(ReportingDataset.expense, expenseSince),
    });
  }

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> newerThan({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
  }) async {
    if (unreachableWith case final failure?) return RemoteUnreachable(failure);
    final authorised = businessUnitIds.where(visibleUnits.contains).toSet();
    bool any(ReportingDataset dataset, int since) => rows[dataset]!.any(
      (r) =>
          (r['change_seq'] as int) > since &&
          authorised.contains(r['business_unit_id']),
    );
    return RemoteOk({
      'server_time': serverTime.toIso8601String(),
      'revenue_newer': any(ReportingDataset.revenue, revenueSince),
      'expense_newer': any(ReportingDataset.expense, expenseSince),
    });
  }

  @override
  Future<RemoteOutcome<List<Map<String, dynamic>>>> changedContributions({
    required ReportingDataset dataset,
    required int sinceGeneration,
    int pageSize = 1000,
  }) async {
    asked.add((dataset: dataset, since: sinceGeneration));
    if (unreachableWith case final failure?) return RemoteUnreachable(failure);
    final matching =
        rows[dataset]!
            .where(
              (r) =>
                  (r['change_seq'] as int) > sinceGeneration &&
                  visibleUnits.contains(r['business_unit_id']),
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['change_seq'] as int).compareTo(b['change_seq'] as int),
          );
    return RemoteOk([
      for (final row in matching) Map<String, dynamic>.from(row),
    ]);
  }

  /// Replaces a document's whole contribution set, which is what the server holds after a
  /// correction — the rows are derived, so an edit does not leave the old ones behind.
  void putRevenue(
    String entryId, {
    required List<Map<String, dynamic>> components,
    required int changeSeq,
    bool voided = false,
  }) {
    rows[ReportingDataset.revenue]!.removeWhere(
      (r) => r['revenue_entry_id'] == entryId,
    );
    for (final component in components) {
      rows[ReportingDataset.revenue]!.add({
        'org_id': _org,
        'revenue_entry_id': entryId,
        'txn_number': 'KI-REV-26-27-000001',
        'tax_treatment': 'inclusive',
        'tax_rate_bp': 500,
        'entered_basis': 'inclusive_total',
        'value_band_id': null,
        'supply_subtype_id': null,
        'voided_at': voided ? '2026-09-01T00:00:00Z' : null,
        'change_seq': changeSeq,
        ...component,
      });
    }
  }

  void putExpense(
    String expenseId, {
    required List<Map<String, dynamic>> lines,
    required int changeSeq,
    bool voided = false,
  }) {
    rows[ReportingDataset.expense]!.removeWhere(
      (r) => r['expense_id'] == expenseId,
    );
    for (final line in lines) {
      rows[ReportingDataset.expense]!.add({
        'org_id': _org,
        'expense_id': expenseId,
        'department_id': 'dept-1',
        'section_id': 'sec-1',
        'category_id': 'cat-kirana',
        'vendor_id': null,
        'voided_at': voided ? '2026-09-01T00:00:00Z' : null,
        'change_seq': changeSeq,
        ...line,
      });
    }
  }
}

Map<String, dynamic> _component({
  required String id,
  required String unit,
  required String category,
  required String pnlDate,
  required int gross,
  required int tax,
}) => {
  'id': id,
  'business_unit_id': unit,
  'revenue_category_id': category,
  'pnl_date': pnlDate,
  'pnl_period_key': pnlDate.substring(0, 7),
  'gross_minor': gross,
  'tax_minor': tax,
  'net_minor': gross - tax,
};

Map<String, dynamic> _line({
  required String id,
  required String allocation,
  required String unit,
  required String pnlDate,
  required int amount,
}) => {
  'id': id,
  'allocation_id': allocation,
  'business_unit_id': unit,
  'pnl_date': pnlDate,
  'pnl_period_key': pnlDate.substring(0, 7),
  'amount_minor': amount,
};

ReportRange _june() =>
    const MonthPeriod(2026, 6).resolve() is ReportRangeResolved
    ? (const MonthPeriod(2026, 6).resolve() as ReportRangeResolved).range
    : throw StateError('June 2026 is a month');

ReportRange _july() =>
    (const MonthPeriod(2026, 7).resolve() as ReportRangeResolved).range;

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late ReportingCache cache;
  late _FakeReportingGateway gateway;
  late ReportingSync sync;

  final fy2026 = const FinancialYear(2026);
  final fy2025 = const FinancialYear(2025);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    cache = ReportingCache(db);
    gateway = _FakeReportingGateway();
    sync = ReportingSync(
      cache: cache,
      gateway: gateway,
      ownerUserId: _me,
      orgId: _org,
      clock: () => DateTime.utc(2026, 9, 7, 12),
    );
  });
  tearDown(() => db.close());

  Future<ReportingSyncReport> run({
    Set<String> units = const {_ccr, _hki},
    List<FinancialYear>? years,
    bool onDemand = false,
  }) => sync.synchronise(
    businessUnitIds: units,
    years: years ?? [fy2026],
    onDemand: onDemand,
  );

  Future<Money> revenueGross(String unit, ReportRange range) async =>
      (await cache.revenueTotals(
        ownerUserId: _me,
        businessUnitId: unit,
        range: range,
      )).gross;

  Future<Money> expenseAmount(String unit, ReportRange range) async =>
      (await cache.expenseTotals(
        ownerUserId: _me,
        businessUnitId: unit,
        range: range,
      )).amount;

  group('the initial snapshot', () {
    test('a device that recorded nothing can report the whole hotel', () async {
      // Everything below was recorded by somebody else, on another device. This is the
      // gap D-173 named: before Slice 4 a second phone reported zero and looked correct.
      gateway.putRevenue(
        'rev-1',
        changeSeq: 100,
        components: [
          _component(
            id: 'c-1',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 10000000,
            tax: 476190,
          ),
        ],
      );
      gateway.putExpense(
        'exp-1',
        changeSeq: 101,
        lines: [
          _line(
            id: 'p-1',
            allocation: 'a-1',
            unit: _ccr,
            pnlDate: '2026-06-30',
            amount: 2500000,
          ),
        ],
      );

      final report = await run();
      expect(report.isComplete, isTrue);
      expect(await revenueGross(_ccr, _june()), Money.fromRupees(100000));
      expect(await expenseAmount(_ccr, _june()), Money.fromRupees(25000));
    });

    test('the first delta asks from zero', () async {
      await run();
      expect(
        gateway.asked.map((a) => a.since).toSet(),
        {0},
        reason:
            'no marker means no watermark. Asking from anything higher would skip every '
            'document written before this device existed',
      );
    });

    test('a marker is written for every requested scope and dataset', () async {
      await run(units: {_ccr, _hki});
      final markers = await cache.markersFor(_me);
      expect(markers.length, 4, reason: '2 properties x 2 datasets');
      expect(markers.every((m) => m.financialYear == 2026), isTrue);
      expect(markers.every((m) => m.onDemand == false), isTrue);
    });

    test(
      'a quiet property is certified to the same generation as a busy one',
      () async {
        gateway.putRevenue(
          'rev-1',
          changeSeq: 900,
          components: [
            _component(
              id: 'c-1',
              unit: _ccr,
              category: 'cat-restaurant',
              pnlDate: '2026-06-15',
              gross: 100,
              tax: 0,
            ),
          ],
        );
        await run();
        final markers = await cache.markersFor(_me);
        expect(
          markers
              .where((m) => m.dataset == ReportingDataset.revenue)
              .map((m) => m.generation)
              .toSet(),
          {900},
          reason:
              'one run is one authoritative boundary. Certifying Hotel Krishna lower '
              'because nothing of its changed would leave it permanently behind, '
              're-reading the same delta for ever (§21)',
        );
      },
    );
  });

  group('the delta replaces a document rather than appending to it', () {
    setUp(() async {
      gateway.putRevenue(
        'rev-1',
        changeSeq: 100,
        components: [
          _component(
            id: 'c-1',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 10000000,
            tax: 476190,
          ),
        ],
      );
      await run();
    });

    test('an accepted correction changes the figure exactly once', () async {
      gateway.putRevenue(
        'rev-1',
        changeSeq: 200,
        components: [
          _component(
            id: 'c-1b',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 12000000,
            tax: 571429,
          ),
        ],
      );
      await run();

      expect(
        await revenueGross(_ccr, _june()),
        Money.fromRupees(120000),
        reason:
            'replaced, not appended. An append leaves 100,000 + 120,000 = 220,000 — a '
            'figure that is wrong, stable, and reconciles against itself (§14)',
      );
      expect(
        (await cache.revenueTotals(
          ownerUserId: _me,
          businessUnitId: _ccr,
          range: _june(),
        )).contributions,
        1,
      );
    });

    test('a correction that splits into two components stores both', () async {
      gateway.putRevenue(
        'rev-1',
        changeSeq: 200,
        components: [
          _component(
            id: 'c-1',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 6000000,
            tax: 285714,
          ),
          _component(
            id: 'c-2',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 4000000,
            tax: 190476,
          ),
        ],
      );
      await run();

      final totals = await cache.revenueTotals(
        ownerUserId: _me,
        businessUnitId: _ccr,
        range: _june(),
      );
      expect(totals.gross, Money.fromRupees(100000));
      expect(
        totals.contributions,
        2,
        reason:
            'component grain survives into the cache: two bands are never flattened '
            'into one rate applied to nothing (D-087)',
      );
    });

    test('re-delivering the same generation is idempotent', () async {
      // The safety overlap re-reads below the watermark on every run, so this is the
      // ordinary case rather than an edge one (ARCHITECTURE §5.2).
      await run();
      await run();
      expect(await revenueGross(_ccr, _june()), Money.fromRupees(100000));
      expect(
        (await cache.revenueTotals(
          ownerUserId: _me,
          businessUnitId: _ccr,
          range: _june(),
        )).contributions,
        1,
      );
    });

    test('the overlap is actually asked for', () async {
      gateway.asked.clear();
      await run();
      expect(
        gateway.asked.first.since,
        0,
        reason:
            'a watermark of 100 less a 500 overlap clamps at zero rather than going '
            'negative — and a negative bound would be a query nobody wrote a rule for',
      );

      gateway.putRevenue(
        'rev-2',
        changeSeq: 9000,
        components: [
          _component(
            id: 'c-9',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-16',
            gross: 100,
            tax: 0,
          ),
        ],
      );
      await run();
      gateway.asked.clear();
      await run();
      expect(
        gateway.asked.first.since,
        9000 - ReportingSync.defaultSafetyOverlap,
        reason:
            'the delta re-reads below its own watermark, because a sequence value is '
            'allocated at write and becomes visible at commit',
      );
    });
  });

  group('a void removes the effect and nothing else', () {
    test('a voided sale stops contributing', () async {
      gateway.putRevenue(
        'rev-1',
        changeSeq: 100,
        components: [
          _component(
            id: 'c-1',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 10000000,
            tax: 476190,
          ),
        ],
      );
      await run();
      expect(await revenueGross(_ccr, _june()), Money.fromRupees(100000));

      gateway.putRevenue(
        'rev-1',
        changeSeq: 200,
        voided: true,
        components: [
          _component(
            id: 'c-1',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 10000000,
            tax: 476190,
          ),
        ],
      );
      final report = await run();

      expect(
        await revenueGross(_ccr, _june()),
        Money.zero,
        reason:
            'the projection carries voided_at rather than filtering it, which is what '
            'makes a void visible to a delta at all. The document is replaced by '
            'nothing (D-006)',
      );
      final revenue =
          report.forDataset(ReportingDataset.revenue) as DatasetSynchronised;
      expect(revenue.rowsDropped, 1);
      expect(revenue.documentsReplaced, 1);
    });
  });

  group('a business-date correction moves the money', () {
    test('June loses it and July gains it, with no double count', () async {
      gateway.putRevenue(
        'rev-1',
        changeSeq: 100,
        components: [
          _component(
            id: 'c-1',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-30',
            gross: 10000000,
            tax: 476190,
          ),
        ],
      );
      await run();
      expect(await revenueGross(_ccr, _june()), Money.fromRupees(100000));

      // A correction replaces the document's components, so the corrected sale arrives
      // under a **new** component id. That is what makes the year-scoped delete
      // load-bearing rather than incidental: an upsert on the old id would have masked it.
      gateway.putRevenue(
        'rev-1',
        changeSeq: 200,
        components: [
          _component(
            id: 'c-1b',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-07-01',
            gross: 10000000,
            tax: 476190,
          ),
        ],
      );
      await run();

      expect(
        await revenueGross(_ccr, _june()),
        Money.zero,
        reason:
            'this is the case a period-filtered delta cannot see: a June query returns '
            'no row for a sale that has left June, so the stale figure would sit in the '
            'cache for ever',
      );
      expect(await revenueGross(_ccr, _july()), Money.fromRupees(100000));
    });

    test('an accounting-period move relocates an expense the same way', () async {
      gateway.putExpense(
        'exp-1',
        changeSeq: 100,
        lines: [
          _line(
            id: 'p-1',
            allocation: 'a-1',
            unit: _ccr,
            pnlDate: '2026-06-30',
            amount: 6000000,
          ),
        ],
      );
      await run();
      expect(await expenseAmount(_ccr, _june()), Money.fromRupees(60000));

      // The same bill, now deliberately split across two accounting periods (D-034).
      gateway.putExpense(
        'exp-1',
        changeSeq: 200,
        lines: [
          _line(
            id: 'p-1',
            allocation: 'a-1',
            unit: _ccr,
            pnlDate: '2026-06-30',
            amount: 3000000,
          ),
          _line(
            id: 'p-2',
            allocation: 'a-1',
            unit: _ccr,
            pnlDate: '2026-07-31',
            amount: 3000000,
          ),
        ],
      );
      await run();

      expect(await expenseAmount(_ccr, _june()), Money.fromRupees(30000));
      expect(await expenseAmount(_ccr, _july()), Money.fromRupees(30000));
    });
  });

  group('a shared bill is attributed to both properties', () {
    test(
      'each property carries its own share and neither carries the total',
      () async {
        gateway.putExpense(
          'exp-1',
          changeSeq: 100,
          lines: [
            _line(
              id: 'p-1',
              allocation: 'a-1',
              unit: _ccr,
              pnlDate: '2026-06-30',
              amount: 2500000,
            ),
            _line(
              id: 'p-2',
              allocation: 'a-2',
              unit: _hki,
              pnlDate: '2026-06-30',
              amount: 3300000,
            ),
          ],
        );
        await run();

        expect(await expenseAmount(_ccr, _june()), Money.fromRupees(25000));
        expect(await expenseAmount(_hki, _june()), Money.fromRupees(33000));
      },
    );

    test('re-apportioning replaces both sides at once', () async {
      gateway.putExpense(
        'exp-1',
        changeSeq: 100,
        lines: [
          _line(
            id: 'p-1',
            allocation: 'a-1',
            unit: _ccr,
            pnlDate: '2026-06-30',
            amount: 2500000,
          ),
          _line(
            id: 'p-2',
            allocation: 'a-2',
            unit: _hki,
            pnlDate: '2026-06-30',
            amount: 3300000,
          ),
        ],
      );
      await run();

      gateway.putExpense(
        'exp-1',
        changeSeq: 200,
        lines: [
          _line(
            id: 'p-3',
            allocation: 'a-3',
            unit: _ccr,
            pnlDate: '2026-06-30',
            amount: 5800000,
          ),
        ],
      );
      await run();

      expect(await expenseAmount(_ccr, _june()), Money.fromRupees(58000));
      expect(
        await expenseAmount(_hki, _june()),
        Money.zero,
        reason:
            'the whole document is replaced, so a line that no longer exists leaves no '
            'residue on the property it used to charge. Deletion is by document and is '
            'not scoped to a unit, which is what makes a moved line safe',
      );
    });
  });

  group('the year boundary', () {
    test('refreshing one year does not touch another', () async {
      gateway.putRevenue(
        'rev-1',
        changeSeq: 100,
        components: [
          // A document contributing to two financial years, which a cross-period
          // allocation legitimately does (D-034).
          _component(
            id: 'c-1',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-03-31',
            gross: 5000000,
            tax: 0,
          ),
          _component(
            id: 'c-2',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-30',
            gross: 7000000,
            tax: 0,
          ),
        ],
      );
      await run(years: [fy2025, fy2026]);

      final march =
          (const MonthPeriod(2026, 3).resolve() as ReportRangeResolved).range;
      expect(await revenueGross(_ccr, march), Money.fromRupees(50000));
      expect(await revenueGross(_ccr, _june()), Money.fromRupees(70000));

      // Now refresh only FY2026. FY2025's row for the same document must survive.
      await run(years: [fy2026]);
      expect(
        await revenueGross(_ccr, march),
        Money.fromRupees(50000),
        reason:
            'replacement is bounded by the year being refreshed, so a document that '
            'contributes to two years does not lose one of them (§15)',
      );
    });
  });

  group('a failed run changes nothing', () {
    test(
      'unreachable leaves the figures and the marker exactly as they were',
      () async {
        gateway.putRevenue(
          'rev-1',
          changeSeq: 100,
          components: [
            _component(
              id: 'c-1',
              unit: _ccr,
              category: 'cat-restaurant',
              pnlDate: '2026-06-15',
              gross: 10000000,
              tax: 476190,
            ),
          ],
        );
        await run();
        final before = await cache.markersFor(_me);

        gateway.unreachableWith = RemoteFailure.offline;
        final report = await run();

        expect(report.isComplete, isFalse);
        expect(
          report.forDataset(ReportingDataset.revenue),
          isA<DatasetUnreachable>(),
        );
        expect(await revenueGross(_ccr, _june()), Money.fromRupees(100000));
        expect(
          (await cache.markersFor(_me)).map((m) => m.generation).toList(),
          before.map((m) => m.generation).toList(),
          reason:
              'unknown is not revoked. A network failure says nothing about a property '
              'books, and purging on one would be the destructive reading (D-048 §1)',
        );
      },
    );

    test('a failing run certifies neither side — one snapshot or none', () async {
      gateway.putRevenue(
        'rev-1',
        changeSeq: 100,
        components: [
          _component(
            id: 'c-1',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 10000000,
            tax: 476190,
          ),
        ],
      );

      // The snapshot never answers. Before the coherence corrective this scenario could
      // leave revenue certified and expenses not, because the two datasets were two
      // independent queries — the run half-succeeded and the cache held one side of a
      // moment. One statement removes the case entirely: there is nothing to half-apply.
      final half = _HalfFailingGateway(gateway, () => true);
      final partial = ReportingSync(
        cache: cache,
        gateway: half,
        ownerUserId: _me,
        orgId: _org,
        clock: () => DateTime.utc(2026, 9, 7, 12),
      );
      final report = await partial.synchronise(
        businessUnitIds: {_ccr},
        years: [fy2026],
      );

      expect(report.isComplete, isFalse);
      expect(
        report.snapshotId,
        isNull,
        reason: 'a run that failed certifies no snapshot',
      );
      expect(
        (await cache.markersFor(_me)).map((m) => m.dataset),
        isEmpty,
        reason:
            'neither side may be certified from a run that did not complete — a marker '
            'over one dataset is exactly the half-snapshot D-188 removes',
      );

      final engine = LocalReportingEngine(
        CachedReportingSource(
          cache: cache,
          ownerUserId: _me,
          coverage: await MarkerCoverage.load(cache, _me),
        ),
      );
      final envelope = await engine.report(
        ReportRequest(
          period: const MonthPeriod(2026, 6),
          scope: ReportingScope.unit(_ccr),
        ),
      );

      expect(
        envelope.outcome,
        isA<PnlRefused>(),
        reason:
            'a run that certified nothing leaves nothing to report, and an uncertified '
            'range refuses rather than presenting an empty cache as a zero (D-163)',
      );
      // Both sides, and that is the corrective rather than a regression of D-183. The
      // per-side refusal is intact and still names one half wherever one half is what is
      // missing — an unauthorised side, or a year pruned from one dataset. What can no
      // longer happen is *this* shape: a run that failed leaving revenue certified and
      // expenses not. There is one statement and one transaction, so a failure leaves
      // neither, and naming both sides is now the truthful answer.
      expect(
        (envelope.outcome as PnlRefused).refusal,
        PnlRefusal.bothSidesUnavailable,
        reason:
            'nothing was certified, so neither side is available — before the coherence '
            'corrective this run would have half-succeeded (D-188)',
      );
      expect(envelope.revenueCoverage, ReportingCoverage.notDownloaded);
      expect(envelope.expenseCoverage, ReportingCoverage.notDownloaded);
      expect(
        envelope.freshness,
        isNull,
        reason: 'a refused report makes no claim about how current it is',
      );
      expect(
        (envelope.outcome as PnlRefused).sideReason,
        isNull,
        reason:
            'sideReason names why the ONE unavailable side was unavailable, and here '
            'neither side is available — the per-side coverage above is what says this '
            'is a synchronisation problem rather than a grant one',
      );
    });
  });

  group('the cache belongs to a person', () {
    test('a colleague synchronisation is not this reader coverage', () async {
      gateway.putRevenue(
        'rev-1',
        changeSeq: 100,
        components: [
          _component(
            id: 'c-1',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 10000000,
            tax: 476190,
          ),
        ],
      );
      gateway.putExpense(
        'exp-1',
        changeSeq: 101,
        lines: [
          _line(
            id: 'p-1',
            allocation: 'a-1',
            unit: _ccr,
            pnlDate: '2026-06-30',
            amount: 2500000,
          ),
        ],
      );
      await run(units: {_ccr});

      final theirs = ReportingSync(
        cache: cache,
        gateway: gateway,
        ownerUserId: _colleague,
        orgId: _org,
        clock: () => DateTime.utc(2026, 9, 7, 12),
      );

      expect(
        await revenueGross(_ccr, _june()),
        Money.fromRupees(100000),
        reason: 'mine is unaffected by anything the next person does',
      );
      expect(
        (await cache.revenueTotals(
          ownerUserId: _colleague,
          businessUnitId: _ccr,
          range: _june(),
        )).gross,
        Money.zero,
        reason:
            'the shared workstation case. A cached P&L is a fact about a person '
            'authority at a moment, not about the installation (D-074)',
      );
      expect(await cache.markersFor(_colleague), isEmpty);

      await theirs.synchronise(businessUnitIds: {_ccr}, years: [fy2026]);
      expect(
        (await cache.revenueTotals(
          ownerUserId: _colleague,
          businessUnitId: _ccr,
          range: _june(),
        )).gross,
        Money.fromRupees(100000),
      );
      expect(
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM reporting_revenue_contributions',
                )
                .getSingle())
            .read<int>('n'),
        2,
        reason: 'one server fact, cached once per person who synchronised it',
      );
    });
  });

  group('gaining authority over a property', () {
    test('a newly granted property is pulled from the beginning', () async {
      // Recorded long before this device had any authority over Hotel Krishna, so its
      // generation is *below* the watermark Crystal Canopy has already reached.
      gateway.putRevenue(
        'rev-hki',
        changeSeq: 50,
        components: [
          _component(
            id: 'c-hki',
            unit: _hki,
            category: 'cat-room',
            pnlDate: '2026-06-10',
            gross: 5200000,
            tax: 247619,
          ),
        ],
      );
      gateway.putRevenue(
        'rev-ccr',
        changeSeq: 5000,
        components: [
          _component(
            id: 'c-ccr',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 10000000,
            tax: 476190,
          ),
        ],
      );

      // The manager holds Crystal Canopy only. RLS returns nothing of Hotel Krishna's,
      // so this run cannot have cached it by accident.
      gateway.visibleUnits = {_ccr};
      await run(units: {_ccr});
      expect(
        (await cache.markersFor(_me))
            .where((m) => m.dataset == ReportingDataset.revenue)
            .single
            .generation,
        5000,
      );
      expect(await revenueGross(_hki, _june()), Money.zero);

      // Hotel Krishna is granted. Its year has never been certified for this person, and
      // its sale sits far below Crystal Canopy's watermark — further than the safety
      // overlap, so the overlap cannot rescue a wrong choice here.
      gateway.visibleUnits = {_ccr, _hki};
      gateway.asked.clear();
      await run(units: {_ccr, _hki});

      expect(
        gateway.asked.first.since,
        0,
        reason:
            'the watermark is the LOWEST any requested scope has reached, and a scope '
            'with no marker takes it to zero. Taking the highest would ask for changes '
            'since a point Hotel Krishna never reached, and every document written '
            'below it would be missed — a gap no later run can notice, because the '
            'marker would say they had arrived',
      );
      expect(
        await revenueGross(_hki, _june()),
        Money.fromRupees(52000),
        reason:
            'the newly granted property is complete, not complete-from-now. This is the '
            'case that makes the minimum load-bearing',
      );
      expect(await revenueGross(_ccr, _june()), Money.fromRupees(100000));
    });
  });

  group('coverage is a conjunction', () {
    Future<ReportingCoverage> coverageOf(ReportRange range) async =>
        (await MarkerCoverage.load(cache, _me)).coverageFor(
          businessUnitId: _ccr,
          range: range,
          side: ReportingDatasetSide.revenue,
        );

    test('an empty year is complete when it was certified', () async {
      await run(units: {_ccr});
      expect(
        await coverageOf(_june()),
        ReportingCoverage.complete,
        reason:
            'a fully synchronised month with no trade is complete and reports zero. '
            'That is the distinction a row count cannot make (D-106, D-108)',
      );
    });

    test('a range crossing 1 April needs both years', () async {
      await run(units: {_ccr}, years: [fy2026]);
      final crossing =
          (CustomRangePeriod(
                    from: BusinessDate.of(2026, 3, 20),
                    to: BusinessDate.of(2026, 4, 10),
                  ).resolve()
                  as ReportRangeResolved)
              .range;
      expect(
        await coverageOf(crossing),
        ReportingCoverage.notDownloaded,
        reason:
            'FY2025 was never certified, and the far side of 1 April is exactly the one '
            'retention prunes first',
      );

      await run(units: {_ccr}, years: [fy2025, fy2026]);
      expect(await coverageOf(crossing), ReportingCoverage.complete);
    });

    test('an uncertified property is not covered by a certified one', () async {
      await run(units: {_ccr});
      final markers = await MarkerCoverage.load(cache, _me);
      expect(
        markers.coverageFor(
          businessUnitId: _hki,
          range: _june(),
          side: ReportingDatasetSide.revenue,
        ),
        ReportingCoverage.notDownloaded,
      );
    });
  });

  group('retention keeps current and previous, and what was asked for', () {
    test('an older year is pruned and the retained ones are not', () async {
      gateway.putRevenue(
        'rev-old',
        changeSeq: 50,
        components: [
          _component(
            id: 'c-old',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2024-06-15',
            gross: 100,
            tax: 0,
          ),
        ],
      );
      await run(units: {_ccr}, years: [const FinancialYear(2024), fy2026]);

      final pruned = await ReportingRetention(
        cache,
      ).prune(ownerUserId: _me, today: BusinessDate.of(2026, 9, 7));
      expect(pruned, [2024]);

      final years = (await cache.markersFor(_me)).map((m) => m.financialYear);
      expect(years.toSet(), {2026});
      expect(
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM reporting_revenue_contributions '
                  'WHERE financial_year = 2024',
                )
                .getSingle())
            .read<int>('n'),
        0,
      );
    });

    test('a year fetched on demand survives the sweep', () async {
      await run(
        units: {_ccr},
        years: [const FinancialYear(2024)],
        onDemand: true,
      );
      final pruned = await ReportingRetention(
        cache,
      ).prune(ownerUserId: _me, today: BusinessDate.of(2026, 9, 7));
      expect(
        pruned,
        isEmpty,
        reason:
            'somebody deliberately fetched it. Deleting it under them would make the '
            'older-range workflow useless in the one case it exists for',
      );
    });

    test(
      'an older year nobody fetched reports notDownloaded rather than zero',
      () async {
        await run(units: {_ccr}, years: [fy2026]);
        final coverage = await MarkerCoverage.load(cache, _me);
        final oldJune =
            (const MonthPeriod(2024, 6).resolve() as ReportRangeResolved).range;
        expect(
          coverage.coverageFor(
            businessUnitId: _ccr,
            range: oldJune,
            side: ReportingDatasetSide.revenue,
          ),
          ReportingCoverage.notDownloaded,
          reason:
              'outside retention the honest answer is "not here", never a confident zero '
              'over an empty table',
        );
      },
    );
  });

  // ── One report is one snapshot (D-188) ───────────────────────────────────────────────
  //
  // The permanent regression against the Slice 4 as-of defect. Before the corrective a
  // report's figures could be assembled from segments certified by *different*
  // synchronisation runs, and nothing in the cache could tell: each marker was internally
  // consistent, every figure was canonical, and the report dated itself from whichever
  // number a caller reached for. `min(generation)` was the obvious thing to reach for and
  // is the thing these tests exist to keep prohibited.
  //
  // The seam is deliberate and deterministic — two explicit `synchronise` calls — so
  // nothing here depends on a sleep, a clock or a race.
  group('one report is one snapshot', () {
    Future<ReportEnvelope> reportOver(
      Set<String> units, {
      ReportingPeriod period = const MonthPeriod(2026, 6),
    }) async {
      final engine = LocalReportingEngine(
        CachedReportingSource(
          cache: cache,
          ownerUserId: _me,
          coverage: await MarkerCoverage.load(cache, _me),
        ),
      );
      return engine.report(
        ReportRequest(period: period, scope: ReportingScope(units)),
      );
    }

    setUp(() {
      gateway.putRevenue(
        'rev-ccr',
        changeSeq: 100,
        components: [
          _component(
            id: 'c-ccr',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-06-15',
            gross: 10000000,
            tax: 476190,
          ),
        ],
      );
      gateway.putExpense(
        'exp-ccr',
        changeSeq: 101,
        lines: [
          _line(
            id: 'l-ccr',
            allocation: 'a-ccr',
            unit: _ccr,
            pnlDate: '2026-06-20',
            amount: 4500000,
          ),
        ],
      );
      gateway.putRevenue(
        'rev-hki',
        changeSeq: 102,
        components: [
          _component(
            id: 'c-hki',
            unit: _hki,
            category: 'cat-room',
            pnlDate: '2026-06-18',
            gross: 5200000,
            tax: 247619,
          ),
        ],
      );
      gateway.putExpense(
        'exp-hki',
        changeSeq: 103,
        lines: [
          _line(
            id: 'l-hki',
            allocation: 'a-hki',
            unit: _hki,
            pnlDate: '2026-06-22',
            amount: 3000000,
          ),
        ],
      );
    });

    test('one run certifies every segment into the same snapshot', () async {
      await run(units: {_ccr, _hki}, years: [fy2026]);

      final markers = await cache.markersFor(_me);
      expect(
        markers.length,
        4,
        reason: 'two properties x two datasets, all from the one run',
      );
      expect(
        markers.map((m) => m.snapshotId).toSet(),
        {'snapshot-1'},
        reason:
            'one statement answered both datasets for both properties, so every marker '
            'names the one snapshot they jointly represent',
      );
      expect(
        markers.map((m) => m.serverConfirmedAt).toSet(),
        {gateway.serverTime},
        reason:
            'the time comes from the same answer as the facts — never a second call, and '
            'never the device clock',
      );

      final envelope = await reportOver({_ccr, _hki});
      expect(envelope.outcome, isA<PnlComputed>());
      expect(
        envelope.freshness?.state,
        ReportingFreshnessState.synchronised,
        reason: 'every required segment provably belongs to one snapshot',
      );
      expect(envelope.freshness?.synchronisedAt, gateway.serverTime);
      expect(
        envelope.freshness?.evidence.snapshotId,
        'snapshot-1',
        reason:
            'the evidence is the server issued identity, not a generation and not a '
            'device timestamp',
      );
    });

    test('two runs cannot be presented as one snapshot', () async {
      // The mixed-generation scenario, built the way it happens: a report needs two
      // properties and they were certified by two runs. Both figures are canonical. The
      // pair is not a snapshot of anything, because no instant existed at which the
      // server held exactly these two states together.
      await run(units: {_ccr}, years: [fy2026]);
      gateway.serverTime = DateTime.utc(2027, 1, 14, 11, 45);
      await run(units: {_hki}, years: [fy2026]);

      expect(
        (await cache.markersFor(_me)).map((m) => m.snapshotId).toSet(),
        {'snapshot-1', 'snapshot-2'},
        reason:
            'two runs, two snapshots — the state the corrective must detect',
      );

      final consolidated = await reportOver({_ccr, _hki});
      expect(
        consolidated.outcome,
        isA<PnlComputed>(),
        reason:
            'the figures are canonical and the report is produced. What is withheld is '
            'the claim about when, not the money (D-070)',
      );
      expect(
        consolidated.revenueCoverage,
        ReportingCoverage.complete,
        reason:
            'availability is not freshness — both properties did synchronise',
      );
      expect(consolidated.expenseCoverage, ReportingCoverage.complete);
      expect(
        consolidated.freshness,
        isNull,
        reason:
            'a consolidated total assembled from two moments is a report of neither, and '
            'dating it from either one would name a state the cache cannot reproduce',
      );

      // And the per-property reports are unaffected: each property IS one snapshot.
      final ccr = await reportOver({_ccr});
      expect(ccr.freshness?.evidence.snapshotId, 'snapshot-1');
      expect(ccr.freshness?.synchronisedAt, DateTime.utc(2027, 1, 14, 9, 30));
      final hki = await reportOver({_hki});
      expect(hki.freshness?.evidence.snapshotId, 'snapshot-2');
      expect(hki.freshness?.synchronisedAt, DateTime.utc(2027, 1, 14, 11, 45));
    });

    test('an identical delta cursor is not evidence of one snapshot', () async {
      // **The permanent regression against `min(generation)`.** Nothing changed on the
      // server between the two runs, so every marker is certified to the *same*
      // generation — a coherence rule keyed on the cursor, by min, by max or by equality,
      // would call this one snapshot. It is not one: the two properties were read at two
      // moments, and a sequence value is allocated when a row is written rather than when
      // a transaction becomes visible, so it orders work and dates nothing.
      gateway.rows[ReportingDataset.revenue]!.clear();
      gateway.rows[ReportingDataset.expense]!.clear();

      await run(units: {_ccr}, years: [fy2026]);
      await run(units: {_hki}, years: [fy2026]);

      final markers = await cache.markersFor(_me);
      expect(
        markers.map((m) => m.generation).toSet().length,
        1,
        reason:
            'the fixture is only a control if the generations really are identical — '
            'otherwise the assertion below could pass for the wrong reason',
      );
      expect(markers.map((m) => m.snapshotId).toSet().length, 2);

      expect(
        (await reportOver({_ccr, _hki})).freshness,
        isNull,
        reason:
            'equal cursors, two snapshots. Coherence is membership of one authoritative '
            'snapshot and is never derived from a generation (D-188)',
      );
    });

    test('a range crossing 1 April needs both years from one run', () async {
      gateway.putRevenue(
        'rev-march',
        changeSeq: 200,
        components: [
          _component(
            id: 'c-march',
            unit: _ccr,
            category: 'cat-restaurant',
            pnlDate: '2026-03-20',
            gross: 2100000,
            tax: 100000,
          ),
        ],
      );
      await run(units: {_ccr}, years: [fy2025]);
      await run(units: {_ccr}, years: [fy2026]);

      final spanning = await reportOver(
        {_ccr},
        period: CustomRangePeriod(
          from: BusinessDate.of(2026, 3, 1),
          to: BusinessDate.of(2026, 6, 30),
        ),
      );
      expect(
        spanning.outcome,
        isA<PnlComputed>(),
        reason: 'both years are certified, so both sides are available',
      );
      expect(
        spanning.freshness,
        isNull,
        reason:
            'the two financial years were certified by different runs, so the range they '
            'jointly cover belongs to no single snapshot',
      );

      // One run over both years, and the same range is datable again.
      await run(units: {_ccr}, years: [fy2025, fy2026]);
      final refreshed = await reportOver(
        {_ccr},
        period: CustomRangePeriod(
          from: BusinessDate.of(2026, 3, 1),
          to: BusinessDate.of(2026, 6, 30),
        ),
      );
      expect(refreshed.freshness?.state, ReportingFreshnessState.synchronised);
    });

    test(
      'a marker from before the corrective proves nothing, and the figures stand',
      () async {
        await run(units: {_ccr}, years: [fy2026]);
        // A device part-way through the corrective: the expense side was certified before
        // anything recorded which snapshot facts came from, and the revenue side after.
        // Both sets of figures are canonical, and only one of them can name a snapshot. A
        // segment that cannot name one must **refuse** the claim rather than be skipped
        // over, because skipping dates the report from whichever subset happened to carry
        // evidence — a stronger statement than the cache can support.
        await db.customStatement(
          "update reporting_coverage_markers set snapshot_id = null "
          "where dataset = 'expense'",
        );

        final envelope = await reportOver({_ccr});
        expect(
          (envelope.outcome as PnlComputed).result.netSales,
          Money.fromPaise(9523810),
          reason:
              'freshness is not availability and is not arithmetic. Withholding the claim '
              'must not move a single paisa',
        );
        expect(envelope.revenueCoverage, ReportingCoverage.complete);
        expect(
          envelope.freshness,
          isNull,
          reason:
              'a marker that cannot name a snapshot cannot be shown to belong to one, and '
              'assuming it does is the defect rather than a convenience',
        );
      },
    );
  });
}

/// Drops the snapshot call, so a failed run can be observed without pretending a network
/// failure is selective by dataset name.
final class _HalfFailingGateway extends ReportingGateway {
  _HalfFailingGateway(this._delegate, this._shouldFail)
    : super(SupabaseClient('http://localhost', 'test-key'));

  final _FakeReportingGateway _delegate;
  final bool Function() _shouldFail;

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> snapshot({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
  }) async {
    if (_shouldFail()) return RemoteUnreachable(RemoteFailure.offline);
    return _delegate.snapshot(
      businessUnitIds: businessUnitIds,
      revenueSince: revenueSince,
      expenseSince: expenseSince,
    );
  }
}
