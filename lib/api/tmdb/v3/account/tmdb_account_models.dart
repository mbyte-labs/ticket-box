import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/item_type.dart';

part 'tmdb_account_models.freezed.dart';
part 'tmdb_account_models.g.dart';

/// TMDB's `media_type` for the watchlist and favorite writes. Only whole titles can be listed:
/// seasons and episodes have no place on a TMDB watchlist.
enum TmdbMediaType {
  movie('movie'),
  tv('tv');

  final String apiName;

  const TmdbMediaType(this.apiName);

  /// The media type of a movie or a show; null for a season or an episode.
  static TmdbMediaType? fromItemType(ItemType type) => switch (type) {
    ItemType.movie => TmdbMediaType.movie,
    ItemType.show => TmdbMediaType.tv,
    ItemType.season || ItemType.episode => null,
  };
}

/// `/3/account`: who the session belongs to. [id] is the numeric account id the list and write
/// endpoints are addressed with.
@Freezed(toJson: false)
abstract class TmdbAccountDetails with _$TmdbAccountDetails {
  const factory TmdbAccountDetails({required int id, required String username, String? name}) = _TmdbAccountDetails;

  factory TmdbAccountDetails.fromJson(Map<String, dynamic> json) => _$TmdbAccountDetailsFromJson(json);
}

/// A row of `/3/account/{id}/rated/movies`. [rating] is the user's own score, 0.5–10 in half steps.
@Freezed(toJson: false)
abstract class TmdbRatedMovie with _$TmdbRatedMovie {
  const factory TmdbRatedMovie({required int id, required double rating}) = _TmdbRatedMovie;

  factory TmdbRatedMovie.fromJson(Map<String, dynamic> json) => _$TmdbRatedMovieFromJson(json);
}

/// A row of `/3/account/{id}/rated/tv`.
@Freezed(toJson: false)
abstract class TmdbRatedShow with _$TmdbRatedShow {
  const factory TmdbRatedShow({required int id, required double rating}) = _TmdbRatedShow;

  factory TmdbRatedShow.fromJson(Map<String, dynamic> json) => _$TmdbRatedShowFromJson(json);
}

/// A row of `/3/account/{id}/rated/tv/episodes`, addressed the way the app keys episodes: the
/// show's id plus the season and episode numbers. The episode's own id is not needed.
@Freezed(toJson: false)
abstract class TmdbRatedEpisode with _$TmdbRatedEpisode {
  const factory TmdbRatedEpisode({
    @JsonKey(name: 'show_id') required int showId,
    @JsonKey(name: 'season_number') required int seasonNumber,
    @JsonKey(name: 'episode_number') required int episodeNumber,
    required double rating,
  }) = _TmdbRatedEpisode;

  factory TmdbRatedEpisode.fromJson(Map<String, dynamic> json) => _$TmdbRatedEpisodeFromJson(json);
}
