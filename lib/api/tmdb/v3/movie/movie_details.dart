import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/api/tmdb/v3/model/credit/aggregate_credits.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_external_ids.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_genre.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_image_set.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_page.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_video.dart';
import 'package:ticketbox/api/tmdb/v3/watch_providers/tmdb_watch_providers_append.dart';

part 'movie_details.freezed.dart';
part 'movie_details.g.dart';

/// `/movie/{id}` with `credits`, `external_ids`, `videos`, `images`, `watch/providers`,
/// `recommendations`, `similar` and `release_dates` appended — the one request a movie snapshot
/// is made of. Every appended object is nullable so a payload that lacks one still parses.
@Freezed(toJson: false)
abstract class TmdbMovieDetails with _$TmdbMovieDetails {
  const TmdbMovieDetails._();

  const factory TmdbMovieDetails({
    required int id,
    String? title,
    String? overview,
    String? tagline,
    @JsonKey(name: 'release_date') String? releaseDate,

    /// Minutes; null or 0 when TMDB does not know it.
    int? runtime,

    /// `Rumored`, `Planned`, `In Production`, `Post Production`, `Released`, `Canceled` — see
    /// `MovieStatus.fromTmdb`.
    String? status,
    String? homepage,

    /// The top-level `imdb_id`; the same value is also under `external_ids` when appended.
    @JsonKey(name: 'imdb_id') String? imdbId,
    @JsonKey(name: 'original_language') String? originalLanguage,
    @JsonKey(name: 'production_countries') @Default(<TmdbProductionCountry>[]) List<TmdbProductionCountry> productionCountries,
    @Default(0) double popularity,
    @JsonKey(name: 'vote_average') @Default(0) double voteAverage,
    @JsonKey(name: 'vote_count') @Default(0) int voteCount,
    @Default(<TmdbGenre>[]) List<TmdbGenre> genres,
    @JsonKey(name: 'release_dates') TmdbReleaseDates? releaseDates,
    TmdbVideos? videos,
    @JsonKey(name: 'external_ids') TmdbExternalIds? externalIds,
    @JsonKey(name: 'poster_path') String? posterPath,
    @JsonKey(name: 'backdrop_path') String? backdropPath,
    TmdbCredits? credits,
    TmdbImageSet? images,
    @JsonKey(name: 'watch/providers') TmdbWatchProvidersAppend? watchProviders,
    TmdbMovieListPage? recommendations,
    TmdbMovieListPage? similar,
  }) = _TmdbMovieDetails;

  factory TmdbMovieDetails.fromJson(Map<String, dynamic> json) => _$TmdbMovieDetailsFromJson(json);

  /// Recommendations when TMDB has any, otherwise the similar titles — the *Similar* row is
  /// rarely empty that way.
  List<TmdbMovieListItem> get related {
    final recommended = recommendations?.results ?? const [];
    return recommended.isNotEmpty ? recommended : (similar?.results ?? const []);
  }
}

@Freezed(toJson: false)
abstract class TmdbProductionCountry with _$TmdbProductionCountry {
  const factory TmdbProductionCountry({@JsonKey(name: 'iso_3166_1') required String iso3166_1, String? name}) = _TmdbProductionCountry;

  factory TmdbProductionCountry.fromJson(Map<String, dynamic> json) => _$TmdbProductionCountryFromJson(json);
}

/// The `release_dates` object appended to `/movie/{id}`: per country, every release with its
/// certification.
@Freezed(toJson: false)
abstract class TmdbReleaseDates with _$TmdbReleaseDates {
  const TmdbReleaseDates._();

  const factory TmdbReleaseDates({@Default(<TmdbCountryReleaseDates>[]) List<TmdbCountryReleaseDates> results}) = _TmdbReleaseDates;

  factory TmdbReleaseDates.fromJson(Map<String, dynamic> json) => _$TmdbReleaseDatesFromJson(json);

  /// The first non-empty certification for [countryIso3166_1] (e.g. `US` → `PG-13`), or null.
  String? certificationForCountry(String countryIso3166_1) {
    for (final country in results) {
      if (country.iso3166_1 != countryIso3166_1) {
        continue;
      }
      for (final release in country.releaseDates) {
        if (release.certification != null && release.certification!.isNotEmpty) {
          return release.certification;
        }
      }
    }
    return null;
  }
}

@Freezed(toJson: false)
abstract class TmdbCountryReleaseDates with _$TmdbCountryReleaseDates {
  const factory TmdbCountryReleaseDates({
    @JsonKey(name: 'iso_3166_1') required String iso3166_1,
    @JsonKey(name: 'release_dates') @Default(<TmdbReleaseDate>[]) List<TmdbReleaseDate> releaseDates,
  }) = _TmdbCountryReleaseDates;

  factory TmdbCountryReleaseDates.fromJson(Map<String, dynamic> json) => _$TmdbCountryReleaseDatesFromJson(json);
}

/// One release in one country. [type]: 1 Premiere, 2 Theatrical (limited), 3 Theatrical,
/// 4 Digital, 5 Physical, 6 TV. [releaseDate] is an ISO-8601 timestamp, not a bare date.
@Freezed(toJson: false)
abstract class TmdbReleaseDate with _$TmdbReleaseDate {
  const factory TmdbReleaseDate({String? certification, int? type, @JsonKey(name: 'release_date') String? releaseDate}) = _TmdbReleaseDate;

  factory TmdbReleaseDate.fromJson(Map<String, dynamic> json) => _$TmdbReleaseDateFromJson(json);
}
