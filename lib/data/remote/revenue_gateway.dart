/// The revenue half of the remote boundary.
///
/// Thin by design, exactly like [ExpenseGateway]: it names the RPC, passes the stored
/// payload through, and lets [SupabaseGateway.guard] turn whatever comes back into
/// `RemoteOk`, `RemoteRefused` or `RemoteUnreachable`. It decides nothing.
///
/// **It sends no rate and no tax.** The server resolves the rule and computes gross, tax
/// and net itself, and ignores anything a caller says about them (D-037). What the client
/// *does* send is what it showed the operator, as `declared_*` values the server compares
/// and refuses on — so a rate that changed between preparing an entry and delivering it
/// surfaces as an explicit mismatch rather than as a document quietly holding different
/// money from the one somebody approved.
library;

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/supabase_gateway.dart';

class RevenueGateway extends SupabaseGateway with RpcCalls {
  RevenueGateway(super.client);

  /// Records a revenue entry.
  ///
  /// [arguments] is the payload captured at save time and stored in the outbox verbatim,
  /// so what is delivered is what the operator intended when they pressed save — not a
  /// re-derivation from a local row that may have moved on since.
  Future<RemoteOutcome<Map<String, dynamic>>> create({
    required Map<String, Object?> arguments,
    required String mutationId,
  }) => callRpc('revenue_create', {...arguments, 'p_mutation_id': mutationId});

  Future<RemoteOutcome<Map<String, dynamic>>> voidEntry({
    required String entryId,
    required int baseRowVersion,
    required String reason,
    required String mutationId,
  }) => callRpc('revenue_void', {
    'p_id': entryId,
    'p_base_row_version': baseRowVersion,
    'p_reason': reason,
    'p_mutation_id': mutationId,
  });

  /// Reads one entry back through the authorised projection.
  ///
  /// Used only by reconciliation, when an answer arrived without the fields needed to
  /// apply it — a replayed older result, or a response shape this build does not know.
  /// Asking the server what it holds under the same identity is the safe recovery; guessing
  /// or re-sending is not.
  Future<RemoteOutcome<Map<String, dynamic>?>> fetchDocument(String id) =>
      guard(() async {
        final rows = await client
            .from('revenue_document')
            .select()
            .eq('id', id)
            .limit(1);
        final list = rows.cast<Map<String, dynamic>>();
        return list.isEmpty ? null : list.first;
      });
}
