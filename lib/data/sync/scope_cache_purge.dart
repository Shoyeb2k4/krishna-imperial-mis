/// Removing locally cached reference data for a business unit the server has confirmed
/// this user no longer has (D-048).
///
/// Three properties matter more than the deletion itself:
///
///  1. **It only runs on confirmed authority.** The entry point takes an
///     [AuthorityRefresh], not a list of unit ids, so there is no signature that lets a
///     caller purge because a request timed out. `unknown ≠ revoked` is enforced by the
///     type, not by a comment.
///  2. **It never touches the outbox.** Queued, failed, rejected and conflicted work is
///     the user's, not the server's, and losing authority is not a reason to lose it.
///     The purge deletes from a fixed list of server-owned tables and asserts that the
///     outbox count is unchanged when it finishes.
///  3. **It is one transaction, bottom-up.** Categories before sections before
///     departments before the unit itself, so there is no moment at which a section
///     hangs off a department that is already gone, and no partially-purged hierarchy
///     if anything fails.
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/domain/auth/authority.dart';

/// What a purge did, for the sync log and for the tests.
final class ScopePurgeResult {
  const ScopePurgeResult({
    required this.revokedUnits,
    required this.rowsRemoved,
    required this.outboxEntriesPreserved,
    required this.skippedReason,
  });

  /// Nothing happened, and why. Null when a purge actually ran.
  const ScopePurgeResult.skipped(String reason)
    : revokedUnits = const {},
      rowsRemoved = const {},
      outboxEntriesPreserved = 0,
      skippedReason = reason;

  final Set<String> revokedUnits;

  /// Rows removed per table. Empty when nothing was cached for the revoked unit.
  final Map<String, int> rowsRemoved;

  /// How many outbox entries were present afterwards. Reported rather than assumed:
  /// this is the number the guarantee in D-048 §2 is about.
  final int outboxEntriesPreserved;

  final String? skippedReason;

  bool get didPurge => skippedReason == null && revokedUnits.isNotEmpty;
  int get totalRowsRemoved =>
      rowsRemoved.values.fold(0, (sum, count) => sum + count);

  @override
  String toString() => skippedReason != null
      ? 'ScopePurgeResult.skipped($skippedReason)'
      : 'ScopePurgeResult(${revokedUnits.length} units, $totalRowsRemoved rows, '
            '$outboxEntriesPreserved outbox entries preserved)';
}

class ScopeCachePurge {
  const ScopeCachePurge(this.db);

  final AppDatabase db;

  /// Purges cached reference data for any unit the confirmed authority no longer covers.
  ///
  /// [previous] is what this device last believed. A null previous snapshot means the
  /// device has nothing to compare against, so nothing is considered revoked — a first
  /// sign-in must never look like a mass revocation.
  Future<ScopePurgeResult> applyTo(
    AuthorityRefresh refresh, {
    required AuthoritySnapshot? previous,
  }) async {
    // The whole point of D-048 §1. A failed refresh is not a denial, and there is
    // deliberately no other way into the deletion below.
    if (refresh is! AuthorityConfirmed) {
      return ScopePurgeResult.skipped(
        'authority was not confirmed (${(refresh as AuthorityUnavailable).reason.name}) '
        '— cached data is kept and shown as stale',
      );
    }

    final revoked = refresh.snapshot.unitsRevokedSince(previous);
    if (revoked.isEmpty) {
      return const ScopePurgeResult.skipped('no business unit was revoked');
    }

    return purgeUnits(revoked);
  }

  /// The deletion itself, for a set of units already established as revoked.
  ///
  /// Separate from [applyTo] so it can be exercised directly, but deliberately not the
  /// documented entry point: everything in production reaches it through the confirmed
  /// authority above.
  Future<ScopePurgeResult> purgeUnits(Set<String> units) async {
    if (units.isEmpty) {
      return const ScopePurgeResult.skipped('no business unit was revoked');
    }

    final outboxBefore = await _outboxCount();
    final removed = <String, int>{};

    await db.transaction(() async {
      // Bottom-up. Each step deletes only rows reachable from the revoked units, and the
      // order guarantees a parent is never removed before its children.
      removed['revenue_tax_rates'] = await _delete(
        'DELETE FROM revenue_tax_rates WHERE revenue_category_id IN '
        '(SELECT id FROM revenue_categories WHERE business_unit_id IN ${_in(units)})',
        units,
      );
      removed['expense_categories'] = await _delete(
        'DELETE FROM expense_categories WHERE section_id IN '
        '(SELECT s.id FROM sections s JOIN departments d ON d.id = s.department_id '
        ' WHERE d.business_unit_id IN ${_in(units)})',
        units,
      );
      removed['sections'] = await _delete(
        'DELETE FROM sections WHERE department_id IN '
        '(SELECT id FROM departments WHERE business_unit_id IN ${_in(units)})',
        units,
      );
      removed['departments'] = await _delete(
        'DELETE FROM departments WHERE business_unit_id IN ${_in(units)}',
        units,
      );
      removed['revenue_categories'] = await _delete(
        'DELETE FROM revenue_categories WHERE business_unit_id IN ${_in(units)}',
        units,
      );
      removed['period_locks'] = await _delete(
        'DELETE FROM period_locks WHERE business_unit_id IN ${_in(units)}',
        units,
      );
      // Vendors are deliberately absent from this transaction (D-049).
      //
      // A vendor may name the revoked unit as its entry-form default, and an earlier
      // draft cleared that locally. That was wrong: the vendor has not changed. One
      // user losing a property is not an edit to a company-wide supplier record, and
      // writing NULL over the cached canonical value would be undone by the very next
      // pull — a pointless pull/clear/pull/clear cycle — while making the local row
      // disagree with the server for no reason.
      //
      // The default is instead filtered at the point of use, through
      // `Vendor.effectiveDefaultBusinessUnitId`, which is derived per user from their
      // current authoritative scope and owns nothing.
      removed['business_units'] = await _delete(
        'DELETE FROM business_units WHERE id IN ${_in(units)}',
        units,
      );
    });

    final outboxAfter = await _outboxCount();
    if (outboxAfter != outboxBefore) {
      // Not a recoverable situation: the one guarantee that must not bend has bent.
      throw StateError(
        'the scope purge changed the outbox from $outboxBefore to $outboxAfter entries. '
        'Queued, failed, rejected and conflicted work must survive an authority change '
        'untouched (D-048 §2).',
      );
    }

    return ScopePurgeResult(
      revokedUnits: units,
      rowsRemoved: removed,
      outboxEntriesPreserved: outboxAfter,
      skippedReason: null,
    );
  }

  /// Removes **every** cached business-unit-scoped record, whatever the unit.
  ///
  /// For a user switch, not a revocation. When a different person signs in on the same
  /// installation — a shared back-office Windows machine is the normal case — the
  /// previous user's downloaded hierarchy must not be browsable while the new user's own
  /// authority is still being established. Nothing about the previous session's scope is
  /// evidence of anything about this one.
  ///
  /// The new user's own reference data arrives moments later from their own authority
  /// refresh, so the cost is one pull. The outbox is untouched here as everywhere: each
  /// entry belongs to whoever queued it (D-050), and signing out is not a reason to lose
  /// somebody's unsent work.
  Future<ScopePurgeResult> purgeAllScopedCache() async {
    final units = await _allCachedUnitIds();
    if (units.isEmpty) {
      return const ScopePurgeResult.skipped(
        'no scoped reference data was cached',
      );
    }
    return purgeUnits(units);
  }

  Future<Set<String>> _allCachedUnitIds() async {
    final rows = await db.customSelect('SELECT id FROM business_units').get();
    return {for (final row in rows) row.data['id'] as String};
  }

  String _in(Set<String> units) =>
      '(${List.filled(units.length, '?').join(', ')})';

  Future<int> _delete(String sql, Set<String> units) => db.customUpdate(
    sql,
    variables: [for (final unit in units) Variable<String>(unit)],
    updates: const {},
  );

  Future<int> _outboxCount() async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM sync_outbox')
        .getSingle();
    return row.data['c'] as int;
  }
}
