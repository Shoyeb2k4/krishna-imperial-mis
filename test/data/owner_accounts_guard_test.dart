/// Structural guards for the Owner Accounts foundation.
///
/// Phase 5 OA-1. Each of these is a property that has to hold for files nobody has written
/// yet, which is why it is a scan over the tree rather than a review of what exists today.
///
/// The one that would be easiest to lose is the capability namespace: a later tidy-up that
/// renamed `owner_ledger.view` to `owner.ledger.view` would break a deploy for a reason
/// that reads like a security finding, and the connection between the two is three
/// migrations away from the file being edited.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/domain/auth/capability.dart';

String _read(String path) => File(path).readAsStringSync();

/// The migration whose filename ends `_<ledgerName>.sql`.
///
/// Matching by name rather than by version is the convention `LEDGER.md` states and the
/// migration audit already uses: the version is whatever the server assigned at apply
/// time, and a filename written before that is a prediction.
String _migrationNamed(String ledgerName) {
  final matches = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('_$ledgerName.sql'))
      .toList();
  // `throw` rather than `expect`: this runs while the group body is being built, and
  // `expect` outside a running test raises `OutsideTestException` — which surfaces as a
  // file that fails to load rather than as the assertion it was meant to be.
  if (matches.length != 1) {
    throw StateError(
      'expected exactly one committed migration named "$ledgerName", '
      'found ${matches.length}',
    );
  }
  return matches.single.readAsStringSync();
}

List<File> _dartFiles(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Source with `///` and `//` comments removed.
///
/// Not tidiness. Counting a name wherever it appears would let the *paragraph explaining
/// that nothing does this* count as the thing doing it — which is the failure the D-139
/// capability guard committed on its own first run.
String _code(String source) => source.replaceAll(RegExp(r'//[^\n]*'), '');

/// SQL with `--` comment lines removed, for the same reason [_code] exists.
String _sqlCode(String source) =>
    source.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  group('the capability namespace is safe against the role-name guard (OA-D11)', () {
    test('no capability literal begins with a bare `owner.`', () {
      // Three shipped reporting migrations refuse any boundary body matching
      // `\mowner\M` as a role-name branch. Postgres word characters include the
      // underscore, so `owner_ledger` does not match — and `owner.ledger.view` does,
      // because the bare word ends at the dot.
      //
      // Asserted over the enum rather than over one file, so a capability added later
      // cannot reintroduce the collision.
      for (final capability in Capability.values) {
        expect(
          capability.code.startsWith('owner.'),
          isFalse,
          reason:
              '${capability.code} would be read as a role-name branch by the '
              'reporting boundary guards and would fail the deploy (OA-D11)',
        );
      }
    });

    test('the owner-account capabilities use the two agreed namespaces', () {
      final ownerCapabilities = Capability.values
          .where((c) => c.code.contains('owner'))
          .map((c) => c.code)
          .toList();

      expect(ownerCapabilities, isNotEmpty);
      for (final code in ownerCapabilities) {
        expect(
          code.startsWith('owner_ledger.') || code.startsWith('owner_masters.'),
          isTrue,
          reason:
              '$code is outside the reviewed namespaces; a third one is a decision, '
              'not a naming choice',
        );
      }
    });

    test(
      'the migrations agree, and none of them writes a dotted owner capability',
      () {
        final migrations = Directory(
          'supabase/migrations',
        ).listSync().whereType<File>().where((f) => f.path.endsWith('.sql'));

        for (final migration in migrations) {
          expect(
            RegExp(r"'owner\.[a-z_.]+'").hasMatch(migration.readAsStringSync()),
            isFalse,
            reason:
                '${migration.path} writes a capability literal beginning "owner."',
          );
        }
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the owner-accounts domain is pure (§37)', () {
    final files = _dartFiles('lib/domain/owner_accounts');

    test('there are files to check in the first place', () {
      // A guard reading an empty haystack reports success (D-103).
      expect(files, isNotEmpty);
      expect(files.length, greaterThanOrEqualTo(3));
    });

    test('nothing imports storage, network, or the framework', () {
      for (final file in files) {
        final source = _code(file.readAsStringSync());
        for (final forbidden in [
          'package:drift',
          'package:supabase',
          'package:flutter/',
          'package:riverpod',
          'package:flutter_riverpod',
          'dart:io',
          'krishna_mis/data/',
          'krishna_mis/features/',
          'krishna_mis/app/',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason: '${file.path} reaches outside the domain for $forbidden',
          );
        }
      }
    });

    test('no binary floating point touches a share or an amount', () {
      // The expressions are lifted verbatim from `finance_purity_test.dart` rather than
      // rewritten. A second, subtly different version of one rule is the situation this
      // project keeps recording — and the first attempt here proved it: a naive `/`
      // pattern matched the slashes inside `package:krishna_mis/domain/...` and reported
      // the domain impure for its own imports.
      for (final file in files) {
        final code = file
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');

        // Strings blanked. An import path is not a division and a spec reference is not
        // a floating-point literal — `'(spec §14.1)'` in a refusal message failed the
        // first version of this check, which is a guard finding its own false positive
        // rather than a defect.
        final arithmetic = code.replaceAll(RegExp(r"'[^']*'"), "''");

        expect(
          RegExp(r'\bdouble\b').hasMatch(code),
          isFalse,
          reason: '${file.path} names `double`',
        );
        expect(
          RegExp(r'\btoDouble\s*\(').hasMatch(code),
          isFalse,
          reason: '${file.path} converts to floating point',
        );
        expect(
          RegExp(r'(?<![\w.])\d+\.\d+(?![\w.])').hasMatch(arithmetic),
          isFalse,
          reason: '${file.path} contains a floating-point literal',
        );
        expect(
          // `/` on ints yields a double in Dart, which is exactly the accident this
          // forbids. Integer division is `~/`.
          RegExp(r'(?<![/~])/(?![/*])').hasMatch(arithmetic),
          isFalse,
          reason: '${file.path} uses `/`; integer division is `~/`',
        );
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('OA-1 stops where OA-3 begins (§37, §42)', () {
    test('nothing in the owner layer computes a balance or an entitlement', () {
      // Owner Settlement needs a PnlResult and the shares together, and that calculator is
      // OA-3's. A repository or a domain file that quietly produced a closing balance
      // would be the second definition of one — which is what OA-D2 exists to prevent.
      final files = [
        ..._dartFiles('lib/domain/owner_accounts'),
        File('lib/data/repositories/owner_ledger_repository.dart'),
        File('lib/data/remote/owner_ledger_gateway.dart'),
        File('lib/data/sync/owner_ledger_mutation_endpoint.dart'),
      ];

      for (final file in files) {
        final source = _code(file.readAsStringSync());
        for (final forbidden in [
          'closingBalance',
          'openingBalanceFor',
          'entitlement',
          'operatingProfit',
          'OwnerSettlement',
          'PnlResult',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason:
                '${file.path} names $forbidden — settlement arithmetic is OA-3, and '
                'a second place that computes it is a second answer',
          );
        }
      }
    });

    test('the owner write path names no expense or revenue table', () {
      // §40 and §41 asserted structurally as well as behaviourally: the behavioural test
      // compares the figures, and this makes the mistake unavailable rather than merely
      // measured.
      final source = _code(
        _read('lib/data/repositories/owner_ledger_repository.dart'),
      );
      for (final forbidden in [
        'expenses',
        'expenseAllocations',
        'expensePeriodAllocations',
        'revenueEntries',
        'revenueComponents',
        'reportingRevenueContributions',
        'reportingExpenseContributions',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason:
              'the Owner Ledger touches $forbidden — an owner movement is neither an '
              'expense nor revenue (§4, §7 of the addendum)',
        );
      }
    });

    test('the repository reads the outbox for sync state and does not copy it', () {
      // D-131: the revenue detail panel and the ledger derived one fact two ways, and the
      // panel reported `Synced` for a sale in conflict. One derivation, from the outbox,
      // joined on the document id.
      final source = _read(
        'lib/data/repositories/owner_ledger_repository.dart',
      );
      expect(source, contains('watchSyncState'));
      expect(
        source,
        contains('o.entity_id = ?1'),
        reason: 'joined on the document id, which is what the ledger uses',
      );
      expect(
        _code(source),
        isNot(contains('syncStateColumn')),
        reason: 'sync state is derived, never a column that could disagree',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('no owner-account concept has leaked into the P&L (§41)', () {
    test('the finance domain names no owner concept', () {
      // The permanent invariant. Owner Settlement consumes a `PnlResult`; the calculator
      // does not know owners exist, and adding a third side to it would destroy the
      // exhaustive switch that is the whole of D-163's enforcement.
      for (final file in _dartFiles('lib/domain/finance')) {
        final source = _code(file.readAsStringSync());
        for (final forbidden in [
          'owner_ledger',
          'ownerLedger',
          'OwnerMovement',
          'OwnershipShare',
          'ncConsumption',
          'withdrawal',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason:
                '${file.path} names $forbidden — the P&L must be unchanged by the '
                'existence of owner accounts (§41)',
          );
        }
      }
    });

    test('the reporting engines are untouched by this slice', () {
      for (final file in _dartFiles('lib/data/reporting')) {
        final source = _code(file.readAsStringSync());
        expect(source, isNot(contains('owner_ledger')));
        expect(source, isNot(contains('OwnerLedger')));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('the Expense guard is a control rather than a comment (§25)', () {
    // Found by **ledger name**, never by version. Supabase assigns the version when the
    // migration is applied, so a filename written before that is a guess — and D-102
    // records exactly this going wrong once already, where a parity file was named for
    // the version its author intended rather than the one the server gave it. Hard-coding
    // it here made this whole file fail to load the moment the migrations were renamed to
    // their real versions.
    final guard = _migrationNamed('expense_categories_refuse_owner_drawings');

    test('the trigger is created and attached to expense_categories', () {
      expect(
        guard,
        contains('create trigger trg_expense_category_not_owner_drawings'),
      );
      expect(
        guard,
        contains('before insert or update on public.expense_categories'),
      );
    });

    test('it is proven to refuse, and proven not to refuse everything', () {
      // A guard that refused every category would satisfy its own negative test perfectly
      // and would have broken master administration entirely.
      expect(guard, contains('OA1_PROBE_REFUSED'));
      expect(guard, contains('OA1_PROBE_ALLOWED'));
      expect(
        guard,
        contains('A rule that cannot fail is not a control'),
        reason:
            'the probe asserts the refusal rather than merely attempting it',
      );
    });

    test('no fifth expense `nature` value was invented', () {
      // Adding `owner_drawings` to the CHECK would create a fifth instance of the family
      // D-068, D-071, D-077, D-103 and D-116 record unless something evaluated it — and
      // if something did, the expense engine would have acquired a concept of owner
      // movements, which is what OA-1 says it must not.
      final migrations = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .map((f) => f.readAsStringSync())
          .join('\n');

      expect(
        RegExp(r"nature in \([^)]*owner").hasMatch(migrations),
        isFalse,
        reason:
            'owner movements belong to the Owner Ledger, not to a category label',
      );
      expect(
        migrations,
        contains(
          "check (nature in ('operating', 'payroll', 'utility', 'other'))",
        ),
        reason: 'the four values are unchanged',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('an ownership timeline moves forward only (§37)', () {
    // Found by the live suite's **second** run, which is the only run that could have
    // found it: `owner_share_set` closed a share that started earlier and left a
    // backdated or duplicate date to `ownership_shares_no_overlap`, so a caller met
    // `23P01`, a table name, a constraint name and a raw daterange. Spec §13.1 has
    // forbidden that in a refusal since Phase 2.
    final corrective = _migrationNamed('owner_share_set_refuses_backdating');
    final body = _sqlCode(corrective);

    test('the rule is in the function body, not only in the prose above it', () {
      // Comments are stripped first. The paragraph explaining the rule is not the rule —
      // which is the failure the D-139 capability guard committed on its own first run.
      // The **refusal site**, not the name appearing anywhere. The migration's own
      // deploy-time assertion contains the literal too, and the first version of this
      // test passed against a body whose refusal had been renamed — which is D-139's
      // failure for the third time in this project's machinery.
      expect(
        body,
        contains("app.refuse('KM031', 'ownership_change_backdated'"),
      );
      expect(
        body,
        contains('max(effective_from)'),
        reason:
            'the refusal is decided from the timeline the owner already has, not from '
            'a flag the caller supplies',
      );
      expect(
        body,
        contains('p_effective_from <= v_latest'),
        reason:
            'at or before, so a duplicate date is refused as well as an earlier one',
      );
    });

    test('the mid-period rule survives the replacement (D-174)', () {
      // A `create or replace` is where a predicate gets lost, and this one restates a
      // function that already carried a refusal of its own.
      expect(body, contains('ownership_change_mid_period'));
    });

    test('the sentence carries no constraint name, table name or SQLSTATE', () {
      final message = RegExp(
        "'ownership_change_backdated',\\s*'([^']*)'",
      ).firstMatch(body)?.group(1);
      expect(message, isNotNull, reason: 'the refusal states a sentence');
      expect(message, isNot(contains('ownership_shares')));
      expect(message, isNot(contains('constraint')));
      expect(message, isNot(contains('23P01')));
      expect(
        message!.toLowerCase(),
        contains('later month'),
        reason: 'the sentence ends in an action rather than in a complaint',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('no Petpooja integration was added (§27)', () {
    test('the repository still contains no POS integration', () {
      final sources = [
        ..._dartFiles('lib'),
        ...Directory(
          'supabase/migrations',
        ).listSync().whereType<File>().where((f) => f.path.endsWith('.sql')),
      ];
      for (final file in sources) {
        // Comments are stripped, and that is the point rather than an exemption: OA-1's
        // own migration says in as many words that Petpooja's NC behaviour is an
        // operational question nobody has answered. What must not exist is code that
        // integrates with one — a comment recording the open question is the opposite of
        // a claim that one was built.
        final code = _code(
          file.readAsStringSync(),
        ).replaceAll(RegExp(r'^--[^\n]*', multiLine: true), '').toLowerCase();
        expect(
          code,
          isNot(contains('petpooja')),
          reason:
              '${file.path} — OA-1 claims no automatic POS reconciliation, and '
              "Petpooja's actual NC behaviour is an operational question",
        );
      }
    });
  });
}
