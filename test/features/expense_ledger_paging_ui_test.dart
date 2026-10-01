/// Phase 8 Slice 4 — the expense ledger's paging, as a person meets it (D-317, D-323).
///
/// The repository tests pin what one statement returns. These pin what the surface does
/// with it: a ledger that says when more exists and fetches it on request, starts again
/// from its first page whenever the question changes, never shows a window computed for
/// somebody or something else, follows the sync worker without losing the reader's
/// place, and — when the device cannot read — says so in words rather than in an
/// exception.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/app/routing/app_router.dart';
import 'package:krishna_mis/core/design/app_theme.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/repositories/expense_repository.dart';
import 'package:krishna_mis/data/sync/outbox_repository.dart';
import 'package:krishna_mis/domain/auth/capability.dart';
import 'package:krishna_mis/domain/masters/master_graph.dart';
import 'package:krishna_mis/domain/sync/sync_state.dart';
import 'package:krishna_mis/domain/value_objects/business_date.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_entry_page.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_filters.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_ledger_page.dart';
import 'package:krishna_mis/features/expenses/presentation/expense_providers.dart';
import 'package:krishna_mis/features/expenses/presentation/widgets/expense_detail_panel.dart';

import '../support/expense_ledger_workload.dart';
import '../support/pnl_fixture.dart' show SwitchableSession, pnlSession;
import '../support/ui_harness.dart';

const _me = 'user-me';

List<CapabilityGrant> _grants({bool viewAll = true}) => [
  CapabilityGrant(
    viewAll ? Capability.expenseViewAll : Capability.expenseViewOwn,
  ),
  const CapabilityGrant(Capability.expenseCreate),
];

/// A repository whose every read fails the way a damaged local database does.
class _BrokenRepository extends ExpenseRepository {
  _BrokenRepository(super.db);

  static final failure = StateError(
    'SqliteException(11): database disk image is malformed, '
    r'C:\Users\someone\AppData\Roaming\krishna_mis.db',
  );

  @override
  Stream<List<LocalExpense>> watchQuery(
    ExpenseQuery filter, {
    int limit = 100,
    int offset = 0,
  }) => Stream.error(failure);

  @override
  Future<LocalExpense?> load(String expenseId) => Future.error(failure);
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late AppDatabase db;
  late SwitchableSession session;
  late LedgerFixtureCounts counts;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    counts = await seedExpenseLedgerFixture(db, documents: 237, years: 1);
    session = SwitchableSession(pnlSession(userId: _me, grants: _grants()));
  });
  tearDown(() => db.close());

  int live() => counts.documents - counts.voided;

  ProviderContainer container({ExpenseRepository? repository}) {
    final c = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sessionProvider.overrideWith(() => session),
        if (repository != null)
          expenseRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// The next window the ledger publishes for the current question.
  Future<ExpenseLedgerWindow> window(ProviderContainer c) async {
    final completer = Completer<ExpenseLedgerWindow>();
    final sub = c.listen(filteredExpensesProvider, (_, next) {
      final shown = expenseLedgerShownTo(
        next.value,
        authorityKey: c.read(expenseLedgerAuthorityKeyProvider),
        filter: c.read(expenseFilterProvider),
      );
      if (shown != null &&
          shown.pages == c.read(expenseLedgerPagesProvider) &&
          !completer.isCompleted) {
        completer.complete(shown);
      }
    }, fireImmediately: true);
    try {
      return await completer.future.timeout(const Duration(seconds: 10));
    } finally {
      sub.close();
    }
  }

  group('more than one page', () {
    test(
      '"Load more" reaches every document, in order, with no repeat',
      () async {
        final c = container();
        var w = await window(c);
        expect(w.rows, hasLength(expenseLedgerPageSize));
        expect(w.hasMore, isTrue);

        while (w.hasMore) {
          c.read(expenseLedgerPagesProvider.notifier).loadMore();
          final before = w.rows.map((e) => e.row.id).toList();
          w = await window(c);
          // What was already on screen stays exactly where it was.
          expect(w.rows.take(before.length).map((e) => e.row.id), before);
        }
        expect(w.rows, hasLength(live()));
        expect(w.rows.map((e) => e.row.id).toSet(), hasLength(live()));
        final whole = await ExpenseRepository(db).list(limit: 1000);
        expect(w.rows.map((e) => e.row.id), [
          for (final e in whole)
            if (e.row.voidedAt == null) e.row.id,
        ]);
        expect(w.hasMore, isFalse, reason: 'the last page says it is the last');
      },
    );
  });

  group('a changed question starts again from the first page', () {
    test('a filter, a search and clearing each reset the pages', () async {
      final c = container();
      final pages = c.read(expenseLedgerPagesProvider.notifier);
      final filter = c.read(expenseFilterProvider.notifier);

      pages
        ..loadMore()
        ..loadMore();
      expect(c.read(expenseLedgerPagesProvider), 3);

      filter.update(const ExpenseFilter(syncState: SyncState.conflict));
      expect(c.read(expenseLedgerPagesProvider), 1);
      final conflicts = await window(c);
      expect(conflicts.rows, isNotEmpty);
      expect(
        conflicts.rows.every((e) => e.syncState == SyncState.conflict),
        isTrue,
      );
      expect(conflicts.rows, hasLength(counts.conflicts));

      pages.loadMore();
      filter.update(const ExpenseFilter(search: 'REF-1'));
      expect(c.read(expenseLedgerPagesProvider), 1);

      pages.loadMore();
      filter.clear();
      expect(c.read(expenseLedgerPagesProvider), 1);
    });

    test(
      'a changed authority resets; an unchanged session refresh does not',
      () async {
        final c = container();
        c.read(expenseLedgerPagesProvider.notifier)
          ..loadMore()
          ..loadMore();

        // The same person, the same grants, a new session state: keep their place.
        session.switchTo(pnlSession(userId: _me, grants: _grants()));
        expect(c.read(expenseLedgerPagesProvider), 3);

        // A changed capability: the ledger answers a different question now.
        session.switchTo(
          pnlSession(userId: _me, grants: _grants(viewAll: false)),
        );
        expect(c.read(expenseLedgerPagesProvider), 1);

        c.read(expenseLedgerPagesProvider.notifier).loadMore();
        session.switchTo(pnlSession(userId: 'someone-else', grants: _grants()));
        expect(c.read(expenseLedgerPagesProvider), 1);
      },
    );
  });

  group('a window is shown only to the question it answers', () {
    test(
      'after a switch of person, the previous window is not shown',
      () async {
        final c = container();
        final owners = await window(c);
        session.switchTo(pnlSession(userId: 'someone-else', grants: _grants()));
        expect(
          expenseLedgerShownTo(
            owners,
            authorityKey: c.read(expenseLedgerAuthorityKeyProvider),
            filter: c.read(expenseFilterProvider),
          ),
          isNull,
        );
        final theirs = await window(c);
        expect(theirs.authorityKey, startsWith('someone-else|'));
      },
    );

    test('after a filter change, the previous window is not shown', () async {
      final c = container();
      final unfiltered = await window(c);
      c
          .read(expenseFilterProvider.notifier)
          .update(const ExpenseFilter(syncState: SyncState.conflict));
      expect(
        expenseLedgerShownTo(
          unfiltered,
          authorityKey: c.read(expenseLedgerAuthorityKeyProvider),
          filter: c.read(expenseFilterProvider),
        ),
        isNull,
      );
    });
  });

  test(
    'a sync change on a later page arrives without losing the reader\'s place',
    () async {
      final c = container();
      final sub = c.listen(filteredExpensesProvider, (_, _) {});
      addTearDown(sub.close);
      c.read(expenseLedgerPagesProvider.notifier).loadMore();
      final before = await window(c);
      expect(before.rows, hasLength(expenseLedgerPageSize * 2));

      // A synced document on page two is now refused as a conflict by the worker.
      final target = before.rows
          .skip(expenseLedgerPageSize)
          .firstWhere((e) => e.syncState == SyncState.synced);
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              mutationId: 'mut-late',
              actorUserId: const Value(_me),
              entityType: 'expense',
              entityId: target.row.id,
              op: 'update',
              payload: '{}',
              nextAttemptAt: DateTime.utc(2027, 4, 2),
              status: OutboxStatus.conflict.name,
              createdAt: DateTime.utc(2027, 4, 2),
            ),
          );
      await (db.update(db.expenses)..where((t) => t.id.equals(target.row.id)))
          .write(const ExpensesCompanion(pendingMutationId: Value('mut-late')));

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      ExpenseLedgerWindow after;
      do {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        after = c.read(filteredExpensesProvider).value!;
      } while (after.rows
                  .firstWhere((e) => e.row.id == target.row.id)
                  .syncState !=
              SyncState.conflict &&
          DateTime.now().isBefore(deadline));

      expect(
        after.rows.firstWhere((e) => e.row.id == target.row.id).syncState,
        SyncState.conflict,
      );
      expect(c.read(expenseLedgerPagesProvider), 2);
      expect(after.rows.map((e) => e.row.id), before.rows.map((e) => e.row.id));
    },
  );

  group('the surface', () {
    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      List<Override> extra = const [],
      Size size = const Size(1366, 900),
      AppDatabase? database,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database ?? db),
            outboxProvider.overrideWithValue(OutboxRepository(database ?? db)),
            sessionProvider.overrideWith(() => session),
            currentBusinessDateProvider.overrideWithValue(
              BusinessDate.of(2027, 3, 31),
            ),
            ...extra,
          ],
          child: MaterialApp(
            theme: AppTheme.desktop,
            home: Scaffold(body: child),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    String shownCount(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const Key('expense-ledger-shown-count')))
        .data!;

    uiTest('the ledger says more exist, and "Load more" fetches them', (
      tester,
    ) async {
      await pump(
        tester,
        const ExpenseLedgerPage(shellKind: AppShellKind.desktop),
      );
      expect(
        shownCount(tester),
        'Showing the newest 50 expenses. More match these filters.',
      );
      var loaded = 50;
      while (find
          .byKey(const Key('expense-ledger-load-more'))
          .evaluate()
          .isNotEmpty) {
        await tester.tap(find.byKey(const Key('expense-ledger-load-more')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        loaded += 50;
        if (loaded < live()) {
          expect(shownCount(tester), startsWith('Showing the newest $loaded'));
        }
      }
      expect(shownCount(tester), 'Showing all ${live()} matching expenses.');
    });

    uiTest(
      'a filter that matches nothing says so, and differs from "none yet"',
      (tester) async {
        final empty = AppDatabase(NativeDatabase.memory());
        addTearDown(empty.close);
        await pump(
          tester,
          const ExpenseLedgerPage(shellKind: AppShellKind.desktop),
          database: empty,
        );
        expect(find.byKey(const Key('expense-ledger-none')), findsOneWidget);
        expect(find.byKey(const Key('expense-ledger-no-match')), findsNothing);
      },
    );

    uiTest('a filter with no match says no expense on this device matches', (
      tester,
    ) async {
      await pump(
        tester,
        const ExpenseLedgerPage(shellKind: AppShellKind.desktop),
        extra: [
          expenseFilterProvider.overrideWith(
            () => _FixedFilter(const ExpenseFilter(search: 'no-such-ref')),
          ),
        ],
      );
      expect(find.byKey(const Key('expense-ledger-no-match')), findsOneWidget);
      expect(find.byKey(const Key('expense-ledger-none')), findsNothing);
    });

    for (final (name, surface) in [
      (
        'the ledger',
        const ExpenseLedgerPage(shellKind: AppShellKind.desktop) as Widget,
      ),
      ('an expense', const ExpenseDetailPanel(expenseId: 'exp-0000001')),
    ]) {
      uiTest('$name that cannot be read says so in words, with a retry', (
        tester,
      ) async {
        await pump(
          tester,
          surface,
          extra: [
            expenseRepositoryProvider.overrideWithValue(_BrokenRepository(db)),
          ],
        );
        expect(find.byKey(const Key('expense-read-retry')), findsOneWidget);
        expect(find.textContaining('could not be read'), findsWidgets);
        _expectNoRawError(tester);
      });
    }

    uiTest('the entry form whose set-up cannot be read says so in words', (
      tester,
    ) async {
      await pump(
        tester,
        const ExpenseEntryPage(),
        size: const Size(430, 932),
        extra: [
          masterGraphProvider.overrideWith(
            (ref) => Future<MasterGraph>.error(_BrokenRepository.failure),
          ),
        ],
      );
      expect(find.text('The set-up could not be read'), findsOneWidget);
      expect(find.textContaining('Nothing has been saved.'), findsOneWidget);
      expect(find.byKey(const Key('expense-read-retry')), findsOneWidget);
      _expectNoRawError(tester);
    });
  });
}

/// No exception text, provider name, SQLite message or local path reaches the screen.
void _expectNoRawError(WidgetTester tester) {
  final text = [
    for (final t in tester.widgetList<Text>(find.byType(Text)))
      t.data ?? t.textSpan?.toPlainText() ?? '',
  ].join('\n');
  for (final forbidden in [
    'SqliteException',
    'StateError',
    'Bad state',
    'malformed',
    'Provider',
    r'C:\',
    'AppData',
    '#0',
  ]) {
    expect(text, isNot(contains(forbidden)), reason: forbidden);
  }
}

class _FixedFilter extends ExpenseFilterNotifier {
  _FixedFilter(this._initial);
  final ExpenseFilter _initial;

  @override
  ExpenseFilter build() => _initial;
}
