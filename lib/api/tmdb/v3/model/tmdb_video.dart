import 'package:freezed_annotation/freezed_annotation.dart';

part 'tmdb_video.freezed.dart';
part 'tmdb_video.g.dart';

/// The `videos` object appended to movie and show details.
@Freezed(toJson: false)
abstract class TmdbVideos with _$TmdbVideos {
  const factory TmdbVideos({@Default(<TmdbVideo>[]) List<TmdbVideo> results}) = _TmdbVideos;

  factory TmdbVideos.fromJson(Map<String, dynamic> json) => _$TmdbVideosFromJson(json);
}

/// One trailer, teaser, clip, etc. [key] is the id on [site] (e.g. a YouTube video id).
@Freezed(toJson: false)
abstract class TmdbVideo with _$TmdbVideo {
  const factory TmdbVideo({required String key, required String site, required String type, @Default(false) bool official, String? name}) =
      _TmdbVideo;

  factory TmdbVideo.fromJson(Map<String, dynamic> json) => _$TmdbVideoFromJson(json);
}
