import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/audit_repository.dart';

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return AuditRepository(ref.watch(supabaseClientProvider));
});

class AuditFilter {
  const AuditFilter({this.eventType, this.since, this.search});
  final String? eventType;
  final DateTime? since;
  final String? search;

  AuditFilter copyWith({
    Object? eventType = _noChange,
    Object? since = _noChange,
    Object? search = _noChange,
  }) {
    return AuditFilter(
      eventType: identical(eventType, _noChange)
          ? this.eventType
          : eventType as String?,
      since: identical(since, _noChange) ? this.since : since as DateTime?,
      search:
          identical(search, _noChange) ? this.search : search as String?,
    );
  }
}

const _noChange = Object();

final auditFilterProvider = StateProvider<AuditFilter>((ref) {
  return AuditFilter(since: DateTime.now().subtract(const Duration(days: 7)));
});

/// Number of "Charger plus" pages requested. Page size is [auditPageSize].
/// Resets to 0 whenever [auditFilterProvider] changes (handled in the screen).
final auditPageProvider = StateProvider<int>((_) => 0);

const int auditPageSize = 50;

final auditEventsProvider = FutureProvider<List<AuditEvent>>((ref) {
  final filter = ref.watch(auditFilterProvider);
  final page = ref.watch(auditPageProvider);
  return ref.watch(auditRepositoryProvider).list(
        limit: auditPageSize * (page + 1),
        eventType: filter.eventType,
        since: filter.since,
        search: filter.search,
      );
});
