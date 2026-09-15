/// Signing in, staying signed in, and signing out.
///
/// Only the authentication half lives here. What a signed-in user may *do* is a separate
/// question answered by `AuthorityGateway`, and keeping the two apart is deliberate:
/// knowing who somebody is has never been the same as knowing what they are allowed to
/// do, and a class that returned both would make it easy to treat the first as the
/// second.
///
/// Session tokens are held in the same platform-secure store as the database key —
/// Android Keystore, Windows DPAPI — rather than in shared preferences, because a
/// refresh token is a bearer credential for company financial data (D-022).
library;

import 'package:krishna_mis/app/session/session_controller.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:krishna_mis/domain/auth/session_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in identity, as authentication knows it. No capabilities here on purpose.
final class AuthenticatedUser {
  const AuthenticatedUser({required this.id, required this.email});
  final String id;
  final String email;
}

/// The outcome of a sign-in attempt.
sealed class SignInResult {
  const SignInResult();
  const factory SignInResult.ok(AuthenticatedUser user) = SignedIn;
  const factory SignInResult.failed(SignInFailure failure) = SignInRejected;
}

final class SignedIn extends SignInResult {
  const SignedIn(this.user);
  final AuthenticatedUser user;
}

final class SignInRejected extends SignInResult {
  const SignInRejected(this.failure);
  final SignInFailure failure;
}

class AuthGateway implements SessionAuth {
  const AuthGateway(this._client);

  final SupabaseClient _client;

  /// The user id of the restored session, or null when nobody is signed in.
  @override
  AuthenticatedUser? get currentUser {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return AuthenticatedUser(id: user.id, email: user.email ?? '');
  }

  Stream<AuthState> get changes => _client.auth.onAuthStateChange;

  /// Signs in with an email address and a password.
  ///
  /// Returns the failure the login screen should show, already classified — the mapping
  /// lives in [failureFor] rather than being implied by which `catch` happened to fire.
  @override
  Future<SignInResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = response.user;
      if (user == null) {
        return const SignInResult.failed(SignInFailure.serverUnavailable);
      }
      return SignInResult.ok(
        AuthenticatedUser(id: user.id, email: user.email ?? email.trim()),
      );
    } on Object catch (error) {
      return SignInResult.failed(failureFor(error));
    }
  }

  /// Classifies a sign-in failure for the login screen.
  ///
  /// Wrong password and unknown address deliberately collapse onto one message: telling
  /// somebody probing the screen which half they got right is a gift to them and of no
  /// use to a manager who has simply mistyped.
  static SignInFailure failureFor(Object error) {
    if (error is AuthApiException) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login') ||
          message.contains('invalid credentials') ||
          message.contains('email not confirmed') ||
          error.statusCode == '400') {
        return SignInFailure.invalidCredentials;
      }
      if (message.contains('disabled') ||
          message.contains('banned') ||
          message.contains('deactivat')) {
        return SignInFailure.accountDeactivated;
      }
      return SignInFailure.serverUnavailable;
    }
    if (error is AuthException) return SignInFailure.serverUnavailable;
    if (error is SocketException || error is TimeoutException) {
      return SignInFailure.offline;
    }
    return SignInFailure.offline;
  }

  /// Ends the session.
  ///
  /// Clears tokens only. The local database — including anything queued and unsent — is
  /// deliberately untouched: destroying it would take work that exists nowhere else
  /// (`ARCHITECTURE.md` §8.2). Erasing local data is a separate, explicit, destructive
  /// action with its own confirmation.
  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on Object {
      // Signing out must succeed locally even when the server cannot be told. The token
      // is discarded either way; leaving somebody signed in because the network was down
      // would be the worse failure.
    }
  }

  /// Attempts to renew an expiring session.
  Future<bool> refreshSession() async {
    try {
      final response = await _client.auth.refreshSession();
      return response.session != null;
    } on Object {
      return false;
    }
  }
}

/// Supabase session persistence backed by the platform-secure store.
///
/// The package's default keeps the session in shared preferences, which on a shared
/// Windows machine is a plain file any process belonging to that user can read. A refresh
/// token is a bearer credential for company financial data, so it goes where the database
/// key goes: Android Keystore, or DPAPI on Windows (D-022, D-036).
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;

  static const _key = 'krishna_mis.session.v1';

  @override
  Future<void> initialize() async {}

  /// The **persisted session string**, exactly as it was written — not the access token
  /// inside it.
  ///
  /// The name is `supabase_flutter`'s, and misleading: its startup passes this value straight
  /// to `auth.setInitialSession(...)` and `auth.recoverSession(...)`, which parse the whole
  /// persisted session, and its own shipped storage returns the stored string unchanged.
  /// Returning only the `access_token` field made every restart fail to restore the session
  /// (Slice 11, D-244).
  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<bool> hasAccessToken() async =>
      (await _storage.read(key: _key)) != null;

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
