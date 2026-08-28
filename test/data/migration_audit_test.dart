/// A pre-deployment audit of the migrations, run as a test so it keeps running.
///
/// Everything here was checked by hand once. Checking it by hand once is worth very
/// little: the next migration is written weeks later by somebody who has forgotten which
/// invariants were load-bearing. A `SECURITY DEFINER` function without a fixed
/// `search_path` is a privilege-escalation vector; a function left with the default
/// `PUBLIC EXECUTE` is reachable by `anon`; a table created after the file that
/// references it will not apply at all. None of those announce themselves.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _dir = Directory('supabase/migrations');

List<({String name, String sql})> _migrations() {
  final files =
      _dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      (name: f.uri.pathSegments.last, sql: f.readAsStringSync()),
  ];
}

/// Each function definition, paired with the header text up to its body.
Iterable<({String file, String name, String header})> _functions() sync* {
  final pattern = RegExp(
    r'create or replace function\s+([\w.]+)\s*\([\s\S]*?\)\s*returns[\s\S]*?as \$\$',
  );
  for (final m in _migrations()) {
    for (final match in pattern.allMatches(m.sql)) {
      yield (file: m.name, name: match.group(1)!, header: match.group(0)!);
    }
  }
}

void main() {
  group('privilege', () {
    test('every SECURITY DEFINER function fixes its search_path', () {
      // Without this a caller can prepend a schema of their own and have the function —
      // running with the owner's rights — call their table or their operator instead.
      final offenders = [
        for (final f in _functions())
          if (f.header.contains('security definer') &&
              !f.header.contains("set search_path = ''"))
            '${f.file}: ${f.name}',
      ];
      expect(offenders, isEmpty);
    });

    test('there are SECURITY DEFINER functions to check in the first place', () {
      // Guards the regex above: a parser that silently matches nothing would make every
      // other assertion in this group vacuously true.
      final definers = _functions()
          .where((f) => f.header.contains('security definer'))
          .length;
      expect(definers, greaterThan(20));
    });

    test(
      'PUBLIC loses EXECUTE, and the migration proves it rather than assuming',
      () {
        final grants = _migrations()
            .firstWhere((m) => m.name.endsWith('_function_grants.sql'))
            .sql;
        expect(grants, contains('revoke all on function %s from public'));
        expect(grants, contains("has_function_privilege('anon'"));
        expect(
          grants,
          contains('raise exception'),
          reason: 'the check must fail the migration, not merely report',
        );
        expect(
          grants,
          contains('alter default privileges in schema public revoke execute'),
          reason: 'the next function written must start closed',
        );
      },
    );

    test('every function exposed in public is on the reviewed API surface', () {
      // The authoritative list lives in the *latest* migration that restates it.
      // 0015 asserted the surface when it was 19 functions long; three were added
      // afterwards, so 0021 restates it in full. Migrations are immutable history —
      // the earlier assertion was correct when it ran and is not rewritten — so this
      // test reads whichever migration currently owns the invariant.
      final invariant = _migrations()
          .lastWhere((m) => m.name.endsWith('_api_surface_invariant.sql'))
          .sql;

      final defined = <String>{
        for (final f in _functions())
          if (f.name.startsWith('public.')) f.name.substring('public.'.length),
      };
      final declared = RegExp(
        r'v_api\s+text\[\]\s*:=\s*array\[([\s\S]*?)\];',
      ).firstMatch(invariant)!.group(1)!;
      final allowed = RegExp(
        r"'(\w+)'",
      ).allMatches(declared).map((m) => m.group(1)!).toSet();

      expect(
        defined.difference(allowed),
        isEmpty,
        reason:
            'a public function exists that the API-surface invariant does not name — '
            'the migration would fail, which is the right outcome, but the list must '
            'be extended deliberately, not discovered at deploy time',
      );
      expect(
        allowed.difference(defined),
        isEmpty,
        reason:
            'the invariant names a function no migration defines — it would refuse to '
            'grant, breaking the client just as completely as over-exposing one',
      );

      // Being on the list is not the same as being callable. Each reviewed function
      // must actually be granted somewhere — the grant may live in the migration that
      // introduced it rather than in the original grants migration.
      final everySql = _migrations().map((m) => m.sql).join('\n');
      for (final name in defined) {
        expect(
          everySql,
          contains('grant execute on function public.$name('),
          reason:
              '$name is defined and reviewed but never granted to authenticated',
        );
      }
    });

    test('the owner bootstrap is never reachable by a client', () {
      final bootstrap = _migrations()
          .firstWhere((m) => m.name.endsWith('_owner_bootstrap.sql'))
          .sql;
      expect(
        bootstrap,
        contains(
          'revoke all on function app.bootstrap_owner(text, text, boolean) '
          'from anon, authenticated',
        ),
      );
      expect(
        bootstrap.contains('grant execute on function app.bootstrap_owner'),
        isFalse,
      );
    });
  });

  group('scope', () {
    test('the expense tables exist, and nothing beyond them does', () {
      // This guard used to say "no Phase 3 table is created early", which was right
      // while Phase 3 was a plan. Phase 3 is approved and under way, so the guard is
      // inverted rather than deleted: the expense tables are now expected, and the ones
      // belonging to later phases still must not appear before their phase does.
      const phase3 = {
        'expenses',
        'expense_allocations',
        'expense_period_allocations',
        'expense_attachments',
      };
      const laterPhases = {'revenue_entries', 'approval_requests'};

      final created = <String>{};
      for (final m in _migrations()) {
        created.addAll(
          RegExp(
            r'create table if not exists public\.([a-z_]+)',
          ).allMatches(m.sql).map((match) => match.group(1)!),
        );
      }

      expect(
        phase3.difference(created),
        isEmpty,
        reason: 'the Phase 3 expense schema is incomplete',
      );
      expect(
        created.intersection(laterPhases),
        isEmpty,
        reason:
            'a table belonging to a later phase must not be created early merely '
            'because it is a known future requirement',
      );
    });

    test('no tax rate is seeded (D-043)', () {
      final seed = _migrations()
          .firstWhere((m) => m.name.endsWith('_seed.sql'))
          .sql;
      expect(
        seed.contains('insert into public.revenue_tax_rates'),
        isFalse,
        reason:
            'no default rate, no assumed 5%, no assumed 18%, no inherited treatment',
      );
    });

    test('no migration embeds credential material', () {
      for (final m in _migrations()) {
        expect(m.sql.contains('sb_secret_'), isFalse, reason: m.name);
        expect(m.sql.contains('service_role_key'), isFalse, reason: m.name);
        expect(
          RegExp(r'postgres(ql)?://[^\s]*:[^\s]*@').hasMatch(m.sql),
          isFalse,
          reason: m.name,
        );
        expect(m.sql.contains('BEGIN PRIVATE KEY'), isFalse, reason: m.name);
      }
    });
  });

  group('ordering', () {
    test('no migration references a table created in a later one', () {
      final all = _migrations();
      final createdIn = <String, int>{};
      for (var i = 0; i < all.length; i++) {
        for (final match in RegExp(
          r'create table if not exists public\.([a-z_]+)',
        ).allMatches(all[i].sql)) {
          createdIn.putIfAbsent(match.group(1)!, () => i);
        }
      }

      final problems = <String>[];
      for (var i = 0; i < all.length; i++) {
        for (final match in RegExp(
          r'references public\.([a-z_]+)',
        ).allMatches(all[i].sql)) {
          final table = match.group(1)!;
          final at = createdIn[table];
          if (at == null || at > i) {
            problems.add('${all[i].name} references $table');
          }
        }
      }
      expect(problems, isEmpty);
    });

    test('no migration calls a helper defined in a later one', () {
      final all = _migrations();
      final definedIn = <String, int>{};
      for (var i = 0; i < all.length; i++) {
        for (final match in RegExp(
          r'create or replace function\s+app\.(\w+)',
        ).allMatches(all[i].sql)) {
          definedIn.putIfAbsent(match.group(1)!, () => i);
        }
      }

      final problems = <String>[];
      for (var i = 0; i < all.length; i++) {
        for (final match in RegExp(
          r'\bapp\.(\w+)\s*\(',
        ).allMatches(all[i].sql)) {
          final fn = match.group(1)!;
          final at = definedIn[fn];
          if (at != null && at > i) {
            problems.add('${all[i].name} calls app.$fn before it exists');
          }
        }
      }
      expect(problems, isEmpty);
    });
  });

  group('the client is never believed', () {
    test('no function takes a role, owner or authority claim as a parameter', () {
      // A parameter named like an authority *claim* is the shape of the bug: the client
      // asserting what it is allowed to do. Authority is derived from auth.uid() and the
      // stored grants, never from the payload.
      //
      // `p_capability` is deliberately not on this list. Naming the capability being
      // asked about is a question — `has_capability('masters.manage', unit)` — not an
      // assertion that the caller holds it.
      final suspicious = RegExp(
        r'p_(is_owner|is_admin|is_superuser|role_claims?|granted|authorized|'
        r'has_permission|bypass|skip_check)\b',
      );
      for (final m in _migrations()) {
        expect(suspicious.hasMatch(m.sql), isFalse, reason: m.name);
      }

      // And the subject of an authorisation check is always auth.uid(), never a user id
      // the caller chose. `user_role_grant(p_user_id, ...)` names the person being
      // granted something; the authority to do the granting is still the caller's.
      final authorization = _migrations()
          .firstWhere((m) => m.name.endsWith('_authorization.sql'))
          .sql;
      expect(
        RegExp(r'ur\.user_id\s*=\s*p_').hasMatch(authorization),
        isFalse,
        reason:
            'a capability lookup keyed on a caller-supplied user id would let anyone '
            'borrow another user permissions',
      );
      expect(authorization, contains('ur.user_id = (select auth.uid())'));
    });

    test('every RPC derives the organisation from the caller, not the request', () {
      // `p_org_id` anywhere in a client-callable function would mean the caller chose its
      // own tenancy. The organisation comes from `app.current_org_id()`, which reads the
      // caller's profile row.
      for (final f in _functions().where((f) => f.name.startsWith('public.'))) {
        expect(
          f.header.contains('p_org_id'),
          isFalse,
          reason: '${f.name} accepts an organisation id from the client',
        );
      }
      final rpcFiles = _migrations().where(
        (m) =>
            m.name.contains('_rpcs.sql') ||
            m.name.endsWith('_owner_bootstrap.sql'),
      );
      for (final m in rpcFiles) {
        expect(m.sql, contains('app.current_org_id()'), reason: m.name);
      }
    });

    test(
      'dynamic SQL is built with format(), never by concatenating a parameter',
      () {
        for (final m in _migrations()) {
          final concatenated = RegExp(
            r"execute\s+'[^']*'\s*\|\|",
          ).hasMatch(m.sql);
          expect(
            concatenated,
            isFalse,
            reason: '${m.name} concatenates into EXECUTE',
          );
        }
      },
    );

    test('clients hold no write grant on any table', () {
      final rls = _migrations()
          .firstWhere((m) => m.name.endsWith('_rls.sql'))
          .sql;
      expect(rls, contains('revoke all on public.%I from anon, authenticated'));
      expect(
        RegExp(r'grant (insert|update|delete)').hasMatch(rls),
        isFalse,
        reason: 'every mutation must travel through a SECURITY DEFINER RPC',
      );
      for (final m in _migrations()) {
        expect(
          RegExp(
            r'grant (insert|update|delete)[^;]*to (anon|authenticated)',
          ).hasMatch(m.sql),
          isFalse,
          reason: '${m.name} grants a client direct write access',
        );
      }
    });

    test('the audit trail and the mutation ledger cannot be amended', () {
      final audit = _migrations()
          .firstWhere((m) => m.name.endsWith('_audit_and_usage.sql'))
          .sql;
      expect(audit, contains('append_only_audit_logs'));
      expect(audit, contains('before update or delete on public.audit_logs'));
      expect(audit, contains('append_only_processed_mutations'));
    });
  });
}
