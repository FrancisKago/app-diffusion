import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlaylistsRepository {
  PlaylistsRepository(this._client);
  final SupabaseClient _client;

  Future<List<Playlist>> list() async {
    try {
      final rows = await _client
          .from('playlists')
          .select()
          .order('created_at', ascending: false);
      return rows
          .map<Playlist>(
            (r) => Playlist.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture playlists échouée', cause: e.message);
    }
  }

  Future<Playlist> fetch(String id) async {
    try {
      final row =
          await _client.from('playlists').select().eq('id', id).single();
      return Playlist.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Lecture playlist échouée', cause: e.message);
    }
  }

  Future<Playlist> create({
    required String establishmentId,
    required String name,
    bool audioEnabled = false,
  }) async {
    try {
      final row = await _client.from('playlists').insert({
        'establishment_id': establishmentId,
        'name': name,
        'audio_enabled': audioEnabled,
      }).select().single();
      return Playlist.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Création playlist échouée', cause: e.message);
    }
  }

  Future<Playlist> updateMeta({
    required String id,
    required String name,
    required bool audioEnabled,
  }) async {
    try {
      final row = await _client.from('playlists').update({
        'name': name,
        'audio_enabled': audioEnabled,
      }).eq('id', id).select().single();
      return Playlist.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Mise à jour playlist échouée', cause: e.message);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from('playlists').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw AppException('Suppression échouée', cause: e.message);
    }
  }

  Future<Playlist> publish(String id) async {
    try {
      final current = await fetch(id);
      final now = DateTime.now().toUtc().toIso8601String();
      final row = await _client.from('playlists').update({
        'version': current.version + 1,
        'published_at': now,
      }).eq('id', id).select().single();
      return Playlist.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Publication échouée', cause: e.message);
    }
  }
}
