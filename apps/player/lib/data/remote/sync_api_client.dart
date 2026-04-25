import 'dart:convert';

import 'package:dio/dio.dart';

class SyncApiClient {
  SyncApiClient({
    required this.baseUrl,
    required this.anonKey,
    required this.deviceJwt,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final String baseUrl;
  final String anonKey;
  final String deviceJwt;
  final Dio _dio;

  Map<String, String> get _headers => {
        'apikey': anonKey,
        'Authorization': 'Bearer $deviceJwt',
        'Accept': 'application/json',
      };

  /// Returns the current playlist assignment for this device, or null if none.
  Future<String?> getMyDevicePlaylistAssignment(String deviceId) async {
    final r = await _dio.get<List<dynamic>>(
      '$baseUrl/rest/v1/device_playlists',
      queryParameters: {
        'device_id': 'eq.$deviceId',
        'select': 'playlist_id',
      },
      options: Options(headers: _headers),
    );
    final data = r.data ?? [];
    if (data.isEmpty) return null;
    return (Map<String, dynamic>.from(data.first as Map))['playlist_id'] as String?;
  }

  Future<Map<String, dynamic>> fetchPlaylist(String playlistId) async {
    final r = await _dio.get<List<dynamic>>(
      '$baseUrl/rest/v1/playlists',
      queryParameters: {'id': 'eq.$playlistId', 'select': '*'},
      options: Options(headers: _headers),
    );
    final list = r.data ?? [];
    if (list.isEmpty) throw StateError('Playlist not found: $playlistId');
    return Map<String, dynamic>.from(list.first as Map);
  }

  Future<List<Map<String, dynamic>>> fetchPlaylistItems(String playlistId) async {
    final r = await _dio.get<List<dynamic>>(
      '$baseUrl/rest/v1/playlist_items',
      queryParameters: {
        'playlist_id': 'eq.$playlistId',
        'select': '*',
        'order': 'position.asc',
      },
      options: Options(headers: _headers),
    );
    return (r.data ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchMedia(List<String> ids) async {
    if (ids.isEmpty) return [];
    final inFilter = '(${ids.join(",")})';
    final r = await _dio.get<List<dynamic>>(
      '$baseUrl/rest/v1/media',
      queryParameters: {'id': 'in.$inFilter', 'select': '*'},
      options: Options(headers: _headers),
    );
    return (r.data ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// Returns a fully-qualified signed URL for downloading the media binary.
  Future<String> signedUrlForMedia(
    String filePath, {
    int expiresInSeconds = 3600,
  }) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/storage/v1/object/sign/media/$filePath',
      data: jsonEncode({'expiresIn': expiresInSeconds}),
      options: Options(
        headers: {..._headers, 'Content-Type': 'application/json'},
      ),
    );
    final body = r.data ?? {};
    final raw = body['signedURL'] ?? body['signedUrl'];
    if (raw is! String) {
      throw StateError('No signedURL in storage response: $body');
    }
    if (raw.startsWith('http')) return raw;
    // Supabase returns a relative path like /object/sign/media/...
    return '$baseUrl/storage/v1$raw';
  }

  Future<void> heartbeat(
    String deviceId, {
    int? syncProgress,
    String? currentMediaId,
  }) async {
    final patch = <String, dynamic>{
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (syncProgress != null) patch['sync_progress'] = syncProgress;
    if (currentMediaId != null) patch['current_media_id'] = currentMediaId;
    await _dio.patch<dynamic>(
      '$baseUrl/rest/v1/devices',
      queryParameters: {'id': 'eq.$deviceId'},
      data: jsonEncode(patch),
      options: Options(
        headers: {..._headers, 'Content-Type': 'application/json'},
      ),
    );
  }
}
