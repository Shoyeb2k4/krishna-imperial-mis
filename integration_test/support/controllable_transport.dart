/// An HTTP client whose network can be taken away on demand.
///
/// **Acceptance only.** It is handed to `bootstrap(transport: …)`, which is a parameter
/// and not a switch: there is no environment variable, no registry and no debug menu that
/// reaches it, and `test/app/no_hardcoded_authority_test.dart` asserts that nothing in
/// `lib/` ever passes one. A shipped binary has no path to this file at all — it lives in
/// `integration_test/`, which is not compiled into the application.
///
/// It also loses a response **after** the server has processed the request, which is the
/// only honest way to prove response-loss recovery against a real backend: the request is
/// genuinely sent, the server genuinely commits, and the client genuinely never learns the
/// answer. A duplicate RPC call proves idempotency and proves nothing about recovery,
/// because the client was told the outcome the first time.
///
/// It exists because the Windows offline behaviour cannot honestly be proven any other
/// way. Removing the build machine's network would break the tooling driving the run, and
/// a firewall rule is a machine security setting this project will not change unattended.
///
/// What it does *not* do is fake an answer. When offline it throws the same
/// `SocketException` the platform throws when a host cannot be reached, from inside the
/// same `send`, so everything downstream is the real thing: the real Supabase client, the
/// real request construction, the real classification in `SupabaseGateway`, the real
/// `AuthorityRefresh.unavailable`, the real session and purge decisions. The only thing
/// simulated is the cable.
library;

import 'dart:io';

import 'package:http/http.dart' as http;

class ControllableTransport extends http.BaseClient {
  ControllableTransport() : _inner = http.Client();

  final http.Client _inner;

  /// Every request made while this is false fails as though the host were unreachable.
  bool online = true;

  /// Requests that were attempted while offline. Useful for asserting that the
  /// application really did try, rather than short-circuiting somewhere earlier.
  final List<String> refusedWhileOffline = [];

  /// The next request whose path contains this fragment reaches the server, is answered,
  /// and the answer is then thrown away — once.
  ///
  /// This is a *lost response*, not a refused request. The distinction is the whole point:
  /// the server has committed by the time this throws, so the client is in the one state
  /// that idempotency exists for, and a retry must replay rather than record twice.
  String? loseResponseOnceFor;

  /// The paths whose responses were actually discarded, so a test can assert the scenario
  /// happened rather than assuming it did.
  final List<String> lostResponses = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!online) {
      refusedWhileOffline.add('${request.method} ${request.url.path}');
      throw const SocketException(
        'Acceptance: the network is unavailable',
        osError: OSError('No route to host', 1231),
      );
    }

    final fragment = loseResponseOnceFor;
    if (fragment != null && request.url.path.contains(fragment)) {
      loseResponseOnceFor = null;
      final response = await _inner.send(request);
      // Drained before throwing, so the exchange is complete on the wire and the server
      // has certainly finished with it. Only the client's knowledge is lost.
      await response.stream.drain<void>();
      lostResponses.add('${request.method} ${request.url.path}');
      throw const SocketException(
        'Acceptance: the connection dropped after the server answered',
        osError: OSError('Connection reset by peer', 10054),
      );
    }

    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
