import 'package:backoffice/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late _MockSupabaseClient client;
  late _MockGoTrueClient auth;
  late AuthRepository repo;

  setUp(() {
    client = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    repo = AuthRepository(client);
  });

  group('signIn', () {
    test('returns session on success', () async {
      final fakeSession = Session(
        accessToken: 'a',
        tokenType: 'bearer',
        user: User(
          id: 'u1',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => AuthResponse(session: fakeSession, user: fakeSession.user),
      );

      final result = await repo.signIn(
        email: 'admin@local.test',
        password: 'x',
      );
      expect(result.user!.id, 'u1');
    });

    test('wraps AuthException into AppException', () async {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AuthException('invalid login'));

      expect(
        () => repo.signIn(email: 'x', password: 'y'),
        throwsA(isA<AppException>()),
      );
    });
  });

  test('signOut calls auth.signOut', () async {
    when(() => auth.signOut()).thenAnswer((_) async {});
    await repo.signOut();
    verify(() => auth.signOut()).called(1);
  });
}
