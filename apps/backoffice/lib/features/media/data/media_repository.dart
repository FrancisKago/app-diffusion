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
      throw AppException('Suppression échouée', cause: e.message);
    } on StorageException catch (e) {
      throw AppException('Suppression Storage échouée', cause: e.message);
    }
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
}

String _extensionFor(String mimeType) => switch (mimeType) {
      'video/mp4' => 'mp4',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'bin',
    };
