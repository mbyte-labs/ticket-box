import 'package:ticketbox/api/tmdb/v3/model/network.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_episode_stub.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_season_stub.dart';
import 'package:ticketbox/api/tmdb/v3/movie/movie_details.dart';
import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/api/tmdb/v3/tv_show/show_details.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/service/catalog/snapshots.dart';

/// Read models for tracked items whose document has not been fetched yet (the backfill is still
/// running, or TMDB was never reachable since the row was created): a synthetic TMDB body built
/// from the convenience columns, so every page renders the same way — with empty cast, related
/// and provider sections until the document lands.
class SnapshotFallback {
  const SnapshotFallback._();

  static MovieSnapshot movie(MovieEntity row) {
    return MovieSnapshot(
      details: TmdbMovieDetails(
        id: row.tmdbId,
        title: row.title,
        overview: row.overview,
        tagline: row.tagline,
        releaseDate: row.releaseDate,
        runtime: row.runtime,
        status: row.status == null ? null : row.statusValue.label,
        homepage: row.homepage,
        imdbId: row.imdbId,
        originalLanguage: row.language,
        voteAverage: row.voteAverage,
        voteCount: row.voteCount,
        popularity: row.popularity,
        posterPath: row.posterPath,
        backdropPath: row.backdropPath,
      ),
      fetchedAt: row.fetchedAt,
      tracked: true,
      providersRegion: row.watchProvidersRegion,
    );
  }

  static ShowSnapshot show(ShowEntity row, List<SeasonEntity> seasons) {
    final nextSeason = row.nextEpisodeSeason;
    final nextNumber = row.nextEpisodeNumber;
    return ShowSnapshot(
      details: TmdbShowDetails(
        id: row.tmdbId,
        name: row.title,
        overview: row.overview,
        tagline: row.tagline,
        firstAirDate: row.firstAirDate,
        lastAirDate: row.lastAirDate,
        status: row.status == null ? null : row.statusValue.label,
        homepage: row.homepage,
        originalLanguage: row.language,
        originCountry: [if (row.country != null) row.country!],
        episodeRunTime: [if (row.runtime != null) row.runtime!],
        numberOfSeasons: row.numberOfSeasons,
        voteAverage: row.voteAverage,
        voteCount: row.voteCount,
        popularity: row.popularity,
        networks: [if (row.network != null) TmdbNetwork(id: 0, name: row.network, logoPath: null, originCountry: null)],
        seasons: [for (final season in seasons) seasonStub(season)],
        nextEpisodeToAir: nextSeason == null || nextNumber == null
            ? null
            : TmdbEpisodeStub(id: 0, seasonNumber: nextSeason, episodeNumber: nextNumber, airDate: row.nextEpisodeAirDate),
        posterPath: row.posterPath,
        backdropPath: row.backdropPath,
      ),
      fetchedAt: row.fetchedAt,
      tracked: true,
      providersRegion: row.watchProvidersRegion,
    );
  }

  static SeasonSnapshot season(SeasonEntity row, List<EpisodeEntity> episodes) {
    return SeasonSnapshot(
      details: TmdbSeasonDetails(
        id: row.tmdbId,
        seasonNumber: row.season,
        name: row.title,
        airDate: row.airDate,
        posterPath: row.posterPath,
        episodes: [
          for (final episode in episodes)
            TmdbSeasonEpisode(
              id: episode.tmdbId ?? 0,
              episodeNumber: episode.episode,
              seasonNumber: episode.season,
              name: episode.title,
              overview: episode.overview,
              airDate: episode.airDate,
              runtime: episode.runtime,
              episodeType: episode.episodeType,
              voteAverage: episode.voteAverage,
              voteCount: episode.voteCount,
              stillPath: episode.stillPath,
            ),
        ],
      ),
      fetchedAt: row.fetchedAt,
      tracked: true,
    );
  }

  static TmdbSeasonStub seasonStub(SeasonEntity season) {
    return TmdbSeasonStub(
      id: season.tmdbId ?? 0,
      seasonNumber: season.season,
      episodeCount: season.episodeCount ?? 0,
      airDate: season.airDate,
      name: season.title,
      posterPath: season.posterPath,
    );
  }
}
