/// Where the persisted sign-in session lives, kept apart from the database key on Windows.
///
/// `flutter_secure_storage_windows` 3.1.2 keeps every key in one DPAPI blob. It rewrites the
/// whole blob on every change, does not serialise readers against writers, and deletes the
/// whole blob when a read cannot decrypt it. The session is rewritten on every sign-in and
/// token refresh; the local database key is written once per installation. Sharing the blob
/// let a failed session read destroy the database key, and with it the local database
/// (Slice 11, D-246; D-022).
///
/// On Windows the session therefore lives in its own DPAPI-protected file:
///
/// * protected exactly as the plugin protects its blob — DPAPI, current user, no entropy
///   (D-036), so this is no weaker and no stronger than before;
/// * written to a temporary file and renamed over the old one, so an interrupted write
///   leaves the previous session rather than a truncated one;
/// * serialised within the process, so a read never meets a half-written file;
/// * **never deleted because a read failed**: an unreadable session is no session, the
///   person signs in again, and the next write replaces it.
///
/// Android keeps the Keystore-backed plugin store (D-022), where none of this applies.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

/// One secret string, read, written and removed.
abstract interface class SessionSecretStore {
  /// The stored value, or null when there is none or it cannot be read.
  Future<String?> read();

  /// Whether anything has ever been written here and not removed — true even when the
  /// value can no longer be read. Used to decide whether an older store is worth asking.
  Future<bool> exists();

  Future<void> write(String value);

  Future<void> delete();
}

/// The platform plugin store under one key: Android's Keystore-backed store, and the
/// location Windows used before D-246.
final class PluginSessionSecretStore implements SessionSecretStore {
  PluginSessionSecretStore(this._storage, {this.key = sessionStorageKey});

  static const String sessionStorageKey = 'krishna_mis.session.v1';

  /// The same options the database key manager uses (D-031).
  static const FlutterSecureStorage platformDefault = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final FlutterSecureStorage _storage;
  final String key;

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<bool> exists() async => (await read()) != null;

  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: key);
}

/// Protects bytes for the current user.
abstract interface class DataProtector {
  Uint8List protect(Uint8List plain);

  /// Null when the bytes cannot be unprotected.
  Uint8List? unprotect(Uint8List protected);
}

/// Windows DPAPI, current-user scope, no optional entropy — the protection the plugin
/// applies to its own blob (D-036).
final class DpapiDataProtector implements DataProtector {
  const DpapiDataProtector();

  @override
  Uint8List protect(Uint8List plain) {
    final protected = _transform(plain, protect: true);
    if (protected == null) {
      throw const FileSystemException('the session could not be protected');
    }
    return protected;
  }

  @override
  Uint8List? unprotect(Uint8List protected) =>
      _transform(protected, protect: false);

  static Uint8List? _transform(Uint8List input, {required bool protect}) =>
      using((arena) {
        final buffer = arena.allocate<Uint8>(input.isEmpty ? 1 : input.length);
        buffer.asTypedList(input.length).setAll(0, input);
        final source = arena.allocate<CRYPT_INTEGER_BLOB>(
          sizeOf<CRYPT_INTEGER_BLOB>(),
        );
        source.ref.cbData = input.length;
        source.ref.pbData = buffer;
        final result = arena.allocate<CRYPT_INTEGER_BLOB>(
          sizeOf<CRYPT_INTEGER_BLOB>(),
        );
        result.ref.cbData = 0;
        result.ref.pbData = nullptr;

        final ok = protect
            ? CryptProtectData(
                source,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                0,
                result,
              )
            : CryptUnprotectData(
                source,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                0,
                result,
              );
        if (ok == 0 || result.ref.pbData.address == 0) return null;
        try {
          return Uint8List.fromList(
            result.ref.pbData.asTypedList(result.ref.cbData),
          );
        } finally {
          LocalFree(result.ref.pbData.cast());
        }
      });
}

/// A secret in its own protected file, replaced atomically and never deleted on a failed
/// read.
final class ProtectedFileSessionStore implements SessionSecretStore {
  ProtectedFileSessionStore({
    required this._directory,
    required this._protector,
    this.fileName = defaultFileName,
  });

  static const String defaultFileName = 'krishna_mis.session.dpapi';

  final Future<Directory> Function() _directory;
  final DataProtector _protector;
  final String fileName;

  Future<void> _last = Future<void>.value();

  /// Runs [action] after every earlier call on this store has finished, failed or not.
  Future<T> _serially<T>(Future<T> Function() action) {
    final next = _last.then((_) => action());
    _last = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<File> _file() async =>
      File(p.join((await _directory()).path, fileName));

  File _temporary(File file) => File('${file.path}.tmp');

  @override
  Future<String?> read() => _serially(() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
    final plain = _protector.unprotect(bytes);
    if (plain == null) return null;
    try {
      return utf8.decode(plain);
    } on FormatException {
      return null;
    }
  });

  @override
  Future<bool> exists() => _serially(() async => (await _file()).exists());

  @override
  Future<void> write(String value) => _serially(() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = _temporary(file);
    await temporary.writeAsBytes(
      _protector.protect(Uint8List.fromList(utf8.encode(value))),
      flush: true,
    );
    await temporary.rename(file.path);
  });

  @override
  Future<void> delete() => _serially(() async {
    final file = await _file();
    for (final candidate in [file, _temporary(file)]) {
      if (await candidate.exists()) await candidate.delete();
    }
  });
}

/// Where the session lives on [operatingSystem] (D-246).
///
/// A plain function of the platform name, like `attachmentSourceFor`, so a host test can
/// assert both production branches without either device (D-077).
SessionSecretStore sessionSecretStoreFor(
  String operatingSystem, {
  Directory? directory,
  DataProtector protector = const DpapiDataProtector(),
  FlutterSecureStorage pluginStorage = PluginSessionSecretStore.platformDefault,
}) => operatingSystem == 'windows'
    ? ProtectedFileSessionStore(
        directory: () async =>
            directory ?? await getApplicationSupportDirectory(),
        protector: protector,
      )
    : PluginSessionSecretStore(pluginStorage);
