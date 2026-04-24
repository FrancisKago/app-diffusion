import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PairingRepository {
  PairingRepository(this._client);
  final SupabaseClient _client;

  Future<void> claim({required String code, required String deviceId}) async {
    try {
      final response = await _client.functions.invoke(
        'claim-pairing-code',
        body: {'code': code, 'device_id': deviceId},
      );
      if (response.status >= 400) {
        final data = response.data;
        final err = (data is Map) ? data['error'] : data;
        throw AppException('Appairage échoué', cause: err);
      }
    } on FunctionException catch (e) {
      throw AppException('Appairage échoué', cause: e.details);
    }
  }
}
