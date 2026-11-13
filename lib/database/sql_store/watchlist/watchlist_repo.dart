import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/filter/page_details.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/paged_response.dart' show PagedResponse;
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlistrepo_order_by.dart';

class WatchlistRepo {
  final DatabaseConnectionManager _connectionManager;

  WatchlistRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  Future<void> insert(WatchlistEntity item) async {
    await _connectionManager.into(_connectionManager.watchlists).insertOnConflictUpdate(item.toInsertable());
  }

  Future<void> insertAll(List<WatchlistEntity> items) async {
    if (items.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.watchlists, items.map((e) => e.toInsertable()).toList());
    });
  }

  /// Replaces the whole watchlist in one batch (one transaction) — for a future backup import.
  ///
  /// Deliberately no isEmpty guard: an empty list must clear the table.
  Future<void> replaceAll(List<WatchlistEntity> items) async {
    await _connectionManager.batch((batch) {
      batch.deleteAll(_connectionManager.watchlists);
      batch.insertAllOnConflictUpdate(_connectionManager.watchlists, items.map((e) => e.toInsertable()).toList());
    });
  }

  /// Replaces the movie and show rows with [items] in one batch, leaving the season and episode
  /// rows alone — what a pull from TMDB does, whose watchlist holds whole titles only.
  Future<void> replaceMoviesAndShows(List<WatchlistEntity> items) async {
    await _connectionManager.batch((batch) {
      batch.deleteWhere(_connectionManager.watchlists, (row) => row.type.isInValues([ItemType.movie, ItemType.show]));
      batch.insertAllOnConflictUpdate(_connectionManager.watchlists, items.map((e) => e.toInsertable()).toList());
    });
  }

  /// Deletes a movie's or a show's own row (season/episode rows have their own deletes).
  Future<void> delete(int tmdbId, ItemType type) async {
    await (_connectionManager.delete(_connectionManager.watchlists)
          ..where((item) => item.type.equalsValue(type) & item.tmdbId.equals(tmdbId) & item.season.equals(0) & item.episode.equals(0))) //
        .go();
  }

  Future<void> deleteSeason(int showTmdbId, int season) async {
    await (_connectionManager.delete(
      _connectionManager.watchlists,
    )..where((item) => item.type.equalsValue(ItemType.season) & item.tmdbId.equals(showTmdbId) & item.season.equals(season))).go();
  }

  Future<void> deleteEpisode(int showTmdbId, int season, int episode) async {
    await (_connectionManager.delete(_connectionManager.watchlists)..where(
          (item) =>
              item.type.equalsValue(ItemType.episode) &
              item.tmdbId.equals(showTmdbId) &
              item.season.equals(season) &
              item.episode.equals(episode),
        ))
        .go();
  }

  Future<void> deleteByKey(MediaKey key) async {
    await (_connectionManager.delete(_connectionManager.watchlists)..where(
          (item) =>
              item.type.equalsValue(key.type) &
              item.tmdbId.equals(key.tmdbId) &
              item.season.equals(key.season) &
              item.episode.equals(key.episode),
        ))
        .go();
  }

  Future<void> deleteByType(ItemType type) async {
    await (_connectionManager.delete(_connectionManager.watchlists)..where((item) => item.type.equalsValue(type))).go();
  }

  Future<void> deleteAll() async {
    await _connectionManager.delete(_connectionManager.watchlists).go();
  }

  /// Every watchlist row, newest first - the backup export's read, mirroring `HistoryRepo.getAll`.
  Future<List<WatchlistEntity>> getAll() async {
    final query = _connectionManager.select(_connectionManager.watchlists)
      ..orderBy([(t) => OrderingTerm(expression: t.listedAt, mode: OrderingMode.desc)]);
    return await query.map((row) => row).get();
  }

  /// The number of watchlist rows across every item type - the Lists page's subtitle.
  Future<int> count() async {
    final countExp = _connectionManager.watchlists.tmdbId.count();
    final query = _connectionManager.selectOnly(_connectionManager.watchlists)..addColumns([countExp]);
    final row = await query.getSingle();
    return row.read(countExp)!;
  }

  /// Re-emits the whole watchlist on every write to the table - what `DataChangeMonitor` listens
  /// on, so a bookmark toggled elsewhere refreshes the watchlist page on its own.
  Stream<List<WatchlistEntity>> listenForChanges() {
    final query = _connectionManager.select(_connectionManager.watchlists)
      ..orderBy([(t) => OrderingTerm(expression: t.listedAt, mode: OrderingMode.desc)]);
    return query.map((row) => row).watch();
  }

  Future<PagedResponse<List<WatchlistEntity>>> get(
    List<ItemType> types,
    WatchlistRepoOrderBy orderBy,
    OrderType orderType,
    PageDetails paged,
  ) async {
    if (types.isEmpty) {
      return PagedResponse(page: paged.page, pageSize: paged.pageSize, totalPages: 1, data: []);
    }
    final countExp = _connectionManager.watchlists.tmdbId.count();
    OrderingMode orderMode = OrderingMode.asc;
    if (orderType == OrderType.descending) {
      orderMode = OrderingMode.desc;
    }
    final countQuery = _connectionManager.selectOnly(_connectionManager.watchlists)
      ..addColumns([countExp])
      ..where((_connectionManager.watchlists.type.isInValues(types)));
    final countRow = await countQuery.getSingle();
    final totalItems = countRow.read(countExp)!;
    if (totalItems == 0) {
      return PagedResponse(page: paged.page, pageSize: paged.pageSize, totalPages: 1, data: []);
    }
    final query = _connectionManager.select(_connectionManager.watchlists)
      ..where((item) => item.type.isInValues(types))
      ..orderBy([(t) => OrderingTerm(expression: t.listedAt, mode: orderMode)])
      ..limit(paged.pageSize, offset: paged.page * paged.pageSize);
    List<WatchlistEntity> result = await query.map((row) => row).get();
    return PagedResponse(page: paged.page, pageSize: paged.pageSize, totalPages: (totalItems / paged.pageSize).ceil(), data: result);
  }

  Future<WatchlistEntity?> getItem(ItemType type, int tmdbId, [int season = 0, int episode = 0]) async {
    final query = (_connectionManager.select(_connectionManager.watchlists)
      ..where(
        (item) => item.type.equalsValue(type) & item.tmdbId.equals(tmdbId) & item.season.equals(season) & item.episode.equals(episode),
      ));
    return await query.getSingleOrNull();
  }

  Future<WatchlistEntity?> getByKey(MediaKey key) => getItem(key.type, key.tmdbId, key.season, key.episode);
}
