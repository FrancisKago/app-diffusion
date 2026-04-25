import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:backoffice/features/devices/data/devices_repository.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockFunctions extends Mock implements FunctionsClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(HttpMethod.post);
  });

  test('revoke() invokes revoke-device Edge Function with deviceId in body',
      () async {
    final client = _MockClient();
    final fns = _MockFunctions();
    when(() => client.functions).thenReturn(fns);
    when(() => fns.invoke(any(),
            body: any(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => FunctionResponse(data: {'ok': true}, status: 200));

    await DevicesRepository(client).revoke('d1');

    final captured = verify(() => fns.invoke(captureAny(),
            body: captureAny(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .captured;
    expect(captured[0], 'revoke-device');
    expect(captured[1], {'deviceId': 'd1'});
  });
}
