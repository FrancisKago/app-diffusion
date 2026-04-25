import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import 'auth_controller.dart';

final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  return ref.read(authRepositoryProvider).fetchCurrentProfile();
});

final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(currentProfileProvider).maybeWhen(
        data: (p) => p?.role == UserRole.admin,
        orElse: () => false,
      );
});
