import 'package:freezed_annotation/freezed_annotation.dart';
import 'user_role.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

class _UserRoleConverter implements JsonConverter<UserRole, String> {
  const _UserRoleConverter();
  @override
  UserRole fromJson(String json) => UserRole.fromString(json);
  @override
  String toJson(UserRole object) => object.dbValue;
}

@freezed
class Profile with _$Profile {
  const factory Profile({
    required String id,
    @_UserRoleConverter() required UserRole role,
    // ignore: invalid_annotation_target
    @JsonKey(name: 'full_name') required String fullName,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
}
