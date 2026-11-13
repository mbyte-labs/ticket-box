import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/common/model/episode_type.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';

class EpisodeConverter {
  /// One episode of a season document, with the [type] the season converter inferred.
  static EpisodeEntity fromSeasonEpisode(int showTmdbId, TmdbSeasonEpisode episode, {required EpisodeType type, int? showRuntime}) {
    return EpisodeEntity.build(
      showTmdbId: showTmdbId,
      season: episode.seasonNumber,
      episode: episode.episodeNumber,
      tmdbId: episode.id,
      imdbId: null,
      title: episode.name,
      overview: episode.overview,
      voteAverage: episode.voteAverage,
      voteCount: episode.voteCount,
      runtime: _runtime(episode.runtime, showRuntime),
      airDate: (episode.airDate == null || episode.airDate!.isEmpty) ? null : episode.airDate,
      episodeType: type.wireValue,
      stillPath: episode.stillPath,
    );
  }

  static int? _runtime(int? episodeRuntime, int? showRuntime) {
    if (episodeRuntime != null && episodeRuntime > 0) {
      return episodeRuntime;
    }
    if (showRuntime != null && showRuntime > 0) {
      return showRuntime;
    }
    return null;
  }
}
