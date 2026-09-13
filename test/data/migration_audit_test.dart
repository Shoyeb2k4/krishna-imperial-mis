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

/// The functions that exist after replaying [migrations], paired with the header text up
/// to their latest body.
///
/// A historical definition is not an active API. Slice 7 removes one dead function, so
/// this scanner has to model `DROP FUNCTION` as well as `CREATE OR REPLACE`; otherwise the
/// API-surface guard itself would require a removed privilege to stay listed forever.
Iterable<({String file, String name, String header})> _functionsFrom(
  List<({String name, String sql})> migrations,
) sync* {
  // The body tag is `$$` in most migrations and a named tag such as `$fn$` where a
  // function's own text contains `$$`. Matching only the bare form is the D-103 mistake
  // in miniature: the parser keyed on an incidental convention, so three new
  // `security definer` predicates were invisible to every assertion in this group at
  // once, including the search_path one, which is the direction that fails quietly.
  final pattern = RegExp(
    r'create or replace function\s+([\w.]+)\s*\([\s\S]*?\)\s*returns[\s\S]*?as \$\w*\$',
    caseSensitive: false,
  );
  final drop = RegExp(
    r'drop function(?: if exists)?\s+([\w.]+)\s*\(',
    caseSensitive: false,
  );
  final active = <String, ({String file, String name, String header})>{};

  for (final migration in migrations) {
    final events = <({int offset, bool creates, RegExpMatch match})>[
      for (final match in pattern.allMatches(migration.sql))
        (offset: match.start, creates: true, match: match),
      for (final match in drop.allMatches(migration.sql))
        (offset: match.start, creates: false, match: match),
    ]..sort((a, b) => a.offset.compareTo(b.offset));

    for (final event in events) {
      final name = event.match.group(1)!.toLowerCase();
      if (event.creates) {
        active[name] = (
          file: migration.name,
          name: name,
          header: event.match.group(0)!,
        );
      } else {
        active.remove(name);
      }
    }
  }

  yield* active.values;
}

Iterable<({String file, String name, String header})> _functions() =>
    _functionsFrom(_migrations());

/// The declaration of the reviewed API surface, wherever it currently lives.
final _apiSurfaceArray = RegExp(
  r'v_api\s+text\[\]\s*:=\s*array\[([\s\S]*?)\];',
);

Set<String> _deadGrantedCapabilities({
  required Set<String> granted,
  required Set<String> exempt,
  required String evaluators,
}) => {
  for (final capability in granted)
    if (!exempt.contains(capability) && !evaluators.contains(capability))
      capability,
};

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

    test('the active-function scanner sees drops and later recreations', () {
      const header =
          'create or replace function public.sample() returns int language sql '
          'security invoker set search_path = public, pg_temp as \$fn\$';
      final removed = _functionsFrom(const [
        (name: '001.sql', sql: '$header select 1 \$fn\$;'),
        (name: '002.sql', sql: 'drop function public.sample();'),
      ]).toList();
      expect(
        removed,
        isEmpty,
        reason:
            'a guard that counts historical definitions would force a removed API to '
            'stay reviewed and callable forever',
      );

      final recreated = _functionsFrom(const [
        (name: '001.sql', sql: '$header select 1 \$fn\$;'),
        (name: '002.sql', sql: 'drop function public.sample();'),
        (name: '003.sql', sql: '$header select 2 \$fn\$;'),
      ]).toList();
      expect(recreated, hasLength(1));
      expect(recreated.single.file, '003.sql');
    });

    test('the D-139 detector catches a granted capability with no evaluator', () {
      final dead = _deadGrantedCapabilities(
        granted: const {'synthetic.report.read'},
        exempt: const {},
        evaluators: 'an unrelated function body',
      );
      expect(
        dead,
        {'synthetic.report.read'},
        reason:
            'a production guard without a positive control can pass because its '
            'extractor stopped seeing grants or evaluators',
      );
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

    test('every applied migration is accounted for by a committed file (A0)', () {
      // A0's finding: the Slice 4 report claimed "seven migrations, all committed" while
      // the repository held two files for seven ledger versions. The SQL was equivalent;
      // the provenance was not, and equivalence is not what an audit trail is for.
      //
      // The ledger is the record. This makes it a checked one — a hand-maintained table
      // drifts exactly like the API surface list did, and for the same reason.
      final ledger = File('supabase/migrations/LEDGER.md').readAsStringSync();

      final applied = RegExp(r'^(\d{14}) (\w+)$', multiLine: true)
          .allMatches(
            ledger.substring(ledger.indexOf('The full applied ledger')),
          )
          .map((m) => (version: m.group(1)!, name: m.group(2)!))
          .toList();
      expect(
        applied.length,
        greaterThan(40),
        reason: 'the applied-ledger listing did not parse — the format moved',
      );

      // A version is accounted for by either route the ledger declares:
      //
      //   * a committed file whose name ends `_<ledger name>.sql` — the Phase 2 convention,
      //     where the repository's authored sequence number differs from Supabase's applied
      //     timestamp, so matching is by name; or
      //   * an explicit row in the grouped table above, for the twelve Phase 2/3 steps that
      //     were applied separately and committed together.
      //
      // Neither route is "the SQL is equivalent". Equivalence is not provenance.
      final committed = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.sql'))
          .toList();
      final accounting = ledger.substring(
        0,
        ledger.indexOf('The full applied ledger'),
      );

      final unaccounted = [
        for (final m in applied)
          if (!committed.any((f) => f.endsWith('_${m.name}.sql')) &&
              !accounting.contains(m.version))
            '${m.version} ${m.name}',
      ];
      expect(
        unaccounted,
        isEmpty,
        reason:
            'an applied migration has neither a committed file bearing its name nor a row '
            'explaining which file accounts for it. Add the file — or the row — rather '
            'than letting the ledger describe a repository that no longer matches the '
            'server (A0, and the D-056 rule it descends from)',
      );

      // And every file the ledger names by filename must actually exist.
      final named = RegExp(
        r'`(\d{14}_\w+\.sql)`',
      ).allMatches(ledger).map((m) => m.group(1)!);
      expect(named, isNotEmpty);
      for (final file in named) {
        expect(
          File('supabase/migrations/$file').existsSync(),
          isTrue,
          reason: 'the ledger names $file, which is not committed',
        );
      }
    });

    test('every function exposed in public is on the reviewed API surface', () {
      // The authoritative list lives in the *latest* migration that restates it.
      // 0015 asserted the surface when it was 19 functions long; three were added
      // afterwards, so 0021 restates it in full. Migrations are immutable history —
      // the earlier assertion was correct when it ran and is not rewritten — so this
      // test reads whichever migration currently owns the invariant.
      //
      // Identified by **what it does**, not by what it is called. This previously matched
      // on the filename ending `_api_surface_invariant.sql`, so Phase 4's
      // `..._api_surface_invariant_revenue.sql` did not match and the test silently read a
      // superseded list — reporting four legitimately reviewed RPCs as unnamed. A guard
      // keyed on a naming convention stops working the moment the convention moves.
      final restatements = _migrations()
          .where((m) => _apiSurfaceArray.hasMatch(m.sql))
          .toList();
      expect(
        restatements,
        isNotEmpty,
        reason:
            'no migration restates the API surface — the invariant has been lost',
      );
      final invariant = restatements.last.sql;

      final defined = <String>{
        for (final f in _functions())
          if (f.name.startsWith('public.')) f.name.substring('public.'.length),
      };
      final declared = _apiSurfaceArray.firstMatch(invariant)!.group(1)!;
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

    test('the unused expense whole-organisation helper is removed', () {
      const name = 'expense_sees_whole_org';
      final active = _functions().where((f) => f.name == 'public.$name');
      expect(
        active,
        isEmpty,
        reason:
            'the helper has no runtime caller. Keeping an authenticated executable '
            'function merely because it was once reviewed is an unnecessary privileged '
            'surface',
      );

      final restatements = _migrations()
          .where((m) => _apiSurfaceArray.hasMatch(m.sql))
          .toList();
      final latest = _apiSurfaceArray
          .firstMatch(restatements.last.sql)!
          .group(1)!;
      expect(latest, isNot(contains("'$name'")));

      final dartCallers = <String>[
        for (final entity in Directory('lib').listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              entity.readAsStringSync().contains(name))
            entity.path,
      ];
      expect(dartCallers, isEmpty);
    });

    test('no capability is granted in production and evaluated nowhere', () {
      // D-127 §3: `transaction.correct.business_date` was granted to two role bundles and
      // named by no function and no policy. A grant with no evaluator is the quieter twin
      // of D-068's rule that nothing evaluates — it reads like a permission model and
      // enforces nothing.
      //
      // The migrations are the whole authority here: the seed grants, the RPC bodies and
      // the policy expressions all live in this directory, so the question can be asked
      // statically without a database. The deploy-time form of the same assertion runs in
      // `20260905141738_expense_business_date_correction.sql` against the live catalogue,
      // which is what catches a grant made by hand.
      //
      // The exemption list is deliberately narrow and deliberately spelled out: a
      // capability is on it only because the surface it governs has not been built yet,
      // and a later phase has to delete its line. It must stay in step with the SQL, so
      // the SQL's own list is what is read rather than a second copy.
      // Comments are stripped first, and that is not tidiness. Counting a capability
      // wherever it appears would let the *paragraph explaining that nothing evaluates
      // it* count as its evaluator — which is precisely the failure this test exists to
      // detect, and which it committed on its first run before this line was added.
      final all = _migrations();
      final everySql = all
          .map((m) => m.sql.replaceAll(RegExp(r'--[^\n]*'), ''))
          .join('\n');

      final grantBlocks = RegExp(
        r'insert into public\.role_capabilities[\s\S]*?on conflict',
      ).allMatches(everySql).map((m) => m.group(0)!).join('\n');
      final granted = RegExp(
        r"'([a-z_]+(?:\.[a-z_]+)+)'",
      ).allMatches(grantBlocks).map((m) => m.group(1)!).toSet();
      expect(
        granted.length,
        greaterThan(15),
        reason:
            'the grant blocks did not parse — a guard that finds nothing to check '
            'reports success (D-103)',
      );

      // The **last** declaration, not the first. A later migration restates the list
      // whole when a capability stops being unbuilt — `reports.view` acquired an
      // evaluator at the reporting boundary and its line went — and reading the first
      // one would go on checking a list two migrations out of date while reporting
      // success. That is D-103's lesson in this file's own machinery: a guard keyed on
      // the wrong occurrence of the right thing has quietly stopped checking.
      final unbuiltDeclarations = RegExp(
        r'v_unbuilt constant text\[\] := array\[([\s\S]*?)\];',
      ).allMatches(everySql).toList();
      expect(
        unbuiltDeclarations,
        isNotEmpty,
        reason: 'the not-yet-built exemption list has been lost',
      );
      final unbuiltDeclaration = unbuiltDeclarations.last;
      final exempt = RegExp(r"'([a-z_.]+)'")
          .allMatches(unbuiltDeclaration.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      // Evaluated means: named inside a **function body** or a **policy expression** —
      // the two places a capability can actually decide something at run time. Named
      // anywhere else does not count, and the exclusions are the point:
      //
      //   * a comment can explain that nothing evaluates it;
      //   * an `insert into role_capabilities` grants it;
      //   * a deploy-time `do $$ … $$` block can *assert* that something evaluates it,
      //     which is a statement about the check rather than the check.
      //
      // All three were counted as evaluation by the first version of this test, and all
      // three let the sabotage control pass. Found by expecting red and getting green,
      // which is the fourth time this project has had to look for that (D-094).
      //
      // The body tag is captured rather than assumed to be a bare dollar-dollar. Three
      // `security definer` predicates once became invisible to an entire assertion group
      // because they were quoted with a named tag (D-155), and `reporting_primitives` —
      // the evaluator this list now depends on — is quoted the same way. A guard keyed on
      // an incidental quoting convention is the third instance of D-103 in this file's
      // history, and it is not going to be the fourth.
      final bodies = RegExp(
        r'create or replace function[\s\S]*?as (\$[a-z_]*\$)([\s\S]*?)\1;',
      ).allMatches(everySql).map((m) => m.group(2)!).join('\n');
      final policies = RegExp(
        r'create policy[\s\S]*?;',
      ).allMatches(everySql).map((m) => m.group(0)!).join('\n');
      final evaluators = '$bodies\n$policies';
      expect(
        evaluators.length,
        greaterThan(20000),
        reason:
            'the function-body and policy extraction found almost nothing — a guard '
            'that reads an empty haystack reports success',
      );

      final dead = _deadGrantedCapabilities(
        granted: granted,
        exempt: exempt,
        evaluators: evaluators,
      );

      expect(
        dead,
        isEmpty,
        reason:
            'granted and evaluated nowhere. Either write the check or withdraw the '
            'grant — and if the feature simply is not built yet, say so on the '
            'exemption list rather than leaving the next reader to guess (D-127)',
      );

      // The exemption list is not a place to park a shipped feature's capability.
      expect(
        exempt,
        isNot(contains('transaction.correct.business_date')),
        reason:
            'the surface it governs shipped in Phase 3; exempting it would be the '
            'defect this corrective exists to close, written down as policy',
      );

      // And `reports.view` is the same finding one phase later. Slice 5 shipped the
      // first client-callable P&L boundary, so the sentence that exempted it — *the
      // surface it governs does not exist yet* — stopped being true the moment that RPC
      // was granted to `authenticated`. Both halves are asserted: the excuse is gone,
      // and the check that replaced it exists.
      expect(
        exempt,
        isNot(contains('reports.view')),
        reason:
            'reporting_primitives is client-callable, so the surface reports.view '
            'governs exists; an excuse that has stopped being true is worse than no '
            'list at all (D-139, D-187)',
      );
      expect(
        evaluators,
        contains('reports.view'),
        reason:
            'reports.view is exempt nowhere and evaluated nowhere, which is the D-139 '
            'defect in reverse: the excuse was deleted without the check being written',
      );

      // Still exempt, and each for a surface that genuinely does not exist. Stated so
      // that removing one is a deliberate act rather than a side effect of editing the
      // line above it.
      expect(exempt, contains('reports.export'));
      expect(exempt, contains('reports.print'));
      expect(exempt, contains('settings.manage'));
    });

    test('the business-date correction is evaluated at the Expense boundary', () {
      // Not a documentation search. The assertion is over the function body that the
      // authoritative mutation boundary actually has.
      final expenseUpdates = _functions()
          .where((f) => f.name == 'public.expense_update')
          .toList();
      expect(expenseUpdates, isNotEmpty);

      final all = _migrations();
      final latest = all.lastWhere(
        (m) =>
            m.sql.contains('create or replace function public.expense_update'),
      );
      final body = latest.sql;

      expect(
        body,
        contains("app.require_capability('transaction.correct.business_date'"),
        reason: 'the capability must gate the act, not merely exist',
      );
      expect(
        body,
        contains(
          "has_capability_anywhere('transaction.correct.beyond_window')",
        ),
        reason:
            'and the window capability stays its own separate guard — capabilities '
            'compose, they do not replace one another',
      );
      expect(
        body,
        contains('from public.expense_period_allocations p'),
        reason:
            'the source periods are read from the one reporting source (D-060), so '
            'a cross-period bill is protected on every month it contributes to',
      );
      expect(
        body,
        contains("then 'corrected'"),
        reason: 'a moved date must record that it was moved (D-019)',
      );
      expect(
        body,
        contains("'expense_business_date_corrected'"),
        reason: 'the act gets its own audit action, not a disguised notes edit',
      );
    });

    test('there is one Expense correction contract, and it is expense_update', () {
      // D-127 finding 2: three canonical documents named `expense_correct_business_date`
      // and no such function has ever existed. Option A keeps one contract, so nothing in
      // the repository may create a second — and no forward-looking document may promise
      // one either. Historical decision entries describing the finding are exempt by
      // name, because this log is append-only.
      final everySql = _migrations().map((m) => m.sql).join('\n');
      expect(
        everySql,
        isNot(contains('function public.expense_correct_business_date')),
        reason:
            'two write paths for one financial document is the whole finding',
      );

      // A forward-looking document may **name** the phantom endpoint, and §24 of
      // `ARCHITECTURE.md` does — in the sentence saying it does not exist. What it may
      // not do is describe it as part of the architecture. So the rule is per line: any
      // line naming it must also deny it. A blanket ban would have forbidden the
      // correction itself, which is the wrong lesson to encode.
      final denial = RegExp(
        r'\b(no|not|never|does not exist|phantom|nothing)\b',
        caseSensitive: false,
      );
      for (final path in const [
        'docs/ARCHITECTURE.md',
        'docs/DATABASE_SCHEMA.md',
        'CLAUDE.md',
      ]) {
        final offending = [
          for (final line in File(path).readAsLinesSync())
            if ((line.contains('expense_correct_business_date') ||
                    line.contains('revenue_correct_business_date')) &&
                !denial.hasMatch(line))
              line.trim(),
        ];
        expect(
          offending,
          isEmpty,
          reason:
              '$path must describe the contract production implements. There must '
              'be one authoritative contract, not documentation promising one API '
              'while the server exposes another (D-127)',
        );
      }

      // And the denial is actually made somewhere, rather than the name simply having
      // been deleted and the correction left unexplained.
      expect(
        File('docs/ARCHITECTURE.md').readAsStringSync(),
        contains('There is no\n`expense_correct_business_date`'),
        reason:
            'the architecture states which contract exists and which never did — a '
            'silent deletion teaches the next reader nothing',
      );
    });

    test('every mandatory financial reason uses the canonical rule', () {
      // A mandatory financial reason is any operation that can refuse for a missing one.
      // There are five — expense void, revenue void, the two business-date corrections,
      // and the period reopen — and every one of them must decide it the same way:
      // all whitespace stripped, not just spaces.
      //
      // One-argument `btrim`/`trim` strips spaces alone. That let a lone tab void an
      // expense, void a sale, and reopen a closed accounting period, each proven against
      // the real server (D-142, D-145). The rule is now `app.stated_reason`.
      //
      // Written as a **search**, not a list. A list is something somebody has to remember
      // to extend, and the sixth mandatory reason is exactly the one that would arrive
      // without anybody remembering.
      //
      // Only the **latest** definition of each function counts. Migrations are immutable
      // history: 0029's `expense_void` genuinely contained the weak form, and it was
      // correct when it ran.
      final all = _migrations();
      final latest = <String, String>{};
      final pattern = RegExp(
        r'create or replace function\s+(public|app)\.(\w+)[\s\S]*?\$\$;',
      );
      for (final m in all) {
        for (final match in pattern.allMatches(m.sql)) {
          latest['${match.group(1)}.${match.group(2)}'] = match.group(0)!;
        }
      }
      expect(
        latest.length,
        greaterThan(20),
        reason:
            'the function-body extraction found almost nothing — a guard that reads '
            'an empty haystack reports success',
      );

      final mandatory = {
        for (final entry in latest.entries)
          if (entry.value.contains('reason_required')) entry.key: entry.value,
      };
      expect(
        mandatory.keys,
        containsAll(const [
          'public.expense_void',
          'public.revenue_void',
          'public.expense_update',
          'public.revenue_update',
          'public.period_reopen',
        ]),
        reason:
            'the five known mandatory financial reasons must all still be found — if '
            'one has gone missing the search is broken, not the schema',
      );

      // The canonical rule, in either accepted form: the shared helper, or the identical
      // expression inlined. `expense_update` predates the helper by one migration and
      // carries the expression; restating a large financial function for no behavioural
      // change would be the worse trade.
      const canonicalHelper = 'app.stated_reason(';
      final canonicalInline = RegExp(
        r"regexp_replace\(\s*coalesce\(\s*p_\w+,\s*''\s*\),\s*'\^\\s\+\|\\s\+\$'",
      );

      final weak = [
        for (final entry in mandatory.entries)
          if (!entry.value.contains(canonicalHelper) &&
              !canonicalInline.hasMatch(entry.value))
            entry.key,
      ];
      expect(
        weak,
        isEmpty,
        reason:
            'a mandatory financial reason is decided by something other than the '
            'canonical all-whitespace rule. One-argument btrim strips spaces only, and '
            'a reason that says nothing is not a reason (D-142, D-145)',
      );

      // And none of them still reaches for the weak form anywhere in its reason handling.
      for (final entry in mandatory.entries) {
        expect(
          RegExp(r'btrim\(\s*coalesce\(\s*p_reason').hasMatch(entry.value),
          isFalse,
          reason: '${entry.key} still trims spaces only',
        );
      }
    });

    test('the reason backstops carry the canonical expression', () {
      // The CHECK constraints behind those reasons. They are inlined rather than calling
      // the helper — a CHECK that calls a function is not re-validated when the function
      // changes — so they are asserted here instead.
      final everySql = _migrations().map((m) => m.sql).join('\n');
      for (final constraint in const [
        'expenses_void_has_reason',
        'revenue_entries_void_states_why',
        'period_lock_events_reopen_needs_reason',
      ]) {
        final declarations = RegExp(
          'add constraint $constraint[\\s\\S]*?not valid;',
        ).allMatches(everySql).toList();
        expect(
          declarations,
          isNotEmpty,
          reason: '$constraint is never declared with the strict expression',
        );
        expect(
          declarations.last.group(0),
          contains('regexp_replace'),
          reason: '$constraint still trims spaces only',
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
      // Phase 4 landed, so revenue is no longer "a later phase". The guard keeps its
      // teeth by naming what is still ahead: nothing from Phase 5 reporting or the
      // deferred approval workflow may appear before its phase is authorised.
      const phase4 = {
        'revenue_entries',
        'revenue_components',
        'revenue_value_bands',
        'revenue_supply_subtypes',
        'business_unit_tax_statuses',
        // Slice 11. Its own table rather than a discriminator on `expense_attachments`,
        // so the foreign key that makes an orphan impossible stays a foreign key.
        'revenue_attachments',
      };
      const laterPhases = {'approval_requests', 'report_snapshots'};

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
        phase4.difference(created),
        isEmpty,
        reason: 'the Phase 4 revenue schema is incomplete',
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
      // **Four privileges, not three.** Phase 3 revoked insert, update and delete and
      // left TRUNCATE standing on four financial base tables, because Supabase grants
      // ALL to  by template - and TRUNCATE does not consult RLS at all.
      // This guard enumerated the same three words, so it could not see what the
      // revoke had missed. Found by asking the live catalogue instead (D-162).
      final rls = _migrations()
          .firstWhere((m) => m.name.endsWith('_rls.sql'))
          .sql;
      expect(rls, contains('revoke all on public.%I from anon, authenticated'));
      expect(
        RegExp(r'grant (insert|update|delete|truncate)').hasMatch(rls),
        isFalse,
        reason: 'every mutation must travel through a SECURITY DEFINER RPC',
      );
      for (final m in _migrations()) {
        expect(
          RegExp(
            r'grant (insert|update|delete|truncate)[^;]*to (anon|authenticated)',
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
