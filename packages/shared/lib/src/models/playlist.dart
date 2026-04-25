import 'package:freezed_annotation/freezed_annotation.dart';

part 'playlist.freezed.dart';
part 'playlist.g.dart';

@freezed
class Playlist with _$Playlist {
  const factory Playlist({
    required String id,
    @JsonKey(name: 'establishment_id') required String establishmentId,
    required String name,
    @JsonKey(name: 'is_default') @Default(false) bool isDefault,
    @JsonKey(name: 'audio_enabled') @Default(false) bool audioEnabled,
    @Default(0) int version,
    @JsonKey(name: 'published_at') DateTime? publishedAt,
  }) = _Playlist;

  factory Playlist.fromJson(Map<String, dynamic> json) =>
      _$PlaylistFromJson(json);
}
