/// Sign-out, local-data erasure, and what happens when the encryption key is gone.
///
/// This is the code behind `docs/ARCHITECTURE.md` §8.2. The rules exist because the
/// local database is the *only* place an unsynced entry lives: a manager who records a
/// ₹18,400 bill on a rooftop with no signal has that figure nowhere else until it syncs.
library;

import 'dart:io';

import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';

/// Raised when erasing local data would destroy work the server has never seen.
///
/// Carries the count so the UI can say "12 entries have not synced yet" rather than a
/// vague warning.
class UnsyncedDataPending implements Exception {
  const UnsyncedDataPending(this.pendingCount);
  final int pendingCount;

  @override
  String toString() =>
      'UnsyncedDataPending: $pendingCount entries have not reached the server yet';
}

/// What a sign-out actually did, so the caller can tell the user the truth.
class SignOutOutcome {
  const SignOutOutcome({
    required this.localDataRetained,
    required this.pendingCount,
  });

  /// Always true for an ordinary sign-out.
  final bool localDataRetained;

  /// Entries still queued. Shown so the user knows work is waiting for the next
  /// sign-in rather than silently sitting there.
  final int pendingCount;
}

class LocalDataLifecycle {
  LocalDataLifecycle({
    required this.outbox,
    required this.keyManager,
    Future<File> Function()? resolveFile,
  }) : _resolveFile = resolveFile ?? resolveDatabaseFile;

  final OutboxRepository outbox;
  final DatabaseKeyManager keyManager;
  final Future<File> Function() _resolveFile;

  /// Ordinary sign-out: clears the session and **nothing else**.
  ///
  /// The local database and its queued mutations survive deliberately. Wiping them on
  /// sign-out would silently destroy entries that exist nowhere else — the single worst
  /// thing this application could do to a manager.
  Future<SignOutOutcome> signOut({
    required Future<void> Function() clearSession,
  }) async {
    await clearSession();
    return SignOutOutcome(
      localDataRetained: true,
      pendingCount: await outbox.unsyncedCount(),
    );
  }

  /// Explicitly destructive: sign out **and erase everything held on this device**.
  ///
  /// Refuses while anything is queued. [force] exists only for the case where the user
  /// has been shown the exact count and typed a confirmation; it is never a default and
  /// never a retry-on-failure path.
  Future<void> eraseLocalData({
    required AppDatabase database,
    required Future<void> Function() clearSession,
    bool force = false,
  }) async {
    final pending = await outbox.unsyncedCount();
    if (pending > 0 && !force) {
      throw UnsyncedDataPending(pending);
    }

    await clearSession();
    await database.close();

    final file = await _resolveFile();
    for (final path in [
      file.path,
      '${file.path}-wal',
      '${file.path}-shm',
      '${file.path}-journal',
    ]) {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    }

    // The key goes last. If deletion of the files failed, the key is still present and
    // the database is still readable — a partially erased state that can be retried,
    // rather than an orphaned encrypted file nobody can ever open or verify.
    await keyManager.deleteKey();
  }

  /// Whether this installation still holds a usable key.
  ///
  /// False after erasure, and false when the OS keystore has been reset or the app data
  /// was restored onto a different device. In that second case the database file may
  /// still exist but is permanently unreadable — which is what encryption means. The
  /// app says so plainly and offers a reset-and-resync; it does not pretend the data is
  /// recoverable.
  Future<bool> hasUsableKey() => keyManager.hasKey();
}
