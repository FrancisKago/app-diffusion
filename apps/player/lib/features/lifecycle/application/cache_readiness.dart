/// A media referenced by the active playlist, with the local path the player
/// expects its binary at (null until downloaded).
class MediaRef {
  const MediaRef({required this.filename, required this.localPath});
  final String filename;
  final String? localPath;
}

/// How ready the local cache is to play the active playlist: how many of its
/// distinct media are actually present on disk, and which are missing.
///
/// This is the single most useful field for diagnosing "device is stuck on
/// standby / black screen": a non-empty [missing] list means playback cannot
/// start because the binaries never finished downloading.
class CacheReadiness {
  const CacheReadiness({
    required this.total,
    required this.downloaded,
    required this.missing,
  });

  final int total;
  final int downloaded;
  final List<String> missing;

  bool get isReady => total > 0 && downloaded == total;
}

/// Pure computation over already-distinct [medias]. [fileExists] is injected so
/// this is testable without touching the filesystem.
CacheReadiness computeCacheReadiness(
  Iterable<MediaRef> medias,
  bool Function(String path) fileExists,
) {
  var total = 0;
  var downloaded = 0;
  final missing = <String>[];
  for (final m in medias) {
    total++;
    final present = m.localPath != null && fileExists(m.localPath!);
    if (present) {
      downloaded++;
    } else {
      missing.add(m.filename);
    }
  }
  return CacheReadiness(
    total: total,
    downloaded: downloaded,
    missing: missing,
  );
}
