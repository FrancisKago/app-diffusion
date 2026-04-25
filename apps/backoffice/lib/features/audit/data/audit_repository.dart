import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuditEvent {
  const AuditEvent({
    required this.id,
    this.actorId,
    required this.actorType,
    required this.eventType,
    this.targetId,
    this.metadata,
    required this.createdAt,
  });

  final int id;
  final String? actorId;
  final String actorType;
  final String eventType;
  final String? targetId;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  factory AuditEvent.fromJson(Map<String, dynamic> json) => AuditEvent(
        id: json['id'] as int,
        actorId: json['actor_id'] as String?,
        actorType: json['actor_type'] as String,
        eventType: json['event_type'] as String,
        targetId: json['target_id'] as String?,
        metadata: json['metadata'] == null
            ? null
            : Map<String, dynamic>.from(json['metadata'] as Map),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class AuditRepository {
  AuditRepository(this._client);
  final SupabaseClient _client;

  Future<List<AuditEvent>> list({
    int limit = 100,
    String? eventType,
    DateTime? since,
  }) async {
    try {
      var query = _client.from('audit_events').select();
      if (eventType != null && eventType.isNotEmpty) {
        query = query.eq('event_type', eventType);
      }
      if (since != null) {
        query = query.gte('created_at', since.toUtc().toIso8601String());
      }
      final rows = await query.order('created_at', ascending: false).limit(limit);
      return rows
          .map<AuditEvent>(
            (r) => AuditEvent.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture audit log échouée', cause: e.message);
    }
  }
}
