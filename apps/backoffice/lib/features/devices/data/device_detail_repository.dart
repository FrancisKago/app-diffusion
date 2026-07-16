import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceHeartbeat {
  const DeviceHeartbeat({
    required this.id,
    required this.deviceId,
    required this.receivedAt,
    this.battery,
    this.storageFreeMb,
    this.appVersion,
  });

  final int id;
  final String deviceId;
  final DateTime receivedAt;
  final int? battery;
  final int? storageFreeMb;
  final String? appVersion;

  factory DeviceHeartbeat.fromJson(Map<String, dynamic> json) =>
      DeviceHeartbeat(
        id: json['id'] as int,
        deviceId: json['device_id'] as String,
        receivedAt: DateTime.parse(json['received_at'] as String),
        battery: json['battery'] as int?,
        storageFreeMb: json['storage_free_mb'] as int?,
        appVersion: json['app_version'] as String?,
      );
}

class PlaybackLogEntry {
  const PlaybackLogEntry({
    required this.id,
    required this.deviceId,
    this.mediaId,
    required this.playedAt,
    required this.durationPlayedSec,
    this.playCount = 1,
  });

  final int id;
  final String deviceId;
  final String? mediaId;
  final DateTime playedAt;

  /// Cumulative seconds played for this (device, media, hour) bucket.
  final int durationPlayedSec;

  /// Number of loops folded into this row (hourly aggregation).
  final int playCount;

  factory PlaybackLogEntry.fromJson(Map<String, dynamic> json) =>
      PlaybackLogEntry(
        id: json['id'] as int,
        deviceId: json['device_id'] as String,
        mediaId: json['media_id'] as String?,
        playedAt: DateTime.parse(json['played_at'] as String),
        durationPlayedSec: json['duration_played_sec'] as int,
        playCount: json['play_count'] as int? ?? 1,
      );
}

class DeviceDetailRepository {
  DeviceDetailRepository(this._client);
  final SupabaseClient _client;

  Future<List<DeviceHeartbeat>> recentHeartbeats(
    String deviceId, {
    int limit = 50,
  }) async {
    try {
      final rows = await _client
          .from('device_heartbeats')
          .select()
          .eq('device_id', deviceId)
          .order('received_at', ascending: false)
          .limit(limit);
      return rows
          .map<DeviceHeartbeat>(
            (r) =>
                DeviceHeartbeat.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture heartbeats échouée', cause: e.message);
    }
  }

  Future<List<PlaybackLogEntry>> recentPlaybackLogs(
    String deviceId, {
    int limit = 50,
  }) async {
    try {
      final rows = await _client
          .from('playback_logs')
          .select()
          .eq('device_id', deviceId)
          .order('played_at', ascending: false)
          .limit(limit);
      return rows
          .map<PlaybackLogEntry>(
            (r) =>
                PlaybackLogEntry.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture playback logs échouée', cause: e.message);
    }
  }

  Future<List<PlaybackLogEntry>> allPlaybackLogsForExport(
    String deviceId,
  ) async {
    try {
      final rows = await _client
          .from('playback_logs')
          .select()
          .eq('device_id', deviceId)
          .order('played_at', ascending: false)
          .limit(10000);
      return rows
          .map<PlaybackLogEntry>(
            (r) =>
                PlaybackLogEntry.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Export logs échoué', cause: e.message);
    }
  }
}
