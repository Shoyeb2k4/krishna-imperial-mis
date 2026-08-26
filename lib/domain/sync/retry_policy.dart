/// Deterministic retry scheduling for the outbox.
///
/// Retries are driven by the outbox clock, connectivity changes and app foreground —
/// never by a tight loop (docs/ARCHITECTURE.md §5.1). The schedule is pure and testable
/// so "when will this be tried again" is a question with an exact answer.
library;

import 'dart:math';

import 'package:meta/meta.dart';

@immutable
final class RetryPolicy {
  const RetryPolicy({this.jitterFraction = 0.2, this.random});

  /// Backoff steps. After the last step the interval stays capped at one hour.
  static const List<Duration> schedule = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
  ];

  /// Proportion of the delay that may be added as jitter, spreading retries so several
  /// queued entries do not all wake at the same instant.
  final double jitterFraction;

  /// Injectable for tests. When null, no jitter is applied and the delay is exactly the
  /// scheduled step — which is what makes the schedule assertable.
  final Random? random;

  /// The base delay before attempt number [attemptCount] + 1.
  ///
  /// `attemptCount == 0` means nothing has been tried yet, so the first retry uses the
  /// first step.
  Duration baseDelayFor(int attemptCount) {
    if (attemptCount < 0) {
      throw ArgumentError.value(
        attemptCount,
        'attemptCount',
        'must not be negative',
      );
    }
    final index = min(attemptCount, schedule.length - 1);
    return schedule[index];
  }

  /// The delay including jitter, if a [random] source was supplied.
  Duration delayFor(int attemptCount) {
    final base = baseDelayFor(attemptCount);
    final rng = random;
    if (rng == null || jitterFraction <= 0) return base;

    final maxJitterMs = (base.inMilliseconds * jitterFraction).round();
    if (maxJitterMs <= 0) return base;
    return base + Duration(milliseconds: rng.nextInt(maxJitterMs + 1));
  }

  /// When the entry becomes eligible again, given the moment the attempt failed.
  DateTime nextAttemptAt(DateTime failedAt, int attemptCount) =>
      failedAt.add(delayFor(attemptCount));
}
