/// An HTTP client whose network can be taken away on demand.
///
/// **Acceptance only.** It is handed to `bootstrap(transport: …)`, which is a parameter
/// and not a switch: there is no environment variable, no registry and no debug menu that
/// reaches it, and `test/app/no_hardcoded_authority_test.dart` asserts that nothing in
/// `lib/` ever passes one. A shipped binary has no path to this file at all — it lives in
/// `integration_test/`, which is not compiled into the application.
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

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!online) {
      refusedWhileOffline.add('${request.method} ${request.url.path}');
      throw const SocketException(
        'Acceptance: the network is unavailable',
        osError: OSError('No route to host', 1231),
      );
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
