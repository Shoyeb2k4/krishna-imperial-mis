/// Phase 8 Slice 4 — the expense ledger reaches every matching document (D-317, D-323).
///
/// Until this slice the Windows ledger asked for the newest 100 documents and nothing
/// more, then applied its sync-state filter to those 100 in Dart. A device holding
/// forty-six conflicted expenses showed one, and a person had no way to reach the 101st
/// expense at all. These tests pin the corrected contract at the repository:
///
/// * every filter is decided in the statement that cuts the page;
/// * the order is total, so pages neither repeat nor skip a document — including
///   documents captured in the same instant on the same day;
/// * the SQL sync state agrees with the Dart rule for every outbox status;
/// * the v22 indexes exist on a fresh database and on an upgraded one, and the ledger
///   reads through them.
library;

import 'dart:io';

import 'package:drift/drift.dart' show ApplyInterceptor, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';

import '../support/expense_fixtures.dart' show createTempDatabaseFile;
import '../support/expense_ledger_workload.dart';

/// One document, inserted exactly as a synced row is stored.
Future<void> _insert(
  AppDatabase db, {
  required String id,
  String date = '2026-06-15',
  DateTime? captured,
  String unit = 'unit-a',
  String category = 'cat-1',
  String? txn = 'KI-EXP-26-27-000001',
  String? outboxStatus,
  bool voided = false,
  bool revoked = false,
  String createdBy = 'user-me',
}) async {
  final now = DateTime.utc(2026, 7, 1);
  final mutation = outboxStatus == null ? null : 'mut-$id';
  await db
      .into(db.expenses)
      .insert(
        ExpensesCompanion.insert(
          id: id,
          orgId: 'org',
          txnNumber: Value(txn),
          financialYear: Value(txn == null ? null : 2026),
          businessDate: date,
          documentTotalMinor: const Value(10000),
          visibleAmountMinor: 10000,
          referenceNumber: Value('REF-$id'),
          createdBy: createdBy,
          capturedAt: captured ?? DateTime.utc(2026, 6, 15, 9),
          voidedAt: Value(voided ? now : null),
          voidedBy: Value(voided ? 'someone' : null),
          voidReason: Value(voided ? 'Entered twice' : null),
          pendingMutationId: Value(mutation),
          scopeRevokedAt: Value(revoked ? now : null),
          updatedAt: now,
        ),
      );
  await db
      .into(db.expenseAllocations)
      .insert(
        ExpenseAllocationsCompanion.insert(
          id: '$id-a',
          orgId: 'org',
          expenseId: id,
          businessUnitId: unit,
          departmentId: 'dept-1',
          sectionId: 'sec-1',
          categoryId: category,
          amountMinor: 10000,
          categoryLabel: 'Kirana',
          updatedAt: now,
        ),
      );
  if (outboxStatus != null) {
    await db
        .into(db.syncOutbox)
        .insert(
          SyncOutboxCompanion.insert(
            mutationId: mutation!,
            actorUserId: const Value('user-me'),
            entityType: 'expense',
            entityId: id,
            op: 'update',
            payload: '{}',
            nextAttemptAt: now,
            status: outboxStatus,
            createdAt: now,
          ),
        );
  }
}

final class _Query implements ExpenseQuery {
  const _Query({
    this.businessUnitId,
    this.categoryId,
    this.syncState,
    this.includeVoided = false,
  });

  @override
  String? get from => null;
  @override
  String? get to => null;
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
  String? get search => null;
  @override
  final bool includeVoided;
}

/// Every page of [query] at [pageSize], concatenated.
Future<List<String>> _pageThrough(
  ExpenseRepository repository,
  ExpenseQuery query, {
  required int pageSize,
}) async {
  final ids = <String>[];
  for (var offset = 0; ; offset += pageSize) {
    final page = await repository.query(query, limit: pageSize, offset: offset);
    ids.addAll(page.map((e) => e.row.id));
    if (page.length < pageSize) return ids;
  }
}

void main() {
  late AppDatabase db;
  late ExpenseRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = ExpenseRepository(db);
  });
  tearDown(() => db.close());

  group('every matching document is reachable', () {
    test(
      'more than 100 documents page through with no repeat and no gap',
      () async {
        final counts = await seedExpenseLedgerFixture(
          db,
          documents: 237,
          years: 1,
        );
        final live = counts.documents - counts.voided;
        expect(live, greaterThan(100), reason: 'the fixture must exceed 100');

        final ids = await _pageThrough(
          repository,
          const _Query(),
          pageSize: 50,
        );
        expect(ids, hasLength(live));
        expect(ids.toSet(), hasLength(live), reason: 'no document twice');

        // And the pages, concatenated, are exactly the one ordered list.
        final whole = await repository.query(const _Query(), limit: 1000);
        expect(ids, [for (final e in whole) e.row.id]);
      },
    );

    test(
      'a sync-state filter is decided before the page is cut, not after it',
      () async {
        final counts = await seedExpenseLedgerFixture(
          db,
          documents: LedgerDatasetClass.current.documents,
          years: 1,
        );
        // The defect, stated: the newest hundred hold only a few of the conflicts, so a
        // filter applied to that window could never have found the rest.
        final newest = await repository.query(const _Query(), limit: 100);
        final inNewest = newest
            .where((e) => e.syncState == SyncState.conflict)
            .length;
        expect(inNewest, lessThan(counts.conflicts ~/ 4));

        final conflicts = await _pageThrough(
          repository,
          const _Query(syncState: SyncState.conflict),
          pageSize: 20,
        );
        expect(conflicts, hasLength(counts.conflicts));
        expect(conflicts.toSet(), hasLength(counts.conflicts));
        final firstPage = await repository.query(
          const _Query(syncState: SyncState.conflict),
          limit: 20,
        );
        expect(firstPage, hasLength(20), reason: 'a filtered page is full');
        expect(
          firstPage.every((e) => e.syncState == SyncState.conflict),
          isTrue,
        );
      },
    );

    test('a hierarchy filter finds every document with a line there', () async {
      await seedExpenseLedgerFixture(db, documents: 400, years: 1);
      final all = await repository.query(const _Query(), limit: 1000);
      final expected = [
        for (final e in all)
          if (e.allocations.any((a) => a.businessUnitId == ledgerHki)) e.row.id,
      ];
      expect(
        await _pageThrough(
          repository,
          _Query(businessUnitId: ledgerHki),
          pageSize: 30,
        ),
        expected,
      );
      final category = [
        for (final e in all)
          if (e.allocations.any((a) => a.categoryId == ledgerFilterCategory))
            e.row.id,
      ];
      expect(
        await _pageThrough(
          repository,
          _Query(categoryId: ledgerFilterCategory),
          pageSize: 30,
        ),
        category,
      );
      // A shared bill belongs in both properties' views.
      final shared = all.firstWhere((e) => e.row.isShared);
      final ccr = await repository.query(
        _Query(businessUnitId: ledgerCcr),
        limit: 1000,
      );
      expect(ccr.map((e) => e.row.id), contains(shared.row.id));
      expect(expected, contains(shared.row.id));
    });
  });

  group('the order is total', () {
    test(
      'documents captured in the same instant on the same day never repeat or vanish across pages',
      () async {
        final instant = DateTime.utc(2026, 6, 15, 9);
        // Inserted out of id order, so storage order cannot stand in for the tie-break.
        for (final i in [3, 0, 6, 1, 5, 2, 4]) {
          await _insert(db, id: 'tie-$i', captured: instant);
        }
        await _insert(
          db,
          id: 'later',
          captured: instant.add(const Duration(hours: 1)),
        );
        await _insert(db, id: 'earlier-day', date: '2026-06-14');
        const expected = [
          'later',
          'tie-6',
          'tie-5',
          'tie-4',
          'tie-3',
          'tie-2',
          'tie-1',
          'tie-0',
          'earlier-day',
        ];

        expect(
          await _pageThrough(repository, const _Query(), pageSize: 2),
          expected,
        );
        // And on a plan that sorts rather than walking the ledger index — the plan a
        // pre-v22 device, or any future filter the index cannot serve, would use. Here
        // the id term in ORDER BY is the only thing deciding the ties.
        await db.customStatement('DROP INDEX ix_expenses_ledger');
        expect(
          await _pageThrough(repository, const _Query(), pageSize: 2),
          expected,
        );
      },
    );

    test(
      'a void between two page reads removes the document and shifts nothing else',
      () async {
        for (var i = 0; i < 6; i++) {
          await _insert(
            db,
            id: 'doc-$i',
            captured: DateTime.utc(2026, 6, 15, 9, i),
          );
        }
        final before = await repository.query(const _Query(), limit: 6);
        expect(before.map((e) => e.row.id), [
          'doc-5',
          'doc-4',
          'doc-3',
          'doc-2',
          'doc-1',
          'doc-0',
        ]);
        await (db.update(
          db.expenses,
        )..where((t) => t.id.equals('doc-4'))).write(
          ExpensesCompanion(
            voidedAt: Value(DateTime.utc(2026, 7, 2)),
            voidedBy: const Value('someone'),
            voidReason: const Value('Entered twice'),
          ),
        );
        final after = await repository.query(const _Query(), limit: 6);
        expect(after.map((e) => e.row.id), [
          'doc-5',
          'doc-3',
          'doc-2',
          'doc-1',
          'doc-0',
        ]);
        final withVoided = await repository.query(
          const _Query(includeVoided: true),
          limit: 6,
        );
        expect(withVoided.map((e) => e.row.id), contains('doc-4'));
      },
    );
  });

  group('what is never browsable', () {
    test(
      'a document retained after a revocation is in no page and no filter',
      () async {
        await _insert(db, id: 'kept', revoked: true, outboxStatus: 'conflict');
        await _insert(db, id: 'shown');
        for (final q in const [
          _Query(),
          _Query(includeVoided: true),
          _Query(syncState: SyncState.conflict),
          _Query(businessUnitId: 'unit-a'),
        ]) {
          final ids = (await repository.query(q)).map((e) => e.row.id);
          expect(ids, isNot(contains('kept')));
        }
        expect(
          (await repository.listRetainedAfterRevocation()).map((e) => e.row.id),
          ['kept'],
        );
      },
    );
  });

  group('one sync-state rule, in SQL and in Dart', () {
    test(
      'the ledger states what load() states, for every outbox status',
      () async {
        var i = 0;
        final cases = <String, ({String? txn, String? status})>{
          for (final status in OutboxStatus.values)
            'with-${status.name}': (
              txn: 'KI-EXP-26-27-00000${i++}',
              status: status.name,
            ),
          'pending-create': (txn: null, status: 'pending'),
          'never-sent': (txn: null, status: null),
          'synced': (txn: 'KI-EXP-26-27-000099', status: null),
        };
        for (final entry in cases.entries) {
          await _insert(
            db,
            id: entry.key,
            txn: entry.value.txn,
            outboxStatus: entry.value.status,
          );
        }
        // An intent that vanished without being reconciled: a pointer to nothing.
        await _insert(db, id: 'lost-intent');
        await (db.update(db.expenses)..where((t) => t.id.equals('lost-intent')))
            .write(const ExpensesCompanion(pendingMutationId: Value('gone')));

        final ledger = {
          for (final e in await repository.query(const _Query(), limit: 100))
            e.row.id: e.syncState,
        };
        for (final id in [...cases.keys, 'lost-intent']) {
          final single = await repository.load(id);
          expect(ledger[id], single!.syncState, reason: id);
          final filtered = await repository.query(
            _Query(syncState: single.syncState),
            limit: 100,
          );
          expect(filtered.map((e) => e.row.id), contains(id), reason: id);
        }
      },
    );

    test(
      'a status this build cannot name is shown as pending, never as synced',
      () async {
        await _insert(db, id: 'odd', outboxStatus: 'fromTheFuture');
        final ledger = await repository.query(const _Query());
        expect(ledger.single.syncState, SyncState.pendingSync);
        expect(
          await repository.query(const _Query(syncState: SyncState.synced)),
          isEmpty,
        );
      },
    );
  });

  group('the page costs the same few statements however long it is', () {
    test(
      'a page is one statement plus one per child table, through the v22 indexes',
      () async {
        final counter = StatementCounter();
        final counted = AppDatabase(
          NativeDatabase.memory().interceptWith(counter),
        );
        addTearDown(counted.close);
        await seedExpenseLedgerFixture(counted, documents: 600, years: 1);
        final repo = ExpenseRepository(counted);
        for (final limit in [10, 50, 300]) {
          counter
            ..reset()
            ..recording = true;
          final page = await repo.query(const _Query(), limit: limit);
          counter.recording = false;
          expect(page, hasLength(limit));
          expect(counter.log, hasLength(4), reason: 'limit $limit');
        }
        counter
          ..reset()
          ..recording = true;
        await repo.query(const _Query(), limit: 50);
        counter.recording = false;
        final pagePlan = await explain(counted, (
          sql: counter.log.first.sql,
          args: counter.log.first.args,
        ));
        expect(pagePlan, contains('ix_expenses_ledger'));
        expect(pagePlan, isNot(contains('TEMP B-TREE')));
        for (final child in counter.log.skip(1)) {
          expect(
            await explain(counted, (sql: child.sql, args: child.args)),
            contains('USING INDEX'),
            reason: child.sql,
          );
        }
        counter
          ..reset()
          ..recording = true;
        await repo.query(_Query(categoryId: ledgerFilterCategory), limit: 50);
        counter.recording = false;
        expect(
          await explain(counted, (
            sql: counter.log.first.sql,
            args: counter.log.first.args,
          )),
          allOf(
            contains('ix_expense_allocations_expense'),
            isNot(contains('SCAN a')),
          ),
          reason: 'a hierarchy filter must not scan the allocation table',
        );
      },
    );
  });

  group('local schema v22', () {
    late File file;
    setUp(() async => file = await createTempDatabaseFile());
    tearDown(() {
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // left for the OS temp sweep
      }
    });

    Future<Set<String>> indexes(AppDatabase db) async => {
      for (final r
          in await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .get())
        r.read<String>('name'),
    };

    test('a fresh database is born with the ledger indexes', () async {
      final fresh = AppDatabase(NativeDatabase(file));
      expect(await indexes(fresh), containsAll(ledgerIndexNames));
      expect(fresh.schemaVersion, greaterThanOrEqualTo(22));
      await fresh.close();
    });

    test('a v21 device upgrades, gains them, and keeps every row', () async {
      final seeded = AppDatabase(NativeDatabase(file));
      await seedExpenseLedgerFixture(seeded, documents: 120, years: 1);
      for (final name in ledgerIndexNames) {
        await seeded.customStatement('DROP INDEX $name');
      }
      await seeded.customStatement('PRAGMA user_version = 21');
      expect(await indexes(seeded), isNot(contains('ix_expenses_ledger')));
      final before = await ExpenseRepository(
        seeded,
      ).query(const _Query(), limit: 500);
      await seeded.close();

      final upgraded = AppDatabase(NativeDatabase(file));
      expect(await indexes(upgraded), containsAll(ledgerIndexNames));
      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), upgraded.schemaVersion);
      final after = await ExpenseRepository(
        upgraded,
      ).query(const _Query(), limit: 500);
      expect(after.map((e) => e.row.id), before.map((e) => e.row.id));
      expect(
        after.map((e) => e.allocations.length),
        before.map((e) => e.allocations.length),
      );
      await upgraded.close();
    });
  });
}
