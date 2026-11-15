import 'package:drift/drift.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';

class SeasonRepo {
  final DatabaseConnectionManager _connectionManager;

  SeasonRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// Inserts or replaces a season row.
  Future<void> insert(SeasonEntity item) async {
    await _connectionManager.into(_connectionManager.seasons).insertOnConflictUpdate(item.toInsertable());
  }

  Future<void> insertAll(List<SeasonEntity> items) async {
    if (items.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.seasons, items.map((e) => e.toInsertable()).toList());
    });
  }

  /// Upserts the season stubs that come with a show's root document without touching an existing
  /// row's `fetchedAt` — a stub says the season exists, how many episodes it has and what its poster
  /// is, not that its episode list is fresh.
  Future<void> upsertStubs(List<SeasonEntity> items) async {
    if (items.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAll(
        _connectionManager.seasons,
        items.map((e) => e.toInsertable()).toList(),
        onConflict: DoUpdate<$SeasonsTable, SeasonEntity>.withExcluded(
          (old, excluded) => SeasonsCompanion.custom(
            tmdbId: coalesce([excluded.tmdbId, old.tmdbId]),
            title: excluded.title,
            episodeCount: excluded.episodeCount,
            airDate: excluded.airDate,
            posterPath: coalesce([excluded.posterPath, old.posterPath]),
          ),
        ),
      );
    });
  }

  /// Replaces fetched seasons — their rows and their episodes — in one batch, so a kill mid-write
  /// cannot leave a season whose episode list is half old, half new. Episodes TMDB no longer lists
  /// for a season are removed; the ones it still lists are upserted with [EpisodeRepo.fullConflict],
  /// which keeps an `imdbId` looked up earlier.
  Future<void> replaceSeasons(int showTmdbId, List<SeasonEntity> seasons, List<EpisodeEntity> episodes) async {
    if (seasons.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      for (final season in seasons) {
        final keep = episodes.where((e) => e.season == season.season).map((e) => e.episode).toList();
        Expression<bool> vanished($EpisodesTable row) =>
            row.showTmdbId.equals(showTmdbId) &
            row.season.equals(season.season) &
            (keep.isEmpty ? const Constant(true) : row.episode.isNotIn(keep));
        batch.deleteWhere(_connectionManager.episodes, vanished);
      }
      batch.insertAllOnConflictUpdate(_connectionManager.seasons, seasons.map((e) => e.toInsertable()).toList());
      batch.insertAll(_connectionManager.episodes, episodes.map((e) => e.toInsertable()).toList(), onConflict: EpisodeRepo.fullConflict());
    });
  }

  /// Every season of a show, ordered by season number.
  Future<List<SeasonEntity>> getAllForShow(int showTmdbId) async {
    final query = _connectionManager.select(_connectionManager.seasons)
      ..where((item) => item.showTmdbId.equals(showTmdbId))
      ..orderBy([(t) => OrderingTerm(expression: t.season)]);
    return await query.map((row) => row).get();
  }

  Future<SeasonEntity?> getBySeasonNumber(int showTmdbId, int season) async {
    final query = _connectionManager.select(_connectionManager.seasons)
      ..where((item) => item.showTmdbId.equals(showTmdbId) & item.season.equals(season));
    return await query.map((row) => row).getSingleOrNull();
  }

  /// The seasons of the given `(show, season)` keys, keyed back the same way; missing ones absent.
  Future<Map<(int, int), SeasonEntity>> getMany(Iterable<(int, int)> keys) async {
    final showIds = keys.map((k) => k.$1).toSet().toList();
    if (showIds.isEmpty) {
      return {};
    }
    final wanted = keys.toSet();
    final result = <(int, int), SeasonEntity>{};
    for (final chunk in showIds.chunked(_lookupChunkSize)) {
      final query = _connectionManager.select(_connectionManager.seasons)..where((item) => item.showTmdbId.isIn(chunk));
      for (final season in await query.get()) {
        final key = (season.showTmdbId, season.season);
        if (wanted.contains(key)) {
          result[key] = season;
        }
      }
    }
    return result;
  }

  /// The season numbers of a show whose episode list has not been fetched (`fetchedAt` null).
  Future<List<int>> getUnfetchedSeasonNumbers(int showTmdbId) async {
    final query = _connectionManager.selectOnly(_connectionManager.seasons)
      ..addColumns([_connectionManager.seasons.season])
      ..where(_connectionManager.seasons.showTmdbId.equals(showTmdbId) & _connectionManager.seasons.fetchedAt.isNull())
      ..orderBy([OrderingTerm(expression: _connectionManager.seasons.season)]);
    final rows = await query.get();
    return rows.map((row) => row.read(_connectionManager.seasons.season)!).toList();
  }

  /// Deletes the seasons of the show whose id was given.
  Future<void> deleteByShowId(int showTmdbId) async {
    await (_connectionManager.delete(_connectionManager.seasons)..where((item) => item.showTmdbId.equals(showTmdbId))).go();
  }

  Future<void> deleteBySeasonNr(int showTmdbId, int season) async {
    await (_connectionManager.delete(
      _connectionManager.seasons,
    )..where((item) => item.showTmdbId.equals(showTmdbId) & item.season.equals(season))).go();
  }

  /// Well below SQLite's default limit of 999 bound variables per statement.
  static const _lookupChunkSize = 500;
}
