import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/managers_repository.dart';

final managersRepositoryProvider = Provider<ManagersRepository>((ref) {
  return ManagersRepository(ref.watch(supabaseClientProvider));
});

final managersListProvider =
    FutureProvider<List<ManagerWithEstablishments>>((ref) {
  return ref.watch(managersRepositoryProvider).list();
});
