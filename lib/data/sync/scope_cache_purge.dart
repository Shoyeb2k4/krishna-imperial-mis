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
///
/// ## What it removes, since D-068
///
/// Two kinds of thing, in one transaction, for the same revoked units.
///
/// **Server-owned reference data** — the hierarchy, unit-scoped tax rules, period locks,
/// the unit itself. Unconditional. The server hands every row back the moment authority
/// returns, so removing it costs a pull and nothing else.
///
/// **Synced financial documents** — expenses, their allocation lines, their period
/// contributions, their attachment records and the staged bytes on disk. This is the
/// project lead's final D-068 policy, and it reverses what the Phase 3 checkpoint
/// shipped: a confirmed revocation must not leave the revoked property's figures sitting
/// in a browsable local cache until the user happens to sign out.
///
/// With one exception, and the exception is the point:
///
/// > A document that still carries **the actor's own unsynced intent** — queued, failed,
/// > rejected or conflicted — is retained whole, stamped `expenses.scope_revoked_at`, and
/// > removed from every canonical financial read.
///
/// Retained *whole*, deliberately. Half-deleting the document behind an unsent intent
/// would leave the person who queued it unable to see what they submitted, which is the
/// one thing the retention exists for. Excluding it from browsing is what makes that
/// safe: it is no longer presented as authorised financial data anywhere, and reaches
/// the user only through the pending / rejected / conflict workflow that owns it.
///
/// ## The partially revoked shared bill
///
/// A ₹58,000 invoice charging both properties, held complete by someone who then loses
/// Crystal Canopy but keeps Hotel Krishna:
///
///     before        after
///     ─────────────────────────────────────────────
///     complete      scoped              ← downgraded
///     total 58,000  total NULL          ← required
///     CCR 25,000    (deleted)
///     HKI 33,000    HKI 33,000
///     visible 58,000 visible 33,000
///
/// The downgrade is not tidiness. Leaving the header `complete` beside the one surviving
/// line publishes `58,000 − 33,000 = 25,000` — the share that was just revoked — which is
/// the precise leak the local read model was shaped to make impossible (D-062). The
/// attachment goes with it, because an attachment is the whole bill and D-063 makes it
/// complete-document-only.
///  3. **It is one transaction, bottom-up.** Categories before sections before
///     departments before the unit itself, so there is no moment at which a section
///     hangs off a department that is already gone, and no partially-purged hierarchy
///     if anything fails.
library;

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/cache_authority_generation.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';

/// What a purge did, for the sync log and for the tests.
final class ScopePurgeResult {
  const ScopePurgeResult({
    required this.revokedUnits,
    required this.rowsRemoved,
    required this.outboxEntriesPreserved,
    required this.skippedReason,
    this.documentsRemoved = const {},
    this.documentsDowngraded = const {},
    this.documentsRetainedForUnsyncedWork = const {},
    this.stagingReclaimed = const {},
    this.physicalReclaim,
  });

  /// No business unit was revoked, and why.
  ///
  /// [rowsRemoved] is non-empty only when a **capability** purge ran instead (OA-3): a
  /// confirmed authority can withdraw the owner domain while every property is kept, and
  /// that removal is reported rather than hidden behind the word "skipped".
  const ScopePurgeResult.skipped(String reason, {this.rowsRemoved = const {}})
    : revokedUnits = const {},
      outboxEntriesPreserved = 0,
      skippedReason = reason,
      documentsRemoved = const {},
      documentsDowngraded = const {},
      documentsRetainedForUnsyncedWork = const {},
      stagingReclaimed = const {},
      physicalReclaim = null;

  final Set<String> revokedUnits;

  /// Rows removed per table. Empty when nothing was cached for the revoked unit.
  final Map<String, int> rowsRemoved;

  /// How many outbox entries were present afterwards. Reported rather than assumed:
  /// this is the number the guarantee in D-048 §2 is about.
  final int outboxEntriesPreserved;

  final String? skippedReason;

  /// Expense documents deleted outright: every line they carried named a revoked unit,
  /// and nothing about them was still unsent.
  final Set<String> documentsRemoved;

  /// Shared documents that lost some lines and kept others, and were therefore
  /// downgraded from `complete` to `scoped` with their document total nulled.
  final Set<String> documentsDowngraded;

  /// Documents kept because they still carry the actor's own unsynced intent. Stamped
  /// `scope_revoked_at` and excluded from canonical financial reads (D-068).
  final Set<String> documentsRetainedForUnsyncedWork;

  /// Expense ids whose staged attachment bytes were reclaimed from disk after the
  /// transaction committed. Reported rather than assumed: file deletion is the one part
  /// of this that a database rollback could not have undone, so it happens last.
  final Set<String> stagingReclaimed;

  /// What was done to the database's physical storage after the purge committed, so a
  /// revoked figure is not left recoverable in a sidecar file. See
  /// [ScopeCachePurge.reclaimPhysicalStorage].
  final String? physicalReclaim;

  bool get didPurge => skippedReason == null && revokedUnits.isNotEmpty;
  int get totalRowsRemoved =>
      rowsRemoved.values.fold(0, (sum, count) => sum + count);

  @override
  String toString() => skippedReason != null
      ? 'ScopePurgeResult.skipped($skippedReason)'
      : 'ScopePurgeResult(${revokedUnits.length} units, $totalRowsRemoved rows, '
            '${documentsRemoved.length} documents removed, '
            '${documentsDowngraded.length} downgraded, '
            '${documentsRetainedForUnsyncedWork.length} retained for unsynced work, '
            '$outboxEntriesPreserved outbox entries preserved)';
}

/// Removes the app-private staged attachment bytes for one financial document.
///
/// Injected rather than imported so this file keeps no dependency on `dart:io` or on a
/// platform path resolver, and so a test can watch what would have been deleted without
/// putting real files anywhere. `AttachmentStagingService.discardDocument` is the
/// production implementation, and it takes an expense id or a revenue entry id
/// indifferently — both are UUIDs naming a staging sub-directory.
typedef StagingReclaimer = Future<void> Function(String documentId);

class ScopeCachePurge {
  const ScopeCachePurge(this.db, {this.reclaimStaging});

  final AppDatabase db;

  /// How to remove staged attachment bytes. Null in contexts that hold no files — a
  /// pure-database test — in which case the rows go and nothing is reclaimed.
  final StagingReclaimer? reclaimStaging;

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

    // Authority is confirmed, so this is also the moment to undo a retention that no
    // longer applies. A document kept only because it carried unsent work is invisible
    // to canonical browsing; if the unit it charges is back in scope, keeping it hidden
    // would be a second, silent revocation nobody decided (D-068).
    final restored =
        await _restoreBrowsability(refresh.snapshot) +
        await _restoreRevenueBrowsability(refresh.snapshot) +
        await _restoreOwnerLedgerBrowsability(refresh.snapshot);

    // OA-3 · the capability half, which a unit diff cannot see. `unitsRevokedSince` is
    // empty for an org-wide holder by construction, and a person can lose the owner domain
    // while keeping every property — so the owner caches are decided by what this confirmed
    // authority *holds*, not by which units it lost.
    final capabilityRemoved = await _purgeOnCapabilityLoss(refresh.snapshot);

    final revoked = refresh.snapshot.unitsRevokedSince(previous);
    if (revoked.isEmpty) {
      final removedCount = capabilityRemoved.values.fold(0, (a, b) => a + b);
      return ScopePurgeResult.skipped(
        [
          'no business unit was revoked',
          if (restored > 0)
            '$restored retained document(s) became browsable again under the '
                'confirmed scope',
          if (removedCount > 0)
            '$removedCount owner-domain row(s) removed because the confirmed '
                'authority no longer holds the capability that reads them',
        ].join('; '),
        rowsRemoved: capabilityRemoved,
      );
    }

    return purgeUnits(revoked, actorUserId: refresh.snapshot.userId);
  }

  /// Removes the owner-domain caches a confirmed authority may no longer read (OA-3).
  ///
  /// **State, not transition.** What this confirmed answer holds decides it, so the rule is
  /// idempotent and survives a device that was offline across the change: the next
  /// confirmed refresh finds the capability absent and acts, whatever the device last
  /// believed.
  ///
  /// Two caches, two capabilities, and neither covers the other:
  ///
  ///  * the **canonical owner cache** — the settlement's input, filled only under the
  ///    settlement transport's own gate — goes whole for this person unless they still
  ///    hold `owner_settlement.view` **and** `owner_ledger.view` **and** `reports.view`.
  ///    Nothing in it is anybody's unsent work, so there is no exception to make;
  ///  * the **OA-1 operational ledger** goes unless they still hold `owner_ledger.view`,
  ///    **sparing the actor's own unsent movements**, which are stamped and removed from
  ///    every canonical read exactly as a revoked unit's would be (D-070).
  ///
  /// Only ever reached through a confirmed authority: [applyTo] refuses everything else
  /// before this line, so a network failure cannot remove anything (D-048 section 1).
  Future<Map<String, int>> _purgeOnCapabilityLoss(
    AuthoritySnapshot snapshot,
  ) async {
    final principal = snapshot.principal;
    final removed = <String, int>{};

    final mayReadSettlement =
        principal.canAnywhere(Capability.ownerSettlementView) &&
        principal.canAnywhere(Capability.ownerLedgerView) &&
        principal.canAnywhere(Capability.reportsView);
    final mayReadLedger = principal.canAnywhere(Capability.ownerLedgerView);

    await db.transaction(() async {
      // D-231: in the same transaction as the purge, so a synchronisation started under the
      // previous authority cannot write after this commits.
      await CacheAuthorityGeneration(db).recordConfirmed(snapshot);
      final reportingUnits = await _reportingUnitsFor(snapshot.userId);
      final noLongerReportable = {
        for (final unit in reportingUnits)
          if (!principal.can(Capability.reportsView, businessUnitId: unit) ||
              !principal.can(Capability.revenueView, businessUnitId: unit) ||
              !principal.can(Capability.expenseViewAll, businessUnitId: unit))
            unit,
      };
      if (noLongerReportable.isNotEmpty) {
        await _purgeReportingCacheFor(
          snapshot.userId,
          noLongerReportable,
          removed,
        );
      }
      if (!mayReadSettlement) {
        await _purgeOwnerSettlementCacheFor(snapshot.userId, removed);
      }
      if (!mayReadLedger) {
        final everyUnit = {
          for (final row
              in await db
                  .customSelect(
                    'SELECT DISTINCT business_unit_id AS id FROM owner_ledger_entries',
                  )
                  .get())
            row.data['id'] as String,
        };
        if (everyUnit.isNotEmpty) await _purgeOwnerLedger(everyUnit, removed);
      }
    });
    return removed;
  }

  Future<Set<String>> _reportingUnitsFor(String ownerUserId) async => {
    for (final row
        in await db
            .customSelect(
              'SELECT business_unit_id AS id FROM reporting_coverage_markers '
              'WHERE owner_user_id = ? '
              'UNION SELECT business_unit_id AS id '
              'FROM reporting_revenue_contributions WHERE owner_user_id = ? '
              'UNION SELECT business_unit_id AS id '
              'FROM reporting_expense_contributions WHERE owner_user_id = ?',
              variables: [
                Variable<String>(ownerUserId),
                Variable<String>(ownerUserId),
                Variable<String>(ownerUserId),
              ],
            )
            .get())
      row.data['id'] as String,
  };

  /// One person's canonical owner cache, coverage first (D-171, D-074).
  Future<void> _purgeOwnerSettlementCacheFor(
    String ownerUserId,
    Map<String, int> removed,
  ) async {
    for (final table in const [
      'owner_settlement_coverage',
      'canonical_owner_movements',
      'canonical_ownership_shares',
      'canonical_owners',
    ]) {
      removed[table] = await db.customUpdate(
        'DELETE FROM $table WHERE owner_user_id = ?',
        variables: [Variable<String>(ownerUserId)],
        updates: const {},
      );
    }
  }

  /// The owner-ledger half of [_restoreBrowsability], on the identical rule — plus the
  /// capability, because a movement may have been stamped for the capability's loss as
  /// much as for a unit's (OA-3).
  ///
  /// Restored only to **the actor who queued it** (D-074), only inside the confirmed
  /// scope, and only while that actor may read the ledger at all.
  Future<int> _restoreOwnerLedgerBrowsability(
    AuthoritySnapshot snapshot,
  ) async {
    if (!snapshot.principal.canAnywhere(Capability.ownerLedgerView)) return 0;

    const ownedByThisActor =
        'EXISTS (SELECT 1 FROM sync_outbox o '
        "          WHERE o.entity_type = 'owner_ledger_entry' "
        '            AND o.entity_id = owner_ledger_entries.id '
        "            AND o.status <> 'done' AND o.actor_user_id = ?)";

    if (snapshot.holdsOrgWideGrant) {
      return db.customUpdate(
        'UPDATE owner_ledger_entries SET scope_revoked_at = NULL '
        'WHERE scope_revoked_at IS NOT NULL AND $ownedByThisActor',
        variables: [Variable<String>(snapshot.userId)],
        updates: const {},
      );
    }

    final units = snapshot.scopedUnits;
    if (units.isEmpty) return 0;
    return db.customUpdate(
      'UPDATE owner_ledger_entries SET scope_revoked_at = NULL '
      'WHERE scope_revoked_at IS NOT NULL AND $ownedByThisActor '
      '  AND business_unit_id IN ${_in(units)}',
      variables: [
        Variable<String>(snapshot.userId),
        for (final unit in units) Variable<String>(unit),
      ],
      updates: const {},
    );
  }

  /// Purges synced owner movements for [units], sparing movements that still carry unsent
  /// work — the revenue rule, applied to the table whose classification has said since
  /// OA-1 that it is purged this way, and which no code actually purged until OA-3.
  Future<Set<String>> _purgeOwnerLedger(
    Set<String> units,
    Map<String, int> removed,
  ) async {
    removed['owner_ledger_entries'] = 0;

    final touched = await _ids(
      'SELECT id FROM owner_ledger_entries WHERE business_unit_id IN ${_in(units)}',
      [for (final unit in units) Variable<String>(unit)],
    );
    if (touched.isEmpty) return const {};

    // Work this device has not delivered: kept, stamped, excluded from every canonical
    // read. It exists nowhere else (D-070).
    final retained = await _ids(
      'SELECT e.id AS id FROM owner_ledger_entries e WHERE e.id IN ${_in(touched)} '
      'AND (e.pending_mutation_id IS NOT NULL OR EXISTS ('
      '  SELECT 1 FROM sync_outbox o WHERE o.entity_type = ? '
      '  AND o.entity_id = e.id AND o.status <> ?))',
      [
        for (final id in touched) Variable<String>(id),
        Variable<String>('owner_ledger_entry'),
        Variable<String>(OutboxStatus.done.name),
      ],
    );

    if (retained.isNotEmpty) {
      await db.customUpdate(
        'UPDATE owner_ledger_entries SET scope_revoked_at = ? '
        'WHERE id IN ${_in(retained)} AND scope_revoked_at IS NULL',
        variables: [
          Variable<DateTime>(DateTime.now().toUtc()),
          for (final id in retained) Variable<String>(id),
        ],
        updates: const {},
      );
    }

    final purgeable = touched.difference(retained);
    if (purgeable.isNotEmpty) {
      removed['owner_ledger_entries'] = await _delete2(
        'DELETE FROM owner_ledger_entries WHERE id IN ${_in(purgeable)}',
        [for (final id in purgeable) Variable<String>(id)],
      );
    }
    return retained;
  }

  /// Clears `scope_revoked_at` on retained documents that belong to **this** actor and
  /// whose every line is inside [snapshot]'s scope again. Returns how many were freed.
  ///
  /// The scope test alone is not enough, and D-074 is what that cost. A retained document
  /// is somebody's *unsent work*, kept because it exists nowhere else (D-070). Restoring
  /// it on scope alone means the next person to sign in with overlapping scope has the
  /// previous user's retained documents un-hidden for them — which is exactly what the
  /// Windows acceptance found: an Owner signed out, twelve documents were correctly
  /// stamped and unbrowsable, a Crystal Canopy manager signed in, and every Crystal
  /// Canopy document was un-stamped again because *the units matched*.
  ///
  /// So ownership is part of the predicate. The link is the outbox, which has recorded
  /// who queued each intent since D-050: a document is restored only while this actor
  /// still has outstanding work on it. A document whose work has since completed stays
  /// stamped and is simply re-pulled from the server, which is where it came from.
  ///
  /// An org-wide holder covers every *unit* by construction (D-025) — it does not make
  /// them the author of somebody else's queued intent, so the ownership test applies to
  /// them too.
  Future<int> _restoreBrowsability(AuthoritySnapshot snapshot) async {
    const ownedByThisActor =
        'EXISTS (SELECT 1 FROM sync_outbox o '
        "          WHERE o.entity_type = 'expense' AND o.entity_id = expenses.id "
        "            AND o.status <> 'done' AND o.actor_user_id = ?)";

    if (snapshot.holdsOrgWideGrant) {
      return db.customUpdate(
        'UPDATE expenses SET scope_revoked_at = NULL '
        'WHERE scope_revoked_at IS NOT NULL AND $ownedByThisActor',
        variables: [Variable<String>(snapshot.userId)],
        updates: const {},
      );
    }

    final units = snapshot.scopedUnits;
    if (units.isEmpty) return 0;
    return db.customUpdate(
      'UPDATE expenses SET scope_revoked_at = NULL '
      'WHERE scope_revoked_at IS NOT NULL AND $ownedByThisActor '
      '  AND NOT EXISTS ('
      '    SELECT 1 FROM expense_allocations a '
      '     WHERE a.expense_id = expenses.id '
      '       AND a.business_unit_id NOT IN ${_in(units)})',
      variables: [
        Variable<String>(snapshot.userId),
        for (final unit in units) Variable<String>(unit),
      ],
      updates: const {},
    );
  }

  /// Stamps every remaining financial document as unbrowsable, without deleting any.
  ///
  /// The fail-closed path (D-074). If a purge cannot complete — a locked staging file, a
  /// database error, anything — the wrong outcome is to carry on with the previous user's
  /// figures still readable. This is the fallback: nothing is destroyed, and nothing is
  /// browsable, which is the safe half of both guarantees. A successful purge afterwards
  /// clears it in the ordinary way.
  /// The revenue half of [_restoreBrowsability], on the identical rule.
  ///
  /// A revenue entry names exactly one business unit on its header, so "every line is in
  /// scope again" is simply "this unit is in scope again" — but the **ownership**
  /// predicate is the same one and is not optional: holding a property does not make
  /// somebody the author of another person's queued intent (D-074).
  Future<int> _restoreRevenueBrowsability(AuthoritySnapshot snapshot) async {
    const ownedByThisActor =
        'EXISTS (SELECT 1 FROM sync_outbox o '
        "          WHERE o.entity_type = 'revenue_entry' "
        '            AND o.entity_id = revenue_entries.id '
        "            AND o.status <> 'done' AND o.actor_user_id = ?)";

    if (snapshot.holdsOrgWideGrant) {
      return db.customUpdate(
        'UPDATE revenue_entries SET scope_revoked_at = NULL '
        'WHERE scope_revoked_at IS NOT NULL AND $ownedByThisActor',
        variables: [Variable<String>(snapshot.userId)],
        updates: const {},
      );
    }

    final units = snapshot.scopedUnits;
    if (units.isEmpty) return 0;
    return db.customUpdate(
      'UPDATE revenue_entries SET scope_revoked_at = NULL '
      'WHERE scope_revoked_at IS NOT NULL AND $ownedByThisActor '
      '  AND business_unit_id IN ${_in(units)}',
      variables: [
        Variable<String>(snapshot.userId),
        for (final unit in units) Variable<String>(unit),
      ],
      updates: const {},
    );
  }

  /// Purges synced revenue for [units], sparing entries that still carry unsent work.
  ///
  /// Simpler than its expense counterpart in one respect and identical in every other: an
  /// entry belongs to exactly one business unit (spec §8), so there is no partially
  /// revoked document to downgrade — the arithmetic that makes a shared expense header
  /// dangerous has no analogue here. An entry is either in a revoked unit or it is not.
  Future<_RevenuePurge> _purgeRevenue(
    Set<String> units,
    Map<String, int> removed,
  ) async {
    removed['revenue_attachments'] = 0;
    removed['revenue_components'] = 0;
    removed['revenue_entries'] = 0;

    final touched = await _ids(
      'SELECT id FROM revenue_entries WHERE business_unit_id IN ${_in(units)}',
      [for (final unit in units) Variable<String>(unit)],
    );
    if (touched.isEmpty) return const _RevenuePurge.empty();

    // Work this device has not delivered. Kept, stamped, and excluded from every
    // canonical read — it exists nowhere else (D-070).
    final retained = await _ids(
      'SELECT e.id AS id FROM revenue_entries e WHERE e.id IN ${_in(touched)} '
      'AND (e.pending_mutation_id IS NOT NULL OR EXISTS ('
      '  SELECT 1 FROM sync_outbox o WHERE o.entity_type = ? '
      '  AND o.entity_id = e.id AND o.status <> ?))',
      [
        for (final id in touched) Variable<String>(id),
        Variable<String>('revenue_entry'),
        Variable<String>(OutboxStatus.done.name),
      ],
    );

    if (retained.isNotEmpty) {
      await db.customUpdate(
        'UPDATE revenue_entries SET scope_revoked_at = ? '
        'WHERE id IN ${_in(retained)} AND scope_revoked_at IS NULL',
        variables: [
          Variable<DateTime>(DateTime.now().toUtc()),
          for (final id in retained) Variable<String>(id),
        ],
        updates: const {},
      );
    }

    final purgeable = touched.difference(retained);
    if (purgeable.isEmpty) {
      return _RevenuePurge(retained: retained, stagingToReclaim: const {});
    }

    final vars = [for (final id in purgeable) Variable<String>(id)];
    // Evidence goes with the document it supports. A revenue entry is never partly
    // visible, so unlike a shared expense there is no downgrade to reason about: the
    // entry is either being removed or it is not, and its attachments follow it.
    removed['revenue_attachments'] = await _delete2(
      'DELETE FROM revenue_attachments WHERE revenue_entry_id IN ${_in(purgeable)}',
      vars,
    );
    removed['revenue_components'] = await _delete2(
      'DELETE FROM revenue_components WHERE revenue_entry_id IN ${_in(purgeable)}',
      vars,
    );
    removed['revenue_entries'] = await _delete2(
      'DELETE FROM revenue_entries WHERE id IN ${_in(purgeable)}',
      [for (final id in purgeable) Variable<String>(id)],
    );
    // The bytes are reclaimed after the transaction commits, never inside it: SQLite can
    // roll a delete back and the filesystem cannot put a JPEG back (D-070 section 3).
    return _RevenuePurge(retained: retained, stagingToReclaim: purgeable);
  }

  Future<int> quarantineAllDocuments() async {
    // The fail-closed sign-out path ends the session too, so nothing in flight lands.
    await CacheAuthorityGeneration(db).endSession();
    final now = DateTime.now().toUtc();
    var stamped = 0;
    for (final table in const [
      'expenses',
      'revenue_entries',
      // OA-3: the owner ledger is a financial table with the same stamp and the same
      // fail-closed obligation — a sign-out that could not purge must not leave the
      // previous person's owner movements browsable either (D-074).
      'owner_ledger_entries',
    ]) {
      stamped += await db.customUpdate(
        'UPDATE $table SET scope_revoked_at = ? WHERE scope_revoked_at IS NULL',
        variables: [Variable<DateTime>(now)],
        updates: const {},
      );
    }
    return stamped;
  }

  /// The canonical reporting cache for the revoked units (D-171).
  ///
  /// **Unconditional, and that is the difference from a financial document.** A synced
  /// expense may be retained because it still carries its actor's unsent intent, which
  /// exists nowhere else (D-070). Nothing in the reporting cache is like that: every row
  /// came from the server, none of it is anybody's attempt, and the server hands it all
  /// back the moment authority returns. So it goes, whole.
  ///
  /// The **marker first**. A coverage claim standing over rows that are about to be
  /// deleted is worse than no claim: it would tell `LocalReportingEngine` that a property
  /// is completely synchronised while its figures are being removed underneath, which is
  /// the one thing the marker exists to prevent.
  Future<void> _purgeReportingCache(
    Set<String> units,
    Map<String, int> removed,
  ) async {
    removed['reporting_coverage_markers'] = await _delete(
      'DELETE FROM reporting_coverage_markers WHERE business_unit_id IN '
      '${_in(units)}',
      units,
    );
    removed['reporting_revenue_contributions'] = await _delete(
      'DELETE FROM reporting_revenue_contributions WHERE business_unit_id IN '
      '${_in(units)}',
      units,
    );
    removed['reporting_expense_contributions'] = await _delete(
      'DELETE FROM reporting_expense_contributions WHERE business_unit_id IN '
      '${_in(units)}',
      units,
    );
  }

  /// One person's canonical reporting cache. Used for a confirmed authority change:
  /// another person's rows on a shared device are not evidence about this revocation.
  Future<void> _purgeReportingCacheFor(
    String ownerUserId,
    Set<String> units,
    Map<String, int> removed,
  ) async {
    for (final table in const [
      'reporting_coverage_markers',
      'reporting_revenue_contributions',
      'reporting_expense_contributions',
    ]) {
      final count = await db.customUpdate(
        'DELETE FROM $table WHERE owner_user_id = ? '
        'AND business_unit_id IN ${_in(units)}',
        variables: [
          Variable<String>(ownerUserId),
          for (final unit in units) Variable<String>(unit),
        ],
        updates: const {},
      );
      removed.update(table, (value) => value + count, ifAbsent: () => count);
    }
  }

  /// The canonical owner cache (OA-2), on the same terms and for the same reason.
  ///
  /// **Nothing here is anybody's unsent work**, unlike `owner_ledger_entries` beside it —
  /// every row is a server-owned fact the server hands straight back when authority
  /// returns. So there is no exception to make and it goes whole, which is the simpler
  /// half of D-070 rather than a weaker one.
  ///
  /// The **coverage row first**, and it is removed unconditionally rather than by unit: a
  /// claim of complete canonical owner history cannot survive the removal of part of that
  /// history, and an owner position spans every property by construction (D-196). Leaving
  /// it would tell a settlement the history is complete while it is being emptied
  /// underneath — precisely what the reporting marker ordering exists to prevent.
  ///
  /// The ownership shares and owner masters go with it: they carry no business unit, they
  /// are what an entitlement is computed *from*, and a device that has lost the ledger has
  /// no business retaining the ratio.
  Future<void> _purgeOwnerSettlementCache(
    Set<String> units,
    Map<String, int> removed,
  ) async {
    removed['owner_settlement_coverage'] = await _delete(
      'DELETE FROM owner_settlement_coverage',
      const {},
    );
    removed['canonical_owner_movements'] = await _delete(
      'DELETE FROM canonical_owner_movements WHERE business_unit_id IN '
      '${_in(units)}',
      units,
    );
    removed['canonical_ownership_shares'] = await _delete(
      'DELETE FROM canonical_ownership_shares',
      const {},
    );
    removed['canonical_owners'] = await _delete(
      'DELETE FROM canonical_owners',
      const {},
    );
  }

  /// The deletion itself, for a set of units already established as revoked.
  ///
  /// Separate from [applyTo] so it can be exercised directly, but deliberately not the
  /// documented entry point: everything in production reaches it through the confirmed
  /// authority above.
  /// [actorUserId] names whose completeness claim is being withdrawn.
  ///
  /// Supplied when the purge follows a confirmed authority answer, because that answer is
  /// about one person. Omitted on the unconditional local paths — sign-out and a user
  /// switch — where no user may keep claiming these units, and every claim goes (D-074).
  Future<ScopePurgeResult> purgeUnits(
    Set<String> units, {
    String? actorUserId,
  }) async {
    if (units.isEmpty) {
      return const ScopePurgeResult.skipped('no business unit was revoked');
    }

    final outboxBefore = await _outboxCount();
    final removed = <String, int>{};
    late _FinancialPurge financial;
    // Revenue entries kept because they still carry their actor's unsent work. Counted
    // separately from the expense figure so the result says how many of each survived
    // rather than blurring two different documents into one number.
    var revenue = const _RevenuePurge.empty();
    var ownerLedgerRetained = const <String>{};

    await db.transaction(() async {
      // D-231: a sign-out or user switch ends the session the caches belonged to, inside
      // the purge's transaction. A confirmed revocation has already recorded its own.
      if (actorUserId == null) await CacheAuthorityGeneration(db).endSession();
      // Financial documents first. They depend on nothing below them, and doing them
      // inside the same transaction is what makes "the revoked unit's figures are gone"
      // a single fact rather than two that could half-happen (D-068).
      financial = await _purgeFinancialDocuments(units, removed);
      revenue = await _purgeRevenue(units, removed);
      ownerLedgerRetained = await _purgeOwnerLedger(units, removed);
      await _purgeReportingCache(units, removed);
      await _purgeOwnerSettlementCache(units, removed);

      // Then reference data, bottom-up. Each step deletes only rows reachable from the
      // revoked units, and the order guarantees a parent is never removed before its
      // children.
      // The revenue reference caches, on the same predicate as the rules they qualify.
      // A component that used one keeps its own snapshot, so a retained entry stays
      // explainable after these rows are gone (D-070 §11).
      removed['revenue_value_bands'] = await _delete(
        'DELETE FROM revenue_value_bands WHERE revenue_category_id IN '
        '(SELECT id FROM revenue_categories WHERE business_unit_id IN ${_in(units)})',
        units,
      );
      removed['revenue_supply_subtypes'] = await _delete(
        'DELETE FROM revenue_supply_subtypes WHERE revenue_category_id IN '
        '(SELECT id FROM revenue_categories WHERE business_unit_id IN ${_in(units)})',
        units,
      );
      removed['business_unit_tax_statuses'] = await _delete(
        'DELETE FROM business_unit_tax_statuses '
        'WHERE business_unit_id IN ${_in(units)}',
        units,
      );
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

      // The revenue configuration completeness record is **downgraded, not deleted**.
      //
      // Deleting it would stop the device claiming authority, which is the security-
      // critical half and is not enough. A device with no row cannot tell a user who has
      // lost a property from one who never had it, and those are different sentences:
      // one is about their access, the other about this installation. Keeping the row at
      // `revoked` — with the datasets and generation cleared, so nothing can read it as
      // still-usable evidence — is what makes `configurationUnavailable` able to say
      // which (D-106, D-108).
      //
      // It is scoped to this actor. Another user's record on a shared workstation is
      // their own and says nothing about this authority answer (D-074).
      await db.customUpdate(
        "UPDATE revenue_config_snapshots SET status = 'revoked', datasets = '', "
        'generation = NULL, updated_at = ? '
        'WHERE business_unit_id IN ${_in(units)}'
        '${actorUserId == null ? '' : ' AND user_id = ?'}',
        variables: [
          Variable<String>(DateTime.now().toUtc().toIso8601String()),
          for (final unit in units) Variable<String>(unit),
          if (actorUserId != null) Variable<String>(actorUserId),
        ],
        updates: const {},
      );
    });

    // Only now, with the transaction committed, are the bytes on disk removed. A
    // rollback could not have put a deleted file back, so nothing is deleted until there
    // is nothing left to roll back. The reverse order would trade a recoverable database
    // state for an unrecoverable filesystem one.
    final reclaimed = <String>{};
    final reclaimer = reclaimStaging;
    if (reclaimer != null) {
      // Both document kinds, through the one reclaimer. A staging directory is named by
      // its document's UUID and nothing about the call knows or needs to know which kind
      // it was.
      for (final documentId in {
        ...financial.stagingToReclaim,
        ...revenue.stagingToReclaim,
      }) {
        await reclaimer(documentId);
        reclaimed.add(documentId);
      }
    }

    // The rows are gone and the bytes are gone; what is left is the physical storage
    // they occupied. See [reclaimPhysicalStorage] for why that is a separate step and
    // why it runs here and not a line earlier.
    final physicalReclaim = await reclaimPhysicalStorage();

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
      documentsRemoved: financial.removed,
      documentsDowngraded: financial.downgraded,
      documentsRetainedForUnsyncedWork: {
        ...financial.retained,
        ...revenue.retained,
        ...ownerLedgerRetained,
      },
      stagingReclaimed: reclaimed,
      physicalReclaim: physicalReclaim,
    );
  }

  /// Makes sure a revoked figure is not left recoverable in the database's *physical*
  /// storage once the purge has committed.
  ///
  /// Deleting a row is a logical operation, and this project has already been caught
  /// once by the difference: `PRAGMA secure_delete` had to be turned on because freed
  /// pages in the main file kept the revoked ₹25,000 legible, which made the purge
  /// weaker than the projection it protects (D-062, D-070). Secure delete handles the
  /// main file. It does **not** handle SQLite's sidecar files, because those are written
  /// by a different mechanism.
  ///
  /// Which sidecars exist depends on the journal mode:
  ///
  /// | Mode | Sidecars | What this does |
  /// |---|---|---|
  /// | `delete` (this project today) | a `-journal` during a write, removed at commit | nothing to do |
  /// | `wal` | `-wal` and `-shm`, holding committed frames until a checkpoint | truncating checkpoint |
  ///
  /// The mode is **read** rather than assumed, so this stays correct if the project ever
  /// moves to WAL for concurrency. A `-wal` file holds the old page images of everything
  /// recently written, so after a revocation it is exactly where the deleted figures
  /// would still be; `wal_checkpoint(TRUNCATE)` writes the frames back into the main
  /// file — where secure delete applies — and truncates the WAL to zero.
  ///
  /// **It runs after the transaction, never inside one.** A checkpoint cannot truncate a
  /// WAL that an open transaction is still reading, and a destructive checkpoint issued
  /// mid-transaction is at best a no-op and at worst a corruption risk. That ordering is
  /// the same reason staged files are reclaimed after the commit rather than during it.
  ///
  /// **On the cost.** A truncating checkpoint rewrites and re-creates the WAL, which is
  /// far more expensive than an ordinary delete. It is deliberately *not* on the path of
  /// every deletion — it happens only on a confirmed security revocation, which is rare
  /// and is the one moment where leaving a recoverable figure behind is the failure that
  /// matters.
  Future<String> reclaimPhysicalStorage() async {
    final mode = (await db.customSelect('PRAGMA journal_mode').getSingle())
        .data
        .values
        .first
        .toString()
        .toLowerCase();

    if (mode != 'wal') {
      return 'journal_mode=$mode — no write-ahead log to reclaim';
    }

    final result = await db
        .customSelect('PRAGMA wal_checkpoint(TRUNCATE)')
        .getSingle();
    return 'journal_mode=wal — truncating checkpoint: ${result.data}';
  }

  /// The financial half of a revocation (D-068).
  ///
  /// Four outcomes, decided per document, and each one is a different thing:
  ///
  /// | Document | Outcome |
  /// |---|---|
  /// | carries the actor's own unsynced intent | retained whole, stamped, unbrowsable |
  /// | every line named a revoked unit | deleted, staged bytes reclaimed |
  /// | some lines revoked, some kept | lines removed, header downgraded to `scoped` |
  /// | no line named a revoked unit | untouched |
  ///
  /// Runs inside the caller's transaction. Deletes explicitly at every level rather than
  /// leaning on `ON DELETE CASCADE`, so the counts it reports are counts of rows it
  /// actually removed and not an estimate of what SQLite did afterwards.
  Future<_FinancialPurge> _purgeFinancialDocuments(
    Set<String> units,
    Map<String, int> removed,
  ) async {
    removed['expense_period_allocations'] = 0;
    removed['expense_allocations'] = 0;
    removed['expense_attachments'] = 0;
    removed['expenses'] = 0;

    final touched = await _ids(
      'SELECT DISTINCT expense_id AS id FROM expense_allocations '
      'WHERE business_unit_id IN ${_in(units)}',
      [for (final unit in units) Variable<String>(unit)],
    );
    if (touched.isEmpty) return const _FinancialPurge.empty();

    // Work this device has not managed to deliver. `pending_mutation_id` alone is enough
    // even when the outbox row has vanished: the repository already treats that state as
    // pending rather than quietly calling it synced, and a purge is not the place to
    // start resolving the ambiguity in the destructive direction.
    final retained = await _ids(
      'SELECT DISTINCT e.id AS id FROM expenses e WHERE e.id IN ${_in(touched)} '
      'AND (e.pending_mutation_id IS NOT NULL OR EXISTS ('
      '  SELECT 1 FROM sync_outbox o WHERE o.entity_type = ? '
      '  AND o.entity_id = e.id AND o.status <> ?))',
      [
        for (final id in touched) Variable<String>(id),
        Variable<String>('expense'),
        Variable<String>(OutboxStatus.done.name),
      ],
    );

    if (retained.isNotEmpty) {
      await db.customUpdate(
        'UPDATE expenses SET scope_revoked_at = ? '
        'WHERE id IN ${_in(retained)} AND scope_revoked_at IS NULL',
        variables: [
          Variable<DateTime>(DateTime.now().toUtc()),
          for (final id in retained) Variable<String>(id),
        ],
        updates: const {},
      );
    }

    final purgeable = touched.difference(retained);
    if (purgeable.isEmpty) {
      return _FinancialPurge(
        removed: const {},
        downgraded: const {},
        retained: retained,
        stagingToReclaim: const {},
      );
    }

    final purgeVars = [for (final id in purgeable) Variable<String>(id)];
    final unitVars = [for (final unit in units) Variable<String>(unit)];

    // Contributions go by their line rather than by their own `business_unit_id`. The
    // two always agree, and deleting through the relationship means they go on agreeing
    // even if one of them is ever wrong.
    removed['expense_period_allocations'] = await _delete2(
      'DELETE FROM expense_period_allocations WHERE allocation_id IN ('
      '  SELECT id FROM expense_allocations '
      '  WHERE expense_id IN ${_in(purgeable)} '
      '    AND business_unit_id IN ${_in(units)})',
      [...purgeVars, ...unitVars],
    );
    removed['expense_allocations'] = await _delete2(
      'DELETE FROM expense_allocations WHERE expense_id IN ${_in(purgeable)} '
      'AND business_unit_id IN ${_in(units)}',
      [...purgeVars, ...unitVars],
    );

    // What is left of each document decides its fate.
    final orphaned = await _ids(
      'SELECT id FROM expenses WHERE id IN ${_in(purgeable)} AND NOT EXISTS ('
      '  SELECT 1 FROM expense_allocations a WHERE a.expense_id = expenses.id)',
      purgeVars,
    );
    final downgraded = purgeable.difference(orphaned);

    // Every affected document loses its attachments either way: an orphaned one is
    // going, and a downgraded one is no longer a complete document, which is the exact
    // predicate D-063 gates the original bill on.
    final losingAttachments = {...orphaned, ...downgraded};
    removed['expense_attachments'] = await _delete2(
      'DELETE FROM expense_attachments WHERE expense_id IN '
      '${_in(losingAttachments)}',
      [for (final id in losingAttachments) Variable<String>(id)],
    );

    if (downgraded.isNotEmpty) {
      // One statement, because the check constraint is evaluated per row at the end of
      // it: `visibility = 'scoped'` and a non-null `document_total_minor` cannot both be
      // true, so setting them in two statements would fail on the first.
      await db.customUpdate(
        "UPDATE expenses SET visibility = 'scoped', document_total_minor = NULL, "
        'visible_amount_minor = ('
        '  SELECT SUM(a.amount_minor) FROM expense_allocations a '
        '  WHERE a.expense_id = expenses.id) '
        'WHERE id IN ${_in(downgraded)}',
        variables: [for (final id in downgraded) Variable<String>(id)],
        updates: const {},
      );
    }

    if (orphaned.isNotEmpty) {
      removed['expenses'] = await _delete2(
        'DELETE FROM expenses WHERE id IN ${_in(orphaned)}',
        [for (final id in orphaned) Variable<String>(id)],
      );
    }

    return _FinancialPurge(
      removed: orphaned,
      downgraded: downgraded,
      retained: retained,
      stagingToReclaim: losingAttachments,
    );
  }

  Future<Set<String>> _ids(String sql, List<Variable<Object>> variables) async {
    final rows = await db.customSelect(sql, variables: variables).get();
    return {for (final row in rows) row.data['id'] as String};
  }

  Future<int> _delete2(String sql, List<Variable<Object>> variables) =>
      db.customUpdate(sql, variables: variables, updates: const {});

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
      // No unit is cached, so there is nothing unit-scoped to remove — but the canonical
      // owner cache carries no unit on three of its four tables, and "no business unit
      // cached" is not a reason to leave the previous person's owners, ownership ratio
      // and start date on a shared machine (OA-3, D-208). Removed for every person, as a
      // user switch removes every unit.
      final removed = <String, int>{};
      await db.transaction(() async {
        await CacheAuthorityGeneration(db).endSession();
        await _purgeOwnerSettlementCache(const {}, removed);
      });
      return ScopePurgeResult.skipped(
        'no scoped reference data was cached; the canonical owner cache was removed',
        rowsRemoved: removed,
      );
    }
    return purgeUnits(units);
  }

  /// Every unit this installation holds anything for — not only the cached masters.
  ///
  /// A user switch has to reach a financial row whose unit master has already gone, or it
  /// would leave exactly that row behind. The owner tables are read as well as
  /// `business_units` for that reason (OA-3).
  Future<Set<String>> _allCachedUnitIds() async {
    final rows = await db
        .customSelect(
          'SELECT id FROM business_units '
          'UNION SELECT business_unit_id FROM reporting_coverage_markers '
          'UNION SELECT business_unit_id FROM reporting_revenue_contributions '
          'UNION SELECT business_unit_id FROM reporting_expense_contributions '
          'UNION SELECT business_unit_id FROM owner_ledger_entries '
          'UNION SELECT business_unit_id FROM canonical_owner_movements',
        )
        .get();
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

/// What the financial half of one purge decided, per document.
final class _FinancialPurge {
  const _FinancialPurge({
    required this.removed,
    required this.downgraded,
    required this.retained,
    required this.stagingToReclaim,
  });

  const _FinancialPurge.empty()
    : removed = const {},
      downgraded = const {},
      retained = const {},
      stagingToReclaim = const {};

  final Set<String> removed;
  final Set<String> downgraded;
  final Set<String> retained;

  /// Documents whose staged attachment bytes must go once the transaction commits.
  final Set<String> stagingToReclaim;
}

/// What the revenue half of one purge decided.
///
/// Simpler than [_FinancialPurge] by exactly one field: an entry names a single business
/// unit (spec section 8), so there is no partially revoked document to downgrade and
/// therefore no `downgraded` set to carry.
final class _RevenuePurge {
  const _RevenuePurge({required this.retained, required this.stagingToReclaim});

  const _RevenuePurge.empty()
    : retained = const {},
      stagingToReclaim = const {};

  /// Entries kept because their actor still has unsent work on them (D-070, D-074).
  /// Their evidence is kept with them: a staged file exists nowhere else.
  final Set<String> retained;

  /// Entries whose staged attachment bytes must go once the transaction commits.
  final Set<String> stagingToReclaim;
}
