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

  Future<Profile?> fetchCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('id, role, full_name')
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return null;
      return Profile.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Lecture profil échouée', cause: e.message);
    }
  }
}
