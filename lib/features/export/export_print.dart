/// Printing an exported report on Windows (Phase 7 Slice 7; D-299, `ARCHITECTURE.md`
/// §51.5).
///
/// ```
///     canonical report → document model → PDF renderer → these bytes
///       → Printing.layoutPdf → the native Windows print dialog
/// ```
///
/// **Printing is the PDF.** The dialog receives exactly the bytes the PDF renderer made for
/// the report — the same bytes Save PDF writes. There is no print layout, no print-specific
/// figure, no second renderer and no direct printer protocol. Whatever page size the
/// person picks in the dialog, the document is the A4 PDF it already is.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Hands [bytes] to the native print dialog. True when the job was sent, false when the
/// person closed the dialog without printing.
typedef ExportPrinter =
    Future<bool> Function({required Uint8List bytes, required String jobName});

/// The native print dialog, through `printing`.
Future<bool> printingLayoutPdf({
  required Uint8List bytes,
  required String jobName,
}) => Printing.layoutPdf(
  // The document is laid out once, by the renderer; the dialog's page choice does not
  // re-lay it out.
  onLayout: (_) async => bytes,
  name: jobName,
  format: PdfPageFormat.a4,
  dynamicLayout: false,
);
