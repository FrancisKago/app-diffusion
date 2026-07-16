import 'package:csv/csv.dart';

import '../data/device_detail_repository.dart';
import 'playback_log_csv_download_stub.dart'
    if (dart.library.html) 'playback_log_csv_download_web.dart';

class PlaybackLogCsvExport {
  const PlaybackLogCsvExport();

  /// Returns a CSV string with one header row + one data row per log entry.
  String serialise(
    List<PlaybackLogEntry> logs, {
    Map<String, String>? mediaNames,
  }) {
    final rows = <List<dynamic>>[
      [
        'played_at_utc',
        'media_id',
        'media_name',
        'duration_played_sec',
        'play_count',
      ],
    ];
    for (final log in logs) {
      rows.add([
        log.playedAt.toUtc().toIso8601String(),
        log.mediaId ?? '',
        mediaNames?[log.mediaId] ?? '',
        log.durationPlayedSec,
        log.playCount,
      ]);
    }
    return const ListToCsvConverter().convert(rows);
  }

  /// Triggers a browser download of the CSV (no-op outside Flutter Web).
  void download(String csv, String filename) {
    downloadCsv(csv, filename);
  }
}
