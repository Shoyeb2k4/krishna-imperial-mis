/// Phase 8 Slice 7 — what start-up does when the local database will not open.
///
/// Every case builds a **real** failing database in its own temporary folder, with a
/// key held in an in-memory store, and opens it the way `bootstrap()` does
/// (`openLocalStore`). Nothing here reads, opens or moves an installation anybody uses —
/// and never the D-247 forensic database.
///
/// Before Slice 7 (recorded in D-329): a missing key was replaced with a new one and then
/// reported as an unreadable file; a lock was reported as unreadable; a lock during the
/// first write reached the screen as a raw SQLite message; a folder that could not be
/// created reached it with its path; and an upgrade interrupted part-way left a database
/// no later start could ever upgrade.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/startup/startup_failure.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/in_memory_secret_storage.dart';

const _key = DatabaseKeyManager.storageKey;

/// An [AppDatabase] whose upgrade fails after every real step has run — the worst place
/// for it to fail, because everything before it would otherwise be kept.
class _UpgradeFailsAtTheEnd extends AppDatabase {
  _UpgradeFailsAtTheEnd(super.executor);

  @override
  Future<void> runUpgradeSteps(Migrator m, int from, int to) async {
    await super.runUpgradeSteps(m, from, to);
    throw StateError('interrupted after the last upgrade step');
  }
}

/// A fresh database whose creation is interrupted after the tables exist.
class _CreateFailsAtTheEnd extends AppDatabase {
  _CreateFailsAtTheEnd(super.executor);

  @override
  Future<void> runCreateSteps(Migrator m) async {
    await super.runCreateSteps(m);
    throw StateError('interrupted after the tables were created');
  }
}

void main() {
  late Directory dir;
  late InMemorySecretStorage store;
  late DatabaseKeyManager keys;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('s7_startup');
    store = InMemorySecretStorage();
    keys = DatabaseKeyManager(storage: store);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // left for the OS temp sweep
    }
  });

  File dbFile() => File('${dir.path}/$localDatabaseFileName');

  Future<Object> failureOf(Future<AppDatabase> Function() open) async {
    try {
      final db = await open();
      await db.close();
    } on Object catch (error) {
      return error;
    }
    fail('expected the open to fail');
  }

  Future<void> createHealthyDatabase() async {
    final db = await openLocalStore(keyManager: keys, directory: dir);
    await db.close();
  }

  int userVersion(String key) {
    final raw = sqlite3.open(dbFile().path);
    try {
      applyEncryptionKey(raw, key);
      return raw.select('PRAGMA user_version').first.values.first! as int;
    } finally {
      raw.close();
    }
  }

  group('each failure is classified for what it is', () {
    test('a fresh installation opens, at the current schema', () async {
      await createHealthyDatabase();
      final key = (await store.read(key: _key))!;
      expect(
        userVersion(key),
        AppDatabase(NativeDatabase.memory()).schemaVersion,
      );
    });

    test('a damaged file is unreadable, and a reset may be offered', () async {
      // A real installation's key, and its file overwritten.
      await createHealthyDatabase();
      dbFile().writeAsBytesSync([
        for (var i = 0; i < 8192; i++) (i * 37) & 0xff,
      ]);
      final error = await failureOf(
        () => openLocalStore(keyManager: keys, directory: dir),
      );
      expect(error, isA<EncryptedDatabaseUnreadable>());
      final failure = StartupFailure.classify(error);
      expect(failure.kind, StartupFailureKind.localDataUnreadable);
      expect(failure.permitsReset, isTrue);
    });

    test(
      'a missing key for an existing file is named as missing, and no key is created',
      () async {
        await createHealthyDatabase();
        await store.delete(key: _key);

        final error = await failureOf(
          () => openLocalStore(keyManager: keys, directory: dir),
        );
        expect(
          error,
          isA<DatabaseKeyUnavailable>().having(
            (e) => e.problem,
            'problem',
            DatabaseKeyProblem.missingForExistingDatabase,
          ),
        );
        // Before Slice 7 a new key was written here, turning "missing" into "wrong".
        expect(await store.read(key: _key), isNull);
        expect(
          StartupFailure.classify(error).kind,
          StartupFailureKind.localDataUnreadable,
        );
      },
    );

    test(
      'the wrong key is unreadable, and the stored key is untouched',
      () async {
        await createHealthyDatabase();
        await store.write(key: _key, value: 'f' * 64);
        final error = await failureOf(
          () => openLocalStore(keyManager: keys, directory: dir),
        );
        expect(error, isA<EncryptedDatabaseUnreadable>());
        expect(await store.read(key: _key), 'f' * 64);
        expect(StartupFailure.classify(error).permitsReset, isTrue);
      },
    );

    test('a malformed stored key is unreadable, never replaced', () async {
      await store.write(key: _key, value: 'not-a-key');
      final error = await failureOf(
        () => openLocalStore(keyManager: keys, directory: dir),
      );
      expect(
        StartupFailure.classify(error).kind,
        StartupFailureKind.localDataUnreadable,
      );
      expect(await store.read(key: _key), 'not-a-key');
    });

    test(
      'a secure store that cannot be read is worth retrying, and is not offered a reset',
      () async {
        final error = await failureOf(
          () => openLocalStore(
            keyManager: DatabaseKeyManager(storage: _UnreadableStore()),
            directory: dir,
          ),
        );
        final failure = StartupFailure.classify(error);
        expect(failure.kind, StartupFailureKind.keyStoreUnavailable);
        expect(failure.permitsReset, isFalse);
      },
    );

    test(
      'a secure store that will not keep a new key is not offered a reset',
      () async {
        final error = await failureOf(
          () => openLocalStore(
            keyManager: DatabaseKeyManager(
              storage: InMemorySecretStorage()..swallowWrites = true,
            ),
            directory: dir,
          ),
        );
        expect(
          StartupFailure.classify(error).kind,
          StartupFailureKind.keyStoreUnavailable,
        );
      },
    );

    test('a folder that cannot be created is a storage problem', () async {
      final blocked = File('${dir.path}/blocked')..writeAsStringSync('x');
      final error = await failureOf(
        () => openLocalStore(
          keyManager: keys,
          directory: Directory(blocked.path),
        ),
      );
      expect(error, isA<FileSystemException>());
      final failure = StartupFailure.classify(error);
      expect(failure.kind, StartupFailureKind.storage);
      expect(failure.permitsReset, isFalse);
    });
  });

  group('a lock is not damage', () {
    late Database holder;

    setUp(() async {
      await createHealthyDatabase();
      holder = sqlite3.open(dbFile().path);
      applyEncryptionKey(holder, (await store.read(key: _key))!);
    });

    tearDown(() {
      try {
        holder.execute('ROLLBACK');
      } on SqliteException {
        // nothing open
      }
      holder.close();
    });

    test(
      'another connection holding the file exclusively is "in use", not unreadable',
      () async {
        holder.execute('BEGIN EXCLUSIVE');
        final error = await failureOf(
          () => openLocalStore(keyManager: keys, directory: dir),
        );
        // Before Slice 7: EncryptedDatabaseUnreadable (sqlite 5).
        expect(error, isNot(isA<EncryptedDatabaseUnreadable>()));
        final failure = StartupFailure.classify(error);
        expect(failure.kind, StartupFailureKind.inUse);
        expect(failure.permitsReset, isFalse);
      },
    );

    test(
      'the file is released for a retry once the other holder is gone',
      () async {
        holder.execute('BEGIN EXCLUSIVE');
        await failureOf(() => openLocalStore(keyManager: keys, directory: dir));
        holder.execute('ROLLBACK');
        final db = await openLocalStore(keyManager: keys, directory: dir);
        await db.close();
      },
    );

    test(
      'the busy timeout is 0: a lock fails at once, it does not wait (measured, D-329)',
      () async {
        final db = await openLocalStore(keyManager: keys, directory: dir);
        final row = await db.customSelect('PRAGMA busy_timeout').getSingle();
        expect(row.data.values.single, 0);
        holder.execute('BEGIN EXCLUSIVE');
        final stopwatch = Stopwatch()..start();
        await expectLater(
          db.customStatement('UPDATE app_meta SET value = value'),
          throwsA(
            isA<SqliteException>().having(
              (e) => SqliteResult.primary(e.resultCode),
              'code',
              5,
            ),
          ),
        );
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
        holder.execute('ROLLBACK');
        await db.close();
      },
    );
  });

  group('an interrupted upgrade changes nothing', () {
    /// A healthy database moved back to v20: the v21 column dropped, the v22 indexes
    /// dropped, the version set. Opening it runs both upgrade steps.
    Future<String> v20Database() async {
      await createHealthyDatabase();
      final key = (await store.read(key: _key))!;
      final raw = sqlite3.open(dbFile().path);
      applyEncryptionKey(raw, key);
      raw.execute(
        'ALTER TABLE owner_settlement_coverage DROP COLUMN ownership_start_date',
      );
      for (final name in [
        'ix_expense_allocations_expense',
        'ix_expense_period_allocations_expense',
        'ix_expense_attachments_expense',
        'ix_expenses_ledger',
      ]) {
        raw.execute('DROP INDEX $name');
      }
      raw.execute(
        "INSERT INTO app_meta (key, value, updated_at) "
        "VALUES ('probe', 'kept', '2026-10-01T00:00:00.000Z')",
      );
      raw.execute('PRAGMA user_version = 20');
      raw.close();
      return key;
    }

    bool hasStartDateColumn(String key) {
      final raw = sqlite3.open(dbFile().path);
      try {
        applyEncryptionKey(raw, key);
        return raw
            .select(
              "SELECT 1 FROM pragma_table_info('owner_settlement_coverage') "
              "WHERE name = 'ownership_start_date'",
            )
            .isNotEmpty;
      } finally {
        raw.close();
      }
    }

    test(
      'the version is not advanced, no step is kept, and a retry succeeds',
      () async {
        final key = await v20Database();

        final error = await failureOf(
          () => openLocalStore(
            keyManager: keys,
            directory: dir,
            build: _UpgradeFailsAtTheEnd.new,
          ),
        );
        expect(
          error,
          isA<LocalSchemaMigrationFailed>()
              .having((e) => e.from, 'from', 20)
              .having((e) => e.to, 'to', 22),
        );
        final failure = StartupFailure.classify(error);
        expect(failure.kind, StartupFailureKind.upgradeFailed);
        expect(failure.permitsReset, isTrue);

        // Nothing the upgrade did survived it.
        expect(userVersion(key), 20);
        expect(hasStartDateColumn(key), isFalse);

        // And the next start — the ordinary build — upgrades cleanly. Before Slice 7 it
        // failed here for ever on `duplicate column name: ownership_start_date`.
        final db = await openLocalStore(keyManager: keys, directory: dir);
        final kept = await db
            .customSelect("SELECT value FROM app_meta WHERE key = 'probe'")
            .getSingle();
        expect(kept.read<String>('value'), 'kept');
        await db.close();
        expect(userVersion(key), 22);
        expect(hasStartDateColumn(key), isTrue);
      },
    );

    test(
      'the failure is deterministic: the same attempt fails the same way',
      () async {
        await v20Database();
        for (var i = 0; i < 2; i++) {
          final error = await failureOf(
            () => openLocalStore(
              keyManager: keys,
              directory: dir,
              build: _UpgradeFailsAtTheEnd.new,
            ),
          );
          expect(error, isA<LocalSchemaMigrationFailed>());
        }
      },
    );

    test(
      'the upgraded database passes its integrity and foreign-key checks',
      () async {
        await v20Database();
        final db = await openLocalStore(keyManager: keys, directory: dir);
        final integrity = await db.customSelect('PRAGMA integrity_check').get();
        expect(integrity.single.data.values.single, 'ok');
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        await db.close();
      },
    );

    test(
      'an interrupted creation leaves an empty file the next start creates cleanly',
      () async {
        final error = await failureOf(
          () => openLocalStore(
            keyManager: keys,
            directory: dir,
            build: _CreateFailsAtTheEnd.new,
          ),
        );
        expect(
          error,
          isA<LocalSchemaMigrationFailed>().having((e) => e.from, 'from', null),
        );
        // Creating a fresh database has nothing worth resetting.
        expect(
          StartupFailure.classify(error).kind,
          StartupFailureKind.unexpected,
        );
        final key = (await store.read(key: _key))!;
        expect(userVersion(key), 0);
        final db = await openLocalStore(keyManager: keys, directory: dir);
        await db.close();
        expect(userVersion(key), 22);
      },
    );
  });

  group('the cause decides, even inside an upgrade', () {
    test('a full disk during an upgrade is storage, not an upgrade defect', () {
      final failure = StartupFailure.classify(
        LocalSchemaMigrationFailed(
          from: 21,
          to: 22,
          cause: SqliteException(
            extendedResultCode: 13,
            message: 'database or disk is full',
          ),
        ),
      );
      expect(failure.kind, StartupFailureKind.storage);
      expect(failure.permitsReset, isFalse);
    });

    test('a lock during an upgrade is "in use"', () {
      expect(
        StartupFailure.classify(
          LocalSchemaMigrationFailed(
            from: 21,
            to: 22,
            cause: SqliteException(
              extendedResultCode: 5,
              message: 'database is locked',
            ),
          ),
        ).kind,
        StartupFailureKind.inUse,
      );
    });

    test('damage found during an upgrade is unreadable', () {
      expect(
        StartupFailure.classify(
          LocalSchemaMigrationFailed(
            from: 21,
            to: 22,
            cause: SqliteException(
              extendedResultCode: 11,
              message: 'database disk image is malformed',
            ),
          ),
        ).kind,
        StartupFailureKind.localDataUnreadable,
      );
    });

    test(
      'a full disk that SQLite already rolled back is still storage (drift wraps it)',
      () {
        final failure = StartupFailure.classify(
          CouldNotRollBackException(
            SqliteException(extendedResultCode: 13, message: 'disk is full'),
            StackTrace.empty,
            SqliteException(extendedResultCode: 1, message: 'no transaction'),
          ),
        );
        expect(failure.kind, StartupFailureKind.storage);
        expect(failure.permitsReset, isFalse);
      },
    );

    test('an extended result code is read by its primary code', () {
      // SQLITE_IOERR_WRITE = 778 = 10 | (3 << 8).
      expect(
        StartupFailure.classify(
          SqliteException(extendedResultCode: 778, message: 'disk I/O error'),
        ).kind,
        StartupFailureKind.storage,
      );
    });

    test('anything unrecognised is never answered with a reset', () {
      for (final error in <Object>[
        StateError('x'),
        ArgumentError('x'),
        Exception('x'),
        SqliteException(extendedResultCode: 1, message: 'SQL logic error'),
      ]) {
        final failure = StartupFailure.classify(error);
        expect(failure.kind, StartupFailureKind.unexpected);
        expect(failure.permitsReset, isFalse);
      }
    });

    test('only unreadable data and a failed upgrade permit a reset', () {
      expect(
        {
          for (final kind in StartupFailureKind.values)
            if (StartupFailure(kind).permitsReset) kind,
        },
        {
          StartupFailureKind.localDataUnreadable,
          StartupFailureKind.upgradeFailed,
        },
      );
    });
  });
}

class _UnreadableStore extends InMemorySecretStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw Exception('keystore locked');
}
