import 'dart:typed_data';
import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class MediaUploadInput {
  const MediaUploadInput({
    required this.establishmentId,
    required this.type,
    required this.bytes,
    required this.mimeType,
    required this.checksum,
    required this.originalFilename,
    this.durationSec,
    this.width,
    this.height,
  });

  final String establishmentId;
  final MediaType type;
  final Uint8List bytes;
  final String mimeType;
  final String checksum;
  final String originalFilename;
  final int? durationSec;
  final int? width;
  final int? height;
}

/// A media plus which playlists reference it. Used to surface obsolete
/// (unused) media and to explain why a used one cannot be deleted.
class MediaWithUsage {
  const MediaWithUsage({
    required this.media,
    required this.playlistCount,
    required this.playlistNames,
  });

  final Media media;

  /// Number of distinct playlists referencing this media.
  final int playlistCount;

  /// Distinct, sorted playlist names referencing this media (for display).
  /// May be shorter than [playlistCount] if a name was not readable under RLS.
  final List<String> playlistNames;

  int get usageCount => playlistCount;
  bool get isUnused => playlistCount == 0;

  factory MediaWithUsage.fromRow(Map<String, dynamic> row) {
    final items = (row['playlist_items'] as List?) ?? const [];
    final ids = <String>{};
    final names = <String>{};
    for (final raw in items) {
      final item = Map<String, dynamic>.from(raw as Map);
      final pid = item['playlist_id'];
      if (pid is String) ids.add(pid);
      final pl = item['playlists'];
      if (pl is Map && pl['name'] is String) {
        names.add(pl['name'] as String);
      }
    }
    final mediaJson = Map<String, dynamic>.from(row)..remove('playlist_items');
    return MediaWithUsage(
      media: Media.fromJson(mediaJson),
      playlistCount: ids.length,
      playlistNames: names.toList()..sort(),
    );
  }
}

class MediaRepository {
  MediaRepository(this._client, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  static const _bucket = 'media';

  Future<List<Media>> list() async {
    try {
      final rows = await _client
          .from('media')
          .select()
          .order('created_at', ascending: false);
      return rows.map<Media>(
        (r) => Media.fromJson(Map<String, dynamic>.from(r as Map)),
      ).toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture médias échouée', cause: e.message);
    }
  }

  /// Lists media with their playlist usage, most recent first. The embedded
  /// `playlist_items(playlist_id, playlists(name))` join is RLS-scoped, so a
  /// manager only sees usage within their own establishments.
  Future<List<MediaWithUsage>> listWithUsage() async {
    try {
      final rows = await _client
          .from('media')
          .select('*, playlist_items(playlist_id, playlists(name))')
          .order('created_at', ascending: false);
      return rows
          .map<MediaWithUsage>(
            (r) => MediaWithUsage.fromRow(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture médias échouée', cause: e.message);
    }
  }

  Future<Media> upload(MediaUploadInput input) async {
    final id = _uuid.v4();
    final ext = _extensionFor(input.mimeType);
    final filePath = '${input.establishmentId}/$id.$ext';

    try {
      await _client.storage.from(_bucket).uploadBinary(
            filePath,
            input.bytes,
            fileOptions: FileOptions(
              contentType: input.mimeType,
              upsert: false,
            ),
          );
    } on StorageException catch (e) {
      throw AppException('Upload échoué', cause: e.message);
    }

    try {
      final row = await _client.from('media').insert({
        'id': id,
        'establishment_id': input.establishmentId,
        'type': input.type.dbValue,
        'file_path': filePath,
        'file_size': input.bytes.length,
        'duration_sec': input.durationSec,
        'width': input.width,
        'height': input.height,
        'mime_type': input.mimeType,
        'checksum_sha256': input.checksum,
        'original_filename': input.originalFilename,
      }).select().single();
      return Media.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      // Roll back the storage object on metadata failure
      await _client.storage.from(_bucket).remove([filePath])
          .catchError((_) => <FileObject>[]);
      throw AppException('Insertion média échouée', cause: e.message);
    }
  }

  Future<void> delete(Media media) async {
    try {
      await _client.from('media').delete().eq('id', media.id);
      await _client.storage.from(_bucket).remove([media.filePath]);
    } on PostgrestException catch (e) {
      // 23503 = foreign_key_violation: the media is still referenced by a
      // playlist_items row (FK is `on delete restrict`).
      if (e.code == '23503') {
        throw AppException(
          'Média utilisé dans une ou plusieurs playlists',
          cause: 'Retirez-le des playlists concernées avant de le supprimer.',
        );
      }
      throw AppException('Suppression échouée', cause: e.message);
    } on StorageException catch (e) {
      throw AppException('Suppression Storage échouée', cause: e.message);
    }
  }

  /// Deletes several media (DB rows + storage objects). Intended for purging
  /// unused media in bulk; a used media raises the same explicit error as
  /// [delete]. Returns the number successfully deleted.
  Future<int> deleteMany(List<Media> media) async {
    var deleted = 0;
    for (final m in media) {
      await delete(m);
      deleted++;
    }
    return deleted;
  }

  Future<String> signedUrl(Media media, {int expiresInSeconds = 3600}) async {
    try {
      return await _client.storage
          .from(_bucket)
          .createSignedUrl(media.filePath, expiresInSeconds);
    } on StorageException catch (e) {
      throw AppException('URL signée échouée', cause: e.message);
    }
  }

  /// Purges storage objects with no matching media row (admin only, via Edge
  /// Function). With [dryRun] true, only counts them. Returns
  /// (orphanCount, deleted).
  Future<({int orphanCount, int deleted})> purgeOrphanStorage({
    bool dryRun = true,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'purge-orphan-media',
        body: {'dryRun': dryRun},
      );
      if (response.status >= 400) {
        final data = response.data;
        final err = (data is Map) ? data['error'] : data;
        throw AppException('Purge stockage échouée', cause: err);
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      return (
        orphanCount: (data['orphanCount'] as num?)?.toInt() ?? 0,
        deleted: (data['deleted'] as num?)?.toInt() ?? 0,
      );
    } on FunctionException catch (e) {
      throw AppException('Purge stockage échouée', cause: e.details);
    }
  }
}

String _extensionFor(String mimeType) => switch (mimeType) {
      'video/mp4' => 'mp4',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'bin',
    };
