import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceCredentials {
  const DeviceCredentials({required this.deviceId, required this.jwt});
  final String deviceId;
  final String jwt;
}

class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kDeviceId = 'device_id';
  static const _kJwt = 'device_jwt';

  Future<DeviceCredentials?> readCredentials() async {
    final deviceId = await _storage.read(key: _kDeviceId);
    final jwt = await _storage.read(key: _kJwt);
    if (deviceId == null || jwt == null) return null;
    return DeviceCredentials(deviceId: deviceId, jwt: jwt);
  }

  Future<void> writeCredentials(DeviceCredentials creds) async {
    await _storage.write(key: _kDeviceId, value: creds.deviceId);
    await _storage.write(key: _kJwt, value: creds.jwt);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kDeviceId);
    await _storage.delete(key: _kJwt);
  }
}
