import 'package:ticketbox/api/tmdb/v3/model/tmdb_season_stub.dart';
import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/common/converter/episode.dart';
import 'package:ticketbox/common/converter/episode_type_inference.dart';
import 'package:ticketbox/common/model/show_status.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';

/// A fully fetched season: its row plus every episode.
class ConvertedSeason {
  final SeasonEntity season;
  final List<EpisodeEntity> episodes;

  const ConvertedSeason({required this.season, required this.episodes});
}

class SeasonConverter {
  /// A season as `/tv/{id}` lists it: exists, has N episodes, no episode list yet (`fetchedAt` null).
  static SeasonEntity fromStub(int showTmdbId, TmdbSeasonStub stub) {
    return SeasonEntity.build(
      showTmdbId: showTmdbId,
      season: stub.seasonNumber,
      tmdbId: stub.id,
      title: stub.name,
      episodeCount: stub.episodeCount,
      airDate: _dateOrNull(stub.airDate),
      posterPath: stub.posterPath,
      fetchedAt: null,
    );
  }

  /// A season from its document, with its episodes classified.
  ///
  /// [showRuntime] fills in episodes TMDB lists without a runtime; [showStatus] and
  /// [lastSeasonNumber] let a finale be told apart from a series finale. [tmdbSeasonId] is the
  /// season's id from the show's `seasons[]` stubs, for documents that carry none.
  static ConvertedSeason fromDetails(
    int showTmdbId,
    TmdbSeasonDetails details, {
    required ShowStatus showStatus,
    required int lastSeasonNumber,
    required DateTime fetchedAt,
    int? tmdbSeasonId,
    int? showRuntime,
  }) {
    final sorted = [...details.episodes]..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final types = EpisodeTypeInference.inferSeason(
      season: details.seasonNumber,
      episodes: sorted.map((e) => (episode: e.episodeNumber, tmdbType: e.episodeType)).toList(),
      showStatus: showStatus,
      lastSeasonNumber: lastSeasonNumber,
    );
    final episodes = [
      for (var i = 0; i < sorted.length; i++)
        EpisodeConverter.fromSeasonEpisode(showTmdbId, sorted[i], type: types[i], showRuntime: showRuntime),
    ];
    final season = SeasonEntity.build(
      showTmdbId: showTmdbId,
      season: details.seasonNumber,
      tmdbId: details.id ?? tmdbSeasonId,
      title: details.name,
      episodeCount: details.episodes.length,
      airDate: _dateOrNull(details.airDate),
      posterPath: details.posterPath,
      fetchedAt: fetchedAt,
    );
    return ConvertedSeason(season: season, episodes: episodes);
  }

  static String? _dateOrNull(String? value) => (value == null || value.isEmpty) ? null : value;
}
