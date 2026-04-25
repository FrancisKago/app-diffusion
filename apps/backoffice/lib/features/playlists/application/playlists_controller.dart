import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../auth/application/auth_controller.dart';
import '../data/device_playlists_repository.dart';
import '../data/playlist_items_repository.dart';
import '../data/playlists_repository.dart';

final playlistsRepositoryProvider = Provider<PlaylistsRepository>((ref) {
  return PlaylistsRepository(ref.watch(supabaseClientProvider));
});

final playlistItemsRepositoryProvider = Provider<PlaylistItemsRepository>((ref) {
  return PlaylistItemsRepository(ref.watch(supabaseClientProvider));
});

final devicePlaylistsRepositoryProvider =
    Provider<DevicePlaylistsRepository>((ref) {
  return DevicePlaylistsRepository(ref.watch(supabaseClientProvider));
});

final playlistsListProvider = FutureProvider<List<Playlist>>((ref) {
  return ref.watch(playlistsRepositoryProvider).list();
});

final playlistDetailProvider =
    FutureProvider.family<Playlist, String>((ref, id) {
  return ref.watch(playlistsRepositoryProvider).fetch(id);
});

final playlistItemsProvider =
    FutureProvider.family<List<PlaylistItem>, String>((ref, playlistId) {
  return ref.watch(playlistItemsRepositoryProvider).listFor(playlistId);
});

final playlistForDeviceProvider =
    FutureProvider.family<String?, String>((ref, deviceId) {
  return ref.watch(devicePlaylistsRepositoryProvider).playlistForDevice(deviceId);
});
