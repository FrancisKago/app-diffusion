import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;

import 'file_hasher.dart';
import 'local/app_database.dart';
import 'local/cache_storage.dart';
import 'media_downloader.dart';
import 'remote/sync_api_client.dart';

class SyncResult {
  const SyncResult({
    required this.playlistVersion,
    required this.itemCount,
    required this.downloadedCount,
    required this.purgedCount,
  });

  final int playlistVersion;
  final int itemCount;
  final int downloadedCount;
  final int purgedCount;
}

class SyncService {
  SyncService({
    required this.api,
    required this.db,
    required this.storage,
    required this.deviceId,
    Dio? downloadClient,
    MediaDownloader? downloader,
  }) : _downloader =
            downloader ?? MediaDownloader(dio: downloadClient ?? Dio());

  final SyncApiClient api;
  final AppDatabase db;
  final CacheStorage storage;
  final String deviceId;
  final MediaDownloader _downloader;

  /// Performs a full sync. Returns null if the device has no playlist assigned.
  Future<SyncResult?> sync() async {
    final playlistId = await api.getMyDevicePlaylistAssignment(deviceId);
    if (playlistId == null) return null;

    final playlistJson = await api.fetchPlaylist(playlistId);
    final itemsJson = await api.fetchPlaylistItems(playlistId);
    final mediaIds =
        itemsJson.map((i) => i['media_id'] as String).toSet().toList();
    final mediaJson = await api.fetchMedia(mediaIds);

    // Upsert playlist
    await db.upsertPlaylist(
      CachedPlaylistCompanion(
        id: Value(playlistJson['id'] as String),
        establishmentId: Value(playlistJson['establishment_id'] as String),
        name: Value(playlistJson['name'] as String),
        version: Value(playlistJson['version'] as int? ?? 0),
        audioEnabled: Value((playlistJson['audio_enabled'] as bool?) ?? false),
        publishedAt: Value(
          playlistJson['published_at'] != null
              ? DateTime.parse(playlistJson['published_at'] as String)
              : null,
        ),
      ),
    );

    // Replace items atomically
    final itemCompanions = itemsJson
        .map(
          (i) => CachedPlaylistItemsCompanion(
            id: Value(i['id'] as String),
            playlistId: Value(i['playlist_id'] as String),
            mediaId: Value(i['media_id'] as String),
            position: Value(i['position'] as int),
            displayDurationSec: Value(i['display_duration_sec'] as int? ?? 10),
            startsAt: Value(
              i['starts_at'] != null
                  ? DateTime.parse(i['starts_at'] as String)
                  : null,
            ),
            endsAt: Value(
              i['ends_at'] != null
                  ? DateTime.parse(i['ends_at'] as String)
                  : null,
            ),
          ),
        )
        .toList();
    await db.replaceItems(playlistId, itemCompanions);

    // Upsert media metadata
    for (final m in mediaJson) {
      await db.upsertMedia(
        CachedMediaCompanion(
          id: Value(m['id'] as String),
          establishmentId: Value(m['establishment_id'] as String),
          type: Value(m['type'] as String),
          filePath: Value(m['file_path'] as String),
          fileSize: Value(m['file_size'] as int),
          mimeType: Value(m['mime_type'] as String),
          checksumSha256: Value(m['checksum_sha256'] as String),
          originalFilename: Value(m['original_filename'] as String),
        ),
      );
    }

    // Download missing media (best effort, retries next sync)
    var downloaded = 0;
    final total = mediaJson.length;
    for (var i = 0; i < total; i++) {
      final m = mediaJson[i];
      final mediaId = m['id'] as String;
      final cached = await db.getMedia(mediaId);
      if (cached?.localPath != null && File(cached!.localPath!).existsSync()) {
        continue;
      }
      try {
        final ext = _extensionFor(m['mime_type'] as String);
        final localFile = await storage.resolveLocalFile(mediaId, ext);
        final signedUrl = await api.signedUrlForMedia(m['file_path'] as String);

        await _downloader.downloadResumable(
          url: signedUrl,
          target: localFile,
        );

        // Verify checksum (streamed, off the UI isolate)
        final actualChecksum = await FileHasher.sha256Hex(localFile.path);
        if (actualChecksum != (m['checksum_sha256'] as String)) {
          await localFile.delete();
          throw StateError('Checksum mismatch for media $mediaId');
        }

        await db.markMediaDownloaded(mediaId, localFile.path);
        downloaded++;
      } catch (e) {
        // ignore: avoid_print
        print('Download failed for media $mediaId: $e');
      }

      // Heartbeat with progress percentage
      final progress = ((i + 1) * 100 ~/ total).clamp(0, 100);
      try {
        await api.heartbeat(deviceId, syncProgress: progress);
      } catch (_) {
        // best effort
      }
    }

    final keepIds = mediaIds.toSet();
    final purged = await storage.purgeLruIfNeeded(keepIds);

    return SyncResult(
      playlistVersion: playlistJson['version'] as int? ?? 0,
      itemCount: itemsJson.length,
      downloadedCount: downloaded,
      purgedCount: purged,
    );
  }

  String _extensionFor(String mimeType) => switch (mimeType) {
        'video/mp4' => 'mp4',
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'bin',
      };
}
