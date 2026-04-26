import 'package:backoffice/features/devices/application/playback_log_csv_export.dart';
import 'package:backoffice/features/devices/data/device_detail_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serialise produces header row + one row per entry', () {
    final logs = [
      PlaybackLogEntry(
        id: 1,
        deviceId: 'd1',
        mediaId: 'm1',
        playedAt: DateTime.utc(2026, 4, 25, 12),
        durationPlayedSec: 30,
      ),
      PlaybackLogEntry(
        id: 2,
        deviceId: 'd1',
        playedAt: DateTime.utc(2026, 4, 25, 13),
        durationPlayedSec: 10,
      ),
    ];
    final csv = const PlaybackLogCsvExport()
        .serialise(logs, mediaNames: {'m1': 'demo.mp4'});
    final lines = csv.split('\r\n');
    expect(lines[0], 'played_at_utc,media_id,media_name,duration_played_sec');
    expect(lines[1], '2026-04-25T12:00:00.000Z,m1,demo.mp4,30');
    // For the second entry, mediaId is null → empty fields
    expect(lines[2], '2026-04-25T13:00:00.000Z,,,10');
  });
}
