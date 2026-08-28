/// The three things a request to the server can mean.
///
/// The same discipline `AuthorityRefresh` applies to permissions, applied to every call:
/// **a refusal and a failure are not the same event**, and collapsing them into
/// `try/catch` or a nullable result is how a lost signal ends up being treated as a
/// denial. One says the server considered the request and declined; the other says the
/// server never got to consider it.
///
/// Callers must handle all three, because the correct response differs completely:
/// a refusal is shown to the user and the attempt stops; an unreachable server means
/// keep the cache, mark it stale, and try again later.
library;

import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:meta/meta.dart';

/// Why a request never produced an answer.
enum RemoteFailure {
  /// No connectivity, DNS failure, timeout — the request did not complete.
  offline,

  /// The server answered unusably: a 5xx, a gateway error, a malformed body.
  serverUnreachable,

  /// The session expired and could not be refreshed. The queue pauses; nothing is lost.
  sessionExpired;

  String get message => switch (this) {
    RemoteFailure.offline =>
      'No connection. Your work is saved on this device and will sync when you are back '
          'online.',
    RemoteFailure.serverUnreachable =>
      'The server could not be reached. Nothing has been lost — this will be retried.',
    RemoteFailure.sessionExpired =>
      'Your session has expired. Sign in again to continue; nothing you have entered has '
          'been lost.',
  };

  /// Whether the sync worker may try again on its own schedule. All three are transient
  /// by nature — unlike a refusal, repeating the request genuinely might succeed.
  bool get isRetryable => this != RemoteFailure.sessionExpired;
}

@immutable
sealed class RemoteOutcome<T> {
  const RemoteOutcome();

  const factory RemoteOutcome.ok(T value) = RemoteOk<T>;
  const factory RemoteOutcome.refused(ServerRefusal refusal) = RemoteRefused<T>;
  const factory RemoteOutcome.unreachable(RemoteFailure failure) =
      RemoteUnreachable<T>;

  /// The value, or null. Deliberately not a `getOrThrow`: the whole point is that the
  /// two non-success cases mean different things and both need handling.
  T? get valueOrNull =>
      this is RemoteOk<T> ? (this as RemoteOk<T>).value : null;

  bool get isOk => this is RemoteOk<T>;

  /// True only when the server actually considered the request and said no.
  ///
  /// Never true for a transport failure — that distinction is what stops a tunnel from
  /// looking like a denial (D-048 §1).
  bool get isRefused => this is RemoteRefused<T>;

  ServerRefusal? get refusalOrNull =>
      this is RemoteRefused<T> ? (this as RemoteRefused<T>).refusal : null;

  RemoteFailure? get failureOrNull => this is RemoteUnreachable<T>
      ? (this as RemoteUnreachable<T>).failure
      : null;

  RemoteOutcome<R> map<R>(R Function(T value) transform) => switch (this) {
    RemoteOk<T>(:final value) => RemoteOutcome.ok(transform(value)),
    RemoteRefused<T>(:final refusal) => RemoteOutcome.refused(refusal),
    RemoteUnreachable<T>(:final failure) => RemoteOutcome.unreachable(failure),
  };
}

final class RemoteOk<T> extends RemoteOutcome<T> {
  const RemoteOk(this.value);
  final T value;
  @override
  String toString() => 'RemoteOk($value)';
}

final class RemoteRefused<T> extends RemoteOutcome<T> {
  const RemoteRefused(this.refusal);
  final ServerRefusal refusal;
  @override
  String toString() => 'RemoteRefused(${refusal.code})';
}

final class RemoteUnreachable<T> extends RemoteOutcome<T> {
  const RemoteUnreachable(this.failure);
  final RemoteFailure failure;
  @override
  String toString() => 'RemoteUnreachable(${failure.name})';
}
