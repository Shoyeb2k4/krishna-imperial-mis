/// An acceptance run must not share the local database key with the installation a person
/// uses by hand.
///
/// Phase 5 Slice 12, on the project lead's ruling. D-246 gave the acceptance suite its own
/// data folder, so it opens its own database file and its own session file. The **key** was
/// not isolated: `DatabaseKeyManager` read and wrote one entry, `krishna_mis.db_key.v1`, in
/// the shared secure-storage plugin, so an acceptance run still created, read and could
/// delete the real installation's key.
///
/// The identifier is now selected by the acceptance boundary that already exists — the data
/// folder — rather than by a caller remembering to pass the right string. Neither side can
/// name the other's entry: `main()` passes no folder and therefore cannot reach the
/// acceptance identifier, and a run given a folder cannot reach the production one.
///
/// Android is untouched: the harness passes a folder on Windows only (D-246), so an Android
/// acceptance run keeps the production identifier and the Keystore-backed store (D-022).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';

import '../support/delete_on_failure_secret_storage.dart';

void main() {
  late Directory acceptanceFolder;

  setUp(() async {
    acceptanceFolder = await Directory.systemTemp.createTemp('krishna_accept_');
  });

  tearDown(() async {
    if (await acceptanceFolder.exists()) {
      await acceptanceFolder.delete(recursive: true);
    }
  });

  group('which identifier each side selects', () {
    test('the production identifier is unchanged', () {
      expect(DatabaseKeyManager.storageKey, 'krishna_mis.db_key.v1');
      expect(DatabaseKeyManager().keyName, DatabaseKeyManager.storageKey);
    });

    test(
      'no data folder — the ordinary app — selects the production identifier',
      () {
        expect(databaseKeyNameFor(), DatabaseKeyManager.storageKey);
        expect(
          databaseKeyNameFor(appDataDirectory: null),
          DatabaseKeyManager.storageKey,
        );
      },
    );

    test('an acceptance data folder selects the acceptance identifier', () {
      expect(
        databaseKeyNameFor(appDataDirectory: acceptanceFolder),
        DatabaseKeyManager.acceptanceStorageKey,
      );
      expect(
        DatabaseKeyManager.acceptanceStorageKey,
        'krishna_mis.acceptance.db_key.v1',
      );
    });

    test('an acceptance run can never land on the production identifier', () {
      expect(
        databaseKeyNameFor(appDataDirectory: acceptanceFolder),
        isNot(DatabaseKeyManager.storageKey),
      );
    });
  });

  group('the two entries are independent', () {
    late DeleteOnFailureSecretStorage store;
    late DatabaseKeyManager production;
    late DatabaseKeyManager acceptance;

    setUp(() {
      store = DeleteOnFailureSecretStorage();
      production = DatabaseKeyManager(storage: store);
      acceptance = DatabaseKeyManager(
        storage: store,
        keyName: DatabaseKeyManager.acceptanceStorageKey,
      );
    });

    test(
      'an acceptance run creates its own key and leaves the real one alone',
      () async {
        final real = await production.obtainKey();
        final theirs = await acceptance.obtainKey();

        expect(theirs, isNot(real), reason: 'two installations, two keys');
        expect(store.values[DatabaseKeyManager.storageKey], real);
        expect(store.values[DatabaseKeyManager.acceptanceStorageKey], theirs);
      },
    );

    test('acceptance cleanup cannot delete the normal key', () async {
      final real = await production.obtainKey();
      await acceptance.obtainKey();

      await acceptance.deleteKey();

      expect(await production.hasKey(), isTrue);
      expect(
        await production.obtainKey(),
        real,
        reason: 'unchanged, not re-created',
      );
      expect(await acceptance.hasKey(), isFalse);
    });

    test('erasing the normal key leaves the acceptance key readable', () async {
      final real = await production.obtainKey();
      final theirs = await acceptance.obtainKey();

      await production.deleteKey();

      expect(await production.hasKey(), isFalse);
      expect(await acceptance.obtainKey(), theirs);
      expect(theirs, isNot(real));
    });

    test(
      'an acceptance restart reopens its own database with its own key',
      () async {
        final first = await acceptance.obtainKey();
        final afterRestart = await DatabaseKeyManager(
          storage: store,
          keyName: DatabaseKeyManager.acceptanceStorageKey,
        ).obtainKey();

        expect(afterRestart, first);
      },
    );
  });

  group('neither side can name the other', () {
    test('main() passes no data folder and names no key identifier', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('appDataDirectory'), isFalse);
      expect(main.contains('acceptance'), isFalse);
      expect(main.contains('db_key'), isFalse);
    });

    test('bootstrap derives the identifier from the acceptance folder', () {
      final source = File('lib/app/bootstrap.dart').readAsStringSync();
      expect(
        source.contains('databaseKeyNameFor'),
        isTrue,
        reason:
            'the boundary selects the identifier; no caller passes a string',
      );
      expect(
        source.contains("'krishna_mis."),
        isFalse,
        reason: 'no identifier literal lives at the call site',
      );
    });
  });
}
