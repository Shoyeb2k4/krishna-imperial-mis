/// A shared P&L PDF does not outlive the person who shared it (Phase 7 Slice 10, D-310).
///
/// The file sits in the app's private cache so the receiving app can read it. It is
/// derived management financial data, so it goes when that person signs out or another
/// person takes the session. It is not removed merely because the Reports tab is left.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/domain/auth/authority.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:krishna_mis/features/export/export_share.dart';

import '../../support/test_session.dart';

class _Session extends StubSession {
  _Session(super.initial);

  void become(SessionState next) => state = next;
}

void main() {
  late Directory cache;
  late File shared;
  late List<File> unrelated;

  setUp(() {
    cache = Directory.systemTemp.createTempSync('share-cleanup-');
    final share = Directory('${cache.path}/share')..createSync();
    shared = File(
      '${share.path}/KrishnaImperialMIS_ProfitAndLoss_Consolidated_2027-03-01_2027-03-31.pdf',
    )..writeAsBytesSync([1, 2, 3]);
    unrelated = [
      File('${share.path}/somebody-elses.pdf')..writeAsStringSync('x'),
      File('${share.path}/KrishnaImperialMIS_notes.txt')
        ..writeAsStringSync('x'),
      File('${cache.path}/KrishnaImperialMIS_Root.pdf')..writeAsStringSync('x'),
      File('${cache.path}/image_cache.bin')..writeAsStringSync('x'),
    ];
  });
  tearDown(() => cache.deleteSync(recursive: true));

  ({ProviderContainer container, _Session session}) start({
    Future<Directory> Function()? root,
  }) {
    final session = _Session(
      readySession(authority: fullAuthority(userId: 'user-a')),
    );
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => session),
        exportShareCacheRootProvider.overrideWith(
          (ref) => root == null ? Future.value(cache) : root(),
        ),
      ],
    );
    addTearDown(container.dispose);
    // The application root keeps the cleanup alive for the whole session.
    container.listen(sharedExportCleanupProvider, (_, _) {});
    return (container: container, session: session);
  }

  Future<int> settled(ProviderContainer c) =>
      c.read(sharedExportCleanupProvider).last;

  void expectUnrelatedIntact() {
    for (final f in unrelated) {
      expect(f.existsSync(), isTrue, reason: f.path);
    }
  }

  test('sign-out removes the shared PDF', () async {
    final s = start();
    await s.container.read(sessionProvider.notifier).signOut();
    expect(await settled(s.container), 1);
    expect(shared.existsSync(), isFalse);
    expectUnrelatedIntact();
  });

  test("a user switch removes the previous person's shared PDF", () async {
    final s = start();
    s.session.become(readySession(authority: fullAuthority(userId: 'user-b')));
    expect(await settled(s.container), 1);
    expect(shared.existsSync(), isFalse);
    expectUnrelatedIntact();
  });

  test('the same person staying signed in keeps the file', () async {
    final s = start();
    // A refresh for the same person: nothing about who is signed in changed.
    s.session.become(
      readySession(
        authority: fullAuthority(userId: 'user-a'),
        freshness: AuthorityFreshness.stale,
      ),
    );
    expect(await settled(s.container), 0);
    expect(shared.existsSync(), isTrue);
  });

  test('unrelated cache content is never touched', () async {
    final s = start();
    s.session.become(const SessionState.unauthenticated());
    await settled(s.container);
    expectUnrelatedIntact();
    expect(Directory('${cache.path}/share').existsSync(), isTrue);
  });

  test('a cache that cannot be reached does not block sign-out', () async {
    final s = start(root: () => Future.error(const FileSystemException('no')));
    await s.container.read(sessionProvider.notifier).signOut();
    expect(
      s.container.read(sessionProvider),
      isA<SessionState>().having((st) => st.userId, 'userId', isNull),
    );
    expect(await settled(s.container), 0);
  });

  test('the next share still removes an earlier file', () {
    // The cleanup before each share is unchanged (D-306).
    expect(removeEarlierShares(cache), 1);
    expect(shared.existsSync(), isFalse);
    expectUnrelatedIntact();
  });
}
