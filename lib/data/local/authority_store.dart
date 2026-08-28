/// The last authority the server confirmed on this device, and whose it was.
///
/// Two jobs, and the second is the security-relevant one:
///
///  1. It lets a previously-verified user keep working offline against permitted cached
///     data, with the staleness visible.
///  2. It records **which user** that authority belongs to. A shared Windows machine in
///     a back office sees several people sign in and out of one installation, and
///     authority cached for the Owner must never be handed to a Manager who signs in
///     afterwards.
///
/// Every read is therefore keyed by user id and returns nothing for anybody else. There
/// is no "load the cached authority" method that does not name whose it should be —
/// which means the mistake cannot be made by forgetting a check.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';

class AuthorityStore {
  const AuthorityStore(this._db);

  final AppDatabase _db;

  static const _key = 'authority.snapshot.v2';

  /// The stored authority, **only** if it belongs to [userId].
  ///
  /// Returns null for a different user rather than throwing: signing in as somebody else
  /// is an ordinary thing to do, and the correct response is simply to have no cached
  /// authority yet — which then fails closed until the server answers.
  Future<AuthoritySnapshot?> loadFor(String userId) async {
    final stored = await _read();
    if (stored == null) return null;
    if (stored.userId != userId) return null;
    return stored;
  }

  /// Who the stored authority belongs to, without returning any of it.
  ///
  /// Used to detect a user switch before deciding what to do about the cache.
  Future<String?> ownerUserId() async => (await _read())?.userId;

  Future<void> save(AuthoritySnapshot snapshot) => _db.customInsert(
    'INSERT INTO app_meta (key, value, updated_at) VALUES (?, ?, ?) '
    'ON CONFLICT(key) DO UPDATE SET value = excluded.value, '
    'updated_at = excluded.updated_at',
    variables: [
      const Variable<String>(_key),
      Variable<String>(
        jsonEncode({
          'user_id': snapshot.userId,
          'org_id': snapshot.orgId,
          'resolved_at': snapshot.resolvedAt.toIso8601String(),
          'grants': [
            for (final grant in snapshot.grants)
              {
                'capability': grant.capability.code,
                'business_unit_id': grant.businessUnitId,
              },
          ],
        }),
      ),
      Variable<String>(DateTime.now().toUtc().toIso8601String()),
    ],
  );

  /// Forgets the stored authority entirely.
  ///
  /// Called on sign-out and on a user switch. Deliberately does **not** touch the
  /// outbox: losing a permission is not a reason to lose somebody's unsent work, and
  /// neither is signing out (D-048 §2, `ARCHITECTURE.md` §8.2).
  Future<void> clear() => _db.customUpdate(
    'DELETE FROM app_meta WHERE key = ?',
    variables: [const Variable<String>(_key)],
    updates: const {},
  );

  Future<AuthoritySnapshot?> _read() async {
    final rows = await _db
        .customSelect(
          'SELECT value FROM app_meta WHERE key = ?',
          variables: [const Variable<String>(_key)],
        )
        .get();
    if (rows.isEmpty) return null;

    try {
      final decoded = jsonDecode(rows.single.data['value'] as String);
      if (decoded is! Map) return null;
      final userId = decoded['user_id'];
      final orgId = decoded['org_id'];
      if (userId is! String || orgId is! String) return null;

      final grants = <CapabilityGrant>[];
      for (final entry in (decoded['grants'] as List? ?? const [])) {
        if (entry is! Map) continue;
        final code = entry['capability'];
        if (code is! String) continue;
        try {
          grants.add(
            CapabilityGrant(
              Capability.fromCode(code),
              businessUnitId: entry['business_unit_id'] as String?,
            ),
          );
        } on ArgumentError {
          // A capability this build no longer knows. Dropping it narrows what the user
          // can do, which is the safe direction for an unreadable stored permission.
          continue;
        }
      }

      return AuthoritySnapshot(
        userId: userId,
        orgId: orgId,
        grants: grants,
        resolvedAt:
            DateTime.tryParse('${decoded['resolved_at']}')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    } on FormatException {
      // Unreadable stored authority is treated as none at all. The user simply has to
      // be online once more; inventing permissions from a corrupted blob is the one
      // outcome that would actually be dangerous.
      return null;
    }
  }
}
