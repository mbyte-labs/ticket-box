import 'package:json_annotation/json_annotation.dart';

enum ResultState {
  @JsonValue('not_loaded')
  notLoaded,
  @JsonValue('processing')
  processing,
  @JsonValue('loaded')
  loaded,
  @JsonValue('error')
  error,
}
