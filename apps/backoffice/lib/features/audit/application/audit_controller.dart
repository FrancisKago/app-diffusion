import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/audit_repository.dart';

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return AuditRepository(ref.watch(supabaseClientProvider));
});

class AuditFilter {
  const AuditFilter({this.eventType, this.since});
  final String? eventType;
  final DateTime? since;
}

final auditFilterProvider = StateProvider<AuditFilter>((ref) {
  return AuditFilter(since: DateTime.now().subtract(const Duration(days: 7)));
});

final auditEventsProvider = FutureProvider<List<AuditEvent>>((ref) {
  final filter = ref.watch(auditFilterProvider);
  return ref.watch(auditRepositoryProvider).list(
        eventType: filter.eventType,
        since: filter.since,
      );
});
