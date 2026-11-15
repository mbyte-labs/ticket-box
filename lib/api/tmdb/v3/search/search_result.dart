import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';

part 'search_result.freezed.dart';

/// One search hit: a movie or a show. People hits are filtered out before this is built.
@freezed
sealed class TmdbSearchResult with _$TmdbSearchResult {
  const TmdbSearchResult._();

  const factory TmdbSearchResult.movie(TmdbMovieListItem movie) = TmdbMovieSearchResult;

  const factory TmdbSearchResult.show(TmdbShowListItem show) = TmdbShowSearchResult;

  /// Parses one row of `/search/multi`, or null for a `media_type` that is neither movie nor tv
  /// (persons, collections).
  static TmdbSearchResult? fromMultiJson(Map<String, dynamic> json) {
    return switch (json['media_type']) {
      'movie' => TmdbSearchResult.movie(TmdbMovieListItem.fromJson(json)),
      'tv' => TmdbSearchResult.show(TmdbShowListItem.fromJson(json)),
      _ => null,
    };
  }

  int get tmdbId => switch (this) {
    TmdbMovieSearchResult(:final movie) => movie.id,
    TmdbShowSearchResult(:final show) => show.id,
  };

  String? get title => switch (this) {
    TmdbMovieSearchResult(:final movie) => movie.title,
    TmdbShowSearchResult(:final show) => show.name,
  };

  double get popularity => switch (this) {
    TmdbMovieSearchResult(:final movie) => movie.popularity,
    TmdbShowSearchResult(:final show) => show.popularity,
  };
}
