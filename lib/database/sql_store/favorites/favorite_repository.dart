import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart' show DatabaseConnectionInitializer;
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';

/// Every query filters on `type` as well as `tmdb_id`: movies and shows share TMDB's id space.
class FavoriteRepo {
  final DatabaseConnectionManager _connectionManager;

  FavoriteRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// Inserts or updates a favorite.
  Future<void> insert(FavoriteEntity item) async {
    await _connectionManager.into(_connectionManager.favoriteItems).insertOnConflictUpdate(item.toInsertable());
  }

  Future<void> insertAll(List<FavoriteEntity> items) async {
    if (items.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.favoriteItems, items.map((e) => e.toInsertable()).toList());
    });
  }

  /// Replaces the whole list with [items] in one batch — for a future backup import. drift runs a
  /// batch in a transaction and notifies its streams once, after the commit, so [subscribe] only
  /// ever sees the final state.
  Future<void> replaceAll(List<FavoriteEntity> items) async {
    await _connectionManager.batch((batch) {
      batch.deleteAll(_connectionManager.favoriteItems);
      batch.insertAllOnConflictUpdate(_connectionManager.favoriteItems, items.map((e) => e.toInsertable()).toList());
    });
  }

  Future<FavoriteEntity?> get(ItemType type, int tmdbId) async {
    final query = _connectionManager.select(_connectionManager.favoriteItems)
      ..where((item) => item.type.equalsValue(type) & item.tmdbId.equals(tmdbId));
    return await query.getSingleOrNull();
  }

  /// Every favorite, newest first — the backup export's read.
  Future<List<FavoriteEntity>> getAll() async {
    final query = _connectionManager.select(_connectionManager.favoriteItems)
      ..orderBy([(t) => OrderingTerm(expression: t.favoritedAt, mode: OrderingMode.desc)]);
    return await query.get();
  }

  /// The favorites of the given [types], the most recently added first — the
  /// Favorites page's order. An empty [types] returns nothing (an empty `IN ()` is invalid SQL).
  Future<List<FavoriteEntity>> getAllNewestFirst(List<ItemType> types) async {
    if (types.isEmpty) {
      return [];
    }
    final query = _connectionManager.select(_connectionManager.favoriteItems)
      ..where((item) => item.type.isInValues(types))
      ..orderBy([(t) => OrderingTerm(expression: t.favoritedAt, mode: OrderingMode.desc)]);
    return await query.get();
  }

  Future<int> count() async {
    final countExp = _connectionManager.favoriteItems.tmdbId.count();
    final query = _connectionManager.selectOnly(_connectionManager.favoriteItems)..addColumns([countExp]);
    final row = await query.getSingle();
    return row.read(countExp)!;
  }

  Future<void> delete(ItemType type, int tmdbId) async {
    await (_connectionManager.delete(
      _connectionManager.favoriteItems,
    )..where((item) => item.type.equalsValue(type) & item.tmdbId.equals(tmdbId))).go();
  }

  Future<void> deleteAll() async {
    await _connectionManager.delete(_connectionManager.favoriteItems).go();
  }

  /// Emits the whole list whenever it changes — fed to `DataChangeMonitor`.
  Stream<List<FavoriteEntity>> subscribe() {
    return _connectionManager.select(_connectionManager.favoriteItems).watch();
  }
}
