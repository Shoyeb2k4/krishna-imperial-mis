/// Reading and changing master data on the server.
///
/// Two halves, deliberately not merged: a **pull** that fetches whatever RLS is willing
/// to return for this user, and **mutations** that go through the `SECURITY DEFINER`
/// RPCs. Nothing here writes to a table directly, because no client holds a grant to —
/// the refusal that would come back is itself part of the design.
///
/// The pull asks for no filter of its own. It does not need one: the policies already
/// return exactly the rows this user may see, so a client-side `where` on business unit
/// would be duplicated logic that could only ever disagree with the server. What comes
/// back *is* the scope.
library;

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/supabase_gateway.dart';

/// Server-owned reference data as one consistent read.
final class ReferenceSnapshot {
  const ReferenceSnapshot({
    required this.businessUnits,
    required this.departments,
    required this.sections,
    required this.expenseCategories,
    required this.revenueCategories,
    required this.paymentMethods,
    required this.vendors,
    required this.taxRules,
    required this.fetchedAt,
  });

  final List<Map<String, dynamic>> businessUnits;
  final List<Map<String, dynamic>> departments;
  final List<Map<String, dynamic>> sections;
  final List<Map<String, dynamic>> expenseCategories;
  final List<Map<String, dynamic>> revenueCategories;
  final List<Map<String, dynamic>> paymentMethods;
  final List<Map<String, dynamic>> vendors;
  final List<Map<String, dynamic>> taxRules;
  final DateTime fetchedAt;

  /// The units this snapshot actually contains — which is to say, the units the server
  /// was willing to return. Used to confirm the pull agrees with the authority that
  /// triggered it.
  Set<String> get unitIds => {
    for (final unit in businessUnits) unit['id'] as String,
  };

  int get totalRows =>
      businessUnits.length +
      departments.length +
      sections.length +
      expenseCategories.length +
      revenueCategories.length +
      paymentMethods.length +
      vendors.length +
      taxRules.length;
}

class MasterGateway extends SupabaseGateway {
  const MasterGateway(super.client);

  /// Everything this user may see, in one pass.
  ///
  /// Phase 2 reference data is small — two properties, a few dozen categories — so a
  /// full pull is both simpler and more obviously correct than an incremental cursor,
  /// and it cannot drift out of step the way a watermark can. `change_seq` is already on
  /// every row for when volume justifies incremental sync; building that machinery now,
  /// before there is any evidence it is needed, would be the wrong trade.
  Future<RemoteOutcome<ReferenceSnapshot>> pullAll() => guard(() async {
    Future<List<Map<String, dynamic>>> rows(String table) async =>
        (await client.from(table).select()).cast<Map<String, dynamic>>();

    // Sequential rather than concurrent: a handful of small requests, and an ordered
    // pull is far easier to reason about when one of them fails.
    final businessUnits = await rows('business_units');
    final departments = await rows('departments');
    final sections = await rows('sections');
    final expenseCategories = await rows('expense_categories');
    final revenueCategories = await rows('revenue_categories');
    final paymentMethods = await rows('payment_methods');
    final vendors = await rows('vendors');
    final taxRules = await rows('revenue_tax_rates');

    return ReferenceSnapshot(
      businessUnits: businessUnits,
      departments: departments,
      sections: sections,
      expenseCategories: expenseCategories,
      revenueCategories: revenueCategories,
      paymentMethods: paymentMethods,
      vendors: vendors,
      taxRules: taxRules,
      fetchedAt: DateTime.now().toUtc(),
    );
  });

  // ── Mutations ─────────────────────────────────────────────────────────────
  // Each carries the mutation id it was queued with, so a redelivery replays rather than
  // reapplies, and the base row version it was based on, so a stale intent conflicts.
  // The two are separate arguments because they answer separate questions (D-021).

  Future<RemoteOutcome<Map<String, dynamic>>> create({
    required String entityType,
    required String? parentId,
    required String code,
    required String name,
    Map<String, dynamic> attributes = const {},
    String? mutationId,
    String? id,
  }) => _rpc('master_create', {
    'p_entity_type': entityType,
    'p_parent_id': parentId,
    'p_code': code,
    'p_name': name,
    'p_attributes': attributes,
    'p_mutation_id': mutationId,
    'p_id': id,
  });

  /// D-038. [acknowledged] is the user's explicit confirmation that the meaning is
  /// unchanged; the server refuses without it whenever the record carries history, so
  /// passing it blindly would defeat the point.
  Future<RemoteOutcome<Map<String, dynamic>>> rename({
    required String entityType,
    required String entityId,
    required String newName,
    required int baseRowVersion,
    bool acknowledged = false,
    String? mutationId,
  }) => _rpc('master_rename', {
    'p_entity_type': entityType,
    'p_entity_id': entityId,
    'p_new_name': newName,
    'p_base_row_version': baseRowVersion,
    'p_acknowledged': acknowledged,
    'p_mutation_id': mutationId,
  });

  Future<RemoteOutcome<Map<String, dynamic>>> archive({
    required String entityType,
    required String entityId,
    required int baseRowVersion,
    String? mutationId,
  }) => _rpc('master_archive', {
    'p_entity_type': entityType,
    'p_entity_id': entityId,
    'p_base_row_version': baseRowVersion,
    'p_mutation_id': mutationId,
  });

  Future<RemoteOutcome<Map<String, dynamic>>> restore({
    required String entityType,
    required String entityId,
    required int baseRowVersion,
    String? mutationId,
  }) => _rpc('master_restore', {
    'p_entity_type': entityType,
    'p_entity_id': entityId,
    'p_base_row_version': baseRowVersion,
    'p_mutation_id': mutationId,
  });

  /// The authoritative usage figure (D-041).
  ///
  /// Returned labelled `source: 'server'`. The caller must not relabel a cached figure
  /// as this one — that is the whole distinction `MasterUsage` exists to preserve.
  Future<RemoteOutcome<Map<String, dynamic>>> usage({
    required String entityType,
    required String entityId,
  }) => _rpc('master_usage', {
    'p_entity_type': entityType,
    'p_entity_id': entityId,
  });

  Future<RemoteOutcome<Map<String, dynamic>>> _rpc(
    String function,
    Map<String, dynamic> params,
  ) async {
    final outcome = await guard(
      () => client.rpc<dynamic>(function, params: params),
    );
    return outcome.map(
      (value) => value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{'status': 'applied'},
    );
  }
}
