/// A widget test that tears its own subscriptions down.
///
/// Since Slice 10 the revenue detail surface reads its sync state from a **Drift stream**
/// (D-131), so a rendered panel holds a live query subscription. Drift schedules a
/// zero-duration timer when one is cancelled, and Flutter checks for pending timers at
/// the end of the test **body** — before `addTearDown` runs. A test that renders the panel
/// and stops therefore fails with *"A Timer is still pending"*, which the runner reports
/// as `did not complete` and reads like a hang.
///
/// The disposal has to happen inside the body, and a per-test call is a thing to forget.
/// One wrapper does it for every test that uses it, which is why this lives here rather
/// than being copied into each suite.
///
/// Named `ui_harness` rather than `ui_test`: the runner treats every `*_test.dart` file as
/// a suite, and a support file with no `main()` fails to load.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

@isTest
void uiTest(
  String description,
  Future<void> Function(WidgetTester tester) body, {
  bool skip = false,
}) => testWidgets(description, (tester) async {
  await body(tester);
  // An empty tree disposes the ProviderScope, which cancels the stream; the pump lets
  // Drift's cancellation timer fire before the invariant check runs.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}, skip: skip);
