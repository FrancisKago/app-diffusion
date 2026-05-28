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
    try {
      await _client.from('devices').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw AppException('Suppression échouée', cause: e.message);
    }
  }
}
