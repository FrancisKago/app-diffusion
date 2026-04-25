import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:backoffice/features/playlists/data/playlists_repository.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockFunctions extends Mock implements FunctionsClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(HttpMethod.post);
  });

  test('publish() invokes publish-playlist Edge Function with id in body',
      () async {
    final client = _MockClient();
    final fns = _MockFunctions();
    when(() => client.functions).thenReturn(fns);
    when(() => fns.invoke(
          any(),
          body: any(named: 'body'),
          method: any(named: 'method'),
          headers: any(named: 'headers'),
          queryParameters: any(named: 'queryParameters'),
        )).thenAnswer((_) async => FunctionResponse(
          data: {
            'ok': true,
            'playlist': {
              'id': 'p1',
              'establishment_id': 'e1',
              'name': 'Demo',
              'audio_enabled': false,
              'version': 5,
              'published_at': '2026-04-25T18:00:00.000Z',
              'created_at': '2026-04-25T17:00:00.000Z',
            },
            'push': {'sentCount': 1, 'targetCount': 1, 'wipedCount': 0},
          },
          status: 200,
        ));

    final repo = PlaylistsRepository(client);
    final result = await repo.publish('p1');

    expect(result.id, 'p1');
    expect(result.version, 5);
    final captured = verify(() => fns.invoke(
          captureAny(),
          body: captureAny(named: 'body'),
          method: any(named: 'method'),
          headers: any(named: 'headers'),
          queryParameters: any(named: 'queryParameters'),
        )).captured;
    expect(captured[0], 'publish-playlist');
    expect(captured[1], {'id': 'p1'});
  });
}
