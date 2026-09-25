/// A small OpenXML (.xlsx) writer (Phase 7 Slice 4; D-298, `ARCHITECTURE.md` §51.5).
///
/// Its whole job is packaging: the workbook and package structure, worksheets, cells,
/// styles, number and date formats, frozen panes, auto-filters, relationships, content
/// types, and ZIP serialisation over `package:archive`.
///
/// **It knows nothing about money or finance.** A numeric cell is handed an exact decimal
/// literal, already written by whoever built the document, and is stored as that literal
/// text in the sheet XML. The writer never parses it into a `double`, never adds two
/// cells, and **cannot write a formula**: there is no formula cell type at all, so a
/// workbook it produces is values only (D-294). What Excel does with a number once it
/// opens the file is Excel's; nothing in the file asks it to calculate anything.
///
/// Output is deterministic — fixed ZIP timestamps, fixed entry order — so the same model
/// always produces the same bytes, which is what lets a test pin a workbook down.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The cell styles the reports use. Their order is the `cellXfs` order in styles.xml.
enum XlsxStyle {
  plain,
  bold,

  /// A column heading: bold on a light fill.
  header,

  /// Rupees and paise, conventional grouping (D-294): `₹1,234,567.89` / `-₹1,234.00`.
  money,
  moneyBold,

  /// A fraction shown as a percentage to two places: 0.5653 → 56.53%.
  percent,
  percentBold,

  /// A calendar date: 19 Sep 2026.
  date,

  /// The document title.
  title,

  /// A note or statement of basis.
  caption,
}

/// One cell. There is deliberately no formula cell.
sealed class XlsxCell {
  const XlsxCell(this.style);
  final XlsxStyle style;

  const factory XlsxCell.text(String value, {XlsxStyle style}) = XlsxText;
  factory XlsxCell.number(String literal, {XlsxStyle style}) = XlsxNumber;
  const factory XlsxCell.date(int year, int month, int day, {XlsxStyle style}) =
      XlsxDate;
  const factory XlsxCell.blank() = XlsxBlank;
}

final class XlsxText extends XlsxCell {
  const XlsxText(this.value, {XlsxStyle style = XlsxStyle.plain})
    : super(style);
  final String value;
}

/// A numeric cell holding an exact decimal literal, e.g. `-12345.67`.
///
/// The literal is validated and kept as text; it is never turned into a floating point
/// number here.
final class XlsxNumber extends XlsxCell {
  XlsxNumber(this.literal, {XlsxStyle style = XlsxStyle.plain}) : super(style) {
    if (!_decimal.hasMatch(literal)) {
      throw ArgumentError.value(literal, 'literal', 'is not a decimal literal');
    }
  }

  static final _decimal = RegExp(r'^-?(0|[1-9][0-9]*)(\.[0-9]+)?$');

  final String literal;
}

final class XlsxDate extends XlsxCell {
  const XlsxDate(
    this.year,
    this.month,
    this.day, {
    XlsxStyle style = XlsxStyle.date,
  }) : super(style);

  final int year;
  final int month;
  final int day;

  /// Excel's serial day number (1900 date system; day 0 is 30 Dec 1899). A calendar
  /// conversion in whole days — UTC is used as a calendar, never as an instant.
  int get serial => DateTime.utc(
    year,
    month,
    day,
  ).difference(DateTime.utc(1899, 12, 30)).inDays;
}

final class XlsxBlank extends XlsxCell {
  const XlsxBlank() : super(XlsxStyle.plain);
}

/// One worksheet.
final class XlsxSheet {
  XlsxSheet({
    required this.name,
    required this.rows,
    this.columnWidths = const [],
    this.freezeRows = 0,
    this.autoFilter,
  }) {
    if (!validName(name)) {
      throw ArgumentError.value(name, 'name', 'is not a valid sheet name');
    }
  }

  /// Excel's rules: 1–31 characters, none of `[]:*?/\`, and not starting or ending with
  /// an apostrophe.
  static bool validName(String name) =>
      name.isNotEmpty &&
      name.length <= 31 &&
      !RegExp(r"[\[\]:*?/\\]").hasMatch(name) &&
      !name.startsWith("'") &&
      !name.endsWith("'");

  final String name;
  final List<List<XlsxCell>> rows;

  /// Column widths in characters, from column A.
  final List<double> columnWidths;

  /// Rows above this line stay visible while scrolling (0: no freeze).
  final int freezeRows;

  /// An auto-filter over a table, as zero-based inclusive coordinates.
  final ({int firstRow, int lastRow, int firstColumn, int lastColumn})?
  autoFilter;
}

/// A workbook: its sheets, in order.
final class XlsxWorkbook {
  XlsxWorkbook({required this.sheets, this.title}) {
    if (sheets.isEmpty) throw ArgumentError('a workbook needs a sheet');
    final names = sheets.map((s) => s.name.toLowerCase()).toSet();
    if (names.length != sheets.length) {
      throw ArgumentError('sheet names must be unique');
    }
  }

  final List<XlsxSheet> sheets;
  final String? title;

  /// The `.xlsx` bytes.
  Uint8List encode() {
    final archive = Archive();
    void add(String path, String xml) {
      final bytes = utf8.encode(xml);
      archive.addFile(
        ArchiveFile(path, bytes.length, bytes)..lastModTime = _fixedModTime,
      );
    }

    add('[Content_Types].xml', _contentTypes());
    add('_rels/.rels', _rootRels);
    add('docProps/core.xml', _core());
    add('xl/workbook.xml', _workbook());
    add('xl/_rels/workbook.xml.rels', _workbookRels());
    add('xl/styles.xml', _styles);
    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i]));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  // 1 Jan 2000 00:00 in DOS time: a fixed stamp, so equal models give equal bytes.
  static const _fixedModTime = (20 << 25) | (1 << 21) | (1 << 16);

  static const _xmlHeader =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

  String _contentTypes() {
    final b = StringBuffer(_xmlHeader)
      ..write(
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" '
        'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/'
        'vnd.openxmlformats-package.core-properties+xml"/>',
      );
    for (var i = 0; i < sheets.length; i++) {
      b.write(
        '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
        'ContentType="application/'
        'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
    }
    b.write('</Types>');
    return b.toString();
  }

  static const _rootRels =
      '$_xmlHeader'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/'
      'package/2006/relationships/metadata/core-properties" '
      'Target="docProps/core.xml"/>'
      '</Relationships>';

  /// Only a title. No author, no creation time: a workbook says nothing about who or
  /// which device made it beyond what its visible header states (§51.8).
  String _core() =>
      '$_xmlHeader'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/'
      'metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '${title == null ? '' : '<dc:title>${_escape(title!)}</dc:title>'}'
      '</cp:coreProperties>';

  String _workbook() {
    final b = StringBuffer(_xmlHeader)
      ..write(
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>',
      );
    for (var i = 0; i < sheets.length; i++) {
      b.write(
        '<sheet name="${_escape(sheets[i].name)}" sheetId="${i + 1}" '
        'r:id="rId${i + 1}"/>',
      );
    }
    b.write('</sheets>');
    final filters = [
      for (var i = 0; i < sheets.length; i++)
        if (sheets[i].autoFilter case final f?)
          '<definedName name="_xlnm._FilterDatabase" localSheetId="$i" '
              'hidden="1">${_quoteSheet(sheets[i].name)}!'
              '${_absoluteRef(f.firstRow, f.firstColumn)}:'
              '${_absoluteRef(f.lastRow, f.lastColumn)}</definedName>',
    ];
    if (filters.isNotEmpty) {
      b.write('<definedNames>${filters.join()}</definedNames>');
    }
    b.write('</workbook>');
    return b.toString();
  }

  String _workbookRels() {
    final b = StringBuffer(_xmlHeader)
      ..write(
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
        'relationships">',
      );
    for (var i = 0; i < sheets.length; i++) {
      b.write(
        '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/'
        'officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet${i + 1}.xml"/>',
      );
    }
    b.write(
      '<Relationship Id="rId${sheets.length + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/'
      'styles" Target="styles.xml"/></Relationships>',
    );
    return b.toString();
  }

  /// Number formats: 164 money, 165 date. 10 is Excel's built-in `0.00%`.
  static const moneyFormatCode = '"₹"#,##0.00;-"₹"#,##0.00';
  static const dateFormatCode = 'dd mmm yyyy';

  static final _styles = () {
    // (numFmtId, fontId, fillId) per XlsxStyle, in enum order.
    const xfs = {
      XlsxStyle.plain: (0, 0, 0),
      XlsxStyle.bold: (0, 1, 0),
      XlsxStyle.header: (0, 1, 2),
      XlsxStyle.money: (164, 0, 0),
      XlsxStyle.moneyBold: (164, 1, 0),
      XlsxStyle.percent: (10, 0, 0),
      XlsxStyle.percentBold: (10, 1, 0),
      XlsxStyle.date: (165, 0, 0),
      XlsxStyle.title: (0, 2, 0),
      XlsxStyle.caption: (0, 3, 0),
    };
    final b = StringBuffer(_xmlHeader)
      ..write(
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="2">'
        '<numFmt numFmtId="164" formatCode="${_escape(moneyFormatCode)}"/>'
        '<numFmt numFmtId="165" formatCode="${_escape(dateFormatCode)}"/>'
        '</numFmts>'
        '<fonts count="4">'
        '<font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="14"/><name val="Calibri"/></font>'
        '<font><i/><sz val="10"/><name val="Calibri"/></font>'
        '</fonts>'
        '<fills count="3">'
        '<fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFEFEBE3"/>'
        '<bgColor indexed="64"/></patternFill></fill>'
        '</fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
        '</border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
        'borderId="0"/></cellStyleXfs>'
        '<cellXfs count="${XlsxStyle.values.length}">',
      );
    for (final style in XlsxStyle.values) {
      final (numFmt, font, fill) = xfs[style]!;
      b.write(
        '<xf numFmtId="$numFmt" fontId="$font" fillId="$fill" borderId="0" '
        'xfId="0"${numFmt == 0 ? '' : ' applyNumberFormat="1"'}'
        '${font == 0 ? '' : ' applyFont="1"'}'
        '${fill == 0 ? '' : ' applyFill="1"'}/>',
      );
    }
    b.write(
      '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" '
      'builtinId="0"/></cellStyles></styleSheet>',
    );
    return b.toString();
  }();

  String _sheet(XlsxSheet sheet) {
    final b = StringBuffer(_xmlHeader)
      ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
      );
    if (sheet.freezeRows > 0) {
      b.write(
        '<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="${sheet.freezeRows}" '
        'topLeftCell="${_ref(sheet.freezeRows, 0)}" activePane="bottomLeft" '
        'state="frozen"/></sheetView></sheetViews>',
      );
    }
    if (sheet.columnWidths.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < sheet.columnWidths.length; i++) {
        b.write(
          '<col min="${i + 1}" max="${i + 1}" '
          'width="${sheet.columnWidths[i]}" customWidth="1"/>',
        );
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < sheet.rows.length; r++) {
      b.write('<row r="${r + 1}">');
      final row = sheet.rows[r];
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        final at = 'r="${_ref(r, c)}" s="${cell.style.index}"';
        switch (cell) {
          case XlsxText(:final value):
            b.write(
              '<c $at t="inlineStr"><is><t xml:space="preserve">'
              '${_escape(value)}</t></is></c>',
            );
          case XlsxNumber(:final literal):
            b.write('<c $at><v>$literal</v></c>');
          case XlsxDate():
            b.write('<c $at><v>${cell.serial}</v></c>');
          case XlsxBlank():
            if (cell.style != XlsxStyle.plain) b.write('<c $at/>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (sheet.autoFilter case final f?) {
      b.write(
        '<autoFilter ref="${_ref(f.firstRow, f.firstColumn)}:'
        '${_ref(f.lastRow, f.lastColumn)}"/>',
      );
    }
    b.write('</worksheet>');
    return b.toString();
  }

  /// A1-style reference for zero-based row and column.
  static String _ref(int row, int column) => '${columnName(column)}${row + 1}';

  static String _absoluteRef(int row, int column) =>
      '\$${columnName(column)}\$${row + 1}';

  /// Zero-based column index to its letters: 0 → A, 25 → Z, 26 → AA.
  static String columnName(int column) {
    var n = column + 1;
    var name = '';
    while (n > 0) {
      final rem = (n - 1) % 26;
      name = String.fromCharCode(65 + rem) + name;
      n = (n - 1) ~/ 26;
    }
    return name;
  }

  static String _quoteSheet(String name) =>
      "'${_escape(name.replaceAll("'", "''"))}'";

  /// XML text escaping, with characters XML 1.0 cannot carry removed.
  static String _escape(String s) => s
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
