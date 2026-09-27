/// Makes a saved, compressed PDF readable by `test/support/pdf_text.dart` (Phase 7
/// Slice 10).
///
/// The shipped renderer compresses its streams, and the text reader reads only an
/// uncompressed PDF. The `pdf` package writes every object as an ordinary `N 0 obj`, so
/// inflating each `/FlateDecode` stream in place and dropping the filter gives the reader
/// the same content streams and `/ToUnicode` maps the uncompressed render has — read out
/// of the real file the person saved, not out of a second render.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Uint8List inflatePdfStreams(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  // A stream's dictionary: from `<<` to the `>>` directly before `stream`, never
  // reaching back across another object.
  final head = RegExp(
    r'<<((?:(?!>>\s*stream|endobj|\d+ 0 obj)[\s\S])*?)>>\s*stream\r?\n',
  );
  final out = StringBuffer();
  var at = 0;
  while (true) {
    final m = head.firstMatch(raw.substring(at));
    if (m == null) break;
    final dict = m.group(1)!;
    final length = RegExp(r'/Length\s+(\d+)(?!\s+\d+\s+R)').firstMatch(dict);
    if (length == null) {
      throw StateError('a stream without a direct /Length');
    }
    final dataStart = at + m.end;
    final dataEnd = dataStart + int.parse(length.group(1)!);
    final data = latin1.encode(raw.substring(dataStart, dataEnd));
    out.write(raw.substring(at, at + m.start));
    if (RegExp(r'/Filter\s*/FlateDecode').hasMatch(dict)) {
      final inflated = latin1.decode(zlib.decode(data));
      final plain = dict
          .replaceAll(RegExp(r'/Filter\s*/FlateDecode'), '')
          .replaceAll(RegExp(r'/Length\s+\d+'), '/Length ${inflated.length}');
      out
        ..write('<<$plain>>\nstream\n')
        ..write(inflated);
    } else {
      out
        ..write('<<$dict>>\nstream\n')
        ..write(latin1.decode(data));
    }
    at = dataEnd;
  }
  out.write(raw.substring(at));
  return Uint8List.fromList(latin1.encode(out.toString()));
}
