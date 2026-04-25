import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:player/data/local/app_database.dart';

class CacheStorage {
  CacheStorage(this._db);

  final AppDatabase _db;

  /// 2 GB cap by default.
  static const int maxCacheBytes = 2 * 1024 * 1024 * 1024;

  Future<Directory> mediaDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'media'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> resolveLocalFile(String mediaId, String extension) async {
    final dir = await mediaDir();
    return File(p.join(dir.path, '$mediaId.$extension'));
  }

  Future<int> currentSize() async {
    final all = await _db.getAllMedia();
    return all
        .where((m) => m.localPath != null)
        .fold<int>(0, (sum, m) => sum + m.fileSize);
  }

  /// Purges least-recently-used cached media until total size <= [maxCacheBytes].
  /// Skips media currently referenced in the active playlist (passed in [keepIds]).
  Future<int> purgeLruIfNeeded(Set<String> keepIds) async {
    var size = await currentSize();
    if (size <= maxCacheBytes) return 0;

    final all = await _db.getAllMedia();
    final purgeable = all
        .where((m) => m.localPath != null && !keepIds.contains(m.id))
        .toList()
      ..sort(
        (a, b) => (a.lastUsedAt ?? 0).compareTo(b.lastUsedAt ?? 0),
      );

    var purged = 0;
    for (final m in purgeable) {
      if (size <= maxCacheBytes) break;
      try {
        final f = File(m.localPath!);
        if (f.existsSync()) {
          await f.delete();
        }
      } catch (_) {
        // Best effort
      }
      await _db.deleteMedia(m.id);
      size -= m.fileSize;
      purged++;
    }
    return purged;
  }
}
