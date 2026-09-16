/// A stand-in for `flutter_secure_storage_windows` 3.1.2 (the locked version), faithful to
/// the one behaviour that matters here.
///
/// The Windows plugin keeps every key in one DPAPI blob. When a read cannot decrypt that
/// blob, `DpapiJsonFileMapStorage.load` deletes the whole file and rethrows (plugin source,
/// `load`: "Failed to decrypt data … Delete corrupt file"). Every other key in the store —
/// including the local database key — goes with it. Slice 11 run 3 hit exactly this.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeleteOnFailureSecretStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  /// When set, the next read behaves like a blob that no longer decrypts: the whole store
  /// is removed and the read throws.
  bool corruptNextRead = false;

  Future<String?> _read(String key) async {
    if (corruptNextRead) {
      corruptNextRead = false;
      values.clear();
      throw Exception('Failure on CryptUnprotectData()');
    }
    return values[key];
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _read(key);

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
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
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
  }) async => values.remove(key);
}
