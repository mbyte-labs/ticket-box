// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'network.freezed.dart';

part 'network.g.dart';

@freezed
abstract class TmdbNetwork with _$TmdbNetwork {
  const factory TmdbNetwork({
    required int id,
    required String? name,
    @JsonKey(name: 'logo_path') required String? logoPath,
    @JsonKey(name: 'origin_country') required String? originCountry,
  }) = _TmdbNetwork;

  factory TmdbNetwork.fromJson(Map<String, dynamic> json) => _$TmdbNetworkFromJson(json);
}
