import 'package:freezed_annotation/freezed_annotation.dart';

part 'device.freezed.dart';
part 'device.g.dart';

enum DeviceOrientation {
  landscape,
  portrait;

  String get dbValue => name;

  static DeviceOrientation fromString(String value) {
    return switch (value) {
      'landscape' => DeviceOrientation.landscape,
      'portrait' => DeviceOrientation.portrait,
      _ => DeviceOrientation.landscape,
    };
  }
}

class _OrientationConverter
    implements JsonConverter<DeviceOrientation, String?> {
  const _OrientationConverter();
  @override
  DeviceOrientation fromJson(String? json) => json == null
      ? DeviceOrientation.landscape
      : DeviceOrientation.fromString(json);
  @override
  String toJson(DeviceOrientation object) => object.dbValue;
}

@freezed
class Device with _$Device {
  const factory Device({
    required String id,
    @JsonKey(name: 'establishment_id') required String establishmentId,
    required String name,
    @_OrientationConverter()
    @Default(DeviceOrientation.landscape)
    DeviceOrientation orientation,
    @JsonKey(name: 'last_seen_at') DateTime? lastSeenAt,
    @JsonKey(name: 'sync_progress') int? syncProgress,
  }) = _Device;

  factory Device.fromJson(Map<String, dynamic> json) =>
      _$DeviceFromJson(json);
}
