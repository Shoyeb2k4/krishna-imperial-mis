/// Recovery from a local database this installation can no longer open.
///
/// This is the flow `docs/ARCHITECTURE.md` §8.2 promised and D-316 recorded as missing.
/// It does two things, and only when a person has asked for them (Phase 8 Slice 7,
/// D-329, D-330):
///
///  1. **Assess** what would be lost — read-only, never changing a byte — so the person
///     is told how much unsent work the local data holds, or told plainly that it cannot
///     be checked;
///  2. **Set the data aside and start empty** — move the database, its sidecars and its
///     staged bills into a quarantine folder, keep the key that belonged to them under a
///     name no ordinary start-up reads, and only then remove the active key so the next
///     start creates a new one with an empty database.
///
/// Nothing here deletes a financial byte. Nothing here runs on its own: start-up never
/// calls it, and the screen that does requires a typed confirmation first.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// What the local data would lose if it were set aside.
sealed class UnsyncedWorkAssessment {
  const UnsyncedWorkAssessment();
}

/// There is no local database file at all, so there is nothing to lose.
final class NoLocalDataFound extends UnsyncedWorkAssessment {
  const NoLocalDataFound();
}

/// The local data was read, and this is what it holds that the server has not accepted.
final class UnsyncedWorkCounted extends UnsyncedWorkAssessment {
  const UnsyncedWorkCounted({
    required this.queued,
    required this.needsAttention,
    required this.billsNotUploaded,
  });

  /// Entries waiting to be sent: pending, in flight, failed for now, or paused on sign-in.
  final int queued;

  /// Entries the server answered but did not accept — a conflict or a refusal — which
  /// wait for a person to decide (D-048 §2).
  final int needsAttention;

  /// Attached bills not yet on the server, or null when the tables could not be read.
  final int? billsNotUploaded;

  int get entries => queued + needsAttention;

  /// True only when every count was read and every one is zero.
  bool get nothingUnsent => entries == 0 && billsNotUploaded == 0;
}

/// Why the local data's unsent work could not be counted.
enum UnsyncedWorkUnknownReason {
  /// No usable key is held, so the file cannot be read at all.
  keyUnavailable,

  /// The key was applied and the file still would not read, or the read failed.
  unreadable,
}

/// The local data could not be read, so nobody can say what it holds. The person is told
/// exactly that — never that everything is safe.
final class UnsyncedWorkUnknown extends UnsyncedWorkAssessment {
  const UnsyncedWorkUnknown(this.reason);
  final UnsyncedWorkUnknownReason reason;
}

/// A reset that did not complete. Whatever this attempt moved has been put back where it
/// could be, and the active key is untouched, so the person can simply try again.
class LocalStoreResetFailed implements Exception {
  const LocalStoreResetFailed(this.stage, this.cause);

  /// Where it stopped: `key` (setting the key aside), `record`, `move`.
  final String stage;
  final Object cause;

  @override
  String toString() => 'LocalStoreResetFailed($stage): $cause';
}

/// What a completed reset set aside.
class QuarantineRecord {
  const QuarantineRecord({
    required this.id,
    required this.directory,
    required this.movedFiles,
    required this.keyEntry,
  });

  final String id;

  /// The quarantine folder. For diagnostics only; never shown to a person.
  final Directory directory;

  /// The file and folder names moved into it.
  final List<String> movedFiles;

  /// The secure-store entry the old key was set aside under, or null when there was no
  /// key to keep — in which case the moved bytes have forensic value only.
  final String? keyEntry;

  bool get keyRetained => keyEntry != null;
}

/// The recovery service for one installation's local data.
class LocalStoreRecovery {
  LocalStoreRecovery({
    required this.directory,
    required this.keyManager,
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  /// The folder holding the database — the application support folder in production.
  final Directory directory;

  /// The manager for this installation's key, named by [databaseKeyNameFor].
  final DatabaseKeyManager keyManager;

  final DateTime Function() _clock;
  final Random _random;

  /// The folder quarantined data goes to, beside the database and never inside anything
  /// the app reads.
  static const String recoveryFolderName = 'recovery';

  /// Staged bills live here (`resolveAttachmentStagingDirectory`); they belong to the
  /// database that references them and go with it.
  static const String attachmentsFolderName = 'attachments';

  File get _databaseFile => File(p.join(directory.path, localDatabaseFileName));

  /// Reads the local data, **read-only**, and counts what it holds that is unsent.
  ///
  /// Never throws: anything it cannot read becomes [UnsyncedWorkUnknown], because the
  /// one answer this must never give by accident is "nothing to lose".
  Future<UnsyncedWorkAssessment> assess() async {
    final file = _databaseFile;
    if (!file.existsSync()) return const NoLocalDataFound();

    String? key;
    try {
      key = await keyManager.readStoredKey();
    } on DatabaseKeyUnavailable {
      key = null;
    }
    if (key == null) {
      return const UnsyncedWorkUnknown(
        UnsyncedWorkUnknownReason.keyUnavailable,
      );
    }

    Database? db;
    try {
      db = sqlite3.open(file.path, mode: OpenMode.readOnly);
      applyEncryptionKey(db, key);
      var queued = 0;
      var needsAttention = 0;
      for (final row in db.select(
        'SELECT status, COUNT(*) AS n FROM sync_outbox GROUP BY status',
      )) {
        final status = row['status'] as String?;
        final n = row['n'] as int;
        switch (status) {
          case 'done':
            break;
          case 'conflict' || 'rejected':
            needsAttention += n;
          default:
            // pending, inFlight, failed, blockedAuth — and any status this build cannot
            // name, which is counted as unsent rather than assumed delivered.
            queued += n;
        }
      }
      return UnsyncedWorkCounted(
        queued: queued,
        needsAttention: needsAttention,
        billsNotUploaded: _countBillsNotUploaded(db),
      );
    } on Object {
      return const UnsyncedWorkUnknown(UnsyncedWorkUnknownReason.unreadable);
    } finally {
      db?.close();
    }
  }

  static int? _countBillsNotUploaded(Database db) {
    try {
      final tables = {
        for (final r in db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('expense_attachments', 'revenue_attachments')",
        ))
          r['name'] as String,
      };
      var total = 0;
      for (final table in tables) {
        total +=
            db
                    .select(
                      'SELECT COUNT(*) AS n FROM $table '
                      "WHERE upload_state NOT IN ('uploaded', 'stagingReclaimed')",
                    )
                    .first['n']
                as int;
      }
      return total;
    } on Object {
      return null;
    }
  }

  /// Sets the local data aside and leaves the installation ready to start empty.
  ///
  /// The order is what makes it safe to stop at any point:
  ///
  ///  1. the key is **copied** aside and read back — the active entry is untouched;
  ///  2. a small record is written describing what is being set aside and why;
  ///  3. the sidecars, then the database, then the staged bills are **moved**, never
  ///     deleted — sidecars first, so a journal is never left behind to be replayed into
  ///     the new database;
  ///  4. only then is the active key removed, so the next start creates a new one.
  ///
  /// Stopped after 1 or 2: nothing has moved, and the same damaged file is offered again.
  /// Stopped during 3: this attempt's moves are put back. Stopped after 3, before 4: the
  /// next start finds no database and opens an empty one with the old key, which still
  /// opens the quarantined copy too. Nothing in any of those states loses a byte.
  ///
  /// [reason] is a short code for the record; it carries no data.
  Future<QuarantineRecord> setAsideAndReset({required String reason}) async {
    final id = _newId();
    final quarantine = Directory(
      p.join(directory.path, recoveryFolderName, 'quarantine-$id'),
    );

    // 1. The key, copied aside under a name no start-up reads.
    String? key;
    String? keyEntry;
    try {
      key = await keyManager.readStoredKey();
      if (key != null) {
        keyEntry = '${keyManager.keyName}.quarantine.$id';
        await keyManager.storeAside(keyEntry, key);
      }
    } on Object catch (error) {
      throw LocalStoreResetFailed('key', error);
    }

    // 2. The record.
    final candidates = [
      for (final suffix in localDatabaseSidecarSuffixes)
        '$localDatabaseFileName$suffix',
      localDatabaseFileName,
    ];
    try {
      await quarantine.create(recursive: true);
      await File(p.join(quarantine.path, 'recovery.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'id': id,
          'set_aside_at': _clock().toUtc().toIso8601String(),
          'reason': reason,
          'key_retained': keyEntry != null,
          'key_entry': keyEntry,
          'note': keyEntry != null
              ? 'The key this installation held is kept under key_entry. It did not '
                    'necessarily open these files: a damaged first page and a wrong '
                    'key look the same to SQLite.'
              : 'No key was held for these files. They are kept for forensic purposes '
                    'only; this application cannot open them.',
        }),
        flush: true,
      );
    } on Object catch (error) {
      throw LocalStoreResetFailed('record', error);
    }

    // 3. The files: sidecars, database, staged bills.
    final moved = <(String from, String to)>[];
    try {
      for (final name in candidates) {
        final source = File(p.join(directory.path, name));
        if (source.existsSync()) {
          final target = p.join(quarantine.path, name);
          await source.rename(target);
          moved.add((source.path, target));
        }
      }
      final staging = Directory(p.join(directory.path, attachmentsFolderName));
      if (staging.existsSync()) {
        final target = p.join(quarantine.path, attachmentsFolderName);
        await staging.rename(target);
        moved.add((staging.path, target));
      }
    } on Object catch (error) {
      for (final (from, to) in moved.reversed) {
        try {
          if (FileSystemEntity.isDirectorySync(to)) {
            Directory(to).renameSync(from);
          } else {
            File(to).renameSync(from);
          }
        } on Object {
          // Left in quarantine; still not deleted, and the record says what was meant.
        }
      }
      throw LocalStoreResetFailed('move', error);
    }

    // 4. The active key, last.
    if (key != null) {
      await keyManager.deleteKey();
    }

    return QuarantineRecord(
      id: id,
      directory: quarantine,
      movedFiles: [for (final (from, _) in moved) p.basename(from)],
      keyEntry: keyEntry,
    );
  }

  String _newId() {
    final now = _clock().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}T'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}Z';
    final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '$stamp-$suffix';
  }
}
