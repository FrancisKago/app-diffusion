import 'package:freezed_annotation/freezed_annotation.dart';

part 'establishment.freezed.dart';
part 'establishment.g.dart';

@freezed
class Establishment with _$Establishment {
  const factory Establishment({
    required String id,
    required String name,
    @Default('UTC') String timezone,
  }) = _Establishment;

  factory Establishment.fromJson(Map<String, dynamic> json) =>
      _$EstablishmentFromJson(json);
}
