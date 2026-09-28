/// Sharing the P&L PDF on Android (Phase 7 Slice 8; D-293, `ARCHITECTURE.md` §51.7).
///
/// ```
///     canonical report → document model → PDF renderer → these bytes
///       → printing's sharePdf → <app cache>/share/<name>.pdf, through its FileProvider
///       → the system share sheet
/// ```
///
/// **No storage permission.** The file is written to the app's private cache and handed
/// to the chosen app through `printing`'s own FileProvider (`<cache>/share/`), which grants
/// read access to that one file. Nothing is written to shared storage, and the manifest
/// declares no storage permission.
///
/// **Cleanup is ours.** `printing` leaves the file for the receiving app to read and marks
/// it only `deleteOnExit`, which on Android almost never runs. A file cannot be removed the
/// moment the sheet opens — the chosen app has not read it yet — so every earlier export
/// this app shared is removed from that folder before the next share, and when the phone
/// P&L is opened. It also goes when the person who shared it signs out or another person
/// takes the session (D-310): the file is management financial data, and it must not
/// survive into somebody else's session. Only this app's own export files are touched.
///
/// **What the share sheet can and cannot say.** Android returns nothing about what the
/// person did in the sheet, so a closed sheet cannot be told from a completed share. The
/// sheet opening is reported as that, and no more.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:krishna_mis/app/providers.dart';
import 'package:krishna_mis/core/export/export_wording.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import 'package:printing/printing.dart';

/// Hands [bytes] to the system share sheet as [fileName]. True when the sheet was opened.
typedef ExportSharer =
    Future<bool> Function({required Uint8List bytes, required String fileName});

/// The system share sheet, through `printing`.
Future<bool> printingSharePdf({
  required Uint8List bytes,
  required String fileName,
}) => Printing.sharePdf(bytes: bytes, filename: fileName);

/// Where an Android share goes: the system share sheet. Overridden in tests.
final exportSharerProvider = Provider<ExportSharer>((ref) => printingSharePdf);

/// The app's private cache, where a shared file is placed. Overridden in tests.
///
/// Not retried: a cache that cannot be reached is answered once, so a cleanup or a share
/// waiting on it gets the error rather than waiting through Riverpod's retry backoff.
final exportShareCacheRootProvider = FutureProvider<Directory>(
  (ref) => exportShareCacheRoot(),
  retry: (_, _) => null,
);

/// The app's private cache — where `printing` places a shared file. On Android this is
/// the application's own cache folder, which no other app can read.
Future<Directory> exportShareCacheRoot() => getTemporaryDirectory();

/// Removes every export this app shared earlier from `<cache>/share/`. Returns how many
/// were removed. Never touches another file, and never fails a share because a file
/// could not be removed.
int removeEarlierShares(Directory cacheRoot) {
  final folder = Directory('${cacheRoot.path}${Platform.pathSeparator}share');
  if (!folder.existsSync()) return 0;
  var removed = 0;
  for (final entry in folder.listSync()) {
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entry is File &&
        name.startsWith(exportFileNamePrefix) &&
        name.endsWith('.pdf')) {
      try {
        entry.deleteSync();
        removed++;
      } on FileSystemException {
        // Left for the next share; the share itself is not refused for it.
      }
    }
  }
  return removed;
}

/// Removes this app's shared PDFs whenever the signed-in person changes: sign-out, a user
/// switch, or a session ending (D-310).
///
/// It watches who is signed in and nothing else. A refresh for the same person, leaving the
/// Reports tab, or a widget that does not rebuild changes nothing. The application root
/// keeps it alive. It runs after the change and never inside sign-out, so a cache that
/// cannot be reached never blocks anybody from signing out. It touches only the files
/// [removeEarlierShares] touches.
final sharedExportCleanupProvider = Provider<SharedExportCleanup>((ref) {
  final cleanup = SharedExportCleanup();
  ref.listen<String?>(sessionProvider.select((s) => s.userId), (before, now) {
    if (before == now) return;
    cleanup.run(() => ref.read(exportShareCacheRootProvider.future));
  });
  return cleanup;
});

/// The person-change cleanup, with its latest run kept so a test can wait for it.
class SharedExportCleanup {
  Future<int> _last = Future.value(0);

  /// How many files the latest run removed; 0 when it could not reach the cache.
  Future<int> get last => _last;

  void run(Future<Directory> Function() cacheRoot) {
    _last = () async {
      try {
        return removeEarlierShares(await cacheRoot());
      } on Object {
        // Best effort: the next share, or the next change of person, tries again.
        return 0;
      }
    }();
  }
}
