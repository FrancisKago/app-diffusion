import 'package:shared/shared.dart';

class EstablishmentsRepository {
  EstablishmentsRepository(this._client);
  final SupabaseClient _client;

  Future<List<Establishment>> list() async {
    try {
      final rows = await _client.from('establishments').select().order('name');
      return rows.map<Establishment>(
        (row) => Establishment.fromJson(Map<String, dynamic>.from(row as Map)),
      ).toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture des établissements échouée', cause: e.message);
    }
  }

  Future<Establishment> create({
    required String name,
    required String timezone,
  }) async {
    try {
      final row = await _client
          .from('establishments')
          .insert({'name': name, 'timezone': timezone})
          .select()
          .single();
      return Establishment.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Création échouée', cause: e.message);
    }
  }

  Future<Establishment> update({
    required String id,
    required String name,
    required String timezone,
  }) async {
    try {
      final row = await _client
          .from('establishments')
          .update({'name': name, 'timezone': timezone})
          .eq('id', id)
          .select()
          .single();
      return Establishment.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Mise à jour échouée', cause: e.message);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from('establishments').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw AppException('Suppression échouée', cause: e.message);
    }
  }
}
