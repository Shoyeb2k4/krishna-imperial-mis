/// The paged reporting sync (D-318 R3, D-320): bounded pages, one publication.
///
/// A real SQLite database, the real cache and the real synchroniser, against a gateway
/// that answers the way `public.reporting_snapshot_page` does: documents ordered by
/// (generation, id), a page never splitting a document, the requested financial years
/// filtering a first synchronisation, and `*_has_more` saying whether to ask again.
///
/// The properties under test are the ones the Product Lead named: a bootstrap obtains the
/// **complete** authorised history in bounded pages; it is restartable and idempotent; it
/// neither duplicates nor skips; it never publishes a half-coherent state; a delta pages
/// on the canonical cursor; and a run is abandoned, publishing nothing, when authority
/// changes under it.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/cache_authority_generation.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/reporting_gateway.dart';
import 'package:krishna_mis/data/repositories/reporting_cache.dart';
import 'package:krishna_mis/data/sync/reporting_sync.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/expenses/expense_number.dart'
    show FinancialYear;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

const _org = 'org-1';
const _ccr = 'unit-ccr';
const _hki = 'unit-hki';
const _me = 'user-me';

int _fyOf(String pnlDate) {
  final year = int.parse(pnlDate.substring(0, 4));
  final month = int.parse(pnlDate.substring(5, 7));
  return month >= 4 ? year : year - 1;
}

/// Answers as `reporting_snapshot_page` does, over a table of projection rows.
final class _PagedGateway extends ReportingGateway {
  _PagedGateway() : super(SupabaseClient('http://localhost', 'test-key'));

  final Map<ReportingDataset, List<Map<String, dynamic>>> rows = {
    ReportingDataset.revenue: [],
    ReportingDataset.expense: [],
  };

  Set<String> visibleUnits = {_ccr, _hki};

  /// Every page asked for, in order.
  final List<ReportingPageCursor> asked = [];

  /// The 1-based call that answers unreachable, if any.
  int? unreachableOnCall;

  /// Runs before the page is answered, with the 1-based call number.
  Future<void> Function(int call)? beforeAnswer;

  int calls = 0;

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> snapshot({
    required List<String> businessUnitIds,
    required int revenueSince,
    required int expenseSince,
    List<int> financialYears = const [],
    ReportingPageCursor after = const ReportingPageCursor.start(),
    int pageDocuments = ReportingPageCursor.defaultPageDocuments,
  }) async {
    calls++;
    asked.add(after);
    if (beforeAnswer != null) await beforeAnswer!(calls);
    if (unreachableOnCall == calls) {
      return const RemoteUnreachable(RemoteFailure.offline);
    }
    final authorised = businessUnitIds.where(visibleUnits.contains).toSet();
    final years = financialYears.toSet();
    final n = pageDocuments.clamp(1, 2000);

    ({
      List<Map<String, dynamic>> rows,
      List<Map<String, dynamic>> documents,
      bool more,
    })
    page(ReportingDataset dataset, int since, int? afterSeq, String? afterId) {
      final documentColumn = dataset.documentColumn;
      final byDocument = <String, List<Map<String, dynamic>>>{};
      for (final row in rows[dataset]!) {
        if (!authorised.contains(row['business_unit_id'])) continue;
        (byDocument[row[documentColumn] as String] ??= []).add(row);
      }
      final candidates = <({String id, int seq})>[];
      for (final entry in byDocument.entries) {
        final seq = entry.value.first['change_seq'] as int;
        if (seq <= since) continue;
        final key = (seq, entry.key);
        final cursor = (afterSeq ?? -1, afterId ?? '');
        if (key.$1 < cursor.$1 ||
            (key.$1 == cursor.$1 && key.$2.compareTo(cursor.$2) <= 0)) {
          continue;
        }
        if (since == 0 &&
            !entry.value.any(
              (r) => years.contains(_fyOf(r['pnl_date'] as String)),
            )) {
          continue;
        }
        candidates.add((id: entry.key, seq: seq));
      }
      candidates.sort(
        (a, b) =>
            a.seq != b.seq ? a.seq.compareTo(b.seq) : a.id.compareTo(b.id),
      );
      final chosen = candidates.take(n).toList();
      return (
        rows: [
          for (final document in chosen)
            for (final row in byDocument[document.id]!)
              if (years.contains(_fyOf(row['pnl_date'] as String)))
                Map<String, dynamic>.from(row),
        ],
        documents: [
          for (final document in chosen)
            {'id': document.id, 'seq': document.seq},
        ],
        more: candidates.length > n,
      );
    }

    final revenue = page(
      ReportingDataset.revenue,
      revenueSince,
      after.revenueSeq,
      after.revenueId,
    );
    final expense = page(
      ReportingDataset.expense,
      expenseSince,
      after.expenseSeq,
      after.expenseId,
    );
    return RemoteOk({
      'snapshot_id': 'snap-$calls',
      'server_time': DateTime.utc(2027, 1, 14, 9, calls).toIso8601String(),
      'page_documents': n,
      'units': [
        for (final unit in businessUnitIds)
          {
            'business_unit_id': unit,
            'reporting_authorised': visibleUnits.contains(unit),
          },
      ],
      'revenue': revenue.rows,
      'revenue_documents': revenue.documents,
      'revenue_has_more': revenue.more,
      'expense': expense.rows,
      'expense_documents': expense.documents,
      'expense_has_more': expense.more,
    });
  }

  void putRevenue(
    String entryId, {
    required String unit,
    required String pnlDate,
    required int gross,
    required int seq,
    bool voided = false,
  }) {
    rows[ReportingDataset.revenue]!.removeWhere(
      (r) => r['revenue_entry_id'] == entryId,
    );
    rows[ReportingDataset.revenue]!.add({
      'id': 'c-$entryId',
      'org_id': _org,
      'revenue_entry_id': entryId,
      'business_unit_id': unit,
      'revenue_category_id': 'cat-restaurant',
      'pnl_date': pnlDate,
      'pnl_period_key': pnlDate.substring(0, 7),
      'gross_minor': gross,
      'tax_minor': 0,
      'net_minor': gross,
      'tax_treatment': 'none',
      'tax_rate_bp': 0,
      'entered_basis': 'inclusive_total',
      'value_band_id': null,
      'supply_subtype_id': null,
      'voided_at': voided ? '2026-09-01T00:00:00Z' : null,
      'change_seq': seq,
    });
  }

  void putExpense(
    String expenseId, {
    required List<({String unit, String pnlDate, int amount})> lines,
    required int seq,
  }) {
    rows[ReportingDataset.expense]!.removeWhere(
      (r) => r['expense_id'] == expenseId,
    );
    var i = 0;
    for (final line in lines) {
      i++;
      rows[ReportingDataset.expense]!.add({
        'id': 'p-$expenseId-$i',
        'org_id': _org,
        'expense_id': expenseId,
        'allocation_id': 'a-$expenseId-$i',
        'business_unit_id': line.unit,
        'department_id': 'dept-1',
        'section_id': 'sec-1',
        'category_id': 'cat-kirana',
        'vendor_id': null,
        'pnl_date': line.pnlDate,
        'pnl_period_key': line.pnlDate.substring(0, 7),
        'amount_minor': line.amount,
        'voided_at': null,
        'change_seq': seq,
        'document_change_seq': seq,
      });
    }
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  final fy2026 = const FinancialYear(2026);

  late AppDatabase db;
  late ReportingCache cache;
  late _PagedGateway gateway;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    cache = ReportingCache(db);
    gateway = _PagedGateway();
  });
  tearDown(() => db.close());

  ReportingSync syncWith({int pageDocuments = 2, AppDatabase? on}) =>
      ReportingSync(
        cache: on == null ? cache : ReportingCache(on),
        gateway: gateway,
        ownerUserId: _me,
        orgId: _org,
        pageDocuments: pageDocuments,
        clock: () => DateTime.utc(2026, 9, 7, 12),
      );

  /// Nine sales and nine bills over both properties, one shared across them.
  void seedHistory() {
    for (var i = 1; i <= 9; i++) {
      gateway.putRevenue(
        'rev-$i',
        unit: i.isEven ? _hki : _ccr,
        pnlDate: '2026-06-${(10 + i).toString().padLeft(2, '0')}',
        gross: 1000 * i,
        seq: 1000 + i,
      );
      gateway.putExpense(
        'exp-$i',
        lines: i == 5
            ? [
                (unit: _ccr, pnlDate: '2026-07-01', amount: 2500),
                (unit: _hki, pnlDate: '2026-07-01', amount: 3300),
              ]
            : [
                (
                  unit: i.isEven ? _hki : _ccr,
                  pnlDate: '2026-07-02',
                  amount: 100 * i,
                ),
              ],
        seq: 2000 + i,
      );
    }
  }

  Future<Set<String>> published(String table, {String owner = _me}) async => {
    for (final row
        in await db
            .customSelect(
              'SELECT contribution_id AS id FROM $table WHERE owner_user_id = ?',
              variables: [Variable<String>(owner)],
            )
            .get())
      row.data['id'] as String,
  };

  Future<int> stagedCount() async {
    var total = 0;
    for (final table in const [
      'reporting_revenue_contributions',
      'reporting_expense_contributions',
    ]) {
      total += (await published(
        table,
        owner: ReportingCache.stagingOwnerFor(_me),
      )).length;
    }
    return total;
  }

  Future<({Set<String> revenue, Set<String> expense})> held() async => (
    revenue: await published('reporting_revenue_contributions'),
    expense: await published('reporting_expense_contributions'),
  );

  Future<ReportingSyncReport> run(ReportingSync sync, {Set<String>? units}) =>
      sync.synchronise(businessUnitIds: units ?? {_ccr, _hki}, years: [fy2026]);

  group('a bootstrap in bounded pages', () {
    test(
      'publishes exactly the cache one unbounded page would, no row twice, none missing',
      () async {
        seedHistory();
        final report = await run(syncWith(pageDocuments: 2));
        expect(report.isComplete, isTrue);
        expect(report.pages, 5, reason: '9 documents per dataset, 2 per page');
        final paged = await held();

        final other = AppDatabase(NativeDatabase.memory());
        addTearDown(other.close);
        final single = await ReportingSync(
          cache: ReportingCache(other),
          gateway: gateway,
          ownerUserId: _me,
          orgId: _org,
          pageDocuments: 1000,
          clock: () => DateTime.utc(2026, 9, 7, 12),
        ).synchronise(businessUnitIds: {_ccr, _hki}, years: [fy2026]);
        expect(single.pages, 1);
        final oneShot = (
          revenue: {
            for (final row
                in await other
                    .customSelect(
                      'SELECT contribution_id AS id FROM '
                      'reporting_revenue_contributions',
                    )
                    .get())
              row.data['id'] as String,
          },
          expense: {
            for (final row
                in await other
                    .customSelect(
                      'SELECT contribution_id AS id FROM '
                      'reporting_expense_contributions',
                    )
                    .get())
              row.data['id'] as String,
          },
        );

        expect(paged.revenue, hasLength(9));
        expect(
          paged.expense,
          hasLength(10),
          reason: 'the shared bill has two lines',
        );
        expect(paged.revenue, oneShot.revenue);
        expect(paged.expense, oneShot.expense);
        expect(await stagedCount(), 0);
        expect(await cache.readResume(_me), isNull);

        // The final page's snapshot is the run's evidence (D-188, D-320).
        final markers = await cache.markersFor(_me);
        expect({for (final m in markers) m.snapshotId}, {'snap-5'});
        expect(
          {for (final m in markers) m.generation},
          {1009, 2009},
          reason:
              'each dataset is certified to the highest document generation seen',
        );
      },
    );

    test(
      'an interrupted run publishes nothing, and the next run resumes from its cursor',
      () async {
        seedHistory();
        gateway.unreachableOnCall = 3;
        final first = await run(syncWith());
        expect(first.isComplete, isFalse);
        expect(first.outcomes.first, isA<DatasetUnreachable>());

        final afterFailure = await held();
        expect(afterFailure.revenue, isEmpty, reason: 'no half-published run');
        expect(afterFailure.expense, isEmpty);
        expect(await cache.markersFor(_me), isEmpty);
        expect(await stagedCount(), greaterThan(0));
        expect(await cache.readResume(_me), isNotNull);

        gateway.unreachableOnCall = null;
        final askedBefore = gateway.asked.length;
        final second = await run(syncWith());
        expect(second.isComplete, isTrue);
        expect(
          gateway.asked[askedBefore].isStart,
          isFalse,
          reason: 'resumed at its cursor rather than from the first page',
        );
        expect(second.pages, 5);
        final complete = await held();
        expect(complete.revenue, hasLength(9));
        expect(complete.expense, hasLength(10));
        expect(await stagedCount(), 0);
        expect(await cache.readResume(_me), isNull);
      },
    );

    test(
      'a resume staged for another scope is discarded, never published',
      () async {
        seedHistory();
        gateway.unreachableOnCall = 2;
        await run(syncWith());
        expect(await stagedCount(), greaterThan(0));

        gateway.unreachableOnCall = null;
        final askedBefore = gateway.asked.length;
        final report = await run(syncWith(), units: {_ccr});
        expect(report.isComplete, isTrue);
        expect(gateway.asked[askedBefore].isStart, isTrue);
        final rows = await held();
        final hkiRevenue = rows.revenue.where(
          (id) => int.parse(id.split('-').last).isEven,
        );
        expect(
          hkiRevenue,
          isEmpty,
          reason: 'nothing staged for HKI was published',
        );
        expect(rows.revenue, hasLength(5));
        expect(await stagedCount(), 0);
      },
    );

    test(
      'a run over an unchanged server a second time changes nothing',
      () async {
        seedHistory();
        await run(syncWith());
        final first = await held();
        final report = await run(syncWith());
        expect(report.isComplete, isTrue);
        final again = await held();
        expect(again.revenue, first.revenue);
        expect(again.expense, first.expense);
      },
    );
  });

  group('authority moving under a run', () {
    test(
      'a session or authority transition between pages abandons it, publishing nothing',
      () async {
        seedHistory();
        gateway.beforeAnswer = (call) async {
          if (call == 3) await CacheAuthorityGeneration(db).endSession();
        };
        final report = await run(syncWith());
        expect(report.abandoned, isTrue);
        final rows = await held();
        expect(rows.revenue, isEmpty);
        expect(rows.expense, isEmpty);
        expect(await cache.markersFor(_me), isEmpty);
        expect(await stagedCount(), 0, reason: 'what was staged is discarded');
        expect(await cache.readResume(_me), isNull);
      },
    );

    test(
      'the server withdrawing a property between pages abandons the run',
      () async {
        seedHistory();
        gateway.beforeAnswer = (call) async {
          if (call == 2) gateway.visibleUnits = {_ccr};
        };
        final report = await run(syncWith());
        expect(report.abandoned, isTrue);
        final rows = await held();
        expect(rows.revenue, isEmpty);
        expect(rows.expense, isEmpty);
        expect(await stagedCount(), 0);
      },
    );

    test('the purge takes staged pages with it', () async {
      seedHistory();
      gateway.unreachableOnCall = 3;
      await run(syncWith());
      expect(await stagedCount(), greaterThan(0));
      await ScopeCachePurge(db).purgeAllScopedCache();
      expect(await stagedCount(), 0);
    });
  });

  group('a delta in bounded pages', () {
    test(
      'clears a document whose rows all left the requested years, and replaces the rest',
      () async {
        // Generations above the safety overlap, so the second run is a real delta.
        seedHistory();
        await run(syncWith());
        expect((await held()).revenue, contains('c-rev-1'));

        // rev-1 moves to the next financial year; five more sales change.
        gateway.putRevenue(
          'rev-1',
          unit: _ccr,
          pnlDate: '2027-05-01',
          gross: 1000,
          seq: 5000,
        );
        for (var i = 2; i <= 6; i++) {
          gateway.putRevenue(
            'rev-$i',
            unit: i.isEven ? _hki : _ccr,
            pnlDate: '2026-06-20',
            gross: 7,
            seq: 5000 + i,
          );
        }
        final report = await run(syncWith());
        expect(report.isComplete, isTrue);
        expect(report.pages, greaterThan(1));
        final rows = await held();
        expect(rows.revenue, isNot(contains('c-rev-1')));
        expect(rows.revenue, hasLength(8));
        final changed = await db
            .customSelect(
              "SELECT COUNT(*) AS n FROM reporting_revenue_contributions "
              "WHERE owner_user_id = ? AND gross_minor = 7",
              variables: [Variable<String>(_me)],
            )
            .getSingle();
        expect(changed.data['n'], 5);
      },
    );

    test('a voided document delivered on a middle page is removed', () async {
      seedHistory();
      await run(syncWith());
      gateway.putRevenue(
        'rev-3',
        unit: _ccr,
        pnlDate: '2026-06-13',
        gross: 3000,
        seq: 6001,
        voided: true,
      );
      for (var i = 4; i <= 7; i++) {
        gateway.putRevenue(
          'rev-$i',
          unit: i.isEven ? _hki : _ccr,
          pnlDate: '2026-06-21',
          gross: 9,
          seq: 6001 + i,
        );
      }
      final report = await run(syncWith());
      expect(report.pages, greaterThan(1));
      expect((await held()).revenue, isNot(contains('c-rev-3')));
    });
  });

  test(
    'a first synchronisation replaces its segment whole, so a document that left '
    'the years does not linger',
    () async {
      // Small generations: every run asks from zero, which is the bootstrap contract —
      // the server lists only documents with a row in the requested years.
      gateway.putRevenue(
        'rev-x',
        unit: _ccr,
        pnlDate: '2026-06-15',
        gross: 500,
        seq: 10,
      );
      await run(syncWith());
      expect((await held()).revenue, contains('c-rev-x'));

      gateway.putRevenue(
        'rev-x',
        unit: _ccr,
        pnlDate: '2026-02-15',
        gross: 500,
        seq: 20,
      );
      final report = await run(syncWith());
      expect(report.isComplete, isTrue);
      expect((await held()).revenue, isEmpty);
    },
  );
}
