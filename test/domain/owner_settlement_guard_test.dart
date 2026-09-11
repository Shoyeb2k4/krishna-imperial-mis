/// Structural guards for the Owner Settlement domain.
///
/// Phase 5 OA-2 §32, §33, §26, §45. Each is a property that has to hold for files nobody
/// has written yet, which is why it is a scan over the directory rather than a review of
/// what exists today.
///
/// The one that matters most is §33. `Net Sales − Expenses` lives once, in
/// `domain/finance` (D-020), and a settlement that recomputed it would be a second P&L
/// that agrees with the first only until somebody edits one — which is the failure this
/// project has recorded under a different name every phase.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _settlementDir = 'lib/domain/owner_accounts/settlement';

List<File> _files(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Source with `///` and `//` comments removed.
///
/// Not tidiness: counting a name wherever it appears would let the paragraph explaining
/// that nothing does this count as the thing doing it — the failure the D-139 capability
/// guard committed on its own first run, and which this project has now repeated three
/// times in its own machinery.
String _code(String source) => source.replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  test('there are files to check in the first place', () {
    // A guard over an empty directory passes perfectly and proves nothing.
    expect(_files(_settlementDir), isNotEmpty);
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§32 · the settlement domain is pure', () {
    test('it imports no storage, no transport and no framework', () {
      for (final file in _files(_settlementDir)) {
        final source = file.readAsStringSync();
        for (final forbidden in [
          'package:drift',
          'package:supabase',
          'package:flutter/',
          'package:flutter_riverpod',
          'package:riverpod',
          'dart:io',
          'dart:ui',
          "import 'package:krishna_mis/data/",
          "import 'package:krishna_mis/features/",
          "import 'package:krishna_mis/app/",
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason: '${file.path} imports $forbidden',
          );
        }
      }
    });

    test('no binary floating point touches a settlement figure', () {
      // Reusing the expressions the finance purity guard already uses, verbatim, rather
      // than writing a second nearly-identical set that could drift from it.
      for (final file in _files(_settlementDir)) {
        final source = _code(file.readAsStringSync());
        // Blank out single-quoted strings so a section reference like §14.1 inside a
        // message is not read as a floating-point literal.
        final scanned = source.replaceAll(RegExp(r"'[^']*'"), "''");

        expect(
          RegExp(r'\bdouble\b').hasMatch(scanned),
          isFalse,
          reason: '${file.path} names double',
        );
        expect(
          RegExp(r'\btoDouble\b').hasMatch(scanned),
          isFalse,
          reason: '${file.path} calls toDouble',
        );
        expect(
          RegExp(r'\b\d+\.\d+\b').hasMatch(scanned),
          isFalse,
          reason: '${file.path} contains a floating-point literal',
        );
        expect(
          RegExp(r'[^/~]/[^/*]').hasMatch(scanned),
          isFalse,
          reason:
              '${file.path} uses `/`, which returns a double in Dart even between two '
              'integers. Integer division is `~/`',
        );
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§33 · the P&L formula is consumed, never recreated', () {
    test('nothing here subtracts expenses from net sales', () {
      for (final file in _files(_settlementDir)) {
        final source = _code(file.readAsStringSync());
        for (final forbidden in [
          'netSales',
          'grossSales',
          'totalExpenses',
          'expenseTotal',
          'RevenueTotals',
          'ExpenseTotals',
          'TaxRule',
          'taxAmount',
          'Pnl.compute',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason:
                '${file.path} names $forbidden. Operating Profit is computed once, in '
                'domain/finance, and consumed here (§33, D-020)',
          );
        }
      }
    });

    test('and it takes Operating Profit as an input it cannot derive', () {
      // The complement, which is the half a "contains nothing" guard cannot express: a
      // file that computed nothing *and consumed nothing* would satisfy the check above
      // perfectly while doing no work at all.
      final settlement = File(
        '$_settlementDir/owner_settlement.dart',
      ).readAsStringSync();
      expect(settlement, contains('CanonicalOperatingProfit'));
      expect(settlement, contains('cumulativeBeforePeriod'));
      expect(settlement, contains('cumulativeAtPeriodEnd'));
    });

    test(
      'the entitlement split consumes a cumulative figure, not a period one',
      () {
        // §38: halving one period's profit strands a paisa every odd month. The named
        // constructor takes a *cumulative* figure, and the period entitlement is a
        // difference of two of them.
        final entitlement = File(
          '$_settlementDir/owner_entitlement.dart',
        ).readAsStringSync();
        expect(entitlement, contains('CumulativeEntitlement.of('));
        expect(entitlement, contains('class PeriodEntitlement'));
        expect(
          _code(entitlement),
          contains('cumulativeAtEnd.perOwner - cumulativeBefore.perOwner'),
          reason: 'the period figure is a difference, and is written as one',
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§26, §3 · nothing is stored, and no balance exists to drift', () {
    test('the settlement domain holds nothing between calls', () {
      // The property that matters is **no state that survives a call** — a cached
      // position or a running balance. A local accumulator inside a fold is not that,
      // and the first version of this guard forbade one: a rule about style wearing the
      // costume of a rule about money.
      for (final file in _files(_settlementDir)) {
        final source = _code(file.readAsStringSync());

        expect(
          // A static **field**, not a static method: `static compute(...)` holds
          // nothing, and forbidding it would forbid the calculator itself. The
          // difference is the parenthesis, so the pattern refuses to cross one.
          RegExp(
            r'^\s*static\s+(?!const\b)[^(\n]*(=|;)',
            multiLine: true,
          ).hasMatch(source),
          isFalse,
          reason:
              '${file.path} declares static state; only `static const` is state-free',
        );
        expect(
          RegExp(r'^(var|late)\s', multiLine: true).hasMatch(source),
          isFalse,
          reason: '${file.path} declares a mutable top-level variable',
        );
        expect(
          RegExp(r'^\s*late\s', multiLine: true).hasMatch(source),
          isFalse,
          reason: '${file.path} declares a late field',
        );
        expect(
          source,
          isNot(contains('storedBalance')),
          reason: 'the position is derived (OA-D2, D-190)',
        );
      }
    });

    test('no local table or migration introduces an owner balance column', () {
      // The rule OA-D2 states, checked where it could actually be broken.
      final schema = File(
        'lib/data/local/owner_tables.dart',
      ).readAsStringSync();
      for (final forbidden in [
        'closingBalance',
        'openingBalance',
        'currentBalance',
        'ownerPosition',
        'settlementBalance',
      ]) {
        expect(
          schema,
          isNot(contains(forbidden)),
          reason:
              'a stored balance is a second copy of a figure the movements already '
              'determine, and a correction or a void can leave it wrong (§3, OA-D2)',
        );
      }

      final migrations = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      expect(
        RegExp(
          r'\bowner\w*_balance\b|\bsettlement_balance\b',
        ).hasMatch(migrations),
        isFalse,
        reason: 'and no server column either',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //
  // OA-2 asserted here that **no** settlement surface existed, because presentation was
  // OA-3's. OA-3 built it, so that assertion moved by instruction — and the boundary it
  // protected moved with it rather than being deleted: the surface is a *preview* and a
  // *formatter*, and these say so in a form the build evaluates.
  group('§45 → OA-3 · the surface is a preview, and it only formats', () {
    List<File> surface() => Directory('lib/features/owner_settlement')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    /// Code with comments **and string literals** removed: the screen says "not a
    /// finalized statement" in words, and a sentence is not a finalize action.
    String identifiers(String source) => _code(source)
        .replaceAll(RegExp(r"'(?:[^'\\\n]|\\.)*'"), "''")
        .replaceAll(RegExp(r'"(?:[^"\\\n]|\\.)*"'), '""');

    test('there is a surface to check', () {
      expect(surface().length, greaterThanOrEqualTo(2));
    });

    test('no finalize, reopen, lock, approval or versioning exists (Q3)', () {
      for (final file in surface()) {
        final code = identifiers(file.readAsStringSync());
        for (final forbidden in [
          RegExp(r'finali[sz]', caseSensitive: false),
          RegExp('reopen', caseSensitive: false),
          RegExp(r'approv', caseSensitive: false),
          RegExp(r'lockStatement|statementLock|isLocked', caseSensitive: false),
          RegExp(r'version', caseSensitive: false),
        ]) {
          expect(
            forbidden.hasMatch(code),
            isFalse,
            reason:
                '${file.path} names ${forbidden.pattern}. OA-3 is preview only; the '
                'Finalized Statement slice defines finalize and reopen, not this one',
          );
        }
      }
    });

    test('no widget recomputes a settlement figure', () {
      for (final file in surface()) {
        final code = identifiers(file.readAsStringSync());
        for (final forbidden in [
          '.paise',
          'Money.fromPaise',
          'Money.sum',
          'Money.zero',
          'OwnerSettlement.compute',
          'CumulativeEntitlement',
          'PeriodEntitlement',
          'Pnl.compute',
          'Pnl.consolidate',
          'resolveV1For',
          'resolveFor',
          'shareBasisPoints',
          'netMovements',
          '~/',
          'OwnerSettlementRepository(',
          'OwnerLedgerRepository',
          'ReportingEngine(',
        ]) {
          expect(
            code,
            isNot(contains(forbidden)),
            reason:
                '${file.path} names $forbidden. The surface consumes the OA-2 result; '
                'Operating Profit, ownership, entitlement and every position are '
                'computed once, elsewhere, and never in a widget (OA-3)',
          );
        }
      }
    });

    test('and it does read the result it is meant to show', () {
      // The complement: a page that computed nothing *and showed nothing* would satisfy
      // the scan above while doing no work at all.
      final page = File(
        'lib/features/owner_settlement/presentation/owner_settlement_page.dart',
      ).readAsStringSync();
      for (final field in [
        'openingPosition',
        'profitEntitlement',
        'withdrawals',
        'ncConsumption',
        'settlementPaid',
        'adjustmentCredits',
        'adjustmentDebits',
        'closingPosition',
        'operatingProfitByBusinessUnit',
        'undistributedRemainder',
      ]) {
        expect(page, contains(field));
      }
    });

    test('the surface never reads the OA-1 owner masters (D-208)', () {
      for (final file in [
        ...surface(),
        File('lib/data/repositories/owner_settlement_preview.dart'),
        File('lib/data/repositories/owner_settlement_repository.dart'),
      ]) {
        final code = identifiers(file.readAsStringSync());
        for (final forbidden in [
          RegExp(r'\.owners\b'),
          RegExp(r'\.ownershipShares\b'),
          RegExp(r'\.ownerFamilyMembers\b'),
        ]) {
          expect(
            forbidden.hasMatch(code),
            isFalse,
            reason:
                '${file.path} reads an organisation-global owner master, which '
                'survives a user switch. The settlement reads the owner-keyed '
                'canonical cache only',
          );
        }
      }
    });

    test('and the settlement domain produces no display string', () {
      for (final file in _files(_settlementDir)) {
        final source = _code(file.readAsStringSync());
        for (final forbidden in [
          'formatted',
          'MoneyFormatter',
          'toDisplay',
          'label',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason:
                '${file.path} names $forbidden — §24 forbids display strings here',
          );
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  group('§19, §45 · the sync exists, and nothing runs it automatically', () {
    test(
      'the real gateway satisfies the interface the synchroniser depends on',
      () {
        // The D-077 shape, checked at the type level: `OwnerLedgerGateway` — the class
        // production builds — implements `OwnerSnapshotSource`, so the synchroniser cannot
        // be wired to something that only looks like it.
        final gateway = File(
          'lib/data/remote/owner_ledger_gateway.dart',
        ).readAsStringSync();
        expect(gateway, contains('implements OwnerSnapshotSource'));
        expect(gateway, contains("rpc<dynamic>('owner_ledger_snapshot')"));
      },
    );

    test('no automatic trigger pulls owner data, and that is deliberate', () {
      // **Not an oversight.** `ReferenceSync` runs for every signed-in person, and a
      // principal with no owner capability legitimately reads zero owner rows — so
      // triggering the pull there would write a coverage row certifying *complete*
      // canonical owner history to somebody entitled to see none of it. A claim that
      // means "complete for a reader who may read nothing" is worse than no claim.
      //
      // The trigger therefore belongs with the surface that holds the capability, which
      // is OA-3's. OA-2 ships the mechanism and states the gap rather than inventing a
      // caller for it.
      final syncEngine = File(
        'lib/data/sync/reference_sync.dart',
      ).readAsStringSync();
      expect(
        syncEngine,
        isNot(contains('OwnerSettlementSync')),
        reason:
            'if this ever changes, the coverage row must first learn to say whether the '
            'reader was entitled to the rows it certifies',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  test('§31 · the reference oracle is independent and does not ship', () {
    // Comments stripped first. The oracle's own header says it calls none of these, and
    // the first version of this guard read that sentence as the violation — D-139's
    // failure, in a guard written while quoting D-139.
    final oracle = _code(
      File('test/support/owner_settlement_reference.dart').readAsStringSync(),
    );

    for (final forbidden in [
      'OwnerSettlement.compute',
      'CumulativeEntitlement',
      'OwnerLedgerTotals',
      'package:krishna_mis/domain/owner_accounts',
      'package:krishna_mis/domain/value_objects/money.dart',
    ]) {
      expect(
        oracle,
        isNot(contains(forbidden)),
        reason:
            'an oracle that calls the production code proves a function equals itself',
      );
    }

    final production = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    expect(
      production,
      isNot(contains('owner_settlement_reference')),
      reason: 'and it must not ship',
    );
  });
}
