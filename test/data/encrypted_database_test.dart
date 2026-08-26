/// Proof that the local database is genuinely encrypted at rest.
///
/// This runs on the host (Windows) as part of the normal suite. The matching
/// on-device proof — including platform-secure key storage — lives in
/// `integration_test/encrypted_storage_test.dart` and must pass on **both** Android and
/// Windows before Phase 1 is complete (docs/ARCHITECTURE.md §8.3).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:sqlite3/sqlite3.dart';

const String keyA =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90'
    'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const String keyB =
    'ffffffffffffffffffffffffffffffff'
    'ffffffffffffffffffffffffffffffff';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('krishna_mis_enc_test');
  });

  tearDown(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  File dbFile(String name) =>
      File('${workspace.path}${Platform.pathSeparator}$name');

  test('the SQLite build in use supports encryption at all', () {
    // If this fails, the `hooks.user_defines.sqlite3.source` setting in pubspec.yaml is
    // not taking effect and nothing below is meaningful. Fail here, loudly, rather than
    // shipping a database that silently ignores PRAGMA key.
    final file = dbFile('cipher_probe.db');
    final db = sqlite3.open(file.path);
    addTearDown(db.close);

    db.execute("PRAGMA key = \"x'$keyA'\";");
    db.execute('CREATE TABLE probe (id INTEGER PRIMARY KEY);');
    db.close();

    expect(
      isFileEncrypted(file),
      isTrue,
      reason:
          'PRAGMA key did not encrypt the file — the plain SQLite build is in use. '
          'Check hooks.user_defines.sqlite3.source in pubspec.yaml.',
    );
  });

  test('a database written with a key cannot be read without one', () async {
    final file = dbFile('secrets.db');
    final db = openEncryptedDatabaseAt(file, keyA);
    await OutboxRepository(db).enqueue(
      PendingMutation(
        mutationId: 'mut-secret',
        entityType: 'expense',
        entityId: 'exp-secret',
        op: MutationOp.create,
        payload: const {'amount_minor': 845000, 'vendor': 'Sharma Traders'},
        createdAt: DateTime.utc(2026, 6, 15),
      ),
      now: DateTime.utc(2026, 6, 15),
    );
    await db.close();

    expect(file.existsSync(), isTrue);
    expect(isFileEncrypted(file), isTrue);
  });

  test('the plaintext never appears in the file on disk', () async {
    final file = dbFile('vendor.db');
    final db = openEncryptedDatabaseAt(file, keyA);
    await OutboxRepository(db).enqueue(
      PendingMutation(
        mutationId: 'mut-1',
        entityType: 'expense',
        entityId: 'exp-1',
        op: MutationOp.create,
        payload: const {'vendor': 'Sharma Traders', 'amount_minor': 1840000},
        createdAt: DateTime.utc(2026, 6, 15),
      ),
      now: DateTime.utc(2026, 6, 15),
    );
    await db.close();

    final bytes = file.readAsBytesSync();
    final asText = String.fromCharCodes(bytes);

    // A lost laptop must not yield vendor names and amounts to a hex editor.
    expect(asText, isNot(contains('Sharma Traders')));
    expect(asText, isNot(contains('1840000')));
    // An unencrypted SQLite file always begins with this header.
    expect(asText.startsWith('SQLite format 3'), isFalse);
  });

  test('the wrong key is refused rather than returning empty data', () async {
    final file = dbFile('wrongkey.db');
    final db = openEncryptedDatabaseAt(file, keyA);
    await db
        .into(db.appMeta)
        .insert(
          AppMetaCompanion.insert(
            key: 'install_id',
            value: 'test',
            updatedAt: DateTime.utc(2026, 6, 15),
          ),
        );
    await db.close();

    final withWrongKey = openEncryptedDatabaseAt(file, keyB);
    // Silently reporting "no rows" would be far worse than failing: it would look like
    // data loss and could prompt someone to re-enter transactions that already exist.
    await expectLater(
      withWrongKey.select(withWrongKey.appMeta).get(),
      throwsA(anything),
    );
    await withWrongKey.close();
  });

  test(
    'data written in one session is readable in the next with the same key',
    () async {
      final file = dbFile('persist.db');

      final first = openEncryptedDatabaseAt(file, keyA);
      await first
          .into(first.appMeta)
          .insert(
            AppMetaCompanion.insert(
              key: 'install_id',
              value: 'krishna-install-001',
              updatedAt: DateTime.utc(2026, 6, 15),
            ),
          );
      await first.close();

      final second = openEncryptedDatabaseAt(file, keyA);
      final rows = await second.select(second.appMeta).get();
      expect(rows.single.value, 'krishna-install-001');
      await second.close();
    },
  );

  test(
    'a queued mutation survives a full close and reopen of the encrypted file',
    () async {
      final file = dbFile('outbox_persist.db');

      final first = openEncryptedDatabaseAt(file, keyA);
      await OutboxRepository(first).enqueue(
        PendingMutation(
          mutationId: 'mut-offline',
          entityType: 'expense',
          entityId: 'exp-offline',
          op: MutationOp.create,
          payload: const {'amount_minor': 845000},
          createdAt: DateTime.utc(2026, 6, 15),
        ),
        now: DateTime.utc(2026, 6, 15),
      );
      await first.close();

      final second = openEncryptedDatabaseAt(file, keyA);
      expect(await OutboxRepository(second).unsyncedCount(), 1);
      await second.close();
    },
  );
}
