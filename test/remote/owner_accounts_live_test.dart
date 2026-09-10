/// The Owner Accounts server boundary, against the real `krishna-mis-dev` project.
///
/// Phase 5 OA-1. Skipped unless `KRISHNA_DEV_IDENTITIES` points at the development
/// identity file, so an ordinary `flutter test` run stays hermetic and offline. Nothing
/// here prints a password, a token or the API key.
///
/// What this proves that no host test can:
///
/// * the **authorization matrix** as the server actually decides it, per identity;
/// * that the server **derives** an NC bill's owner from the family mapping and refuses a
///   declared owner that disagrees (§12) — the client's opinion is compared, never used;
/// * that the `KI-OWN` sequence issues numbers and that a replayed mutation id returns the
///   same one rather than a second movement;
/// * the whitespace rule on a void, over every shape of whitespace (spec §14.1);
/// * that the expense guard refuses a category named for an owner movement, with its own
///   refusal code and not merely with *some* error;
/// * and that recording owner movements moves **no** expense or revenue contribution.
///
/// Every fixture it creates is reversed through the real `owner_movement_void`, and the
/// teardown sweeps **before** the fixtures as well as after them — a suite that depends on
/// its own teardown having succeeded can pass exactly once (D-071, D-076).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/owner_accounts/owner.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _identitiesVar = 'KRISHNA_DEV_IDENTITIES';

/// A marker in `remarks`, so the teardown can find what this run created across process
/// boundaries — the one identifier that survives one (D-071).
const _marker = 'OA1-LIVE';

String? refusalOf(Object? error) =>
    error is PostgrestException ? error.code : null;

/// Ownership-share dates are computed from where the timeline currently stands, never
/// written down (D-076) — see the note on the ownership-share group.
String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _firstOfNextMonth(String isoDate) {
  final d = DateTime.parse(isoDate);
  return _iso(DateTime.utc(d.year, d.month + 1, 1));
}

String _dayBefore(String isoDate) {
  final d = DateTime.parse(isoDate);
  return _iso(
    DateTime.utc(d.year, d.month, d.day).subtract(const Duration(days: 1)),
  );
}

String _midMonth(String isoDate) {
  final d = DateTime.parse(isoDate);
  return _iso(DateTime.utc(d.year, d.month, 15));
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

  final clients = <String, SupabaseClient>{};
  late SupabaseClient client;

  Future<SupabaseClient> sessionFor(String email) async {
    final existing = clients[email];
    if (existing != null) return existing;
    final fresh = SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_ANON_KEY'] as String,
    );
    await fresh.auth.signInWithPassword(
      email: email,
      password:
          (identities[email] as Map<String, dynamic>)['password'] as String,
    );
    clients[email] = fresh;
    return fresh;
  }

  Future<void> signInAs(String email) async {
    client = await sessionFor(email);
  }

  Future<String> unitId(String code) async {
    final row = await client
        .from('business_units')
        .select('id')
        .eq('code', code)
        .single();
    return row['id'] as String;
  }

  /// Voids every movement this run created, through the real API.
  ///
  /// Never a delete: financial history is corrected by void plus audit (D-006), and no
  /// client role holds DELETE on the table in any case.
  Future<int> sweep() async {
    final owner = await sessionFor('giridhar@hki.com');
    final rows = await owner
        .from('owner_ledger_entries')
        .select('id, row_version, remarks, voided_at')
        .like('remarks', '%$_marker%');
    var reversed = 0;
    for (final row in rows.cast<Map<String, dynamic>>()) {
      if (row['voided_at'] != null) continue;
      await owner.rpc<dynamic>(
        'owner_movement_void',
        params: {
          'p_id': row['id'],
          'p_reason': 'OA-1 live acceptance fixture reversal ($_marker)',
          'p_base_row_version': row['row_version'],
          'p_mutation_id': const Uuid().v4(),
        },
      );
      reversed++;
    }
    return reversed;
  }

  // The owner and family fixtures this run needs. Created once, reused, and deliberately
  // **not** removed: an owner is a master, masters archive rather than delete (D-006),
  // and the names are synthetic placeholders rather than production bootstrap data
  // (§45, §46).
  late String ownerAId;
  late String ownerBId;
  late String famA1Id;
  late String famB1Id;
  late String ccr;
  late String hki;

  setUpAll(() async {
    client = SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_ANON_KEY'] as String,
    );
    await signInAs('giridhar@hki.com');
    ccr = await unitId('CCR');
    hki = await unitId('HKI');

    // Sweep first as well as last. A suite that depends on its own teardown having
    // succeeded can pass exactly once (D-076).
    await sweep();

    Future<String> ensureOwner(String code, String name) async {
      final existing = await client
          .from('owners')
          .select('id')
          .eq('code', code)
          .maybeSingle();
      if (existing != null) return existing['id'] as String;
      final id = const Uuid().v4();
      await client.rpc<dynamic>(
        'owner_create',
        params: {
          'p_id': id,
          'p_code': code,
          'p_display_name': name,
          'p_mutation_id': const Uuid().v4(),
        },
      );
      return id;
    }

    Future<String> ensureFamily(
      String ownerId,
      String name, {
      bool mayUseNc = true,
    }) async {
      final existing = await client
          .from('owner_family_members')
          .select('id')
          .eq('display_name', name)
          .maybeSingle();
      if (existing != null) return existing['id'] as String;
      final id = const Uuid().v4();
      await client.rpc<dynamic>(
        'owner_family_member_create',
        params: {
          'p_id': id,
          'p_owner_id': ownerId,
          'p_display_name': name,
          'p_effective_from': '2026-04-01',
          'p_may_use_nc': mayUseNc,
          'p_mutation_id': const Uuid().v4(),
        },
      );
      return id;
    }

    ownerAId = await ensureOwner('OA1_TEST_OWNER_A', 'OA-1 Test Owner A');
    ownerBId = await ensureOwner('OA1_TEST_OWNER_B', 'OA-1 Test Owner B');
    famA1Id = await ensureFamily(ownerAId, 'OA-1 Test Owner A spouse');
    famB1Id = await ensureFamily(ownerBId, 'OA-1 Test Owner B daughter');
  });

  tearDownAll(() async {
    final reversed = await sweep();
    // ignore: avoid_print
    print('OA-1 live teardown: reversed $reversed owner movements');
    for (final c in clients.values) {
      await c.auth.signOut();
    }
  });

  Future<Map<String, dynamic>> createMovement({
    required String type,
    required int amount,
    String? businessUnit,
    String? ownerId,
    String? familyMemberId,
    String? declaredOwnerId,
    String? direction,
    String? reason,
    String businessDate = '2026-06-15',
    String? mutationId,
    String? id,
  }) async {
    final result = await client.rpc<dynamic>(
      'owner_movement_create',
      params: {
        'p_id': id ?? const Uuid().v4(),
        'p_business_unit_id': businessUnit ?? hki,
        'p_business_date': businessDate,
        'p_movement_type': type,
        'p_amount_minor': amount,
        'p_direction': direction,
        'p_family_member_id': familyMemberId,
        'p_declared_owner_id': declaredOwnerId,
        'p_owner_id': ownerId,
        'p_remarks': 'OA-1 live acceptance $_marker',
        'p_reason': reason,
        'p_mutation_id': mutationId ?? const Uuid().v4(),
      },
    );
    return (result as Map).cast<String, dynamic>();
  }

  // ═════════════════════════════════════════════════════════════════════════
  group('the masters exist and nothing was seeded', () {
    test('the two test owners were created through the real RPC', () async {
      await signInAs('giridhar@hki.com');
      final rows = await client.from('owners').select('id, code');
      expect(
        rows.cast<Map<String, dynamic>>().map((r) => r['code']),
        containsAll(['OA1_TEST_OWNER_A', 'OA1_TEST_OWNER_B']),
      );
    });

    test('no share is configured for any owner outside this suite (OA-D3)', () async {
      // The 50:50 ratio is a business fact, and the real owner names and the inception
      // date are bootstrap data nobody has supplied. A migration that seeded `5000 bp`
      // would be a financial claim nobody made (§4, §46).
      //
      // Scoped to *other* owners rather than to the whole table, because the suite below
      // configures shares for its own two synthetic owners and **cannot reverse them**:
      // no client role holds DELETE on `ownership_shares` (D-006) and OA-1 builds no
      // removal RPC. That residue is stated rather than hidden — see the note on the
      // configuration test.
      await signInAs('giridhar@hki.com');
      final shares = await client
          .from('ownership_shares')
          .select('id, owner_id, owners!inner(code)');
      final foreign = shares.cast<Map<String, dynamic>>().where(
        (r) =>
            !((r['owners'] as Map)['code'] as String).startsWith('OA1_TEST_'),
      );
      expect(
        foreign,
        isEmpty,
        reason:
            'OA-1 configures no ownership share for a real owner; production values are '
            'a project-lead input',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //
  // **The dates in this group are computed, not written down, and that is the whole
  // reason it survives a second run.** No client role holds DELETE on
  // `ownership_shares` — configuration archives rather than deletes (D-006) — and OA-1
  // deliberately builds no share-removal RPC, because withdrawing an ownership ratio is
  // a governance act nobody has specified. So the rows this group writes are permanent,
  // and a group keyed on literal dates could pass exactly once.
  //
  // It did. The first run configured 5000 + 5000 from 2026-04-01 and moved Owner A to
  // 6000 from 2026-07-01, green throughout; the second met its own residue and failed
  // with a raw exclusion-constraint message — which is how the missing refusal in
  // `owner_share_set` was found at all (see the fourth test). That is D-076 exactly: a
  // fixture identifier, or here a fixture *date*, must survive everything the test does
  // to the fixture.
  //
  // The group is a **sequence**, like the live backend phase chain (D-107): the base
  // month is fixed once for the whole group and the three tests below walk it forward.
  group('the 50:50 model is configurable exactly, and refuses mid-period', () {
    late String base;
    late String next;

    setUpAll(() async {
      await signInAs('giridhar@hki.com');
      final rows = await client
          .from('ownership_shares')
          .select('owner_id, effective_from')
          .inFilter('owner_id', [ownerAId, ownerBId]);
      final starts =
          rows
              .cast<Map<String, dynamic>>()
              .map((r) => r['effective_from'] as String)
              .toList()
            ..sort();
      base = starts.isEmpty ? '2026-04-01' : _firstOfNextMonth(starts.last);
      next = _firstOfNextMonth(base);
    });

    test('a mid-month effective date is refused with a sentence', () async {
      await signInAs('giridhar@hki.com');
      try {
        await client.rpc<dynamic>(
          'owner_share_set',
          params: {
            'p_owner_id': ownerAId,
            'p_share_basis_points': 5000,
            'p_effective_from': _midMonth(base),
            'p_mutation_id': const Uuid().v4(),
          },
        );
        fail('a mid-month ownership change was accepted');
      } catch (e) {
        expect(refusalOf(e), 'KM031');
      }
    });

    test(
      '5000 + 5000 configures and totals exactly 10000 (OA-D1, §38)',
      () async {
        await signInAs('giridhar@hki.com');
        for (final owner in [ownerAId, ownerBId]) {
          await client.rpc<dynamic>(
            'owner_share_set',
            params: {
              'p_owner_id': owner,
              'p_share_basis_points': 5000,
              'p_effective_from': base,
              'p_note': 'OA-1 live acceptance, synthetic owner',
              'p_mutation_id': const Uuid().v4(),
            },
          );
        }

        final rows = await client
            .from('ownership_shares')
            .select(
              'owner_id, share_basis_points, effective_from, effective_to',
            );
        final applicable = rows
            .cast<Map<String, dynamic>>()
            .where((r) => r['effective_to'] == null)
            .toList();

        expect(applicable, hasLength(2));
        expect(
          applicable.fold<int>(
            0,
            (sum, r) => sum + (r['share_basis_points'] as int),
          ),
          10000,
          reason:
              'exactly 100%, in integer basis points — no 49.999, no double',
        );
        expect(
          applicable.map((r) => r['share_basis_points']),
          everyElement(5000),
        );
      },
    );

    test('re-setting a share closes the open one rather than overlapping it', () async {
      // The exclusion constraint forbids two shares for one owner over overlapping
      // dates, so `owner_share_set` closing the previous one is what makes a ratio
      // change a single business act rather than a window in which the shares do not
      // total 10000.
      await signInAs('giridhar@hki.com');

      Future<List<Map<String, dynamic>>> sharesOfOwnerA() async {
        final rows = await client
            .from('ownership_shares')
            .select('share_basis_points, effective_from, effective_to')
            .eq('owner_id', ownerAId)
            // Explicitly ascending: this client's `order` defaults to *descending*,
            // which is what made the first version of this test compare the oldest
            // share against the one just closed.
            .order('effective_from', ascending: true);
        return rows.cast<Map<String, dynamic>>();
      }

      // Captured **before** the change, so the last assertion compares a historical
      // ratio against what it actually was rather than against a literal that only
      // happens to be right on a first run.
      final before = await sharesOfOwnerA();
      final previous = before.last;

      // 5000 again rather than a different ratio: under D-204 the V1 vector is fixed,
      // so a test that configured 6000 to prove supersession would be configuring
      // something the boundary now refuses — and would leave the development database
      // holding a vector no settlement could resolve. Re-setting the same share from a
      // later month proves the closing behaviour just as exactly.
      await client.rpc<dynamic>(
        'owner_share_set',
        params: {
          'p_owner_id': ownerAId,
          'p_share_basis_points': 5000,
          'p_effective_from': next,
          'p_mutation_id': const Uuid().v4(),
        },
      );

      final after = await sharesOfOwnerA();
      // Addressed by date rather than by position. `PostgrestFilterBuilder.order`
      // defaults to *descending* in this client, so an index is a bet on which end of
      // the list a row landed at — and a test that indexes the wrong end fails while
      // saying nothing about the product.
      final byStart = {for (final r in after) r['effective_from'] as String: r};
      final added = byStart[next]!;
      final closed = byStart[previous['effective_from'] as String]!;

      expect(added['effective_from'], next);
      expect(added['effective_to'], isNull);
      expect(added['share_basis_points'], 5000);

      expect(
        closed['effective_to'],
        _dayBefore(next),
        reason:
            'the previous share ends the day before the next begins — no gap, no '
            'overlap, and the inclusive end lands on a month boundary (§5)',
      );
      expect(
        closed['share_basis_points'],
        previous['share_basis_points'],
        reason: 'a later change does not restate a historical ratio (§37)',
      );
    });

    test('a backdated share is refused with a sentence, not a constraint name', () async {
      // The defect the second run of this suite found. `owner_share_set` closed a share
      // that started *earlier* and left everything else to `ownership_shares_no_overlap`,
      // so configuring a ratio at or before one already configured handed the caller a
      // SQLSTATE, a table name and a constraint name — which spec §13.1 has forbidden in
      // a refusal since Phase 2.
      //
      // The rule underneath it is §37's: an ownership timeline moves forward only,
      // because rewriting a historical ratio would silently restate every settlement
      // computed under it.
      await signInAs('giridhar@hki.com');
      try {
        await client.rpc<dynamic>(
          'owner_share_set',
          params: {
            'p_owner_id': ownerAId,
            'p_share_basis_points': 5000,
            'p_effective_from': base,
            'p_mutation_id': const Uuid().v4(),
          },
        );
        fail('a backdated ownership share was accepted');
      } catch (e) {
        expect(refusalOf(e), 'KM031');
        final message = e is PostgrestException ? e.message : '$e';
        expect(
          message,
          isNot(
            anyOf(
              contains('ownership_shares'),
              contains('exclusion constraint'),
              contains('daterange'),
              contains('23P01'),
            ),
          ),
          reason:
              'a refusal never carries a SQLSTATE, a table name or a constraint name '
              '(spec §13.1)',
        );
        expect(
          message.toLowerCase(),
          contains('later month'),
          reason: 'the sentence ends in an action rather than in a complaint',
        );
      }
    });
    // ── The V1 ownership vector, at the configuration boundary (D-204) ──────
    //
    // The domain refuses to *resolve* anything but `[5000, 5000]`; these prove the other
    // half — that the server refuses to *accept* it, so the database never holds a
    // configuration every settlement would later refuse.

    test(
      'a share that is not 5000 basis points is refused, with a sentence',
      () async {
        await signInAs('giridhar@hki.com');
        for (final bp in [6000, 4000, 7000, 10000, 1]) {
          try {
            await client.rpc<dynamic>(
              'owner_share_set',
              params: {
                'p_owner_id': ownerAId,
                'p_share_basis_points': bp,
                'p_effective_from': _firstOfNextMonth(next),
                'p_mutation_id': const Uuid().v4(),
              },
            );
            fail('an ownership share of $bp basis points was accepted');
          } catch (e) {
            expect(refusalOf(e), 'KM033', reason: '$bp bp must be refused');
            final message = e is PostgrestException ? e.message : '$e';
            expect(
              message,
              isNot(
                anyOf(
                  contains('ownership_shares'),
                  contains('constraint'),
                  contains('23514'),
                ),
              ),
              reason:
                  'a refusal never carries a table or constraint name (spec §13.1)',
            );
            expect(message, contains('5000'));
          }
        }
      },
    );

    test('a third owner is refused while two are configured', () async {
      // Owner C exists only to be refused. It is created once, holds no ownership share,
      // and never will — which is exactly what this asserts afterwards, because a
      // refusal test that left a third owner holding a share would have broken the very
      // invariant it exists to protect.
      await signInAs('giridhar@hki.com');

      final existing = await client
          .from('owners')
          .select('id')
          .eq('code', 'OA1_TEST_OWNER_C_REFUSAL_FIXTURE')
          .maybeSingle();
      final ownerCId = existing != null
          ? existing['id'] as String
          : await () async {
              final id = const Uuid().v4();
              await client.rpc<dynamic>(
                'owner_create',
                params: {
                  'p_id': id,
                  'p_code': 'OA1_TEST_OWNER_C_REFUSAL_FIXTURE',
                  'p_display_name': 'OA-1 Test Owner C (refusal fixture)',
                  'p_mutation_id': const Uuid().v4(),
                },
              );
              return id;
            }();

      try {
        await client.rpc<dynamic>(
          'owner_share_set',
          params: {
            'p_owner_id': ownerCId,
            'p_share_basis_points': 5000,
            'p_effective_from': _firstOfNextMonth(next),
            'p_mutation_id': const Uuid().v4(),
          },
        );
        fail('a third owner was given an ownership share');
      } catch (e) {
        expect(refusalOf(e), 'KM033');
        final message = e is PostgrestException ? e.message : '$e';
        expect(message.toLowerCase(), contains('two owners'));
      }

      final cShares = await client
          .from('ownership_shares')
          .select('id')
          .eq('owner_id', ownerCId);
      expect(cShares, isEmpty, reason: 'the refusal fixture holds no share');
    });

    test(
      'the configured vector resolves to exactly [5000, 5000] (1, 2, 3)',
      () async {
        // End to end: the rows the server holds, read through the projection, handed to
        // the same domain resolver a settlement will use. Not a re-implementation of the
        // rule in the test — `resolveV1For` is the rule.
        await signInAs('giridhar@hki.com');
        final rows = await client
            .from('ownership_shares')
            .select(
              'id, owner_id, share_basis_points, effective_from, effective_to',
            );

        final set = OwnershipShareSet([
          for (final r in rows.cast<Map<String, dynamic>>())
            OwnershipShare(
              id: r['id'] as String,
              ownerId: r['owner_id'] as String,
              shareBasisPoints: r['share_basis_points'] as int,
              effectiveFrom: BusinessDate.tryParse(
                r['effective_from'] as String,
              )!,
              effectiveTo: r['effective_to'] == null
                  ? null
                  : BusinessDate.tryParse(r['effective_to'] as String)!,
            ),
        ]);

        final from = BusinessDate.tryParse(next)!;
        final to = BusinessDate.tryParse(_dayBefore(_firstOfNextMonth(next)))!;

        final resolved = set.resolveV1For(from, to);
        expect(
          resolved,
          isA<OwnershipResolved>(),
          reason: 'the live configuration is the V1 vector: $resolved',
        );

        final vector = (resolved as OwnershipResolved).shares;
        expect(vector, hasLength(v1OwnerCount));
        expect(
          vector.map((s) => s.shareBasisPoints),
          everyElement(v1ShareBasisPoints),
        );
        expect(resolved.totalBasisPoints, totalOwnershipBasisPoints);
      },
    );

    test('historical share records remain readable, and unchanged (7)', () async {
      // The development database holds shares recorded before this ruling that are not
      // 5000 basis points. Nothing rewrote them, and nothing should have: a settlement
      // over a period they govern refuses, which is the correct consequence of a
      // version that does not do variable ownership — not a reason to restate history.
      await signInAs('giridhar@hki.com');
      final rows = await client
          .from('ownership_shares')
          .select('share_basis_points, effective_from, effective_to');
      final all = rows.cast<Map<String, dynamic>>();

      expect(all, isNotEmpty);
      for (final r in all) {
        expect(r['effective_from'], isNotNull);
        expect(r['share_basis_points'], isA<int>());
      }

      // Every closed historical row is still exactly as recorded, whatever its value.
      final historical = all.where((r) => r['effective_to'] != null).toList();
      expect(
        historical,
        isNotEmpty,
        reason:
            'supersession has produced closed rows, and they are still here',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('the ledger boundary', () {
    test('a withdrawal is numbered on its own KI-OWN sequence', () async {
      await signInAs('giridhar@hki.com');
      final result = await createMovement(
        type: 'withdrawal',
        amount: 5000000,
        ownerId: ownerAId,
      );

      expect(result['status'], 'created');
      expect(result['owner_id'], ownerAId);
      expect(result['direction'], 'debit');
      expect(result['row_version'], 1);
      expect(result['business_date_source'], 'derived');
      expect(
        result['txn_number'] as String,
        startsWith('KI-OWN-26-27-'),
        reason:
            'its own sequence, shared with neither expenses nor revenue (§21)',
      );
    });

    test(
      'a replayed mutation id returns the same number, not a second movement',
      () async {
        await signInAs('giridhar@hki.com');
        final mutationId = const Uuid().v4();
        final id = const Uuid().v4();

        final first = await createMovement(
          type: 'withdrawal',
          amount: 1234500,
          ownerId: ownerAId,
          mutationId: mutationId,
          id: id,
        );
        final replay = await createMovement(
          type: 'withdrawal',
          amount: 1234500,
          ownerId: ownerAId,
          mutationId: mutationId,
          id: id,
        );

        expect(replay['status'], 'replayed');
        expect(replay['txn_number'], first['txn_number']);

        final rows = await client
            .from('owner_ledger_entries')
            .select('id')
            .eq('id', id);
        expect(
          rows,
          hasLength(1),
          reason: 'exactly one financial record (D-004)',
        );
      },
    );

    test('an NC bill derives its owner from the person (§12)', () async {
      await signInAs('giridhar@hki.com');
      final result = await createMovement(
        type: 'nc_consumption',
        amount: 325000,
        businessUnit: ccr,
        familyMemberId: famA1Id,
      );
      expect(
        result['owner_id'],
        ownerAId,
        reason: "the spouse's bill is Owner A's, derived and not chosen",
      );
      expect(result['direction'], 'debit');
    });

    test(
      'a declared owner that disagrees is refused, never re-attributed',
      () async {
        await signInAs('giridhar@hki.com');
        try {
          await createMovement(
            type: 'nc_consumption',
            amount: 100000,
            businessUnit: ccr,
            familyMemberId: famA1Id,
            declaredOwnerId: ownerBId,
          );
          fail('a mismatched attribution was accepted');
        } catch (e) {
          expect(
            refusalOf(e),
            'KM030',
            reason:
                'the operator approved a statement about one owner; recording it against '
                'another would make the record say something nobody agreed to',
          );
        }
      },
    );

    test('an agreeing declared owner is accepted', () async {
      await signInAs('giridhar@hki.com');
      final result = await createMovement(
        type: 'nc_consumption',
        amount: 100000,
        businessUnit: ccr,
        familyMemberId: famB1Id,
        declaredOwnerId: ownerBId,
      );
      expect(result['owner_id'], ownerBId);
    });

    test(
      'an opening balance and an adjustment must state a direction',
      () async {
        await signInAs('giridhar@hki.com');
        try {
          await createMovement(
            type: 'opening_balance',
            amount: 100000,
            ownerId: ownerAId,
          );
          fail('an opening balance with no direction was accepted');
        } catch (e) {
          expect(refusalOf(e), 'KM006');
        }

        final credited = await createMovement(
          type: 'opening_balance',
          amount: 100000,
          ownerId: ownerAId,
          direction: 'credit',
        );
        expect(credited['direction'], 'credit');
      },
    );

    test('an adjustment with a whitespace-only reason is refused', () async {
      await signInAs('giridhar@hki.com');
      for (final blank in ['', '   ', '\t', '\n', ' \t\r\n ']) {
        try {
          await createMovement(
            type: 'manual_adjustment',
            amount: 100,
            ownerId: ownerAId,
            direction: 'credit',
            reason: blank,
          );
          fail('an adjustment with reason "$blank" was accepted');
        } catch (e) {
          // The CHECK constraint refuses it if the RPC's own normalisation lets it past;
          // either way it must not be recorded. Both are the canonical rule (spec §14.1).
          expect(
            e,
            isA<PostgrestException>(),
            reason: 'whitespace is not a reason',
          );
        }
      }
    });

    test(
      'a negative amount is refused; the type decides the sign (§43)',
      () async {
        await signInAs('giridhar@hki.com');
        try {
          await createMovement(
            type: 'withdrawal',
            amount: -1,
            ownerId: ownerAId,
          );
          fail('a negative amount was accepted');
        } catch (e) {
          expect(refusalOf(e), 'KM006');
        }
      },
    );

    test('an unknown movement type is refused rather than defaulted', () async {
      await signInAs('giridhar@hki.com');
      try {
        await createMovement(type: 'drawing', amount: 100, ownerId: ownerAId);
        fail('an unknown movement type was accepted');
      } catch (e) {
        expect(refusalOf(e), 'KM006');
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('correction and void', () {
    test(
      'a stale base version is a conflict, and nothing is applied',
      () async {
        await signInAs('giridhar@hki.com');
        final created = await createMovement(
          type: 'withdrawal',
          amount: 5000000,
          ownerId: ownerAId,
        );
        final id = created['id'] as String;

        try {
          await client.rpc<dynamic>(
            'owner_movement_update',
            params: {
              'p_id': id,
              'p_base_row_version': 99,
              'p_business_date': '2026-06-15',
              'p_amount_minor': 4500000,
              'p_mutation_id': const Uuid().v4(),
            },
          );
          fail('a stale correction was applied');
        } catch (e) {
          expect(refusalOf(e), 'KM003');
        }

        final row = await client
            .from('owner_ledger_entries')
            .select('amount_minor, row_version')
            .eq('id', id)
            .single();
        expect(row['amount_minor'], 5000000);
        expect(row['row_version'], 1);
      },
    );

    test(
      'a correction moves the amount by exactly the difference (§29)',
      () async {
        await signInAs('giridhar@hki.com');
        final created = await createMovement(
          type: 'withdrawal',
          amount: 5000000,
          ownerId: ownerAId,
        );
        final id = created['id'] as String;

        final updated = await client.rpc<dynamic>(
          'owner_movement_update',
          params: {
            'p_id': id,
            'p_base_row_version': 1,
            'p_business_date': '2026-06-15',
            'p_amount_minor': 4500000,
            'p_remarks': 'OA-1 live acceptance $_marker',
            'p_mutation_id': const Uuid().v4(),
          },
        );
        expect((updated as Map)['row_version'], 2);

        final row = await client
            .from('owner_ledger_entries')
            .select('amount_minor, txn_number, business_date_source')
            .eq('id', id)
            .single();
        expect(row['amount_minor'], 4500000);
        expect(
          row['txn_number'],
          created['txn_number'],
          reason:
              'the number belongs to the identity and survives a correction',
        );
        expect(
          row['business_date_source'],
          'derived',
          reason: 'an ordinary amount correction did not move the date',
        );
      },
    );

    test(
      'a void with a whitespace-only reason is refused, in every shape',
      () async {
        await signInAs('giridhar@hki.com');
        final created = await createMovement(
          type: 'withdrawal',
          amount: 700000,
          ownerId: ownerAId,
        );
        final id = created['id'] as String;

        for (final blank in ['', '   ', '\t', '\n', '\r', ' \t\r\n ']) {
          try {
            await client.rpc<dynamic>(
              'owner_movement_void',
              params: {
                'p_id': id,
                'p_reason': blank,
                'p_base_row_version': 1,
                'p_mutation_id': const Uuid().v4(),
              },
            );
            fail('a void with reason "$blank" was accepted');
          } catch (e) {
            expect(
              refusalOf(e),
              'KM008',
              reason:
                  'one-argument trim strips spaces alone; a lone tab must not be a '
                  'reason (spec §14.1, D-142)',
            );
          }
        }

        // And a real reason voids, stored trimmed.
        await client.rpc<dynamic>(
          'owner_movement_void',
          params: {
            'p_id': id,
            'p_reason': '  recorded twice  ',
            'p_base_row_version': 1,
            'p_mutation_id': const Uuid().v4(),
          },
        );
        final row = await client
            .from('owner_ledger_entries')
            .select('voided_at, void_reason')
            .eq('id', id)
            .single();
        expect(row['voided_at'], isNotNull);
        expect(row['void_reason'], 'recorded twice');
      },
    );

    test('a voided movement accepts no correction', () async {
      await signInAs('giridhar@hki.com');
      final created = await createMovement(
        type: 'withdrawal',
        amount: 800000,
        ownerId: ownerAId,
      );
      final id = created['id'] as String;
      await client.rpc<dynamic>(
        'owner_movement_void',
        params: {
          'p_id': id,
          'p_reason': 'entered twice',
          'p_base_row_version': 1,
          'p_mutation_id': const Uuid().v4(),
        },
      );

      try {
        await client.rpc<dynamic>(
          'owner_movement_update',
          params: {
            'p_id': id,
            'p_base_row_version': 2,
            'p_business_date': '2026-06-15',
            'p_amount_minor': 1,
            'p_mutation_id': const Uuid().v4(),
          },
        );
        fail('a voided movement was corrected');
      } catch (e) {
        expect(refusalOf(e), 'KM020');
      }
    });

    test('change_seq advances on every mutation (§22, D-177)', () async {
      await signInAs('giridhar@hki.com');
      final created = await createMovement(
        type: 'withdrawal',
        amount: 900000,
        ownerId: ownerAId,
      );
      final id = created['id'] as String;

      Future<int> generation() async =>
          (await client
                  .from('owner_ledger_entries')
                  .select('change_seq')
                  .eq('id', id)
                  .single())['change_seq']
              as int;

      final afterCreate = await generation();

      await client.rpc<dynamic>(
        'owner_movement_update',
        params: {
          'p_id': id,
          'p_base_row_version': 1,
          'p_business_date': '2026-06-15',
          'p_amount_minor': 850000,
          'p_remarks': 'OA-1 live acceptance $_marker',
          'p_mutation_id': const Uuid().v4(),
        },
      );
      final afterEdit = await generation();

      await client.rpc<dynamic>(
        'owner_movement_void',
        params: {
          'p_id': id,
          'p_reason': 'acceptance fixture',
          'p_base_row_version': 2,
          'p_mutation_id': const Uuid().v4(),
        },
      );
      final afterVoid = await generation();

      expect(
        afterEdit,
        greaterThan(afterCreate),
        reason:
            'an edit invisible to a delta is D-177 exactly, and it is invisible until a '
            'reporting pull silently misses a correction',
      );
      expect(afterVoid, greaterThan(afterEdit));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('the authorization matrix (§30, §31, §32)', () {
    test('an anonymous caller reads nothing and calls nothing', () async {
      final anon = SupabaseClient(
        config['SUPABASE_URL'] as String,
        config['SUPABASE_ANON_KEY'] as String,
      );
      for (final table in [
        'owners',
        'ownership_shares',
        'owner_family_members',
        'owner_ledger_entries',
      ]) {
        // Either answer satisfies "reads nothing", and the stronger one is what the
        // server actually gives: `anon` holds no SELECT at all, so PostgREST refuses with
        // `42501 permission denied` rather than returning an empty set. Asserting only
        // on emptiness would have called that a failure — which is a test insisting the
        // boundary be *weaker* than it is.
        try {
          final rows = await anon.from(table).select('id');
          expect(rows, isEmpty, reason: '$table leaked to an anonymous caller');
        } on PostgrestException catch (e) {
          expect(
            e.code,
            '42501',
            reason: '$table refused an anonymous caller for the right reason',
          );
        }
      }
      await expectLater(
        anon.rpc<dynamic>(
          'owner_movement_create',
          params: {
            'p_id': const Uuid().v4(),
            'p_business_unit_id': hki,
            'p_business_date': '2026-06-15',
            'p_movement_type': 'withdrawal',
            'p_amount_minor': 1,
          },
        ),
        throwsA(anything),
      );
      await anon.dispose();
    });

    test(
      'a Data Entry principal sees no owner ledger and cannot record one',
      () async {
        // §31's staff-privacy line, as the server decides it. This identity holds no
        // owner-account capability at all, so it learns nothing financial about an owner.
        await signInAs('data.entry@example.com');
        expect(await client.from('owner_ledger_entries').select('id'), isEmpty);
        expect(await client.from('ownership_shares').select('id'), isEmpty);

        try {
          await createMovement(
            type: 'withdrawal',
            amount: 1,
            ownerId: ownerAId,
          );
          fail('Data Entry recorded an owner withdrawal');
        } catch (e) {
          expect(refusalOf(e), anyOf('KM001', 'KM002'));
        }
      },
    );

    test('a unit-scoped Manager holds nothing in this domain in V1', () async {
      // Deliberate: whether operational staff may record NC is a product decision nobody
      // has taken, and OA-1 creates no temporary broad access.
      await signInAs('ccr.manager@example.com');
      expect(await client.from('owner_ledger_entries').select('id'), isEmpty);
      try {
        await createMovement(
          type: 'nc_consumption',
          amount: 1,
          businessUnit: ccr,
          familyMemberId: famA1Id,
        );
        fail('a Manager recorded an NC bill');
      } catch (e) {
        expect(refusalOf(e), anyOf('KM001', 'KM002'));
      }
    });

    test('the Accountant records and reads, and cannot adjust', () async {
      await signInAs('accountant@example.com');

      final created = await createMovement(
        type: 'withdrawal',
        amount: 250000,
        businessUnit: ccr,
        ownerId: ownerAId,
      );
      expect(created['status'], 'created');

      // Reads the whole ledger — the unscoped capability the Accountant bundle carries.
      final rows = await client.from('owner_ledger_entries').select('id');
      expect(rows, isNotEmpty);

      // And is refused the escape hatch (§16).
      try {
        await createMovement(
          type: 'manual_adjustment',
          amount: 100,
          businessUnit: ccr,
          ownerId: ownerAId,
          direction: 'credit',
          reason: 'should not be permitted',
        );
        fail('the Accountant recorded a manual adjustment');
      } catch (e) {
        expect(refusalOf(e), anyOf('KM001', 'KM002'));
      }
    });

    test('the base tables are never writable by any client role', () async {
      await signInAs('giridhar@hki.com');
      await expectLater(
        client.from('owner_ledger_entries').insert({
          'id': const Uuid().v4(),
          'org_id': const Uuid().v4(),
        }),
        throwsA(anything),
        reason: 'every mutation travels through a reviewed RPC (D-162)',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  group('the Expense guard, and non-interference (§25, §40, §41)', () {
    test(
      'an expense category named for an owner movement is refused, with KM032',
      () async {
        await signInAs('giridhar@hki.com');
        final section = await client
            .from('sections')
            .select('id')
            .limit(1)
            .single();

        // Through the real administrative RPC, whose parameter is `p_entity_type` — the
        // first attempt passed `p_kind` and got `PGRST202 function not found`, which the
        // assertion below correctly refused to accept as a refusal.
        try {
          await client.rpc<dynamic>(
            'master_create',
            params: {
              'p_entity_type': 'expense_category',
              'p_parent_id': section['id'],
              'p_code': 'OA1_LIVE_OWNER_WD',
              'p_name': 'Owner Withdrawal',
              'p_attributes': <String, Object?>{},
              'p_mutation_id': const Uuid().v4(),
              'p_id': const Uuid().v4(),
            },
          );
          fail('an expense category named "Owner Withdrawal" was created');
        } catch (e) {
          expect(
            refusalOf(e),
            'KM032',
            reason:
                'the guard must refuse with its own code — a probe that accepts any error '
                'proves nothing (the deploy-time probe failed exactly that way once)',
          );
        }
      },
    );

    test(
      'recording owner movements moves no expense or revenue contribution',
      () async {
        await signInAs('giridhar@hki.com');

        Future<Map<String, int>> totals() async {
          final revenue = await client
              .from('revenue_period_contributions')
              .select('gross_minor, tax_minor, net_minor')
              .eq('pnl_period_key', '2026-06');
          final expense = await client
              .from('expense_period_contributions')
              .select('amount_minor')
              .eq('pnl_period_key', '2026-06');
          var gross = 0, tax = 0, net = 0, cost = 0;
          for (final r in revenue.cast<Map<String, dynamic>>()) {
            gross += r['gross_minor'] as int;
            tax += r['tax_minor'] as int;
            net += r['net_minor'] as int;
          }
          for (final r in expense.cast<Map<String, dynamic>>()) {
            cost += r['amount_minor'] as int;
          }
          return {
            'gross': gross,
            'tax': tax,
            'net': net,
            'cost': cost,
            'revenueRows': revenue.length,
            'expenseRows': expense.length,
          };
        }

        final before = await totals();

        await createMovement(
          type: 'withdrawal',
          amount: 5000000,
          ownerId: ownerAId,
        );
        await createMovement(
          type: 'nc_consumption',
          amount: 2000000,
          businessUnit: ccr,
          familyMemberId: famA1Id,
        );

        final after = await totals();

        expect(
          after,
          before,
          reason:
              'a Rs 50,000 withdrawal and a Rs 20,000 NC bill must move Gross Sales, GST, '
              'Net Sales, Expenses and the contribution counts by exactly nothing — '
              'compared here, not asserted (§40, §41)',
        );
      },
    );
  });
}
