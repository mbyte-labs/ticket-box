import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';

class UserRatingRepo {
  final DatabaseConnectionManager _connectionManager;

  UserRatingRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  Future<UserRatingEntity?> get(ItemType type, int tmdbId, [int season = 0, int episode = 0]) async {
    final query = (_connectionManager.select(_connectionManager.userRatings)
      ..where(
        (item) => item.type.equalsValue(type) & item.tmdbId.equals(tmdbId) & item.season.equals(season) & item.episode.equals(episode),
      ));
    return await query.getSingleOrNull();
  }

  Future<UserRatingEntity?> getByKey(MediaKey key) => get(key.type, key.tmdbId, key.season, key.episode);

  /// The user's ratings of the episodes of one season — what a season's derived rating is averaged from.
  Future<List<UserRatingEntity>> getForSeasonEpisodes(int showTmdbId, int season) async {
    final query = (_connectionManager.select(_connectionManager.userRatings)
      ..where((item) => item.type.equalsValue(ItemType.episode) & item.tmdbId.equals(showTmdbId) & item.season.equals(season)));
    return await query.get();
  }

  /// Every rating the user has given, across all item types.
  ///
  /// Bounded by how much the user has actually rated (hundreds, maybe low thousands of rows), so
  /// the stats aggregations happen in Dart on the full list.
  Future<List<UserRatingEntity>> getAll() async {
    return await _connectionManager.select(_connectionManager.userRatings).get();
  }

  Future<void> insert(UserRatingEntity item) async {
    await _connectionManager.into(_connectionManager.userRatings).insertOnConflictUpdate(item.toInsertable());
  }

  Future<void> insertAll(List<UserRatingEntity> items) async {
    if (items.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.userRatings, items.map((e) => e.toInsertable()).toList());
    });
  }

  Future<void> delete(ItemType type, int tmdbId, [int season = 0, int episode = 0]) async {
    await (_connectionManager.delete(_connectionManager.userRatings)..where(
          (item) => item.type.equalsValue(type) & item.tmdbId.equals(tmdbId) & item.season.equals(season) & item.episode.equals(episode),
        ))
        .go();
  }

  Future<void> deleteByKey(MediaKey key) => delete(key.type, key.tmdbId, key.season, key.episode);

  /// Replaces every rating in one batch (one transaction) — for a future backup import.
  ///
  /// Deliberately no isEmpty guard: an empty list must clear the table.
  Future<void> replaceAll(List<UserRatingEntity> items) async {
    await _connectionManager.batch((batch) {
      batch.deleteAll(_connectionManager.userRatings);
      batch.insertAllOnConflictUpdate(_connectionManager.userRatings, items.map((e) => e.toInsertable()).toList());
    });
  }

  Future<void> deleteAll() async {
    await _connectionManager.delete(_connectionManager.userRatings).go();
  }

  /// Re-emits every rating on every write to the table - what `DataChangeMonitor` listens on.
  Stream<List<UserRatingEntity>> listenForChanges() {
    return _connectionManager.select(_connectionManager.userRatings).watch();
  }
}
