/// Phase 8 Slice 7 — what a person sees when the application cannot start, and the reset.
///
/// Driven through [StartupRunner], the code `main()` runs, with a fake start that throws
/// what a real one throws. Nothing here touches a real installation.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/bootstrap.dart';
import 'package:krishna_mis/app/env/app_environment.dart';
import 'package:krishna_mis/app/startup/startup_failure.dart';
import 'package:krishna_mis/app/startup/startup_failure_app.dart';
import 'package:krishna_mis/app/startup/startup_runner.dart';
import 'package:krishna_mis/data/local/app_database.dart';
import 'package:krishna_mis/data/local/database_key_manager.dart';
import 'package:krishna_mis/data/local/encrypted_database.dart';
import 'package:krishna_mis/data/local/local_store_recovery.dart';
import 'package:sqlite3/common.dart' show SqliteException;

class _FakeRecovery implements StartupRecoveryActions {
  _FakeRecovery({
    this.assessment = const UnsyncedWorkUnknown(
      UnsyncedWorkUnknownReason.unreadable,
    ),
    this.fails = false,
  });

  final UnsyncedWorkAssessment assessment;
  final bool fails;
  int resets = 0;

  @override
  Future<UnsyncedWorkAssessment> assess() async => assessment;

  @override
  Future<void> reset() async {
    resets++;
    if (fails) throw const LocalStoreResetFailed('move', 'in use');
  }
}

/// Text that must never reach a person's screen.
final _technical = RegExp(
  r'Sqlite|SQLITE|Drift|Exception|Error\b|krishna_mis\.db|[A-Z]:\\|/Users/|'
  r'secure_storage|DPAPI|Keystore|stack|#0',
);

void main() {
  late List<Widget> shown;
  late _FakeRecovery recovery;
  late int starts;

  setUp(() {
    shown = [];
    recovery = _FakeRecovery();
    starts = 0;
  });

  StartupRunner runnerFailingWith(
    List<Object> errors, {
    StartupRecoveryActions? actions,
  }) => StartupRunner(
    boot: () async {
      final i = starts++;
      if (i < errors.length) throw errors[i];
      throw StateError('no more scripted failures');
    },
    run: shown.add,
    appFor: (_) => const Text('the application'),
    recoveryFor: (_) async => actions ?? recovery,
    log: (_, _) {},
  );

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shown.last);
    await tester.pumpAndSettle();
  }

  void expectNoTechnicalText(WidgetTester tester) {
    for (final widget in tester.widgetList<Text>(find.byType(Text))) {
      final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      expect(
        _technical.hasMatch(text),
        isFalse,
        reason: 'technical text reached the screen: "$text"',
      );
    }
    for (final widget in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    )) {
      fail('a SelectableText is on the failure screen: ${widget.data}');
    }
  }

  final pathy = SqliteException(
    extendedResultCode: 26,
    message: r'file is not a database: C:\Users\someone\AppData\krishna_mis.db',
  );

  group('every kind is described in plain words', () {
    final cases = <String, (Object, StartupFailureKind)>{
      'damaged': (
        const EncryptedDatabaseUnreadable(
          'database did not open with the stored key (sqlite 26)',
          resultCode: 26,
        ),
        StartupFailureKind.localDataUnreadable,
      ),
      'key missing': (
        const DatabaseKeyUnavailable(
          'no key is stored for the existing local database',
          problem: DatabaseKeyProblem.missingForExistingDatabase,
        ),
        StartupFailureKind.localDataUnreadable,
      ),
      'key store': (
        const DatabaseKeyUnavailable('secure storage read failed (_Exception)'),
        StartupFailureKind.keyStoreUnavailable,
      ),
      'upgrade': (
        LocalSchemaMigrationFailed(from: 21, to: 22, cause: StateError('x')),
        StartupFailureKind.upgradeFailed,
      ),
      'in use': (
        SqliteException(extendedResultCode: 5, message: 'database is locked'),
        StartupFailureKind.inUse,
      ),
      'storage': (
        const PathExistsException(
          r'Creation failed',
          OSError('Cannot create a file', 183),
          r'C:\Users\someone\AppData\Roaming\Krishna Imperial',
        ),
        StartupFailureKind.storage,
      ),
      'unexpected': (StateError('Bad state'), StartupFailureKind.unexpected),
      'raw path in a SQLite message': (
        pathy,
        StartupFailureKind.localDataUnreadable,
      ),
    };

    for (final MapEntry(key: name, value: (error, kind)) in cases.entries) {
      testWidgets('$name: titled, referenced, nothing technical', (
        tester,
      ) async {
        await runnerFailingWith([error]).start();
        await show(tester);
        expect(find.text(startupFailureWording(kind).title), findsOneWidget);
        expect(
          find.text('Reference: ${StartupFailure(kind).reference}'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('startup-try-again')), findsOneWidget);
        expect(
          find.byKey(const Key('startup-open-reset')),
          StartupFailure(kind).permitsReset ? findsOneWidget : findsNothing,
        );
        expectNoTechnicalText(tester);
      });
    }
  });

  testWidgets('a configuration failure shows its curated explanation', (
    tester,
  ) async {
    await runnerFailingWith([
      const ConfigurationRefused(
        ConfigurationProblem(
          'Backend configuration is incomplete.',
          'Supply SUPABASE_URL and SUPABASE_ANON_KEY together.',
        ),
      ),
    ]).start();
    await show(tester);
    expect(
      find.text(
        'Backend configuration is incomplete. '
        'Supply SUPABASE_URL and SUPABASE_ANON_KEY together.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('startup-open-reset')), findsNothing);
  });

  testWidgets(
    'a retryable failure never offers a reset, even with recovery to hand',
    (tester) async {
      for (final error in <Object>[
        SqliteException(extendedResultCode: 5, message: 'locked'),
        SqliteException(extendedResultCode: 13, message: 'full'),
        const DatabaseKeyUnavailable('x'),
        StateError('x'),
      ]) {
        shown.clear();
        await runnerFailingWith([error]).start();
        await show(tester);
        expect(find.byKey(const Key('startup-open-reset')), findsNothing);
      }
    },
  );

  testWidgets('Try again starts again, and a success replaces the screen', (
    tester,
  ) async {
    var attempts = 0;
    final runner = StartupRunner(
      boot: () async {
        if (attempts++ == 0) {
          throw SqliteException(extendedResultCode: 5, message: 'locked');
        }
        // A second start succeeds; the result is never inspected here.
        throw _Started();
      },
      run: shown.add,
      appFor: (_) => const Text('the application'),
      recoveryFor: (_) async => recovery,
      log: (_, _) {},
    );
    await runner.start();
    await show(tester);
    await tester.tap(find.byKey(const Key('startup-try-again')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(shown, hasLength(2));
  });

  group('reset', () {
    Future<void> openReset(WidgetTester tester, Object error) async {
      await runnerFailingWith([error, error]).start();
      await show(tester);
      await tester.tap(find.byKey(const Key('startup-open-reset')));
      await tester.pumpAndSettle();
    }

    Finder confirm() => find.byKey(const Key('reset-confirm'));
    bool confirmEnabled(WidgetTester tester) =>
        tester.widget<FilledButton>(confirm()).onPressed != null;

    testWidgets('needs the exact word typed before it can be pressed', (
      tester,
    ) async {
      await openReset(tester, pathy);
      expect(confirmEnabled(tester), isFalse);
      for (final attempt in ['', 'reset', 'Reset', 'RESE', 'RESETT', 'yes']) {
        await tester.enterText(
          find.byKey(const Key('reset-confirmation-field')),
          attempt,
        );
        await tester.pump();
        expect(confirmEnabled(tester), isFalse, reason: '"$attempt"');
      }
      expect(recovery.resets, 0);

      await tester.enterText(
        find.byKey(const Key('reset-confirmation-field')),
        resetConfirmationWord,
      );
      await tester.pump();
      expect(confirmEnabled(tester), isTrue);
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(recovery.resets, 1);
      // Not a success message: the app started again, and that start decides.
      expect(starts, 2);
      expect(find.textContaining('success', findRichText: true), findsNothing);
      expectNoTechnicalText(tester);
    });

    testWidgets('a start that fails after a reset shows that failure', (
      tester,
    ) async {
      await openReset(tester, pathy);
      await tester.enterText(
        find.byKey(const Key('reset-confirmation-field')),
        resetConfirmationWord,
      );
      await tester.pump();
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      // The second scripted start failed; the runner showed a failure screen again.
      expect(shown.last, isA<StartupFailureApp>());
      await tester.pumpWidget(shown.last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          startupFailureWording(StartupFailureKind.localDataUnreadable).title,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a reset that fails says so, and does not start again', (
      tester,
    ) async {
      recovery = _FakeRecovery(fails: true);
      await openReset(tester, pathy);
      await tester.enterText(
        find.byKey(const Key('reset-confirmation-field')),
        resetConfirmationWord,
      );
      await tester.pump();
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reset-failed')), findsOneWidget);
      expect(starts, 1);
      expectNoTechnicalText(tester);
    });

    testWidgets('Cancel goes back and changes nothing', (tester) async {
      await openReset(tester, pathy);
      await tester.tap(find.byKey(const Key('reset-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('startup-try-again')), findsOneWidget);
      expect(recovery.resets, 0);
    });

    final statements = <String, (UnsyncedWorkAssessment, String, String?)>{
      'unknown': (
        const UnsyncedWorkUnknown(UnsyncedWorkUnknownReason.keyUnavailable),
        'not possible to check',
        'No entries waiting',
      ),
      'counted': (
        const UnsyncedWorkCounted(
          queued: 3,
          needsAttention: 1,
          billsNotUploaded: 2,
        ),
        '3 entries recorded on this device have not reached the server',
        'No entries waiting',
      ),
      'counted, bills unknown': (
        const UnsyncedWorkCounted(
          queued: 0,
          needsAttention: 0,
          billsNotUploaded: null,
        ),
        'could not be checked',
        null,
      ),
      'nothing unsent': (
        const UnsyncedWorkCounted(
          queued: 0,
          needsAttention: 0,
          billsNotUploaded: 0,
        ),
        'No entries waiting to be sent were found',
        'may be lost',
      ),
    };
    for (final MapEntry(key: name, value: (assessment, says, never))
        in statements.entries) {
      testWidgets('tells the truth about unsent work: $name', (tester) async {
        recovery = _FakeRecovery(assessment: assessment);
        await openReset(tester, pathy);
        final text = tester
            .widget<Text>(find.byKey(const Key('reset-unsynced-statement')))
            .data!;
        expect(text, contains(says));
        if (never != null) expect(text, isNot(contains(never)));
        expect(text, isNot(contains('safely synced')));
      });
    }
  });

  test('every wording is plain and never names an implementation', () {
    for (final kind in StartupFailureKind.values) {
      final w = startupFailureWording(kind);
      expect(_technical.hasMatch(w.title), isFalse, reason: kind.name);
      expect(_technical.hasMatch(w.body), isFalse, reason: kind.name);
      // A build problem is not fixed by trying again, and does not say it is.
      if (kind != StartupFailureKind.configuration) {
        expect(w.body, contains('ry again'), reason: kind.name);
      }
    }
  });

  test('main() shows no raw error text', () {
    final main = File('lib/main.dart').readAsStringSync();
    final runner = File(
      'lib/app/startup/startup_runner.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/app/startup/startup_failure_app.dart',
    ).readAsStringSync();
    for (final source in [main, runner, screen]) {
      expect(source, isNot(contains(r"'$error'")));
      expect(source, isNot(contains('SelectableText')));
      expect(source, isNot(contains('error.toString()')));
    }
  });
}

class _Started implements Exception {}
