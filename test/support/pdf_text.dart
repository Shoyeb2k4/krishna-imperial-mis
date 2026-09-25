/// Reads the text back out of a generated PDF, for the Phase 7 export tests (Slice 5).
///
/// The renderer embeds TrueType fonts, so a content stream holds glyph codes, not
/// letters: searching the bytes for "Net Sales" would find nothing even when the page
/// says it. This reader does what a PDF viewer's text layer does. It decodes each glyph
/// code through the font's own `/ToUnicode` map, then groups the words on a page into
/// lines by their vertical position.
///
/// It expects an **uncompressed** PDF, which the renderer produces when asked to
/// (`compress: false`).
library;

import 'dart:convert';
import 'dart:typed_data';

final class PdfTextPage {
  PdfTextPage(this.lines);

  /// Top to bottom; each line's words left to right, joined by single spaces.
  final List<String> lines;

  String get text => lines.join('\n');
}

final class PdfText {
  PdfText._(this.pages);

  factory PdfText.read(Uint8List bytes) {
    final raw = latin1.decode(bytes);
    if (raw.contains('/FlateDecode')) {
      throw StateError('the PDF is compressed; render it with compress: false');
    }
    final objects = <int, String>{
      for (final m in RegExp(
        r'(\d+) 0 obj\s*(.*?)\s*endobj',
        dotAll: true,
      ).allMatches(raw))
        int.parse(m.group(1)!): m.group(2)!,
    };

    // Font object number -> (glyph code -> text).
    final cmaps = <int, Map<int, String>>{};
    for (final entry in objects.entries) {
      final ref = RegExp(r'/ToUnicode (\d+) 0 R').firstMatch(entry.value);
      if (ref == null) continue;
      final cmap = objects[int.parse(ref.group(1)!)]!;
      cmaps[entry.key] = {
        for (final m in RegExp(
          r'<([0-9A-Fa-f]{4})> <([0-9A-Fa-f]{4,})>',
        ).allMatches(cmap))
          int.parse(m.group(1)!, radix: 16): String.fromCharCode(
            int.parse(m.group(2)!, radix: 16),
          ),
      };
    }

    // Pages, in the order the page tree lists them.
    final pagesObject = objects.values.firstWhere(
      (o) => o.contains('/Type/Pages'),
    );
    final kids = [
      for (final m in RegExp(r'(\d+) 0 R').allMatches(
        RegExp(r'/Kids\s*\[([^\]]*)\]').firstMatch(pagesObject)!.group(1)!,
      ))
        int.parse(m.group(1)!),
    ];

    final pages = <PdfTextPage>[];
    for (final kid in kids) {
      final page = objects[kid]!;
      final contents = RegExp(
        r'/Contents (\d+) 0 R',
      ).firstMatch(page)!.group(1)!;
      final stream = RegExp(
        r'stream\r?\n(.*?)\r?\nendstream',
        dotAll: true,
      ).firstMatch(objects[int.parse(contents)]!)!.group(1)!;

      // Every word, placed on the page through the current transformation matrix: the
      // widgets nest `q … cm … Q` blocks, and a `Td` is relative to them.
      final words = <(double, double, String)>[];
      var ctm = const [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
      final saved = <List<double>>[];
      Map<int, String> font = const {};
      const n = r'(-?[\d.]+)';
      for (final m in RegExp(
        '(?<![\\w/])(q|Q)(?![\\w])'
        '|$n $n $n $n $n $n cm'
        r'|/F(\d+) [\d.]+ Tf'
        '|$n $n Td \\[<([0-9a-fA-F]*)>\\]TJ',
      ).allMatches(stream)) {
        if (m.group(1) == 'q') {
          saved.add(ctm);
        } else if (m.group(1) == 'Q') {
          ctm = saved.removeLast();
        } else if (m.group(2) != null) {
          final t = [for (var i = 2; i <= 7; i++) double.parse(m.group(i)!)];
          // new = t × ctm
          ctm = [
            t[0] * ctm[0] + t[1] * ctm[2],
            t[0] * ctm[1] + t[1] * ctm[3],
            t[2] * ctm[0] + t[3] * ctm[2],
            t[2] * ctm[1] + t[3] * ctm[3],
            t[4] * ctm[0] + t[5] * ctm[2] + ctm[4],
            t[4] * ctm[1] + t[5] * ctm[3] + ctm[5],
          ];
        } else if (m.group(8) != null) {
          font = cmaps[int.parse(m.group(8)!)] ?? const {};
        } else {
          final x = double.parse(m.group(9)!);
          final y = double.parse(m.group(10)!);
          final hex = m.group(11)!;
          final b = StringBuffer();
          for (var i = 0; i < hex.length; i += 4) {
            b.write(
              font[int.parse(hex.substring(i, i + 4), radix: 16)] ?? '\uFFFD',
            );
          }
          words.add((
            x * ctm[1] + y * ctm[3] + ctm[5],
            x * ctm[0] + y * ctm[2] + ctm[4],
            b.toString(),
          ));
        }
      }

      // Group by baseline, top of the page first.
      final byLine = <int, List<(double, String)>>{};
      for (final (y, x, text) in words) {
        byLine.putIfAbsent(y.round(), () => []).add((x, text));
      }
      final ys = byLine.keys.toList()..sort((a, b) => b.compareTo(a));
      pages.add(
        PdfTextPage([
          for (final y in ys)
            (byLine[y]!..sort((a, b) => a.$1.compareTo(b.$1)))
                .map((w) => w.$2)
                .join(' '),
        ]),
      );
    }
    return PdfText._(pages);
  }

  final List<PdfTextPage> pages;

  String get text => pages.map((p) => p.text).join('\n\f\n');

  /// Every line of every page.
  List<String> get lines => [for (final p in pages) ...p.lines];
}
