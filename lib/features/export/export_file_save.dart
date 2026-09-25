/// Saving an exported file on Windows (Phase 7 Slice 6; `ARCHITECTURE.md` §51.7).
///
/// ```
///     suggested name → the native Save As dialog (file_selector getSaveLocation)
///       → cancelled?            nothing is written, and that is not an error
///       → extension missing?    added; a file already at the new name is refused, never
///                               replaced — the dialog asked about a different name
///       → write beside it, then rename over the chosen path
///       → failure?              the partial file is removed; the reason is stated
/// ```
///
/// The person chooses the folder every time. Nothing here names a default folder, reads
/// Downloads or Documents, or reaches anywhere the person did not choose.
///
/// **Overwriting.** Windows' own Save As dialog asks before it returns the name of a file
/// that already exists (the dialog's default `FOS_OVERWRITEPROMPT`), so a replacement that
/// reaches the write step is one the person confirmed. The only name that did not pass
/// through that question is one this code changed by adding the extension, and that one
/// is refused if it is taken.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:krishna_mis/features/export/export_pipeline.dart';

/// Asks the person where to save. Null when they cancelled.
typedef ExportSaveLocationPicker =
    Future<String?> Function({
      required String suggestedName,
      required ExportFileFormat format,
    });

/// The native Save As dialog, through `file_selector`.
Future<String?> fileSelectorSaveLocation({
  required String suggestedName,
  required ExportFileFormat format,
}) async {
  final location = await fs.getSaveLocation(
    suggestedName: suggestedName,
    confirmButtonText: 'Save',
    acceptedTypeGroups: [
      fs.XTypeGroup(label: format.label, extensions: [format.extension]),
    ],
  );
  return location?.path;
}

/// Why a file was not written.
enum ExportSaveFailure {
  /// The Save As dialog could not be shown.
  dialogUnavailable,

  /// The name, once its extension was added, belongs to a file that already exists — a
  /// file the dialog never asked about. It is not replaced.
  nameTaken,

  /// The folder or the file refused the write.
  permissionDenied,

  /// Another program has the file open (on Windows, typically the previous copy open in
  /// Excel or a PDF viewer).
  fileInUse,

  /// Any other write failure: a full disk, a folder that went away.
  writeFailed,
}

sealed class ExportSaveOutcome {
  const ExportSaveOutcome();
}

final class ExportSaved extends ExportSaveOutcome {
  const ExportSaved(this.fileName);

  /// The name the file was saved under, without its folder.
  final String fileName;
}

/// The person closed the dialog. Nothing was written, and nothing went wrong.
final class ExportSaveCancelled extends ExportSaveOutcome {
  const ExportSaveCancelled();
}

final class ExportSaveFailed extends ExportSaveOutcome {
  const ExportSaveFailed(this.failure);
  final ExportSaveFailure failure;
}

/// Saves bytes where the person chooses.
final class ExportFileSaver {
  ExportFileSaver({required this.pickLocation, Random? random})
    : _random = random ?? Random.secure();

  final ExportSaveLocationPicker pickLocation;
  final Random _random;

  /// Asks where, then writes. [beforeWrite] is asked once more after the dialog closes,
  /// and nothing is written if it says no — authority can change while a dialog is open.
  Future<ExportSaveOutcome> save({
    required Uint8List bytes,
    required String suggestedName,
    required ExportFileFormat format,
    bool Function()? beforeWrite,
  }) async {
    final String? chosen;
    try {
      chosen = await pickLocation(suggestedName: suggestedName, format: format);
    } on Object {
      return const ExportSaveFailed(ExportSaveFailure.dialogUnavailable);
    }
    if (chosen == null || chosen.isEmpty) return const ExportSaveCancelled();

    final ending = '.${format.extension}';
    final extensionAdded = !chosen.toLowerCase().endsWith(ending);
    final path = extensionAdded ? '$chosen$ending' : chosen;
    if (extensionAdded &&
        FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
      return const ExportSaveFailed(ExportSaveFailure.nameTaken);
    }
    if (beforeWrite != null && !beforeWrite()) {
      return const ExportSaveCancelled();
    }
    return writeAtomically(path, bytes, random: _random);
  }
}

/// Writes [bytes] to [path] so a failure never leaves a partial file under that name.
///
/// The bytes go to a hidden file in the same folder and are then renamed over [path]; a
/// failure at either step removes the hidden file.
Future<ExportSaveOutcome> writeAtomically(
  String path,
  Uint8List bytes, {
  Random? random,
}) async {
  final target = File(path);
  final name = target.uri.pathSegments.last;
  final token = (random ?? Random.secure()).nextInt(1 << 32).toRadixString(16);
  final temporary = File(
    '${target.parent.path}${Platform.pathSeparator}.$name.$token.part',
  );
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(target.path);
    return ExportSaved(name);
  } on FileSystemException catch (e) {
    try {
      if (temporary.existsSync()) temporary.deleteSync();
    } on FileSystemException {
      // The original failure is the one worth reporting.
    }
    return ExportSaveFailed(exportSaveFailureOf(e));
  }
}

/// What a file-system error means to the person saving.
ExportSaveFailure exportSaveFailureOf(FileSystemException e) {
  final code = e.osError?.errorCode;
  return Platform.isWindows
      ? exportSaveFailureForWindows(code)
      : exportSaveFailureForPosix(code);
}

/// The POSIX half of [exportSaveFailureOf], by errno. Separate so both halves are tested
/// on any host.
ExportSaveFailure exportSaveFailureForPosix(int? code) => switch (code) {
  1 || 13 || 30 => ExportSaveFailure.permissionDenied, // EPERM, EACCES, EROFS
  16 || 26 => ExportSaveFailure.fileInUse, // EBUSY, ETXTBSY
  _ => ExportSaveFailure.writeFailed,
};

/// The Windows half of [exportSaveFailureOf], by Win32 error code: ERROR_ACCESS_DENIED
/// and ERROR_WRITE_PROTECT; ERROR_SHARING_VIOLATION and ERROR_LOCK_VIOLATION.
ExportSaveFailure exportSaveFailureForWindows(int? code) => switch (code) {
  5 || 19 => ExportSaveFailure.permissionDenied,
  32 || 33 => ExportSaveFailure.fileInUse,
  _ => ExportSaveFailure.writeFailed,
};
