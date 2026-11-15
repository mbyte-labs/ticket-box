import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/api/tmdb/v3/model/credit/aggregate_credits.dart';
import 'package:ticketbox/api/tmdb/v3/model/network.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_episode_stub.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_external_ids.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_genre.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_image_set.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_page.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_season_stub.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_video.dart';
import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/api/tmdb/v3/watch_providers/tmdb_watch_providers_append.dart';

part 'show_details.freezed.dart';
part 'show_details.g.dart';

/// `/tv/{id}` with `aggregate_credits`, `external_ids`, `content_ratings`, `videos`, `images`,
/// `watch/providers`, `recommendations`, `similar` and optionally `season/N` appended — the one
/// request a show snapshot is made of.
///
/// Dates are TMDB's `yyyy-MM-dd` strings, left unparsed at this layer. Anything TMDB may omit or
/// null is nullable or defaulted so an incomplete entry (an announced show, a show with no
/// episodes yet) still parses.
@Freezed(toJson: false)
abstract class TmdbShowDetails with _$TmdbShowDetails {
  const TmdbShowDetails._();

  const factory TmdbShowDetails({
    required int id,
    String? name,
    String? overview,
    String? tagline,
    @JsonKey(name: 'first_air_date') String? firstAirDate,
    @JsonKey(name: 'last_air_date') String? lastAirDate,

    /// `Returning Series`, `Ended`, `Canceled`, ... — see `ShowStatus.fromTmdb`.
    String? status,

    /// `Scripted`, `Reality`, `Documentary`, `Miniseries`, ...
    String? type,
    @JsonKey(name: 'in_production') @Default(false) bool inProduction,
    String? homepage,
    @JsonKey(name: 'original_language') String? originalLanguage,
    @JsonKey(name: 'origin_country') @Default(<String>[]) List<String> originCountry,

    /// Often empty on current TMDB data; the per-episode `runtime` is the reliable source.
    @JsonKey(name: 'episode_run_time') @Default(<int>[]) List<int> episodeRunTime,
    @JsonKey(name: 'number_of_seasons') @Default(0) int numberOfSeasons,
    @JsonKey(name: 'number_of_episodes') @Default(0) int numberOfEpisodes,
    @Default(0) double popularity,
    @JsonKey(name: 'vote_average') @Default(0) double voteAverage,
    @JsonKey(name: 'vote_count') @Default(0) int voteCount,
    @Default(<TmdbGenre>[]) List<TmdbGenre> genres,
    @Default(<TmdbNetwork>[]) List<TmdbNetwork> networks,
    @Default(<TmdbSeasonStub>[]) List<TmdbSeasonStub> seasons,
    @JsonKey(name: 'last_episode_to_air') TmdbEpisodeStub? lastEpisodeToAir,
    @JsonKey(name: 'next_episode_to_air') TmdbEpisodeStub? nextEpisodeToAir,
    @JsonKey(name: 'external_ids') TmdbExternalIds? externalIds,
    @JsonKey(name: 'content_ratings') TmdbContentRatings? contentRatings,
    TmdbVideos? videos,
    @JsonKey(name: 'poster_path') String? posterPath,
    @JsonKey(name: 'backdrop_path') String? backdropPath,
    @JsonKey(name: 'aggregate_credits') TmdbCredits? aggregateCredits,
    TmdbImageSet? images,
    @JsonKey(name: 'watch/providers') TmdbWatchProvidersAppend? watchProviders,
    TmdbShowListPage? recommendations,
    TmdbShowListPage? similar,

    /// The full season payloads that `append_to_response=season/1,season/2,...` adds under
    /// `season/N` keys, keyed by season number. Filled by [TmdbShowDetails.fromJson], never by the
    /// generated decoder (the keys are dynamic).
    @JsonKey(includeFromJson: false, includeToJson: false) @Default(<int, TmdbSeasonDetails>{}) Map<int, TmdbSeasonDetails> appendedSeasons,
  }) = _TmdbShowDetails;

  /// Expression-bodied on purpose: freezed only wires up json_serializable for a `fromJson` of
  /// that shape; the dynamic `season/N` keys are folded in by [_withAppendedSeasons].
  factory TmdbShowDetails.fromJson(Map<String, dynamic> json) => _withAppendedSeasons(_$TmdbShowDetailsFromJson(json), json);

  static final RegExp _appendedSeasonKey = RegExp(r'^season/(\d+)$');

  static TmdbShowDetails _withAppendedSeasons(TmdbShowDetails details, Map<String, dynamic> json) {
    final seasons = <int, TmdbSeasonDetails>{};
    for (final entry in json.entries) {
      final match = _appendedSeasonKey.firstMatch(entry.key);
      final value = entry.value;
      if (match == null || value is! Map<String, dynamic>) {
        continue;
      }
      // A season that does not exist comes back as TMDB's error object under the same key
      // (`{"success": false, "status_code": 34, …}`), not as a season — skip it. Appended seasons
      // carry no `id`, so `season_number` is the discriminator.
      if (value['season_number'] is! int) {
        continue;
      }
      seasons[int.parse(match.group(1)!)] = TmdbSeasonDetails.fromJson(value);
    }
    return seasons.isEmpty ? details : details.copyWith(appendedSeasons: seasons);
  }

  /// The IMDb id from the appended `external_ids`, when present.
  String? get imdbId => externalIds?.imdbId;

  /// Recommendations when TMDB has any, otherwise the similar titles.
  List<TmdbShowListItem> get related {
    final recommended = recommendations?.results ?? const [];
    return recommended.isNotEmpty ? recommended : (similar?.results ?? const []);
  }
}

/// The `content_ratings` object appended to `/tv/{id}`: one certification per country.
@Freezed(toJson: false)
abstract class TmdbContentRatings with _$TmdbContentRatings {
  const TmdbContentRatings._();

  const factory TmdbContentRatings({@Default(<TmdbContentRating>[]) List<TmdbContentRating> results}) = _TmdbContentRatings;

  factory TmdbContentRatings.fromJson(Map<String, dynamic> json) => _$TmdbContentRatingsFromJson(json);

  /// The rating for [countryIso3166_1] (e.g. `US` → `TV-MA`), or null when that country has none.
  String? forCountry(String countryIso3166_1) {
    for (final result in results) {
      if (result.iso3166_1 == countryIso3166_1 && result.rating != null && result.rating!.isNotEmpty) {
        return result.rating;
      }
    }
    return null;
  }
}

@Freezed(toJson: false)
abstract class TmdbContentRating with _$TmdbContentRating {
  const factory TmdbContentRating({@JsonKey(name: 'iso_3166_1') required String iso3166_1, String? rating}) = _TmdbContentRating;

  factory TmdbContentRating.fromJson(Map<String, dynamic> json) => _$TmdbContentRatingFromJson(json);
}
