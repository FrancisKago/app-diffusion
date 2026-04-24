import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManagerWithEstablishments {
  ManagerWithEstablishments({
    required this.profile,
    required this.establishmentIds,
  });
  final Profile profile;
  final List<String> establishmentIds;
}

class ManagersRepository {
  ManagersRepository(this._client);
  final SupabaseClient _client;

  Future<List<ManagerWithEstablishments>> list() async {
    try {
      final rows = await _client
          .from('profiles')
          .select('id, role, full_name, establishment_managers(establishment_id)')
          .eq('role', 'manager')
          .order('full_name');
      return rows.map<ManagerWithEstablishments>((row) {
        final rowMap = Map<String, dynamic>.from(row as Map);
        final links = (rowMap['establishment_managers'] as List)
            .map((l) => (l as Map)['establishment_id'] as String)
            .toList();
        return ManagerWithEstablishments(
          profile: Profile.fromJson({
            'id': rowMap['id'],
            'role': rowMap['role'],
            'full_name': rowMap['full_name'],
          }),
          establishmentIds: links,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture gérants échouée', cause: e.message);
    }
  }

  Future<void> create({
    required String email,
    required String password,
    required String fullName,
    required List<String> establishmentIds,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-manager',
        body: {
          'email': email,
          'password': password,
          'full_name': fullName,
          'establishment_ids': establishmentIds,
        },
      );
      if (response.status >= 400) {
        final data = response.data;
        final err = (data is Map) ? data['error'] : data;
        throw AppException('Création gérant échouée', cause: err);
      }
    } on FunctionException catch (e) {
      throw AppException('Création gérant échouée', cause: e.details);
    }
  }
}
