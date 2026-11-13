import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_entity.dart';

/// The stored TMDB documents. One row per tracked movie, show root and fetched season.
class SnapshotDocumentRepo {
  final DatabaseConnectionManager _connectionManager;

  SnapshotDocumentRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  Future<void> upsert(SnapshotDocumentEntity document) async {
    await _connectionManager.into(_connectionManager.snapshotDocuments).insertOnConflictUpdate(document.toInsertable());
  }

  Future<void> upsertAll(List<SnapshotDocumentEntity> documents) async {
    if (documents.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.snapshotDocuments, documents.map((e) => e.toInsertable()).toList());
    });
  }

  Future<String?> getMovie(int tmdbId) => _get(ItemType.movie, tmdbId, 0);

  Future<String?> getShow(int tmdbId) => _get(ItemType.show, tmdbId, 0);

  Future<String?> getSeason(int showTmdbId, int season) => _get(ItemType.season, showTmdbId, season);

  Future<String?> _get(ItemType type, int tmdbId, int season) async {
    final query = _connectionManager.select(_connectionManager.snapshotDocuments)
      ..where((row) => row.type.equalsValue(type) & row.tmdbId.equals(tmdbId) & row.season.equals(season));
    final row = await query.getSingleOrNull();
    return row?.metadataJson;
  }

  /// Removes a movie's document, or a show's root and every season document.
  Future<void> deleteFor(ItemType type, int tmdbId) async {
    final types = type == ItemType.movie ? [ItemType.movie] : [ItemType.show, ItemType.season];
    await (_connectionManager.delete(
      _connectionManager.snapshotDocuments,
    )..where((row) => row.type.isInValues(types) & row.tmdbId.equals(tmdbId))).go();
  }

  Future<void> deleteSeason(int showTmdbId, int season) async {
    await (_connectionManager.delete(
      _connectionManager.snapshotDocuments,
    )..where((row) => row.type.equalsValue(ItemType.season) & row.tmdbId.equals(showTmdbId) & row.season.equals(season))).go();
  }
}
