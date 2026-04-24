import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../auth/application/auth_controller.dart';
import '../data/devices_repository.dart';
import '../data/pairing_repository.dart';

final devicesRepositoryProvider = Provider<DevicesRepository>((ref) {
  return DevicesRepository(ref.watch(supabaseClientProvider));
});

final devicesListProvider = FutureProvider<List<Device>>((ref) {
  return ref.watch(devicesRepositoryProvider).list();
});

final pairingRepositoryProvider = Provider<PairingRepository>((ref) {
  return PairingRepository(ref.watch(supabaseClientProvider));
});
