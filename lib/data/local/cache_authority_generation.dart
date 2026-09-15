/// Which session and which authority the canonical caches currently belong to (D-231).
///
/// Phase 5 Slice 11. A synchronisation is a request and, later, a write. Between the two the
/// person may sign out, a different person may sign in, or a confirmed authority refresh may
/// withdraw a capability the run was started under — and the purge that follows removes the
/// cache. Without this record the late answer is written back afterwards, under the old
/// person's id, onto a shared machine.
///
/// ## Why the existing authority record could not do it
///
/// `AuthorityStore` already knows whose authority is cached, but it is saved and cleared
/// **outside** the purge's transaction, so there is always a moment in which the purge has
/// committed and the stored authority still names the old answer. A check against it would
/// be a check that can be passed at exactly the wrong time.
///
/// This record is written **inside** the purge's own transaction, and a synchroniser checks
/// it **inside** the transaction that would write. Drift runs both on one connection, so the
/// two are strictly ordered: either the write commits before the purge, and the purge removes
/// it, or the purge commits first and the write sees a newer generation and writes nothing.
///
/// ## What moves it
///
///  * the end of a session — sign-out, a user switch, and the sign-out fail-closed path;
///  * a confirmed authority whose reporting or owner-settlement capabilities differ from the
///    last one recorded.
///
/// An unrelated grant change does not move it, and neither does a refresh that could not
/// reach the server — unknown is not revoked (D-048).
///
/// It is not financial data, adds no table, and lives in `app_meta` beside the authority
/// record it complements.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';

/// The generation a synchroniser started under.
final class CacheGeneration {
  const CacheGeneration({required this.epoch, this.userId, this.fingerprint});

  final int epoch;

  /// Whose session the caches belong to. Null once a session has ended.
  final String? userId;

  final String? fingerprint;
}

/// Thrown inside a cache transaction when the run that opened it is no longer current. The
/// transaction rolls back, so nothing it would have written exists.
final class StaleCacheGeneration implements Exception {
  const StaleCacheGeneration(this.reason);
  final String reason;

  @override
  String toString() => 'StaleCacheGeneration($reason)';
}

class CacheAuthorityGeneration {
  const CacheAuthorityGeneration(this._db);

  final AppDatabase _db;

  static const key = 'cache.authority.generation.v1';

  /// The capabilities whose loss makes an in-flight canonical synchronisation stale: the
  /// three a P&L needs (D-164) and the two the owner-settlement cache needs (OA-3).
  static const relevant = {
    Capability.reportsView,
    Capability.revenueView,
    Capability.expenseViewAll,
    Capability.ownerSettlementView,
    Capability.ownerLedgerView,
  };

  Future<CacheGeneration?> read() async {
    final rows = await _db
        .customSelect(
          'SELECT value FROM app_meta WHERE key = ?',
          variables: [const Variable<String>(key)],
        )
        .get();
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.single.data['value'] as String);
      if (decoded is! Map) return null;
      final epoch = decoded['epoch'];
      if (epoch is! int) return null;
      return CacheGeneration(
        epoch: epoch,
        userId: decoded['user_id'] as String?,
        fingerprint: decoded['fingerprint'] as String?,
      );
    } on FormatException {
      return null;
    }
  }

  /// Records a confirmed authority. Moves the generation only when whose it is, or what it
  /// may read, has changed. Call inside the purge's transaction.
  Future<void> recordConfirmed(AuthoritySnapshot snapshot) async {
    final current = await read();
    final fingerprint = fingerprintOf(snapshot);
    if (current != null &&
        current.userId == snapshot.userId &&
        current.fingerprint == fingerprint) {
      return;
    }
    await _write(
      CacheGeneration(
        epoch: (current?.epoch ?? 0) + 1,
        userId: snapshot.userId,
        fingerprint: fingerprint,
      ),
    );
  }

  /// Ends the session the caches belonged to. Every run started before this is stale.
  Future<void> endSession() async {
    final current = await read();
    await _write(CacheGeneration(epoch: (current?.epoch ?? 0) + 1));
  }

  /// Refuses, by throwing [StaleCacheGeneration], unless the generation is exactly the one
  /// [startedUnder] and still belongs to [ownerUserId]. Call inside the writing transaction.
  ///
  /// A run that started before anything was ever recorded, and still finds nothing recorded,
  /// is allowed: nothing has happened since that could make it stale.
  Future<void> ensureStillCurrent({
    required CacheGeneration? startedUnder,
    required String ownerUserId,
  }) async {
    final current = await read();
    if (current == null && startedUnder == null) return;
    if (current == null || startedUnder == null) {
      throw const StaleCacheGeneration(
        'the session or authority changed while this run was in flight',
      );
    }
    if (current.epoch != startedUnder.epoch) {
      throw const StaleCacheGeneration(
        'the session or authority changed while this run was in flight',
      );
    }
    if (current.userId != ownerUserId) {
      throw const StaleCacheGeneration(
        'the caches no longer belong to the person this run was started for',
      );
    }
  }

  /// A stable description of what this authority may read from the canonical caches.
  static String fingerprintOf(AuthoritySnapshot snapshot) {
    final grants = <String>{
      for (final grant in snapshot.grants)
        if (relevant.contains(grant.capability))
          '${grant.capability.code}@${grant.businessUnitId ?? '*'}',
    }.toList()..sort();
    return '${snapshot.userId}|${snapshot.orgId}|${grants.join(',')}';
  }

  Future<void> _write(CacheGeneration generation) => _db.customInsert(
    'INSERT INTO app_meta (key, value, updated_at) VALUES (?, ?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value, '
    'updated_at = excluded.updated_at',
    variables: [
      const Variable<String>(key),
      Variable<String>(
        jsonEncode({
          'epoch': generation.epoch,
          'user_id': generation.userId,
          'fingerprint': generation.fingerprint,
        }),
      ),
      Variable<String>(DateTime.now().toUtc().toIso8601String()),
    ],
  );
}
