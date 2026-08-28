/// The one place a Supabase error becomes something the application understands.
///
/// Every gateway extends this, and none of them catches exceptions itself. That is
/// deliberate: the classification below is the security-relevant part of the whole remote
/// layer, and having it written once means no gateway can quietly decide that a timeout
/// looked close enough to a refusal.
///
/// The mapping it performs:
///
/// | What came back | Becomes |
/// |---|---|
/// | A `PostgrestException` with one of our `KM…` codes | `RemoteRefused` carrying a typed `ServerRefusal` |
/// | `42501` / `401` / `403` — no grant at all | `RemoteRefused` (missing capability) |
/// | An `AuthException`, or a session that will not refresh | `RemoteUnreachable(sessionExpired)` |
/// | A socket, DNS, TLS or timeout error | `RemoteUnreachable(offline)` |
/// | Anything else | `RemoteUnreachable(serverUnreachable)` |
///
/// Note which way the unknown case falls. An unclassifiable failure is **unreachable**,
/// not refused — because "we do not know what happened" must never authorise a
/// destructive local action, and only a positive refusal ends an attempt (D-048 §1).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:krishna_mis/data/remote/remote_outcome.dart';
import 'package:krishna_mis/domain/sync/server_refusal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class SupabaseGateway {
  const SupabaseGateway(this.client);

  final SupabaseClient client;

  /// Runs [request] and classifies whatever comes back.
  Future<RemoteOutcome<T>> guard<T>(Future<T> Function() request) async {
    try {
      return RemoteOutcome.ok(await request());
    } on PostgrestException catch (error) {
      return RemoteOutcome.refused(_refusalFrom(error));
    } on AuthException {
      // The session could not be established or renewed. Not a refusal of *this*
      // request — the request never got a chance — so the queue pauses rather than
      // burning attempts or marking anything rejected.
      return const RemoteOutcome.unreachable(RemoteFailure.sessionExpired);
    } on SocketException {
      return const RemoteOutcome.unreachable(RemoteFailure.offline);
    } on HandshakeException {
      return const RemoteOutcome.unreachable(RemoteFailure.offline);
    } on TimeoutException {
      return const RemoteOutcome.unreachable(RemoteFailure.offline);
    } on Object {
      // Deliberately the *unreachable* side of the line. An error nobody anticipated is
      // an unknown, and an unknown must not be allowed to look like the server saying no.
      return const RemoteOutcome.unreachable(RemoteFailure.serverUnreachable);
    }
  }

  /// Turns a PostgREST error into the typed refusal the application reasons about.
  ///
  /// Our RPCs raise with a JSON `DETAIL` carrying a stable `code`; PostgREST surfaces
  /// that as `details`. Where the payload is present the refusal is exact, including the
  /// structured numbers a screen needs — the child count behind a D-039 archive refusal,
  /// the transaction count behind a D-038 acknowledgement.
  ServerRefusal _refusalFrom(PostgrestException error) {
    final detail = _decodeDetail(error.details);
    final code = detail['code'] as String?;

    if (code != null) {
      return ServerRefusal.fromCode(
        code,
        serverMessage: error.message,
        detail: detail,
      );
    }

    // No structured payload. `42501` is Postgres refusing on privileges — the request
    // reached a table or function this role holds no grant on, which is exactly the
    // "no direct writes" boundary. It is a genuine refusal, not a transport problem.
    if (error.code == '42501') {
      return ServerRefusal.fromCode(
        'missing_capability',
        serverMessage: error.message,
      );
    }

    return ServerRefusal.fromCode(error.code, serverMessage: error.message);
  }

  Map<String, Object?> _decodeDetail(Object? details) {
    if (details is Map<String, Object?>) return details;
    if (details is String && details.trimLeft().startsWith('{')) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map<String, Object?>) return decoded;
      } on FormatException {
        // A non-JSON detail string is ordinary Postgres prose. Nothing to extract, and
        // nothing worth failing over.
      }
    }
    return const {};
  }
}
