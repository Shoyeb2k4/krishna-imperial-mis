/// A failed read of the persisted session must never cost the local database key.
///
/// Phase 5 Slice 11 (D-246). On Windows, `flutter_secure_storage_windows` 3.1.2 keeps every
/// key in one DPAPI blob and deletes the whole blob when a read fails to decrypt. The
/// session, rewritten on every sign-in and refresh, shared that blob with the database key,
/// which is written once per installation. In Slice 11 run 3 a session read failed, the
/// blob was deleted, and the Windows acceptance database became permanently unreadable
/// (D-022). On Windows the session now lives in its own protected file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/session_secret_store.dart';
import 'package:krishna_mis/data/remote/auth_gateway.dart';
import 'package:path/path.dart' as p;

import '../support/delete_on_failure_secret_storage.dart';

const _session = '{"access_token":"a","refresh_token":"r"}';

/// Reversible and obviously not plaintext; can be told to fail the next unprotect.
class _FakeProtector implements DataProtector {
  bool failNextUnprotect = false;

  @override
  Uint8List protect(Uint8List plain) =>
      Uint8List.fromList([0x7f, for (final b in plain) b ^ 0x5a]);

  @override
  Uint8List? unprotect(Uint8List protected) {
    if (failNextUnprotect) {
      failNextUnprotect = false;
      return null;
    }
    if (protected.isEmpty || protected.first != 0x7f) return null;
    return Uint8List.fromList([for (final b in protected.skip(1)) b ^ 0x5a]);
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('krishna_session_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  File sessionFile() =>
      File(p.join(dir.path, ProtectedFileSessionStore.defaultFileName));

  group('where the session lives', () {
    test('Windows resolves its own protected file', () {
      expect(
        sessionSecretStoreFor('windows', directory: dir),
        isA<ProtectedFileSessionStore>(),
      );
    });

    test('Android keeps the Keystore-backed plugin store', () {
      expect(sessionSecretStoreFor('android'), isA<PluginSessionSecretStore>());
    });
  });

  group('the Windows composition keeps the session apart from the key', () {
    test(
      'a session read that fails to decrypt leaves the database key where it was',
      () async {
        final plugin = DeleteOnFailureSecretStorage();
        final protector = _FakeProtector();
        final keys = DatabaseKeyManager(storage: plugin);
        final key = await keys.obtainKey();

        final sessions = SecureSessionStorage.forPlatform(
          operatingSystem: 'windows',
          directory: dir,
          pluginStorage: plugin,
          protector: protector,
        );
        await sessions.persistSession(_session);

        // Both stores fail their next read. Only the one the session uses may be asked.
        plugin.corruptNextRead = true;
        protector.failNextUnprotect = true;

        expect(await sessions.accessToken(), isNull);
        expect(
          await sessionFile().exists(),
          isTrue,
          reason: 'an unreadable session is no session, and is never deleted',
        );
        expect(
          plugin.corruptNextRead,
          isTrue,
          reason: 'the key store was not read',
        );
        plugin.corruptNextRead = false;
        expect(
          await keys.obtainKey(),
          key,
          reason:
              'if the session shared the key store, the failed read would have deleted '
              'the key and with it the local database',
        );
        expect(
          plugin.values.containsKey(PluginSessionSecretStore.sessionStorageKey),
          isFalse,
          reason: 'the session is not written to the key store',
        );
      },
    );

    test('the next sign-in replaces an unreadable session', () async {
      final protector = _FakeProtector();
      final sessions = SecureSessionStorage.forPlatform(
        operatingSystem: 'windows',
        directory: dir,
        pluginStorage: DeleteOnFailureSecretStorage(),
        protector: protector,
      );
      await sessions.persistSession('{"old":1}');
      protector.failNextUnprotect = true;
      expect(await sessions.accessToken(), isNull);

      await sessions.persistSession(_session);
      expect(await sessions.accessToken(), _session);
      expect(
        await File('${sessionFile().path}.tmp').exists(),
        isFalse,
        reason: 'the write went through a temporary file and renamed it',
      );
    });

    test('sign-out removes the session and nothing else', () async {
      final plugin = DeleteOnFailureSecretStorage();
      final key = await DatabaseKeyManager(storage: plugin).obtainKey();
      final sessions = SecureSessionStorage.forPlatform(
        operatingSystem: 'windows',
        directory: dir,
        pluginStorage: plugin,
        protector: _FakeProtector(),
      );
      await sessions.persistSession(_session);
      await sessions.removePersistedSession();

      expect(await sessions.hasAccessToken(), isFalse);
      expect(await sessionFile().exists(), isFalse);
      expect(await DatabaseKeyManager(storage: plugin).obtainKey(), key);
    });

    test(
      'an acceptance data folder never takes a session out of the shared store',
      () async {
        final plugin = DeleteOnFailureSecretStorage();
        await plugin.write(
          key: PluginSessionSecretStore.sessionStorageKey,
          value: _session,
        );
        final sessions = SecureSessionStorage.forPlatform(
          operatingSystem: 'windows',
          directory: dir,
          pluginStorage: plugin,
          protector: _FakeProtector(),
        );

        expect(await sessions.accessToken(), isNull);
        expect(
          plugin.values[PluginSessionSecretStore.sessionStorageKey],
          _session,
        );
      },
    );
  });

  group('a session left in the shared store by an earlier build', () {
    SecureSessionStorage withLegacy(
      DeleteOnFailureSecretStorage plugin,
      _FakeProtector protector,
    ) => SecureSessionStorage(
      store: ProtectedFileSessionStore(
        directory: () async => dir,
        protector: protector,
      ),
      legacy: PluginSessionSecretStore(plugin),
    );

    test('is moved once, and the key stays', () async {
      final plugin = DeleteOnFailureSecretStorage();
      final key = await DatabaseKeyManager(storage: plugin).obtainKey();
      await plugin.write(
        key: PluginSessionSecretStore.sessionStorageKey,
        value: _session,
      );
      final protector = _FakeProtector();

      expect(await withLegacy(plugin, protector).accessToken(), _session);
      expect(
        plugin.values.containsKey(PluginSessionSecretStore.sessionStorageKey),
        isFalse,
      );
      expect(await sessionFile().exists(), isTrue);
      expect(await DatabaseKeyManager(storage: plugin).obtainKey(), key);
      expect(await withLegacy(plugin, protector).accessToken(), _session);
    });

    test(
      'is not asked for once the new store exists, even when that store is unreadable',
      () async {
        final plugin = DeleteOnFailureSecretStorage();
        final key = await DatabaseKeyManager(storage: plugin).obtainKey();
        final protector = _FakeProtector();
        final sessions = withLegacy(plugin, protector);
        await sessions.persistSession(_session);

        plugin.corruptNextRead = true;
        protector.failNextUnprotect = true;
        expect(await sessions.accessToken(), isNull);
        expect(plugin.corruptNextRead, isTrue);
        plugin.corruptNextRead = false;
        expect(await DatabaseKeyManager(storage: plugin).obtainKey(), key);
      },
    );

    test('a failing shared store is no session, not an error', () async {
      final plugin = DeleteOnFailureSecretStorage()..corruptNextRead = true;
      expect(await withLegacy(plugin, _FakeProtector()).accessToken(), isNull);
      expect(await sessionFile().exists(), isFalse);
    });
  });

  group('real DPAPI on this Windows host', () {
    test(
      'round trip, not plaintext on disk, and a damaged file is kept',
      () async {
        final store = ProtectedFileSessionStore(
          directory: () async => dir,
          protector: const DpapiDataProtector(),
        );
        await store.write(_session);

        final bytes = await sessionFile().readAsBytes();
        expect(String.fromCharCodes(bytes), isNot(contains('refresh_token')));
        expect(await store.read(), _session);

        await sessionFile().writeAsBytes([...bytes.take(20), 1, 2, 3]);
        expect(await store.read(), isNull);
        expect(await sessionFile().exists(), isTrue);

        await store.delete();
        expect(await sessionFile().exists(), isFalse);
      },
      skip: Platform.isWindows ? false : 'DPAPI exists only on Windows',
    );
  });
}
