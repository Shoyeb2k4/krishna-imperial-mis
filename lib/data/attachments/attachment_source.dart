/// Where a bill comes from, per platform, behind one interface.
///
/// Android has a camera and a gallery; Windows has a file dialog. Those are genuinely
/// different affordances and the interface says so rather than pretending one abstraction
/// covers both — a "pick a file" button on a phone is a worse experience than a camera
/// button, and a camera button on a finance workstation is nonsense.
///
/// What every implementation must guarantee is the same, and it is the security-relevant
/// part: whatever comes back is handed to [AttachmentStagingService], which copies the
/// bytes into app-private storage before anything else happens. An implementation must
/// never return a path the application intends to keep referencing — the OS may revoke,
/// move or clean it, and a receipt that vanished between capture and upload is a receipt
/// that was never kept.
library;

import 'dart:io';

import 'package:krishna_mis/app/routing/app_router.dart';

/// One way of getting a file.
enum AttachmentIntake {
  /// Take a photograph now. Android only.
  camera,

  /// Choose an existing image. Android's gallery.
  gallery,

  /// Choose any supported file. The Windows file dialog, and Android's document picker.
  file;

  String get label => switch (this) {
    AttachmentIntake.camera => 'Take a photo',
    AttachmentIntake.gallery => 'Choose a photo',
    AttachmentIntake.file => 'Choose a file',
  };
}

/// A file the user chose, before it has been staged.
///
/// [file] may live anywhere — a camera cache, a content URI resolved to a temp copy, a
/// Documents folder. It is not durable, and nothing may hold on to it.
final class PickedFile {
  const PickedFile({
    required this.file,
    required this.fileName,
    this.contentType,
  });

  final File file;
  final String fileName;
  final String? contentType;
}

/// The platform's way of producing a file. One implementation per target.
abstract interface class AttachmentSource {
  /// Which intakes this platform actually offers.
  Set<AttachmentIntake> get available;

  /// Returns null when the user cancelled — which is an ordinary outcome, not an error.
  Future<PickedFile?> pick(AttachmentIntake intake);
}

/// What each platform offers, so the interface can be built from the same list the
/// implementation honours.
Set<AttachmentIntake> intakesFor(AppShellKind shellKind) => switch (shellKind) {
  // A phone is the operational entry device: photographing the bill is the point
  // (spec §18).
  AppShellKind.mobile => {
    AttachmentIntake.camera,
    AttachmentIntake.gallery,
    AttachmentIntake.file,
  },
  // A finance workstation receives invoices as files (spec §19).
  AppShellKind.desktop => {AttachmentIntake.file},
};

/// The implementation used when no platform source has been installed.
///
/// Returns nothing and offers nothing, so a screen built before the platform plugins land
/// degrades to "no attachment" rather than to a crash. Never used in a shipped build with
/// attachments enabled; the bootstrap installs a real one per platform.
class UnavailableAttachmentSource implements AttachmentSource {
  const UnavailableAttachmentSource();

  @override
  Set<AttachmentIntake> get available => const {};

  @override
  Future<PickedFile?> pick(AttachmentIntake intake) async => null;
}
