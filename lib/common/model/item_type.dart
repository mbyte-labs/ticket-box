import 'package:freezed_annotation/freezed_annotation.dart';

enum ItemType {
  @JsonValue('movie')
  movie,
  @JsonValue('show')
  show,
  @JsonValue('season')
  season,
  @JsonValue('episode')
  episode,
}
