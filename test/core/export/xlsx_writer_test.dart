/// The OpenXML writer packages cells and never calculates (Phase 7 Slice 4; D-294, D-298).
///
/// Every assertion opens the bytes the writer produced — the ZIP, the parts, the sheet
/// XML — rather than trusting the objects it was handed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/export/xlsx/xlsx_writer.dart';

import '../../support/xlsx_reader.dart';

XlsxWorkbook _book() => XlsxWorkbook(
  title: 'A & B <test>',
  sheets: [
    XlsxSheet(
      name: 'Summary',
      columnWidths: const [20, 14],
      rows: [
        [const XlsxCell.text('Heading', style: XlsxStyle.title)],
        [],
        [
          const XlsxCell.text('Amount'),
          XlsxCell.number('-1234.05', style: XlsxStyle.money),
        ],
        [const XlsxCell.text('Day'), const XlsxCell.date(2026, 9, 19)],
      ],
    ),
    XlsxSheet(
      name: 'Lines',
      freezeRows: 1,
      autoFilter: (firstRow: 0, lastRow: 2, firstColumn: 0, lastColumn: 1),
      rows: [
        [
          const XlsxCell.text('Name', style: XlsxStyle.header),
          const XlsxCell.text('Value', style: XlsxStyle.header),
        ],
        [
          const XlsxCell.text('Tom & "Jerry" <x>\u0001'),
          XlsxCell.number('0.5653', style: XlsxStyle.percent),
        ],
        [
          const XlsxCell.text('  kept spaces  '),
          XlsxCell.number('9007199254740.99', style: XlsxStyle.moneyBold),
        ],
      ],
    ),
  ],
);

void main() {
  final bytes = _book().encode();
  final stored = StoredWorkbook(bytes);

  group('the package', () {
    test('holds exactly the parts a workbook needs, in a fixed order', () {
      expect(stored.partNames, [
        '[Content_Types].xml',
        '_rels/.rels',
        'docProps/core.xml',
        'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels',
        'xl/styles.xml',
        'xl/worksheets/sheet1.xml',
        'xl/worksheets/sheet2.xml',
      ]);
    });

    test('every part is well-formed XML', () {
      for (final name in stored.partNames) {
        expect(tagsBalance(stored.part(name)), isTrue, reason: name);
        expect(stored.part(name), startsWith('<?xml version="1.0"'));
      }
    });

    test('declares every sheet and relates it to the workbook', () {
      final types = stored.part('[Content_Types].xml');
      final rels = stored.part('xl/_rels/workbook.xml.rels');
      for (final n in [1, 2]) {
        expect(types, contains('PartName="/xl/worksheets/sheet$n.xml"'));
        expect(rels, contains('Target="worksheets/sheet$n.xml"'));
      }
      expect(rels, contains('Target="styles.xml"'));
      expect(stored.sheetNames, ['Summary', 'Lines']);
    });

    test('the same workbook always gives the same bytes', () {
      expect(_book().encode(), bytes);
    });

    test('says nothing about who or which device made it', () {
      final core = stored.part('docProps/core.xml');
      expect(core, contains('<dc:title>A &amp; B &lt;test&gt;</dc:title>'));
      for (final absent in [
        'creator',
        'lastModifiedBy',
        'created',
        'modified',
      ]) {
        expect(core, isNot(contains(absent)));
      }
    });
  });

  group('cells', () {
    test('a number is stored as its exact literal, unparsed', () {
      final summary = stored.cells('Summary');
      expect(summary['B3']!.isNumber, isTrue);
      expect(summary['B3']!.value, '-1234.05');
      final lines = stored.cells('Lines');
      expect(lines['B2']!.value, '0.5653');
      expect(lines['B3']!.value, '9007199254740.99');
    });

    test(
      'text is inline, escaped, whitespace kept, and XML-illegal bytes removed',
      () {
        final lines = stored.cells('Lines');
        expect(lines['A2']!.type, 'inlineStr');
        expect(lines['A2']!.text, 'Tom & "Jerry" <x>');
        expect(lines['A3']!.text, '  kept spaces  ');
        expect(stored.sheetXml('Lines'), contains('xml:space="preserve"'));
      },
    );

    test('a date is its serial day, formatted as a date', () {
      expect(const XlsxDate(1900, 3, 1).serial, 61);
      expect(const XlsxDate(2000, 1, 1).serial, 36526);
      final day = stored.cells('Summary')['B4']!;
      expect(day.value, '46284');
      expect(day.style, XlsxStyle.date.index);
    });

    test('there is no formula anywhere, because there is no formula cell', () {
      for (final name in stored.partNames) {
        expect(stored.part(name), isNot(contains('<f>')), reason: name);
        expect(stored.part(name), isNot(contains('<f ')), reason: name);
      }
    });

    test('anything that is not a plain decimal literal is refused', () {
      for (final bad in [
        '',
        '1e5',
        '1,234.00',
        ' 12',
        '12 ',
        '01',
        '1.',
        '.5',
        '+1',
        '--1',
        'NaN',
        'Infinity',
        '₹12',
      ]) {
        expect(() => XlsxCell.number(bad), throwsArgumentError, reason: bad);
      }
      for (final good in ['0', '-0.01', '12', '1234567.89', '0.0000']) {
        expect((XlsxCell.number(good) as XlsxNumber).literal, good);
      }
    });
  });

  group('styles', () {
    final styles = stored.part('xl/styles.xml');

    test('money is conventional rupee grouping, from D-294', () {
      expect(XlsxWorkbook.moneyFormatCode, '"₹"#,##0.00;-"₹"#,##0.00');
      expect(
        styles,
        contains(
          '<numFmt numFmtId="164" '
          'formatCode="&quot;₹&quot;#,##0.00;-&quot;₹&quot;#,##0.00"/>',
        ),
      );
      expect(
        styles,
        contains('<numFmt numFmtId="165" formatCode="dd mmm yyyy"/>'),
      );
    });

    test('there is one cell format per style, in the enum order', () {
      expect(styles, contains('<cellXfs count="${XlsxStyle.values.length}">'));
      final xfs = RegExp(
        r'<cellXfs[^>]*>(.*?)</cellXfs>',
      ).firstMatch(styles)!.group(1)!;
      final numFmts = [
        for (final m in RegExp(r'<xf numFmtId="([0-9]+)"').allMatches(xfs))
          int.parse(m.group(1)!),
      ];
      expect(numFmts, hasLength(XlsxStyle.values.length));
      expect(numFmts[XlsxStyle.money.index], 164);
      expect(numFmts[XlsxStyle.moneyBold.index], 164);
      expect(numFmts[XlsxStyle.percent.index], 10);
      expect(numFmts[XlsxStyle.date.index], 165);
      expect(numFmts[XlsxStyle.plain.index], 0);
    });
  });

  group('panes and filters', () {
    test('a frozen header row', () {
      final xml = stored.sheetXml('Lines');
      expect(
        xml,
        contains(
          '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" '
          'state="frozen"/>',
        ),
      );
      expect(stored.sheetXml('Summary'), isNot(contains('<pane')));
    });

    test('an auto-filter, and the hidden name Excel keeps for it', () {
      expect(stored.sheetXml('Lines'), contains('<autoFilter ref="A1:B3"/>'));
      expect(
        stored.part('xl/workbook.xml'),
        contains(
          '<definedName name="_xlnm._FilterDatabase" localSheetId="1" '
          'hidden="1">\'Lines\'!\$A\$1:\$B\$3</definedName>',
        ),
      );
    });

    test('column widths are written', () {
      expect(
        stored.sheetXml('Summary'),
        contains('<col min="1" max="1" width="20.0" customWidth="1"/>'),
      );
    });
  });

  group('names', () {
    test('columns are lettered as Excel letters them', () {
      expect(XlsxWorkbook.columnName(0), 'A');
      expect(XlsxWorkbook.columnName(25), 'Z');
      expect(XlsxWorkbook.columnName(26), 'AA');
      expect(XlsxWorkbook.columnName(701), 'ZZ');
      expect(XlsxWorkbook.columnName(702), 'AAA');
    });

    test('a sheet name Excel would refuse is refused here first', () {
      for (final bad in [
        '',
        'a' * 32,
        'a/b',
        'a:b',
        'a[b]',
        'a*b',
        'a?b',
        r'a\b',
        "'quoted'",
      ]) {
        expect(
          () => XlsxSheet(name: bad, rows: const []),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('two sheets may not share a name, whatever the case', () {
      expect(
        () => XlsxWorkbook(
          sheets: [
            XlsxSheet(name: 'Lines', rows: const []),
            XlsxSheet(name: 'LINES', rows: const []),
          ],
        ),
        throwsArgumentError,
      );
      expect(() => XlsxWorkbook(sheets: const []), throwsArgumentError);
    });
  });
}
