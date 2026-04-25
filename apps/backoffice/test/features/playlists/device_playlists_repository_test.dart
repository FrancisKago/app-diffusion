import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:backoffice/features/playlists/data/device_playlists_repository.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockFunctions extends Mock implements FunctionsClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(HttpMethod.post);
  });

  test('assign() invokes assign-playlist with deviceId + playlistId', () async {
    final client = _MockClient();
    final fns = _MockFunctions();
    when(() => client.functions).thenReturn(fns);
    when(() => fns.invoke(any(),
            body: any(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => FunctionResponse(data: {'ok': true}, status: 200));

    await DevicePlaylistsRepository(client).assign(deviceId: 'd1', playlistId: 'p1');

    final captured = verify(() => fns.invoke(captureAny(),
            body: captureAny(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .captured;
    expect(captured[0], 'assign-playlist');
    expect(captured[1], {'deviceId': 'd1', 'playlistId': 'p1'});
  });

  test('unassign() invokes assign-playlist with playlistId: null', () async {
    final client = _MockClient();
    final fns = _MockFunctions();
    when(() => client.functions).thenReturn(fns);
    when(() => fns.invoke(any(),
            body: any(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => FunctionResponse(data: {'ok': true}, status: 200));

    await DevicePlaylistsRepository(client).unassign('d1');

    final captured = verify(() => fns.invoke(captureAny(),
            body: captureAny(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .captured;
    expect(captured[0], 'assign-playlist');
    expect(captured[1], {'deviceId': 'd1', 'playlistId': null});
  });
}
