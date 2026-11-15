// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

part 'image.freezed.dart';

part 'image.g.dart';

@freezed
abstract class TmdbImage with _$TmdbImage {
  const factory TmdbImage({
    @JsonKey(name: 'aspect_ratio') required double aspectRatio,
    @JsonKey(name: 'file_path') required String filePath,
    @JsonKey(name: 'vote_average') required double voteAverage,
    @JsonKey(name: 'vote_count') required int voteCount,
    @JsonKey(name: 'height') required int height,
    @JsonKey(name: 'width') required int width,

    /// The iso_639_1 of the language the image is in
    /// Example: en_US
    @JsonKey(name: 'iso_639_1') required String? language,
  }) = _TmdbImage;

  factory TmdbImage.fromJson(Map<String, dynamic> json) => _$TmdbImageFromJson(json);
}
