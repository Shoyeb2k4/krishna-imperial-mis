/// The production database key on Windows, in its own DPAPI-protected file in
/// production's own folder (Phase 9 Slice 2, D-346).
///
/// `flutter_secure_storage_windows` 3.1.2 writes every entry into one blob at
/// `getApplicationSupportDirectory()\flutter_secure_storage.dat`. On Windows that folder is
/// named by the executable's version resource — `%APPDATA%\Krishna Imperial\Krishna
/// Imperial MIS` — for every build, which is the legacy development folder and, on the
/// project lead's workstation, the D-247 installation. A production key kept in the plugin
/// would therefore be written into exactly the folder production must never touch.
///
/// So production on Windows keeps its key here instead, protected exactly as the plugin
/// protects its blob — DPAPI, current user, no entropy (D-036) — and with D-246's file
/// discipline: one file per entry, written to a temporary file and renamed over the old
/// one, serialised within the process, and **never deleted because a read failed**. Unlike
/// the session store, a file that exists and will not unprotect is reported as an
/// unreadable store rather than as no key, so a damaged key file is never mistaken for a
/// first run (D-329).
///
/// Android keeps the Keystore-backed plugin store, which is private to the production
/// application id.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:krishna_mis/data/local/session_secret_store.dart';
import 'package:path/path.dart' as p;

class ProtectedFileSecretStorage extends FlutterSecureStorage {
  ProtectedFileSecretStorage({
    required this.directory,
    this._protector = const DpapiDataProtector(),
  });

  /// The folder the entries live in. Production's own, never the legacy folder.
  final Directory directory;
  final DataProtector _protector;

  static const String fileSuffix = '.dpapi';

  Future<void> _last = Future<void>.value();

  Future<T> _serially<T>(Future<T> Function() action) {
    final next = _last.then((_) => action());
    _last = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// The file holding [key]. Entry names are this application's own constants; anything
  /// that could leave the folder is refused.
  File fileFor(String key) {
    if (key.isEmpty || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'not a storable entry name');
    }
    return File(p.join(directory.path, '$key$fileSuffix'));
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
  }) => _serially(() async {
    final file = fileFor(key);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final plain = _protector.unprotect(bytes);
    if (plain == null) {
      throw const FileSystemException(
        'a stored entry could not be unprotected',
      );
    }
    return utf8.decode(plain);
  });

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
  }) => _serially(() async {
    final file = fileFor(key);
    if (value == null) {
      await _deleteFile(file);
      return;
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(
      _protector.protect(Uint8List.fromList(utf8.encode(value))),
      flush: true,
    );
    await temporary.rename(file.path);
  });

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _serially(() => _deleteFile(fileFor(key)));

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _serially(() => fileFor(key).exists());

  // Overridden so no call can fall through to the plugin, which would write into the
  // legacy folder. Neither is used by the key manager.
  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => throw UnsupportedError('production key storage is read by name only');

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      throw UnsupportedError('production key storage is deleted by name only');

  static Future<void> _deleteFile(File file) async {
    for (final candidate in [file, File('${file.path}.tmp')]) {
      if (await candidate.exists()) await candidate.delete();
    }
  }
}
