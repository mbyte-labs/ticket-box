import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_entity.dart';

class TmdbSyncOutboxRepo {
  final DatabaseConnectionManager _connectionManager;

  TmdbSyncOutboxRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// Queues [operation] for [key], replacing any pending operation of the same data set for the
  /// same key: the newest intent wins (rate 7 then rate 8 leaves one `rate 8`; add then remove
  /// leaves the remove, because the add may already have reached TMDB). One transaction.
  Future<int> enqueue({required TmdbSyncOperation operation, required MediaKey key, int? rating}) {
    return _connectionManager.transaction(() async {
      await (_connectionManager.delete(_connectionManager.tmdbSyncOutbox)..where(
            (row) =>
                row.operation.isInValues(TmdbSyncOperation.of(operation.dataSet)) &
                row.type.equalsValue(key.type) &
                row.tmdbId.equals(key.tmdbId) &
                row.season.equals(key.season) &
                row.episode.equals(key.episode),
          ))
          .go();
      return _connectionManager
          .into(_connectionManager.tmdbSyncOutbox)
          .insert(
            TmdbSyncOutboxCompanion.insert(
              operation: operation,
              type: key.type,
              tmdbId: key.tmdbId,
              season: key.season,
              episode: key.episode,
              rating: Value(rating),
              createdAt: DateTime.now().toUtc(),
            ),
          );
    });
  }

  /// The oldest [limit] pending rows queued after [afterId], in the order they were queued — the
  /// flush walks the queue with it, so a row it just left in place is not read again in the same run.
  Future<List<TmdbSyncOutboxEntity>> getPending(int limit, {int afterId = 0}) async {
    final query = _connectionManager.select(_connectionManager.tmdbSyncOutbox)
      ..where((row) => row.id.isBiggerThanValue(afterId))
      ..orderBy([(row) => OrderingTerm(expression: row.id)])
      ..limit(limit);
    return await query.get();
  }

  Future<List<TmdbSyncOutboxEntity>> getAll() async {
    final query = _connectionManager.select(_connectionManager.tmdbSyncOutbox)..orderBy([(row) => OrderingTerm(expression: row.id)]);
    return await query.get();
  }

  Future<void> delete(int id) async {
    await (_connectionManager.delete(_connectionManager.tmdbSyncOutbox)..where((row) => row.id.equals(id))).go();
  }

  /// Records one more failed delivery of row [id] and why.
  Future<void> markAttempt(int id, String error) async {
    await _connectionManager.customUpdate(
      'UPDATE tmdb_sync_outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      variables: [Variable.withString(error), Variable.withInt(id)],
      updates: {_connectionManager.tmdbSyncOutbox},
    );
  }

  /// Drops every pending operation of [dataSet] — when its toggle is turned off, or right after a
  /// pull replaced the local list and the pending pushes refer to a state that no longer exists.
  Future<void> deleteByDataSet(TmdbDataSet dataSet) async {
    await (_connectionManager.delete(
      _connectionManager.tmdbSyncOutbox,
    )..where((row) => row.operation.isInValues(TmdbSyncOperation.of(dataSet)))).go();
  }

  Future<void> deleteAll() async {
    await _connectionManager.delete(_connectionManager.tmdbSyncOutbox).go();
  }

  Future<int> count() async {
    final countExp = _connectionManager.tmdbSyncOutbox.id.count();
    final query = _connectionManager.selectOnly(_connectionManager.tmdbSyncOutbox)..addColumns([countExp]);
    final row = await query.getSingle();
    return row.read(countExp)!;
  }

  /// The number of pending rows, re-emitted on every change — the Settings page's "N changes
  /// waiting to reach TMDB" line.
  Stream<int> watchCount() {
    final countExp = _connectionManager.tmdbSyncOutbox.id.count();
    final query = _connectionManager.selectOnly(_connectionManager.tmdbSyncOutbox)..addColumns([countExp]);
    return query.watchSingle().map((row) => row.read(countExp)!);
  }
}
