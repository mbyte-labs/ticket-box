import 'package:drift/drift.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart' show DatabaseConnectionInitializer;
import 'package:ticketbox/database/sql_store/show/show_entity.dart';

/// The tracked shows. A row exists iff the show is in the library; nothing here writes one for a
/// browsed title — that is the tracking service's job, together with the snapshot documents.
class ShowRepo {
  final DatabaseConnectionManager _connectionManager;

  ShowRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// Inserts or replaces the whole row (a snapshot write).
  Future<void> insert(ShowEntity item) async {
    await _connectionManager.into(_connectionManager.shows).insertOnConflictUpdate(item.toInsertable());
  }

  Future<void> insertAll(List<ShowEntity> items) async {
    if (items.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.shows, items.map((e) => e.toInsertable()).toList());
    });
  }

  /// Rows that only say "in the library since [trackedAt]" for ids that have none yet (a backup
  /// restore, a TMDB account pull); existing rows are left alone. The backfill fetches the rest.
  Future<void> insertStubs(Iterable<int> tmdbIds, {required DateTime trackedAt}) async {
    final ids = tmdbIds.toSet().toList();
    if (ids.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAll(_connectionManager.shows, [
        for (final id in ids) ShowsCompanion.insert(tmdbId: Value(id), trackedAt: trackedAt),
      ], mode: InsertMode.insertOrIgnore);
    });
  }

  Future<ShowEntity?> get(int tmdbId) async {
    final query = _connectionManager.select(_connectionManager.shows)..where((item) => item.tmdbId.equals(tmdbId));
    return await query.map((row) => row).getSingleOrNull();
  }

  /// Whether the show is in the library.
  Future<bool> exists(int tmdbId) async => await get(tmdbId) != null;

  /// The shows with the given ids; missing ones are simply absent.
  Future<Map<int, ShowEntity>> getMany(List<int> tmdbIds) async {
    if (tmdbIds.isEmpty) {
      return {};
    }
    final result = <int, ShowEntity>{};
    for (final chunk in tmdbIds.chunked(_lookupChunkSize)) {
      final query = _connectionManager.select(_connectionManager.shows)..where((item) => item.tmdbId.isIn(chunk));
      for (final show in await query.get()) {
        result[show.tmdbId] = show;
      }
    }
    return result;
  }

  /// Every tracked show.
  Future<List<ShowEntity>> getAll() => _connectionManager.select(_connectionManager.shows).get();

  /// Every tracked show id.
  Future<Set<int>> getAllIds() async {
    final query = _connectionManager.selectOnly(_connectionManager.shows)..addColumns([_connectionManager.shows.tmdbId]);
    final rows = await query.get();
    return rows.map((row) => row.read(_connectionManager.shows.tmdbId)!).toSet();
  }

  /// Shows with no snapshot yet (`fetched_at` NULL), oldest in the library first — the backfill's
  /// work list.
  Future<List<int>> getIdsWithoutSnapshot() async {
    final query = _connectionManager.selectOnly(_connectionManager.shows)
      ..addColumns([_connectionManager.shows.tmdbId])
      ..where(_connectionManager.shows.fetchedAt.isNull())
      ..orderBy([OrderingTerm(expression: _connectionManager.shows.trackedAt)]);
    final rows = await query.get();
    return rows.map((row) => row.read(_connectionManager.shows.tmdbId)!).toList();
  }

  /// Moves the freshness forward without changing anything else — what a TMDB 404 on a tracked
  /// show does, so the row is kept and silenced for one refresh interval.
  Future<void> stampFetched(int tmdbId, DateTime fetchedAt) async {
    await (_connectionManager.update(
      _connectionManager.shows,
    )..where((item) => item.tmdbId.equals(tmdbId))).write(ShowsCompanion(fetchedAt: Value(fetchedAt)));
  }

  /// Removes the row — the deferred-deletion sweep, after every reference is gone. Seasons,
  /// episodes and documents are removed by their own repos in the same transaction.
  Future<void> delete(int tmdbId) async {
    await (_connectionManager.delete(_connectionManager.shows)..where((item) => item.tmdbId.equals(tmdbId))).go();
  }

  /// Fires whenever the table changes, for the grids that render titles and artwork from it.
  Stream<void> listenForChanges() => _connectionManager.select(_connectionManager.shows).watch();

  /// Well below SQLite's default limit of 999 bound variables per statement.
  static const _lookupChunkSize = 500;
}
