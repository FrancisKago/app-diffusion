import 'package:freezed_annotation/freezed_annotation.dart';

part 'media.freezed.dart';
part 'media.g.dart';

enum MediaType {
  video,
  image;

  String get dbValue => name;

  static MediaType fromString(String v) => switch (v) {
        'video' => MediaType.video,
        'image' => MediaType.image,
        _ => throw ArgumentError.value(v, 'value', 'unknown media type'),
      };
}

class _MediaTypeConverter implements JsonConverter<MediaType, String> {
  const _MediaTypeConverter();
  @override
  MediaType fromJson(String json) => MediaType.fromString(json);
  @override
  String toJson(MediaType object) => object.dbValue;
}

@freezed
class Media with _$Media {
  const factory Media({
    required String id,
    @JsonKey(name: 'establishment_id') required String establishmentId,
    @JsonKey(name: 'owner_id') String? ownerId,
    @_MediaTypeConverter() required MediaType type,
    @JsonKey(name: 'file_path') required String filePath,
    @JsonKey(name: 'file_size') required int fileSize,
    @JsonKey(name: 'duration_sec') int? durationSec,
    int? width,
    int? height,
    @JsonKey(name: 'mime_type') required String mimeType,
    @JsonKey(name: 'checksum_sha256') required String checksumSha256,
    @JsonKey(name: 'original_filename') required String originalFilename,
  }) = _Media;

  factory Media.fromJson(Map<String, dynamic> json) =>
      _$MediaFromJson(json);
}
