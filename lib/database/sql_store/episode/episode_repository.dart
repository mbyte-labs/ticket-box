import 'package:drift/drift.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';

class EpisodeRepo {
  final DatabaseConnectionManager _connectionManager;

  EpisodeRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// Inserts or updates an episode inside the DB
  Future<void> insert(EpisodeEntity item) async {
    await _connectionManager.into(_connectionManager.episodes).insertOnConflictUpdate(item.toInsertable());
  }

  Future<void> insertAll(List<EpisodeEntity> items) async {
    if (items.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.episodes, items.map((e) => e.toInsertable()).toList());
    });
  }

  /// Conflict clause for a season document write: everything is fresh except an `imdbId` the
  /// document does not carry, which must not wipe one looked up earlier.
  static UpsertClause<$EpisodesTable, EpisodeEntity> fullConflict() {
    return DoUpdate.withExcluded(
      (old, excluded) => EpisodesCompanion.custom(
        tmdbId: excluded.tmdbId,
        imdbId: coalesce([excluded.imdbId, old.imdbId]),
        title: excluded.title,
        overview: excluded.overview,
        voteAverage: excluded.voteAverage,
        voteCount: excluded.voteCount,
        runtime: excluded.runtime,
        airDate: excluded.airDate,
        episodeType: excluded.episodeType,
        stillPath: excluded.stillPath,
      ),
    );
  }

  Future<void> updateImdbId(int showTmdbId, int season, int episode, String? imdbId) async {
    await (_connectionManager.update(_connectionManager.episodes)
          ..where((item) => item.showTmdbId.equals(showTmdbId) & item.season.equals(season) & item.episode.equals(episode)))
        .write(EpisodesCompanion(imdbId: Value(imdbId)));
  }

  Future<EpisodeEntity?> get(int showTmdbId, int season, int episode) async {
    final query = _connectionManager.select(_connectionManager.episodes)
      ..where((item) => item.showTmdbId.equals(showTmdbId) & item.season.equals(season) & item.episode.equals(episode));
    return await query.map((row) => row).getSingleOrNull();
  }

  /// The episodes of the given `(show, season, episode)` keys, keyed back the same way; missing
  /// ones absent. Reads whole shows and filters in memory — a history page names a few dozen
  /// episodes across a handful of shows, so that is cheaper than a row-value `IN`.
  Future<Map<(int, int, int), EpisodeEntity>> getMany(Iterable<(int, int, int)> keys) async {
    final wanted = keys.toSet();
    final showIds = wanted.map((k) => k.$1).toSet().toList();
    if (showIds.isEmpty) {
      return {};
    }
    final result = <(int, int, int), EpisodeEntity>{};
    for (final chunk in showIds.chunked(_lookupChunkSize)) {
      final query = _connectionManager.select(_connectionManager.episodes)..where((item) => item.showTmdbId.isIn(chunk));
      for (final episode in await query.get()) {
        final key = (episode.showTmdbId, episode.season, episode.episode);
        if (wanted.contains(key)) {
          result[key] = episode;
        }
      }
    }
    return result;
  }

  /// Every episode of one season, ordered by episode number.
  Future<List<EpisodeEntity>> getAllForSeason(int showTmdbId, int season) async {
    final query = _connectionManager.select(_connectionManager.episodes)
      ..where((item) => item.showTmdbId.equals(showTmdbId) & item.season.equals(season))
      ..orderBy([(t) => OrderingTerm(expression: t.episode)]);
    return await query.map((row) => row).get();
  }

  /// Every episode of a show, ordered by season and episode — the progress calculator's catalogue.
  /// An episode without an air date reads as "not aired" there.
  Future<List<EpisodeEntity>> getAllForShow(int showTmdbId) async {
    final query = _connectionManager.select(_connectionManager.episodes)
      ..where((item) => item.showTmdbId.equals(showTmdbId))
      ..orderBy([(t) => OrderingTerm(expression: t.season), (t) => OrderingTerm(expression: t.episode)]);
    return await query.map((row) => row).get();
  }

  /// The *open* seasons of a show — the ones the refresh scheduler re-fetches: the highest-numbered
  /// season plus every non-special season with an undated episode or one airing after [today]
  /// (`YYYY-MM-DD`). A closed season never changes and is never re-fetched by the job.
  Future<List<int>> getOpenSeasons(int showTmdbId, String today) async {
    final rows = await _connectionManager
        .customSelect(
          '''
      SELECT season FROM (
        SELECT MAX(season) AS season FROM seasons WHERE show_tmdb_id = ?1
        UNION
        SELECT DISTINCT season FROM episodes WHERE show_tmdb_id = ?1 AND season > 0 AND (air_date IS NULL OR air_date > ?2))
      WHERE season IS NOT NULL ORDER BY season''',
          variables: [Variable.withInt(showTmdbId), Variable.withString(today)],
          readsFrom: {_connectionManager.seasons, _connectionManager.episodes},
        )
        .get();
    return rows.map((row) => row.read<int>('season')).toList();
  }

  /// Deletes the episodes of the show whose id was given.
  Future<void> deleteByShowId(int showTmdbId) async {
    await (_connectionManager.delete(_connectionManager.episodes)..where((item) => item.showTmdbId.equals(showTmdbId))).go();
  }

  /// Deletes one season's episodes.
  Future<void> deleteBySeason(int showTmdbId, int season) async {
    await (_connectionManager.delete(
      _connectionManager.episodes,
    )..where((item) => item.showTmdbId.equals(showTmdbId) & item.season.equals(season))).go();
  }

  Future<void> deleteByEpisodeNr(int showTmdbId, int season, int episode) async {
    await (_connectionManager.delete(
      _connectionManager.episodes,
    )..where((item) => item.showTmdbId.equals(showTmdbId) & item.season.equals(season) & item.episode.equals(episode))).go();
  }

  /// Well below SQLite's default limit of 999 bound variables per statement.
  static const _lookupChunkSize = 500;
}
