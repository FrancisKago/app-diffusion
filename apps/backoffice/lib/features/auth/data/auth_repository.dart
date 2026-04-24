import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      throw AppException('Échec de la connexion', cause: e.message);
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  Stream<AuthState> onAuthStateChange() => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;
}
