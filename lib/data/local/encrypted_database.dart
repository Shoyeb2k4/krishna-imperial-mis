/// Opening the encrypted local database on Android and Windows.
///
/// The native SQLite build is selected in `pubspec.yaml` under `hooks.user_defines`:
/// `source: sqlite3mc` gives the SQLite3MultipleCiphers build, which provides AES-256
/// encryption uniformly on both target platforms (docs/DECISIONS.md D-029).
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart';

const String _databaseFileName = 'krishna_mis.db';

/// Raised when the database file exists but will not open with the key we hold —
/// almost always a lost or replaced key. Surfaced to the user in plain language.
class EncryptedDatabaseUnreadable implements Exception {
  const EncryptedDatabaseUnreadable(this.detail);
  final String detail;

  @override
  String toString() => 'EncryptedDatabaseUnreadable: $detail';
}

/// Applies the encryption key to a freshly opened connection.
///
/// Must run before any other statement. Passing the key in `x'…'` form hands SQLite the
/// raw 256-bit value rather than a passphrase to be derived, so the key we generated is
/// the key actually used.
void applyEncryptionKey(CommonDatabase db, String hexKey) {
  db.execute("PRAGMA key = \"x'$hexKey'\";");

  // Touching the schema forces SQLite to decrypt page 1. Without this, a wrong key is
  // not discovered until the first real query, somewhere far less convenient.
  try {
    db.execute('SELECT count(*) FROM sqlite_schema;');
  } on SqliteException catch (error) {
    throw EncryptedDatabaseUnreadable(
      'database did not open with the stored key (sqlite ${error.resultCode})',
    );
  }
}

/// Resolves the on-disk location of the database.
///
/// App-private storage on both platforms: `getApplicationSupportDirectory()` maps to
/// the app sandbox on Android and to `%APPDATA%\<company>\<product>` on Windows.
Future<File> resolveDatabaseFile() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return File(p.join(directory.path, _databaseFileName));
}

/// Opens the real, encrypted, on-disk database for the running app.
Future<AppDatabase> openEncryptedDatabase({
  DatabaseKeyManager? keyManager,
}) async {
  final manager = keyManager ?? DatabaseKeyManager();
  final key = await manager.obtainKey();
  final file = await resolveDatabaseFile();

  return AppDatabase(
    LazyDatabase(() async {
      return NativeDatabase(file, setup: (db) => applyEncryptionKey(db, key));
    }),
  );
}

/// Opens an encrypted database at an explicit path with an explicit key.
///
/// Used by the integration tests that prove encryption actually works on each platform,
/// and by the "can this file be read at all" recovery check.
AppDatabase openEncryptedDatabaseAt(File file, String hexKey) => AppDatabase(
  NativeDatabase(file, setup: (db) => applyEncryptionKey(db, hexKey)),
);

/// Proves a database file is genuinely encrypted by attempting to read it with no key.
///
/// Returns `true` when the file refuses to open unencrypted — which is the outcome we
/// want. Used as a positive assertion in the platform proof tests rather than trusting
/// that a pragma had the intended effect.
bool isFileEncrypted(File file) {
  if (!file.existsSync()) return false;
  CommonDatabase? db;
  try {
    db = sqlite3.open(file.path);
    db.execute('SELECT count(*) FROM sqlite_schema;');
    return false; // Opened and read without a key — not encrypted.
  } on SqliteException {
    return true;
  } finally {
    db?.close();
  }
}
