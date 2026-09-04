/// Delivering a correction and a void, and what the endpoint does with each answer
/// (Slice 10 §16, §17, §23, §24, §27).
///
/// These drive the **real** [RevenueMutationEndpoint] against a fake gateway, rather than
/// a fake endpoint, because the things being proved are its own: that an update carries
/// the base version the form opened on, that a void carries its reason and its version,
/// that a redelivery replays instead of recording twice, and that the two refusals which
/// mean *a person must choose* are classified as conflicts while everything else is
/// terminal.
///
/// The distinction the last one turns on: a stale version (`KM003`) and a tax mismatch
/// (`KM030`, D-114) are two defensible answers with nobody entitled to overwrite the
/// other. A withdrawn capability is not — no retry changes it, and there is nothing to
/// choose between.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/data/remote/revenue_gateway.dart';
import 'package:krishna_mis/data/repositories/revenue_repository.dart';
import 'package:krishna_mis/data/sync/revenue_mutation_endpoint.dart';
import 'package:krishna_mis/domain/sync/pending_mutation.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A gateway that records what it was asked to send and answers as told.
///
/// It never opens a socket: the Supabase client is constructed and not used, which is
/// enough because every method below is overridden.
class _FakeGateway extends RevenueGateway {
  _FakeGateway() : super(SupabaseClient('http://localhost', 'test-key'));

  final List<({String rpc, Map<String, Object?> args})> sent = [];

  /// The canonical store, keyed by mutation id — which is what idempotency means.
  final Map<String, Map<String, dynamic>> committed = {};

  ServerRefusal? refuseNextWith;
  RemoteFailure? unreachableWith;

  RemoteOutcome<Map<String, dynamic>> _answer(
    String rpc,
    Map<String, Object?> args,
    String mutationId,
    String entityId,
  ) {
    sent.add((rpc: rpc, args: args));

    if (unreachableWith case final failure?) {
      return RemoteUnreachable(failure);
    }
    if (refuseNextWith case final refusal?) {
      refuseNextWith = null;
      return RemoteRefused(refusal);
    }

    final replay = committed.containsKey(mutationId);
    if (!replay) {
      committed[mutationId] = {
        'id': entityId,
        'status': 'created',
        'row_version': (committed.length + 2),
        'txn_number': 'KI-REV-26-27-000001',
        'financial_year': '2026-27',
        'updated_at': '2026-06-15T10:00:00.000Z',
      };
    }
    final stored = committed[mutationId]!;
    return RemoteOk({...stored, if (replay) 'status': 'replayed'});
  }

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> create({
    required Map<String, Object?> arguments,
    required String mutationId,
  }) async => _answer(
    'revenue_create',
    {...arguments, 'p_mutation_id': mutationId},
    mutationId,
    '${arguments['p_id']}',
  );

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> update({
    required Map<String, Object?> arguments,
    required int baseRowVersion,
    required String mutationId,
  }) async => _answer(
    'revenue_update',
    {
      ...arguments,
      'p_base_row_version': baseRowVersion,
      'p_mutation_id': mutationId,
    },
    mutationId,
    '${arguments['p_id']}',
  );

  @override
  Future<RemoteOutcome<Map<String, dynamic>>> voidEntry({
    required String entryId,
    required int baseRowVersion,
    required String reason,
    required String mutationId,
  }) async => _answer(
    'revenue_void',
    {
      'p_id': entryId,
      'p_base_row_version': baseRowVersion,
      'p_reason': reason,
      'p_mutation_id': mutationId,
    },
    mutationId,
    entryId,
  );
}

/// Real UUIDs: `PendingMutation` refuses anything else, because the mutation id is the
/// idempotency key the server stores and matches on.
const _mutationId = '019220a0-0000-7000-8000-000000000001';
const _entityId = '019220a0-0000-7000-8000-000000000002';

PendingMutation _mutation({
  required MutationOp op,
  String mutationId = _mutationId,
  String entityId = _entityId,
  int? baseRowVersion,
  Map<String, Object?> payload = const {},
}) => PendingMutation(
  mutationId: mutationId,
  entityType: revenueEntityType,
  entityId: entityId,
  op: op,
  payload: payload,
  baseRowVersion: baseRowVersion,
  createdAt: DateTime.utc(2026, 6, 15, 10),
);

ServerRefusal _refusal(String code, RefusalKind kind) =>
    ServerRefusal(code: code, kind: kind, message: 'refused', detail: const {});

void main() {
  late _FakeGateway gateway;
  late RevenueMutationEndpoint endpoint;

  setUp(() {
    gateway = _FakeGateway();
    endpoint = RevenueMutationEndpoint(gateway);
  });

  group('what an update actually sends (§4, §16)', () {
    test(
      'the stored payload goes verbatim, with the version the form opened on',
      () async {
        await endpoint.push([
          _mutation(
            op: MutationOp.update,
            baseRowVersion: 7,
            payload: const {
              'p_id': _entityId,
              'p_business_date': '2026-06-15',
              'p_components': [
                {'id': 'c0', 'entered_amount_minor': 10000000},
              ],
            },
          ),
        ]);

        final call = gateway.sent.single;
        expect(call.rpc, 'revenue_update');
        // Never re-read at send time: a background pull that moved the row must make this
        // a conflict rather than silently retarget somebody's correction.
        expect(call.args['p_base_row_version'], 7);
        expect(call.args['p_business_date'], '2026-06-15');
        // No rate and no tax as instructions. The server resolves and compares (D-114).
        expect(call.args.keys, isNot(contains('p_tax_rate_bp')));
        expect(call.args.keys, isNot(contains('p_business_unit_id')));
        expect(call.args.keys, isNot(contains('p_revenue_category_id')));
      },
    );

    test('a void carries its reason and its base version', () async {
      await endpoint.push([
        _mutation(
          op: MutationOp.void_,
          baseRowVersion: 3,
          payload: const {'p_reason': 'entered twice'},
        ),
      ]);

      final call = gateway.sent.single;
      expect(call.rpc, 'revenue_void');
      expect(call.args['p_reason'], 'entered twice');
      expect(call.args['p_base_row_version'], 3);
    });
  });

  group('redelivery (§16, §17, §23)', () {
    test('the same correction twice is one record, replayed', () async {
      final intent = _mutation(
        op: MutationOp.update,
        baseRowVersion: 4,
        payload: const {'p_id': 'entry-1'},
      );

      final first = await endpoint.push([intent]);
      final second = await endpoint.push([intent]);

      expect(first.single.outcome, MutationOutcome.applied);
      // The idempotency guarantee working, not an error.
      expect(second.single.outcome, MutationOutcome.duplicateIgnored);
      expect(gateway.committed, hasLength(1));
      // Both calls reached the server; only one record exists.
      expect(gateway.sent, hasLength(2));
    });

    test('the same void twice is one void, replayed', () async {
      final intent = _mutation(
        op: MutationOp.void_,
        baseRowVersion: 3,
        payload: const {'p_reason': 'entered twice'},
      );

      await endpoint.push([intent]);
      final second = await endpoint.push([intent]);

      expect(second.single.outcome, MutationOutcome.duplicateIgnored);
      expect(gateway.committed, hasLength(1));
    });

    test(
      'a lost response leaves the intent recoverable, and the retry replays',
      () async {
        final intent = _mutation(
          op: MutationOp.update,
          baseRowVersion: 4,
          payload: const {'p_id': 'entry-1'},
        );

        // The server commits and the answer never arrives.
        await endpoint.push([intent]);
        expect(gateway.committed, hasLength(1));

        // Recovery re-sends **the same intent**. A fresh mutation id would be a second
        // financial record for one act, and nothing afterwards could tell them apart.
        final retry = await endpoint.push([intent]);
        expect(retry.single.outcome, MutationOutcome.duplicateIgnored);
        expect(gateway.committed, hasLength(1));
        expect(retry.single.rowVersion, isNotNull);
      },
    );
  });

  group('classification (§24, §27)', () {
    test('a stale version is a conflict, never a rejection', () async {
      gateway.refuseNextWith = _refusal('KM003', RefusalKind.versionConflict);

      final result = await endpoint.push([
        _mutation(op: MutationOp.void_, baseRowVersion: 2),
      ]);

      // A void issued from a stale view must not void a version nobody reviewed
      // (D-021). It is a conflict a person resolves.
      expect(result.single.outcome, MutationOutcome.conflict);
    });

    test(
      'a tax mismatch is a conflict, and it is not the same word as a rejection',
      () async {
        gateway.refuseNextWith = _refusal(
          'KM030',
          RefusalKind.taxConfigurationMismatch,
        );

        final result = await endpoint.push([
          _mutation(op: MutationOp.update, baseRowVersion: 4),
        ]);

        expect(result.single.outcome, MutationOutcome.conflict);
      },
    );

    test('a closed period keeps its own truthful reason', () async {
      gateway.refuseNextWith = _refusal('KM004', RefusalKind.periodClosed);

      final result = await endpoint.push([
        _mutation(op: MutationOp.update, baseRowVersion: 4),
      ]);

      // Never dressed up as a conflict: there is nothing to choose between, and the
      // user is entitled to be told the real reason (D-026).
      expect(result.single.outcome, MutationOutcome.periodClosed);
    });

    test(
      'a withdrawn capability is terminal, not something to retry',
      () async {
        gateway.refuseNextWith = _refusal(
          'KM001',
          RefusalKind.missingCapability,
        );

        final result = await endpoint.push([
          _mutation(op: MutationOp.void_, baseRowVersion: 2),
        ]);

        expect(result.single.outcome, MutationOutcome.notPermitted);
      },
    );

    test(
      'an unreachable server is transient, and never looks like a refusal',
      () async {
        gateway.unreachableWith = RemoteFailure.offline;

        final result = await endpoint.push([
          _mutation(op: MutationOp.update, baseRowVersion: 4),
        ]);

        // "We could not tell" must never look like the server saying no (D-048 §1).
        expect(result.single.outcome, MutationOutcome.transientFailure);
        expect(gateway.committed, isEmpty);
      },
    );

    test(
      'an expired session pauses the queue rather than burning the attempt',
      () async {
        gateway.unreachableWith = RemoteFailure.sessionExpired;

        final result = await endpoint.push([
          _mutation(op: MutationOp.update, baseRowVersion: 4),
        ]);

        expect(result.single.outcome, MutationOutcome.authExpired);
      },
    );
  });

  group('an op this build cannot deliver', () {
    test(
      'is kept for a person, not discarded and not retried for ever',
      () async {
        final result = await endpoint.push([
          _mutation(op: MutationOp.archive, baseRowVersion: 1),
        ]);

        expect(result.single.outcome, MutationOutcome.notPermitted);
        expect(result.single.message, contains('kept'));
        expect(gateway.sent, isEmpty);
      },
    );
  });
}
