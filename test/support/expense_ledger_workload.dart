/// The Phase 8 Slice 4 expense-ledger workload, shared by the host measurement and the
/// on-device run (D-313).
///
/// Three things live here so the host test and the integration test cannot drift apart:
///
/// * a **deterministic fixture** — the same seeded documents in the same order on every
///   platform, with ties in `captured_at`, shared bills, cross-period splits, voided rows,
///   attachments and every outbox state the ledger can show;
/// * the **workloads** — the ledger reads a person actually makes: the first page, the
///   next one, a middle and a deep page, and each filter on its own;
/// * an exact **statement counter**, as a Drift [QueryInterceptor], so the number of
///   queries a page costs is measured rather than argued.
///
/// Every figure here is synthetic and carries no business fact (spec §32). Nothing here
/// talks to a server.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';

// ── The fixture ──────────────────────────────────────────────────────────────

final String ledgerCcr = seedId('bu:CCR');
final String ledgerHki = seedId('bu:HKI');

/// Two classifications per property, so a category filter selects a real subset.
final List<({String dept, String section, String category, String label})>
_ccrLines = [
  (
    dept: seedId('dept:CCR/FB'),
    section: seedId('sec:CCR/FB/FOOD_PROD'),
    category: seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
    label: 'Kirana & Pulses',
  ),
  (
    dept: seedId('dept:CCR/FB'),
    section: seedId('sec:CCR/FB/FOOD_PROD'),
    category: seedId('cat:CCR/FB/FOOD_PROD/VEG'),
    label: 'Vegetables & Fruits',
  ),
];
final List<({String dept, String section, String category, String label})>
_hkiLines = [
  (
    dept: seedId('dept:HKI/HKI_UTIL'),
    section: seedId('sec:HKI/HKI_UTIL/HKI_POWER'),
    category: seedId('cat:HKI/HKI_UTIL/HKI_POWER/ELECTRICITY'),
    label: 'Electricity',
  ),
  (
    dept: seedId('dept:HKI/HKI_UTIL'),
    section: seedId('sec:HKI/HKI_UTIL/HKI_POWER'),
    category: seedId('cat:HKI/HKI_UTIL/HKI_POWER/DIESEL'),
    label: 'Diesel',
  ),
];

/// The category a category filter asks for: one of the two Crystal Canopy lines.
String get ledgerFilterCategory => _ccrLines.first.category;

/// What a fixture holds, so a report states the exact row counts it measured (D-313).
final class LedgerFixtureCounts {
  const LedgerFixtureCounts({
    required this.documents,
    required this.allocations,
    required this.periodRows,
    required this.attachments,
    required this.outbox,
    required this.voided,
    required this.conflicts,
    required this.firstDate,
    required this.lastDate,
  });

  final int documents;
  final int allocations;
  final int periodRows;
  final int attachments;
  final int outbox;
  final int voided;
  final int conflicts;
  final String firstDate;
  final String lastDate;

  @override
  String toString() =>
      '$documents expenses ($voided voided, $conflicts in conflict), '
      '$allocations allocations, $periodRows period rows, '
      '$attachments attachments, $outbox outbox entries, '
      'business dates $firstDate … $lastDate';
}

/// The dataset classes of D-313, sized for the ledger.
///
/// SCALE is 100,000 contribution rows a year, half of them expenses: about 45,000
/// documents carrying about 50,000 expense period rows. STRESS is five years of that.
/// CURRENT is the shape of `krishna-mis-dev` on 2026-09-30 (2,276 expenses).
enum LedgerDatasetClass {
  current(documents: 2276, years: 1),
  scale(documents: 45000, years: 1),
  stress(documents: 225000, years: 5);

  const LedgerDatasetClass({required this.documents, required this.years});

  final int documents;
  final int years;
}

/// Seeds [documents] expenses across [years] financial years ending 31 March 2027.
///
/// Deterministic: document *i* is the same document on every machine. Inserted through
/// Drift's own batch so every value is stored exactly as the application stores it.
Future<LedgerFixtureCounts> seedExpenseLedgerFixture(
  AppDatabase db, {
  required int documents,
  required int years,
  String orgId = 'test-org',
  String actor = 'user-me',
}) async {
  final last = DateTime.utc(2027, 3, 31);
  final first = DateTime.utc(2027 - years, 4, 1);
  final days = last.difference(first).inDays + 1;

  var allocations = 0;
  var periodRows = 0;
  var attachments = 0;
  var outbox = 0;
  var voided = 0;
  var conflicts = 0;
  final updatedAt = DateTime.utc(2027, 4, 1, 3);

  const chunk = 2000;
  for (var start = 0; start < documents; start += chunk) {
    final end = start + chunk < documents ? start + chunk : documents;
    await db.batch((batch) {
      for (var i = start; i < end; i++) {
        // Evenly across the range, so a month and a property both select a real share.
        final day = first.add(Duration(days: (i * days) ~/ documents));
        final date = _iso(day);
        // Three consecutive documents share one capture instant: the tie the ordering's
        // third term exists for.
        final captured = day.add(Duration(hours: 9, seconds: (i ~/ 3) % 3600));
        final id = 'exp-${i.toString().padLeft(7, '0')}';
        final shared = i % 10 == 0;
        final unit = i.isEven ? ledgerCcr : ledgerHki;
        final isVoided = i % 10 == 3;
        final status = _outboxStatusFor(i);
        final hasNumber = status != OutboxStatus.pending;
        final mutation = status == null ? null : 'mut-$id';
        final amount = 100000 + (i % 977) * 100;

        if (isVoided) voided++;
        if (status == OutboxStatus.conflict) conflicts++;

        batch.insert(
          db.expenses,
          ExpensesCompanion.insert(
            id: id,
            orgId: orgId,
            txnNumber: Value(hasNumber ? 'KI-EXP-26-27-${_seq(i)}' : null),
            financialYear: Value(hasNumber ? 2026 : null),
            businessDate: date,
            documentTotalMinor: Value(amount),
            visibleAmountMinor: amount,
            isShared: Value(shared),
            vendorId: Value('vendor-${i % 20}'),
            paymentStatus: Value(i % 4 == 0 ? 'paid' : 'unpaid'),
            paymentDate: Value(i % 4 == 0 ? date : null),
            paymentMethodId: Value(i % 4 == 0 ? 'pm-cash' : null),
            referenceNumber: Value('REF-$i'),
            createdBy: actor,
            capturedAt: captured,
            voidedAt: Value(isVoided ? updatedAt : null),
            voidedBy: Value(isVoided ? actor : null),
            voidReason: Value(isVoided ? 'Synthetic void' : null),
            pendingMutationId: Value(mutation),
            rowVersion: const Value(2),
            updatedAt: updatedAt,
          ),
        );

        final lines = shared
            ? [
                (unit: ledgerCcr, line: _ccrLines[i % 2], amount: amount ~/ 2),
                (
                  unit: ledgerHki,
                  line: _hkiLines[i % 2],
                  amount: amount - amount ~/ 2,
                ),
              ]
            : [
                (
                  unit: unit,
                  line: unit == ledgerCcr ? _ccrLines[i % 2] : _hkiLines[i % 2],
                  amount: amount,
                ),
              ];
        for (var l = 0; l < lines.length; l++) {
          final entry = lines[l];
          final allocationId = '$id-a$l';
          allocations++;
          batch.insert(
            db.expenseAllocations,
            ExpenseAllocationsCompanion.insert(
              id: allocationId,
              orgId: orgId,
              expenseId: id,
              businessUnitId: entry.unit,
              departmentId: entry.line.dept,
              sectionId: entry.line.section,
              categoryId: entry.line.category,
              amountMinor: entry.amount,
              categoryLabel: entry.line.label,
              sortOrder: Value(l),
              updatedAt: updatedAt,
            ),
          );
          // One in twenty lines is split across two accounting periods (D-034).
          final split = i % 20 == 1 && entry.amount > 1;
          final parts = split
              ? [entry.amount ~/ 2, entry.amount - entry.amount ~/ 2]
              : [entry.amount];
          for (var p = 0; p < parts.length; p++) {
            final pnl = p == 0 ? date : _iso(day.add(const Duration(days: 31)));
            periodRows++;
            batch.insert(
              db.expensePeriodAllocations,
              ExpensePeriodAllocationsCompanion.insert(
                id: '$allocationId-p$p',
                orgId: orgId,
                expenseId: id,
                allocationId: allocationId,
                businessUnitId: entry.unit,
                accountingPeriodStart: pnl,
                accountingPeriodEnd: pnl,
                amountMinor: parts[p],
                pnlDate: pnl,
                pnlPeriodKey: pnl.substring(0, 7),
                isDerived: Value(!split),
                updatedAt: updatedAt,
              ),
            );
          }
        }

        if (i % 5 == 0) {
          attachments++;
          batch.insert(
            db.expenseAttachments,
            ExpenseAttachmentsCompanion.insert(
              id: '$id-att',
              orgId: orgId,
              expenseId: id,
              fileName: 'bill-$i.jpg',
              contentType: 'image/jpeg',
              byteSize: 120000,
              contentHash: 'hash-$i',
              uploadState: const Value('uploaded'),
              storagePath: Value('org/$orgId/expenses/$id/$id-att.jpg'),
              uploadedAt: Value(updatedAt),
              uploadedBy: actor,
              createdAt: updatedAt,
              updatedAt: updatedAt,
            ),
          );
        }

        if (status != null) {
          outbox++;
          batch.insert(
            db.syncOutbox,
            SyncOutboxCompanion.insert(
              mutationId: mutation!,
              actorUserId: Value(actor),
              entityType: 'expense',
              entityId: id,
              op: hasNumber ? 'update' : 'create',
              payload: '{}',
              nextAttemptAt: updatedAt,
              status: status.name,
              createdAt: updatedAt,
            ),
          );
        }
      }
    });
  }

  return LedgerFixtureCounts(
    documents: documents,
    allocations: allocations,
    periodRows: periodRows,
    attachments: attachments,
    outbox: outbox,
    voided: voided,
    conflicts: conflicts,
    firstDate: _iso(first),
    lastDate: _iso(last),
  );
}

/// The outbox state document [i] carries, or null for a document with nothing queued.
///
/// Sparse on purpose: on a real device almost everything is synced, which is exactly why
/// a filter applied after the page is cut finds almost nothing.
OutboxStatus? _outboxStatusFor(int i) {
  if (i % 50 == 7) return OutboxStatus.pending;
  if (i % 50 == 17) return OutboxStatus.conflict;
  if (i % 200 == 27) return OutboxStatus.failed;
  if (i % 500 == 37) return OutboxStatus.rejected;
  return null;
}

String _seq(int i) => (i + 1).toString().padLeft(6, '0');

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// ── The workloads ────────────────────────────────────────────────────────────

/// A ledger query as the repository receives it.
final class LedgerWorkloadQuery implements ExpenseQuery {
  const LedgerWorkloadQuery({
    this.from,
    this.to,
    this.businessUnitId,
    this.categoryId,
    this.syncState,
    this.search,
    this.includeVoided = false,
  });

  @override
  final String? from;
  @override
  final String? to;
  @override
  final String? businessUnitId;
  @override
  String? get departmentId => null;
  @override
  String? get sectionId => null;
  @override
  final String? categoryId;
  @override
  String? get vendorId => null;
  @override
  String? get paymentStatus => null;
  @override
  final SyncState? syncState;
  @override
  final String? search;
  @override
  final bool includeVoided;
}

/// One measured read: a filter, a window, and a name to report it under.
final class LedgerWorkload {
  const LedgerWorkload(this.name, this.query, {this.offset = 0});

  final String name;
  final LedgerWorkloadQuery query;
  final int offset;
}

/// The workloads, at a page size of [pageSize], for a fixture of [documents].
List<LedgerWorkload> ledgerWorkloads({
  required int documents,
  required int pageSize,
}) {
  // Live (unvoided) documents are nine in ten; a page index is computed against them.
  final live = documents - documents ~/ 10;
  int pageAt(int row) => (row ~/ pageSize) * pageSize;
  return [
    const LedgerWorkload('first page', LedgerWorkloadQuery()),
    LedgerWorkload(
      'second page',
      const LedgerWorkloadQuery(),
      offset: pageSize,
    ),
    LedgerWorkload(
      'middle page',
      const LedgerWorkloadQuery(),
      offset: pageAt(live ~/ 2),
    ),
    LedgerWorkload(
      'deep page',
      const LedgerWorkloadQuery(),
      offset: pageAt(live - pageSize * 2),
    ),
    LedgerWorkload(
      'property filter',
      LedgerWorkloadQuery(businessUnitId: ledgerHki),
    ),
    LedgerWorkload(
      'category filter',
      LedgerWorkloadQuery(categoryId: ledgerFilterCategory),
    ),
    const LedgerWorkload(
      'one-month range',
      LedgerWorkloadQuery(from: '2026-11-01', to: '2026-11-30'),
    ),
    // A category nothing carries: the worst case for a filter answered by walking the
    // ledger in order, because nothing stops the walk early.
    const LedgerWorkload(
      'unmatched category',
      LedgerWorkloadQuery(categoryId: 'no-such-category'),
    ),
    const LedgerWorkload('search', LedgerWorkloadQuery(search: '000123')),
    const LedgerWorkload(
      'sync filter: conflict',
      LedgerWorkloadQuery(syncState: SyncState.conflict),
    ),
    const LedgerWorkload(
      'include voided',
      LedgerWorkloadQuery(includeVoided: true),
    ),
  ];
}

// ── Measuring ────────────────────────────────────────────────────────────────

/// Every statement the database ran, in order, with how long each took.
final class StatementCounter extends QueryInterceptor {
  final List<({String sql, List<Object?> args, Duration took})> log = [];
  bool recording = false;

  void reset() => log.clear();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (!recording) return executor.runSelect(statement, args);
    final watch = Stopwatch()..start();
    final rows = await executor.runSelect(statement, args);
    log.add((sql: statement, args: args, took: watch.elapsed));
    return rows;
  }
}

/// One workload's measurement: timings from warm runs, plus the deterministic half.
final class LedgerMeasurement {
  const LedgerMeasurement({
    required this.workload,
    required this.rows,
    required this.statements,
    required this.median,
    required this.min,
    required this.max,
    required this.pageSelectMedian,
    required this.plan,
    this.hydrationPlan,
  });

  final String workload;
  final int rows;
  final int statements;
  final Duration median;
  final Duration min;
  final Duration max;

  /// The time the statement that cut the page took; the rest is hydration.
  final Duration pageSelectMedian;
  final String plan;
  final String? hydrationPlan;

  Duration get hydrationMedian => median - pageSelectMedian;

  String row() =>
      '${workload.padRight(22)} rows ${rows.toString().padLeft(4)} · '
      'stmts ${statements.toString().padLeft(4)} · '
      'median ${_ms(median)} (min ${_ms(min)}, max ${_ms(max)}) · '
      'page select ${_ms(pageSelectMedian)} · hydration ${_ms(hydrationMedian)}';
}

String _ms(Duration d) => '${(d.inMicroseconds / 1000).toStringAsFixed(1)} ms';

/// Runs [workload] once to warm, then [runs] times, through [read].
///
/// [read] is the repository call under test, so the same harness measures the ledger
/// before and after it changes.
Future<LedgerMeasurement> measureLedger(
  AppDatabase db,
  StatementCounter counter,
  LedgerWorkload workload, {
  required Future<int> Function(LedgerWorkload) read,
  int runs = 5,
}) async {
  await read(workload); // discarded warm-up (D-313)
  final totals = <Duration>[];
  final pageSelects = <Duration>[];
  var rows = 0;
  var statements = 0;
  ({String sql, List<Object?> args})? pageStatement;
  ({String sql, List<Object?> args})? childStatement;

  for (var r = 0; r < runs; r++) {
    counter
      ..reset()
      ..recording = true;
    final watch = Stopwatch()..start();
    rows = await read(workload);
    final took = watch.elapsed;
    counter.recording = false;
    totals.add(took);
    statements = counter.log.length;
    final first = counter.log.first;
    pageSelects.add(first.took);
    pageStatement = (sql: first.sql, args: first.args);
    final child = counter.log
        .skip(1)
        .where((s) => s.sql.contains('expense_allocations'));
    childStatement = child.isEmpty
        ? null
        : (sql: child.first.sql, args: child.first.args);
  }

  totals.sort();
  pageSelects.sort();
  return LedgerMeasurement(
    workload: workload.name,
    rows: rows,
    statements: statements,
    median: totals[totals.length ~/ 2],
    min: totals.first,
    max: totals.last,
    pageSelectMedian: pageSelects[pageSelects.length ~/ 2],
    plan: await explain(db, pageStatement!),
    hydrationPlan: childStatement == null
        ? null
        : await explain(db, childStatement),
  );
}

/// `EXPLAIN QUERY PLAN` for a captured statement, one line per step.
Future<String> explain(
  AppDatabase db,
  ({String sql, List<Object?> args}) statement,
) async {
  final rows = await db
      .customSelect(
        'EXPLAIN QUERY PLAN ${statement.sql}',
        variables: [for (final a in statement.args) _variable(a)],
      )
      .get();
  return [for (final r in rows) r.data['detail']].join(' | ');
}

Variable<Object> _variable(Object? value) => switch (value) {
  final int v => Variable<int>(v),
  final String v => Variable<String>(v),
  final bool v => Variable<bool>(v),
  final double v => Variable<double>(v),
  final DateTime v => Variable<DateTime>(v),
  null => const Variable<Object>(null),
  _ => Variable<String>('$value'),
};

/// The v22 ledger indexes, by name, so a measurement can remove them and reproduce the
/// pre-v22 read path on the same data (D-323).
const ledgerIndexNames = [
  'ix_expense_allocations_expense',
  'ix_expense_period_allocations_expense',
  'ix_expense_attachments_expense',
  'ix_expenses_ledger',
];

/// The database's size in bytes: pages in use times the page size.
Future<int> databaseBytes(AppDatabase db) async {
  final pages = await db.customSelect('PRAGMA page_count').getSingle();
  final size = await db.customSelect('PRAGMA page_size').getSingle();
  return (pages.data.values.first! as int) * (size.data.values.first! as int);
}

/// Resident memory, where the platform reports it.
int residentBytes() => ProcessInfo.currentRss;
