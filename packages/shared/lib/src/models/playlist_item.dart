import 'package:freezed_annotation/freezed_annotation.dart';

part 'playlist_item.freezed.dart';
part 'playlist_item.g.dart';

@freezed
class PlaylistItem with _$PlaylistItem {
  const factory PlaylistItem({
    required String id,
    @JsonKey(name: 'playlist_id') required String playlistId,
    @JsonKey(name: 'media_id') required String mediaId,
    required int position,
    @JsonKey(name: 'display_duration_sec') @Default(10) int displayDurationSec,
    @JsonKey(name: 'starts_at') DateTime? startsAt,
    @JsonKey(name: 'ends_at') DateTime? endsAt,
  }) = _PlaylistItem;

  factory PlaylistItem.fromJson(Map<String, dynamic> json) =>
      _$PlaylistItemFromJson(json);
}
