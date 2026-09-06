/// Getting a bill onto the device, safely, before anything is sent anywhere.
///
/// Three rules shape this file.
///
/// **1 · The source is copied, never referenced.** A gallery URI, a Downloads path or a
/// camera temp file can be moved, renamed, revoked or garbage-collected between the
/// moment a user attaches it and the moment the upload runs — which may be days later, on
/// a different network, after a restart. So the bytes are copied into app-private storage
/// first, and the record points at that copy.
///
/// **2 · Nothing here waits for a network, and the expense never waits for this.**
/// Staging is local work. The upload is out of band (spec §15): a failing photo must not
/// stop a financial record from syncing.
///
/// **3 · The hash is computed on what was staged.** It is what makes "uploaded" a claim
/// about bytes rather than about an HTTP status. The same hash is compared after the
/// server has the object, and only then does the staging copy become reclaimable.
///
/// Images are re-encoded on the way in, to the approved ~2.5 MB target, in pure Dart —
/// no platform plugin, so both targets behave identically. Documents are not re-encoded:
/// re-writing a PDF risks changing what an invoice says, and the limit is a limit.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:krishna_mis/domain/attachments/document_attachment.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Where app-private attachment staging lives. Injected so a test can point it at a
/// temporary directory without touching the real application support directory.
typedef StagingDirectoryResolver = Future<Directory> Function();

/// Why a file was not accepted. Each one is something to tell the user plainly.
///
/// The wording takes the document kind, because "an expense can carry at most 5
/// attachments" is the wrong sentence to show somebody recording a day's takings. The
/// numbers are the same for both (spec §15, [AttachmentPolicy]).
enum AttachmentRejection {
  tooManyAttachments,
  documentTooLarge,
  documentWouldExceedTotal,
  unsupportedType,
  unreadableSource;

  String messageFor(AttachmentOwnerKind owner) => switch (this) {
    AttachmentRejection.tooManyAttachments =>
      'A${owner == AttachmentOwnerKind.expense ? 'n' : ''} ${owner.noun} can '
          'carry at most ${AttachmentPolicy.maxPerDocument} attachments.',
    AttachmentRejection.documentTooLarge =>
      'A document may be up to '
          '${AttachmentPolicy.maxDocumentBytes ~/ (1024 * 1024)} MB.',
    AttachmentRejection.documentWouldExceedTotal =>
      'Together the attachments on one ${owner.noun} may be up to '
          '${AttachmentPolicy.maxTotalBytesPerDocument ~/ (1024 * 1024)} MB.',
    AttachmentRejection.unsupportedType =>
      'Only images and PDF documents can be attached.',
    AttachmentRejection.unreadableSource =>
      'That file could not be read. Try attaching it again.',
  };

  /// The expense wording, which is what the expense surfaces already read.
  String get message => messageFor(AttachmentOwnerKind.expense);
}

/// Refused, with a reason worth showing.
final class AttachmentRefused implements Exception {
  const AttachmentRefused(this.reason);
  final AttachmentRejection reason;
  @override
  String toString() => 'AttachmentRefused(${reason.name}): ${reason.message}';
}

/// The content types a financial document's attachment may have.
///
/// Deliberately a short list. "Whatever the picker returned" is how a 400 MB video ends
/// up attached to a ₹200 grocery bill.
abstract final class AttachmentTypes {
  static const Set<String> images = {
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif',
    'image/webp',
  };
  static const Set<String> documents = {'application/pdf'};

  static bool isSupported(String contentType) =>
      images.contains(contentType) || documents.contains(contentType);

  /// Best guess from a file name, for pickers that do not report one.
  static String? fromFileName(String fileName) =>
      switch (p.extension(fileName).toLowerCase()) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.png' => 'image/png',
        '.heic' => 'image/heic',
        '.heif' => 'image/heif',
        '.webp' => 'image/webp',
        '.pdf' => 'application/pdf',
        _ => null,
      };
}

/// Re-encodes an image towards a size target while keeping it readable.
///
/// An invoice photograph is only worth keeping if the figures on it can still be read, so
/// this reduces quality and dimensions in steps and stops as soon as the target is met —
/// it never crushes an image that was already small, and it never keeps going below a
/// floor. If the target cannot be met, the best attempt is kept rather than the file being
/// refused: a large, legible bill is worth more than no bill.
class ImageOptimizer {
  const ImageOptimizer({
    this.targetBytes = AttachmentPolicy.imageTargetBytes,
    this.maxDimension = 2600,
    this.minDimension = 1400,
  });

  final int targetBytes;

  /// A phone camera produces far more resolution than a receipt needs. 2600px on the
  /// long edge keeps small print legible.
  final int maxDimension;

  /// Never go below this, whatever the target says. Below it, digits start to go.
  final int minDimension;

  Uint8List optimize(Uint8List bytes) {
    if (bytes.length <= targetBytes) return bytes;

    final decoded = img.decodeImage(bytes);
    // Not something this build can decode — HEIC on a desktop, say. Keep the original:
    // an attachment that is too large is a smaller problem than a lost receipt.
    if (decoded == null) return bytes;

    var best = bytes;
    for (final quality in const [85, 75, 65]) {
      for (final longEdge in [maxDimension, 2000, minDimension]) {
        final scaled = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: longEdge)
            : img.copyResize(decoded, height: longEdge);
        final encoded = Uint8List.fromList(
          img.encodeJpg(scaled, quality: quality),
        );
        if (encoded.length < best.length) best = encoded;
        if (encoded.length <= targetBytes) return encoded;
      }
    }
    return best;
  }
}

/// What was staged, ready to be attached to an expense.
final class StagedAttachment {
  const StagedAttachment({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.byteSize,
    required this.contentHash,
    required this.localPath,
    required this.originalByteSize,
  });

  final String id;
  final String fileName;
  final String contentType;
  final int byteSize;
  final String contentHash;
  final String localPath;

  /// What the source file weighed before optimisation. Reported so the interface can say
  /// something true about what it did rather than silently shrinking a user's file.
  final int originalByteSize;

  bool get wasOptimized => byteSize < originalByteSize;

  DocumentAttachment toDomain() => DocumentAttachment(
    id: id,
    fileName: fileName,
    contentType: contentType,
    byteSize: byteSize,
    contentHash: contentHash,
    uploadState: AttachmentUploadState.staged,
    localStagingPath: localPath,
  );
}

class AttachmentStagingService {
  AttachmentStagingService({
    required this.resolveStagingDirectory,
    this.optimizer = const ImageOptimizer(),
  });

  final StagingDirectoryResolver resolveStagingDirectory;
  final ImageOptimizer optimizer;

  /// Copies [source] into app-private storage, optimising it if it is an image.
  ///
  /// [ownerId] is the financial document's own id — an expense or a revenue entry. It
  /// names the staging sub-directory and nothing else; both are UUID v7 values from one
  /// namespace, so there is no collision to design around and no branch here that has to
  /// know which kind it is.
  ///
  /// [alreadyAttached] is what the document already carries, so the per-document count
  /// and total are checked against reality rather than against one file at a time.
  Future<StagedAttachment> stage({
    required File source,
    required String ownerId,
    String? fileName,
    String? contentType,
    List<DocumentAttachment> alreadyAttached = const [],
  }) async {
    if (alreadyAttached.length >= AttachmentPolicy.maxPerDocument) {
      throw const AttachmentRefused(AttachmentRejection.tooManyAttachments);
    }
    if (!source.existsSync()) {
      throw const AttachmentRefused(AttachmentRejection.unreadableSource);
    }

    final name = fileName ?? p.basename(source.path);
    final type = contentType ?? AttachmentTypes.fromFileName(name);
    if (type == null || !AttachmentTypes.isSupported(type)) {
      throw const AttachmentRefused(AttachmentRejection.unsupportedType);
    }

    Uint8List bytes;
    try {
      bytes = await source.readAsBytes();
    } on Object {
      throw const AttachmentRefused(AttachmentRejection.unreadableSource);
    }
    final originalSize = bytes.length;

    // Images shrink towards the target; documents are taken as they are, because
    // re-writing a PDF risks changing what the invoice says.
    var storedName = name;
    if (AttachmentTypes.images.contains(type)) {
      final optimised = optimizer.optimize(bytes);
      if (optimised.length < bytes.length) {
        bytes = optimised;
        storedName = '${p.basenameWithoutExtension(name)}.jpg';
      }
    } else if (bytes.length > AttachmentPolicy.maxDocumentBytes) {
      throw const AttachmentRefused(AttachmentRejection.documentTooLarge);
    }

    final existingTotal = alreadyAttached.fold<int>(
      0,
      (sum, a) => sum + a.byteSize,
    );
    if (existingTotal + bytes.length >
        AttachmentPolicy.maxTotalBytesPerDocument) {
      throw const AttachmentRefused(
        AttachmentRejection.documentWouldExceedTotal,
      );
    }

    final id = const Uuid().v4();
    final directory = Directory(
      p.join((await resolveStagingDirectory()).path, ownerId),
    );
    await directory.create(recursive: true);

    final extension = p.extension(storedName);
    final staged = File(p.join(directory.path, '$id$extension'));
    await staged.writeAsBytes(bytes, flush: true);

    return StagedAttachment(
      id: id,
      fileName: storedName,
      contentType:
          AttachmentTypes.images.contains(type) && storedName.endsWith('.jpg')
          ? 'image/jpeg'
          : type,
      byteSize: bytes.length,
      contentHash: sha256Of(bytes),
      localPath: staged.path,
      originalByteSize: originalSize,
    );
  }

  /// Deletes the staged copy of an attachment that was never saved.
  ///
  /// Only ever for an abandoned draft. A staged file belonging to a saved document is
  /// reclaimed by `AttachmentUploadWorker.reclaimVerifiedStaging`, and only after the
  /// server has confirmed it.
  Future<void> discard(StagedAttachment attachment) async {
    final file = File(attachment.localPath);
    if (file.existsSync()) await file.delete();
  }

  /// Removes the whole staging directory for a document that was abandoned or purged.
  Future<void> discardDocument(String ownerId) async {
    final directory = Directory(
      p.join((await resolveStagingDirectory()).path, ownerId),
    );
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

/// SHA-256, lowercase hex, of exactly these bytes.
String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

/// SHA-256 of a file, read in chunks so a 10 MB PDF does not have to be held twice.
Future<String> sha256OfFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}

/// The base64 of the SHA-256 digest, which is the shape object stores report.
String base64Sha256(List<int> bytes) =>
    base64.encode(sha256.convert(bytes).bytes);
