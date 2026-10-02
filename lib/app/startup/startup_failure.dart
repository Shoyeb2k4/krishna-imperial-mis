/// What stopped the application from starting, in terms a person can act on.
///
/// Every start-up failure used to reach the screen as its raw exception text — a SQLite
/// message, a file path — under one sentence that called it a database problem whatever
/// it was (D-316). A lock read as "unreadable"; a missing key read as a damaged file.
/// This classifies the failure first, so the screen can say what happened, what was not
/// touched, and what will help — and so the one destructive answer, setting the local
/// data aside, is offered **only** where it can help (Phase 8 Slice 7, D-329, D-330).
library;

import 'dart:io';

import 'package:drift/drift.dart' show CouldNotRollBackException;

import 'package:krishna_mis/app/bootstrap.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:sqlite3/common.dart' show SqliteException;

enum StartupFailureKind {
  /// The build itself is misconfigured. Nothing local is involved.
  configuration,

  /// The device's secure store could not be read or written just now — on Android,
  /// ordinary before the first unlock after a restart. Try again; never reset, because a
  /// store that cannot be written would refuse the new key a reset needs.
  keyStoreUnavailable,

  /// The local data will not open: its key is missing or is not a key, the key does not
  /// open it, or the file is damaged. Trying again is offered first; resetting is
  /// offered, because nothing else can open it.
  localDataUnreadable,

  /// An upgrade to this version's schema did not complete. Since Slice 7 it ran in one
  /// transaction, so the data is exactly as it was. Try again (or update the app);
  /// resetting is offered, with what it would lose.
  upgradeFailed,

  /// Another copy of the app, or another program, holds the database. Close it and try
  /// again. Never reset: the data is fine.
  inUse,

  /// The device could not read or write its storage — full, removed, refused. Free space
  /// and try again. Never reset: a reset needs storage too.
  storage,

  /// Anything else. Try again; if it persists, tell support. Never reset on a guess.
  unexpected,
}

/// A classified start-up failure.
class StartupFailure {
  const StartupFailure(this.kind);

  final StartupFailureKind kind;

  /// Whether "Reset local data and download again" may be offered at all.
  ///
  /// Only where the local data itself cannot be used and nothing short of setting it
  /// aside will change that. A lock, a full disk, an unavailable key store, a build
  /// problem and an unknown error are never answered with a reset.
  bool get permitsReset => switch (kind) {
    StartupFailureKind.localDataUnreadable ||
    StartupFailureKind.upgradeFailed => true,
    StartupFailureKind.configuration ||
    StartupFailureKind.keyStoreUnavailable ||
    StartupFailureKind.inUse ||
    StartupFailureKind.storage ||
    StartupFailureKind.unexpected => false,
  };

  /// A short code a person can quote to support. It names the kind and nothing else —
  /// no path, no message, no key material.
  String get reference => 'START-${kind.name.toUpperCase()}';

  /// Classifies whatever start-up threw.
  static StartupFailure classify(Object error) =>
      StartupFailure(_kindOf(error));

  static StartupFailureKind _kindOf(Object error) {
    switch (error) {
      case ConfigurationRefused():
        return StartupFailureKind.configuration;
      case CouldNotRollBackException(:final cause):
        // SQLite rolls a transaction back by itself on some errors — a full disk among
        // them — and drift's own ROLLBACK then finds nothing to roll back. The cause is
        // what happened (D-329).
        return _kindOf(cause);
      case DatabaseKeyUnavailable(:final problem):
        return switch (problem) {
          DatabaseKeyProblem.storeUnreadable ||
          DatabaseKeyProblem.storeUnwritable =>
            StartupFailureKind.keyStoreUnavailable,
          DatabaseKeyProblem.malformed ||
          DatabaseKeyProblem.missingForExistingDatabase =>
            StartupFailureKind.localDataUnreadable,
        };
      case EncryptedDatabaseUnreadable():
        return StartupFailureKind.localDataUnreadable;
      case LocalSchemaMigrationFailed(:final cause, :final from):
        // The cause decides first: a full disk during an upgrade is a storage problem,
        // and a lock is a lock. Only what is neither is the upgrade's own failure — and a
        // fresh database that could not be created has nothing worth resetting.
        final underlying = _kindOf(cause);
        if (underlying != StartupFailureKind.unexpected) return underlying;
        return from == null
            ? StartupFailureKind.unexpected
            : StartupFailureKind.upgradeFailed;
      case SqliteException(:final resultCode):
        return switch (SqliteResult.primary(resultCode)) {
          5 || 6 => StartupFailureKind.inUse, // BUSY, LOCKED
          11 || 26 => StartupFailureKind.localDataUnreadable, // CORRUPT, NOTADB
          8 ||
          10 ||
          13 ||
          14 => StartupFailureKind.storage, // READONLY, IOERR, FULL, CANTOPEN
          _ => StartupFailureKind.unexpected,
        };
      case FileSystemException():
        return StartupFailureKind.storage;
      default:
        return StartupFailureKind.unexpected;
    }
  }
}
