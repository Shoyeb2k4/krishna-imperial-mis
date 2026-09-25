/// Money on screen is laid out whole, at the reader's own text size (D-286).
///
/// A figure must not be ellipsised, clipped, wrapped, or shrunk to fit. The layout gives
/// way instead: it reflows, and the row grows taller. These checks read what was actually
/// painted, so they catch every mechanism rather than the one somebody thought of —
/// a `FittedBox`, a `Transform.scale`, a clamped text scale, or a paragraph laid out
/// narrower than its own text.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/core/design/components/figure_reflow.dart';
import 'package:krishna_mis/core/design/components/money_text.dart';

/// A paragraph that is nothing but an amount: `₹1,23,642.00`, `-₹500`, `+₹1,200.00`,
/// `(₹500.00)`.
final RegExp _pureFigure = RegExp(r'^[+\-−(]?₹[\d,]+(\.\d{2})?\)?$');

/// Every paragraph on screen that states an amount in rupees.
List<RenderParagraph> moneyParagraphs(WidgetTester tester) => [
  for (final element in find.byType(RichText).evaluate())
    if (element.renderObject case final RenderParagraph p
        when p.attached && p.text.toPlainText().contains('₹'))
      p,
];

/// Asserts every amount on screen is whole and unshrunk, and returns how many were
/// checked so a caller can refuse a vacuous pass.
int expectMoneyWholeAndUnshrunk(
  WidgetTester tester,
  String where, {
  int atLeast = 1,
}) {
  final root = tester.binding.renderViews.first.child!;
  final expectedScale = MediaQuery.textScalerOf(
    tester.element(find.byType(Directionality).first),
  ).scale(100);
  var checked = 0;
  for (final p in moneyParagraphs(tester)) {
    final text = withoutBreakMarks(p.text.toPlainText());
    final what = '"$text" at $where';

    // Not shrunk by an ancestor: the paragraph is painted at scale 1.
    // Measured on x and y: a 4×4 transform's max-axis scale includes z, which a 2-D
    // shrink leaves at 1 and would hide.
    final probe = MatrixUtils.transformRect(
      p.getTransformTo(root),
      Offset.zero & const Size(100, 100),
    );
    final scale = math.min(probe.width, probe.height) / 100;
    expect(
      scale,
      closeTo(1, 0.001),
      reason: '$what is drawn at ${scale.toStringAsFixed(3)}×: shrunk to fit',
    );

    // Not given a smaller text scale than the reader chose.
    expect(
      p.textScaler.scale(100),
      closeTo(expectedScale, 0.01),
      reason: '$what does not follow the system text scale',
    );

    // Not clipped, ellipsised or cut short.
    expect(p.didExceedMaxLines, isFalse, reason: '$what is cut short');
    if (_pureFigure.hasMatch(text.trim())) {
      final oneLine = p.getMaxIntrinsicWidth(double.infinity);
      final lineHeight = p.getMaxIntrinsicHeight(double.infinity);
      final broken = p.size.height > lineHeight + 0.5;
      if (!broken) {
        expect(
          p.size.width + 0.5,
          greaterThanOrEqualTo(oneLine),
          reason:
              '$what is laid out narrower than its own text: '
              '${p.size.width.toStringAsFixed(1)} of ${oneLine.toStringAsFixed(1)}',
        );
      } else {
        // The last resort (D-286, clarified 2026-09-25): a figure may break only when
        // the COMPLETE figure is wider than the actual empty line available to it —
        // the full width of the FigureReflow line it has been stacked onto — and then
        // only between digit groups, at full size. The line is measured from the real
        // layout, never approximated from the screen width.
        final line = emptyLineOf(p);
        expect(
          line,
          isNotNull,
          reason:
              '$what is broken outside a line of its own: only a figure a '
              'FigureReflow has stacked onto an empty line may break',
        );
        expect(
          line!.isSideBySide,
          isFalse,
          reason: '$what is broken while it still shares its line with a label',
        );
        expect(
          p.constraints.maxWidth,
          closeTo(line.size.width, 0.5),
          reason:
              '$what is broken inside ${p.constraints.maxWidth.toStringAsFixed(1)} '
              'of an empty line ${line.size.width.toStringAsFixed(1)} wide: it was '
              'not given the whole line',
        );
        expect(
          oneLine,
          greaterThan(line.size.width + 0.5),
          reason:
              '$what (${oneLine.toStringAsFixed(1)} wide) is broken although it '
              'fits on its empty line (${line.size.width.toStringAsFixed(1)})',
        );
        // Each new line begins after a comma: never inside a digit group.
        final shown = p.text.toPlainText();
        for (var i = 1; i < shown.length; i++) {
          if (shown[i] == '\u200B') continue;
          final here = p.getBoxesForSelection(
            TextSelection(baseOffset: i, extentOffset: i + 1),
          );
          final before = p.getBoxesForSelection(
            TextSelection(baseOffset: i - 1, extentOffset: i),
          );
          if (here.isEmpty || before.isEmpty) continue;
          if (here.first.top > before.first.top + 1) {
            final read = withoutBreakMarks(shown.substring(0, i));
            expect(
              read.endsWith(','),
              isTrue,
              reason: '$what breaks inside a digit group, after "$read"',
            );
          }
        }
        // Every glyph lands inside the line: no digit group runs past its edge.
        final boxes = p.getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: p.text.toPlainText().length,
          ),
        );
        final right = boxes.fold<double>(0, (m, b) => math.max(m, b.right));
        final left = boxes.fold<double>(
          p.size.width,
          (m, b) => math.min(m, b.left),
        );
        expect(
          left >= -0.5 && right <= p.size.width + 0.5,
          isTrue,
          reason:
              '$what runs past its line: glyphs span $left–$right of '
              '${p.size.width}',
        );
      }
      // Inside the screen: a figure pushed off the edge is a figure nobody can read.
      final rect = MatrixUtils.transformRect(
        p.getTransformTo(root),
        Offset.zero & Size(broken ? p.size.width : oneLine, p.size.height),
      );
      expect(
        rect.left >= -0.5 && rect.right <= root.size.width + 0.5,
        isTrue,
        reason: '$what runs off the screen: $rect of ${root.size}',
      );
    }
    checked++;
  }
  expect(
    checked,
    greaterThanOrEqualTo(atLeast),
    reason: 'too few amounts checked at $where',
  );
  return checked;
}

/// The empty line [p] may occupy: the nearest [RenderFigureReflow] of which [p] lies
/// inside the **figure** child — never inside the lead. Null when the figure has no
/// such line, which means it was given a slot rather than a line of its own.
RenderFigureReflow? emptyLineOf(RenderParagraph p) {
  RenderObject child = p;
  var parent = p.parent;
  while (parent != null) {
    if (parent is RenderFigureReflow) {
      return identical(child, parent.lastChild) ? parent : null;
    }
    child = parent;
    parent = parent.parent;
  }
  return null;
}

/// No layout error — an overflow is a figure drawn over its neighbour.
void expectNoLayoutError(WidgetTester tester, String where) {
  final error = tester.takeException();
  expect(
    error,
    isNull,
    reason: '$where: ${error is FlutterError ? error.toStringDeep() : error}',
  );
}

/// Loads Roboto — the Android system face the phone theme asks for — so a layout test
/// measures real glyph widths.
///
/// The test framework's default face draws every glyph a full em wide, which makes a
/// figure nearly twice as wide as it is on a phone. A check that money fits at 2.0× on
/// 320dp means nothing against glyphs no phone draws. The faces come from the Flutter
/// SDK's own material fonts, so nothing is downloaded and nothing is added to the app.
///
/// The SDK ships these as `Roboto-Regular.ttf` and so on. They are found by comparing
/// names case-insensitively, because a hard-coded `roboto-regular.ttf` worked only on
/// Windows' case-insensitive filesystem and failed in setUpAll on Linux — which skipped
/// every test in the six layout suites (cloud/CI portability).
Future<void> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  expect(root, isNotNull, reason: 'FLUTTER_ROOT is not set for this test run');
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  expect(
    dir.existsSync(),
    isTrue,
    reason: 'missing ${dir.path} — run `flutter precache` on a fresh SDK',
  );
  final files = dir.listSync().whereType<File>().toList();
  final loader = FontLoader('Roboto');
  for (final face in const ['regular', 'medium', 'bold']) {
    final wanted = 'roboto-$face.ttf';
    final matches = [
      for (final file in files)
        if (file.uri.pathSegments.last.toLowerCase() == wanted) file,
    ];
    expect(
      matches,
      hasLength(1),
      reason: 'expected exactly one $wanted in ${dir.path}',
    );
    final bytes = matches.single.readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Scrolls every vertical list on screen from top to bottom, checking every amount at
/// each stop: a lazy list builds only what is near the viewport, so a check at one
/// scroll position alone misses the rest.
Future<int> expectEveryAmountWholeWhileScrolling(
  WidgetTester tester,
  String where,
) async {
  var checked = expectMoneyWholeAndUnshrunk(tester, '$where, top', atLeast: 0);
  final states = tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where((s) => s.position.axis == Axis.vertical)
      .toList();
  for (final state in states) {
    if (!state.mounted) continue;
    final position = state.position;
    final step = position.viewportDimension * 0.6;
    for (var stop = 1; stop < 60; stop++) {
      if (!state.mounted || position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        math.min(position.pixels + step, position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      expectNoLayoutError(tester, '$where, stop $stop');
      checked += expectMoneyWholeAndUnshrunk(
        tester,
        '$where, stop $stop',
        atLeast: 0,
      );
    }
    if (state.mounted) position.jumpTo(0);
    await tester.pumpAndSettle();
  }
  expect(checked, greaterThan(0), reason: 'no amount checked at $where');
  return checked;
}

/// Scrolls the page's vertical lists until [finder] has been built: at 2.0× a phone's
/// header can fill the screen, and a lazy list builds nothing below it.
Future<void> scrollUntilBuilt(WidgetTester tester, Finder finder) async {
  for (var stop = 0; stop < 80 && finder.evaluate().isEmpty; stop++) {
    final states = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((s) => s.position.axis == Axis.vertical)
        .toList();
    var moved = false;
    for (final state in states) {
      final position = state.position;
      if (position.pixels < position.maxScrollExtent) {
        position.jumpTo(
          math.min(
            position.pixels + position.viewportDimension * 0.5,
            position.maxScrollExtent,
          ),
        );
        moved = true;
        break;
      }
    }
    await tester.pumpAndSettle();
    if (!moved) break;
  }
  expect(finder, findsWidgets, reason: 'never built: $finder');
}

/// A [Text] showing [figure] as a person reads it. `MoneyText` carries invisible break
/// marks between digit groups (D-286), so an exact `find.text` on an amount no longer
/// matches it.
Finder findFigure(String figure) => find.byWidgetPredicate(
  (w) => w is Text && w.data != null && withoutBreakMarks(w.data!) == figure,
  description: 'the figure "$figure"',
);
