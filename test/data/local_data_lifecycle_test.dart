/// Sign-out and erasure semantics (docs/ARCHITECTURE.md §8.2).
///
/// The rule being defended: nothing may silently destroy an entry the server has never
/// seen.
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/local/local_data_lifecycle.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';

import '../support/in_memory_secret_storage.dart';

const String testKey =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

/// Mutation ids are UUIDs — the server stores `mutation_id` as `uuid`, so a fixture
/// using a short label would be refused as a malformed argument before any business rule
/// ran. Derived from a name to stay readable and deterministic.
String mid(String name) =>
    const Uuid().v5('c0ffee00-0000-4000-8000-000000000000', name);

void main() {
  late Directory workspace;
  late File dbFile;
  late AppDatabase db;
  late OutboxRepository outbox;
  late DatabaseKeyManager keyManager;
  late LocalDataLifecycle lifecycle;
  late int sessionsCleared;

  setUpAll(() {
    // Every test here legitimately opens a fresh AppDatabase over its own executor, so
    // drift's "created multiple times" warning is noise in this file only.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync('krishna_mis_lifecycle');
    dbFile = File('${workspace.path}${Platform.pathSeparator}lifecycle.db');
    db = openEncryptedDatabaseAt(dbFile, testKey);
    outbox = OutboxRepository(db);
    keyManager = DatabaseKeyManager(storage: InMemorySecretStorage());
    await keyManager.obtainKey();
    sessionsCleared = 0;
    lifecycle = LocalDataLifecycle(
      outbox: outbox,
      keyManager: keyManager,
      resolveFile: () async => dbFile,
    );
  });

  tearDown(() async {
    // Windows holds a lock on an open database file, so close before deleting.
    try {
      await db.close();
    } on Object {
      // Already closed by the test under way — that is the normal path for erasure.
    }
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  Future<void> clearSession() async => sessionsCleared++;

  Future<void> queueOne(String id) => outbox.enqueue(
    PendingMutation(
      mutationId: mid(id),
      entityType: 'expense',
      entityId: 'exp-$id',
      op: MutationOp.create,
      payload: const {'amount_minor': 1840000, 'vendor': 'Sharma Traders'},
      createdAt: DateTime.utc(2026, 6, 15),
    ),
    now: DateTime.utc(2026, 6, 15),
  );

  group('sign out', () {
    test('clears the session and keeps the local database', () async {
      await queueOne('mut-1');

      final outcome = await lifecycle.signOut(clearSession: clearSession);

      expect(sessionsCleared, 1);
      expect(outcome.localDataRetained, isTrue);
      expect(outcome.pendingCount, 1);
      expect(dbFile.existsSync(), isTrue);
      expect(await lifecycle.hasUsableKey(), isTrue);
      // The queued entry is untouched — it exists nowhere else.
      expect(await outbox.unsyncedCount(), 1);
    });

    test('reports zero pending when everything has synced', () async {
      final outcome = await lifecycle.signOut(clearSession: clearSession);
      expect(outcome.pendingCount, 0);
    });
  });

  group('erase local data', () {
    test('refuses while entries are queued, and names the count', () async {
      await queueOne('mut-1');
      await queueOne('mut-2');

      await expectLater(
        lifecycle.eraseLocalData(database: db, clearSession: clearSession),
        throwsA(
          isA<UnsyncedDataPending>().having((e) => e.pendingCount, 'count', 2),
        ),
      );

      // Refusal must be total: nothing cleared, nothing deleted.
      expect(sessionsCleared, 0);
      expect(dbFile.existsSync(), isTrue);
      expect(await lifecycle.hasUsableKey(), isTrue);
      expect(await outbox.unsyncedCount(), 2);
    });

    test('erases the database and the key when nothing is pending', () async {
      await lifecycle.eraseLocalData(database: db, clearSession: clearSession);

      expect(sessionsCleared, 1);
      expect(dbFile.existsSync(), isFalse);
      expect(await lifecycle.hasUsableKey(), isFalse);
    });

    test(
      'force erases despite pending work, for a typed confirmation only',
      () async {
        await queueOne('mut-1');
        await lifecycle.eraseLocalData(
          database: db,
          clearSession: clearSession,
          force: true,
        );
        expect(dbFile.existsSync(), isFalse);
        expect(await lifecycle.hasUsableKey(), isFalse);
      },
    );

    test('removes the WAL and shared-memory sidecars too', () async {
      final wal = File('${dbFile.path}-wal')..writeAsStringSync('x');
      final shm = File('${dbFile.path}-shm')..writeAsStringSync('x');

      await lifecycle.eraseLocalData(database: db, clearSession: clearSession);

      // Leaving these behind would leave encrypted page data on disk after the user was
      // told their data was erased.
      expect(wal.existsSync(), isFalse);
      expect(shm.existsSync(), isFalse);
    });
  });

  group('key loss', () {
    test('a database whose key is gone cannot be opened, and says so', () async {
      await db
          .into(db.appMeta)
          .insert(
            AppMetaCompanion.insert(
              key: 'probe',
              value: 'Sharma Traders',
              updatedAt: DateTime.utc(2026, 6, 15),
            ),
          );
      await db.close();

      // The OS keystore was reset, or the data was restored onto another device.
      await keyManager.deleteKey();
      expect(await lifecycle.hasUsableKey(), isFalse);

      final freshKey = await DatabaseKeyManager(
        storage: InMemorySecretStorage(),
      ).obtainKey();
      final reopened = openEncryptedDatabaseAt(dbFile, freshKey);
      await expectLater(
        reopened.select(reopened.appMeta).get(),
        throwsA(anything),
        reason: 'a lost key must fail loudly, never present an empty database',
      );
      await reopened.close();
    });
  });
}
