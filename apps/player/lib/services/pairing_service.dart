import 'dart:convert';
import 'package:http/http.dart' as http;

enum PairingStatus { pending, claimed, expired }

class PairingCodeResponse {
  const PairingCodeResponse({
    required this.sessionId,
    required this.code,
    required this.ttlSeconds,
  });
  final String sessionId;
  final String code;
  final int ttlSeconds;
}

class PairingStatusResponse {
  const PairingStatusResponse({
    required this.status,
    this.deviceId,
    this.jwt,
  });
  final PairingStatus status;
  final String? deviceId;
  final String? jwt;
}

class PairingService {
  PairingService({
    required this.baseUrl,
    required this.anonKey,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  final String baseUrl;
  final String anonKey;
  final http.Client _client;

  Map<String, String> get _headers => {
        'apikey': anonKey,
        'Content-Type': 'application/json',
      };

  Future<PairingCodeResponse> requestCode() async {
    final uri = Uri.parse('$baseUrl/functions/v1/request-pairing-code');
    final res = await _client.post(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw StateError('request-pairing-code failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return PairingCodeResponse(
      sessionId: json['session_id'] as String,
      code: json['code'] as String,
      ttlSeconds: json['ttl_seconds'] as int? ?? 900,
    );
  }

  Future<PairingStatusResponse> pollStatus(String sessionId) async {
    final uri = Uri.parse(
      '$baseUrl/functions/v1/pairing-status?session_id=$sessionId',
    );
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw StateError('pairing-status failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final statusStr = json['status'] as String;
    final status = switch (statusStr) {
      'claimed' => PairingStatus.claimed,
      'expired' => PairingStatus.expired,
      _ => PairingStatus.pending,
    };
    return PairingStatusResponse(
      status: status,
      deviceId: json['device_id'] as String?,
      jwt: json['jwt'] as String?,
    );
  }
}
