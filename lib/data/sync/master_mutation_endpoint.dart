/// The real transport the sync engine pushes through.
///
/// Until now the outbox and the gateways existed side by side and nothing joined them:
/// `SyncEngine` had only a fake endpoint, and every server call in Phase 2 was made
/// directly by a screen. That was survivable while every master mutation was made online
/// by a user watching the result — and it stops being survivable the moment work is queued
/// offline, because nothing would ever deliver it.
///
/// This class is that join, and nothing more. It performs no business arithmetic, decides
/// no authority and invents no retry: it dispatches one queued intent to the RPC that
/// corresponds to it, and translates the answer into the outcome the engine already knows
/// how to act on.
///
/// The translation is the security-relevant part, and it is one table:
///
/// | Server said | Outcome | Why |
/// |---|---|---|
/// | applied / replayed | `applied` / `duplicateIgnored` | the record exists exactly once |
/// | `KM003` version conflict | `conflict` | the *record* moved; a person resolves it |
/// | `KM004` period closed | `periodClosed` | a distinct, truthful reason |
/// | `KM001` / `KM002` no permission | `notPermitted` | terminal; never retried |
/// | any other refusal | `notPermitted` | still terminal — the server said no |
/// | session expired | `authExpired` | the queue pauses; nothing is dropped |
/// | unreachable | `transientFailure` | unknown, so retry — never "rejected" |
///
/// Note the last row. An unclassifiable failure is transient, not a refusal, because
/// "we could not tell" must never look like the server saying no (D-048 §1).
library;

import 'package:krishna_mis/data/remote/master_gateway.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/vendor_tax_period_gateways.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';

class MasterMutationEndpoint implements RemoteMutationEndpoint {
  const MasterMutationEndpoint({required this.masters, required this.vendors});

  final MasterGateway masters;
  final VendorGateway vendors;

  @override
  Future<List<MutationResult>> push(List<PendingMutation> mutations) async {
    final results = <MutationResult>[];
    for (final mutation in mutations) {
      results.add(await _one(mutation));
    }
    return results;
  }

  Future<MutationResult> _one(PendingMutation mutation) async {
    final outcome = await _dispatch(mutation);
    if (outcome == null) {
      // A queued intent this build does not know how to deliver. Terminal rather than
      // retried forever: repeating it cannot teach the client what it is.
      return MutationResult(
        mutationId: mutation.mutationId,
        outcome: MutationOutcome.notPermitted,
        message:
            'This entry cannot be sent by this version of the application. '
            'It has been kept so it is not lost.',
      );
    }

    return switch (outcome) {
      RemoteOk(:final value) => MutationResult(
        mutationId: mutation.mutationId,
        outcome: value['status'] == 'replayed'
            ? MutationOutcome.duplicateIgnored
            : MutationOutcome.applied,
        rowVersion: value['row_version'] as int?,
        serverUpdatedAt: DateTime.tryParse('${value['updated_at']}')?.toUtc(),
      ),
      RemoteRefused(:final refusal) => MutationResult(
        mutationId: mutation.mutationId,
        outcome: switch (refusal.kind) {
          RefusalKind.versionConflict => MutationOutcome.conflict,
          RefusalKind.periodClosed => MutationOutcome.periodClosed,
          _ => MutationOutcome.notPermitted,
        },
        message: refusal.message,
      ),
      RemoteUnreachable(:final failure) => MutationResult(
        mutationId: mutation.mutationId,
        outcome: failure == RemoteFailure.sessionExpired
            ? MutationOutcome.authExpired
            : MutationOutcome.transientFailure,
        message: failure.message,
      ),
    };
  }

  /// Routes one intent to the RPC that corresponds to it, or null if there is none.
  ///
  /// Every call passes the intent's own `mutationId`, which is what makes a redelivery
  /// replay instead of applying a second time (D-004), and its `baseRowVersion`, which is
  /// what makes a stale intent a conflict instead of an overwrite (D-021).
  Future<RemoteOutcome<Map<String, dynamic>>?> _dispatch(
    PendingMutation mutation,
  ) {
    final payload = mutation.payload;

    if (mutation.entityType == 'vendor') {
      return switch (mutation.op) {
        MutationOp.create => vendors.create(
          id: mutation.entityId,
          code: '${payload['code']}',
          name: '${payload['name']}',
          attributes: _attributes(payload),
          mutationId: mutation.mutationId,
        ),
        MutationOp.update => vendors.update(
          id: mutation.entityId,
          baseRowVersion: mutation.baseRowVersion!,
          attributes: _attributes(payload),
          mutationId: mutation.mutationId,
        ),
        _ => Future.value(null),
      };
    }

    // Everything else in the hierarchy shares one set of RPCs, keyed by entity type.
    return switch (mutation.op) {
      MutationOp.update => masters.rename(
        entityType: mutation.entityType,
        entityId: mutation.entityId,
        newName: '${payload['name']}',
        baseRowVersion: mutation.baseRowVersion!,
        acknowledged: payload['acknowledged'] == true,
        mutationId: mutation.mutationId,
      ),
      MutationOp.archive => masters.archive(
        entityType: mutation.entityType,
        entityId: mutation.entityId,
        baseRowVersion: mutation.baseRowVersion!,
        mutationId: mutation.mutationId,
      ),
      _ => Future.value(null),
    };
  }

  /// The vendor's editable fields, minus the ones that are not attributes.
  ///
  /// `code` is immutable by design (D-035) and is never sent as an update.
  static Map<String, dynamic> _attributes(Map<String, Object?> payload) => {
    for (final entry in payload.entries)
      if (entry.key != 'code' && entry.key != 'acknowledged')
        entry.key: entry.value,
  };
}
