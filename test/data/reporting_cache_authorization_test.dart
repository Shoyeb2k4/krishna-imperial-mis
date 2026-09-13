/// Phase 5 Slice 7 — the local P&L cache follows confirmed capability loss and
/// remains isolated by signed-in person (D-070, D-074).
///
/// A business-unit diff is insufficient: somebody can keep both properties while
/// losing one of the three capabilities a P&L requires. The cached facts and their
/// coverage/snapshot evidence must then go for that person, marker first. A network
/// failure is not a revocation and removes nothing.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';

const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _pnlCapabilities = {
  Capability.reportsView,
  Capability.revenueView,
  Capability.expenseViewAll,
};

void main() {
  late AppDatabase db;
  late ScopeCachePurge purge;
  final now = DateTime.utc(2026, 9, 12, 10);

  AuthoritySnapshot authority(
    String userId, {
    required Map<String, Set<Capability>> byUnit,
  }) => AuthoritySnapshot(
    userId: userId,
    orgId: 'org-1',
    resolvedAt: now,
    grants: [
      for (final entry in byUnit.entries) ...[
        // Keeps the unit itself in scope even when a reporting capability is removed.
        CapabilityGrant(Capability.mastersView, businessUnitId: entry.key),
        for (final capability in entry.value)
          CapabilityGrant(capability, businessUnitId: entry.key),
      ],
    ],
  );

  Future<void> seed(String ownerUserId) => ReportingCache(db).applySnapshot(
    ownerUserId: ownerUserId,
    orgId: 'org-1',
    snapshotId: 'snapshot-$ownerUserId',
    serverConfirmedAt: now,
    businessUnitIds: const {_ccr, _hki},
    financialYears: const [2026],
    datasets: {
      ReportingDataset.revenue: const DatasetApplication(
        documentIds: ['rev-ccr', 'rev-hki'],
        rowsByYear: {
          2026: [
            RevenueRowValues(
              contributionId: 'rev-component-ccr',
              revenueEntryId: 'rev-ccr',
              businessUnitId: _ccr,
              revenueCategoryId: 'rev-category-ccr',
              pnlDate: '2026-06-15',
              pnlPeriodKey: '2026-06',
              grossMinor: 10500,
              taxMinor: 500,
              netMinor: 10000,
              taxTreatment: 'inclusive',
              taxRateBasisPoints: 500,
              enteredBasis: 'inclusive_total',
              documentGeneration: 1,
            ),
            RevenueRowValues(
              contributionId: 'rev-component-hki',
              revenueEntryId: 'rev-hki',
              businessUnitId: _hki,
              revenueCategoryId: 'rev-category-hki',
              pnlDate: '2026-06-15',
              pnlPeriodKey: '2026-06',
              grossMinor: 21000,
              taxMinor: 1000,
              netMinor: 20000,
              taxTreatment: 'inclusive',
              taxRateBasisPoints: 500,
              enteredBasis: 'inclusive_total',
              documentGeneration: 1,
            ),
          ],
        },
        generationByYear: {2026: 1},
      ),
      ReportingDataset.expense: const DatasetApplication(
        documentIds: ['exp-ccr', 'exp-hki'],
        rowsByYear: {
          2026: [
            ExpenseRowValues(
              contributionId: 'exp-component-ccr',
              expenseId: 'exp-ccr',
              allocationId: 'allocation-ccr',
              businessUnitId: _ccr,
              departmentId: 'department-ccr',
              sectionId: 'section-ccr',
              categoryId: 'expense-category-ccr',
              pnlDate: '2026-06-15',
              pnlPeriodKey: '2026-06',
              amountMinor: 4000,
              documentGeneration: 1,
            ),
            ExpenseRowValues(
              contributionId: 'exp-component-hki',
              expenseId: 'exp-hki',
              allocationId: 'allocation-hki',
              businessUnitId: _hki,
              departmentId: 'department-hki',
              sectionId: 'section-hki',
              categoryId: 'expense-category-hki',
              pnlDate: '2026-06-15',
              pnlPeriodKey: '2026-06',
              amountMinor: 8000,
              documentGeneration: 1,
            ),
          ],
        },
        generationByYear: {2026: 1},
      ),
    },
    onDemand: false,
    now: now,
  );

  Future<int> count(
    String table,
    String userId, {
    String? businessUnitId,
  }) async {
    final unitClause = businessUnitId == null
        ? ''
        : ' AND business_unit_id = ?';
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM $table WHERE owner_user_id = ?$unitClause',
          variables: [
            Variable<String>(userId),
            if (businessUnitId != null) Variable<String>(businessUnitId),
          ],
        )
        .getSingle();
    return row.data['n'] as int;
  }

  Future<Map<String, int>> cacheOf(String userId) async => {
    for (final table in const [
      'reporting_coverage_markers',
      'reporting_revenue_contributions',
      'reporting_expense_contributions',
    ])
      table: await count(table, userId),
  };

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    purge = ScopeCachePurge(db);
  });
  tearDown(() => db.close());

  test(
    'sign-out removes reporting facts and evidence without unit masters',
    () async {
      await seed('user-1');
      expect(await db.select(db.businessUnits).get(), isEmpty);
      await purge.purgeAllScopedCache();
      expect((await cacheOf('user-1')).values, everyElement(0));
    },
  );

  group('confirmed reporting-capability loss with both units retained', () {
    for (final lost in _pnlCapabilities) {
      test(
        'losing ${lost.code} removes the cached P&L and its evidence',
        () async {
          await seed('user-1');
          final before = authority(
            'user-1',
            byUnit: const {_ccr: _pnlCapabilities, _hki: _pnlCapabilities},
          );
          final afterCapabilities = {..._pnlCapabilities}..remove(lost);
          final after = authority(
            'user-1',
            byUnit: {_ccr: afterCapabilities, _hki: afterCapabilities},
          );

          await purge.applyTo(
            AuthorityRefresh.confirmed(after),
            previous: before,
          );

          expect(await cacheOf('user-1'), {
            'reporting_coverage_markers': 0,
            'reporting_revenue_contributions': 0,
            'reporting_expense_contributions': 0,
          });
        },
      );
    }

    test('a capability lost on one unit removes only that unit', () async {
      await seed('user-1');
      final before = authority(
        'user-1',
        byUnit: const {_ccr: _pnlCapabilities, _hki: _pnlCapabilities},
      );
      final after = authority(
        'user-1',
        byUnit: const {
          _ccr: {Capability.revenueView, Capability.expenseViewAll},
          _hki: _pnlCapabilities,
        },
      );

      await purge.applyTo(AuthorityRefresh.confirmed(after), previous: before);

      for (final table in const [
        'reporting_coverage_markers',
        'reporting_revenue_contributions',
        'reporting_expense_contributions',
      ]) {
        expect(await count(table, 'user-1', businessUnitId: _ccr), 0);
        expect(
          await count(table, 'user-1', businessUnitId: _hki),
          greaterThan(0),
        );
      }
    });

    test(
      'another person cache is not evidence about this revocation',
      () async {
        await seed('user-1');
        await seed('user-2');
        final before = authority(
          'user-1',
          byUnit: const {_ccr: _pnlCapabilities, _hki: _pnlCapabilities},
        );
        final after = authority('user-1', byUnit: const {_ccr: {}, _hki: {}});

        await purge.applyTo(
          AuthorityRefresh.confirmed(after),
          previous: before,
        );

        expect((await cacheOf('user-1')).values, everyElement(0));
        expect((await cacheOf('user-2')).values, everyElement(greaterThan(0)));
      },
    );

    for (final reason in AuthorityUnavailableReason.values) {
      test('an unavailable refresh (${reason.name}) removes nothing', () async {
        await seed('user-1');
        await purge.applyTo(
          AuthorityRefresh.unavailable(reason),
          previous: authority(
            'user-1',
            byUnit: const {_ccr: _pnlCapabilities, _hki: _pnlCapabilities},
          ),
        );
        expect((await cacheOf('user-1')).values, everyElement(greaterThan(0)));
      });
    }
  });
}
