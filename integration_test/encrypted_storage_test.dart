/// On-device proof that encrypted local storage and platform-secure key handling
/// actually work — on **both** Android and Windows.
///
/// The owner's instruction was explicit: prove this in Phase 1, not near release
/// (docs/ARCHITECTURE.md §8.3, docs/DECISIONS.md D-022). Unlike the host-side test,
/// this exercises the real Android Keystore / Windows DPAPI path and the real
/// application storage directory.
///
/// Run with:
///   flutter test integration_test/encrypted_storage_test.dart -d windows
///   flutter test integration_test/encrypted_storage_test.dart -d `android-device`
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final platform = Platform.operatingSystem;

  setUp(() async {
    // Each run starts from a known state: no key, no database file.
    await DatabaseKeyManager().deleteKey();
    final file = await resolveDatabaseFile();
    if (file.existsSync()) file.deleteSync();
  });

  group('platform-secure key storage on $platform', () {
    test('generates a 256-bit key on first run and persists it', () async {
      final manager = DatabaseKeyManager();
      expect(await manager.hasKey(), isFalse);

      final key = await manager.obtainKey();
      expect(key.length, 64, reason: '256 bits as lowercase hex');
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(key), isTrue);
      expect(await manager.hasKey(), isTrue);

      // A separate manager instance — as after an app restart — reads the same key
      // back out of the OS keystore.
      expect(await DatabaseKeyManager().obtainKey(), key);
    });

    test('two installations would not share a key', () async {
      final first = await DatabaseKeyManager().obtainKey();
      await DatabaseKeyManager().deleteKey();
      final second = await DatabaseKeyManager().obtainKey();
      expect(second, isNot(first));
    });

    test('deleting the key removes it from secure storage', () async {
      await DatabaseKeyManager().obtainKey();
      await DatabaseKeyManager().deleteKey();
      expect(await DatabaseKeyManager().hasKey(), isFalse);
    });
  });

  group('encrypted database on $platform', () {
    test('opens, writes, and survives a close and reopen', () async {
      final db = await openEncryptedDatabase();
      final outbox = OutboxRepository(db);

      await outbox.enqueue(
        PendingMutation(
          mutationId: 'integration-mut-1',
          entityType: 'expense',
          entityId: 'integration-exp-1',
          op: MutationOp.create,
          payload: const {
            'amount_minor': 845000,
            'vendor': 'Sharma Traders',
            'business_date': '2026-06-15',
          },
          createdAt: DateTime.now().toUtc(),
        ),
        now: DateTime.now().toUtc(),
      );
      expect(await outbox.unsyncedCount(), 1);
      await db.close();

      // Reopen exactly as the app would on next launch: key from the OS keystore.
      final reopened = await openEncryptedDatabase();
      final recovered = OutboxRepository(reopened);
      expect(await recovered.unsyncedCount(), 1);
      expect(
        await recovered.statusOf('integration-mut-1'),
        OutboxStatus.pending,
        reason: 'a queued offline save must survive an app restart',
      );
      await reopened.close();
    });

    test('the file on disk is genuinely encrypted', () async {
      final db = await openEncryptedDatabase();
      await db
          .into(db.appMeta)
          .insert(
            AppMetaCompanion.insert(
              key: 'probe',
              value: 'Sharma Traders',
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      await db.close();

      final file = await resolveDatabaseFile();
      expect(file.existsSync(), isTrue);
      expect(
        isFileEncrypted(file),
        isTrue,
        reason: 'the database opened without a key on $platform',
      );

      final asText = String.fromCharCodes(file.readAsBytesSync());
      expect(asText.startsWith('SQLite format 3'), isFalse);
      expect(asText, isNot(contains('Sharma Traders')));
    });

    test(
      'losing the key makes the database unreadable, as encryption implies',
      () async {
        final db = await openEncryptedDatabase();
        await db
            .into(db.appMeta)
            .insert(
              AppMetaCompanion.insert(
                key: 'probe',
                value: 'value',
                updatedAt: DateTime.now().toUtc(),
              ),
            );
        await db.close();

        // Simulates a reset keystore or a recreated Windows profile.
        await DatabaseKeyManager().deleteKey();
        final withNewKey = await openEncryptedDatabase();
        await expectLater(
          withNewKey.select(withNewKey.appMeta).get(),
          throwsA(anything),
          reason:
              'a new key must fail loudly, not silently present an empty database that '
              'would look like data loss',
        );
        await withNewKey.close();
      },
    );
  });
}
