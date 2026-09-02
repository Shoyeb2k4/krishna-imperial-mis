/// Bringing this device's copy of the server's reference data up to date.
///
/// The order is the design, and it is not interchangeable:
///
///   1. **ask the server who this user is now** — nothing else happens until it answers;
///   2. **purge** any unit it no longer covers (D-048), on that confirmed answer alone;
///   3. **pull** what the server is willing to return;
///   4. **write it in one transaction**, so the local hierarchy is never half-replaced;
///   5. **remember** the confirmed scope, so the next run can tell what changed.
///
/// Step 1 gating steps 2–5 is what makes a lost connection harmless: the run simply
/// stops, the cache stays exactly as it was, and it is reported as stale rather than
/// wrong. Screens keep reading from Drift throughout — this class updates the read model,
/// it is never on the path between a screen and what it renders.
library;

import 'package:krishna_mis/app/session/session_controller.dart';

import 'package:drift/drift.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/authority_store.dart';
import 'package:krishna_mis/data/remote/master_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/repositories/revenue_tax_repository.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';

/// What one synchronisation run did.
final class ReferenceSyncReport {
  const ReferenceSyncReport({
    required this.authority,
    this.purge,
    this.rowsWritten = 0,
    this.pullFailure,
    this.rejectedSnapshotReason,
  });

  final AuthorityRefresh authority;
  final ScopePurgeResult? purge;
  final int rowsWritten;
  final RemoteFailure? pullFailure;

  /// Set when an authoritative payload arrived and was refused as unusable (B18).
  ///
  /// Distinct from [pullFailure], which means the data did not arrive at all. Both leave
  /// the previous snapshot in place; only one of them is a statement about the server's
  /// configuration, and a diagnostics screen should not conflate them.
  final String? rejectedSnapshotReason;

  bool get authorityConfirmed => authority.establishesAuthority;
  bool get didPull =>
      rowsWritten > 0 || (authorityConfirmed && pullFailure == null);

  /// How fresh the data on screen now is — the same three-way distinction the reporting
  /// layer makes about figures, applied to permissions and reference data.
  AuthorityFreshness get freshness => authorityConfirmed
      ? AuthorityFreshness.confirmed
      : AuthorityFreshness.stale;

  @override
  String toString() =>
      'ReferenceSyncReport(${authority.runtimeType}, '
      'purge: ${purge?.totalRowsRemoved ?? 0}, written: $rowsWritten)';
}

class ReferenceSync implements ReferenceSynchroniser {
  ReferenceSync({
    required this.db,
    required this.authorityGateway,
    required this.masterGateway,
    AuthorityStore? authorityStore,
    ScopeCachePurge? purge,
  }) : _purge = purge ?? ScopeCachePurge(db),
       _store = authorityStore ?? AuthorityStore(db);

  final AppDatabase db;
  final AuthoritySource authorityGateway;
  final ReferencePuller masterGateway;
  final ScopeCachePurge _purge;
  final AuthorityStore _store;

  /// One full synchronisation pass.
  @override
  Future<ReferenceSyncReport> synchronise() async {
    final refresh = await authorityGateway.refresh();

    // Everything below this line requires a positive answer. Without one the cache is
    // kept and labelled stale — never touched, never second-guessed (D-048 §1).
    if (refresh is! AuthorityConfirmed) {
      return ReferenceSyncReport(authority: refresh);
    }

    final previous = await _store.loadFor(refresh.snapshot.userId);
    final purgeResult = await _purge.applyTo(refresh, previous: previous);

    final pull = await masterGateway.pullAll();
    if (pull is! RemoteOk<ReferenceSnapshot>) {
      // Authority was established and any revocation has already been honoured, but the
      // data itself did not arrive. The confirmed scope is still recorded: it is true,
      // and forgetting it would make the next run re-purge from a stale baseline.
      await _store.save(refresh.snapshot);
      return ReferenceSyncReport(
        authority: refresh,
        purge: purgeResult,
        pullFailure: pull.failureOrNull ?? RemoteFailure.serverUnreachable,
      );
    }

    // Fail closed before the write, not during it (B18).
    //
    // The server prevents ambiguous and incomplete configuration, and the client still
    // checks: a payload that cannot satisfy the domain's own invariants must not replace
    // a snapshot that could. Replacing good configuration with unusable configuration is
    // strictly worse than keeping yesterday's, because the device would then confidently
    // refuse every revenue entry while claiming to be synchronised.
    //
    // Nothing is repaired. A malformed authoritative payload is a server problem and
    // guessing at it on-device would be inventing a tax fact (D-043).
    final invalid = _rejectionReasonFor(pull.value);
    if (invalid != null) {
      await _store.save(refresh.snapshot);
      return ReferenceSyncReport(
        authority: refresh,
        purge: purgeResult,
        pullFailure: RemoteFailure.serverUnreachable,
        rejectedSnapshotReason: invalid,
      );
    }

    final written = await _replaceLocally(pull.value, refresh);
    await _store.save(refresh.snapshot);

    return ReferenceSyncReport(
      authority: refresh,
      purge: purgeResult,
      rowsWritten: written,
    );
  }

  /// Writes the server's answer into the local read model, in one transaction.
  ///
  /// Upsert by primary key rather than delete-and-reinsert: the ids are stable and
  /// server-owned, so an upsert converges on canonical state without ever leaving a
  /// window in which the hierarchy is empty. Rows the server no longer returns for a
  /// *revoked* unit are already gone, removed by the purge above.
  Future<int> _replaceLocally(
    ReferenceSnapshot snapshot,
    AuthorityConfirmed refresh,
  ) async {
    var written = 0;
    final now = DateTime.now().toUtc();

    await db.transaction(() async {
      Future<void> upsert(
        String table,
        List<Map<String, dynamic>> rows,
        Map<String, String> columns,
      ) async {
        for (final row in rows) {
          final names = columns.keys.toList();
          final placeholders = List.filled(names.length, '?').join(', ');
          final assignments = names
              .where((c) => c != 'id')
              .map((c) => '$c = excluded.$c')
              .join(', ');
          await db.customInsert(
            'INSERT INTO $table (${names.join(', ')}) VALUES ($placeholders) '
            'ON CONFLICT(id) DO UPDATE SET $assignments',
            variables: [
              for (final name in names)
                Variable<Object>(_value(row, columns[name]!, now)),
            ],
          );
          written++;
        }
      }

      await upsert('business_units', snapshot.businessUnits, const {
        'id': 'id',
        'org_id': 'org_id',
        'code': 'code',
        'name': 'name',
        'kind': 'kind',
        'timezone': 'timezone',
        'business_day_cutoff': 'business_day_cutoff',
        'sort_order': 'sort_order',
        'archived_at': 'archived_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });

      await upsert('departments', snapshot.departments, const {
        'id': 'id',
        'org_id': 'org_id',
        'business_unit_id': 'business_unit_id',
        'code': 'code',
        'name': 'name',
        'sort_order': 'sort_order',
        'archived_at': 'archived_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });

      await upsert('sections', snapshot.sections, const {
        'id': 'id',
        'org_id': 'org_id',
        'department_id': 'department_id',
        'code': 'code',
        'name': 'name',
        'sort_order': 'sort_order',
        'archived_at': 'archived_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });

      await upsert('expense_categories', snapshot.expenseCategories, const {
        'id': 'id',
        'org_id': 'org_id',
        'section_id': 'section_id',
        'code': 'code',
        'name': 'name',
        'nature': 'nature',
        'is_shared_by_default': 'is_shared_by_default',
        'sort_order': 'sort_order',
        'archived_at': 'archived_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });

      await upsert('revenue_categories', snapshot.revenueCategories, const {
        'id': 'id',
        'org_id': 'org_id',
        'business_unit_id': 'business_unit_id',
        'code': 'code',
        'name': 'name',
        'sort_order': 'sort_order',
        'archived_at': 'archived_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });

      await upsert('payment_methods', snapshot.paymentMethods, const {
        'id': 'id',
        'org_id': 'org_id',
        'code': 'code',
        'name': 'name',
        'requires_reference': 'requires_reference',
        'sort_order': 'sort_order',
        'archived_at': 'archived_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });

      await upsert('vendors', snapshot.vendors, const {
        'id': 'id',
        'org_id': 'org_id',
        'code': 'code',
        'name': 'name',
        'gstin': 'gstin',
        'phone': 'phone',
        'address': 'address',
        'notes': 'notes',
        'default_business_unit_id': 'default_business_unit_id',
        'default_category_id': 'default_category_id',
        'sort_order': 'sort_order',
        'archived_at': 'archived_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });

      // The four v1.2 columns were absent here until Slice 6, and their absence was a
      // defect rather than an omission: Slice 4 made `input_basis` NOT NULL on the
      // server, so every rule that exists carries one, and a sync that dropped it wrote a
      // rule the resolver classifies as `incompleteRule` — refusing every revenue entry
      // on a device whose configuration had in fact arrived intact. Nothing would have
      // reported a sync failure, because none occurred.
      await upsert('revenue_tax_rates', snapshot.taxRules, const {
        'id': 'id',
        'org_id': 'org_id',
        'revenue_category_id': 'revenue_category_id',
        'rate_basis_points': 'rate_bp',
        'treatment': 'treatment',
        'effective_from': 'effective_from',
        'effective_to': 'effective_to',
        'input_basis': 'input_basis',
        'value_band_id': 'value_band_id',
        'supply_subtype_id': 'supply_subtype_id',
        'premises_status_code': 'premises_status_code',
        'note': 'note',
        'archived_at': 'archived_at',
        'created_by': 'created_by',
        'created_at': 'created_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });

      // Bands are write-once on the server (D-100) and must stay write-once here. An
      // upsert converges on the server's row for a band's own id, and supersession
      // arrives as a *second* band plus a pointer — never as an edit to the first one's
      // bounds, which would retroactively redefine what every rule referencing it applied
      // to, for dates already recorded.
      await upsert('revenue_value_bands', snapshot.valueBands, const {
        'id': 'id',
        'org_id': 'org_id',
        'revenue_category_id': 'revenue_category_id',
        'code': 'code',
        'label': 'label',
        'floor_minor': 'floor_minor',
        'ceiling_minor': 'ceiling_minor',
        'superseded_by_band_id': 'superseded_by_band_id',
        'archived_at': 'archived_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });

      await upsert('revenue_supply_subtypes', snapshot.supplySubtypes, const {
        'id': 'id',
        'org_id': 'org_id',
        'revenue_category_id': 'revenue_category_id',
        'code': 'code',
        'label': 'label',
        'archived_at': 'archived_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });

      await upsert(
        'business_unit_tax_statuses',
        snapshot.premisesStatuses,
        const {
          'id': 'id',
          'org_id': 'org_id',
          'business_unit_id': 'business_unit_id',
          'effective_from': 'effective_from',
          'effective_to': 'effective_to',
          'status_code': 'status_code',
          'note': 'note',
          'archived_at': 'archived_at',
          'row_version': 'row_version',
          'updated_at': 'updated_at',
        },
      );

      // Rows the server no longer returns for a unit this user still holds are gone from
      // the authoritative dataset and must go from the cache too, or a deleted band would
      // remain selectable for ever. Confined to the units this snapshot actually covers,
      // so a scope the server did not answer for is left exactly as it was.
      await _removeAbsent(snapshot);

      // The completeness marker is written LAST, inside the same transaction. Everything
      // above must have succeeded for control to reach here, and a failure anywhere rolls
      // the whole thing back — including this claim. That ordering is the whole of B4:
      // a device may not say "synchronised" because the first request of four worked.
      await _markComplete(snapshot, refresh);
    });

    return written;
  }

  /// Why this snapshot must not be committed, or null if it may be.
  ///
  /// Deliberately narrow. It asserts the things whose absence would make the local
  /// configuration *unusable or misleading*, and nothing else — the server owns the
  /// business rules, and a client that second-guessed them would eventually refuse
  /// legitimate configuration it simply did not understand.
  String? _rejectionReasonFor(ReferenceSnapshot snapshot) {
    for (final rule in snapshot.taxRules) {
      final id = rule['id'];

      // A rule with no basis cannot say which amount an operator typed, so every entry
      // against it refuses. The server has refused to create one since A1; a payload
      // carrying one means something upstream is wrong, and the right answer is to keep
      // the snapshot that works.
      final basis = rule['input_basis'];
      if (basis == null || (basis is String && basis.isEmpty)) {
        return 'tax rule $id carries no input basis';
      }
      if (basis is! String || !_knownBases.contains(basis)) {
        return 'tax rule $id carries an unrecognised input basis';
      }
      if (rule['treatment'] is! String ||
          !_knownTreatments.contains(rule['treatment'])) {
        return 'tax rule $id carries an unrecognised tax treatment';
      }
      if (rule['rate_bp'] is! int || (rule['rate_bp'] as int) < 0) {
        return 'tax rule $id carries no usable rate';
      }
      if (rule['effective_from'] is! String) {
        return 'tax rule $id carries no effective date';
      }

      // A discriminator naming a band the snapshot does not contain is unresolvable: the
      // resolver would report `missingFact` and the operator would be asked to choose
      // something that does not exist here.
      final band = rule['value_band_id'];
      if (band != null && !snapshot.valueBands.any((b) => b['id'] == band)) {
        return 'tax rule $id names value band $band, which is not in this snapshot';
      }
      final subtype = rule['supply_subtype_id'];
      if (subtype != null &&
          !snapshot.supplySubtypes.any((t) => t['id'] == subtype)) {
        return 'tax rule $id names supply subtype $subtype, which is not in this snapshot';
      }
    }

    // A band with neither bound is a label pretending to be a discriminator — the same
    // thing the server's own check constraint refuses (D-100).
    for (final band in snapshot.valueBands) {
      if (band['floor_minor'] == null && band['ceiling_minor'] == null) {
        return 'value band ${band['id']} describes no range';
      }
    }

    return null;
  }

  static const _knownBases = {'inclusive_total', 'pre_tax'};
  static const _knownTreatments = {'inclusive', 'exclusive', 'none'};

  static String _placeholders(Set<String> values) =>
      '(${values.isEmpty ? "''" : List.filled(values.length, '?').join(', ')})';

  /// Removes cached configuration rows the authoritative snapshot no longer contains.
  ///
  /// Confined to the categories and units this snapshot actually covers. A unit the
  /// server did not answer for is not evidence of anything — the run simply did not ask
  /// about it — and deleting on that basis would be the `unknown ≠ revoked` mistake with
  /// a different trigger (D-048 §1).
  ///
  /// Financial explainability is untouched by any of this: a recorded component carries
  /// its own rate, treatment, basis and band snapshot and consults no reference row, so a
  /// band deleted here still explains the entries that named it (D-070 §11).
  Future<void> _removeAbsent(ReferenceSnapshot snapshot) async {
    final categories = {
      for (final c in snapshot.revenueCategories) c['id'] as String,
    };
    final units = snapshot.unitIds;
    if (categories.isEmpty && units.isEmpty) return;

    Future<void> prune(
      String table,
      String scopeColumn,
      Set<String> keep,
    ) async {
      if (keep.isEmpty) return;
      final kept = snapshot
          .rowsFor(table)
          .map((r) => r['id'] as String)
          .toSet();
      final scope = List.filled(keep.length, '?').join(', ');
      final ids = kept.isEmpty ? '' : List.filled(kept.length, '?').join(', ');
      await db.customUpdate(
        'DELETE FROM $table WHERE $scopeColumn IN ($scope)'
        '${kept.isEmpty ? '' : ' AND id NOT IN ($ids)'}',
        variables: [
          for (final v in keep) Variable<String>(v),
          for (final v in kept) Variable<String>(v),
        ],
        updates: const {},
      );
    }

    await prune('revenue_tax_rates', 'revenue_category_id', categories);
    await prune('revenue_value_bands', 'revenue_category_id', categories);
    await prune('revenue_supply_subtypes', 'revenue_category_id', categories);
    await prune('business_unit_tax_statuses', 'business_unit_id', units);
  }

  /// Records, per business unit, that the whole required configuration arrived.
  ///
  /// Per unit and per user because that is the granularity at which the claim is true.
  /// A single organisation-wide flag would let a Crystal Canopy sync vouch for Hotel
  /// Krishna, and one person's sync vouch for the next person on a shared workstation —
  /// neither of which this device has any evidence for (D-108).
  ///
  /// The confirmed time is the **server's**, taken from the authority answer. The device
  /// clock is recorded beside it and decides nothing (spec §9).
  Future<void> _markComplete(
    ReferenceSnapshot snapshot,
    AuthorityConfirmed refresh,
  ) async {
    // Withdraw any claim this user holds for a unit the server did not return.
    //
    // `pullAll` asks for everything and RLS decides what that means, so the units in a
    // confirmed snapshot **are** this user's current scope — including for an org-wide
    // holder, whose `scopedUnits` is empty by construction (D-025). A completeness record
    // naming a unit outside it is stale, and stale is not something a device may keep
    // resolving new revenue against.
    //
    // This does not duplicate the purge, and it catches a case the purge cannot: the
    // purge compares against the *previously stored* authority, which
    // `AuthorityStore.loadFor` correctly returns nothing for when somebody else used this
    // installation in between (D-051 §9). With no previous snapshot there is no diff and
    // no revoked set — yet the claim is still stale. The confirmed answer needs no diff.
    await db.customUpdate(
      "UPDATE revenue_config_snapshots SET status = 'revoked', datasets = '', "
      'generation = NULL, updated_at = ? '
      'WHERE user_id = ? AND business_unit_id NOT IN ${_placeholders(snapshot.unitIds)}',
      variables: [
        Variable<String>(DateTime.now().toUtc().toIso8601String()),
        Variable<String>(refresh.snapshot.userId),
        for (final unit in snapshot.unitIds) Variable<String>(unit),
      ],
      updates: const {},
    );

    final datasets = RevenueConfigDataset.encode(RevenueConfigDataset.all);
    final generation = snapshot.generation;
    final now = DateTime.now().toUtc().toIso8601String();

    for (final unitId in snapshot.unitIds) {
      await db.customInsert(
        'INSERT INTO revenue_config_snapshots '
        '(user_id, org_id, business_unit_id, status, datasets, generation, '
        ' confirmed_at, updated_at) '
        "VALUES (?, ?, ?, 'complete', ?, ?, ?, ?) "
        'ON CONFLICT(user_id, business_unit_id) DO UPDATE SET '
        'status = excluded.status, datasets = excluded.datasets, '
        'generation = excluded.generation, confirmed_at = excluded.confirmed_at, '
        'updated_at = excluded.updated_at',
        variables: [
          Variable<String>(refresh.snapshot.userId),
          Variable<String>(refresh.snapshot.orgId),
          Variable<String>(unitId),
          Variable<String>(datasets),
          Variable<Object>(generation ?? ''),
          Variable<String>(refresh.snapshot.resolvedAt.toIso8601String()),
          Variable<String>(now),
        ],
      );
    }
  }

  /// Local columns are typed by Drift; the server hands back JSON. Booleans and
  /// timestamps are the two that do not survive the trip unassisted.
  Object? _value(Map<String, dynamic> row, String remoteColumn, DateTime now) {
    final value = row[remoteColumn];
    if (value is bool) return value ? 1 : 0;
    if (remoteColumn == 'updated_at' && value == null) {
      return now.toIso8601String();
    }
    return value;
  }
}
