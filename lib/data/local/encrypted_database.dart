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

/// The database file's name, and the sidecars SQLite may keep beside it. Recovery moves
/// all of them together, because a database without its journal is a different database.
const String localDatabaseFileName = _databaseFileName;
const List<String> localDatabaseSidecarSuffixes = ['-wal', '-shm', '-journal'];

/// Raised when the database file exists but its first page will not read with the key we
/// hold — a lost or replaced key, or a damaged file. SQLite cannot tell the two apart
/// (both are `SQLITE_NOTADB`), so neither does this.
///
/// **Only** those result codes. A lock (`SQLITE_BUSY`) used to be reported as this too,
/// which told somebody whose file was merely in use that it was unreadable (D-329).
class EncryptedDatabaseUnreadable implements Exception {
  const EncryptedDatabaseUnreadable(this.detail, {this.resultCode});
  final String detail;

  /// The SQLite primary result code, when there was one.
  final int? resultCode;

  @override
  String toString() => 'EncryptedDatabaseUnreadable: $detail';
}

/// SQLite primary result codes the start-up path distinguishes.
abstract final class SqliteResult {
  static const int corrupt = 11;
  static const int notADatabase = 26;

  static int primary(int extended) => extended & 0xff;
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
    final code = SqliteResult.primary(error.resultCode);
    if (code == SqliteResult.notADatabase || code == SqliteResult.corrupt) {
      throw EncryptedDatabaseUnreadable(
        'database did not open with the stored key (sqlite $code)',
        resultCode: code,
      );
    }
    // A lock, a full disk or an I/O error is not evidence about the key or the file's
    // contents, and is reported as what it is.
    rethrow;
  }
}

/// Resolves the on-disk location of the database.
///
/// App-private storage on both platforms: `getApplicationSupportDirectory()` maps to
/// the app sandbox on Android and to `%APPDATA%\<company>\<product>` on Windows.
Future<File> resolveDatabaseFile({Directory? directory}) async {
  directory ??= await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return File(p.join(directory.path, _databaseFileName));
}

/// Opens the real, encrypted, on-disk database for the running app.
Future<AppDatabase> openEncryptedDatabase({
  DatabaseKeyManager? keyManager,
  Directory? directory,
  String? databaseKeyName,
}) async {
  final manager = keyManager ?? DatabaseKeyManager(keyName: databaseKeyName);
  final file = await resolveDatabaseFile(directory: directory);
  // A key is created only for a database that does not exist yet (D-329).
  final key = await manager.obtainKey(databaseExists: file.existsSync());

  return AppDatabase(
    LazyDatabase(() async {
      return NativeDatabase(file, setup: (db) => applyEncryptionKey(db, key));
    }),
  );
}

/// Opens the local database **and proves it is usable** before returning it.
///
/// The connection is lazy, so on its own a damaged file, a wrong key or a failed upgrade
/// would surface at whichever query happened to run first — at start-up that was the
/// outbox recovery, which made every failure look like a sync problem. Forcing the open
/// here runs the key check, every pending migration and `beforeOpen` at one place, and a
/// failure closes the connection before it propagates, so the file is free to be retried,
/// inspected or set aside (Phase 8 Slice 7, D-329).
///
/// [build] exists for tests that need to interrupt a migration; production passes none.
Future<AppDatabase> openLocalStore({
  DatabaseKeyManager? keyManager,
  Directory? directory,
  String? databaseKeyName,
  AppDatabase Function(QueryExecutor executor)? build,
}) async {
  final manager = keyManager ?? DatabaseKeyManager(keyName: databaseKeyName);
  final file = await resolveDatabaseFile(directory: directory);
  final key = await manager.obtainKey(databaseExists: file.existsSync());
  final executor = NativeDatabase(
    file,
    setup: (db) => applyEncryptionKey(db, key),
  );
  final database = (build ?? AppDatabase.new)(executor);
  try {
    await database.customSelect('SELECT 1').get();
    return database;
  } on Object {
    try {
      await database.close();
    } on Object {
      // The original failure is the one worth reporting.
    }
    rethrow;
  }
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

/// Where staged attachments live: inside the application's own support directory.
///
/// App-private by construction. A gallery path or a Downloads folder is not a place a
/// financial document can be kept — the OS may move, rename or revoke it between the
/// moment a bill is attached and the moment it uploads, which can be days later.
Future<Directory> resolveAttachmentStagingDirectory() async {
  final directory = Directory(
    p.join((await getApplicationSupportDirectory()).path, 'attachments'),
  );
  await directory.create(recursive: true);
  return directory;
}
