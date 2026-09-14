/// Document rows beneath a P&L, from the real canonical reporting cache (Phase 5 Slice 10).
///
/// What is real: SQLite, `ReportingCache`, `ReportingSync`, `MarkerCoverage` and
/// `CachedDrilldownSource`. What is substituted: only the server's snapshot answer
/// ([FakeReportingGateway]). Every row reaches the cache the way a real one does — through a
/// synchronisation — so a correction and a void are replacements the synchroniser performs,
/// not rows a test deleted.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/reporting/cached_drilldown_source.dart';
import 'package:krishna_mis/data/reporting/cached_reporting_source.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:krishna_mis/domain/finance/pnl_drilldown.dart';
import 'package:krishna_mis/domain/finance/reporting_period.dart';
import 'package:krishna_mis/domain/finance/reporting_source.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';

import '../support/pnl_fixture.dart';

ReportRange _range(String from, String to) =>
    (CustomRangePeriod(
              from: BusinessDate.tryParse(from)!,
              to: BusinessDate.tryParse(to)!,
            ).resolve()
            as ReportRangeResolved)
        .range;

Principal _principal(String userId, List<CapabilityGrant> grants) =>
    Principal(userId: userId, grants: grants);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late ReportingCache cache;
  late FakeReportingGateway gateway;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cache = ReportingCache(db);
    gateway = FakeReportingGateway();
  });
  tearDown(() => db.close());

  Future<void> sync({
    String owner = pnlMe,
    List<int> years = const [2026],
    bool onDemand = false,
  }) async {
    final report =
        await ReportingSync(
          cache: cache,
          gateway: gateway,
          ownerUserId: owner,
          orgId: 'test-org',
        ).synchronise(
          businessUnitIds: const {pnlCcr, pnlHki},
          years: [for (final y in years) FinancialYear(y)],
          onDemand: onDemand,
        );
    expect(report.outcomes.every((o) => o.isApplied), isTrue);
  }

  Future<CachedDrilldownSource> source({
    String owner = pnlMe,
    List<CapabilityGrant>? grants,
  }) async => CachedDrilldownSource(
    cache: cache,
    principal: _principal(owner, grants ?? pnlD2()),
    coverage: await MarkerCoverage.load(cache, owner),
  );

  final june = _range('2026-06-01', '2026-06-30');
  final ccrScope = ReportingScope.unit(pnlCcr);
  final both = ReportingScope(const {pnlCcr, pnlHki});

  List<T> rowsOf<T>(DrilldownRows<T> rows) => switch (rows) {
    DrilldownRowsAvailable(:final rows) => rows,
    DrilldownRowsUnavailable(:final reason) => fail('unavailable: $reason'),
  };

  ReportingCoverage? refusalOf<T>(DrilldownRows<T> rows) => switch (rows) {
    DrilldownRowsAvailable() => null,
    DrilldownRowsUnavailable(:final reason) => reason,
  };

  Future<List<ExpenseDocumentLine>> kirana(
    CachedDrilldownSource s, {
    ReportRange? range,
    ReportingScope? scope,
  }) async => rowsOf(
    await s.expenseDocuments(
      scope: scope ?? ccrScope,
      range: range ?? june,
      businessUnitId: pnlCcr,
      departmentId: '$pnlCcr-dept',
      sectionId: '$pnlCcr-section',
      categoryId: '$pnlCcr-kirana',
    ),
  );

  Future<List<RevenueDocumentLine>> restaurant(
    CachedDrilldownSource s, {
    ReportRange? range,
  }) async => rowsOf(
    await s.revenueDocuments(
      scope: ccrScope,
      range: range ?? june,
      businessUnitId: pnlCcr,
      revenueCategoryId: '$pnlCcr-restaurant',
    ),
  );

  group('revenue documents', () {
    test('components of one sale are one row, summed exactly', () async {
      final a = pnlSale(pnlCcr, '2026-06-15', gross: 7645000, tax: 364048);
      final b = pnlSale(pnlCcr, '2026-06-15', gross: 3500000, tax: 166667)
        ..['revenue_entry_id'] = a['revenue_entry_id'];
      gateway.revenue.addAll([a, b]);
      await sync();

      final rows = await restaurant(await source());
      expect(rows, hasLength(1));
      expect(rows.single.revenueEntryId, a['revenue_entry_id']);
      expect(rows.single.totals.gross.paise, 11145000);
      expect(rows.single.totals.tax.paise, 530715);
      expect(rows.single.totals.net.paise, 10614285);
      expect(rows.single.totals.contributions, 2);

      // The same rows the category line was summed from: exactly equal.
      final category = (await cache.revenueByCategory(
        ownerUserId: pnlMe,
        businessUnitId: pnlCcr,
        range: june,
      )).single;
      expect(
        PnlDrilldown.revenueChildrenReconcile(
          category.totals,
          rows.map((r) => r.totals),
        ),
        isTrue,
      );
    });

    test('range boundaries are inclusive P&L dates, nothing else', () async {
      gateway.revenue.addAll([
        pnlSale(pnlCcr, '2026-05-31', gross: 100, tax: 5),
        pnlSale(pnlCcr, '2026-06-01', gross: 200, tax: 10),
        pnlSale(pnlCcr, '2026-06-30', gross: 300, tax: 14),
        pnlSale(pnlCcr, '2026-07-01', gross: 400, tax: 19),
      ]);
      await sync();
      final rows = await restaurant(await source());
      expect(
        [for (final r in rows) r.pnlDate.iso],
        ['2026-06-30', '2026-06-01'],
        reason:
            'newest first; the 31 May and 1 July sales belong to other months',
      );
    });

    test('a business-date correction moves the row between periods', () async {
      final sale = pnlSale(pnlCcr, '2026-06-30', gross: 12364200, tax: 588771);
      gateway.revenue.add(sale);
      await sync();
      expect(await restaurant(await source()), hasLength(1));

      sale
        ..['pnl_date'] = '2026-07-01'
        ..['pnl_period_key'] = '2026-07'
        ..['change_seq'] = 9000;
      await sync();
      final s = await source();
      expect(await restaurant(s), isEmpty, reason: 'June no longer holds it');
      final july = await restaurant(
        s,
        range: _range('2026-07-01', '2026-07-31'),
      );
      expect(july.single.revenueEntryId, sale['revenue_entry_id']);
    });

    test('a void removes the document from the bucket', () async {
      final sale = pnlSale(pnlCcr, '2026-06-12', gross: 5000, tax: 238);
      gateway.revenue.add(sale);
      await sync();
      expect(await restaurant(await source()), hasLength(1));
      sale
        ..['voided_at'] = '2026-06-20T10:00:00Z'
        ..['change_seq'] = 9001;
      await sync();
      expect(await restaurant(await source()), isEmpty);
    });
  });

  group('expense documents', () {
    test(
      'two allocation lines of one document in one bucket are one row',
      () async {
        final first = pnlCost(pnlCcr, '2026-06-18', 1845000);
        final second = pnlCost(pnlCcr, '2026-06-18', 420001)
          ..['expense_id'] = first['expense_id'];
        gateway.expense.addAll([first, second]);
        await sync();
        final rows = await kirana(await source());
        expect(rows, hasLength(1));
        expect(rows.single.totals.amount.paise, 2265001);
        expect(rows.single.totals.contributions, 2);
      },
    );

    test('a shared document contributes only this property share', () async {
      final ccr = pnlCost(pnlCcr, '2026-06-18', 2500000);
      final hki = pnlCost(
        pnlHki,
        '2026-06-18',
        3300000,
        category: 'electricity',
      )..['expense_id'] = ccr['expense_id'];
      gateway.expense.addAll([ccr, hki]);
      await sync();
      final rows = await kirana(await source());
      expect(rows.single.expenseId, ccr['expense_id']);
      expect(rows.single.totals.amount.paise, 2500000);
    });

    test(
      'a multi-period document: only contributions inside the range',
      () async {
        final may = pnlCost(pnlCcr, '2026-05-31', 3000000);
        final june_ = pnlCost(pnlCcr, '2026-06-30', 3000000)
          ..['expense_id'] = may['expense_id']
          ..['allocation_id'] = may['allocation_id'];
        gateway.expense.addAll([may, june_]);
        await sync();
        final s = await source();
        final juneRows = await kirana(s);
        expect(juneRows.single.totals.amount.paise, 3000000);
        expect(juneRows.single.spansPeriods, isFalse);

        final both_ = await kirana(
          s,
          range: _range('2026-05-01', '2026-06-30'),
        );
        expect(both_.single.totals.amount.paise, 6000000);
        expect(both_.single.firstPnlDate.iso, '2026-05-31');
        expect(both_.single.lastPnlDate.iso, '2026-06-30');
      },
    );

    test(
      'membership is the P&L date, never the business or payment date',
      () async {
        // June salary recorded on 5 July and paid on 5 July: a June cost (D-016).
        gateway.expense.add(
          pnlCost(pnlCcr, '2026-06-30', 8000000)
            ..['business_date'] = '2026-07-05'
            ..['payment_date'] = '2026-07-05',
        );
        await sync();
        final s = await source();
        expect(await kirana(s), hasLength(1));
        expect(
          await kirana(s, range: _range('2026-07-01', '2026-07-31')),
          isEmpty,
        );
      },
    );

    test('a correction moving the contribution to July leaves June', () async {
      final cost = pnlCost(pnlCcr, '2026-06-25', 450000);
      gateway.expense.add(cost);
      await sync();
      cost
        ..['pnl_date'] = '2026-07-02'
        ..['pnl_period_key'] = '2026-07'
        ..['change_seq'] = 9100;
      await sync();
      final s = await source();
      expect(await kirana(s), isEmpty);
      expect(
        await kirana(s, range: _range('2026-07-01', '2026-07-31')),
        hasLength(1),
      );
    });

    test('a void removes it', () async {
      final cost = pnlCost(pnlCcr, '2026-06-25', 450000);
      gateway.expense.add(cost);
      await sync();
      cost
        ..['voided_at'] = '2026-06-26T10:00:00Z'
        ..['change_seq'] = 9101;
      await sync();
      expect(await kirana(await source()), isEmpty);
    });
  });

  group('authority is the P&L boundary, decided before anything is read', () {
    setUp(() async {
      gateway
        ..revenue.add(pnlSale(pnlCcr, '2026-06-10', gross: 1000, tax: 48))
        ..expense.addAll([
          pnlCost(pnlCcr, '2026-06-11', 500),
          pnlCost(pnlHki, '2026-06-11', 700, category: 'electricity'),
        ]);
      await sync();
    });

    test('a property reader reads their property and not the other', () async {
      final s = await source(grants: pnlD2(pnlCcr));
      expect(await kirana(s), hasLength(1));
      expect(
        refusalOf(
          await s.expenseDocuments(
            scope: ReportingScope.unit(pnlHki),
            range: june,
            businessUnitId: pnlHki,
            departmentId: '$pnlHki-dept',
            sectionId: '$pnlHki-section',
            categoryId: '$pnlHki-electricity',
          ),
        ),
        ReportingCoverage.notAuthorised,
      );
    });

    test(
      'a property outside the report scope is refused, never read',
      () async {
        final s = await source();
        expect(
          refusalOf(
            await s.expenseDocuments(
              scope: ccrScope,
              range: june,
              businessUnitId: pnlHki,
              departmentId: '$pnlHki-dept',
              sectionId: '$pnlHki-section',
              categoryId: '$pnlHki-electricity',
            ),
          ),
          ReportingCoverage.notAuthorised,
        );
      },
    );

    test('expense.view.own does not qualify', () async {
      final s = await source(
        grants: const [
          CapabilityGrant(Capability.reportsView, businessUnitId: pnlCcr),
          CapabilityGrant(Capability.revenueView, businessUnitId: pnlCcr),
          CapabilityGrant(Capability.expenseViewOwn, businessUnitId: pnlCcr),
        ],
      );
      expect(
        refusalOf(
          await s.expenseDocuments(
            scope: ccrScope,
            range: june,
            businessUnitId: pnlCcr,
            departmentId: '$pnlCcr-dept',
            sectionId: '$pnlCcr-section',
            categoryId: '$pnlCcr-kirana',
          ),
        ),
        ReportingCoverage.notAuthorised,
      );
      expect(
        refusalOf(
          await s.revenueDocuments(
            scope: ccrScope,
            range: june,
            businessUnitId: pnlCcr,
            revenueCategoryId: '$pnlCcr-restaurant',
          ),
        ),
        ReportingCoverage.notAuthorised,
      );
    });

    test(
      'consolidated needs unscoped authority; two scoped grants do not add up',
      () async {
        final scoped = await source(
          grants: [...pnlD2(pnlCcr), ...pnlD2(pnlHki)],
        );
        expect(
          refusalOf(
            await scoped.expenseDocuments(
              scope: both,
              range: june,
              businessUnitId: pnlCcr,
              departmentId: '$pnlCcr-dept',
              sectionId: '$pnlCcr-section',
              categoryId: '$pnlCcr-kirana',
            ),
          ),
          ReportingCoverage.notAuthorised,
        );
        // Each property on its own is still theirs.
        expect(await kirana(scoped), hasLength(1));

        final unscoped = await source();
        expect(await kirana(unscoped, scope: both), hasLength(1));
      },
    );

    test('another person never reads this cache', () async {
      final other = await source(owner: 'user-other');
      expect(
        refusalOf(
          await other.expenseDocuments(
            scope: ccrScope,
            range: june,
            businessUnitId: pnlCcr,
            departmentId: '$pnlCcr-dept',
            sectionId: '$pnlCcr-section',
            categoryId: '$pnlCcr-kirana',
          ),
        ),
        ReportingCoverage.notDownloaded,
      );
      // And once they have synchronised their own (empty) cache, still none of mine.
      gateway
        ..revenue.clear()
        ..expense.clear();
      await sync(owner: 'user-other');
      expect(await kirana(await source(owner: 'user-other')), isEmpty);
    });
  });

  test(
    'an older financial year: not downloaded, then rows once fetched on demand',
    () async {
      gateway.expense.add(pnlCost(pnlCcr, '2024-06-14', 91500));
      await sync();
      final older = _range('2024-06-01', '2024-06-30');
      expect(
        refusalOf(
          await (await source()).expenseDocuments(
            scope: ccrScope,
            range: older,
            businessUnitId: pnlCcr,
            departmentId: '$pnlCcr-dept',
            sectionId: '$pnlCcr-section',
            categoryId: '$pnlCcr-kirana',
          ),
        ),
        ReportingCoverage.notDownloaded,
        reason:
            'never a confident empty list for a year this device does not hold',
      );

      await sync(years: const [2024], onDemand: true);
      final rows = await kirana(await source(), range: older);
      expect(rows.single.totals.amount.paise, 91500);
    },
  );
}
