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
///
/// The dialog asks for the document only after the person presses Print, and it gets it
/// from [layout], not from [bytes]: [layout] decides authority again at that moment, so a
/// `reports.print` withdrawn while the dialog is open sends nothing (Slice 10). [bytes]
/// is the document the layout would give, for a caller that records or names the job.
typedef ExportPrinter =
    Future<bool> Function({
      required Uint8List bytes,
      required String jobName,
      required Uint8List Function() layout,
    });

/// The document the print dialog is given: [bytes] while [stillPermitted] holds, and no
/// bytes at all once it does not. `printing` aborts a job whose document is empty
/// (`AbortDoc`) and reports it as failed, so nothing reaches the printer. Throwing here
/// instead would leave the plugin's future unanswered for ever.
Uint8List exportPrintLayout(Uint8List bytes, bool Function() stillPermitted) =>
    stillPermitted() ? bytes : Uint8List(0);

/// The native print dialog, through `printing`.
Future<bool> printingLayoutPdf({
  required Uint8List bytes,
  required String jobName,
  required Uint8List Function() layout,
}) => Printing.layoutPdf(
  // The document is laid out once, by the renderer; the dialog's page choice does not
  // re-lay it out.
  onLayout: (_) async => layout(),
  name: jobName,
  format: PdfPageFormat.a4,
  dynamicLayout: false,
);
