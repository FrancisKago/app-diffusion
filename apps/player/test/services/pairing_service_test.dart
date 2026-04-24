import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:player/services/pairing_service.dart';

class _MockClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('http://x'));
  });

  group('PairingService.requestCode', () {
    test('parses session_id and code from successful response', () async {
      final client = _MockClient();
      when(
        () => client.post(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"session_id":"s1","code":"482193","ttl_seconds":900}',
          200,
        ),
      );

      final svc = PairingService(
        baseUrl: 'http://localhost:54321',
        anonKey: 'anon',
        httpClient: client,
      );
      final res = await svc.requestCode();
      expect(res.sessionId, 's1');
      expect(res.code, '482193');
    });
  });

  group('PairingService.pollStatus', () {
    test('returns claimed with jwt', () async {
      final client = _MockClient();
      when(
        () => client.get(
          any(),
          headers: any(named: 'headers'),
        ),
      ).thenAnswer(
        (_) async => http.Response(
          '{"status":"claimed","device_id":"d1","jwt":"eyJ..."}',
          200,
        ),
      );

      final svc = PairingService(
        baseUrl: 'http://localhost:54321',
        anonKey: 'anon',
        httpClient: client,
      );
      final res = await svc.pollStatus('s1');
      expect(res.status, PairingStatus.claimed);
      expect(res.deviceId, 'd1');
      expect(res.jwt, 'eyJ...');
    });
  });
}
