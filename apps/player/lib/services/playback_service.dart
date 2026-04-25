import 'package:player/data/local/app_database.dart';

class PlaybackService {
  /// Returns items active at [now] : those without dates, OR within [starts_at, ends_at].
  static List<CachedPlaylistItem> activeItems(
    List<CachedPlaylistItem> items,
    DateTime now,
  ) {
    return items.where((i) {
      if (i.startsAt != null && now.isBefore(i.startsAt!)) return false;
      if (i.endsAt != null && now.isAfter(i.endsAt!)) return false;
      return true;
    }).toList();
  }
}
