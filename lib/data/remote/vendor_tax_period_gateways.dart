/// Vendors, tax rules and period control on the server.
///
/// Three small gateways rather than one, because they answer to three different rules —
/// `masters.manage`, `tax.manage` and `period.close`/`period.reopen` — and a single
/// class covering all three would obscure that. They share only the transport base.
///
/// Pulls live in `MasterGateway.pullAll`, which fetches all reference data in one
/// consistent pass; what is here is the mutation half.
library;

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/supabase_gateway.dart';

/// Shared plumbing: call an RPC, keep the outcome typed.
mixin _RpcCalls on SupabaseGateway {
  Future<RemoteOutcome<Map<String, dynamic>>> callRpc(
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

/// Vendors are organisation-global masters (D-049). Renaming and archiving one goes
/// through `master_rename` / `master_archive` like any other master, so a vendor obeys
/// the same D-038 acknowledgement and D-039 archive rules rather than a parallel set.
class VendorGateway extends SupabaseGateway with _RpcCalls {
  VendorGateway(super.client);

  Future<RemoteOutcome<Map<String, dynamic>>> create({
    required String code,
    required String name,
    Map<String, dynamic> attributes = const {},
    String? mutationId,
    String? id,
  }) => callRpc('vendor_create', {
    'p_code': code,
    'p_name': name,
    'p_attributes': attributes,
    'p_mutation_id': mutationId,
    'p_id': id,
  });

  /// Edits the optional detail. The **name** deliberately is not changed here: it goes
  /// through `master_rename`, which carries the acknowledgement a vendor with history
  /// needs.
  Future<RemoteOutcome<Map<String, dynamic>>> update({
    required String id,
    required int baseRowVersion,
    required Map<String, dynamic> attributes,
    String? mutationId,
  }) => callRpc('vendor_update', {
    'p_id': id,
    'p_base_row_version': baseRowVersion,
    'p_attributes': attributes,
    'p_mutation_id': mutationId,
  });
}

/// Date-effective tax configuration (D-017).
///
/// There is deliberately no "set the rate" call. A rate change is a new period that
/// supersedes the old one, atomically, so last year's Net Sales can never be restated —
/// and an API shaped as `update` would invite exactly that.
class TaxGateway extends SupabaseGateway with _RpcCalls {
  TaxGateway(super.client);

  Future<RemoteOutcome<Map<String, dynamic>>> create({
    required String revenueCategoryId,
    required int rateBasisPoints,
    required String treatment,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
    String? note,
    String? mutationId,
    String? id,
  }) => callRpc('tax_rule_create', {
    'p_revenue_category_id': revenueCategoryId,
    'p_rate_bp': rateBasisPoints,
    'p_treatment': treatment,
    'p_effective_from': _date(effectiveFrom),
    'p_effective_to': effectiveTo == null ? null : _date(effectiveTo),
    'p_note': note,
    'p_mutation_id': mutationId,
    'p_id': id,
  });

  Future<RemoteOutcome<Map<String, dynamic>>> supersede({
    required String currentRuleId,
    required int baseRowVersion,
    required int rateBasisPoints,
    required String treatment,
    required DateTime effectiveFrom,
    String? note,
    String? mutationId,
  }) => callRpc('tax_rule_supersede', {
    'p_current_rule_id': currentRuleId,
    'p_base_row_version': baseRowVersion,
    'p_rate_bp': rateBasisPoints,
    'p_treatment': treatment,
    'p_effective_from': _date(effectiveFrom),
    'p_note': note,
    'p_mutation_id': mutationId,
  });

  Future<RemoteOutcome<Map<String, dynamic>>> archive({
    required String ruleId,
    required int baseRowVersion,
    String? mutationId,
  }) => callRpc('tax_rule_archive', {
    'p_rule_id': ruleId,
    'p_base_row_version': baseRowVersion,
    'p_mutation_id': mutationId,
  });

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

/// Closing and reopening accounting periods (spec §13.4).
class PeriodGateway extends SupabaseGateway with _RpcCalls {
  PeriodGateway(super.client);

  Future<RemoteOutcome<Map<String, dynamic>>> close({
    required String periodKey,
    String? businessUnitId,
    String? mutationId,
  }) => callRpc('period_close', {
    'p_period_key': periodKey,
    'p_business_unit_id': businessUnitId,
    'p_mutation_id': mutationId,
  });

  /// [reason] is mandatory and the server enforces it. Passing a placeholder to satisfy
  /// the signature would defeat the audit trail it exists to populate.
  Future<RemoteOutcome<Map<String, dynamic>>> reopen({
    required String periodKey,
    required String reason,
    String? businessUnitId,
    int? baseRowVersion,
    String? mutationId,
  }) => callRpc('period_reopen', {
    'p_period_key': periodKey,
    'p_reason': reason,
    'p_business_unit_id': businessUnitId,
    'p_base_row_version': baseRowVersion,
    'p_mutation_id': mutationId,
  });

  /// Whether a period is open for a unit, as the server sees it right now.
  Future<RemoteOutcome<String>> state({
    required String periodKey,
    required String businessUnitId,
  }) async {
    final outcome = await guard(
      () => client.rpc<dynamic>(
        'period_state',
        params: {
          'p_period_key': periodKey,
          'p_business_unit_id': businessUnitId,
        },
      ),
    );
    return outcome.map((value) => '$value');
  }
}
