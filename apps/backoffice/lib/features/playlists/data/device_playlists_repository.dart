import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DevicePlaylistsRepository {
  DevicePlaylistsRepository(this._client);
  final SupabaseClient _client;

  Future<String?> playlistForDevice(String deviceId) async {
    try {
      final rows = await _client
          .from('device_playlists')
          .select('playlist_id')
          .eq('device_id', deviceId);
      if (rows.isEmpty) return null;
      return rows.first['playlist_id'] as String;
    } on PostgrestException catch (e) {
      throw AppException('Lecture affectation échouée', cause: e.message);
    }
  }

  Future<void> assign({
    required String deviceId,
    required String playlistId,
  }) async {
    try {
      await _client.from('device_playlists').upsert({
        'device_id': deviceId,
        'playlist_id': playlistId,
      });
    } on PostgrestException catch (e) {
      throw AppException('Assignation échouée', cause: e.message);
    }
  }

  Future<void> unassign(String deviceId) async {
    try {
      await _client.from('device_playlists').delete().eq('device_id', deviceId);
    } on PostgrestException catch (e) {
      throw AppException('Détachement échoué', cause: e.message);
    }
  }
}
