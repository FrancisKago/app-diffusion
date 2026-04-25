import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlaylistItemsRepository {
  PlaylistItemsRepository(this._client);
  final SupabaseClient _client;

  Future<List<PlaylistItem>> listFor(String playlistId) async {
    try {
      final rows = await _client
          .from('playlist_items')
          .select()
          .eq('playlist_id', playlistId)
          .order('position');
      return rows
          .map<PlaylistItem>(
            (r) => PlaylistItem.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture items échouée', cause: e.message);
    }
  }

  Future<PlaylistItem> append({
    required String playlistId,
    required String mediaId,
    int displayDurationSec = 10,
  }) async {
    try {
      final existing = await _client
          .from('playlist_items')
          .select('position')
          .eq('playlist_id', playlistId)
          .order('position', ascending: false)
          .limit(1);
      final nextPos =
          existing.isEmpty ? 0 : (existing.first['position'] as int) + 1;
      final row = await _client.from('playlist_items').insert({
        'playlist_id': playlistId,
        'media_id': mediaId,
        'position': nextPos,
        'display_duration_sec': displayDurationSec,
      }).select().single();
      return PlaylistItem.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Ajout item échoué', cause: e.message);
    }
  }

  Future<PlaylistItem> updateItem({
    required String id,
    int? displayDurationSec,
    DateTime? startsAt,
    DateTime? endsAt,
    bool clearStartsAt = false,
    bool clearEndsAt = false,
  }) async {
    try {
      final patch = <String, dynamic>{};
      if (displayDurationSec != null) {
        patch['display_duration_sec'] = displayDurationSec;
      }
      if (clearStartsAt) {
        patch['starts_at'] = null;
      } else if (startsAt != null) {
        patch['starts_at'] = startsAt.toUtc().toIso8601String();
      }
      if (clearEndsAt) {
        patch['ends_at'] = null;
      } else if (endsAt != null) {
        patch['ends_at'] = endsAt.toUtc().toIso8601String();
      }
      final row = await _client
          .from('playlist_items')
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      return PlaylistItem.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Mise à jour item échouée', cause: e.message);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from('playlist_items').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw AppException('Suppression item échouée', cause: e.message);
    }
  }

  Future<void> reorder({
    required String playlistId,
    required List<String> orderedItemIds,
  }) async {
    try {
      await _client.rpc(
        'reorder_playlist_items',
        params: {
          'p_playlist_id': playlistId,
          'p_ordered_item_ids': orderedItemIds,
        },
      );
    } on PostgrestException catch (e) {
      throw AppException('Réordonnancement échoué', cause: e.message);
    }
  }
}
