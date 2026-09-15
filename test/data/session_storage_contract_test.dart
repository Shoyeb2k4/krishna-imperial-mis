/// The persisted session must come back whole, or nobody stays signed in across a restart.
///
/// Phase 5 Slice 11. Every Windows acceptance log carried the same two warnings on start-up —
/// `Error while setting initial session` and `Error while recovering session`, each a
/// `FormatException` at character 1 over the start of a bare JWT.
///
/// `supabase_flutter` 2.17.2 hands whatever `LocalStorage.accessToken()` returns straight to
/// `auth.setInitialSession(...)` and `auth.recoverSession(...)`, both of which parse a
/// **persisted session JSON string**. Its own shipped storage returns the stored string
/// unchanged. `SecureSessionStorage` instead decoded that string and returned only its
/// `access_token` field — so recovery could never parse what it was given, no session was ever
/// restored, and every launch fell back to the sign-in screen.
///
/// It failed closed, which is why nothing looked wrong: nobody saw anybody else's data. It is
/// still a defect, and the restart rule the Phase 2 acceptance header describes — "no sign-in
/// at all — the session must come back on its own" — had no phase behind it.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:krishna_mis/data/remote/auth_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

import '../support/in_memory_secret_storage.dart';

/// A persisted session in the shape GoTrue writes it: the serialised session object.
String _persisted() => jsonEncode({
  'access_token':
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
      'eyJzdWIiOiJ1c2VyLWEiLCJleHAiOjQxMDI0NDQ4MDAsInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.'
      'test-signature',
  'expires_in': 3600,
  'expires_at': 4102444800,
  'refresh_token': 'test-refresh',
  'token_type': 'bearer',
  'user': {
    'id': 'user-a',
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'a@example.test',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-09-01T00:00:00.000Z',
  },
});

void main() {
  test(
    'what was persisted is what is handed back for recovery, unchanged',
    () async {
      final storage = SecureSessionStorage(storage: InMemorySecretStorage());
      final persisted = _persisted();

      expect(await storage.hasAccessToken(), isFalse);
      await storage.persistSession(persisted);
      expect(await storage.hasAccessToken(), isTrue);

      expect(
        await storage.accessToken(),
        persisted,
        reason:
            'supabase_flutter passes accessToken() to setInitialSession/recoverSession, '
            'which parse the persisted session JSON; returning only the access token makes '
            'every restart fail to restore the session',
      );
    },
  );

  test('the value handed back parses as the session it came from', () async {
    final storage = SecureSessionStorage(storage: InMemorySecretStorage());
    await storage.persistSession(_persisted());

    final restored = Session.fromJson(
      jsonDecode((await storage.accessToken())!) as Map<String, dynamic>,
    );
    expect(restored, isNotNull);
    expect(restored!.user.id, 'user-a');
    expect(restored.refreshToken, 'test-refresh');
  });

  test('sign-out removes it, so the next launch restores nothing', () async {
    final storage = SecureSessionStorage(storage: InMemorySecretStorage());
    await storage.persistSession(_persisted());
    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
    expect(await storage.accessToken(), isNull);
  });
}
