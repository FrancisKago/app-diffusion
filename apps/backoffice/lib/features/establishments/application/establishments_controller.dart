import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../auth/application/auth_controller.dart';
import '../data/establishments_repository.dart';

final establishmentsRepositoryProvider = Provider<EstablishmentsRepository>((ref) {
  return EstablishmentsRepository(ref.watch(supabaseClientProvider));
});

final establishmentsListProvider = FutureProvider<List<Establishment>>((ref) {
  return ref.watch(establishmentsRepositoryProvider).list();
});
