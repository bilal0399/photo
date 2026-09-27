import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../model/app_user.dart';

/// Authentication contract. Email/password are handled by Supabase Auth; the
/// username and role live in the `profiles` table.
abstract class AuthService {
  bool get isSignedIn;
  Stream<bool> authState();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<AppUser?> currentUser();

  /// Admin action: create a new account with the given profile fields.
  Future<void> createUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
  });
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);

  final SupabaseClient _client;

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  Stream<bool> authState() =>
      _client.auth.onAuthStateChange.map((_) => _client.auth.currentSession != null);

  @override
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> createUser({
    required String fullName,
    required String email,
    required String password,
    required String role,
  }) async {
    // Preferred path: the `admin-users` Edge Function creates the account with
    // the service key on the server, after checking that the caller is admin.
    // It works with public sign-ups disabled, which keeps strangers out.
    try {
      await _client.functions.invoke('admin-users', body: {
        'action': 'create',
        'username': fullName.trim(),
        'email': email.trim(),
        'password': password,
        'role': role,
      });
      return;
    } on FunctionException catch (e) {
      // 404: the function is not deployed yet, fall back to a sign-up below.
      if (e.status != 404) {
        final details = e.details;
        final message = details is Map && details['error'] is String
            ? details['error'] as String
            : (e.reasonPhrase ?? 'HTTP ${e.status}');
        throw AuthException(message, statusCode: '${e.status}');
      }
    }

    // Use a throwaway client so signing the new user up does NOT replace the
    // admin's current session on the global client. The implicit flow avoids
    // the PKCE code-verifier storage that a bare client doesn't have.
    final temp = SupabaseClient(
      Env.supabaseUrl,
      Env.supabaseAnonKey,
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        autoRefreshToken: false,
      ),
    );
    try {
      final res = await temp.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'username': fullName.trim()},
      );
      final newId = res.user?.id;
      // The DB trigger creates the profile with role 'user'. Promote to admin
      // only when requested (allowed by the admins-update-profiles policy).
      if (newId != null && role == 'admin') {
        await _client.from('profiles').update({'role': 'admin'}).eq('id', newId);
      }
    } finally {
      await temp.dispose();
    }
  }

  @override
  Future<AppUser?> currentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    Map<String, dynamic>? profile;
    try {
      profile = await _client.from('profiles').select().eq('id', user.id).maybeSingle();
    } catch (_) {
      profile = null; // profile row may not exist yet — fall back to email
    }
    return AppUser.from(id: user.id, email: user.email ?? '', profile: profile);
  }
}

final authServiceProvider = Provider<AuthService>(
  (ref) => SupabaseAuthService(Supabase.instance.client),
);

/// Emits whenever the signed-in state changes (drives the router guard).
final authStateProvider = StreamProvider<bool>(
  (ref) => ref.watch(authServiceProvider).authState(),
);

/// The current user's profile (username + role), or null when signed out.
final currentUserProvider = FutureProvider<AppUser?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authServiceProvider).currentUser();
});
