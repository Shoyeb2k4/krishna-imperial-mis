// The host suite's one global test configuration (Phase 8 Slice 5, D-325).
//
// `flutter test` runs `testExecutable` around every test file under `test/`
// (the nearest `flutter_test_config.dart` wins, and there is no other one).
// It makes a missed tap fatal: a `tap()`, `drag()` or `longPress()` whose
// finder resolves to a widget that would not receive the pointer is a test
// failure, never a warning scrolled past in the log (D-075).
//
// It is enforced per test rather than set once, so no test can change it for
// the tests after it:
//
// * before every test the flag is set fatal again, whatever an earlier test
//   left behind — test order, sharding and concurrency cannot alter the policy;
// * after every test it must still be fatal. A test that turns it off and does
//   not restore it fails, by name, instead of silently weakening the rest of
//   its file.
//
// There is no switch for a whole file or a whole test. A tap that is meant to
// miss says so at the call, with `warnIfMissed: false` and a
// `// missed-tap opt-out:` comment giving the reason; the guard in
// `test/app/missed_tap_policy_test.dart` holds that rule.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;

  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);

  tearDown(() {
    if (WidgetController.hitTestWarningShouldBeFatal) return;
    // Restore first, so one leak cannot weaken the tests that follow.
    WidgetController.hitTestWarningShouldBeFatal = true;
    fail(
      'This test left WidgetController.hitTestWarningShouldBeFatal false. '
      'Missed taps are fatal for the whole host suite (D-325); a tap that is '
      'meant to miss opts out at its own call, with a stated reason.',
    );
  });

  await testMain();
}
