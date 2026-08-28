/// The same rules exist twice by design — once in Dart for the interface, once in
/// Postgres for the guarantee (D-037). That duplication is deliberate and it is also the
/// obvious place for a silent defect: a capability added to the enum and not to the
/// catalogue, a role bundle widened on one side only, two seeds describing the same
/// hierarchy under different ids.
///
/// None of that fails loudly at runtime. A missing capability code simply means a grant
/// that never matches; a widened bundle simply means someone can do more than intended.
/// So the migrations are read as text and compared against the domain here, in a test
/// that needs no backend and runs on every build.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/local/seed/master_seed.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:uuid/uuid.dart';

/// Every migration, concatenated in the order Postgres applies them.
///
/// The catalogue and the bundles are not established once and left alone: a later
/// migration adds a capability, or grants an existing one to a role. Reading only the
/// original file made this comparison silently incomplete — it passed while Dart knew a
/// capability Postgres had never heard of.
String _allMigrations() {
  final files =
      Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    throw StateError('no migrations to compare the domain against');
  }
  return files.map((f) => f.readAsStringSync()).join('\n');
}

String _migration(String name) {
  final file = File('supabase/migrations/$name');
  if (!file.existsSync()) {
    throw StateError(
      'migration $name is missing — the schema and the domain cannot be compared',
    );
  }
  return file.readAsStringSync();
}

/// Capability codes from every `insert into public.capabilities` block.
Set<String> _catalogueCodes(String sql) {
  final blocks = RegExp(
    r'insert into public\.capabilities[\s\S]*?on conflict',
  ).allMatches(sql);
  expect(
    blocks,
    isNotEmpty,
    reason: 'no capability catalogue insert was found',
  );
  return {
    for (final block in blocks)
      ...RegExp(
        r"\('([a-z0-9_.]+)',\s*'[a-z_]+',",
      ).allMatches(block.group(0)!).map((m) => m.group(1)!),
  };
}

/// Capabilities granted to [roleCode] by any migration after the seed.
///
/// The seed states each bundle in full; a later migration adds one capability to some of
/// them. Both count, and reading only the seed made this comparison quietly incomplete.
/// Matched as one shape rather than by splitting into blocks, because the surrounding
/// SQL is not reliably delimited.
Set<String> _laterGrants(String sql, String roleCode) => {
  for (final match in RegExp(
    r"select r\.id, '([a-z0-9_.]+)'[\s\S]{0,200}?r\.code in \(([^)]*)\)",
  ).allMatches(sql))
    if (match.group(2)!.contains("'$roleCode'")) match.group(1)!,
};

/// The capability codes granted to one role in the seed migration.
Set<String> _bundle(String sql, String roleCode) {
  final block = RegExp(
    "select app\\.seed_id\\('role:$roleCode'\\), code from unnest\\(array\\[([\\s\\S]*?)\\]\\)",
  ).firstMatch(sql);
  expect(
    block,
    isNotNull,
    reason: 'no capability bundle found for role $roleCode',
  );
  return RegExp(
    r"'([a-z0-9_.]+)'",
  ).allMatches(block!.group(1)!).map((m) => m.group(1)!).toSet();
}

void main() {
  // The seed and the full corpus; the identity migration is read through the corpus.
  final seed = _migration('20260827091200_seed.sql');
  final everything = _allMigrations();

  group('capability catalogue', () {
    test('Postgres knows exactly the capabilities the domain defines', () {
      final inDart = {for (final c in Capability.values) c.code};
      final inSql = _catalogueCodes(everything);

      expect(
        inSql.difference(inDart),
        isEmpty,
        reason:
            'the catalogue grants codes the application has no capability for',
      );
      expect(
        inDart.difference(inSql),
        isEmpty,
        reason:
            'a capability exists in Dart with no catalogue row — every grant of it '
            'would silently fail the foreign key, or never be grantable at all',
      );
    });

    test('the catalogue has no duplicate codes', () {
      // Only the catalogue inserts, not every parenthesised pair in every migration —
      // `('x', 'y',` is a common enough shape in SQL to make a whole-file scan noise.
      final codes = [
        for (final block in RegExp(
          r'insert into public\.capabilities[\s\S]*?on conflict',
        ).allMatches(everything))
          ...RegExp(
            r"\('([a-z0-9_.]+)',\s*'[a-z_]+',",
          ).allMatches(block.group(0)!).map((m) => m.group(1)!),
      ];
      expect(codes.length, codes.toSet().length);
    });
  });

  group('role bundles', () {
    test('Owner holds every capability, on both sides', () {
      // The Owner bundle is inserted as "select every row from capabilities", so the
      // assertion that matters is the Dart one: nothing may be excluded from it.
      expect(RoleTemplates.owner.length, Capability.values.length);
      expect(
        seed,
        contains(
          "select app.seed_id('role:owner'), c.code from public.capabilities c",
        ),
      );
    });

    test('Manager grants the same capabilities in Dart and in Postgres', () {
      expect(
        _bundle(seed, 'manager').union(_laterGrants(everything, 'manager')),
        {for (final c in RoleTemplates.manager) c.code},
      );
    });

    test('Accountant grants the same capabilities in Dart and in Postgres', () {
      expect(
        _bundle(
          seed,
          'accountant',
        ).union(_laterGrants(everything, 'accountant')),
        {for (final c in RoleTemplates.accountant) c.code},
      );
    });

    test('Data Entry grants the same capabilities in Dart and in Postgres', () {
      expect(
        _bundle(
          seed,
          'data_entry',
        ).union(_laterGrants(everything, 'data_entry')),
        {for (final c in RoleTemplates.dataEntry) c.code},
      );
    });

    test('no non-Owner role can manage masters, tax, users, roles or periods', () {
      // Not a restatement of the bundles above: this is the property the owner asked for
      // in requirement §18.3, checked against the SQL that will actually be applied.
      const administrative = {
        'masters.manage',
        'tax.manage',
        'users.manage',
        'roles.manage',
        'settings.manage',
        'period.close',
        'period.reopen',
      };
      for (final role in ['manager', 'accountant', 'data_entry']) {
        expect(
          _bundle(seed, role).intersection(administrative),
          isEmpty,
          reason: '$role must not hold an administrative capability',
        );
      }
    });

    test(
      'only Owner is unscoped; every other role must name a business unit',
      () {
        expect(
          RoleTemplates.requiresUnitScope(RoleTemplates.ownerCode),
          isFalse,
        );
        for (final role in [
          RoleTemplates.managerCode,
          RoleTemplates.accountantCode,
          RoleTemplates.dataEntryCode,
        ]) {
          expect(RoleTemplates.requiresUnitScope(role), isTrue);
        }
        expect(seed, contains("'owner',      'Owner',      true, false"));
      },
    );
  });

  group('seed identity', () {
    test('the Dart and Postgres seeds share one namespace', () {
      final inSql = RegExp(
        r"'([0-9a-f-]{36})'::uuid, p_path",
      ).firstMatch(seed)?.group(1);
      expect(inSql, seedNamespace);
    });

    test('the two seeds describe the same hierarchy, path for path', () {
      final inSql = RegExp(r"seed_id\('([^']+)'\)")
          .allMatches(seed)
          .map((m) => m.group(1)!)
          .where((p) => !p.startsWith('role:'))
          .toSet();

      // Paths built with format() at run time appear in the SQL as templates, so compare
      // only the literal ones plus the templated shapes the loop produces.
      final templated = RegExp(
        r"format\('([a-z]+):",
      ).allMatches(seed).map((m) => m.group(1)!).toSet();
      expect(
        templated,
        containsAll(<String>{'dept', 'sec', 'cat'}),
        reason:
            'the hierarchy loop should derive department, section and category ids',
      );

      final dartLiterals = seedPaths()
          .where(
            (p) =>
                !p.startsWith('dept:') &&
                !p.startsWith('sec:') &&
                !p.startsWith('cat:'),
          )
          .toSet();
      expect(
        inSql,
        dartLiterals,
        reason:
            'the organisation, business units, revenue categories and payment '
            'methods must be identical in both seeds',
      );
    });

    test('every seeded expense category in the SQL exists in the Dart seed', () {
      // The SQL hierarchy is a VALUES list; each row names unit / department / section /
      // category, which is exactly a `cat:` path.
      final rows = RegExp(
        r"\('(CCR|HKI)','([A-Z_]+)','[^']*',\d+,'([A-Z_]+)','[^']*',\d+,'([A-Z_]+)'",
      ).allMatches(seed);
      expect(
        rows,
        isNotEmpty,
        reason: 'the hierarchy VALUES list was not found',
      );

      final fromSql = {
        for (final m in rows)
          'cat:${m.group(1)}/${m.group(2)}/${m.group(3)}/${m.group(4)}',
      };
      final fromDart = seedPaths().where((p) => p.startsWith('cat:')).toSet();
      expect(fromSql, fromDart);
    });

    test('the derivation matches an independent UUID v5 implementation', () {
      // `uuid_generate_v5` in Postgres and `Uuid().v5` here must be the same algorithm —
      // SHA-1 over namespace and name — or the two seeds produce different ids for the
      // same record and the whole scheme is worse than useless.
      //
      // The Dart side is pinned to published vectors first, then to the exact values a
      // separate implementation produces for this project's namespace. Both sets were
      // generated by Python's `uuid` module, which shares no code with either.
      expect(
        const Uuid().v5(Namespace.dns.value, 'www.example.com'),
        '2ed6657d-e927-568b-95e1-2665a8aea6a2',
      );
      expect(
        const Uuid().v5(Namespace.dns.value, 'python.org'),
        '886313e1-3b8a-5372-9b90-0c9aee199e5d',
      );

      expect(seedId('org:KRISHNA'), '5341bd8e-65f1-5825-84d0-2c3bca9ba8fc');
      expect(seedId('bu:CCR'), 'ce13c1ce-daed-5084-a23c-c35bb8da0fa8');
      expect(seedId('bu:HKI'), '061dfcf5-10bc-58d5-9700-0ffa0e659abe');
      expect(
        seedId('rev:CCR/NANDBHOG'),
        'af354a6d-b0ba-5bc0-8cdb-f66a5e169256',
      );
      expect(
        seedId('cat:CCR/FB/FOOD_PROD/KIRANA'),
        '88887d0a-9864-5a57-aa95-fb41d1848fb2',
      );

      final id = seedId('bu:CCR');
      expect(id[14], '5', reason: 'the version nibble must be 5');
      expect('89ab'.contains(id[19]), isTrue, reason: 'RFC 4122 variant');
    });
  });

  group('the guarantees the migrations claim', () {
    final masters = _migration('20260827090200_masters.sql');
    final integrity = _migration('20260827090300_master_integrity.sql');
    final rls = _migration('20260827090900_rls.sql');

    test(
      'the hierarchy is pinned by composite foreign keys, not by a bare parent id',
      () {
        expect(
          masters,
          contains('foreign key (org_id, business_unit_id, department_id)'),
        );
        expect(
          masters,
          contains(
            'foreign key (org_id, business_unit_id, department_id, section_id)',
          ),
        );
      },
    );

    test('a master cannot change business unit', () {
      expect(integrity, contains('refuse_reparent_across_units'));
    });

    test('archiving refuses while live children exist (D-039)', () {
      expect(integrity, contains('has_active_children'));
      expect(integrity, contains('refuse_archive_with_live_children'));
      // D-039 forbids a cascade in V1. Nothing may archive a child on a parent's behalf,
      // and no referencing key may delete one either.
      expect(integrity.toLowerCase(), isNot(contains('on delete cascade')));
      expect(masters.toLowerCase(), isNot(contains('on delete cascade')));
      expect(
        RegExp(r'update public\.\w+ set archived_at').allMatches(integrity),
        isEmpty,
        reason: 'the archive guard must refuse, never archive anything itself',
      );
    });

    test('write access is revoked from every client role', () {
      expect(rls, contains('revoke all on public.%I from anon, authenticated'));
      expect(rls, contains('enable row level security'));
    });

    test('every table listed for RLS is one the schema actually creates', () {
      final listed = RegExp(
        r"foreach t in array array\[([\s\S]*?)\]",
      ).firstMatch(rls)!.group(1)!;
      final tables = RegExp(
        r"'([a-z_]+)'",
      ).allMatches(listed).map((m) => m.group(1)!).toSet();
      final created = <String>{};
      for (final name in [
        '20260827090100_identity.sql',
        '20260827090200_masters.sql',
        '20260827090400_user_roles.sql',
        '20260827090500_period_control.sql',
        '20260827090600_tax_rules.sql',
        '20260827090700_audit_and_usage.sql',
      ]) {
        created.addAll(
          RegExp(
            r'create table if not exists public\.([a-z_]+)',
          ).allMatches(_migration(name)).map((m) => m.group(1)!),
        );
      }
      expect(
        created.difference(tables),
        isEmpty,
        reason:
            'a table exists with no RLS — it would be readable by any authenticated '
            'user in any organisation',
      );
      expect(tables.difference(created), isEmpty);
    });
  });
}
