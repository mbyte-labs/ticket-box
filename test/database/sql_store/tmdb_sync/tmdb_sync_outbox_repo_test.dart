import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';

/// The outbox keeps one row per data set and key — the newest intent — and hands them out in the
/// order they were queued.
void main() {
  late DatabaseConnectionManager db;
  late TmdbSyncOutboxRepo repo;

  setUp(() {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = TmdbSyncOutboxRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  test('a newer rating of the same title replaces the pending one', () async {
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(550), rating: 7);
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(550), rating: 8);

    final rows = await repo.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.operation, TmdbSyncOperation.rate);
    expect(rows.single.rating, 8);
  });

  test('a remove after an add leaves the remove: the add may already have reached TMDB', () async {
    await repo.enqueue(operation: TmdbSyncOperation.watchlistAdd, key: const MediaKey.show(1396));
    await repo.enqueue(operation: TmdbSyncOperation.watchlistRemove, key: const MediaKey.show(1396));

    final rows = await repo.getAll();
    expect(rows.map((row) => row.operation), [TmdbSyncOperation.watchlistRemove]);
  });

  test('operations of different data sets for the same key coexist', () async {
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(550), rating: 9);
    await repo.enqueue(operation: TmdbSyncOperation.watchlistRemove, key: const MediaKey.movie(550));
    await repo.enqueue(operation: TmdbSyncOperation.favoriteAdd, key: const MediaKey.movie(550));

    expect(await repo.count(), 3);
  });

  test('a movie and a show sharing a tmdb id are two rows', () async {
    await repo.enqueue(operation: TmdbSyncOperation.favoriteAdd, key: const MediaKey.movie(42));
    await repo.enqueue(operation: TmdbSyncOperation.favoriteAdd, key: const MediaKey.show(42));

    expect(await repo.count(), 2);
  });

  test('episodes of one show are keyed by their numbers', () async {
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.episode(1396, 1, 1), rating: 8);
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.episode(1396, 1, 2), rating: 9);
    await repo.enqueue(operation: TmdbSyncOperation.unrate, key: const MediaKey.episode(1396, 1, 1));

    final rows = await repo.getAll();
    expect(rows.map((row) => (row.operation, row.episode)), [(TmdbSyncOperation.rate, 2), (TmdbSyncOperation.unrate, 1)]);
  });

  test('pending rows come back oldest first, after a given id', () async {
    final first = await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(1), rating: 5);
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(2), rating: 6);
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(3), rating: 7);

    expect((await repo.getPending(2)).map((row) => row.tmdbId), [1, 2]);
    expect((await repo.getPending(10, afterId: first)).map((row) => row.tmdbId), [2, 3]);
  });

  test('a failed attempt is counted and its reason kept', () async {
    final id = await repo.enqueue(operation: TmdbSyncOperation.favoriteAdd, key: const MediaKey.movie(550));

    await repo.markAttempt(id, 'networkError');
    await repo.markAttempt(id, 'serviceDown');

    final row = (await repo.getAll()).single;
    expect(row.attempts, 2);
    expect(row.lastError, 'serviceDown');
  });

  test('deleting by data set leaves the other data sets alone', () async {
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(550), rating: 9);
    await repo.enqueue(operation: TmdbSyncOperation.unrate, key: const MediaKey.show(1396));
    await repo.enqueue(operation: TmdbSyncOperation.watchlistAdd, key: const MediaKey.movie(550));

    await repo.deleteByDataSet(TmdbDataSet.ratings);

    final rows = await repo.getAll();
    expect(rows.map((row) => row.operation), [TmdbSyncOperation.watchlistAdd]);
  });

  test('the count stream follows the queue', () async {
    final counts = <int>[];
    final subscription = repo.watchCount().listen(counts.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(1), rating: 5);
    await pumpEventQueue();
    await repo.deleteAll();
    await pumpEventQueue();

    expect(counts, [0, 1, 0]);
  });
}
