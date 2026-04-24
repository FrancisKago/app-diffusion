import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).onAuthStateChange();
});

final currentSessionProvider = Provider<Session?>((ref) {
  final asyncState = ref.watch(authStateProvider);
  return asyncState.maybeWhen(
    data: (s) => s.session,
    orElse: () => ref.watch(authRepositoryProvider).currentSession,
  );
});
