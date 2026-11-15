import 'package:drift/drift.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';

/// The tracked movies. A row exists iff the movie is in the library; nothing here writes one for a
/// browsed title — that is the tracking service's job, together with the snapshot document.
class MovieRepo {
  final DatabaseConnectionManager _connectionManager;

  MovieRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  /// Inserts or replaces the whole row (a snapshot write).
  Future<void> insert(MovieEntity item) async {
    await _connectionManager.into(_connectionManager.movies).insertOnConflictUpdate(item.toInsertable());
  }

  Future<void> insertAll(List<MovieEntity> items) async {
    if (items.isEmpty) {
      return;
    }
    await _connectionManager.batch((batch) {
      batch.insertAllOnConflictUpdate(_connectionManager.movies, items.map((e) => e.toInsertable()).toList());
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
      batch.insertAll(_connectionManager.movies, [
        for (final id in ids) MoviesCompanion.insert(tmdbId: Value(id), trackedAt: trackedAt),
      ], mode: InsertMode.insertOrIgnore);
    });
  }

  Future<MovieEntity?> get(int tmdbId) async {
    final query = _connectionManager.select(_connectionManager.movies)..where((item) => item.tmdbId.equals(tmdbId));
    return await query.map((row) => row).getSingleOrNull();
  }

  /// Whether the movie is in the library.
  Future<bool> exists(int tmdbId) async => await get(tmdbId) != null;

  /// The movies with the given ids; missing ones are simply absent.
  Future<Map<int, MovieEntity>> getMany(List<int> tmdbIds) async {
    if (tmdbIds.isEmpty) {
      return {};
    }
    final result = <int, MovieEntity>{};
    for (final chunk in tmdbIds.chunked(_lookupChunkSize)) {
      final query = _connectionManager.select(_connectionManager.movies)..where((item) => item.tmdbId.isIn(chunk));
      for (final movie in await query.get()) {
        result[movie.tmdbId] = movie;
      }
    }
    return result;
  }

  /// Every tracked movie.
  Future<List<MovieEntity>> getAll() => _connectionManager.select(_connectionManager.movies).get();

  /// Every tracked movie id.
  Future<Set<int>> getAllIds() async {
    final query = _connectionManager.selectOnly(_connectionManager.movies)..addColumns([_connectionManager.movies.tmdbId]);
    final rows = await query.get();
    return rows.map((row) => row.read(_connectionManager.movies.tmdbId)!).toSet();
  }

  /// Movies with no snapshot yet (`fetched_at` NULL), oldest in the library first — the backfill's
  /// work list.
  Future<List<int>> getIdsWithoutSnapshot() async {
    final query = _connectionManager.selectOnly(_connectionManager.movies)
      ..addColumns([_connectionManager.movies.tmdbId])
      ..where(_connectionManager.movies.fetchedAt.isNull())
      ..orderBy([OrderingTerm(expression: _connectionManager.movies.trackedAt)]);
    final rows = await query.get();
    return rows.map((row) => row.read(_connectionManager.movies.tmdbId)!).toList();
  }

  /// Moves the freshness forward without changing anything else — what a TMDB 404 on a tracked
  /// movie does, so the row is kept and silenced for one refresh interval.
  Future<void> stampFetched(int tmdbId, DateTime fetchedAt) async {
    await (_connectionManager.update(
      _connectionManager.movies,
    )..where((item) => item.tmdbId.equals(tmdbId))).write(MoviesCompanion(fetchedAt: Value(fetchedAt)));
  }

  /// Removes the row — the deferred-deletion sweep, after every reference is gone.
  Future<void> delete(int tmdbId) async {
    await (_connectionManager.delete(_connectionManager.movies)..where((item) => item.tmdbId.equals(tmdbId))).go();
  }

  /// Fires whenever the table changes, for the grids that render titles and artwork from it.
  Stream<void> listenForChanges() => _connectionManager.select(_connectionManager.movies).watch();

  /// Well below SQLite's default limit of 999 bound variables per statement.
  static const _lookupChunkSize = 500;
}
