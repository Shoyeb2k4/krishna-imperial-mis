/// The settlement preview: authority first, evidence second, the OA-2 calculator last —
/// and every refusal a different reason, never ₹0.
///
/// Phase 5 OA-3. Driven through the **real** `ReportingEngine`, `Pnl.compute`, the real
/// owner sync and repository over SQLite, and `OwnerSettlement.compute`. The only double is
/// the reporting-facts port, which sums fixture rows by range the way a source sums
/// canonical rows; everything downstream of it is production code.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/sync/canonical_cache_lock.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_preview.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_contribution.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/revenue/revenue_contribution.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import '../support/cache_principal.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _units = {_ccr, _hki};

typedef _Row = ({String unit, BusinessDate date, int net, int expense});

/// A reporting-facts source over fixture rows. It sums, as a source does; the engine and
/// `domain/finance` do everything after that.
final class _Facts implements ReportingFactsSource {
  _Facts(this.rows, {this.coverage = const {}, bool withEvidence = true})
    : evidence = withEvidence
          ? ReportingSnapshotEvidence(
              snapshotId: 'rep-snap',
              serverConfirmedAt: DateTime.utc(2026, 7, 1, 8),
            )
          : null;

  final List<_Row> rows;
  final Map<String, ReportingCoverage> coverage;
  final ReportingSnapshotEvidence? evidence;
  int calls = 0;

  @override
  Future<UnitReportingFacts> factsFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingScope scope,
  }) async {
    calls++;
    final state = coverage[businessUnitId] ?? ReportingCoverage.complete;
    if (state != ReportingCoverage.complete) {
      return UnitReportingFacts.uncovered(
        businessUnitId: businessUnitId,
        coverage: state,
      );
    }
    var net = 0;
    var expense = 0;
    var n = 0;
    for (final row in rows) {
      if (row.unit == businessUnitId && range.contains(row.date)) {
        net += row.net;
        expense += row.expense;
        n++;
      }
    }
    return UnitReportingFacts(
      businessUnitId: businessUnitId,
      revenueCoverage: ReportingCoverage.complete,
      expenseCoverage: ReportingCoverage.complete,
      revenue: RevenueTotals(
        gross: Money.fromPaise(net),
        tax: Money.zero,
        net: Money.fromPaise(net),
        contributions: n,
      ),
      expenses: ExpenseTotals(
        amount: Money.fromPaise(expense),
        contributions: n,
      ),
    );
  }

  @override
  Future<ReportingScopeFacts> factsForScope({
    required ReportRange range,
    required ReportingScope scope,
  }) async => ReportingScopeFacts(
    units: [
      for (final unit in scope.ordered)
        await factsFor(businessUnitId: unit, range: range, scope: scope),
    ],
    snapshot: evidence,
  );
}

/// Fails the test the moment anything reads it. Authority is decided before any read.
final class _Untouchable implements ReportingFactsSource {
  @override
  Future<UnitReportingFacts> factsFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingScope scope,
  }) => throw StateError('the P&L was read before authority was decided');

  @override
  Future<ReportingScopeFacts> factsForScope({
    required ReportRange range,
    required ReportingScope scope,
  }) => throw StateError('the P&L was read before authority was decided');
}

class _OwnerSource implements OwnerSnapshotSource {
  _OwnerSource(this.body);
  Map<String, dynamic> body;
  @override
  Future<RemoteOutcome<Map<String, dynamic>>> fetchSettlementSnapshot() async =>
      RemoteOk(body);
}

Map<String, dynamic> _movement(
  String id, {
  required String owner,
  required String date,
  required int amount,
  String type = 'withdrawal',
}) => {
  'id': id,
  'org_id': 'org-1',
  'business_unit_id': _hki,
  'owner_id': owner,
  'txn_number': 'KI-OWN-$id',
  'financial_year': '26-27',
  'business_date': date,
  'business_date_source': 'derived',
  'pnl_period_key': date.substring(0, 7),
  'movement_type': type,
  'direction': 'debit',
  'amount_minor': amount,
  'family_member_id': null,
  'collected_by_family_member_id': null,
  'nc_bill_reference': null,
  'reference_number': null,
  'remarks': null,
  'reason': null,
  'created_by': 'someone',
  'captured_at': '${date}T10:00:00.000Z',
  'row_version': 1,
  'change_seq': 1,
  'voided_at': null,
  'void_reason': null,
};

Map<String, dynamic> _ownerSnapshot({
  String? start = '2026-04-01',
  List<Map<String, dynamic>> movements = const [],
  int bpA = 5000,
  int bpB = 5000,
}) => {
  'snapshot_id': 'own-snap',
  'server_time': '2026-07-01T09:00:00.000Z',
  'settlement_authorised': true,
  'ownership_start_date': start,
  'movements': movements,
  'owners': [
    for (final o in const ['owner-a', 'owner-b'])
      {
        'id': o,
        'org_id': 'org-1',
        'code': o.toUpperCase(),
        'display_name': o == 'owner-a' ? 'Partner Alpha' : 'Partner Beta',
        'active': true,
        'archived_at': null,
        'row_version': 1,
        'change_seq': 1,
      },
  ],
  'ownership_shares': [
    for (final (o, bp) in [('owner-a', bpA), ('owner-b', bpB)])
      {
        'id': 'share-$o',
        'org_id': 'org-1',
        'owner_id': o,
        'share_basis_points': bp,
        'effective_from': '2026-04-01',
        'effective_to': null,
        'note': null,
        'row_version': 1,
        'change_seq': 1,
      },
  ],
  'family_members': const [],
};

/// The Owner bundle, as the server grants it: every capability, unscoped.
final _owner = Principal(
  userId: 'user-1',
  grants: [for (final c in RoleTemplates.owner) CapabilityGrant(c)],
);

/// Operating Profit by month: April 10,00,000 · May 20,00,000 · June 30,00,001 paise,
/// split across the two properties.
final _rows = <_Row>[
  (
    unit: _ccr,
    date: BusinessDate.of(2026, 4, 10),
    net: 800000,
    expense: 200000,
  ),
  (
    unit: _hki,
    date: BusinessDate.of(2026, 4, 20),
    net: 600000,
    expense: 200000,
  ),
  (unit: _ccr, date: BusinessDate.of(2026, 5, 10), net: 1500000, expense: 0),
  (unit: _hki, date: BusinessDate.of(2026, 5, 20), net: 500000, expense: 0),
  (unit: _ccr, date: BusinessDate.of(2026, 6, 10), net: 2000001, expense: 0),
  (
    unit: _hki,
    date: BusinessDate.of(2026, 6, 20),
    net: 1500000,
    expense: 500000,
  ),
];

void main() {
  late AppDatabase db;
  late OwnerSettlementRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = OwnerSettlementRepository(
      db,
      principal: canonicalCachePrincipal('user-1'),
    );
  });
  tearDown(() => db.close());

  Future<void> synchronise(Map<String, dynamic> body) async {
    final result = await OwnerSettlementSync(
      database: db,
      gateway: _OwnerSource(body),
      ownerUserId: 'user-1',
    ).synchronise();
    expect(result, isA<OwnerSettlementSynchronised>());
  }

  OwnerSettlementPreviewService service({
    Principal? principal,
    ReportingFactsSource? source,
  }) => OwnerSettlementPreviewService(
    lock: CanonicalCacheLock(),
    repository: repository,
    reporting: LocalReportingEngine(source ?? _Facts(_rows)),
    principal: principal ?? _owner,
  );

  Future<OwnerSettlementPreview> june({
    Principal? principal,
    ReportingFactsSource? source,
  }) => service(
    principal: principal,
    source: source,
  ).preview(year: 2026, month: 6, businessUnitIds: _units);

  OwnerSettlementUnavailableReason reasonOf(OwnerSettlementPreview p) =>
      (p as OwnerSettlementPreviewUnavailable).reason;

  // ═══════════════════════════════════════════════════════════════════════════
  group('authority is decided before anything is read (OA-3 Q2)', () {
    test('the Accountant bundle holds no owner settlement access', () async {
      await synchronise(_ownerSnapshot());
      final accountant = Principal(
        userId: 'user-1',
        grants: [
          for (final c in RoleTemplates.accountant)
            CapabilityGrant(c, businessUnitId: _ccr),
        ],
      );
      expect(
        reasonOf(await june(principal: accountant, source: _Untouchable())),
        OwnerSettlementUnavailableReason.notAuthorised,
        reason:
            'even with owner_ledger.view and a synchronised cache on this device, the '
            'settlement is closed to the Accountant by ruling',
      );
    });

    test('the Manager and Data Entry bundles hold none either', () async {
      for (final bundle in [RoleTemplates.manager, RoleTemplates.dataEntry]) {
        final principal = Principal(
          userId: 'user-1',
          grants: [
            for (final c in bundle) CapabilityGrant(c, businessUnitId: _hki),
          ],
        );
        expect(
          reasonOf(await june(principal: principal, source: _Untouchable())),
          OwnerSettlementUnavailableReason.notAuthorised,
        );
      }
    });

    test('an anonymous principal is refused, not shown a zero', () async {
      expect(
        reasonOf(
          await june(principal: Principal.anonymous, source: _Untouchable()),
        ),
        OwnerSettlementUnavailableReason.notAuthorised,
      );
    });

    test(
      'owner_settlement.view without the consolidated P&L is refused as such',
      () async {
        // A reader granted the settlement but holding the P&L only per property: two
        // scoped grants never add up to the organisation (D-187), and a partial owner
        // settlement must never be produced (Q2).
        final principal = Principal(
          userId: 'user-1',
          grants: [
            const CapabilityGrant(Capability.ownerSettlementView),
            const CapabilityGrant(Capability.ownerLedgerView),
            for (final unit in _units) ...[
              CapabilityGrant(Capability.reportsView, businessUnitId: unit),
              CapabilityGrant(Capability.revenueView, businessUnitId: unit),
              CapabilityGrant(Capability.expenseViewAll, businessUnitId: unit),
            ],
          ],
        );
        expect(
          reasonOf(await june(principal: principal, source: _Untouchable())),
          OwnerSettlementUnavailableReason.reportingNotAuthorised,
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('evidence is required, and a missing piece is named', () {
    test('no owner history on this device', () async {
      expect(
        reasonOf(await june(source: _Untouchable())),
        OwnerSettlementUnavailableReason.ownerHistoryNotDownloaded,
      );
    });

    test('the start date is not configured', () async {
      await synchronise(_ownerSnapshot(start: null));
      expect(
        reasonOf(await june(source: _Untouchable())),
        OwnerSettlementUnavailableReason.startDateNotConfigured,
        reason:
            'never the financial-year start, never 2026-04-01 because the tax model uses '
            'it: the production date is outstanding (OA-3 Q1)',
      );
    });

    test('a month before the start date', () async {
      await synchronise(_ownerSnapshot(start: '2026-07-01'));
      expect(
        reasonOf(await june(source: _Untouchable())),
        OwnerSettlementUnavailableReason.beforeStartDate,
      );
    });

    test('the P&L for a property is not downloaded', () async {
      await synchronise(_ownerSnapshot());
      expect(
        reasonOf(
          await june(
            source: _Facts(
              _rows,
              coverage: {_hki: ReportingCoverage.notDownloaded},
            ),
          ),
        ),
        OwnerSettlementUnavailableReason.reportingNotDownloaded,
        reason:
            'one property missing refuses the organisation, never ₹0 (D-163)',
      );
    });

    test('the P&L for a property is not authorised', () async {
      await synchronise(_ownerSnapshot());
      expect(
        reasonOf(
          await june(
            source: _Facts(
              _rows,
              coverage: {_ccr: ReportingCoverage.notAuthorised},
            ),
          ),
        ),
        OwnerSettlementUnavailableReason.reportingNotAuthorised,
      );
    });

    test('no property to consolidate', () async {
      await synchronise(_ownerSnapshot());
      expect(
        reasonOf(
          await service(
            source: _Untouchable(),
          ).preview(year: 2026, month: 6, businessUnitIds: const {}),
        ),
        OwnerSettlementUnavailableReason.reportingNotDownloaded,
      );
    });

    test('a vector that is not the V1 pair (D-204)', () async {
      await synchronise(_ownerSnapshot(bpA: 6000, bpB: 4000));
      expect(
        reasonOf(await june()),
        OwnerSettlementUnavailableReason.ownershipUnavailable,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('a computed preview is the OA-2 result, unmodified', () {
    test('a positive position: the business owes the owner', () async {
      await synchronise(
        _ownerSnapshot(
          movements: [
            _movement(
              'w1',
              owner: 'owner-a',
              date: '2026-06-12',
              amount: 500000,
            ),
          ],
        ),
      );

      final ready = await june() as OwnerSettlementPreviewReady;
      final s = ready.statement;

      // April + May = 30,00,000 → 15,00,000 each before June. Through June 60,00,001 →
      // 30,00,000 each, remainder 1 paisa belonging to neither.
      expect(s.periodKey, '2026-06');
      expect(s.operatingProfit, Money.fromPaise(3000001));
      expect(s.cumulativeOperatingProfit, Money.fromPaise(6000001));
      expect(s.undistributedRemainder, Money.fromPaise(1));
      expect(s.entitlementReconciles, isTrue);
      expect(s.linesReconcile, isTrue);

      final a = s.lines.firstWhere((l) => l.ownerId == 'owner-a');
      expect(a.openingPosition, Money.fromPaise(1500000));
      expect(a.profitEntitlement, Money.fromPaise(1500000));
      expect(a.withdrawals, Money.fromPaise(500000));
      expect(a.closingPosition, Money.fromPaise(2500000));

      final b = s.lines.firstWhere((l) => l.ownerId == 'owner-b');
      expect(b.closingPosition, Money.fromPaise(3000000));

      expect(s.operatingProfitByBusinessUnit, {
        _ccr: Money.fromPaise(2000001),
        _hki: Money.fromPaise(1000000),
      });
      expect(ready.ownerNames, {
        'owner-a': 'Partner Alpha',
        'owner-b': 'Partner Beta',
      });
    });

    test(
      'a negative position: recoverable from the owner, never clamped',
      () async {
        await synchronise(
          _ownerSnapshot(
            movements: [
              _movement(
                'w1',
                owner: 'owner-b',
                date: '2026-06-12',
                amount: 4000000,
              ),
            ],
          ),
        );
        final ready = await june() as OwnerSettlementPreviewReady;
        final b = ready.statement.lines.firstWhere(
          (l) => l.ownerId == 'owner-b',
        );
        expect(b.closingPosition, Money.fromPaise(-1000000));
      },
    );

    test('a real zero is a computed statement, not a refusal', () async {
      await synchronise(_ownerSnapshot());
      final ready =
          await june(source: _Facts(const [])) as OwnerSettlementPreviewReady;
      expect(ready.statement.operatingProfit, Money.zero);
      for (final line in ready.statement.lines) {
        expect(line.closingPosition, Money.zero);
      }
      expect(
        ready.statement.operatingProfitByBusinessUnit.values,
        everyElement(Money.zero),
      );
    });

    test('the first month needs no "before" range, and asks for none', () async {
      await synchronise(_ownerSnapshot(start: '2026-06-01'));
      final source = _Facts(_rows);
      final ready = await june(source: source) as OwnerSettlementPreviewReady;

      final a = ready.statement.lines.first;
      expect(
        a.openingPosition,
        Money.zero,
        reason: 'nothing precedes the start date, by definition',
      );
      expect(
        ready.statement.cumulativeOperatingProfit,
        Money.fromPaise(3000001),
      );
      // One consolidated read to the month end, then one per property: nothing for a
      // range before the start, which would have been a reversed range.
      expect(source.calls, 2 + 2);
    });

    test(
      'each half keeps its own evidence, and none is manufactured',
      () async {
        await synchronise(_ownerSnapshot());
        final ready = await june() as OwnerSettlementPreviewReady;

        expect(ready.ownerHistory.snapshotId, 'own-snap');
        expect(
          ready.ownerHistory.serverConfirmedAt,
          DateTime.utc(2026, 7, 1, 9),
        );
        expect(ready.reportingFreshness!.evidence.snapshotId, 'rep-snap');
        expect(ready.ownershipStartDate, BusinessDate.of(2026, 4, 1));
      },
    );

    test(
      'a P&L with no single synchronisation carries no freshness claim',
      () async {
        await synchronise(_ownerSnapshot());
        final ready =
            await june(source: _Facts(_rows, withEvidence: false))
                as OwnerSettlementPreviewReady;
        expect(ready.reportingFreshness, isNull);
      },
    );
  });
}
