// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/api/tmdb/v3/model/image.dart';

part 'person_image_response.g.dart';

@JsonSerializable(createToJson: false)
class TmdbPersonImageResponse {
  @JsonKey(name: 'id')
  final int tmdbId;
  @JsonKey(name: 'profiles', defaultValue: [])
  final List<TmdbImage> profiles;

  const TmdbPersonImageResponse(this.tmdbId, this.profiles);

  factory TmdbPersonImageResponse.fromJson(Map<String, dynamic> json) => _$TmdbPersonImageResponseFromJson(json);
}
