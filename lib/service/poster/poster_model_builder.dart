import 'package:ticketbox/api/tmdb/v3/model/tmdb_list_item.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_season_stub.dart';
import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/common/model/episode_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/title_builder.dart';

/// Builds [PosterModel]s (without marks) from catalogue rows and TMDB list payloads.
class PosterModelBuilder {
  const PosterModelBuilder._();

  static const String noTitle = '-No title available-';

  static String? _score(double voteAverage) => voteAverage <= 0 ? null : voteAverage.toStringAsFixed(1);

  static PosterModel movie(MovieEntity row) {
    return PosterModel(
      key: MediaKey.movie(row.tmdbId),
      title: row.title ?? noTitle,
      noPosterText: row.title ?? noTitle,
      posterPath: row.posterPath,
      tracked: true,
      rating: _score(row.voteAverage),
    );
  }

  static PosterModel show(ShowEntity row) {
    return PosterModel(
      key: MediaKey.show(row.tmdbId),
      title: row.title ?? noTitle,
      noPosterText: row.title ?? noTitle,
      posterPath: row.posterPath,
      tracked: true,
      rating: _score(row.voteAverage),
    );
  }

  /// A tracked season tile: its own poster, else the show's.
  static PosterModel season(SeasonEntity row, {required String? showTitle, required String? showPosterPath}) {
    return PosterModel(
      key: MediaKey.season(row.showTmdbId, row.season),
      title: row.title ?? ConfirmationTitleBuilder.seasonTitle(row.season),
      noPosterText: showTitle ?? noTitle,
      posterPath: row.posterPath ?? showPosterPath,
      tracked: true,
      rating: null,
    );
  }

  /// A season tile from a show document's `seasons[]` stub (a live view, or before the season
  /// rows exist).
  static PosterModel seasonStub(
    int showTmdbId,
    TmdbSeasonStub stub, {
    required String? showTitle,
    required String? showPosterPath,
    bool tracked = false,
  }) {
    return PosterModel(
      key: MediaKey.season(showTmdbId, stub.seasonNumber),
      title: stub.name ?? ConfirmationTitleBuilder.seasonTitle(stub.seasonNumber),
      noPosterText: showTitle ?? noTitle,
      posterPath: stub.posterPath ?? showPosterPath,
      tracked: tracked,
      rating: stub.voteAverage == null ? null : _score(stub.voteAverage!),
    );
  }

  /// A tracked episode tile: `S1xE2 Name`, the season's poster as artwork, the still for the
  /// still tiles.
  static PosterModel episode(EpisodeEntity row, {required String? showTitle, required String? seasonPosterPath}) {
    return PosterModel(
      key: MediaKey.episode(row.showTmdbId, row.season, row.episode),
      title: ConfirmationTitleBuilder.episodeTitleFromParts(row.season, row.episode, row.title),
      noPosterText: showTitle ?? noTitle,
      posterPath: seasonPosterPath,
      stillPath: row.stillPath,
      tracked: true,
      rating: _score(row.voteAverage),
      episodeType: row.type,
    );
  }

  /// An episode tile from a season document's entry (a live view, or the season page).
  static PosterModel episodeEntry(
    int showTmdbId,
    TmdbSeasonEpisode entry, {
    required EpisodeType type,
    required String? showTitle,
    required String? seasonPosterPath,
    bool tracked = false,
  }) {
    return PosterModel(
      key: MediaKey.episode(showTmdbId, entry.seasonNumber, entry.episodeNumber),
      title: ConfirmationTitleBuilder.episodeTitleFromParts(entry.seasonNumber, entry.episodeNumber, entry.name),
      noPosterText: showTitle ?? noTitle,
      posterPath: seasonPosterPath,
      stillPath: entry.stillPath,
      tracked: tracked,
      rating: _score(entry.voteAverage),
      episodeType: type,
    );
  }

  /// An Up Next tile: the show's next episode over its season poster.
  static PosterModel upNext(UpNextRow row) {
    return PosterModel(
      key: MediaKey.episode(row.next.showTmdbId, row.next.season, row.next.episode),
      title: ConfirmationTitleBuilder.episodeTitleFromParts(row.next.season, row.next.episode, row.next.title),
      noPosterText: row.showTitle.isEmpty ? noTitle : row.showTitle,
      posterPath: row.seasonPosterPath ?? row.showPosterPath,
      tracked: true,
      rating: _score(row.next.voteAverage),
      episodeType: EpisodeType.fromWireValue(row.next.episodeType),
      upcoming: !row.next.aired,
      airDate: row.next.airDate,
    );
  }

  /// A browsed movie (search, discover, related, person page): untracked unless marked later.
  static PosterModel movieListItem(TmdbMovieListItem item) {
    return PosterModel(
      key: MediaKey.movie(item.id),
      title: item.title ?? noTitle,
      noPosterText: item.title ?? noTitle,
      posterPath: item.posterPath,
      tracked: false,
      rating: _score(item.voteAverage),
    );
  }

  static PosterModel showListItem(TmdbShowListItem item) {
    return PosterModel(
      key: MediaKey.show(item.id),
      title: item.name ?? noTitle,
      noPosterText: item.name ?? noTitle,
      posterPath: item.posterPath,
      tracked: false,
      rating: _score(item.voteAverage),
    );
  }
}
