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
/// P&L is opened. Only this app's own export files are touched.
///
/// **What the share sheet can and cannot say.** Android returns nothing about what the
/// person did in the sheet, so a closed sheet cannot be told from a completed share. The
/// sheet opening is reported as that, and no more.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
final exportShareCacheRootProvider = FutureProvider<Directory>(
  (ref) => exportShareCacheRoot(),
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
