import 'package:freezed_annotation/freezed_annotation.dart';

part 'admin_diagnostic.freezed.dart';

@freezed
class AdminDiagnostic with _$AdminDiagnostic {
  const factory AdminDiagnostic({
    required String appVersion,
    required String deviceId,
    String? establishmentName,
    DateTime? lastSyncOk,
    required bool foregroundServiceRunning,
    required bool batteryOptimExcluded,
  }) = _AdminDiagnostic;
}
