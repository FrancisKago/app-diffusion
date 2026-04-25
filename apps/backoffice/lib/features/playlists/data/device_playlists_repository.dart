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
      final response = await _client.functions.invoke(
        'assign-playlist',
        body: {'deviceId': deviceId, 'playlistId': playlistId},
      );
      if (response.status != 200) {
        throw AppException(
          'Assignation échouée',
          cause: 'Edge function returned status ${response.status}',
        );
      }
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Assignation échouée', cause: e.toString());
    }
  }

  Future<void> unassign(String deviceId) async {
    try {
      final response = await _client.functions.invoke(
        'assign-playlist',
        body: {'deviceId': deviceId, 'playlistId': null},
      );
      if (response.status != 200) {
        throw AppException(
          'Détachement échoué',
          cause: 'Edge function returned status ${response.status}',
        );
      }
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Détachement échoué', cause: e.toString());
    }
  }
}
