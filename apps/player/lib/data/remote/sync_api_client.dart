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

  /// Sends a heartbeat by calling the `record_heartbeat` Postgres RPC.
  ///
  /// The [deviceId] parameter is kept for backward compatibility with existing
  /// call sites but is now unused — the server identifies the device via the
  /// JWT (`auth.uid()`).
  Future<void> heartbeat(
    String deviceId, {
    int? syncProgress,
    String? currentMediaId,
    int? battery,
    int? storageFreeMb,
    String? appVersion,
  }) async {
    final body = <String, dynamic>{};
    if (battery != null) body['p_battery'] = battery;
    if (storageFreeMb != null) body['p_storage_free_mb'] = storageFreeMb;
    if (appVersion != null) body['p_app_version'] = appVersion;
    if (syncProgress != null) body['p_sync_progress'] = syncProgress;
    if (currentMediaId != null) body['p_current_media_id'] = currentMediaId;
    await _dio.post<dynamic>(
      '$baseUrl/rest/v1/rpc/record_heartbeat',
      data: jsonEncode(body),
      options: Options(
        headers: {..._headers, 'Content-Type': 'application/json'},
      ),
    );
  }

  /// Records a playback log via the `record_playback` Postgres RPC.
  Future<void> recordPlayback({
    required String mediaId,
    required int durationPlayedSec,
  }) async {
    await _dio.post<dynamic>(
      '$baseUrl/rest/v1/rpc/record_playback',
      data: jsonEncode({
        'p_media_id': mediaId,
        'p_duration_played_sec': durationPlayedSec,
      }),
      options: Options(
        headers: {..._headers, 'Content-Type': 'application/json'},
      ),
    );
  }
}
