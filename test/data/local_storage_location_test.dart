/// Production's local data is kept apart from every other build's, and can never reach the
/// D-247 installation (Phase 9 Slice 2, D-346).
///
/// The approved values: production on Windows lives in
/// `%APPDATA%\Krishna Imperial\Krishna Imperial MIS Production` and opens its database
/// with `krishna_mis.db_key.prod.v1`. The legacy folder
/// `%APPDATA%\Krishna Imperial\Krishna Imperial MIS` is every non-production build's, and
/// on the project lead's workstation it holds the D-247 database, which nothing here opens.
///
/// Every test is a pure computation or uses a temporary folder: none reads, writes or
/// creates anything in the real application-data folders.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/local_storage_location.dart';
import 'package:krishna_mis/data/local/protected_file_secret_storage.dart';
import 'package:krishna_mis/data/local/session_secret_store.dart';
import 'package:krishna_mis/data/remote/auth_gateway.dart';
import 'package:path/path.dart' as p;

/// Reverses the bytes: protected output is never the plain text, and it round-trips.
final class _ReversingProtector implements DataProtector {
  bool refuse = false;

  @override
  Uint8List protect(Uint8List plain) =>
      Uint8List.fromList(plain.reversed.toList());

  @override
  Uint8List? unprotect(Uint8List protected) =>
      refuse ? null : Uint8List.fromList(protected.reversed.toList());
}

const _roaming = r'C:\Users\someone\AppData\Roaming';

Future<LocalStorageLocation> _production({
  String os = 'windows',
  required Directory platformSupport,
  DataProtector? protector,
  String roaming = _roaming,
}) => resolveLocalStorage(
  production: true,
  operatingSystem: os,
  roamingAppData: () async => roaming,
  platformSupportDirectory: () async => platformSupport,
  protector: protector ?? _ReversingProtector(),
);

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('krishna_storage_identity_');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('the approved production identity', () {
    test('the Windows production folder is the approved one', () {
      expect(
        windowsProductionDataPath(_roaming),
        p.join(_roaming, 'Krishna Imperial', 'Krishna Imperial MIS Production'),
      );
      expect(WindowsDataFolders.production, 'Krishna Imperial MIS Production');
    });

    test('the production key name is the approved one', () {
      expect(
        DatabaseKeyManager.productionStorageKey,
        'krishna_mis.db_key.prod.v1',
      );
    });
  });

  group('D-247 structural guards', () {
    test('1 · the production folder is not the legacy folder', () {
      expect(
        p.equals(
          windowsProductionDataPath(_roaming),
          windowsLegacyDataPath(_roaming),
        ),
        isFalse,
      );
      expect(WindowsDataFolders.production, isNot(WindowsDataFolders.legacy));
    });

    test('2 · the production key is not the legacy key', () {
      expect(
        DatabaseKeyManager.productionStorageKey,
        isNot(DatabaseKeyManager.storageKey),
      );
    });

    test(
      '3 · the production folder is not the acceptance or dev folder',
      () async {
        final prod = await _production(platformSupport: temp);
        final dev = await resolveLocalStorage(production: false);
        final acceptance = await resolveLocalStorage(
          production: false,
          acceptanceDirectory: temp,
        );
        expect(prod.directory!.path, isNot(temp.path));
        expect(dev.directory, isNull, reason: 'dev keeps the platform default');
        expect(acceptance.directory!.path, temp.path);
        expect(
          prod.directory!.path.contains(WindowsDataFolders.production),
          isTrue,
        );
      },
    );

    test('4 · no two environments share a key name', () {
      final names = {
        databaseKeyNameFor(production: true),
        databaseKeyNameFor(),
        databaseKeyNameFor(appDataDirectory: Directory('x')),
      };
      expect(names, hasLength(3));
      expect(names, contains('krishna_mis.db_key.prod.v1'));
      expect(names, contains('krishna_mis.db_key.v1'));
      expect(names, contains('krishna_mis.acceptance.db_key.v1'));
    });

    test('5 · the production resolver cannot return the legacy path', () async {
      for (final roaming in [
        _roaming,
        r'D:\Profiles\x\AppData\Roaming',
        '/tmp/roaming',
      ]) {
        final location = await _production(
          platformSupport: temp,
          roaming: roaming,
        );
        expect(
          p.equals(location.directory!.path, windowsLegacyDataPath(roaming)),
          isFalse,
        );
        expect(
          p.basename(location.directory!.path),
          WindowsDataFolders.production,
        );
      }
    });

    test(
      '5b · on Windows production never asks for the platform folder',
      () async {
        var asked = false;
        await resolveLocalStorage(
          production: true,
          operatingSystem: 'windows',
          roamingAppData: () async => _roaming,
          platformSupportDirectory: () async {
            asked = true;
            return temp;
          },
        );
        expect(
          asked,
          isFalse,
          reason:
              'the platform folder on Windows is the legacy folder (Runner.rc)',
        );
      },
    );

    test(
      '6 · an acceptance folder stays isolated, even in a production build',
      () async {
        final location = await resolveLocalStorage(
          production: true,
          acceptanceDirectory: temp,
          operatingSystem: 'windows',
          roamingAppData: () async => _roaming,
        );
        expect(location.environment, StorageEnvironment.acceptance);
        expect(location.directory!.path, temp.path);
        expect(location.keyName, DatabaseKeyManager.acceptanceStorageKey);
      },
    );

    test(
      '7 · switching environment cannot reuse another environment\'s key',
      () async {
        final prod = await _production(platformSupport: temp);
        final dev = await resolveLocalStorage(production: false);
        expect(prod.keyName, DatabaseKeyManager.productionStorageKey);
        expect(dev.keyName, DatabaseKeyManager.storageKey);
        expect(prod.keyStorage, isA<ProtectedFileSecretStorage>());
        expect(
          dev.keyStorage,
          isNull,
          reason: 'non-production keeps its existing store, unchanged',
        );
      },
    );

    test('8 · production takes nothing from the legacy store', () {
      // With a folder given, the session is never moved out of the shared plugin store —
      // the one-time D-246 move is a non-production-only act.
      final storage = SecureSessionStorage.forPlatform(
        operatingSystem: 'windows',
        directory: temp,
      );
      expect(storage.migratesLegacySession, isFalse);
      final legacy = SecureSessionStorage.forPlatform(
        operatingSystem: 'windows',
      );
      expect(legacy.migratesLegacySession, isTrue);
    });

    test('8b · the storage module copies and renames nothing', () {
      final source = File(
        'lib/data/local/local_storage_location.dart',
      ).readAsStringSync();
      for (final forbidden in [
        '.copy(',
        '.rename(',
        'copySync',
        'renameSync',
      ]) {
        expect(source.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  group('the Windows production key file', () {
    test(
      'a key is created, kept and read back inside the production folder',
      () async {
        final prodFolder = Directory(p.join(temp.path, 'prod'));
        final storage = ProtectedFileSecretStorage(
          directory: prodFolder,
          protector: _ReversingProtector(),
        );
        final keys = DatabaseKeyManager(
          storage: storage,
          keyName: DatabaseKeyManager.productionStorageKey,
        );
        final key = await keys.obtainKey();
        expect(await keys.obtainKey(), key);
        final files = prodFolder.listSync().map((f) => p.basename(f.path));
        expect(files, ['krishna_mis.db_key.prod.v1.dpapi']);
        final raw = await File(
          p.join(prodFolder.path, 'krishna_mis.db_key.prod.v1.dpapi'),
        ).readAsString();
        expect(raw.contains(key), isFalse, reason: 'stored protected');
      },
    );

    test(
      'a file that will not unprotect is unreadable, never "no key"',
      () async {
        final protector = _ReversingProtector();
        final storage = ProtectedFileSecretStorage(
          directory: temp,
          protector: protector,
        );
        final keys = DatabaseKeyManager(
          storage: storage,
          keyName: DatabaseKeyManager.productionStorageKey,
        );
        await keys.obtainKey();
        protector.refuse = true;
        await expectLater(
          keys.obtainKey(databaseExists: true),
          throwsA(
            isA<DatabaseKeyUnavailable>().having(
              (e) => e.problem,
              'problem',
              DatabaseKeyProblem.storeUnreadable,
            ),
          ),
        );
        expect(
          storage.fileFor(DatabaseKeyManager.productionStorageKey).existsSync(),
          isTrue,
          reason: 'a failed read deletes nothing (D-246)',
        );
      },
    );

    test('an entry name cannot leave the folder', () {
      final storage = ProtectedFileSecretStorage(directory: temp);
      for (final bad in ['', r'..\x', '../x', r'C:\x', 'a/b']) {
        expect(() => storage.fileFor(bad), throwsArgumentError, reason: bad);
      }
    });

    test('a key set aside and the key delete stay inside the folder', () async {
      final storage = ProtectedFileSecretStorage(
        directory: temp,
        protector: _ReversingProtector(),
      );
      final keys = DatabaseKeyManager(
        storage: storage,
        keyName: DatabaseKeyManager.productionStorageKey,
      );
      final key = await keys.obtainKey();
      await keys.storeAside('krishna_mis.db_key.prod.v1.quarantine.x', key);
      await keys.deleteKey();
      expect(await keys.hasKey(), isFalse);
      expect(temp.listSync().map((f) => p.basename(f.path)), [
        'krishna_mis.db_key.prod.v1.quarantine.x.dpapi',
      ]);
    });

    test(
      'the real DPAPI round trip, on Windows',
      () async {
        final storage = ProtectedFileSecretStorage(directory: temp);
        await storage.write(key: 'probe', value: 'value-under-dpapi');
        expect(await storage.read(key: 'probe'), 'value-under-dpapi');
        final raw = await storage.fileFor('probe').readAsBytes();
        expect(
          String.fromCharCodes(raw).contains('value-under-dpapi'),
          isFalse,
        );
      },
      skip: Platform.isWindows ? false : 'DPAPI exists on Windows only',
    );
  });

  group('the real Windows location, computed without touching it', () {
    test(
      'production resolves under the real roaming folder, beside the legacy one',
      () async {
        final roaming = await windowsRoamingAppData();
        final location = await resolveLocalStorage(
          production: true,
          operatingSystem: 'windows',
        );
        expect(
          location.directory!.path,
          p.join(
            roaming,
            'Krishna Imperial',
            'Krishna Imperial MIS Production',
          ),
        );
        expect(
          p.equals(location.directory!.path, windowsLegacyDataPath(roaming)),
          isFalse,
        );
        // Resolving creates nothing: the folder appears only when production writes.
        expect(
          location.keyStorage,
          isA<ProtectedFileSecretStorage>().having(
            (s) => s.directory.path,
            'directory',
            location.directory!.path,
          ),
        );
      },
      skip: Platform.isWindows ? false : 'the roaming folder is Windows only',
    );
  });

  group('Android production', () {
    test(
      'uses its own private folder and its own key in the Keystore store',
      () async {
        final location = await _production(
          os: 'android',
          platformSupport: temp,
        );
        expect(location.environment, StorageEnvironment.production);
        expect(location.directory!.path, temp.path);
        expect(location.keyName, DatabaseKeyManager.productionStorageKey);
        expect(location.keyStorage, isNull, reason: 'Keystore-backed plugin');
      },
    );
  });

  test('staged bills live inside the resolved location', () async {
    final location = await resolveLocalStorage(
      production: false,
      acceptanceDirectory: temp,
    );
    final staging = await location.attachmentStagingDirectory();
    expect(p.isWithin(temp.path, staging.path), isTrue);
  });
}
