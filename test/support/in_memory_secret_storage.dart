/// An in-memory stand-in for platform secure storage.
///
/// Host tests cannot reach the Android Keystore or Windows DPAPI — those are proven by
/// the on-device suite in `integration_test/`. This fake lets the *logic* around the key
/// (generation, read-back verification, erasure, loss) be tested exhaustively on the host.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class InMemorySecretStorage extends FlutterSecureStorage {
  InMemorySecretStorage({Map<String, String>? initial})
    : _values = {...?initial};

  final Map<String, String> _values;

  /// Set to true to simulate a secure store that accepts a write and loses it — the
  /// failure `DatabaseKeyManager` guards against by reading the key back before use.
  bool swallowWrites = false;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (swallowWrites) return;
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _values.containsKey(key);

  // Overridden so that no call on this fake can fall through to the platform's real
  // secure store. Without these, `readAll` and `deleteAll` reached the plugin (found by
  // the Phase 8 Slice 8 recovery acceptance).
  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(_values);

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (!swallowWrites) _values.clear();
  }
}
