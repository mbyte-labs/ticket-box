import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/genres/genres.dart';

class GenresRepo {
  final DatabaseConnectionManager _connectionManager;

  GenresRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  Future<void> insertAll(List<GenreEntity> items) async {
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.genres, items.map((e) => e.toInsertable()).toList());
    });
  }

  /// Replaces one type's genre list in one batch (one transaction, streams notified once), so a
  /// failure or kill between the delete and the inserts can no longer leave the table empty.
  ///
  /// Deliberately no isEmpty guard: an empty remote list must clear the type.
  Future<void> replaceByType(ItemType type, List<GenreEntity> items) async {
    await _connectionManager.batch((batch) {
      batch.deleteWhere(_connectionManager.genres, (genre) => genre.type.equalsValue(type));
      batch.insertAllOnConflictUpdate(_connectionManager.genres, items.map((e) => e.toInsertable()).toList());
    });
  }

  Future<GenreEntity?> get(ItemType type, int id) async {
    final query = _connectionManager.select(_connectionManager.genres)..where((genre) => genre.id.equals(id) & genre.type.equalsValue(type));
    return await query.map((row) => row).getSingleOrNull();
  }

  Future<List<GenreEntity>> getByType(ItemType type) async {
    final query = _connectionManager.select(_connectionManager.genres)
      ..where((genre) => genre.type.equalsValue(type))
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    return await query.map((row) => row).get();
  }

  Future<void> deleteAll() async {
    await _connectionManager.delete(_connectionManager.genres).go();
  }
}
