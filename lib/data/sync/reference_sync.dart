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
import 'package:krishna_mis/data/remote/authority_gateway.dart';
import 'package:krishna_mis/data/remote/master_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/sync/scope_cache_purge.dart';
import 'package:krishna_mis/domain/auth/authority.dart';

/// What one synchronisation run did.
final class ReferenceSyncReport {
  const ReferenceSyncReport({
    required this.authority,
    this.purge,
    this.rowsWritten = 0,
    this.pullFailure,
  });

  final AuthorityRefresh authority;
  final ScopePurgeResult? purge;
  final int rowsWritten;
  final RemoteFailure? pullFailure;

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
  final AuthorityGateway authorityGateway;
  final MasterGateway masterGateway;
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

    final written = await _replaceLocally(pull.value);
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
  Future<int> _replaceLocally(ReferenceSnapshot snapshot) async {
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

      await upsert('revenue_tax_rates', snapshot.taxRules, const {
        'id': 'id',
        'org_id': 'org_id',
        'revenue_category_id': 'revenue_category_id',
        'rate_basis_points': 'rate_bp',
        'treatment': 'treatment',
        'effective_from': 'effective_from',
        'effective_to': 'effective_to',
        'note': 'note',
        'archived_at': 'archived_at',
        'created_by': 'created_by',
        'created_at': 'created_at',
        'row_version': 'row_version',
        'updated_at': 'updated_at',
      });
    });

    return written;
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
