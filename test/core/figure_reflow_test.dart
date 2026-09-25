/// The layout that gives way so money never has to (D-286).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/design/components/figure_reflow.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';
import 'package:krishna_mis/domain/value_objects/money.dart';

import '../support/money_layout.dart';

void main() {
  setUpAll(loadRealFonts);

  Future<RenderFigureReflow> pumpReflow(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
    FigureReflowOrder order = FigureReflowOrder.leadFirst,
  }) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: FigureReflow(
                lead: const Text('NET SALES', key: Key('lead')),
                figure: MoneyText(
                  Money.fromPaise(16638300),
                  key: const Key('figure'),
                  style: const TextStyle(fontSize: 26),
                ),
                order: order,
              ),
            ),
          ),
        ),
      ),
    );
    return tester.renderObject<RenderFigureReflow>(find.byType(FigureReflow));
  }

  testWidgets('side by side while the whole figure fits', (tester) async {
    final reflow = await pumpReflow(tester, width: 350);
    expect(reflow.isSideBySide, isTrue);
    final lead = tester.getRect(find.byKey(const Key('lead')));
    final figure = tester.getRect(find.byKey(const Key('figure')));
    expect(figure.left, greaterThan(lead.right));
    expect(figure.right, closeTo(350, 0.5));
  });

  testWidgets('stacked, at full size, when it does not — and taller', (
    tester,
  ) async {
    final side = await pumpReflow(tester, width: 350);
    final sideHeight = side.size.height;
    final reflow = await pumpReflow(tester, width: 200, textScale: 1.6);
    expect(reflow.isSideBySide, isFalse);
    expect(reflow.size.height, greaterThan(sideHeight));
    final lead = tester.getRect(find.byKey(const Key('lead')));
    final figure = tester.getRect(find.byKey(const Key('figure')));
    expect(figure.top, greaterThanOrEqualTo(lead.bottom));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(const Key('figure')),
        matching: find.byType(RichText),
      ),
    );
    expect(paragraph.textScaler.scale(10), closeTo(16, 0.01));
  });

  testWidgets('a bar goes below its figure when the figure comes first', (
    tester,
  ) async {
    await pumpReflow(tester, width: 150, order: FigureReflowOrder.figureFirst);
    final lead = tester.getRect(find.byKey(const Key('lead')));
    final figure = tester.getRect(find.byKey(const Key('figure')));
    expect(lead.top, greaterThanOrEqualTo(figure.bottom));
  });

  group('the last resort: a break between digit groups', () {
    test('break opportunities follow commas only, and never split a sign', () {
      final shown = breakableAtDigitGroups('-₹12,36,420.00');
      expect(withoutBreakMarks(shown), '-₹12,36,420.00');
      expect(shown.indexOf('\u200B'), shown.indexOf(',') + 1);
      expect(shown.contains('-\u2060₹'), isTrue);
      expect(shown.contains('.\u200B'), isFalse);
    });

    testWidgets('a figure wider than its whole line breaks after a comma', (
      tester,
    ) async {
      await pumpReflow(tester, width: 220, textScale: 2);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(const Key('figure')),
          matching: find.byType(RichText),
        ),
      );
      final text = paragraph.text.toPlainText();
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      final tops = {for (final b in boxes) b.top.round()};
      expect(tops.length, greaterThan(1), reason: 'the figure did not break');
      // Every line after the first starts right after a break mark following a comma.
      for (var i = 1; i < text.length; i++) {
        final here = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1),
        );
        final before = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: i - 1, extentOffset: i),
        );
        if (here.isEmpty || before.isEmpty) continue;
        if (here.first.top > before.first.top + 1 && text[i] != '\u200B') {
          final visibleBefore = withoutBreakMarks(text.substring(0, i));
          expect(
            visibleBefore.endsWith(','),
            isTrue,
            reason: 'a line starts inside a digit group after "$visibleBefore"',
          );
        }
      }
      expect(tester.takeException(), isNull);
      expectMoneyWholeAndUnshrunk(tester, 'the break', atLeast: 0);
    });
  });

  // D-286 as clarified by the project lead (2026-09-25): an exact figure stays on one
  // line whenever the COMPLETE figure fits on the actual empty line available to it.
  // Measured at the real width, not approximated from the screen.
  group('the empty line decides, measured exactly', () {
    RenderParagraph figureParagraph(WidgetTester tester) =>
        tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byKey(const Key('figure')),
            matching: find.byType(RichText),
          ),
        );

    bool isBroken(RenderParagraph p) =>
        p.size.height > p.getMaxIntrinsicHeight(double.infinity) + 0.5;

    Future<double> wholeWidthAt(WidgetTester tester, double textScale) async {
      await pumpReflow(tester, width: 1000, textScale: textScale);
      return figureParagraph(tester).getMaxIntrinsicWidth(double.infinity);
    }

    testWidgets(
      'a line exactly as wide as the whole figure keeps it on one line',
      (tester) async {
        final whole = await wholeWidthAt(tester, 2);
        final reflow = await pumpReflow(
          tester,
          width: whole.ceilToDouble(),
          textScale: 2,
        );
        expect(
          reflow.isSideBySide,
          isFalse,
          reason: 'the label needs the room',
        );
        final p = figureParagraph(tester);
        expect(
          isBroken(p),
          isFalse,
          reason: 'the figure fits its empty line and must not break',
        );
        expect(emptyLineOf(p), same(reflow));
        expect(p.constraints.maxWidth, closeTo(reflow.size.width, 0.5));
        expect(tester.takeException(), isNull);
        expectMoneyWholeAndUnshrunk(tester, 'an exact empty line');
      },
    );

    testWidgets(
      'a line narrower than the whole figure lets it break, after a comma only',
      (tester) async {
        final whole = await wholeWidthAt(tester, 2);
        await pumpReflow(
          tester,
          width: whole.floorToDouble() - 2,
          textScale: 2,
        );
        final p = figureParagraph(tester);
        expect(isBroken(p), isTrue, reason: 'it cannot fit and must break');
        expect(tester.takeException(), isNull);
        expectMoneyWholeAndUnshrunk(tester, 'a line too narrow');
      },
    );
  });
}
