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
}
