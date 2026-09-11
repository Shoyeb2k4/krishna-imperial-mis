/// **OA-2 §18 and §20 — the remote-completeness audit, run before any settlement
/// arithmetic exists.**
///
/// The brief is explicit: *do not build a settlement engine over device-local partial
/// Owner Ledger history*, and prove what canonical owner data another device can actually
/// obtain before writing the calculation. So this file exists to establish the gap rather
/// than to work around it, and it is committed as the evidence the decision was built on.
///
/// It asks three questions of the **real** backend and a **fresh** device:
///
/// 1. Device A records an owner movement and the server accepts it. Can Device B — a
///    device that never created or opened it — see it in its canonical local ledger?
/// 2. Can Device B see the ownership masters a settlement needs: owners, ownership
///    shares, family links?
/// 3. Is the gap on the **server** side or the **client** side? That decides whether the
///    fix is a boundary change or a pull, and they are very different pieces of work.
///
/// Skipped unless `KRISHNA_DEV_IDENTITIES` points at the development identity file, so an
/// ordinary `flutter test` run stays hermetic and offline.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/owner_ledger_repository.dart';
import 'package:krishna_mis/data/remote/owner_ledger_gateway.dart';
import 'package:krishna_mis/data/repositories/owner_settlement_repository.dart';
import 'package:krishna_mis/data/sync/owner_settlement_sync.dart';
import 'package:krishna_mis/domain/owner_accounts/owner.dart';
import 'package:krishna_mis/domain/owner_accounts/owner_ledger.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _identitiesVar = 'KRISHNA_DEV_IDENTITIES';
const _marker = 'OA2-AUDIT';

/// Everything, with no filter of any kind — the most generous question a device can ask
/// its own canonical ledger. If this comes back empty, nothing narrower will help.
class _EverythingQuery implements OwnerLedgerQuery {
  @override
  Set<String>? get businessUnitIds => null;
  @override
  String? get ownerId => null;
  @override
  String? get businessUnitId => null;
  @override
  OwnerMovementType? get movementType => null;
  @override
  BusinessDate? get from => null;
  @override
  BusinessDate? get to => null;
  @override
  bool get includeVoided => true;
  @override
  int get limit => 1000;
  @override
  int get offset => 0;
}

void main() {
  final identitiesPath = Platform.environment[_identitiesVar];
  if (identitiesPath == null || !File(identitiesPath).existsSync()) {
    return;
  }

  final config =
      jsonDecode(File(r'config/dev.json').readAsStringSync())
          as Map<String, dynamic>;
  final identities =
      jsonDecode(File(identitiesPath).readAsStringSync())
          as Map<String, dynamic>;

  late SupabaseClient deviceA;
  late SupabaseClient deviceB;
  late AppDatabase deviceBLocal;
  late OwnerLedgerRepository deviceBRepository;
  late String hki;
  late String ownerAId;
  final created = <({String id, int rowVersion})>[];

  Future<SupabaseClient> signIn(String email) async {
    final client = SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_ANON_KEY'] as String,
    );
    await client.auth.signInWithPassword(
      email: email,
      password:
          (identities[email] as Map<String, dynamic>)['password'] as String,
    );
    return client;
  }

  setUpAll(() async {
    // Two independent authenticated sessions for the same person. That is deliberately
    // the *friendliest* case: if a second device cannot see the movement even when it is
    // the same human with the same authority, no narrower case can.
    deviceA = await signIn('giridhar@hki.com');
    deviceB = await signIn('giridhar@hki.com');

    // Device B's local database is brand new — the state of a fresh installation, a
    // reinstalled phone, or a second workstation.
    deviceBLocal = AppDatabase(NativeDatabase.memory());
    deviceBRepository = OwnerLedgerRepository(deviceBLocal);

    hki =
        (await deviceA
                .from('business_units')
                .select('id')
                .eq('code', 'HKI')
                .single())['id']
            as String;

    ownerAId =
        (await deviceA
                .from('owners')
                .select('id')
                .eq('code', 'OA1_TEST_OWNER_A')
                .single())['id']
            as String;
  });

  tearDownAll(() async {
    // Reversed through the real void, never deleted (D-006).
    for (final movement in created) {
      await deviceA.rpc<dynamic>(
        'owner_movement_void',
        params: {
          'p_id': movement.id,
          'p_reason': 'OA-2 completeness audit fixture reversal ($_marker)',
          'p_base_row_version': movement.rowVersion,
          'p_mutation_id': const Uuid().v4(),
        },
      );
    }
    await deviceBLocal.close();
    await deviceA.auth.signOut();
    await deviceB.auth.signOut();
  });

  test(
    '§18 · a canonical movement Device A recorded is invisible to Device B',
    () async {
      final id = const Uuid().v4();
      final result =
          (await deviceA.rpc<dynamic>(
                    'owner_movement_create',
                    params: {
                      'p_id': id,
                      'p_business_unit_id': hki,
                      'p_business_date': '2026-06-15',
                      'p_movement_type': 'withdrawal',
                      'p_amount_minor': 1234500,
                      'p_owner_id': ownerAId,
                      'p_remarks': 'OA-2 completeness audit $_marker',
                      'p_mutation_id': const Uuid().v4(),
                    },
                  )
                  as Map)
              .cast<String, dynamic>();

      expect(result['status'], 'created');
      expect(
        result['txn_number'],
        isNotNull,
        reason: 'the server accepted it and issued a KI-OWN number',
      );
      created.add((id: id, rowVersion: result['row_version'] as int));

      // The whole of the question. Device B is authorised, online, and asking its own
      // canonical ledger the most generous question available.
      final visible = await deviceBRepository.query(_EverythingQuery());

      expect(
        visible,
        isEmpty,
        reason:
            'THE GAP: a device holds only the owner movements it recorded itself. A '
            'settlement computed here would silently omit every movement made anywhere '
            'else, and would reconcile against itself perfectly while doing it',
      );
      expect(await deviceBRepository.load(id), isNull);
    },
  );

  test('§20 · the ownership masters are invisible to Device B as well', () async {
    // This is the half OA-1 did not report, and it is the more severe one: without
    // shares there is no ratio to allocate by, and without the family links an NC bill
    // cannot be attributed to an owner at all.
    expect(
      (await deviceBRepository.owners()),
      isEmpty,
      reason: 'no owner master reaches a device through any production path',
    );
    expect(
      (await deviceBRepository.ownershipShares()).shares,
      isEmpty,
      reason:
          'THE SECOND GAP: `ownershipShares()` reads a local table nothing writes, so '
          'the V1 vector resolves to "no share configured" on every real device',
    );
    expect(
      (await deviceBRepository.familyMapping()).ncConsumersOn(
        BusinessDate.of(2026, 6, 15),
      ),
      isEmpty,
      reason: 'and no family link reaches a device either',
    );
  });

  test(
    '§19 · the gap is client-side: the server hands Device B everything',
    () async {
      // Which decides the shape of the fix. If the boundary refused, this would be a
      // security/RLS change; it does not, so what is missing is a caller — the same
      // finding D-173 recorded for reporting, in a second domain.
      final movements = await deviceB
          .from('owner_ledger_entries')
          .select(
            'id, txn_number, movement_type, amount_minor, owner_id, voided_at',
          )
          .eq('id', created.single.id);

      expect(
        movements,
        hasLength(1),
        reason:
            'the projection returns it to the very session that could not see it',
      );
      expect(movements.single['amount_minor'], 1234500);

      expect(await deviceB.from('owners').select('id'), isNotEmpty);
      expect(await deviceB.from('ownership_shares').select('id'), isNotEmpty);
      expect(
        await deviceB.from('owner_family_members').select('id'),
        isNotEmpty,
      );
    },
  );

  test('§18 · and no production code path could have filled that cache', () async {
    // Stated structurally as well as behaviourally, because the behavioural test above
    // would also pass if a pull existed and merely had not run yet. It does not exist:
    // the gateway offers `fetchMovement(id)` for reconciliation and no list read at all,
    // and the three master fetches it does offer have no caller anywhere in `lib/`.
    final gateway = File(
      'lib/data/remote/owner_ledger_gateway.dart',
    ).readAsStringSync();
    expect(gateway, contains('fetchMovement('));
    expect(
      gateway,
      isNot(contains('fetchMovements(')),
      reason: 'there is no canonical owner ledger list read',
    );

    final production = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('owner_ledger_gateway.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    for (final fetch in [
      'fetchOwners(',
      'fetchOwnershipShares(',
      'fetchFamilyMembers(',
    ]) {
      expect(
        production,
        isNot(contains(fetch)),
        reason:
            '$fetch exists on the gateway and is called by nothing — the D-077 shape, '
            'in the owner-accounts domain',
      );
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //
  // **And the gap, closed.** Everything above describes an unsynchronised Device B and
  // stays true of one; this runs the OA-2 synchroniser on that same device and asks the
  // same questions again.
  group('§19 · the canonical owner pull closes it', () {
    late OwnerSettlementRepository settlement;

    setUpAll(() async {
      settlement = OwnerSettlementRepository(
        deviceBLocal,
        ownerUserId: deviceB.auth.currentUser!.id,
      );
    });

    test('one pull, and Device B holds what Device A recorded', () async {
      final sync = OwnerSettlementSync(
        database: deviceBLocal,
        gateway: OwnerLedgerGateway(deviceB),
        ownerUserId: deviceB.auth.currentUser!.id,
      );

      final result = await sync.synchronise();
      expect(
        result,
        isA<OwnerSettlementSynchronised>(),
        reason: 'the run reports what it established: $result',
      );

      final established = result as OwnerSettlementSynchronised;
      expect(established.movements, greaterThan(0));
      expect(
        established.snapshotId,
        isNotEmpty,
        reason: 'the server issued the snapshot identity, not the device',
      );

      final movement = await settlement.canonicalMovements(
        through: BusinessDate.of(2030, 12, 31),
      );
      final mine = movement.where((m) => m.id == created.single.id).toList();
      expect(
        mine,
        hasLength(1),
        reason:
            'the movement Device A recorded and Device B never opened is now here, '
            'which is the whole of what the audit found missing',
      );
      expect(mine.single.amount.paise, 1234500);
      expect(mine.single.isCanonical, isTrue);
    });

    test('and the ownership vector it must allocate by', () async {
      final shares = await settlement.ownershipShares();
      expect(shares.shares, isNotEmpty);
      expect(await settlement.activeOwnerIds(), isNotEmpty);

      // The live configuration is the approved V1 pair, resolved through the same call a
      // settlement makes (D-204).
      final open = shares.shares.where((s) => s.effectiveTo == null).toList();
      expect(open, hasLength(v1OwnerCount));
      expect(
        open.map((s) => s.shareBasisPoints),
        everyElement(v1ShareBasisPoints),
      );
    });

    test(
      'coverage is the server own evidence, and only the server can issue it',
      () async {
        final coverage = await settlement.coverage();
        expect(coverage, isNotNull);
        expect(coverage!.movementCount, greaterThan(0));
        expect(
          coverage.serverConfirmedAt.isAfter(DateTime.utc(2026)),
          isTrue,
          reason:
              'the server transaction time, from the statement that returned the facts — '
              'never a device clock reading (D-188)',
        );
      },
    );

    test('a second pull is idempotent: replaced, never appended', () async {
      await OwnerSettlementSync(
        database: deviceBLocal,
        gateway: OwnerLedgerGateway(deviceB),
        ownerUserId: deviceB.auth.currentUser!.id,
      ).synchronise();

      // The property, not a count compared across two live reads: another suite writing
      // the same ledger between the two pulls legitimately changes the count, and did
      // (OA-3, run beside the OA-1 suite). What a full replace must never do is hold one
      // movement twice.
      final ids = [
        for (final m in await settlement.canonicalMovements(
          through: BusinessDate.of(2030, 12, 31),
        ))
          m.id,
      ];
      expect(
        ids.toSet(),
        hasLength(ids.length),
        reason: 'a full replace cannot double-count what it re-reads',
      );
      expect(ids.where((id) => id == created.single.id), hasLength(1));
    });
  });
}
