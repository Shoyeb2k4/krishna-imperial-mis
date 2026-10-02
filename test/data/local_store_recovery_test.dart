/// Phase 8 Slice 7 — assessing and setting aside local data that will not open.
///
/// Every case runs in its own temporary folder with an in-memory key store. Nothing here
/// touches an installation anybody uses, and never the D-247 forensic database.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/local/local_store_recovery.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../support/in_memory_secret_storage.dart';

const _key = DatabaseKeyManager.storageKey;

void main() {
  late Directory dir;
  late InMemorySecretStorage store;
  late DatabaseKeyManager keys;

  LocalStoreRecovery recovery({int seed = 7}) => LocalStoreRecovery(
    directory: dir,
    keyManager: keys,
    clock: () => DateTime.utc(2026, 10, 1, 9, 30),
    random: Random(seed),
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('s7_recovery');
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

  File dbFile() => File(p.join(dir.path, localDatabaseFileName));

  String digest(File f) => sha256.convert(f.readAsBytesSync()).toString();

  /// A real database with a known mix of unsent work, written the way the app writes:
  /// the outbox through SQL, bills through the attachment table.
  Future<void> databaseWithWork({
    int pending = 0,
    int failed = 0,
    int conflict = 0,
    int rejected = 0,
    int done = 0,
    int billsWaiting = 0,
    int billsUploaded = 0,
  }) async {
    final db = await openLocalStore(keyManager: keys, directory: dir);
    var n = 0;
    Future<void> outbox(String status, int count) async {
      for (var i = 0; i < count; i++) {
        n++;
        await db.customStatement(
          'INSERT INTO sync_outbox (mutation_id, entity_type, entity_id, op, '
          'payload, status, attempt_count, created_at, next_attempt_at) '
          "VALUES (?, 'expense', ?, 'create', '{}', ?, 0, "
          "'2026-10-01T00:00:00.000Z', '2026-10-01T00:00:00.000Z')",
          ['m$n', 'e$n', status],
        );
      }
    }

    await outbox('pending', pending);
    await outbox('failed', failed);
    await outbox('conflict', conflict);
    await outbox('rejected', rejected);
    await outbox('done', done);
    await db.customStatement('PRAGMA foreign_keys = OFF');
    Future<void> bills(String state, int count) async {
      for (var i = 0; i < count; i++) {
        n++;
        final uploaded = state == 'uploaded';
        await db.customStatement(
          'INSERT INTO expense_attachments (id, org_id, expense_id, file_name, '
          'content_type, byte_size, content_hash, upload_state, storage_path, '
          'uploaded_at, uploaded_by, created_at, updated_at) '
          "VALUES (?, 'org', 'exp', 'bill.jpg', 'image/jpeg', 10, 'h', ?, ?, ?, "
          "'u', '2026-10-01T00:00:00.000Z', '2026-10-01T00:00:00.000Z')",
          [
            'a$n',
            state,
            uploaded ? 'org/x' : null,
            uploaded ? '2026-10-01T00:00:00.000Z' : null,
          ],
        );
      }
    }

    await bills('pendingUpload', billsWaiting);
    await bills('uploaded', billsUploaded);
    await db.close();
  }

  group('assess', () {
    test('no file: nothing to lose', () async {
      expect(await recovery().assess(), isA<NoLocalDataFound>());
    });

    test('counts what is unsent, and changes no byte of the file', () async {
      await databaseWithWork(
        pending: 2,
        failed: 1,
        conflict: 1,
        rejected: 2,
        done: 5,
        billsWaiting: 3,
        billsUploaded: 4,
      );
      final before = digest(dbFile());
      final result = await recovery().assess();
      expect(
        result,
        isA<UnsyncedWorkCounted>()
            .having((c) => c.queued, 'queued', 3)
            .having((c) => c.needsAttention, 'needs attention', 3)
            .having((c) => c.billsNotUploaded, 'bills', 3)
            .having((c) => c.nothingUnsent, 'nothing unsent', isFalse),
      );
      expect(digest(dbFile()), before, reason: 'assessment is read-only');
    });

    test('a status this build cannot name is counted as unsent', () async {
      await databaseWithWork(pending: 0);
      final raw = sqlite3.open(dbFile().path);
      applyEncryptionKey(raw, (await store.read(key: _key))!);
      raw.execute(
        'INSERT INTO sync_outbox (mutation_id, entity_type, entity_id, op, payload, '
        "status, attempt_count, created_at, next_attempt_at) VALUES ('mx', 'expense', "
        "'ex', 'create', '{}', 'somethingNew', 0, '2026-10-01T00:00:00.000Z', "
        "'2026-10-01T00:00:00.000Z')",
      );
      raw.close();
      expect(
        await recovery().assess(),
        isA<UnsyncedWorkCounted>().having((c) => c.queued, 'queued', 1),
      );
    });

    test('only an outbox read and found empty is "nothing unsent"', () async {
      await databaseWithWork(done: 3, billsUploaded: 2);
      expect(
        await recovery().assess(),
        isA<UnsyncedWorkCounted>().having(
          (c) => c.nothingUnsent,
          'nothing unsent',
          isTrue,
        ),
      );
    });

    test('a missing key: unknown, never zero', () async {
      await databaseWithWork(pending: 2);
      await store.delete(key: _key);
      expect(
        await recovery().assess(),
        isA<UnsyncedWorkUnknown>().having(
          (u) => u.reason,
          'reason',
          UnsyncedWorkUnknownReason.keyUnavailable,
        ),
      );
    });

    test('a damaged file: unknown, never zero', () async {
      await databaseWithWork(pending: 2);
      dbFile().writeAsBytesSync([for (var i = 0; i < 4096; i++) i & 0xff]);
      expect(
        await recovery().assess(),
        isA<UnsyncedWorkUnknown>().having(
          (u) => u.reason,
          'reason',
          UnsyncedWorkUnknownReason.unreadable,
        ),
      );
    });

    test(
      'a database left at an older version by a failed upgrade is still counted',
      () async {
        await databaseWithWork(pending: 1, conflict: 1);
        final raw = sqlite3.open(dbFile().path);
        applyEncryptionKey(raw, (await store.read(key: _key))!);
        raw.execute('PRAGMA user_version = 20');
        raw.close();
        expect(
          await recovery().assess(),
          isA<UnsyncedWorkCounted>().having((c) => c.entries, 'entries', 2),
        );
      },
    );
  });

  group('set aside and reset', () {
    test(
      'moves the database, its sidecars and staged bills aside; keeps the key aside; '
      'removes only the active key',
      () async {
        await databaseWithWork(pending: 2);
        final oldKey = (await store.read(key: _key))!;
        final journal = File('${dbFile().path}-journal')
          ..writeAsStringSync('journal');
        final staging = Directory(p.join(dir.path, 'attachments', 'exp-1'))
          ..createSync(recursive: true);
        File(p.join(staging.path, 'bill.jpg')).writeAsStringSync('bytes');
        final dbDigest = digest(dbFile());

        final record = await recovery().setAsideAndReset(
          reason: 'localDataUnreadable',
        );

        // Nothing left where the app would open it.
        expect(dbFile().existsSync(), isFalse);
        expect(journal.existsSync(), isFalse);
        expect(
          Directory(p.join(dir.path, 'attachments')).existsSync(),
          isFalse,
        );
        // Everything moved, byte for byte.
        final quarantined = File(
          p.join(record.directory.path, localDatabaseFileName),
        );
        expect(digest(quarantined), dbDigest);
        expect(
          File(
            p.join(record.directory.path, '$localDatabaseFileName-journal'),
          ).readAsStringSync(),
          'journal',
        );
        expect(
          File(
            p.join(record.directory.path, 'attachments', 'exp-1', 'bill.jpg'),
          ).readAsStringSync(),
          'bytes',
        );
        expect(
          p.isWithin(p.join(dir.path, 'recovery'), record.directory.path),
          isTrue,
        );
        // The key: aside under its own name, active entry gone.
        expect(record.keyRetained, isTrue);
        expect(await store.read(key: record.keyEntry!), oldKey);
        expect(await store.read(key: _key), isNull);
        expect(record.keyEntry, startsWith('$_key.quarantine.'));
        // And it still opens what was set aside. (The test's journal is not a real one;
        // SQLite would try to replay it, so it goes before the read.)
        File(
          p.join(record.directory.path, '$localDatabaseFileName-journal'),
        ).deleteSync();
        final reopened = sqlite3.open(
          quarantined.path,
          mode: OpenMode.readOnly,
        );
        applyEncryptionKey(reopened, oldKey);
        expect(
          reopened.select('SELECT COUNT(*) AS n FROM sync_outbox').first['n'],
          2,
        );
        reopened.close();

        // The record says what happened and holds no key material.
        final json =
            jsonDecode(
                  File(
                    p.join(record.directory.path, 'recovery.json'),
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        expect(json['reason'], 'localDataUnreadable');
        expect(json['key_retained'], isTrue);
        expect(jsonEncode(json), isNot(contains(oldKey)));
      },
    );

    test('the next start opens an empty database with a new key: nothing of the old '
        "person's data, staging or cache survives", () async {
      // A database holding a previous person's authority, reporting staging and
      // queued work — everything D-070, D-074 and D-240 protect.
      final db = await openLocalStore(keyManager: keys, directory: dir);
      await db.customStatement(
        "INSERT INTO app_meta (key, value, updated_at) VALUES "
        "('authority.snapshot', 'previous person', '2026-10-01T00:00:00.000Z'), "
        "('reporting.resume', 'staged run', '2026-10-01T00:00:00.000Z')",
      );
      await db.customStatement(
        'INSERT INTO sync_outbox (mutation_id, entity_type, entity_id, op, '
        'payload, status, attempt_count, created_at, next_attempt_at) '
        "VALUES ('m1', 'expense', 'e1', 'create', '{}', 'pending', 0, "
        "'2026-10-01T00:00:00.000Z', '2026-10-01T00:00:00.000Z')",
      );
      await db.close();
      final oldKey = (await store.read(key: _key))!;

      await recovery().setAsideAndReset(reason: 'upgradeFailed');

      final fresh = await openLocalStore(keyManager: keys, directory: dir);
      final newKey = (await store.read(key: _key))!;
      expect(newKey, isNot(oldKey));
      for (final table in fresh.allTables) {
        final n = await fresh
            .customSelect('SELECT COUNT(*) AS n FROM ${table.actualTableName}')
            .getSingle();
        expect(
          n.read<int>('n'),
          0,
          reason: '${table.actualTableName} carried something across a reset',
        );
      }
      expect(fresh.schemaVersion, 22);
      await fresh.close();
    });

    test(
      'with no key held: the bytes are kept for forensics, and the record says so',
      () async {
        await databaseWithWork(pending: 1);
        await store.delete(key: _key);
        final record = await recovery().setAsideAndReset(
          reason: 'localDataUnreadable',
        );
        expect(record.keyRetained, isFalse);
        final json =
            jsonDecode(
                  File(
                    p.join(record.directory.path, 'recovery.json'),
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        expect(json['key_retained'], isFalse);
        expect(json['note'] as String, contains('forensic'));
        final fresh = await openLocalStore(keyManager: keys, directory: dir);
        await fresh.close();
      },
    );

    test(
      'a move that fails puts back what it moved and keeps the active key',
      () async {
        await databaseWithWork(pending: 1);
        final oldKey = (await store.read(key: _key))!;
        final journal = File('${dbFile().path}-journal')
          ..writeAsStringSync('journal');
        // Predict this attempt's quarantine folder and put a folder where the database
        // would go, so the sidecar moves and then the database does not.
        final r = recovery(seed: 11);
        final id =
            '20261001T093000Z-'
            '${Random(11).nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}';
        Directory(
          p.join(
            dir.path,
            'recovery',
            'quarantine-$id',
            localDatabaseFileName,
            'blocker',
          ),
        ).createSync(recursive: true);

        await expectLater(
          r.setAsideAndReset(reason: 'localDataUnreadable'),
          throwsA(
            isA<LocalStoreResetFailed>().having(
              (e) => e.stage,
              'stage',
              'move',
            ),
          ),
        );
        expect(dbFile().existsSync(), isTrue);
        expect(journal.readAsStringSync(), 'journal', reason: 'put back');
        expect(await store.read(key: _key), oldKey, reason: 'active key kept');
        // The data is exactly as it was: it still opens.
        final db = await openLocalStore(keyManager: keys, directory: dir);
        await db.close();
      },
    );

    test(
      'a key store that will not keep the key aside stops before moving',
      () async {
        await databaseWithWork(pending: 1);
        final oldKey = (await store.read(key: _key))!;
        store.swallowWrites = true;
        await expectLater(
          recovery().setAsideAndReset(reason: 'localDataUnreadable'),
          throwsA(
            isA<LocalStoreResetFailed>().having((e) => e.stage, 'stage', 'key'),
          ),
        );
        expect(dbFile().existsSync(), isTrue);
        expect(await store.read(key: _key), oldKey);
      },
    );

    test(
      'stopped after the move and before the key is removed, the next start still '
      'works, and the old key still opens what was set aside',
      () async {
        await databaseWithWork(pending: 1);
        final oldKey = (await store.read(key: _key))!;
        // The state a kill between steps 3 and 4 leaves: files moved, key still active.
        final aside = Directory(p.join(dir.path, 'recovery', 'quarantine-x'))
          ..createSync(recursive: true);
        dbFile().renameSync(p.join(aside.path, localDatabaseFileName));

        final fresh = await openLocalStore(keyManager: keys, directory: dir);
        await fresh.close();
        expect(await store.read(key: _key), oldKey);
        final quarantined = sqlite3.open(
          p.join(aside.path, localDatabaseFileName),
          mode: OpenMode.readOnly,
        );
        applyEncryptionKey(quarantined, oldKey);
        expect(
          quarantined
              .select('SELECT COUNT(*) AS n FROM sync_outbox')
              .first['n'],
          1,
        );
        quarantined.close();
      },
    );

    test('two resets keep two separate quarantines', () async {
      await databaseWithWork(pending: 1);
      final first = await recovery(seed: 1).setAsideAndReset(reason: 'a');
      final db = await openLocalStore(keyManager: keys, directory: dir);
      await db.close();
      final second = await recovery(seed: 2).setAsideAndReset(reason: 'b');
      expect(first.directory.path, isNot(second.directory.path));
      expect(first.directory.existsSync(), isTrue);
      expect(second.directory.existsSync(), isTrue);
    });
  });
}
