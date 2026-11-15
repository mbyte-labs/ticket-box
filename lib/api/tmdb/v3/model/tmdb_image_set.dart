import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/api/tmdb/v3/model/image.dart';

part 'tmdb_image_set.freezed.dart';
part 'tmdb_image_set.g.dart';

/// The `images` object `append_to_response=images` adds to movie, show and season details (sent
/// with `include_image_language=en,null`, so language-less artwork is not filtered out by the
/// request's `language=en-US`). Every list is empty when TMDB has nothing of that kind; movies and
/// shows carry posters and backdrops, seasons posters, episodes stills.
@Freezed(toJson: false)
abstract class TmdbImageSet with _$TmdbImageSet {
  const factory TmdbImageSet({
    @Default(<TmdbImage>[]) List<TmdbImage> posters,
    @Default(<TmdbImage>[]) List<TmdbImage> backdrops,
    @Default(<TmdbImage>[]) List<TmdbImage> stills,
  }) = _TmdbImageSet;

  factory TmdbImageSet.fromJson(Map<String, dynamic> json) => _$TmdbImageSetFromJson(json);
}
