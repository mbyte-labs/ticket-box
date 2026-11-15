import 'package:freezed_annotation/freezed_annotation.dart';

part 'tmdb_list_item.freezed.dart';
part 'tmdb_list_item.g.dart';

/// A movie row as the list endpoints (`search/movie`, `discover/movie`, `trending/movie/*`,
/// `movie/{id}/recommendations|similar`) return it — the details payload minus the heavy parts.
@Freezed(toJson: false)
abstract class TmdbMovieListItem with _$TmdbMovieListItem {
  const factory TmdbMovieListItem({
    required int id,
    String? title,
    @JsonKey(name: 'release_date') String? releaseDate,
    @JsonKey(name: 'vote_average') @Default(0) double voteAverage,
    @JsonKey(name: 'vote_count') @Default(0) int voteCount,
    @Default(0) double popularity,
    @JsonKey(name: 'genre_ids') @Default(<int>[]) List<int> genreIds,
    @JsonKey(name: 'poster_path') String? posterPath,
    String? overview,
  }) = _TmdbMovieListItem;

  factory TmdbMovieListItem.fromJson(Map<String, dynamic> json) => _$TmdbMovieListItemFromJson(json);
}

/// A show row as the list endpoints return it. Same stats as [TmdbMovieListItem], but TMDB names
/// the title `name` and the date `first_air_date` for TV.
@Freezed(toJson: false)
abstract class TmdbShowListItem with _$TmdbShowListItem {
  const factory TmdbShowListItem({
    required int id,
    String? name,
    @JsonKey(name: 'first_air_date') String? firstAirDate,
    @JsonKey(name: 'vote_average') @Default(0) double voteAverage,
    @JsonKey(name: 'vote_count') @Default(0) int voteCount,
    @Default(0) double popularity,
    @JsonKey(name: 'genre_ids') @Default(<int>[]) List<int> genreIds,
    @JsonKey(name: 'poster_path') String? posterPath,
    String? overview,
  }) = _TmdbShowListItem;

  factory TmdbShowListItem.fromJson(Map<String, dynamic> json) => _$TmdbShowListItemFromJson(json);
}
