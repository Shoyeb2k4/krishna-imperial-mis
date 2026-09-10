/// The Owner Accounts half of the remote boundary.
///
/// Thin by design, exactly like [ExpenseGateway] and [RevenueGateway]: it names the RPC,
/// passes the stored payload through, and lets [SupabaseGateway.guard] turn whatever comes
/// back into `RemoteOk`, `RemoteRefused` or `RemoteUnreachable`. It decides nothing.
///
/// **It sends no owner for a consumption.** The server resolves the family mapping as at
/// the business date and computes the attribution itself. What the client *does* send is
/// what it showed the operator, as `p_declared_owner_id`, which the server compares and
/// refuses on — so a family link that changed between opening the form and pressing save
/// surfaces as an explicit mismatch rather than as a bill quietly landing on the wrong
/// account (§12, and D-114's contract for a declared tax figure).
library;

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/supabase_gateway.dart';

/// The one canonical-owner read a settlement needs.
///
/// A narrow interface rather than the whole gateway, so the synchroniser depends on the
/// single call it makes and a test can supply one without a Supabase client — the shape
/// D-121 established for the ledger query.
abstract interface class OwnerSnapshotSource {
  Future<RemoteOutcome<Map<String, dynamic>>> fetchSettlementSnapshot();
}

class OwnerLedgerGateway extends SupabaseGateway
    with RpcCalls
    implements OwnerSnapshotSource {
  OwnerLedgerGateway(super.client);

  // ── The ledger ────────────────────────────────────────────────────────────

  /// Records an owner movement.
  ///
  /// [arguments] is the payload captured at save time and stored in the outbox verbatim,
  /// so what is delivered is what the operator intended when they pressed save — not a
  /// re-derivation from a local row that may have moved on since.
  Future<RemoteOutcome<Map<String, dynamic>>> create({
    required Map<String, Object?> arguments,
    required String mutationId,
  }) => callRpc('owner_movement_create', {
    ...arguments,
    'p_mutation_id': mutationId,
  });

  /// Corrects an owner movement.
  ///
  /// [baseRowVersion] is the version the operator was looking at when the form opened,
  /// carried from there and never re-read here. A background pull that moved the row must
  /// make this a conflict rather than silently retarget somebody's correction (D-021).
  Future<RemoteOutcome<Map<String, dynamic>>> update({
    required Map<String, Object?> arguments,
    required int baseRowVersion,
    required String mutationId,
  }) => callRpc('owner_movement_update', {
    ...arguments,
    'p_base_row_version': baseRowVersion,
    'p_mutation_id': mutationId,
  });

  Future<RemoteOutcome<Map<String, dynamic>>> voidMovement({
    required String entryId,
    required int baseRowVersion,
    required String reason,
    required String mutationId,
  }) => callRpc('owner_movement_void', {
    'p_id': entryId,
    'p_base_row_version': baseRowVersion,
    'p_reason': reason,
    'p_mutation_id': mutationId,
  });

  /// Reads one movement back.
  ///
  /// Used only by reconciliation, when an answer arrived without the fields needed to
  /// apply it — a replayed older result, or a response shape this build does not know.
  /// Asking the server what it holds under the same identity is the safe recovery;
  /// guessing or re-sending is not.
  ///
  /// Straight off `owner_ledger_entries`, which is behind its own RLS policy: a caller
  /// without the unscoped `owner_ledger.view` gets nothing, and nothing is filtered here.
  /// There is no projection in between because there is nothing to withhold — an owner
  /// movement is never partly visible.
  Future<RemoteOutcome<Map<String, dynamic>?>> fetchMovement(String id) =>
      guard(() async {
        final rows = await client
            .from('owner_ledger_entries')
            .select()
            .eq('id', id)
            .limit(1);
        final list = rows.cast<Map<String, dynamic>>();
        return list.isEmpty ? null : list.first;
      });

  /// **The canonical owner data a settlement is computed from, in one coherent read.**
  ///
  /// Phase 5 OA-2 §18, §19. One RPC returning movements, owners and ownership shares
  /// together with the server's own MVCC snapshot identity and transaction time — because
  /// four separate reads are four snapshots under READ COMMITTED, and a settlement
  /// assembled from them would be a position of a moment that never existed. That is the
  /// defect D-188 corrected for reporting, and repeating it knowingly would be worse than
  /// the first time.
  ///
  /// It calculates nothing. The arithmetic is the client domain's, and a client-callable
  /// settlement boundary would need the capability OA-3 owns (§44).
  @override
  Future<RemoteOutcome<Map<String, dynamic>>> fetchSettlementSnapshot() =>
      guard(() async {
        final result = await client.rpc<dynamic>('owner_ledger_snapshot');
        return (result as Map).cast<String, dynamic>();
      });

  // ── The masters ───────────────────────────────────────────────────────────
  //
  // Individual reads, retained for administration and diagnostics. **The settlement path
  // does not use them** — it takes `fetchSettlementSnapshot`, precisely so its datasets
  // come from one snapshot rather than three.

  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchOwners() =>
      guard(() async {
        final rows = await client.from('owners').select();
        return rows.cast<Map<String, dynamic>>();
      });

  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchOwnershipShares() =>
      guard(() async {
        final rows = await client.from('ownership_shares').select();
        return rows.cast<Map<String, dynamic>>();
      });

  Future<RemoteOutcome<List<Map<String, dynamic>>>> fetchFamilyMembers() =>
      guard(() async {
        final rows = await client.from('owner_family_members').select();
        return rows.cast<Map<String, dynamic>>();
      });

  // ── Administration ────────────────────────────────────────────────────────

  Future<RemoteOutcome<Map<String, dynamic>>> createOwner({
    required String id,
    required String code,
    required String displayName,
    required String mutationId,
  }) => callRpc('owner_create', {
    'p_id': id,
    'p_code': code,
    'p_display_name': displayName,
    'p_mutation_id': mutationId,
  });

  /// Sets an owner's share from a date, closing whatever was open before it.
  ///
  /// One call rather than two, because "from 1 April this owner holds 50%" is one business
  /// act — and splitting it would leave a window in which the shares do not total 10000,
  /// a state a settlement is required to refuse and which only the administrative path
  /// could have created.
  Future<RemoteOutcome<Map<String, dynamic>>> setOwnershipShare({
    required String ownerId,
    required int shareBasisPoints,
    required String effectiveFrom,
    required String mutationId,
    String? note,
  }) => callRpc('owner_share_set', {
    'p_owner_id': ownerId,
    'p_share_basis_points': shareBasisPoints,
    'p_effective_from': effectiveFrom,
    'p_note': note,
    'p_mutation_id': mutationId,
  });

  Future<RemoteOutcome<Map<String, dynamic>>> createFamilyMember({
    required String id,
    required String ownerId,
    required String displayName,
    required String effectiveFrom,
    required String mutationId,
    String? relationshipLabel,
    bool isSelf = false,
    bool mayUseNc = true,
  }) => callRpc('owner_family_member_create', {
    'p_id': id,
    'p_owner_id': ownerId,
    'p_display_name': displayName,
    'p_effective_from': effectiveFrom,
    'p_relationship_label': relationshipLabel,
    'p_is_self': isSelf,
    'p_may_use_nc': mayUseNc,
    'p_mutation_id': mutationId,
  });

  /// Ends a family link.
  ///
  /// **This is how a reassignment happens**: end here, create anew under the other owner.
  /// The link itself cannot move — a trigger refuses that — so historical attribution
  /// survives by construction rather than by care (§6).
  Future<RemoteOutcome<Map<String, dynamic>>> endFamilyMember({
    required String id,
    required String effectiveTo,
    required String mutationId,
  }) => callRpc('owner_family_member_end', {
    'p_id': id,
    'p_effective_to': effectiveTo,
    'p_mutation_id': mutationId,
  });
}
