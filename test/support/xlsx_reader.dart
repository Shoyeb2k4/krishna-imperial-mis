/// Reads a generated `.xlsx` back, for the Phase 7 export tests (Slice 4).
///
/// It opens the ZIP and reads the sheet XML directly, so a test asserts what is actually
/// in the file a person would open — the part names, the stored cell values and their
/// styles — rather than what the writer was asked to write.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One cell as it is stored in the sheet XML.
final class StoredCell {
  const StoredCell({
    required this.ref,
    required this.style,
    this.type,
    this.value,
    this.text,
  });

  final String ref;
  final int style;

  /// `inlineStr` for text; null for a number or a date.
  final String? type;

  /// The `<v>` content, exactly as stored.
  final String? value;

  /// The inline string, unescaped.
  final String? text;

  bool get isNumber => type == null && value != null;

  @override
  String toString() => '$ref(s=$style, t=$type, v=$value, text=$text)';
}

final class StoredWorkbook {
  StoredWorkbook(Uint8List bytes) : archive = ZipDecoder().decodeBytes(bytes);

  final Archive archive;

  List<String> get partNames => [for (final f in archive.files) f.name];

  String part(String name) {
    final file = archive.findFile(name);
    if (file == null) throw StateError('no part $name');
    return utf8.decode(file.content as List<int>);
  }

  /// The sheet names, in workbook order.
  List<String> get sheetNames => [
    for (final m in RegExp(
      r'<sheet name="([^"]*)"',
    ).allMatches(part('xl/workbook.xml')))
      unescape(m.group(1)!),
  ];

  String sheetXml(String name) =>
      part('xl/worksheets/sheet${sheetNames.indexOf(name) + 1}.xml');

  /// Every stored cell of a sheet, keyed by its A1 reference.
  Map<String, StoredCell> cells(String sheet) {
    final xml = sheetXml(sheet);
    final out = <String, StoredCell>{};
    for (final m in RegExp(
      r'<c r="([A-Z]+[0-9]+)" s="([0-9]+)"( t="([a-zA-Z]+)")?(/>|>(.*?)</c>)',
    ).allMatches(xml)) {
      final body = m.group(6) ?? '';
      final v = RegExp(r'<v>([^<]*)</v>').firstMatch(body)?.group(1);
      final t = RegExp(r'<t[^>]*>([^<]*)</t>').firstMatch(body)?.group(1);
      out[m.group(1)!] = StoredCell(
        ref: m.group(1)!,
        style: int.parse(m.group(2)!),
        type: m.group(4),
        value: v,
        text: t == null ? null : unescape(t),
      );
    }
    return out;
  }

  /// The rows of a sheet as the text a reader sees: an inline string, or a stored value.
  List<List<String>> rows(String sheet) {
    final xml = sheetXml(sheet);
    final all = cells(sheet);
    return [
      for (final r in RegExp(r'<row r="([0-9]+)">(.*?)</row>').allMatches(xml))
        [
          for (final c in RegExp(
            r'<c r="([A-Z]+[0-9]+)"',
          ).allMatches(r.group(2)!))
            all[c.group(1)!]!.text ?? all[c.group(1)!]!.value ?? '',
        ],
    ];
  }

  /// Every stored text and value in the workbook, for leakage checks.
  String get allText => [
    for (final f in archive.files)
      if (f.isFile) utf8.decode(f.content as List<int>),
  ].join('\n');

  static String unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&');
}

/// True when every element opened in [xml] is closed in order — a cheap well-formedness
/// check that needs no XML parser dependency.
bool tagsBalance(String xml) {
  final stack = <String>[];
  final body = xml.replaceFirst(RegExp(r'^<\?xml[^>]*\?>\s*'), '');
  for (final m in RegExp(
    r'<(/?)([A-Za-z_][\w:.-]*)[^>]*?(/?)>',
  ).allMatches(body)) {
    final closing = m.group(1) == '/';
    final name = m.group(2)!;
    final selfClosing = m.group(3) == '/';
    if (selfClosing) continue;
    if (closing) {
      if (stack.isEmpty || stack.removeLast() != name) return false;
    } else {
      stack.add(name);
    }
  }
  return stack.isEmpty;
}
