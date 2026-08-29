/// The expense half of the remote boundary.
///
/// Thin by design: it names the RPC, passes the arguments through, and lets
/// [SupabaseGateway.guard] turn whatever comes back into `RemoteOk`, `RemoteRefused` or
/// `RemoteUnreachable`. It decides nothing. Every rule — capability, scope on each unit,
/// the cross-unit and cross-period privileges, hierarchy, archive state, the period lock
/// on each period, the edit window, the row version — is decided in Postgres, and the
/// client never sends its own opinion as a claim (D-037).
///
/// The payload is built by [ExpenseRepository] at save time and stored in the outbox, so
/// what is delivered is what the user intended at the moment they pressed save — not a
/// re-derivation from a local row that may have moved on since.
library;

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/supabase_gateway.dart';

class ExpenseGateway extends SupabaseGateway with RpcCalls {
  ExpenseGateway(super.client);

  /// Records an expense.
  ///
  /// [arguments] is the stored payload verbatim. The `p_mutation_id` is added here rather
  /// than at save time because it belongs to the delivery, not to the document — though
  /// in practice they are the same value for the life of the intent (D-004).
  Future<RemoteOutcome<Map<String, dynamic>>> create({
    required Map<String, Object?> arguments,
    required String mutationId,
  }) => callRpc('expense_create', {...arguments, 'p_mutation_id': mutationId});

  Future<RemoteOutcome<Map<String, dynamic>>> update({
    required Map<String, Object?> arguments,
    required int baseRowVersion,
    required String mutationId,
  }) => callRpc('expense_update', {
    ...arguments,
    'p_base_row_version': baseRowVersion,
    'p_mutation_id': mutationId,
  });

  Future<RemoteOutcome<Map<String, dynamic>>> voidExpense({
    required String expenseId,
    required int baseRowVersion,
    required String reason,
    required String mutationId,
  }) => callRpc('expense_void', {
    'p_id': expenseId,
    'p_base_row_version': baseRowVersion,
    'p_reason': reason,
    'p_mutation_id': mutationId,
  });

  /// Re-reads one document as the server is willing to show it to this caller.
  ///
  /// Reads `expense_document`, never `expenses`: the header total on a shared bill is
  /// withheld by the projection, and asking the base table would both fail and be the
  /// wrong question. This is the recovery path when a response is lost after the server
  /// committed — ask again, with the same identity.
  Future<RemoteOutcome<Map<String, dynamic>?>> fetchDocument(
    String expenseId,
  ) => guard(() async {
    final rows = await client
        .from('expense_document')
        .select()
        .eq('id', expenseId)
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  });

  /// The allocation lines this caller may see, for one document.
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchAllocations(
    String expenseId,
  ) => guard(() async {
    final rows = await client
        .from('expense_allocations')
        .select()
        .eq('expense_id', expenseId);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  });

  /// The period contributions this caller may see — the one reporting source (D-060).
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchPeriodContributions(
    String expenseId,
  ) => guard(() async {
    final rows = await client
        .from('expense_period_contributions')
        .select()
        .eq('expense_id', expenseId);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  });

  /// Attachments, if this caller is entitled to the whole document.
  ///
  /// A scoped caller gets an empty list — not because the client filtered it, but because
  /// the server's policy returns nothing. An invoice image for a shared bill states the
  /// full ₹58,000 on its face, so it is complete-document-only.
  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchAttachments(
    String expenseId,
  ) => guard(() async {
    final rows = await client
        .from('expense_attachments')
        .select()
        .eq('expense_id', expenseId);
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  });
}
