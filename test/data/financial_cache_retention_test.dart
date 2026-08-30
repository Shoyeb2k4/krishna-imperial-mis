/// D-068 — what a confirmed scope revocation does to financial data already on the
/// device, and the one thing it must not do.
///
/// The Phase 3 checkpoint retained synced expenses through a revocation and recorded the
/// opposite reading as an open question for the project lead. He answered: the revoked
/// property's figures must leave the browsable cache at the moment authority is
/// confirmed, not at the next sign-out. What survives is narrower and sharper — the
/// actor's own unsent, rejected or conflicted intent, which exists nowhere else.
///
/// Three properties are load-bearing here, and each has tests that fail without it:
///
///  1. **Unknown is still not revoked.** Every deletion below is reachable only through
///     a confirmed authority. A timeout deletes nothing.
///  2. **A partially revoked shared bill is downgraded, not merely trimmed.** Leaving a
///     `complete` header beside one surviving line publishes `total − own share`, which
///     is the revoked property's share. The arithmetic is done in the test rather than
///     described, because that is the leak.
///  3. **Unsent work survives, and stops being browsable.** Both halves matter: deleting
///     it loses something irreplaceable, and listing it keeps unauthorised figures in the
///     ledger.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/expenses/expense.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_filters.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';
import 'package:uuid/uuid.dart';

import '../support/expense_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late ExpenseRepository repository;
  late OutboxRepository outbox;
  late ScopeCachePurge purge;
  late List<String> reclaimed;

  final now = DateTime.utc(2026, 6, 15, 9, 30);

  AuthoritySnapshot snapshot(Set<String> units, {bool orgWide = false}) =>
      AuthoritySnapshot(
        userId: 'user-1',
        orgId: seedOrgId,
        resolvedAt: now,
        grants: [
          if (orgWide)
            const CapabilityGrant(Capability.expenseViewAll)
          else
            for (final unit in units)
              CapabilityGrant(Capability.expenseViewAll, businessUnitId: unit),
        ],
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await seedMasterData(db, now: now);
    repository = ExpenseRepository(db);
    outbox = OutboxRepository(db);
    reclaimed = [];
    purge = ScopeCachePurge(
      db,
      reclaimStaging: (expenseId) async => reclaimed.add(expenseId),
    );
  });

  tearDown(() => db.close());

  /// Saves a document and then marks it synced, which is what makes it *canonical
  /// server-owned read data* rather than somebody's attempt — the whole distinction the
  /// policy turns on.
  Future<ExpenseDocument> synced(ExpenseDocument expense) async {
    final mutationId = const Uuid().v4();
    await repository.createLocally(
      expense,
      actorUserId: 'user-1',
      mutationId: mutationId,
      now: now,
    );
    await db.customUpdate(
      'UPDATE expenses SET pending_mutation_id = NULL, txn_number = ?, '
      'financial_year = 2026 WHERE id = ?',
      variables: [
        Variable<String>('KI-EXP-26-27-00000${expense.id.hashCode % 9 + 1}'),
        Variable<String>(expense.id),
      ],
      updates: const {},
    );
    await db.customStatement(
      "UPDATE sync_outbox SET status = 'done' WHERE mutation_id = ?",
      [mutationId],
    );
    return expense;
  }

  Future<int> count(String table) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    return row.data['c'] as int;
  }

  Future<void> attach(String expenseId) => db.customInsert(
    'INSERT INTO expense_attachments (id, org_id, expense_id, file_name, '
    'content_type, byte_size, content_hash, local_path, upload_state, '
    'storage_path, uploaded_at, attempt_count, uploaded_by, created_at, '
    "updated_at) VALUES (?, ?, ?, 'bill.jpg', 'image/jpeg', 1024, 'abc', "
    "?, 'uploaded', ?, ?, 0, 'user-1', ?, ?)",
    variables: [
      Variable<String>('att-$expenseId'),
      Variable<String>(seedOrgId),
      Variable<String>(expenseId),
      Variable<String>('/staging/$expenseId/bill.jpg'),
      Variable<String>('org/x/expenses/$expenseId/att.jpg'),
      Variable<DateTime>(now),
      Variable<DateTime>(now),
      Variable<DateTime>(now),
    ],
  );

  group(
    'the purge still refuses to act on anything but a confirmed answer',
    () {
      test('a timeout deletes no financial data whatsoever', () async {
        final bill = await synced(sharedExpense());
        await attach(bill.id);

        for (final reason in AuthorityUnavailableReason.values) {
          final result = await purge.applyTo(
            AuthorityRefresh.unavailable(reason),
            previous: snapshot({ccrId, hkiId}),
          );
          expect(result.didPurge, isFalse);
        }

        expect(await count('expenses'), 1);
        expect(await count('expense_allocations'), 2);
        expect(
          reclaimed,
          isEmpty,
          reason: 'no bytes may be deleted on the strength of a failed request',
        );
      });

      test('a first sign-in purges nothing', () async {
        await synced(simpleExpense());
        final result = await purge.applyTo(
          AuthorityRefresh.confirmed(snapshot({hkiId})),
          previous: null,
        );
        expect(result.didPurge, isFalse);
        expect(await count('expenses'), 1);
      });
    },
  );

  group('a document wholly inside the revoked property', () {
    test('is removed, with its lines, contributions and attachment', () async {
      final expense = simpleExpense(); // one CCR line, ₹200
      await synced(expense);
      await attach(expense.id);

      final result = await purge.applyTo(
        AuthorityRefresh.confirmed(snapshot({hkiId})),
        previous: snapshot({ccrId, hkiId}),
      );

      expect(result.didPurge, isTrue);
      expect(result.documentsRemoved, {expense.id});
      expect(await count('expenses'), 0);
      expect(await count('expense_allocations'), 0);
      expect(await count('expense_period_allocations'), 0);
      expect(await count('expense_attachments'), 0);
    });

    test('takes its staged bytes with it, after the transaction', () async {
      final expense = simpleExpense();
      await synced(expense);
      await attach(expense.id);

      final result = await purge.purgeUnits({ccrId});

      expect(result.stagingReclaimed, {expense.id});
      expect(
        reclaimed,
        [expense.id],
        reason:
            'deleting the row and leaving the JPEG in app-private storage retains '
            'exactly what D-063 says a user without the complete document may not have',
      );
    });

    test('leaves a document in a retained property completely alone', () async {
      final ccr = simpleExpense();
      final hki = expenseWith(lines: [line(unit: hkiId, rupees: 500)]);
      await synced(ccr);
      await synced(hki);

      await purge.purgeUnits({ccrId});

      final remaining = await db.select(db.expenses).get();
      expect(remaining.map((e) => e.id), [hki.id]);
      expect(remaining.single.visibility, 'complete');
      expect(remaining.single.documentTotalMinor, 50000);
    });
  });

  group('the partially revoked shared bill', () {
    late ExpenseDocument bill;

    setUp(() async {
      bill = sharedExpense(); // ₹58,000 = CCR ₹25,000 + HKI ₹33,000
      await synced(bill);
      await attach(bill.id);
    });

    test('keeps the retained line and drops the revoked one', () async {
      final result = await purge.purgeUnits({ccrId});

      expect(result.documentsDowngraded, {bill.id});
      expect(result.documentsRemoved, isEmpty);

      final lines = await db.select(db.expenseAllocations).get();
      expect(lines, hasLength(1));
      expect(lines.single.businessUnitId, hkiId);
      expect(lines.single.amountMinor, 3300000);

      final contributions = await db.select(db.expensePeriodAllocations).get();
      expect(contributions, hasLength(1));
      expect(contributions.single.businessUnitId, hkiId);
    });

    test(
      'is downgraded to scoped, and its document total is destroyed',
      () async {
        await purge.purgeUnits({ccrId});

        final header = await db.select(db.expenses).getSingle();
        expect(header.visibility, 'scoped');
        expect(header.documentTotalMinor, isNull);
        expect(header.visibleAmountMinor, 3300000);
        expect(
          header.isShared,
          isTrue,
          reason:
              'that the bill is shared is authorised; the other share is not',
        );
      },
    );

    test('the revoked share is not recoverable from what remains', () async {
      await purge.purgeUnits({ccrId});

      // The leak, done as arithmetic rather than described. Before the purge the device
      // held 5,800,000 and 3,300,000; their difference is 2,500,000, which is the share
      // this user has just lost the right to see.
      final row = await db.customSelect('SELECT * FROM expenses').getSingle();
      final held = row.data.values.whereType<int>().toSet();
      expect(held, isNot(contains(5800000)), reason: 'the invoice total');
      expect(
        held,
        isNot(contains(2500000)),
        reason: "the other property's share",
      );

      final everyAmount = await db
          .customSelect(
            'SELECT amount_minor AS a FROM expense_allocations '
            'UNION ALL SELECT amount_minor AS a FROM expense_period_allocations',
          )
          .get();
      expect(
        everyAmount.map((r) => r.data['a']),
        everyElement(3300000),
        reason: 'nothing but this user\'s own share is left anywhere',
      );
    });

    test(
      'loses its attachment, because it is no longer a complete document',
      () async {
        await purge.purgeUnits({ccrId});

        expect(await count('expense_attachments'), 0);
        expect(
          reclaimed,
          [bill.id],
          reason:
              'an attachment is the whole bill and says ₹58,000 on its face; D-063 '
              'gates it on exactly the predicate that just became false',
        );
      },
    );

    test('losing both properties removes it outright', () async {
      final result = await purge.purgeUnits({ccrId, hkiId});

      expect(result.documentsRemoved, {bill.id});
      expect(result.documentsDowngraded, isEmpty);
      expect(await count('expenses'), 0);
    });
  });

  group('unsent work survives, and stops being browsable', () {
    for (final status in const [
      OutboxStatus.pending,
      OutboxStatus.failed,
      OutboxStatus.rejected,
      OutboxStatus.conflict,
      OutboxStatus.blockedAuth,
    ]) {
      test('a ${status.name} intent keeps its document', () async {
        final expense = simpleExpense();
        final mutationId = const Uuid().v4();
        await repository.createLocally(
          expense,
          actorUserId: 'user-1',
          mutationId: mutationId,
          now: now,
        );
        await db.customStatement(
          'UPDATE sync_outbox SET status = ? WHERE mutation_id = ?',
          [status.name, mutationId],
        );

        final result = await purge.purgeUnits({ccrId});

        expect(result.documentsRetainedForUnsyncedWork, {expense.id});
        expect(result.documentsRemoved, isEmpty);
        expect(
          await count('expense_allocations'),
          1,
          reason:
              'retained whole — a half-deleted document cannot be inspected or '
              'reconciled, which is the only reason it was kept',
        );
        expect(await count('sync_outbox'), 1);
        expect(reclaimed, isEmpty);
      });
    }

    test('a delivered intent does not protect anything', () async {
      final expense = await synced(simpleExpense());
      final result = await purge.purgeUnits({ccrId});

      expect(result.documentsRetainedForUnsyncedWork, isEmpty);
      expect(result.documentsRemoved, {expense.id});
    });

    test('the retained document is stamped and leaves the ledger', () async {
      final expense = simpleExpense();
      await repository.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );

      await purge.purgeUnits({ccrId});

      final header = await db.select(db.expenses).getSingle();
      expect(header.scopeRevokedAt, isNotNull);

      expect(await repository.list(), isEmpty, reason: 'the ledger');
      expect(
        await repository.query(const ExpenseFilter()),
        isEmpty,
        reason: 'the filtered query',
      );
      expect(
        await repository.query(const ExpenseFilter(includeVoided: true)),
        isEmpty,
        reason: 'and no filter combination reaches it either',
      );
    });

    test('it contributes nothing to any reporting figure', () async {
      final expense = simpleExpense();
      await repository.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      expect(
        await repository.contributionTotal(periodKey: '2026-06'),
        Money.fromRupees(200),
      );

      await purge.purgeUnits({ccrId});

      expect(
        await repository.contributionTotal(periodKey: '2026-06'),
        Money.zero,
        reason:
            'an unsent attempt over a property the user no longer holds must not '
            'move a total that is presented as authorised',
      );
    });

    test('it is reachable only through the dedicated workflow', () async {
      final expense = simpleExpense();
      await repository.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      await purge.purgeUnits({ccrId});

      final retained = await repository.listRetainedAfterRevocation();
      expect(retained, hasLength(1));
      expect(retained.single.row.id, expense.id);
      expect(
        retained.single.syncState,
        SyncState.pendingSync,
        reason: 'the person who queued it can still see what became of it',
      );
      expect(retained.single.allocations, hasLength(1));
    });

    test('another signed-in user can neither push nor inherit it', () async {
      final expense = simpleExpense();
      await repository.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      await purge.purgeUnits({ccrId});

      expect(
        await outbox.dueEntries(now: now, actorUserId: 'user-2'),
        isEmpty,
        reason: 'the outbox belongs to whoever queued it (D-050)',
      );
      expect(
        await outbox.dueEntries(now: now, actorUserId: 'user-1'),
        hasLength(1),
      );
    });
  });

  group('the guarantees that do not bend', () {
    test('the outbox is never smaller afterwards', () async {
      await synced(simpleExpense());
      final pending = simpleExpense();
      await repository.createLocally(
        pending,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );

      final before = await count('sync_outbox');
      final result = await purge.purgeUnits({ccrId, hkiId});

      expect(result.outboxEntriesPreserved, before);
      expect(await count('sync_outbox'), before);
    });

    test('no foreign key is violated, including at sign-out', () async {
      final bill = await synced(sharedExpense());
      await synced(simpleExpense());
      await attach(bill.id);

      // purgeAllScopedCache is the sign-out and user-switch path: every cached unit at
      // once. This is the sequence that threw before local schema v8.
      await purge.purgeAllScopedCache();

      final violations = await db
          .customSelect('PRAGMA foreign_key_check')
          .get();
      expect(violations, isEmpty);
    });

    test('signing out leaves no financial figure for the next user', () async {
      // The scenario the project lead named: an Owner downloads a complete shared
      // invoice, then a scoped manager signs in on the same installation.
      final bill = await synced(sharedExpense());
      await attach(bill.id);

      await purge.purgeAllScopedCache();

      expect(await count('expenses'), 0);
      expect(await count('expense_allocations'), 0);
      expect(await count('expense_period_allocations'), 0);
      expect(await count('expense_attachments'), 0);
      expect(reclaimed, contains(bill.id));
    });
  });

  group('the purge is as strong as the projection it protects', () {
    test('the revoked share is not left legible in the database file', () async {
      // D-062 proved the scoped *projection* by reading the bytes of three databases,
      // because "the widget does not display it" is not protection when a SQLite file
      // opens in a text editor. A purge that only unlinks rows would be weaker than the
      // projection: the figures would sit in freed pages until something overwrote them.
      // `PRAGMA secure_delete` is what closes that, and this is the test that says so.
      final file = await createTempDatabaseFile();
      addTearDown(() => file.parent.deleteSync(recursive: true));

      final bill = sharedExpense(); // ₹58,000 = CCR ₹25,000 + HKI ₹33,000
      final owned = AppDatabase(NativeDatabase(file));
      await owned.customStatement('PRAGMA foreign_keys = ON');
      await seedMasterData(owned, now: now);
      await ExpenseRepository(owned).createLocally(
        bill,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      await owned.customStatement(
        'UPDATE expenses SET pending_mutation_id = NULL, '
        "txn_number = 'KI-EXP-26-27-000001', financial_year = 2026",
      );
      await owned.customStatement("UPDATE sync_outbox SET status = 'done'");

      // Present before, so the assertion afterwards is about the purge and not about
      // the search never having found anything.
      expect(_containsPaise(await file.readAsBytes(), 2500000), isTrue);

      await ScopeCachePurge(owned).purgeUnits({ccrId});
      await owned.close();

      final after = await file.readAsBytes();
      expect(
        _containsPaise(after, 2500000),
        isFalse,
        reason: "the revoked property's share, gone from the file itself",
      );
      expect(
        _containsPaise(after, 5800000),
        isFalse,
        reason: 'and so is the invoice total it could be derived from',
      );
      expect(
        _containsPaise(after, 3300000),
        isTrue,
        reason: 'while the share this user still holds is untouched',
      );
    });
  });

  group('every persistence surface, not only the main file', () {
    // D-070 asked for the byte-level guarantee across *all* of SQLite's on-disk
    // surfaces, not just the database file. Which sidecars exist depends on the journal
    // mode, so both modes are exercised: `delete`, which this project uses today, and
    // `wal`, which it may use later for concurrency and where the revoked figures would
    // otherwise sit in the log until something happened to check-point it.

    /// Every file SQLite may have written for this database.
    List<File> surfacesFor(File main) => [
      main,
      File('${main.path}-wal'),
      File('${main.path}-shm'),
      File('${main.path}-journal'),
    ].where((f) => f.existsSync()).toList();

    Future<File> databaseHoldingTheSharedBill({
      required String journalMode,
    }) async {
      final file = await createTempDatabaseFile();
      final owned = AppDatabase(NativeDatabase(file));
      await owned.customStatement('PRAGMA journal_mode = $journalMode');
      await owned.customStatement('PRAGMA foreign_keys = ON');
      await seedMasterData(owned, now: now);
      await ExpenseRepository(owned).createLocally(
        sharedExpense(),
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      await owned.customStatement(
        'UPDATE expenses SET pending_mutation_id = NULL, '
        "txn_number = 'KI-EXP-26-27-000001', financial_year = 2026",
      );
      await owned.customStatement("UPDATE sync_outbox SET status = 'done'");
      await owned.close();
      return file;
    }

    for (final journalMode in const ['delete', 'wal']) {
      test('in $journalMode mode the revoked share leaves every file', () async {
        final file = await databaseHoldingTheSharedBill(
          journalMode: journalMode,
        );
        addTearDown(() => file.parent.deleteSync(recursive: true));

        final db = AppDatabase(NativeDatabase(file));
        await db.customStatement('PRAGMA journal_mode = $journalMode');
        await db.customStatement('PRAGMA foreign_keys = ON');

        // Present before, in at least one surface, so the assertion afterwards is about
        // the purge and not about a search that never found anything.
        expect(
          surfacesFor(
            file,
          ).any((f) => _containsPaise(f.readAsBytesSync(), 2500000)),
          isTrue,
          reason: 'the revoked share is on disk to begin with',
        );

        final result = await ScopeCachePurge(db).purgeUnits({ccrId});
        expect(result.physicalReclaim, isNotNull);
        expect(
          result.physicalReclaim,
          contains(journalMode),
          reason: 'the mode is read, not assumed',
        );

        // Scanned with the database still **open**, deliberately. Closing it makes
        // SQLite check-point and remove the WAL by itself, which would hide the very
        // frames this test exists to look for — the control run proved exactly that:
        // with the checkpoint removed and the scan after close, the test still passed.
        // The realistic moment is also this one: the application is running, the purge
        // has just happened, and the question is what is on the disk right now.
        for (final surface in surfacesFor(file)) {
          final bytes = surface.readAsBytesSync();
          expect(
            _containsPaise(bytes, 2500000),
            isFalse,
            reason:
                "the revoked property's share survived in "
                '${surface.path.split(Platform.pathSeparator).last}',
          );
          expect(
            _containsPaise(bytes, 5800000),
            isFalse,
            reason:
                'the invoice total survived in '
                '${surface.path.split(Platform.pathSeparator).last}',
          );
        }

        // And what the user still holds is untouched, in the main file.
        expect(
          _containsPaise(file.readAsBytesSync(), 3300000),
          isTrue,
          reason: 'the retained share is not collateral damage',
        );
        await db.close();
      });
    }

    test('a truncating checkpoint is only issued in WAL mode', () async {
      // The expensive step is deliberately not on the path of every ordinary delete.
      final file = await databaseHoldingTheSharedBill(journalMode: 'delete');
      addTearDown(() => file.parent.deleteSync(recursive: true));

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final report = await ScopeCachePurge(db).reclaimPhysicalStorage();
      expect(report, contains('no write-ahead log'));
    });

    test('the staged attachment directory goes with the document', () async {
      // The bytes of a bill are not in the database at all, so no pragma reaches them.
      final staging = Directory(
        '${(await createTempDatabaseFile()).parent.path}/staging',
      )..createSync(recursive: true);
      addTearDown(() {
        if (staging.parent.existsSync()) {
          staging.parent.deleteSync(recursive: true);
        }
      });

      final bill = File('${staging.path}/receipt.jpg')
        ..writeAsBytesSync(List.filled(64, 7));
      expect(bill.existsSync(), isTrue);

      final expense = simpleExpense();
      await synced(expense);
      await attach(expense.id);

      final removed = <String>[];
      final purgeWithFiles = ScopeCachePurge(
        db,
        reclaimStaging: (expenseId) async {
          removed.add(expenseId);
          if (staging.existsSync()) staging.deleteSync(recursive: true);
        },
      );
      await purgeWithFiles.purgeUnits({ccrId});

      expect(removed, [expense.id]);
      expect(
        bill.existsSync(),
        isFalse,
        reason:
            'an attachment the user may no longer retrieve is not left on disk',
      );
    });
  });

  group('restoring the scope makes retained work browsable again', () {
    test(
      'a confirmed authority that covers the unit clears the stamp',
      () async {
        final expense = simpleExpense();
        await repository.createLocally(
          expense,
          actorUserId: 'user-1',
          mutationId: const Uuid().v4(),
          now: now,
        );
        await purge.purgeUnits({ccrId});
        expect(await repository.list(), isEmpty);

        await purge.applyTo(
          AuthorityRefresh.confirmed(snapshot({ccrId, hkiId})),
          previous: snapshot({hkiId}),
        );

        final visible = await repository.list();
        expect(visible, hasLength(1));
        expect(visible.single.row.scopeRevokedAt, isNull);
      },
    );

    test('an org-wide grant covers everything', () async {
      final expense = simpleExpense();
      await repository.createLocally(
        expense,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      await purge.purgeUnits({ccrId});

      await purge.applyTo(
        AuthorityRefresh.confirmed(snapshot(const {}, orgWide: true)),
        previous: snapshot({hkiId}),
      );

      expect(await repository.list(), hasLength(1));
    });

    test('a partially restored shared document stays hidden', () async {
      final bill = sharedExpense();
      await repository.createLocally(
        bill,
        actorUserId: 'user-1',
        mutationId: const Uuid().v4(),
        now: now,
      );
      await purge.purgeUnits({ccrId, hkiId});
      expect(await repository.list(), isEmpty);

      // Only Crystal Canopy comes back. The document also charges Hotel Krishna.
      await purge.applyTo(
        AuthorityRefresh.confirmed(snapshot({ccrId})),
        previous: snapshot(const {}),
      );

      expect(
        await repository.list(),
        isEmpty,
        reason:
            'the strict reading: a shared document becomes browsable only when every '
            'property it charges is reachable again',
      );
    });
  });
}

/// Whether a paise amount appears in the raw file as SQLite would have stored it.
///
/// SQLite writes integers big-endian, in the narrowest width that fits, so the search is
/// for the byte sequences a record could actually hold rather than for a decimal string.
bool _containsPaise(List<int> bytes, int value) {
  for (final width in const [3, 4, 6, 8]) {
    final needle = [
      for (var i = width - 1; i >= 0; i--) (value >> (8 * i)) & 0xff,
    ];
    for (var i = 0; i + needle.length <= bytes.length; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
  }
  return false;
}
