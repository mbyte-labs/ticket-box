import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/api/tmdb/v3/model/credit/person_credit.dart';

part 'season_details.freezed.dart';
part 'season_details.g.dart';

/// `/tv/{id}/season/{n}` — the season header plus every episode in it.
///
/// Also the shape of each `season/N` key `append_to_response` adds to `/tv/{id}` (see
/// `TmdbShowDetails.appendedSeasons`). `air_date` and `poster_path` are null for unaired or
/// sparsely edited seasons, so both are nullable here.
@Freezed(toJson: false)
abstract class TmdbSeasonDetails with _$TmdbSeasonDetails {
  const TmdbSeasonDetails._();

  const factory TmdbSeasonDetails({
    /// Present on `/tv/{id}/season/{n}`; **absent** when the season arrives appended to `/tv/{id}`
    /// (`append_to_response=season/N`), which only carries a Mongo-style `_id`. Callers fall back
    /// to the id from the show's `seasons[]` stubs.
    int? id,
    @JsonKey(name: 'season_number') required int seasonNumber,
    String? name,
    String? overview,
    @JsonKey(name: 'air_date') String? airDate,
    @JsonKey(name: 'poster_path') String? posterPath,
    @JsonKey(name: 'vote_average') double? voteAverage,
    @Default(<TmdbSeasonEpisode>[]) List<TmdbSeasonEpisode> episodes,
  }) = _TmdbSeasonDetails;

  factory TmdbSeasonDetails.fromJson(Map<String, dynamic> json) => _$TmdbSeasonDetailsFromJson(json);

  /// The entry for episode [episodeNumber], or null when the season does not list it.
  TmdbSeasonEpisode? episode(int episodeNumber) {
    for (final entry in episodes) {
      if (entry.episodeNumber == episodeNumber) {
        return entry;
      }
    }
    return null;
  }
}

/// One `episodes[]` entry of a season payload. Carries the community votes the season score is
/// derived from (TMDB has no season-level `vote_average` worth using) plus the episode's own
/// metadata and guest stars, so a season document is enough to render every episode page.
@Freezed(toJson: false)
abstract class TmdbSeasonEpisode with _$TmdbSeasonEpisode {
  const factory TmdbSeasonEpisode({
    required int id,
    @JsonKey(name: 'episode_number') required int episodeNumber,
    @JsonKey(name: 'season_number') required int seasonNumber,
    String? name,
    String? overview,
    @JsonKey(name: 'air_date') String? airDate,
    int? runtime,

    /// `standard`, `finale` or `mid_season`.
    @JsonKey(name: 'episode_type') String? episodeType,
    @JsonKey(name: 'vote_average') @Default(0) double voteAverage,
    @JsonKey(name: 'vote_count') @Default(0) int voteCount,
    @JsonKey(name: 'still_path') String? stillPath,
    @JsonKey(name: 'production_code') String? productionCode,

    /// The episode's guest cast, as the season payload lists it; empty for most episodes.
    @JsonKey(name: 'guest_stars') @Default(<TmdbCastPerson>[]) List<TmdbCastPerson> guestStars,
  }) = _TmdbSeasonEpisode;

  factory TmdbSeasonEpisode.fromJson(Map<String, dynamic> json) => _$TmdbSeasonEpisodeFromJson(json);
}
