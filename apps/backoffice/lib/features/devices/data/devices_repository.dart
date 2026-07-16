import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DevicesRepository {
  DevicesRepository(this._client);
  final SupabaseClient _client;

  /// Realtime stream of the device list, scoped by RLS. Emits a fresh list on
  /// every insert/update/delete on `public.devices` (heartbeats, sync
  /// progress, revocation, assignments). Replaces the former 30s polling.
  Stream<List<Device>> watch() {
    return _client
        .from('devices')
        .stream(primaryKey: ['id'])
        .order('name')
        .map(
          (rows) => rows
              .map((r) => Device.fromJson(Map<String, dynamic>.from(r)))
              .toList(),
        );
  }

  Future<Device> create({
    required String establishmentId,
    required String name,
    required DeviceOrientation orientation,
  }) async {
    try {
      final row = await _client.from('devices').insert({
        'establishment_id': establishmentId,
        'name': name,
        'orientation': orientation.dbValue,
      }).select().single();
      return Device.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Création device échouée', cause: e.message);
    }
  }

  Future<void> revoke(String id) async {
    try {
      final response = await _client.functions.invoke(
        'revoke-device',
        body: {'deviceId': id},
      );
      if (response.status != 200) {
        throw AppException(
          'Révocation échouée',
          cause: 'Edge function returned status ${response.status}',
        );
      }
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Révocation échouée', cause: e.toString());
    }
  }

  Future<void> delete(String id) async {
    // A device can own >1M playback_logs; a direct delete cascades over all of
    // them in one statement and hits the 8s timeout. admin_delete_device clears
    // children in bounded batches — loop until it reports done. 20k/batch stays
    // safely under the timeout even while the kiosk is still writing logs; a
    // rare transient timeout (57014) is retried since the RPC is resumable.
    const batch = 20000;
    const maxIterations = 5000;
    var timeouts = 0;
    for (var i = 0; i < maxIterations; i++) {
      try {
        final done = await _client.rpc('admin_delete_device', params: {
          'p_id': id,
          'p_batch': batch,
        }) as bool;
        if (done) return;
        timeouts = 0;
      } on PostgrestException catch (e) {
        if (e.code == '57014' && timeouts < 60) {
          timeouts++;
          continue; // transient statement timeout — resume next batch
        }
        throw AppException('Suppression échouée', cause: e.message);
      }
    }
    throw AppException(
      'Suppression échouée',
      cause: 'Trop de données à purger — réessayez.',
    );
  }
}
