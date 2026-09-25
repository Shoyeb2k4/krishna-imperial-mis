/// The fonts an exported PDF is set in (Phase 7 Slice 5; D-295, `ARCHITECTURE.md` §51.5).
///
/// Noto Sans Regular and Bold, bundled with the application under
/// `assets/fonts/noto_sans/` with their SIL Open Font License. The renderer is **handed**
/// the bytes: it never loads an asset, opens a file or fetches anything, so a PDF looks the
/// same on every device and with the network absent. The delivery layer reads the bundle.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Where the bundled fonts live, for whoever reads the bundle.
const exportPdfRegularFontAsset = 'assets/fonts/noto_sans/NotoSans-Regular.ttf';
const exportPdfBoldFontAsset = 'assets/fonts/noto_sans/NotoSans-Bold.ttf';

/// The Indian rupee sign. A font that cannot draw it cannot set an exported figure.
const _rupee = 0x20B9;

final class ExportPdfFonts {
  ExportPdfFonts._(this.regular, this.bold);

  /// From the bundled font bytes. Refuses a font that cannot draw ₹, rather than letting
  /// the PDF print a figure with a missing symbol.
  factory ExportPdfFonts.fromBytes({
    required ByteData regular,
    required ByteData bold,
  }) {
    for (final data in [regular, bold]) {
      if (!TtfParser(data).charToGlyphIndexMap.containsKey(_rupee)) {
        throw ArgumentError('the export font cannot draw the rupee sign');
      }
    }
    return ExportPdfFonts._(pw.Font.ttf(regular), pw.Font.ttf(bold));
  }

  final pw.Font regular;
  final pw.Font bold;
}
