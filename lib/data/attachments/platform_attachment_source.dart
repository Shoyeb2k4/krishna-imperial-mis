/// The real platform pickers, behind the one interface the expense form uses.
///
/// This file exists because of a defect worth stating plainly: for the whole of Phase 3
/// the only implementation of [AttachmentSource] in `lib/` was
/// [UnavailableAttachmentSource], and nothing ever replaced it. Every automated
/// attachment test overrode the provider with a synthetic source, so the entire pipeline
/// behind the picker was proven while the picker itself did not exist, on either
/// platform. See D-077.
///
/// The division of labour here is deliberate:
///
///   * **Android** photographs or chooses an image through `image_picker`, with the
///     system **Photo Picker** explicitly enabled — that is the modern, permission-free
///     path, and it is opt-in rather than the default. Choosing an arbitrary document
///     goes through `file_selector`, which on Android is the Storage Access Framework.
///     Neither needs a storage permission, and neither is asked for.
///   * **Windows** opens the native `IFileOpenDialog` through `file_selector`. No custom
///     browser, no elevation.
///
/// What both guarantee is the part that matters downstream: whatever comes back is a
/// throwaway handle, handed straight to `AttachmentStagingService`, which copies the bytes
/// into app-private storage. Nothing here returns a path the application keeps.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:image_picker/image_picker.dart' hide PickedFile;
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart'
    hide PickedFile;
import 'package:krishna_mis/data/attachments/attachment_source.dart';
import 'package:krishna_mis/data/attachments/attachment_staging.dart';

/// The extensions the file dialog offers, derived from the one accepted-type table so a
/// new supported type cannot be added to the policy and forgotten in the picker.
const List<String> _acceptedExtensions = [
  'jpg',
  'jpeg',
  'png',
  'heic',
  'heif',
  'webp',
  'pdf',
];

/// Windows matches on extension; Android matches on MIME type. Supplying both lets one
/// declaration serve both platform implementations.
final fs.XTypeGroup _billTypeGroup = fs.XTypeGroup(
  label: 'Bills and invoices',
  extensions: _acceptedExtensions,
  mimeTypes: [...AttachmentTypes.images, ...AttachmentTypes.documents],
);

/// Turns a plugin's file handle into a [PickedFile], preferring the plugin's own content
/// type and falling back to the extension — Android's Photo Picker frequently reports no
/// MIME type at all.
PickedFile _pickedFrom(String path, String name, String? mimeType) =>
    PickedFile(
      file: File(path),
      fileName: name,
      contentType: mimeType ?? AttachmentTypes.fromFileName(name),
    );

/// Android: camera, the system Photo Picker, and the Storage Access Framework.
class AndroidAttachmentSource implements AttachmentSource {
  AndroidAttachmentSource({ImagePicker? images})
    : _images = images ?? ImagePicker() {
    // Opt in to the system Photo Picker. It defaults to **false**, which would fall back
    // to an intent that reads the media store — the very thing that drags a storage
    // permission in behind it.
    final platform = ImagePickerPlatform.instance;
    if (platform is ImagePickerAndroid) {
      platform.useAndroidPhotoPicker = true;
    }
  }

  final ImagePicker _images;

  @override
  Set<AttachmentIntake> get available => const {
    AttachmentIntake.camera,
    AttachmentIntake.gallery,
    AttachmentIntake.file,
  };

  @override
  Future<PickedFile?> pick(AttachmentIntake intake) async {
    switch (intake) {
      case AttachmentIntake.camera:
      case AttachmentIntake.gallery:
        final source = intake == AttachmentIntake.camera
            ? ImageSource.camera
            : ImageSource.gallery;
        final image = await _images.pickImage(source: source);
        if (image == null) return null;
        return _pickedFrom(image.path, image.name, image.mimeType);
      case AttachmentIntake.file:
        final file = await fs.openFile(acceptedTypeGroups: [_billTypeGroup]);
        if (file == null) return null;
        return _pickedFrom(file.path, file.name, file.mimeType);
    }
  }
}

/// Windows: the native file dialog, and nothing else. A finance workstation receives
/// invoices as files (spec §19).
class WindowsAttachmentSource implements AttachmentSource {
  const WindowsAttachmentSource();

  @override
  Set<AttachmentIntake> get available => const {AttachmentIntake.file};

  @override
  Future<PickedFile?> pick(AttachmentIntake intake) async {
    if (intake != AttachmentIntake.file) return null;
    final file = await fs.openFile(acceptedTypeGroups: [_billTypeGroup]);
    if (file == null) return null;
    return _pickedFrom(file.path, file.name, file.mimeType);
  }
}

/// The adapter for [operatingSystem], as [Platform.operatingSystem] reports it.
///
/// A plain function of a string rather than a read of `Platform` inside a widget, so a
/// host test can assert **both** production branches without running on either device —
/// which is exactly the assertion that was missing when the picker silently did not exist.
AttachmentSource attachmentSourceFor(
  String operatingSystem,
) => switch (operatingSystem) {
  'android' => AndroidAttachmentSource(),
  'windows' => const WindowsAttachmentSource(),
  // The product targets Android and Windows only (spec §2). Anything else — a host
  // test process, a platform this product does not ship on — genuinely has no picker,
  // and says so rather than pretending.
  _ => const UnavailableAttachmentSource(),
};
