/// D-227 — does the owner-settlement path share a coherent boundary with the P&L?
///
/// Phase 5 Slice 11. Slice 8 serialised the P&L surface's cache reads with its own
/// synchronisation. The owner-settlement refresher and the settlement preview were built
/// afterwards and took no part in that: the preview reads the P&L several separate times,
/// and the refresher writes the reporting cache, each without the other.
///
/// The ruling was to prove or disprove it, not to add a lock because a decision number
/// existed. So the tests below construct the two interleavings deterministically and
/// compare each result, in paise, against a **coherent before** and a **coherent after**
/// worked out by hand from the fixture rows — never from production arithmetic. A result
/// matching neither is a report of a moment that never existed.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/reporting/local_reporting_engine.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_preview.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/canonical_cache_lock.dart';
import 'package:krishna_mis/data/sync/owner_settlement_refresh.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/pnl.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import '../support/cache_principal.dart';
import '../support/pnl_fixture.dart';
import 'owner_settlement_sync_test.dart' show snapshot;

const _me = 'user-me';

/// A reporting-facts source that pauses once, at a chosen point, over the real cached source.
///
/// It mixes in the same per-unit composition the cached source uses, so the pause can sit
/// between two properties inside one consolidated read — the finest interleaving a P&L read
/// has — or at the end of a whole read.
final class _Paused with PerUnitReportingFacts implements ReportingFactsSource {
  _Paused(this.inner, {this.afterUnitReads, this.afterScopeReads});

  final CachedReportingSource inner;
  final int? afterUnitReads;
  final int? afterScopeReads;

  final reached = Completer<void>();
  final release = Completer<void>();
  var _units = 0;
  var _scopes = 0;

  Future<void> _maybePause(int count, int? at) async {
    if (at == null || count != at) return;
    reached.complete();
    await release.future;
  }

  @override
  Future<UnitReportingFacts> factsFor({
    required String businessUnitId,
    required ReportRange range,
    required ReportingScope scope,
  }) async {
    final facts = await inner.factsFor(
      businessUnitId: businessUnitId,
      range: range,
      scope: scope,
    );
    await _maybePause(++_units, afterUnitReads);
    return facts;
  }

  @override
  Future<ReportingScopeFacts> factsForScope({
    required ReportRange range,
    required ReportingScope scope,
  }) async {
    final facts = await super.factsForScope(range: range, scope: scope);
    await _maybePause(++_scopes, afterScopeReads);
    return facts;
  }

  @override
  Future<ReportingSnapshotEvidence?> snapshotEvidenceFor({
    required ReportRange range,
    required ReportingScope scope,
  }) => inner.snapshotEvidenceFor(range: range, scope: scope);
}

class _OwnerSource implements OwnerSnapshotSource {
  @override
  Future<RemoteOutcome<Map<String, dynamic>>> fetchSettlementSnapshot() async =>
      RemoteOk(snapshot(ownershipStartDate: '2026-05-01'));
}

/// The coherent states, worked out by hand. June 2026, consolidated, start 1 May.
///
///  BEFORE  May:  CCR sale net 20,000.00
///          June: HKI sale net 10,000.00, CCR cost 4,000.00
///          June profit 6,000.00 · cumulative to 30 June 26,000.00
///
///  AFTER   the May sale is corrected into June, and HKI records a 3,000.00 June cost
///          May:  nothing
///          June: 20,000.00 + 10,000.00 − 4,000.00 − 3,000.00 = 23,000.00
///          June profit 23,000.00 · cumulative to 30 June 23,000.00
const _beforeJune = 600000;
const _beforeCumulative = 2600000;
const _afterJune = 2300000;
const _afterCumulative = 2300000;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  late AppDatabase db;
  late ReportingCache cache;
  late FakeReportingGateway gateway;
  late ReportingSync reportingSync;
  late OwnerSettlementRepository repository;
  late Map<String, dynamic> maySale;

  final today = BusinessDate.of(2026, 9, 19);
  final fy = FinancialYear.of(today);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    cache = ReportingCache(db);
    gateway = FakeReportingGateway();
    maySale = pnlSale(pnlCcr, '2026-05-10', gross: 2100000, tax: 100000);
    gateway
      ..revenue.add(maySale)
      ..revenue.add(pnlSale(pnlHki, '2026-06-12', gross: 1050000, tax: 50000))
      ..expense.add(pnlCost(pnlCcr, '2026-06-11', 400000));
    reportingSync = ReportingSync(
      cache: cache,
      gateway: gateway,
      ownerUserId: _me,
      orgId: 'test-org',
    );
    repository = OwnerSettlementRepository(
      db,
      principal: canonicalCachePrincipal(_me),
    );
    await OwnerSettlementSync(
      database: db,
      gateway: _OwnerSource(),
      ownerUserId: _me,
    ).synchronise();
    final first = await reportingSync.synchronise(
      businessUnitIds: {pnlCcr, pnlHki},
      years: [fy],
    );
    expect(first.isComplete, isTrue);
  });

  tearDown(() => db.close());

  /// The server moves: the May sale is corrected into June, and HKI records a June cost.
  void serverMoves() {
    gateway.revenue
      ..remove(maySale)
      ..add({
        ...pnlSale(pnlCcr, '2026-06-10', gross: 2100000, tax: 100000),
        'id': maySale['id'],
        'revenue_entry_id': maySale['revenue_entry_id'],
      });
    gateway.expense.add(pnlCost(pnlHki, '2026-06-15', 300000));
  }

  Future<CachedReportingSource> cachedSource() async => CachedReportingSource(
    cache: cache,
    principal: canonicalCachePrincipal(_me),
    coverage: await MarkerCoverage.load(cache, _me),
  );

  OwnerSettlementRefresher refresher(CanonicalCacheLock lock) =>
      OwnerSettlementRefresher(
        ownerSync: OwnerSettlementSync(
          database: db,
          gateway: _OwnerSource(),
          ownerUserId: _me,
        ),
        reportingSync: reportingSync,
        repository: repository,
        lock: lock,
      );

  OwnerSettlementPreviewService previewService(
    ReportingFactsSource source,
    CanonicalCacheLock lock,
  ) => OwnerSettlementPreviewService(
    repository: repository,
    reporting: LocalReportingEngine(source),
    principal: canonicalCachePrincipal(_me),
    lock: lock,
  );

  /// Starts [write] while [paused] is holding a read, lets the write run as far as it can,
  /// then releases the read. A write that cannot get past a shared boundary simply does not
  /// finish until the read releases — which is the property being tested, not a timeout.
  Future<void> interleave(_Paused paused, Future<void> Function() write) async {
    await paused.reached.future;
    var finished = false;
    final writing = write().then((_) => finished = true);
    for (var i = 0; i < 200 && !finished; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    paused.release.complete();
    await writing;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  group('the settlement preview against a reporting refresh', () {
    test('coherent references, computed without any interleaving', () async {
      final lock = CanonicalCacheLock();
      final before = await previewService(
        await cachedSource(),
        lock,
      ).preview(year: 2026, month: 6, businessUnitIds: {pnlCcr, pnlHki});
      final ready = before as OwnerSettlementPreviewReady;
      expect(ready.statement.operatingProfit.paise, _beforeJune);
      expect(
        ready.statement.cumulativeOperatingProfit.paise,
        _beforeCumulative,
      );

      serverMoves();
      await refresher(lock).refresh(
        businessUnitIds: {pnlCcr, pnlHki},
        periodEnd: BusinessDate.of(2026, 6, 30),
        today: today,
      );
      final after =
          await previewService(
                await cachedSource(),
                lock,
              ).preview(year: 2026, month: 6, businessUnitIds: {pnlCcr, pnlHki})
              as OwnerSettlementPreviewReady;
      expect(after.statement.operatingProfit.paise, _afterJune);
      expect(after.statement.cumulativeOperatingProfit.paise, _afterCumulative);
    });

    test(
      'a preview paused after its first P&L read is never a mixed snapshot',
      () async {
        final lock = CanonicalCacheLock();
        final paused = _Paused(await cachedSource(), afterScopeReads: 1);

        final previewing = previewService(
          paused,
          lock,
        ).preview(year: 2026, month: 6, businessUnitIds: {pnlCcr, pnlHki});

        serverMoves();
        await interleave(
          paused,
          () => refresher(lock).refresh(
            businessUnitIds: {pnlCcr, pnlHki},
            periodEnd: BusinessDate.of(2026, 6, 30),
            today: today,
          ),
        );

        final result = (await previewing) as OwnerSettlementPreviewReady;
        final june = result.statement.operatingProfit.paise;
        final cumulative = result.statement.cumulativeOperatingProfit.paise;
        final byUnit = result.statement.operatingProfitByBusinessUnit.values
            .fold(0, (sum, money) => sum + money.paise);

        final coherentBefore =
            june == _beforeJune &&
            cumulative == _beforeCumulative &&
            byUnit == _beforeJune;
        final coherentAfter =
            june == _afterJune &&
            cumulative == _afterCumulative &&
            byUnit == _afterJune;
        expect(
          coherentBefore || coherentAfter,
          isTrue,
          reason:
              'the preview read cumulative profit before the refresh and the rest after '
              'it: June $june, cumulative $cumulative, per-property June $byUnit — '
              'matching neither the coherent before ($_beforeJune / $_beforeCumulative) '
              'nor the coherent after ($_afterJune / $_afterCumulative) (D-227)',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('a P&L read against the settlement refresh', () {
    test(
      'a consolidated read paused between properties is never a mixed snapshot',
      () async {
        final lock = CanonicalCacheLock();
        final paused = _Paused(await cachedSource(), afterUnitReads: 1);

        // The P&L surface reads under the shared lock; the settlement refresh writes.
        final reading = lock.run(
          () => LocalReportingEngine(paused).report(
            ReportRequest(
              period: const MonthPeriod(2026, 6),
              scope: ReportingScope({pnlCcr, pnlHki}),
            ),
          ),
        );

        serverMoves();
        await interleave(
          paused,
          () => refresher(lock).refresh(
            businessUnitIds: {pnlCcr, pnlHki},
            periodEnd: BusinessDate.of(2026, 6, 30),
            today: today,
          ),
        );

        final outcome = (await reading).outcome as PnlComputed;
        final profit = outcome.result.operatingProfit.paise;
        expect(
          profit == _beforeJune || profit == _afterJune,
          isTrue,
          reason:
              'one property was read before the settlement refresh and the other after '
              'it: consolidated June profit $profit matches neither $_beforeJune nor '
              '$_afterJune (D-227)',
        );
      },
    );
  });
}
