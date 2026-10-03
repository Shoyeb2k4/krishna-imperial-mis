/// Generation and platform-secure storage of the local database encryption key.
///
/// The key is a 256-bit CSPRNG value created once per installation. It must never be
/// hard-coded, never written to configuration, never committed, never logged, and never
/// included in diagnostics or crash reports — see docs/DECISIONS.md D-022, D-036 and
/// docs/ARCHITECTURE.md §8.1.
///
/// | Platform | Protection (verified against the running app — D-036) |
/// |---|---|
/// | Android  | AES-GCM ciphertext, wrapping key held in the Android Keystore |
/// | Windows  | **DPAPI** (`CryptProtectData`), user-scoped, no application entropy |
///
/// On Windows the whole key/value store is a single DPAPI blob at
/// `%APPDATA%\<Company>\<Product>\flutter_secure_storage.dat`. The Credential Manager
/// path that also ships inside the package is **not** the code path taken — the Dart FFI
/// implementation is. Confirmed by inspecting the artefact the real Windows build wrote.
///
/// Residual risk, accepted for V1: DPAPI binds to the Windows *user account*, not to
/// hardware, and no additional entropy is supplied, so **any process running as the same
/// Windows user can unwrap the key**. Mitigated by requiring a Windows account password,
/// short session lifetimes, re-authentication after idle and no automatic sign-in.
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Raised when the key exists but cannot be retrieved — a reset OS keystore, a
/// recreated Windows profile, app data restored onto a different device.
///
/// This is unrecoverable by design: that is what encryption means. The app tells the
/// user plainly and offers to reset the local store and re-download from the server.
/// Any mutation that had not yet synced is lost, and we say so rather than reassure.
class DatabaseKeyUnavailable implements Exception {
  const DatabaseKeyUnavailable(
    this.reason, {
    this.problem = DatabaseKeyProblem.storeUnreadable,
  });
  final String reason;

  /// Which of the distinct key failures this is. Start-up reads it to decide whether a
  /// reset can help at all (Phase 8 Slice 7, D-329): a store that cannot be *read* right
  /// now may answer in a moment, and a store that cannot be *written* would refuse the new
  /// key a reset needs, so neither is offered one.
  final DatabaseKeyProblem problem;

  @override
  String toString() => 'DatabaseKeyUnavailable(${problem.name}): $reason';
}

/// Why the local database key could not be obtained.
enum DatabaseKeyProblem {
  /// The platform secure store threw on read. On Android this is ordinary before the
  /// first unlock after a reboot, so it is treated as worth trying again.
  storeUnreadable,

  /// The platform secure store threw on write, or did not keep what it was given.
  storeUnwritable,

  /// A value is stored under the key's name and is not a key.
  malformed,

  /// No key is stored, but a database file exists that only a key could open. Creating a
  /// new key would not open it, so none is created (D-329).
  missingForExistingDatabase,
}

/// Which stored key an installation opens its database with.
///
/// The acceptance suite is given its own data folder so it never opens or replaces a
/// database somebody uses by hand (D-246). The **key** has to be its own too, or a run
/// still creates, reads and can delete the real installation's entry in the shared store.
///
/// The folder decides, rather than a caller passing a string: `main()` passes no folder and
/// so cannot reach the acceptance identifier, and a run given a folder cannot reach the
/// production one. Neither invariant depends on anybody remembering.
///
/// Android is untouched — the harness passes a folder on Windows only, so an Android
/// acceptance run keeps the production identifier and its Keystore-backed store (D-022).
///
/// [production] selects production's own entry (Phase 9 Slice 2, D-346). An acceptance
/// folder still wins, so a test run can never reach production's key either.
String databaseKeyNameFor({
  Directory? appDataDirectory,
  bool production = false,
}) => appDataDirectory != null
    ? DatabaseKeyManager.acceptanceStorageKey
    : production
    ? DatabaseKeyManager.productionStorageKey
    : DatabaseKeyManager.storageKey;

class DatabaseKeyManager {
  DatabaseKeyManager({
    FlutterSecureStorage? storage,
    Random? random,
    String? keyName,
  }) : _storage = storage ?? _defaultStorage,
       _random = random ?? Random.secure(),
       keyName = keyName ?? storageKey;

  /// Android: `encryptedSharedPreferences` is requested explicitly rather than left
  /// to the default, because it is what routes storage through
  /// EncryptedSharedPreferences with its master key held in the Android Keystore.
  /// Windows: the plugin uses DPAPI, scoped to the current Windows user.
  ///
  /// The package is **pinned to 9.2.4**: 11.x requires compileSdk 37, which this
  /// toolchain does not have. See docs/DECISIONS.md D-030.
  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Versioned so a future key-rotation feature can migrate rather than collide.
  static const String storageKey = 'krishna_mis.db_key.v1';

  /// The acceptance suite's own entry, so a run cannot create, read, replace or delete the
  /// key of the installation a person uses by hand. Selected by the data folder, never by a
  /// caller naming it (see [databaseKeyNameFor]).
  static const String acceptanceStorageKey = 'krishna_mis.acceptance.db_key.v1';

  /// Production's own entry, approved by the project lead (Phase 9 Slice 2, D-346). No
  /// development, staging or acceptance build can name it, and a production build cannot
  /// name either of the others — so switching environment can never reuse a key.
  static const String productionStorageKey = 'krishna_mis.db_key.prod.v1';

  static const int keyLengthBytes = 32; // 256-bit

  final FlutterSecureStorage _storage;
  final Random _random;

  /// The entry this manager reads, writes and deletes. Every operation names it, so one
  /// installation's cleanup cannot reach another's key.
  final String keyName;

  /// Returns the existing key, or creates and stores one on first run.
  ///
  /// The returned value is lowercase hex with no `0x` prefix. It is passed straight to
  /// the SQLite `PRAGMA key` and is never logged, echoed, or returned to the UI.
  ///
  /// [databaseExists] says whether a database file is already on disk. When it is and no
  /// key is stored, no key is created: the file was written with a key this installation
  /// no longer holds, a new one cannot open it, and writing one would only turn "the key is
  /// missing" into "the key is wrong" on the next launch (Phase 8 Slice 7, D-329 — before
  /// this, a missing key was replaced silently and then reported as an unreadable file).
  Future<String> obtainKey({bool databaseExists = false}) async {
    final existing = await _read();
    if (existing != null) {
      if (!_isWellFormed(existing)) {
        throw const DatabaseKeyUnavailable(
          'stored key is malformed; the local database cannot be opened',
          problem: DatabaseKeyProblem.malformed,
        );
      }
      return existing;
    }
    if (databaseExists) {
      throw const DatabaseKeyUnavailable(
        'no key is stored for the existing local database',
        problem: DatabaseKeyProblem.missingForExistingDatabase,
      );
    }

    final created = _generateHexKey();
    await _write(created);

    // Read back before use. If secure storage silently failed to persist, we must find
    // out now — not on the next launch, when the database would be unopenable.
    final confirmed = await _read();
    if (confirmed != created) {
      throw const DatabaseKeyUnavailable(
        'secure storage did not retain the generated key',
        problem: DatabaseKeyProblem.storeUnwritable,
      );
    }
    return created;
  }

  /// Whether a key has already been established on this installation.
  Future<bool> hasKey() async => (await _read()) != null;

  /// The stored value, unchecked, or null. Only the recovery service reads it, to set a
  /// key aside beside the database it belongs to (D-329); it is never logged or shown.
  Future<String?> readStoredKey() => _read();

  /// Copies [value] to [entryName] and reads it back. Used only to set a key aside under
  /// a name no ordinary start-up reads (D-329). Throws [DatabaseKeyUnavailable] when the
  /// store does not keep it, so a reset never proceeds believing a key was kept.
  Future<void> storeAside(String entryName, String value) async {
    if (entryName == keyName) {
      throw ArgumentError('a key cannot be set aside under its own name');
    }
    try {
      await _storage.write(key: entryName, value: value);
      final kept = await _storage.read(key: entryName);
      if (kept != value) {
        throw const DatabaseKeyUnavailable(
          'secure storage did not retain the key set aside',
          problem: DatabaseKeyProblem.storeUnwritable,
        );
      }
    } on DatabaseKeyUnavailable {
      rethrow;
    } on Exception catch (error) {
      throw DatabaseKeyUnavailable(
        'secure storage write failed (${error.runtimeType})',
        problem: DatabaseKeyProblem.storeUnwritable,
      );
    }
  }

  /// Removes the key. Only ever called by the explicit "sign out and erase local data"
  /// action, which refuses while the outbox holds unsynced entries. Deleting the key
  /// makes the local database permanently unreadable.
  Future<void> deleteKey() => _storage.delete(key: keyName);

  Future<String?> _read() async {
    try {
      return await _storage.read(key: keyName);
    } on Exception catch (error) {
      // Deliberately does not include the exception's payload: platform channel errors
      // from secure storage have been known to echo stored material.
      throw DatabaseKeyUnavailable(
        'secure storage read failed (${error.runtimeType})',
      );
    }
  }

  Future<void> _write(String value) async {
    try {
      await _storage.write(key: keyName, value: value);
    } on Exception catch (error) {
      throw DatabaseKeyUnavailable(
        'secure storage write failed (${error.runtimeType})',
        problem: DatabaseKeyProblem.storeUnwritable,
      );
    }
  }

  String _generateHexKey() {
    final buffer = StringBuffer();
    for (var i = 0; i < keyLengthBytes; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static bool _isWellFormed(String key) {
    if (key.length != keyLengthBytes * 2) return false;
    for (final unit in key.codeUnits) {
      final isDigit = unit >= 0x30 && unit <= 0x39;
      final isLowerHex = unit >= 0x61 && unit <= 0x66;
      if (!isDigit && !isLowerHex) return false;
    }
    return true;
  }
}
