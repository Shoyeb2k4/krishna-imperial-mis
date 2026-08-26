/// Generation and platform-secure storage of the local database encryption key.
///
/// The key is a 256-bit CSPRNG value created once per installation. It must never be
/// hard-coded, never written to configuration, never committed, never logged, and never
/// included in diagnostics or crash reports — see docs/DECISIONS.md D-022 and
/// docs/ARCHITECTURE.md §8.1.
///
/// | Platform | Protection |
/// |---|---|
/// | Android  | AES-GCM ciphertext, wrapping key held in the Android Keystore |
/// | Windows  | DPAPI-protected credential store, scoped to the Windows user |
///
/// Residual risk, accepted for V1: DPAPI binds to the Windows *user account*, not to
/// hardware, so malware running as the same user could unwrap the key. Mitigated by
/// requiring a Windows account password, short session lifetimes and no auto sign-in.
library;

import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Raised when the key exists but cannot be retrieved — a reset OS keystore, a
/// recreated Windows profile, app data restored onto a different device.
///
/// This is unrecoverable by design: that is what encryption means. The app tells the
/// user plainly and offers to reset the local store and re-download from the server.
/// Any mutation that had not yet synced is lost, and we say so rather than reassure.
class DatabaseKeyUnavailable implements Exception {
  const DatabaseKeyUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'DatabaseKeyUnavailable: $reason';
}

class DatabaseKeyManager {
  DatabaseKeyManager({FlutterSecureStorage? storage, Random? random})
    : _storage = storage ?? _defaultStorage,
      _random = random ?? Random.secure();

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
  static const int keyLengthBytes = 32; // 256-bit

  final FlutterSecureStorage _storage;
  final Random _random;

  /// Returns the existing key, or creates and stores one on first run.
  ///
  /// The returned value is lowercase hex with no `0x` prefix. It is passed straight to
  /// the SQLite `PRAGMA key` and is never logged, echoed, or returned to the UI.
  Future<String> obtainKey() async {
    final existing = await _read();
    if (existing != null) {
      if (!_isWellFormed(existing)) {
        throw const DatabaseKeyUnavailable(
          'stored key is malformed; the local database cannot be opened',
        );
      }
      return existing;
    }

    final created = _generateHexKey();
    await _write(created);

    // Read back before use. If secure storage silently failed to persist, we must find
    // out now — not on the next launch, when the database would be unopenable.
    final confirmed = await _read();
    if (confirmed != created) {
      throw const DatabaseKeyUnavailable(
        'secure storage did not retain the generated key',
      );
    }
    return created;
  }

  /// Whether a key has already been established on this installation.
  Future<bool> hasKey() async => (await _read()) != null;

  /// Removes the key. Only ever called by the explicit "sign out and erase local data"
  /// action, which refuses while the outbox holds unsynced entries. Deleting the key
  /// makes the local database permanently unreadable.
  Future<void> deleteKey() => _storage.delete(key: storageKey);

  Future<String?> _read() async {
    try {
      return await _storage.read(key: storageKey);
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
      await _storage.write(key: storageKey, value: value);
    } on Exception catch (error) {
      throw DatabaseKeyUnavailable(
        'secure storage write failed (${error.runtimeType})',
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
