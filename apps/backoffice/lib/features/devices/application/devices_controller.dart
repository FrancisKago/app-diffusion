import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../auth/application/auth_controller.dart';
import '../data/device_detail_repository.dart';
import '../data/devices_repository.dart';
import '../data/pairing_repository.dart';

final devicesRepositoryProvider = Provider<DevicesRepository>((ref) {
  return DevicesRepository(ref.watch(supabaseClientProvider));
});

final devicesListProvider = StreamProvider<List<Device>>((ref) {
  return ref.watch(devicesRepositoryProvider).watch();
});

final pairingRepositoryProvider = Provider<PairingRepository>((ref) {
  return PairingRepository(ref.watch(supabaseClientProvider));
});

final deviceDetailRepositoryProvider = Provider<DeviceDetailRepository>((ref) {
  return DeviceDetailRepository(ref.watch(supabaseClientProvider));
});

final deviceHeartbeatsProvider =
    FutureProvider.family<List<DeviceHeartbeat>, String>((ref, deviceId) {
  return ref.watch(deviceDetailRepositoryProvider).recentHeartbeats(deviceId);
});

final devicePlaybackLogsProvider =
    FutureProvider.family<List<PlaybackLogEntry>, String>((ref, deviceId) {
  return ref.watch(deviceDetailRepositoryProvider).recentPlaybackLogs(deviceId);
});
