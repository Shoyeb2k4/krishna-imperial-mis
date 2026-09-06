/// The revenue server boundary, against the real `krishna-mis-dev` project.
///
/// Skipped unless `KRISHNA_DEV_IDENTITIES` points at the development identity file, so an
/// ordinary `flutter test` run stays hermetic and offline. Nothing here prints a password,
/// a token or the API key.
///
/// The centrepiece is the **two-session write-skew test** (D-095). A validating trigger
/// checks rows visible to its own transaction, so two concurrent writers can each be
/// individually valid while their pair is ambiguous. That cannot be demonstrated from one
/// session, and this suite does not pretend otherwise: it fires two genuine concurrent
/// PostgREST calls, each of which is its own backend transaction, and asserts the
/// invariant that must hold however they interleave.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:krishna_mis/domain/tax/tax_rule.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

import '../support/revenue_parity_vectors.dart';

const _identitiesVar = 'KRISHNA_DEV_IDENTITIES';

/// The refusal code carried in a `PostgrestException`, which the server sets as SQLSTATE.
String? refusalOf(Object? error) =>
    error is PostgrestException ? error.code : null;

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

  Future<SupabaseClient> sessionFor(String email, {String? tag}) async {
    final key = tag == null ? email : '$email#$tag';
    final existing = clients[key];
    if (existing != null) return existing;
    final fresh = SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_ANON_KEY'] as String,
    );
    final entry = identities[email] as Map<String, dynamic>;
    await fresh.auth.signInWithPassword(
      email: email,
      password: entry['password'] as String,
    );
    clients[key] = fresh;
    return fresh;
  }

  Future<void> signInAs(String email) async {
    client = await sessionFor(email);
  }

  Future<String> categoryId(String unitCode, String categoryCode) async {
    final unit = await client
        .from('business_units')
        .select('id')
        .eq('code', unitCode)
        .single();
    final category = await client
        .from('revenue_categories')
        .select('id')
        .eq('code', categoryCode)
        .eq('business_unit_id', unit['id'] as String)
        .single();
    return category['id'] as String;
  }

  /// Archives a rule, so a test leaves the baseline as it found it.
  Future<void> archive(SupabaseClient c, String ruleId) async {
    final row = await c
        .from('revenue_tax_rates')
        .select('row_version')
        .eq('id', ruleId)
        .maybeSingle();
    if (row == null) return;
    await c.rpc<dynamic>(
      'tax_rule_archive',
      params: {
        'p_rule_id': ruleId,
        'p_base_row_version': row['row_version'],
        'p_mutation_id': const Uuid().v4(),
      },
    );
  }

  setUpAll(() async {
    client = SupabaseClient(
      config['SUPABASE_URL'] as String,
      config['SUPABASE_ANON_KEY'] as String,
    );
  });

  group('the verified FY 2026-27 baseline', () {
    setUp(() => signInAs('giridhar@hki.com'));

    test(
      'is exactly four rules, one per category, with no speculative data',
      () async {
        final rules = await client
            .from('revenue_tax_rates')
            .select(
              'rate_bp, treatment, input_basis, effective_from, '
              'value_band_id, supply_subtype_id, premises_status_code, '
              'revenue_categories(code, business_units(code))',
            )
            .isFilter('archived_at', null);

        expect(rules, hasLength(4));

        final byCategory = {
          for (final r in rules)
            ((r['revenue_categories'] as Map)['code'] as String): r,
        };

        expect(
          byCategory.keys,
          containsAll(['RESTAURANT', 'NANDBHOG', 'ROOM', 'BANQUET']),
        );

        for (final entry in byCategory.entries) {
          final rule = entry.value;
          expect(
            rule['effective_from'],
            '2026-04-01',
            reason: '${entry.key} must take effect on the confirmed date',
          );
          expect(
            rule['input_basis'],
            'inclusive_total',
            reason: '${entry.key} records the customer-billed total (D-090)',
          );
          // No band, subtype or premises status is invented for any category.
          expect(rule['value_band_id'], isNull);
          expect(rule['supply_subtype_id'], isNull);
          expect(rule['premises_status_code'], isNull);
        }

        expect(byCategory['RESTAURANT']!['rate_bp'], 500);
        expect(byCategory['RESTAURANT']!['treatment'], 'inclusive');
        expect(byCategory['NANDBHOG']!['rate_bp'], 500);
        expect(byCategory['ROOM']!['rate_bp'], 500);

        // Banquet is untaxed, and there is no dormant 5% alternative (D-091).
        expect(byCategory['BANQUET']!['treatment'], 'none');
        expect(byCategory['BANQUET']!['rate_bp'], 0);
      },
    );

    test('Restaurant and Nandbhog are two independent rows', () async {
      final restaurant = await categoryId('CCR', 'RESTAURANT');
      final nandbhog = await categoryId('CCR', 'NANDBHOG');

      final rules = await client
          .from('revenue_tax_rates')
          .select('id, revenue_category_id')
          .isFilter('archived_at', null)
          .inFilter('revenue_category_id', [restaurant, nandbhog]);

      expect(rules, hasLength(2));
      expect(
        (rules[0]['id'] as String) != (rules[1]['id'] as String),
        isTrue,
        reason: 'neither references nor inherits from the other (D-089)',
      );
    });

    test('no band, subtype or premises status exists anywhere', () async {
      for (final table in const [
        'revenue_value_bands',
        'revenue_supply_subtypes',
        'business_unit_tax_statuses',
      ]) {
        final rows = await client.from(table).select('id');
        expect(rows, isEmpty, reason: '$table must ship empty');
      }
    });
  });

  group('the security boundary', () {
    test('an unassigned user enumerates nothing', () async {
      await signInAs('unassigned@example.com');

      final entries = await client.from('revenue_document').select('id');
      final components = await client
          .from('revenue_component_detail')
          .select('id');

      expect(entries, isEmpty);
      expect(components, isEmpty);
    });

    test('a scoped manager sees only their own property', () async {
      await signInAs('ccr.manager@example.com');

      final ccr = await client
          .from('business_units')
          .select('id')
          .eq('code', 'CCR')
          .single();
      // A view carries no foreign-key metadata, so the unit is compared by id rather
      // than through an embedded resource.
      final entries = await client
          .from('revenue_document')
          .select('business_unit_id');

      for (final e in entries) {
        expect(
          e['business_unit_id'],
          ccr['id'],
          reason:
              'a Crystal Canopy manager must not receive Hotel Krishna revenue',
        );
      }
      expect(ccr['id'], isNotNull);
    });

    test('base tables are not the authenticated API', () async {
      await signInAs('giridhar@hki.com');

      // `revenue_entries` and `revenue_components` carry no grant at all: reads go
      // through the projection. This is the D-062 boundary, restated for revenue.
      await expectLater(
        client.from('revenue_entries').select('id'),
        throwsA(
          predicate(
            (e) => e is PostgrestException && e.code == '42501',
            'permission denied',
          ),
        ),
      );
      await expectLater(
        client.from('revenue_components').select('id'),
        throwsA(predicate((e) => e is PostgrestException && e.code == '42501')),
      );
    });

    test('no revenue function is reachable by anon', () async {
      final anon = SupabaseClient(
        config['SUPABASE_URL'] as String,
        config['SUPABASE_ANON_KEY'] as String,
      );
      await expectLater(
        anon.rpc<dynamic>(
          'revenue_create',
          params: {
            'p_id': const Uuid().v7(),
            'p_business_unit_id': const Uuid().v4(),
            'p_revenue_category_id': const Uuid().v4(),
            'p_business_date': '2026-06-15',
            'p_components': <dynamic>[],
          },
        ),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('server tax resolution refuses rather than guessing', () {
    late String restaurant;

    setUp(() async {
      await signInAs('giridhar@hki.com');
      restaurant = await categoryId('CCR', 'RESTAURANT');
    });

    test('a date before the baseline has no applicable rule', () async {
      // Not a zero rate, and not an exemption — a gap (D-084).
      await expectLater(
        client.rpc<dynamic>(
          'revenue_create',
          params: {
            'p_id': const Uuid().v7(),
            'p_business_unit_id': await categoryId('CCR', 'RESTAURANT').then((
              _,
            ) async {
              final u = await client
                  .from('business_units')
                  .select('id')
                  .eq('code', 'CCR')
                  .single();
              return u['id'];
            }),
            'p_revenue_category_id': restaurant,
            'p_business_date': '2026-03-31',
            'p_components': [
              {'entered_amount_minor': 10000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        ),
        throwsA(
          predicate((e) => refusalOf(e) == 'KM027', 'refused with no_tax_rule'),
        ),
      );
    });
  });

  group('three engines, one specification, exact paise (B9, B10)', () {
    setUp(() => signInAs('giridhar@hki.com'));

    test('the verified rules are stored in the form the client parses', () async {
      // The defect this pins, found by writing the Slice 5 suite: the adapter parsed
      // `EnteredBasis.name` (`inclusiveTotal`) while both schemas store `inclusive_total`,
      // so every rule carrying a basis would have thrown on read. A round trip through the
      // real column is the only thing that proves the two forms agree — a Dart-only test
      // would have been checking Dart against itself.
      final rules = await client
          .from('revenue_tax_rates')
          .select('input_basis, treatment')
          .isFilter('archived_at', null);

      expect(rules, hasLength(4));

      for (final rule in rules) {
        final basis = rule['input_basis'] as String?;
        expect(
          basis,
          isNotNull,
          reason:
              'A1: a rule with no basis is unusable and can no longer be created',
        );
        expect(
          () => EnteredBasis.fromName(basis!),
          returnsNormally,
          reason: 'the client must read what the server stores; got "$basis"',
        );
        expect(
          () => TaxTreatment.fromName(rule['treatment'] as String),
          returnsNormally,
        );
      }
    });

    test('Dart reproduces the server figures for every verified rule', () async {
      // The server side of parity is asserted inside
      // `20260901144002_revenue_arithmetic_parity.sql`, which fails the deploy rather than
      // warning — the D-067 pattern. This is the other half: the same vectors, through the
      // Dart engine, against rules read from the real database rather than from a fixture.
      expect(File(revenueParityMigration).existsSync(), isTrue);

      final rules = await client
          .from('revenue_tax_rates')
          .select('rate_bp, treatment, input_basis')
          .isFilter('archived_at', null);

      final vectors = readArithmeticVectors();
      var checked = 0;

      for (final rule in rules) {
        final rateBp = rule['rate_bp'] as int;
        final treatment = TaxTreatment.fromName(rule['treatment'] as String);
        final basis = EnteredBasis.fromName(rule['input_basis'] as String);

        for (final v in vectors.where(
          (v) => v.rateBp == rateBp && v.treatment == treatment,
        )) {
          final dart = TaxRule(
            id: 'parity',
            revenueCategoryId: 'parity',
            rateBasisPoints: rateBp,
            treatment: treatment,
            effectiveFrom: vDate('2026-04-01'),
            inputBasis: basis,
          ).compute(Money.fromPaise(v.entered));

          expect(dart.gross.paise, v.gross, reason: '$v');
          expect(dart.tax.paise, v.tax, reason: '$v');
          expect(dart.net.paise, v.net, reason: '$v');
          checked++;
        }
      }

      expect(
        checked,
        greaterThan(0),
        reason:
            'no vector matched any live rule — the parity table and the configured rules '
            'have drifted apart, and a suite that silently checks nothing reports success',
      );
    });
  });

  group('two sessions cannot jointly create an ambiguous rule set (D-095)', () {
    // The test the brief calls mandatory. Each RPC call below is a separate PostgREST
    // request and therefore a separate backend transaction: genuine concurrency, not a
    // simulation.
    late SupabaseClient sessionA;
    late SupabaseClient sessionB;
    late String category;
    late String baselineRuleId;

    setUp(() async {
      sessionA = await sessionFor('giridhar@hki.com', tag: 'A');
      sessionB = await sessionFor('giridhar@hki.com', tag: 'B');
      client = sessionA;
      category = await categoryId('CCR', 'RESTAURANT');

      // Free a window so the two contenders are valid against the committed state on
      // their own. The baseline rule is open-ended, so it must be end-dated first —
      // which is itself the correct way to introduce a successor.
      final baseline = await sessionA
          .from('revenue_tax_rates')
          .select('id')
          .eq('revenue_category_id', category)
          .isFilter('archived_at', null)
          .eq('effective_from', '2026-04-01')
          .single();
      baselineRuleId = baseline['id'] as String;
      await sessionA.rpc<dynamic>(
        'revenue_tax_rule_end_date',
        params: {
          'p_rule_id': baselineRuleId,
          'p_effective_to': '2027-04-01',
          'p_mutation_id': const Uuid().v4(),
        },
      );
    });

    tearDown(() async {
      // Put the baseline back exactly as the migration installed it: archive anything
      // this test created, then restore the open-ended effective_to.
      //
      // Archive rather than delete, and not for tidiness: no client role holds DELETE on
      // financial configuration (D-006), so this is the strongest reversal the real API
      // offers — which is the correct trade. The consequence is that archived scaffolding
      // accumulates in the development project across runs, so **no assertion anywhere may
      // read `revenue_tax_rates` without filtering `archived_at`**. One did (the live
      // backend suite's phase-a), and it failed for that reason rather than for a defect.
      // Clearing the accumulation is an administrative action, not a client grant.
      final strays = await sessionA
          .from('revenue_tax_rates')
          .select('id')
          .eq('revenue_category_id', category)
          .isFilter('archived_at', null)
          .eq('effective_from', '2027-04-01');
      for (final s in strays) {
        await archive(sessionA, s['id'] as String);
      }
      await sessionA.rpc<dynamic>(
        'revenue_tax_rule_end_date',
        params: {
          'p_rule_id': baselineRuleId,
          'p_effective_to': null,
          'p_mutation_id': const Uuid().v4(),
        },
      );
    });

    Future<Object?> attempt(SupabaseClient session, int rateBp) async {
      try {
        await session.rpc<dynamic>(
          'revenue_tax_rule_create',
          params: {
            'p_revenue_category_id': category,
            'p_rate_bp': rateBp,
            'p_treatment': 'inclusive',
            'p_effective_from': '2027-04-01',
            'p_input_basis': 'inclusive_total',
            'p_mutation_id': const Uuid().v4(),
          },
        );
        return null;
      } on Object catch (error) {
        return error;
      }
    }

    test('exactly one of two concurrent conflicting writers succeeds', () async {
      // Both target the same category over the same dates with wildcard discriminators,
      // so either alone is valid and both together are ambiguous.
      final outcomes = await Future.wait([
        attempt(sessionA, 500),
        attempt(sessionB, 1800),
      ]);

      final failures = outcomes.whereType<Object>().toList();
      final successes = outcomes.where((o) => o == null).length;

      expect(
        successes,
        1,
        reason: 'exactly one writer may win, however the two interleave',
      );
      expect(failures, hasLength(1));
      expect(
        refusalOf(failures.single),
        'KM025',
        reason: 'the loser is told the configuration would be ambiguous',
      );

      // The invariant that actually matters: the committed state is unambiguous.
      final live = await sessionA
          .from('revenue_tax_rates')
          .select('id')
          .eq('revenue_category_id', category)
          .isFilter('archived_at', null)
          .eq('effective_from', '2027-04-01');
      expect(
        live,
        hasLength(1),
        reason: 'the database must never hold two rules that could both match',
      );
    });

    test('and repeating it does not eventually let both through', () async {
      // Once is not evidence about a race. Five rounds, each with its own cleanup.
      for (var round = 0; round < 5; round++) {
        final outcomes = await Future.wait([
          attempt(sessionA, 500),
          attempt(sessionB, 1800),
        ]);
        expect(
          outcomes.where((o) => o == null).length,
          1,
          reason:
              'round $round admitted ${outcomes.where((o) => o == null).length} writers',
        );

        final live = await sessionA
            .from('revenue_tax_rates')
            .select('id')
            .eq('revenue_category_id', category)
            .isFilter('archived_at', null)
            .eq('effective_from', '2027-04-01');
        expect(
          live,
          hasLength(1),
          reason: 'round $round left an ambiguous set',
        );
        await archive(sessionA, live.single['id'] as String);
      }
    });

    test('POSITIVE CONTROL: without the lock, both writers commit', () async {
      // The control the brief requires: proof that the serialization mechanism is what
      // makes the difference, not luck of scheduling.
      //
      // It runs against transient scaffolding in the `wsk` schema — a scratch table and
      // two functions with the SAME read-validate-write shape, one taking the advisory
      // lock and one not, each pausing between validating and writing so the interleave
      // is deterministic rather than hoped for. No production table is touched and no
      // real trigger is disabled, which is what keeps this a control rather than a way
      // of turning the protection off.
      //
      // The scaffolding is created and dropped around a run, so this test SKIPS when it
      // is absent. That is deliberate: leaving a lock-bypassing function permanently
      // callable would be a backdoor, and a skipped control that says why is more honest
      // than a shipped one that weakens the system.
      Future<int> race(String fn) async {
        final scratchCategory = const Uuid().v4();
        await Future.wait([
          sessionA.rpc<dynamic>(
            fn,
            params: {'p_category': scratchCategory, 'p_rate': 500},
          ),
          sessionB.rpc<dynamic>(
            fn,
            params: {'p_category': scratchCategory, 'p_rate': 1800},
          ),
        ]);
        return await sessionA.rpc<int>(
          'wsk_count',
          params: {'p_category': scratchCategory},
        );
      }

      try {
        await sessionA.rpc<dynamic>(
          'wsk_locked',
          params: {'p_category': const Uuid().v4(), 'p_rate': 1},
        );
      } on Object {
        markTestSkipped(
          'write-skew scaffolding is not installed — see D-095 for the recorded result',
        );
        return;
      }

      expect(
        await race('wsk_unlocked'),
        2,
        reason:
            'WITHOUT the lock both writers validate against a state neither has changed '
            'yet, and both commit — this is the write skew D-095 exists to prevent',
      );
      expect(
        await race('wsk_locked'),
        1,
        reason:
            'WITH the lock the second waits, then sees the first, and refuses',
      );
    });

    test('unrelated categories are not serialised against each other', () async {
      // The lock is keyed on (org, category), so configuring Restaurant must not block
      // somebody configuring Room. Both of these should succeed.
      final room = await categoryId('HKI', 'ROOM');
      final roomBaseline = await sessionA
          .from('revenue_tax_rates')
          .select('id')
          .eq('revenue_category_id', room)
          .isFilter('archived_at', null)
          .single();
      await sessionA.rpc<dynamic>(
        'revenue_tax_rule_end_date',
        params: {
          'p_rule_id': roomBaseline['id'],
          'p_effective_to': '2027-04-01',
          'p_mutation_id': const Uuid().v4(),
        },
      );

      final outcomes = await Future.wait([
        attempt(sessionA, 500),
        (() async {
          try {
            await sessionB.rpc<dynamic>(
              'revenue_tax_rule_create',
              params: {
                'p_revenue_category_id': room,
                'p_rate_bp': 1200,
                'p_treatment': 'inclusive',
                'p_effective_from': '2027-04-01',
                'p_input_basis': 'inclusive_total',
                'p_mutation_id': const Uuid().v4(),
              },
            );
            return null;
          } on Object catch (e) {
            return e;
          }
        })(),
      ]);

      expect(
        outcomes.where((o) => o == null).length,
        2,
        reason: 'different categories must not contend for one lock',
      );

      // Restore Room.
      final roomStrays = await sessionA
          .from('revenue_tax_rates')
          .select('id')
          .eq('revenue_category_id', room)
          .isFilter('archived_at', null)
          .eq('effective_from', '2027-04-01');
      for (final s in roomStrays) {
        await archive(sessionA, s['id'] as String);
      }
      await sessionA.rpc<dynamic>(
        'revenue_tax_rule_end_date',
        params: {
          'p_rule_id': roomBaseline['id'],
          'p_effective_to': null,
          'p_mutation_id': const Uuid().v4(),
        },
      );
    });
  });

  // -- Slice 10: the correction boundary --------------------------------------
  //
  // Every rule here is the server's, and the server's answer is the one that counts
  // (D-037). The client mirrors these decisions to shape its interface; nothing below
  // asks the client anything.
  //
  // Fixtures are created through the real RPCs and **voided** afterwards, never deleted:
  // no client role holds DELETE on a financial table and none is granted for cleanup
  // (D-006, D-071). The audit rows recording that they existed remain, which is the
  // asymmetry the append-only guard is for (D-066).
  group('revenue_update and revenue_void, against the real boundary', () {
    const marker = 'ACCEPTANCE slice10-correction';

    late String ccrUnit;
    late String restaurant;
    final created = <String>[];

    Future<String> unitId(String code) async {
      final row = await client
          .from('business_units')
          .select('id')
          .eq('code', code)
          .single();
      return row['id'] as String;
    }

    /// Records a sale through the shipped RPC and returns the server's answer.
    Future<Map<String, dynamic>> record({
      int paise = 10000000,
      String date = '2026-06-15',
    }) async {
      final id = const Uuid().v7();
      final answer =
          await client.rpc<dynamic>(
                'revenue_create',
                params: {
                  'p_id': id,
                  'p_business_unit_id': ccrUnit,
                  'p_revenue_category_id': restaurant,
                  'p_business_date': date,
                  'p_notes': marker,
                  'p_components': [
                    {'entered_amount_minor': paise},
                  ],
                  'p_mutation_id': const Uuid().v4(),
                },
              )
              as Map<String, dynamic>;
      created.add(id);
      return answer;
    }

    Future<Map<String, dynamic>> document(String id) async =>
        await client.from('revenue_document').select().eq('id', id).single();

    setUpAll(() async {
      await signInAs('giridhar@hki.com');
      ccrUnit = await unitId('CCR');
      restaurant = await categoryId('CCR', 'RESTAURANT');
    });

    setUp(() => signInAs('giridhar@hki.com'));

    tearDownAll(() async {
      // Void, never delete. A document a closed period refuses is reported rather than
      // swallowed, so the next reader sees it rather than a silent leftover.
      await signInAs('giridhar@hki.com');
      for (final id in created) {
        try {
          final row = await client
              .from('revenue_document')
              .select('row_version, voided_at')
              .eq('id', id)
              .maybeSingle();
          if (row == null || row['voided_at'] != null) continue;
          await client.rpc<dynamic>(
            'revenue_void',
            params: {
              'p_id': id,
              'p_base_row_version': row['row_version'],
              'p_reason': '$marker fixture reversal',
              'p_mutation_id': const Uuid().v4(),
            },
          );
        } on PostgrestException catch (error) {
          // ignore: avoid_print
          print('slice10 fixture $id not reversed: ${error.code}');
        }
      }
    });

    test(
      'the server re-resolves the tax and ignores what the client claims',
      () async {
        final id = (await record(paise: 10000000))['id'] as String;
        final before = await document(id);

        await client.rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': id,
            'p_base_row_version': before['row_version'],
            'p_business_date': '2026-06-15',
            'p_notes': marker,
            'p_components': [
              {
                'entered_amount_minor': 21000000,
                // Deliberately wrong, and deliberately not sent as declared_*: the server
                // computes its own figures and ignores anything a caller says about them.
                'gross_amount_minor': 1,
                'tax_amount_minor': 1,
                'net_amount_minor': 1,
              },
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );

        final after = await document(id);
        // 5% inclusive on 2,10,000.00.
        expect(after['gross_amount_minor'], 21000000);
        expect(after['tax_amount_minor'], 1000000);
        expect(after['net_amount_minor'], 20000000);
        expect(
          after['net_amount_minor'],
          (after['gross_amount_minor'] as int) -
              (after['tax_amount_minor'] as int),
        );
      },
    );

    test(
      'a declared figure that disagrees is refused KM030, not applied',
      () async {
        final id = (await record())['id'] as String;
        final before = await document(id);

        await expectLater(
          client.rpc<dynamic>(
            'revenue_update',
            params: {
              'p_id': id,
              'p_base_row_version': before['row_version'],
              'p_business_date': '2026-06-15',
              'p_notes': marker,
              'p_components': [
                {
                  'entered_amount_minor': 21000000,
                  'declared_gross_minor': 21000000,
                  // A rate that is not the configured one - the case where the
                  // configuration changed between preparing the entry and delivering it.
                  'declared_tax_minor': 999999,
                  'declared_net_minor': 20000001,
                },
              ],
              'p_mutation_id': const Uuid().v4(),
            },
          ),
          throwsA(
            predicate(
              (e) => refusalOf(e) == 'KM030',
              'refused with tax_configuration_mismatch',
            ),
          ),
        );

        // And nothing was applied: the operator's approved figures are not quietly
        // replaced by figures they never saw (D-114).
        final after = await document(id);
        expect(after['row_version'], before['row_version']);
        expect(after['gross_amount_minor'], before['gross_amount_minor']);
      },
    );

    test('the transaction number and the identity survive a correction', () async {
      final id = (await record())['id'] as String;
      final before = await document(id);
      expect(before['txn_number'], startsWith('KI-REV-'));

      await client.rpc<dynamic>(
        'revenue_update',
        params: {
          'p_id': id,
          'p_base_row_version': before['row_version'],
          'p_business_date': '2026-06-16',
          'p_notes': marker,
          // A moved business date is a correction, and a correction states why
          // (spec §9). Before the Phase 4 corrective this call was accepted with no
          // reason and no capability at all.
          'p_correction_reason': 'Recorded against the wrong trading day',
          'p_components': [
            {'entered_amount_minor': 12000000},
          ],
          'p_mutation_id': const Uuid().v4(),
        },
      );

      final after = await document(id);
      expect(after['txn_number'], before['txn_number']);
      expect(after['id'], before['id']);
      expect(after['financial_year'], before['financial_year']);
      // The version advanced, which is what makes a stale second attempt a conflict.
      expect(after['row_version'], greaterThan(before['row_version'] as int));
      expect(after['business_date'], '2026-06-16');
      expect(after['pnl_period_key'], '2026-06');
    });

    test(
      'a stale correction is refused as a conflict, and applies nothing',
      () async {
        final id = (await record())['id'] as String;
        final v1 = await document(id);

        await client.rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': id,
            'p_base_row_version': v1['row_version'],
            'p_business_date': '2026-06-15',
            'p_notes': marker,
            'p_components': [
              {'entered_amount_minor': 12000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );

        // A second correction based on the version the first one replaced.
        await expectLater(
          client.rpc<dynamic>(
            'revenue_update',
            params: {
              'p_id': id,
              'p_base_row_version': v1['row_version'],
              'p_business_date': '2026-06-15',
              'p_notes': marker,
              'p_components': [
                {'entered_amount_minor': 13000000},
              ],
              'p_mutation_id': const Uuid().v4(),
            },
          ),
          throwsA(
            predicate((e) => refusalOf(e) == 'KM003', 'refused as a conflict'),
          ),
        );

        expect((await document(id))['gross_amount_minor'], 12000000);
      },
    );

    test(
      'redelivering the same correction replays rather than applying twice',
      () async {
        final id = (await record())['id'] as String;
        final before = await document(id);

        final params = {
          'p_id': id,
          'p_base_row_version': before['row_version'],
          'p_business_date': '2026-06-15',
          'p_notes': marker,
          'p_components': [
            {'entered_amount_minor': 12000000},
          ],
          'p_mutation_id': const Uuid().v4(),
        };

        final first =
            await client.rpc<dynamic>('revenue_update', params: params)
                as Map<String, dynamic>;
        final second =
            await client.rpc<dynamic>('revenue_update', params: params)
                as Map<String, dynamic>;

        // Idempotency (D-004): the stored result is replayed, and the document moved once.
        expect(second['status'], 'replayed');
        expect(second['row_version'], first['row_version']);
        final after = await document(id);
        expect(after['row_version'], first['row_version']);
        expect(after['gross_amount_minor'], 12000000);
      },
    );

    test(
      'a void needs a reason, keeps the document, and is not a delete',
      () async {
        final id = (await record())['id'] as String;
        final before = await document(id);

        await expectLater(
          client.rpc<dynamic>(
            'revenue_void',
            params: {
              'p_id': id,
              'p_base_row_version': before['row_version'],
              'p_reason': '   ',
              'p_mutation_id': const Uuid().v4(),
            },
          ),
          throwsA(predicate((e) => refusalOf(e) != null, 'refused')),
        );

        await client.rpc<dynamic>(
          'revenue_void',
          params: {
            'p_id': id,
            'p_base_row_version': before['row_version'],
            'p_reason': '$marker voided deliberately',
            'p_mutation_id': const Uuid().v4(),
          },
        );

        final after = await document(id);
        expect(after['voided_at'], isNotNull);
        expect(after['void_reason'], contains('voided deliberately'));
        // Still there, with its number and its components (D-006).
        expect(after['txn_number'], before['txn_number']);
        final components = await client
            .from('revenue_component_detail')
            .select('id')
            .eq('revenue_entry_id', id);
        expect(components, isNotEmpty);
      },
    );

    test(
      'a voided sale is immutable, and it says so with its own code',
      () async {
        final id = (await record())['id'] as String;
        final before = await document(id);
        await client.rpc<dynamic>(
          'revenue_void',
          params: {
            'p_id': id,
            'p_base_row_version': before['row_version'],
            'p_reason': '$marker voided deliberately',
            'p_mutation_id': const Uuid().v4(),
          },
        );
        final voided = await document(id);

        await expectLater(
          client.rpc<dynamic>(
            'revenue_update',
            params: {
              'p_id': id,
              'p_base_row_version': voided['row_version'],
              'p_business_date': '2026-06-15',
              'p_notes': marker,
              'p_components': [
                {'entered_amount_minor': 1},
              ],
              'p_mutation_id': const Uuid().v4(),
            },
          ),
          throwsA(
            predicate(
              (e) => refusalOf(e) == 'KM020',
              'a voided document is immutable; correct by recording a new one',
            ),
          ),
        );
      },
    );

    test(
      'a stale void is refused rather than voiding a version nobody reviewed',
      () async {
        final id = (await record())['id'] as String;
        final v1 = await document(id);

        await client.rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': id,
            'p_base_row_version': v1['row_version'],
            'p_business_date': '2026-06-15',
            'p_notes': marker,
            'p_components': [
              {'entered_amount_minor': 12000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );

        // D-021 exactly: device A loads v3, device B edits to v4, device A voids "v3".
        await expectLater(
          client.rpc<dynamic>(
            'revenue_void',
            params: {
              'p_id': id,
              'p_base_row_version': v1['row_version'],
              'p_reason': '$marker stale void',
              'p_mutation_id': const Uuid().v4(),
            },
          ),
          throwsA(
            predicate((e) => refusalOf(e) == 'KM003', 'refused as a conflict'),
          ),
        );
        expect((await document(id))['voided_at'], isNull);
      },
    );

    test('a manager cannot correct revenue somebody else recorded', () async {
      // Recorded by the Owner; corrected by a scoped manager holding revenue.edit but
      // not revenue.edit.all. The split expenses have had since D-072a.
      final id = (await record())['id'] as String;
      final before = await document(id);

      final manager = await sessionFor('ccr.manager@example.com');
      await expectLater(
        manager.rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': id,
            'p_base_row_version': before['row_version'],
            'p_business_date': '2026-06-15',
            'p_notes': marker,
            'p_components': [
              {'entered_amount_minor': 12000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        ),
        throwsA(predicate((e) => refusalOf(e) != null, 'refused')),
      );
      expect((await document(id))['row_version'], before['row_version']);
    });

    test(
      'a manager cannot void at all: recording is not the right to erase',
      () async {
        final id = (await record())['id'] as String;
        final before = await document(id);

        final manager = await sessionFor('ccr.manager@example.com');
        await expectLater(
          manager.rpc<dynamic>(
            'revenue_void',
            params: {
              'p_id': id,
              'p_base_row_version': before['row_version'],
              'p_reason': '$marker attempted by a manager',
              'p_mutation_id': const Uuid().v4(),
            },
          ),
          throwsA(
            predicate((e) => refusalOf(e) == 'KM001', 'missing capability'),
          ),
        );
        expect((await document(id))['voided_at'], isNull);
      },
    );

    // The edit window, measured against the property's own business date (D-067) and
    // inclusive of its last day (D-065).
    //
    // Driven as the **manager** on their **own** entries, because that is the only actor
    // the age rule actually binds: the Owner holds `transaction.correct.beyond_window`,
    // so an Owner refusal would prove nothing about the window.
    //
    // Both halves are here on purpose. A test that only asserts the refusal cannot tell
    // "the window works" from "the manager can never correct anything", and the second
    // would pass just as green.
    group('the edit window binds the manager', () {
      late SupabaseClient manager;
      final managerCreated = <String>[];

      /// A date unambiguously inside the window, whatever the cut-off does.
      ///
      /// Yesterday in the property's own zone: at least a day inside D+7 from either
      /// side of the 05:00 boundary, so the positive control cannot fail for being a
      /// few hours out. No RPC is added to compute it - a test-only endpoint in a
      /// financial system is a thing that eventually gets called (D-105).
      String insideTheWindow() {
        final ist = DateTime.now().toUtc().add(
          const Duration(hours: 5, minutes: 30),
        );
        final yesterday = DateTime.utc(
          ist.year,
          ist.month,
          ist.day,
        ).subtract(const Duration(days: 1));
        return yesterday.toIso8601String().substring(0, 10);
      }

      Future<Map<String, dynamic>> managerRecords(String date) async {
        final id = const Uuid().v7();
        await manager.rpc<dynamic>(
          'revenue_create',
          params: {
            'p_id': id,
            'p_business_unit_id': ccrUnit,
            'p_revenue_category_id': restaurant,
            'p_business_date': date,
            'p_notes': marker,
            'p_components': [
              {'entered_amount_minor': 10000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );
        managerCreated.add(id);
        created.add(id);
        return await manager
            .from('revenue_document')
            .select()
            .eq('id', id)
            .single();
      }

      Future<void> managerCorrects(Map<String, dynamic> doc) => manager
          .rpc<dynamic>(
            'revenue_update',
            params: {
              'p_id': doc['id'],
              'p_base_row_version': doc['row_version'],
              'p_business_date': doc['business_date'],
              'p_notes': marker,
              'p_components': [
                {'entered_amount_minor': 12000000},
              ],
              'p_mutation_id': const Uuid().v4(),
            },
          )
          .then((_) {});

      setUp(() async {
        manager = await sessionFor('ccr.manager@example.com');
      });

      test('their own entry from today is correctable', () async {
        final doc = await managerRecords(insideTheWindow());
        await managerCorrects(doc);

        final after = await manager
            .from('revenue_document')
            .select('gross_amount_minor')
            .eq('id', doc['id'] as String)
            .single();
        expect(after['gross_amount_minor'], 12000000);
      });

      test('their own entry from beyond the window is refused KM021', () async {
        // Well past D+7, and still inside the configured baseline so the refusal is
        // about the window rather than about an unresolvable rule.
        final doc = await managerRecords('2026-06-15');

        await expectLater(
          managerCorrects(doc),
          throwsA(
            predicate(
              (e) => refusalOf(e) == 'KM021',
              'refused for the edit window, not for something else',
            ),
          ),
        );

        final after = await manager
            .from('revenue_document')
            .select('gross_amount_minor, row_version')
            .eq('id', doc['id'] as String)
            .single();
        expect(after['gross_amount_minor'], 10000000);
        expect(after['row_version'], doc['row_version']);
      });

      test(
        'the Owner may still correct it, which is what the capability is for',
        () async {
          final doc = await managerRecords('2026-06-15');

          await signInAs('giridhar@hki.com');
          await client.rpc<dynamic>(
            'revenue_update',
            params: {
              'p_id': doc['id'],
              'p_base_row_version': doc['row_version'],
              'p_business_date': doc['business_date'],
              'p_notes': marker,
              'p_components': [
                {'entered_amount_minor': 12000000},
              ],
              'p_mutation_id': const Uuid().v4(),
            },
          );

          expect(
            (await document(doc['id'] as String))['gross_amount_minor'],
            12000000,
          );
        },
      );
    });

    test(
      'the business unit and the category cannot be moved by a correction',
      () async {
        // Not a parameter at all: `revenue_update` takes no unit and no category, so an
        // edit that moved revenue between properties is unavailable rather than refused.
        // A named argument that does not exist cannot be forgotten later.
        final id = (await record())['id'] as String;
        final before = await document(id);

        await expectLater(
          client.rpc<dynamic>(
            'revenue_update',
            params: {
              'p_id': id,
              'p_base_row_version': before['row_version'],
              'p_business_date': '2026-06-15',
              'p_business_unit_id': await unitId('HKI'),
              'p_notes': marker,
              'p_components': [
                {'entered_amount_minor': 12000000},
              ],
              'p_mutation_id': const Uuid().v4(),
            },
          ),
          throwsA(isA<PostgrestException>()),
        );

        final after = await document(id);
        expect(after['business_unit_id'], ccrUnit);
        expect(after['revenue_category_id'], restaurant);
      },
    );

    // ── The Phase 4 corrective: moving a sale's trading day is a correction ──
    //
    // The bounded parity audit the expense corrective required found this, and found it
    // by probe rather than by reading the SQL: a **Manager** — holding `revenue.edit` and
    // not `transaction.correct.business_date` — moved a sale from one trading day to
    // another, and the call returned `status: updated` with no capability asked for, no
    // reason collected, and one audit row reading `edited` with a null reason.
    //
    // Four of the seven parity requirements were already met (both periods, tax
    // re-resolution, KI-REV preserved, concurrency) and are not re-tested here — the
    // group above covers them. These are the three that were missing.
    group('a moved business date is a correction (spec §9)', () {
      late SupabaseClient manager;

      setUp(() async {
        manager = await sessionFor('ccr.manager@example.com');
      });

      /// A sale the manager recorded themselves, inside the edit window, so neither
      /// ownership nor the age rule is what refuses anything below.
      Future<Map<String, dynamic>> managerSale() async {
        final id = const Uuid().v7();
        final ist = DateTime.now().toUtc().add(
          const Duration(hours: 5, minutes: 30),
        );
        final yesterday = DateTime.utc(
          ist.year,
          ist.month,
          ist.day,
        ).subtract(const Duration(days: 1));
        await manager.rpc<dynamic>(
          'revenue_create',
          params: {
            'p_id': id,
            'p_business_unit_id': ccrUnit,
            'p_revenue_category_id': restaurant,
            'p_business_date': yesterday.toIso8601String().substring(0, 10),
            'p_notes': marker,
            'p_components': [
              {'entered_amount_minor': 10000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );
        created.add(id);
        return await manager
            .from('revenue_document')
            .select()
            .eq('id', id)
            .single();
      }

      /// The same sale, asked to move one day earlier.
      Future<void> moveOneDay(
        SupabaseClient as,
        Map<String, dynamic> doc, {
        String? reason,
      }) async {
        final from = DateTime.parse(doc['business_date'] as String);
        await as.rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': doc['id'],
            'p_base_row_version': doc['row_version'],
            'p_business_date': from
                .subtract(const Duration(days: 1))
                .toIso8601String()
                .substring(0, 10),
            'p_notes': marker,
            'p_correction_reason': ?reason,
            'p_components': [
              {'entered_amount_minor': 10000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );
      }

      test('a manager cannot move a trading day at all', () async {
        final doc = await managerSale();

        await expectLater(
          moveOneDay(manager, doc, reason: 'I made a mistake'),
          throwsA(
            predicate(
              (e) => refusalOf(e) == 'KM001' || refusalOf(e) == 'KM002',
              'refused for the correction capability',
            ),
          ),
        );

        final after = await document(doc['id'] as String);
        expect(
          after['business_date'],
          doc['business_date'],
          reason: 'the trading day a sale is reported on did not move',
        );
        expect(after['row_version'], doc['row_version']);
      });

      test('the same manager may still correct the figure', () async {
        // The control that makes the refusal above mean something. Without it, "the
        // capability binds" and "the manager can never correct anything" look the same.
        final doc = await managerSale();
        await manager.rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': doc['id'],
            'p_base_row_version': doc['row_version'],
            'p_business_date': doc['business_date'],
            'p_notes': marker,
            'p_components': [
              {'entered_amount_minor': 12000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );
        expect(
          (await document(doc['id'] as String))['gross_amount_minor'],
          12000000,
        );
      });

      test('a holder of the capability still needs a reason', () async {
        final doc = await managerSale();
        await signInAs('accountant@example.com');

        for (final blank in ['', '   ', '\t', '\n ']) {
          await expectLater(
            moveOneDay(client, doc, reason: blank),
            throwsA(
              predicate((e) => refusalOf(e) == 'KM008', 'reason required'),
            ),
            reason: 'blank is not a reason, whichever whitespace it is made of',
          );
        }

        await expectLater(
          moveOneDay(client, doc),
          throwsA(predicate((e) => refusalOf(e) == 'KM008', 'reason required')),
          reason: 'and neither is omitting it',
        );

        final after = await document(doc['id'] as String);
        expect(after['business_date'], doc['business_date']);
        expect(after['row_version'], doc['row_version']);
      });

      test(
        'a permitted correction succeeds and is audited as its own act',
        () async {
          final doc = await managerSale();
          await signInAs('accountant@example.com');
          await moveOneDay(
            client,
            doc,
            reason: 'Rung up after midnight against the wrong trading day',
          );

          await signInAs('giridhar@hki.com');
          final after = await document(doc['id'] as String);
          expect(
            after['business_date'],
            isNot(doc['business_date']),
            reason: 'the correction was applied',
          );
          expect(
            after['txn_number'],
            doc['txn_number'],
            reason:
                'the number belongs to the identity and survives a correction',
          );

          final audit = await client
              .from('audit_logs')
              .select('action,reason,before_state,after_state')
              .eq('entity_id', doc['id'] as String)
              .eq('action', 'business_date_corrected');
          expect(
            audit,
            hasLength(1),
            reason:
                'spec §14 lists business date corrected among the audited actions, '
                'and a generic edited row does not answer which days were moved',
          );
          expect(
            audit.single['reason'],
            'Rung up after midnight against the wrong trading day',
          );
          expect(
            (audit.single['before_state'] as Map)['business_date'],
            doc['business_date'],
          );
        },
      );

      test('an ordinary correction writes no correction audit row', () async {
        // The gate binds on the branch it is for and on no other: a figure corrected on
        // the same trading day is not a business-date correction and must not look like
        // one in the audit trail.
        final doc = await managerSale();
        await manager.rpc<dynamic>(
          'revenue_update',
          params: {
            'p_id': doc['id'],
            'p_base_row_version': doc['row_version'],
            'p_business_date': doc['business_date'],
            'p_notes': marker,
            'p_components': [
              {'entered_amount_minor': 11000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );

        await signInAs('giridhar@hki.com');
        final audit = await client
            .from('audit_logs')
            .select('action')
            .eq('entity_id', doc['id'] as String)
            .eq('action', 'business_date_corrected');
        expect(audit, isEmpty);
      });

      test('a correction within one month is still a correction', () async {
        // The reason the detection compares **dates** and not period keys: 15 June to
        // 20 June is the ordinary case, and a guard keyed on `pnl_period_key` would have
        // seen no change at all and let it through ungated.
        final doc = await managerSale();
        await signInAs('accountant@example.com');
        final from = DateTime.parse(doc['business_date'] as String);
        final sameMonth = DateTime.utc(from.year, from.month, 1)
            .add(Duration(days: from.day == 3 ? 5 : 2))
            .toIso8601String()
            .substring(0, 10);

        await expectLater(
          client.rpc<dynamic>(
            'revenue_update',
            params: {
              'p_id': doc['id'],
              'p_base_row_version': doc['row_version'],
              'p_business_date': sameMonth,
              'p_notes': marker,
              'p_components': [
                {'entered_amount_minor': 10000000},
              ],
              'p_mutation_id': const Uuid().v4(),
            },
          ),
          throwsA(predicate((e) => refusalOf(e) == 'KM008', 'reason required')),
          reason:
              'the period key is unchanged, and the trading day is not — the '
              'correction rules follow the date',
        );
      });
    });
    // ── A void reason that says nothing is not a reason ─────────────────────
    //
    // `revenue_void` used `coalesce(trim(p_reason), '') = ''`, and one-argument `trim`
    // strips spaces alone. Proven against the shipped function before it was changed: a
    // lone tab voided a sale and was stored as its `void_reason`.
    //
    // The same matrix the correction reason is held to, because they are now one rule —
    // `app.stated_reason` — rather than two expressions that happened to agree.
    group('a void reason rejects every whitespace-only value', () {
      Future<Map<String, dynamic>> voidable() async {
        final id = (await record(paise: 15000))['id'] as String;
        return await document(id);
      }

      Future<void> voidWith(Map<String, dynamic> doc, String reason) async {
        await signInAs('accountant@example.com');
        await client.rpc<dynamic>(
          'revenue_void',
          params: {
            'p_id': doc['id'],
            'p_base_row_version': doc['row_version'],
            'p_reason': reason,
            'p_mutation_id': const Uuid().v4(),
          },
        );
      }

      for (final blank in const [
        ('', 'empty'),
        ('   ', 'spaces'),
        ('\t', 'one tab — the case that got through'),
        ('\n', 'newline'),
        ('\r', 'carriage return'),
        (' \t\r\n ', 'mixed whitespace'),
      ]) {
        test('refused: ${blank.$2}', () async {
          final doc = await voidable();

          await expectLater(
            voidWith(doc, blank.$1),
            throwsA(
              predicate((e) => refusalOf(e) == 'KM008', 'reason required'),
            ),
            reason: blank.$2,
          );

          await signInAs('giridhar@hki.com');
          final after = await document(doc['id'] as String);
          expect(
            after['voided_at'],
            isNull,
            reason: 'a refused void leaves the sale exactly as it was',
          );
          expect(after['row_version'], doc['row_version']);
        });
      }

      test('an ordinary reason still voids, and is stored trimmed', () async {
        // The control. Without it, "whitespace is refused" and "nothing can be voided"
        // look identical, and the second would pass just as green.
        final doc = await voidable();
        await voidWith(doc, '  Recorded twice by mistake  ');

        await signInAs('giridhar@hki.com');
        final after = await document(doc['id'] as String);
        expect(after['voided_at'], isNotNull);
        expect(
          after['void_reason'],
          'Recorded twice by mistake',
          reason: 'the ends are trimmed and nothing else is touched',
        );
        expect(
          after['txn_number'],
          doc['txn_number'],
          reason: 'a void keeps the document, its number and its components',
        );
      });

      test(
        'internal spacing is content, not whitespace to be squeezed',
        () async {
          final doc = await voidable();
          await voidWith(doc, 'Duplicate  of  KI-REV-26-27-000001');

          await signInAs('giridhar@hki.com');
          expect(
            (await document(doc['id'] as String))['void_reason'],
            'Duplicate  of  KI-REV-26-27-000001',
          );
        },
      );

      test('the Slice 10 void contract is otherwise unchanged', () async {
        final doc = await voidable();

        // A manager holds no `revenue.void`: recording a sale is not the right to erase it.
        final manager = await sessionFor('ccr.manager@example.com');
        await expectLater(
          manager.rpc<dynamic>(
            'revenue_void',
            params: {
              'p_id': doc['id'],
              'p_base_row_version': doc['row_version'],
              'p_reason': 'a manager should not be able to do this',
              'p_mutation_id': const Uuid().v4(),
            },
          ),
          throwsA(
            predicate((e) => refusalOf(e) == 'KM001', 'missing capability'),
          ),
        );

        // A stale view cannot void a version nobody reviewed (D-021).
        await signInAs('accountant@example.com');
        await expectLater(
          client.rpc<dynamic>(
            'revenue_void',
            params: {
              'p_id': doc['id'],
              'p_base_row_version': (doc['row_version'] as int) + 5,
              'p_reason': 'a stale void',
              'p_mutation_id': const Uuid().v4(),
            },
          ),
          throwsA(predicate((e) => refusalOf(e) == 'KM003', 'stale version')),
        );

        // And the ordinary void still works, replays on redelivery, and audits once.
        final mutationId = const Uuid().v4();
        for (var attempt = 0; attempt < 2; attempt++) {
          await client.rpc<dynamic>(
            'revenue_void',
            params: {
              'p_id': doc['id'],
              'p_base_row_version': doc['row_version'],
              'p_reason': 'Recorded in error',
              'p_mutation_id': mutationId,
            },
          );
        }

        await signInAs('giridhar@hki.com');
        final after = await document(doc['id'] as String);
        expect(after['voided_at'], isNotNull);
        expect(after['txn_number'], doc['txn_number']);
        expect(after['row_version'], (doc['row_version'] as int) + 1);

        final audit = await client
            .from('audit_logs')
            .select('id')
            .eq('entity_id', doc['id'] as String)
            .eq('action', 'voided');
        expect(
          audit,
          hasLength(1),
          reason: 'one void, one audit effect (D-004)',
        );
      });
    });

    // ── Business-date provenance (spec §9, D-019) ───────────────────────────
    //
    // An approved V1 product decision: a revenue entry records how its **current** trading
    // day came to be. The server owns the answer — there is no provenance parameter — and
    // the audit trail remains the historical sequence.
    group('the entry records how its business date was established', () {
      late SupabaseClient manager;

      setUp(() async {
        manager = await sessionFor('ccr.manager@example.com');
      });

      String isoDaysAgo(int days) {
        final ist = DateTime.now().toUtc().add(
          const Duration(hours: 5, minutes: 30),
        );
        final day = DateTime.utc(
          ist.year,
          ist.month,
          ist.day,
        ).subtract(Duration(days: days));
        return day.toIso8601String().substring(0, 10);
      }

      /// A sale the manager recorded themselves, inside the edit window.
      Future<Map<String, dynamic>> managerSale({int daysAgo = 1}) async {
        final id = const Uuid().v7();
        await manager.rpc<dynamic>(
          'revenue_create',
          params: {
            'p_id': id,
            'p_business_unit_id': ccrUnit,
            'p_revenue_category_id': restaurant,
            'p_business_date': isoDaysAgo(daysAgo),
            'p_notes': marker,
            'p_components': [
              {'entered_amount_minor': 10000000},
            ],
            'p_mutation_id': const Uuid().v4(),
          },
        );
        created.add(id);
        return await manager
            .from('revenue_document')
            .select()
            .eq('id', id)
            .single();
      }

      Future<Map<String, dynamic>> correctAs(
        SupabaseClient as,
        Map<String, dynamic> doc, {
        String? date,
        String? reason,
        int? version,
        int paise = 10000000,
      }) async =>
          (await as.rpc<dynamic>(
                'revenue_update',
                params: {
                  'p_id': doc['id'],
                  'p_base_row_version': version ?? doc['row_version'],
                  'p_business_date': date ?? doc['business_date'],
                  'p_notes': marker,
                  'p_correction_reason': ?reason,
                  'p_components': [
                    {'entered_amount_minor': paise},
                  ],
                  'p_mutation_id': const Uuid().v4(),
                },
              )
              as Map<String, dynamic>);

      Future<String> sourceOf(String id) async {
        await signInAs('giridhar@hki.com');
        return (await document(id))['business_date_source'] as String;
      }

      test('a newly recorded sale is derived', () async {
        final doc = await managerSale();
        expect(doc['business_date_source'], 'derived');
        expect(await sourceOf(doc['id'] as String), 'derived');
      });

      test('an ordinary edit leaves it derived', () async {
        final doc = await managerSale();
        final answer = await correctAs(manager, doc, paise: 12000000);
        expect(answer['business_date_source'], 'derived');
        expect(answer['business_date_corrected'], isFalse);
        expect(await sourceOf(doc['id'] as String), 'derived');
      });

      test(
        'a date correction makes it corrected, and says so in the answer',
        () async {
          final doc = await managerSale();
          await signInAs('accountant@example.com');
          final answer = await correctAs(
            client,
            doc,
            date: isoDaysAgo(2),
            reason: 'Rung up after midnight against the wrong trading day',
          );
          expect(answer['business_date_corrected'], isTrue);
          expect(answer['business_date_source'], 'corrected');
          expect(await sourceOf(doc['id'] as String), 'corrected');
          expect(
            (await document(doc['id'] as String))['txn_number'],
            doc['txn_number'],
          );

          // The audit remains the historical sequence, and carries both provenances.
          final audit = await client
              .from('audit_logs')
              .select('before_state,after_state,reason')
              .eq('entity_id', doc['id'] as String)
              .eq('action', 'business_date_corrected');
          expect(audit, hasLength(1));
          expect(
            (audit.single['before_state'] as Map)['business_date_source'],
            'derived',
          );
          expect(
            (audit.single['after_state'] as Map)['business_date_source'],
            'corrected',
          );
        },
      );

      test('an ordinary edit after a correction stays corrected', () async {
        final doc = await managerSale();
        await signInAs('accountant@example.com');
        final corrected = await correctAs(
          client,
          doc,
          date: isoDaysAgo(2),
          reason: 'Wrong trading day',
        );

        final ordinary = await correctAs(
          client,
          doc,
          version: corrected['row_version'] as int,
          date: isoDaysAgo(2),
          paise: 13000000,
        );
        expect(
          ordinary['business_date_source'],
          'corrected',
          reason:
              'the question is how this trading day came to be, and a later amount '
              'correction does not change that answer',
        );
        expect(await sourceOf(doc['id'] as String), 'corrected');
      });

      test(
        'a second deliberate correction stays corrected, and audits again',
        () async {
          final doc = await managerSale();
          await signInAs('accountant@example.com');
          final first = await correctAs(
            client,
            doc,
            date: isoDaysAgo(2),
            reason: 'First correction',
          );
          final second = await correctAs(
            client,
            doc,
            version: first['row_version'] as int,
            date: isoDaysAgo(3),
            reason: 'Second correction',
          );
          expect(second['business_date_source'], 'corrected');

          final audit = await client
              .from('audit_logs')
              .select('reason')
              .eq('entity_id', doc['id'] as String)
              .eq('action', 'business_date_corrected');
          expect(
            audit,
            hasLength(2),
            reason: 'the column is present-state; the audit is the sequence',
          );
          expect(
            audit.map((r) => r['reason']),
            containsAll(['First correction', 'Second correction']),
          );
        },
      );

      test('every refusal leaves the provenance untouched', () async {
        // Stale version, missing capability, a blank reason and a closed period: each is
        // refused before the write, so none of them may move the provenance.
        await signInAs('giridhar@hki.com');
        final stale = await managerSale();
        await expectLater(
          correctAs(
            client,
            stale,
            date: isoDaysAgo(2),
            reason: 'stale',
            version: (stale['row_version'] as int) + 5,
          ),
          throwsA(predicate((e) => refusalOf(e) == 'KM003', 'stale version')),
        );
        expect(await sourceOf(stale['id'] as String), 'derived');

        final noCapability = await managerSale();
        await expectLater(
          correctAs(
            manager,
            noCapability,
            date: isoDaysAgo(2),
            reason: 'a manager may not move a trading day',
          ),
          throwsA(
            predicate(
              (e) => refusalOf(e) == 'KM001' || refusalOf(e) == 'KM002',
              'missing the correction capability',
            ),
          ),
        );
        expect(await sourceOf(noCapability['id'] as String), 'derived');

        final blank = await managerSale();
        await signInAs('accountant@example.com');
        for (final reason in ['', '   ', '\t']) {
          await expectLater(
            correctAs(client, blank, date: isoDaysAgo(2), reason: reason),
            throwsA(
              predicate((e) => refusalOf(e) == 'KM008', 'reason required'),
            ),
          );
        }
        expect(await sourceOf(blank['id'] as String), 'derived');

        final closed = await managerSale();
        await signInAs('giridhar@hki.com');
        const closedKey = '2026-03';
        await client
            .rpc<dynamic>(
              'period_close',
              params: {
                'p_period_key': closedKey,
                'p_business_unit_id': ccrUnit,
              },
            )
            .then((_) {}, onError: (_) {});
        try {
          await signInAs('accountant@example.com');
          await expectLater(
            correctAs(
              client,
              closed,
              date: '2026-03-10',
              reason: 'into a closed month',
            ),
            throwsA(predicate((e) => refusalOf(e) == 'KM004', 'period closed')),
          );
          expect(await sourceOf(closed['id'] as String), 'derived');
        } finally {
          await signInAs('giridhar@hki.com');
          await client
              .rpc<dynamic>(
                'period_reopen',
                params: {
                  'p_period_key': closedKey,
                  'p_business_unit_id': ccrUnit,
                  'p_reason': '$marker restoring the development fixture',
                },
              )
              .then((_) {}, onError: (_) {});
        }
      });

      test(
        'a redelivered correction replays with the same provenance',
        () async {
          final doc = await managerSale();
          await signInAs('accountant@example.com');
          final mutationId = const Uuid().v4();

          Future<Map<String, dynamic>> deliver() async =>
              (await client.rpc<dynamic>(
                    'revenue_update',
                    params: {
                      'p_id': doc['id'],
                      'p_base_row_version': doc['row_version'],
                      'p_business_date': isoDaysAgo(2),
                      'p_notes': marker,
                      'p_correction_reason': 'Wrong trading day',
                      'p_components': [
                        {'entered_amount_minor': 10000000},
                      ],
                      'p_mutation_id': mutationId,
                    },
                  )
                  as Map<String, dynamic>);

          final first = await deliver();
          final replay = await deliver();

          expect(first['business_date_source'], 'corrected');
          expect(
            replay['business_date_source'],
            'corrected',
            reason: 'the stored result is replayed, provenance and all',
          );
          expect(replay['status'], 'replayed');
          expect(replay['txn_number'], doc['txn_number']);

          await signInAs('giridhar@hki.com');
          final after = await document(doc['id'] as String);
          expect(after['business_date_source'], 'corrected');
          expect(after['row_version'], (doc['row_version'] as int) + 1);
          expect(after['txn_number'], doc['txn_number']);

          final audit = await client
              .from('audit_logs')
              .select('id')
              .eq('entity_id', doc['id'] as String)
              .eq('action', 'business_date_corrected');
          expect(audit, hasLength(1), reason: 'one effective correction');
        },
      );
    });
  });

  // ── Phase 4 Slice 11 · evidence, and who may have it ───────────────────────
  //
  // The matrix the brief calls for (§36), against the real project. Every refusal here
  // is Storage or RLS answering, never a hidden control: the client is asked directly
  // for the object and for the metadata row, and is told no.
  group('revenue attachments, against the real boundary (Slice 11)', () {
    const marker = 'ACCEPTANCE slice11-evidence';
    const bucket = 'expense-attachments';

    late String ccrUnit;
    late String restaurant;
    late String orgId;
    final createdSales = <String>[];
    final createdObjects = <String>[];

    Future<String> unitId(String code) async {
      final row = await client
          .from('business_units')
          .select('id')
          .eq('code', code)
          .single();
      return row['id'] as String;
    }

    /// Bytes that are not a real JPEG, which is fine: nothing on this path decodes them,
    /// and the bucket's MIME list is matched on the declared content type.
    List<int> evidenceBytes([int seed = 3]) =>
        List<int>.generate(1024, (i) => (i * seed) % 251);

    String pathFor(String saleId, String attachmentId) =>
        'org/$orgId/revenue/$saleId/$attachmentId.jpg';

    Future<String> record({String date = '2026-06-15'}) async {
      final id = const Uuid().v7();
      await client.rpc<dynamic>(
        'revenue_create',
        params: {
          'p_id': id,
          'p_business_unit_id': ccrUnit,
          'p_revenue_category_id': restaurant,
          'p_business_date': date,
          'p_notes': marker,
          'p_components': [
            {'entered_amount_minor': 10000000},
          ],
          'p_mutation_id': const Uuid().v4(),
        },
      );
      createdSales.add(id);
      return id;
    }

    /// The full two-write act the client performs: object, then metadata.
    Future<Map<String, dynamic>> attach(
      String saleId, {
      String? attachmentId,
      String fileName = 'z-report.jpg',
      List<int>? bytes,
      SupabaseClient? as,
      String? mutationId,
    }) async {
      final c = as ?? client;
      final id = attachmentId ?? const Uuid().v4();
      final content = bytes ?? evidenceBytes();
      final path = pathFor(saleId, id);
      await c.storage
          .from(bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(content),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      createdObjects.add(path);
      return await c.rpc<dynamic>(
            'revenue_attachment_register',
            params: {
              'p_id': id,
              'p_revenue_entry_id': saleId,
              'p_file_name': fileName,
              'p_content_type': 'image/jpeg',
              'p_byte_size': content.length,
              'p_content_hash': sha256.convert(content).toString(),
              'p_storage_path': path,
              // Defaults to the attachment id, which is what the client sends: one
              // delivery per file. A test that wants the *other* idempotency guard —
              // the same file id arriving under a fresh delivery — supplies its own.
              'p_mutation_id': mutationId ?? id,
            },
          )
          as Map<String, dynamic>;
    }

    setUpAll(() async {
      await signInAs('giridhar@hki.com');
      ccrUnit = await unitId('CCR');
      restaurant = await categoryId('CCR', 'RESTAURANT');
      orgId =
          (await client
                  .from('revenue_categories')
                  .select('org_id')
                  .limit(1)
                  .single())['org_id']
              as String;
    });

    setUp(() => signInAs('giridhar@hki.com'));

    tearDownAll(() async {
      await signInAs('giridhar@hki.com');
      for (final id in createdSales) {
        try {
          final row = await client
              .from('revenue_document')
              .select('row_version, voided_at')
              .eq('id', id)
              .maybeSingle();
          if (row == null || row['voided_at'] != null) continue;
          await client.rpc<dynamic>(
            'revenue_void',
            params: {
              'p_id': id,
              'p_base_row_version': row['row_version'],
              'p_reason': '$marker fixture reversal',
              'p_mutation_id': const Uuid().v4(),
            },
          );
        } on PostgrestException catch (error) {
          // ignore: avoid_print
          print('slice11 fixture $id not reversed: ${error.code}');
        }
      }
      // The objects are NOT deleted, and that is the correct outcome rather than a gap.
      // No client role holds DELETE on the bucket (D-063), granting one for the
      // convenience of a test would be a backdoor, and the metadata rows they belong to
      // are attached to voided sales that remain as history (D-006, D-066). They are
      // listed here so the run says what it left rather than calling the bucket pristine.
      // ignore: avoid_print
      print(
        'slice11 retained ${createdObjects.length} acceptance object(s) under '
        'org/$orgId/revenue/: ${createdObjects.join(', ')}',
      );
    });

    test('the authorised actor attaches, and reads both halves back', () async {
      final sale = await record();
      final answer = await attach(sale);

      expect(answer['status'], 'registered');
      expect(answer['revenue_entry_id'], sale);
      expect(
        answer['storage_path'],
        startsWith('org/$orgId/revenue/$sale/'),
        reason: 'the server derives the path; it does not accept the caller\'s',
      );

      // The metadata row.
      final rows = await client
          .from('revenue_attachments')
          .select()
          .eq('revenue_entry_id', sale);
      expect(rows, hasLength(1));
      expect(rows.first['file_name'], 'z-report.jpg');
      expect(rows.first['content_hash'], answer['content_hash']);

      // And the object itself.
      final bytes = await client.storage
          .from(bucket)
          .download(answer['storage_path'] as String);
      expect(bytes, isNotEmpty);
    });

    test('attaching moves no financial figure (§25)', () async {
      final sale = await record();
      final before = await client
          .from('revenue_document')
          .select()
          .eq('id', sale)
          .single();

      await attach(sale);

      final after = await client
          .from('revenue_document')
          .select()
          .eq('id', sale)
          .single();
      for (final field in const [
        'gross_amount_minor',
        'tax_amount_minor',
        'net_amount_minor',
        'business_date',
        'pnl_period_key',
        'txn_number',
        'row_version',
        'business_date_source',
        'component_count',
      ]) {
        expect(
          after[field],
          before[field],
          reason: '$field changed because a file was attached',
        );
      }
    });

    test('a redelivery is idempotent: one object, one row', () async {
      final sale = await record();
      final attachmentId = const Uuid().v4();

      final first = await attach(sale, attachmentId: attachmentId);
      final replay = await attach(sale, attachmentId: attachmentId);

      expect(first['status'], 'registered');
      expect(
        replay['status'],
        'replayed',
        reason: 'the mutation id replays its stored answer (D-004)',
      );
      expect(replay['storage_path'], first['storage_path']);
      expect(
        await client
            .from('revenue_attachments')
            .select('id')
            .eq('revenue_entry_id', sale),
        hasLength(1),
      );
      // The object path is deterministic, so the second upload overwrote itself.
      final listing = await client.storage
          .from(bucket)
          .list(path: 'org/$orgId/revenue/$sale');
      expect(listing, hasLength(1));
    });

    test(
      'the same id with different content is refused, never overwritten',
      () async {
        final sale = await record();
        final attachmentId = const Uuid().v4();
        await attach(sale, attachmentId: attachmentId);

        // A fresh delivery of the same file id with different bytes. The mutation id
        // has to differ or this replays the first answer and proves nothing — which is
        // exactly what the first version of this test did.
        await expectLater(
          attach(
            sale,
            attachmentId: attachmentId,
            bytes: evidenceBytes(11),
            mutationId: const Uuid().v4(),
          ),
          throwsA(predicate((Object e) => refusalOf(e) == 'KM009')),
        );
      },
    );

    test('a path that does not belong to the attachment is refused', () async {
      final sale = await record();
      final other = await record();
      final attachmentId = const Uuid().v4();
      final bytes = evidenceBytes();
      await client.storage
          .from(bucket)
          .uploadBinary(
            pathFor(sale, attachmentId),
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      createdObjects.add(pathFor(sale, attachmentId));

      await expectLater(
        client.rpc<dynamic>(
          'revenue_attachment_register',
          params: {
            'p_id': attachmentId,
            'p_revenue_entry_id': sale,
            'p_file_name': 'z-report.jpg',
            'p_content_type': 'image/jpeg',
            'p_byte_size': bytes.length,
            'p_content_hash': sha256.convert(bytes).toString(),
            // Somebody else's sale.
            'p_storage_path': pathFor(other, attachmentId),
            'p_mutation_id': const Uuid().v4(),
          },
        ),
        throwsA(predicate((Object e) => refusalOf(e) == 'KM010')),
      );
    });

    test('a voided sale keeps its evidence and accepts none (§30)', () async {
      final sale = await record();
      await attach(sale);

      final doc = await client
          .from('revenue_document')
          .select('row_version')
          .eq('id', sale)
          .single();
      await client.rpc<dynamic>(
        'revenue_void',
        params: {
          'p_id': sale,
          'p_base_row_version': doc['row_version'],
          'p_reason': '$marker void with evidence',
          'p_mutation_id': const Uuid().v4(),
        },
      );

      expect(
        await client
            .from('revenue_attachments')
            .select('id')
            .eq('revenue_entry_id', sale),
        hasLength(1),
        reason: 'a void does not destroy the evidence for what was recorded',
      );
      await expectLater(
        attach(sale),
        throwsA(predicate((Object e) => refusalOf(e) == 'KM020')),
      );
    });

    group('who may have it', () {
      test('a wrong-property manager cannot enumerate the metadata', () async {
        final sale = await record();
        final registered = await attach(sale);

        // Hotel Krishna's manager, looking at a Crystal Canopy sale.
        final hki = await sessionFor('hki.manager@example.com');
        expect(
          await hki
              .from('revenue_attachments')
              .select()
              .eq('revenue_entry_id', sale),
          isEmpty,
          reason: 'RLS, not a hidden control',
        );
        expect(
          await hki.from('revenue_attachments').select(),
          isEmpty,
          reason: 'and not by asking for everything either',
        );

        // Nor the object, which is Storage refusing on its own predicate.
        await expectLater(
          hki.storage
              .from(bucket)
              .download(registered['storage_path'] as String),
          throwsA(anything),
        );

        // Nor may they register one against it.
        await expectLater(
          attach(sale, as: hki),
          throwsA(anything),
          reason: 'attaching implies reading back',
        );
      });

      test('the property\'s own manager may read it', () async {
        final sale = await record();
        final registered = await attach(sale);

        final ccr = await sessionFor('ccr.manager@example.com');
        expect(
          await ccr
              .from('revenue_attachments')
              .select('file_name')
              .eq('revenue_entry_id', sale),
          hasLength(1),
          reason:
              'canonical evidence follows the parent sale\'s read authority',
        );
        final bytes = await ccr.storage
            .from(bucket)
            .download(registered['storage_path'] as String);
        expect(bytes, isNotEmpty);
      });

      test('a revoked user loses both halves, and gets them back on restore', () async {
        // The one case the scoped-manager test cannot cover: not "somebody who never
        // had it", but somebody whose access is *withdrawn*. Server-side that is the
        // same predicate re-evaluated — there is no per-session cache to invalidate —
        // and this proves it rather than arguing it.
        final sale = await record();
        final registered = await attach(sale);
        final path = registered['storage_path'] as String;

        final ccr = await sessionFor('ccr.manager@example.com');
        expect(
          await ccr
              .from('revenue_attachments')
              .select('id')
              .eq('revenue_entry_id', sale),
          hasLength(1),
          reason: 'held before the revocation, or the rest proves nothing',
        );

        await signInAs('giridhar@hki.com');
        final target = await client
            .from('profiles')
            .select('id')
            .eq('email', 'ccr.manager@example.com')
            .single();
        final grant = await client
            .from('user_roles')
            .select('id, roles!inner(code)')
            .eq('user_id', target['id'] as String)
            .eq('business_unit_id', ccrUnit)
            .isFilter('revoked_at', null)
            .single();
        final roleCode =
            (grant['roles'] as Map<String, dynamic>)['code'] as String;

        await client.rpc<dynamic>(
          'user_role_revoke',
          params: {'p_grant_id': grant['id']},
        );

        try {
          // A fresh session, because the point is what the *server* now decides.
          final revoked = await sessionFor(
            'ccr.manager@example.com',
            tag: 'slice11-revoked',
          );
          expect(
            await revoked
                .from('revenue_attachments')
                .select('id')
                .eq('revenue_entry_id', sale),
            isEmpty,
            reason: 'the metadata row is gone from their reach',
          );
          await expectLater(
            revoked.storage.from(bucket).download(path),
            throwsA(anything),
            reason: 'and so is the object',
          );
        } finally {
          // Restored, and **read back** rather than assumed: a restore is not restored
          // until it has been read back (D-142).
          await signInAs('giridhar@hki.com');
          await client.rpc<dynamic>(
            'user_role_grant',
            params: {
              'p_user_id': target['id'],
              'p_role_code': roleCode,
              'p_business_unit_id': ccrUnit,
            },
          );
          final back = await client
              .from('user_roles')
              .select('id')
              .eq('user_id', target['id'] as String)
              .eq('business_unit_id', ccrUnit)
              .isFilter('revoked_at', null);
          expect(
            back,
            hasLength(1),
            reason: 'the development grant fixture is left as it was found',
          );
        }
      });

      test('an anonymous caller gets neither half', () async {
        final sale = await record();
        final registered = await attach(sale);

        final anon = SupabaseClient(
          config['SUPABASE_URL'] as String,
          config['SUPABASE_ANON_KEY'] as String,
        );
        // Refused outright or answered with nothing — both are "no", and which one the
        // stack chooses is not a product decision worth pinning.
        try {
          expect(await anon.from('revenue_attachments').select(), isEmpty);
        } on PostgrestException {
          // refused, which is the stronger of the two
        }
        await expectLater(
          anon.storage
              .from(bucket)
              .download(registered['storage_path'] as String),
          throwsA(anything),
        );
        await expectLater(
          anon.rpc<dynamic>(
            'revenue_attachment_register',
            params: {
              'p_id': const Uuid().v4(),
              'p_revenue_entry_id': sale,
              'p_file_name': 'x.jpg',
              'p_content_type': 'image/jpeg',
              'p_byte_size': 10,
              'p_content_hash': 'x',
              'p_storage_path': 'x',
            },
          ),
          throwsA(anything),
          reason: 'nothing in public is callable by anon (D-044)',
        );
      });

      test('the expense prefix and the revenue prefix decide separately', () async {
        // A revenue object must not be reachable through the expense predicate, and the
        // reverse. Proven on the parsers, which are what the two policies branch on.
        final probe = await client.rpc<dynamic>(
          'storage_revenue_id',
          params: {'p_name': 'org/$orgId/expenses/${const Uuid().v7()}/a.jpg'},
        );
        expect(probe, isNull);
        final other = await client.rpc<dynamic>(
          'storage_expense_id',
          params: {'p_name': 'org/$orgId/revenue/${const Uuid().v7()}/a.jpg'},
        );
        expect(other, isNull);
      });
    });

    test('the bucket is private: no unauthenticated URL serves an object', () async {
      final sale = await record();
      final registered = await attach(sale);
      final path = registered['storage_path'] as String;

      // A public bucket would serve this to anybody who could guess the path — and the
      // path is deliberately guessable, because path secrecy is not authorisation
      // (spec §15.2). So the check is what an unauthenticated fetch actually returns.
      final publicUrl = client.storage.from(bucket).getPublicUrl(path);
      final response = await HttpClient()
          .getUrl(Uri.parse(publicUrl))
          .then((request) => request.close());
      expect(
        response.statusCode,
        greaterThanOrEqualTo(400),
        reason:
            'financial evidence is never in a public bucket, and this is the fetch '
            'rather than the configuration saying so (§5)',
      );
      // The bucket's own flag is asserted at deploy time by the migration, where the
      // catalogue is actually readable; no client role may list buckets, which is
      // itself the right answer.
    });
  });
}
