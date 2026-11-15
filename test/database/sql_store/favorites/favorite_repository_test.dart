import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';

/// A movie and a show can share the same numeric TMDB id, so every read and delete must
/// discriminate on [ItemType]; and the Favorites page filters by type in SQL, newest first.
void main() {
  late DatabaseConnectionManager db;
  late FavoriteRepo repo;

  // A movie and an unrelated show that happen to share one TMDB id.
  const sharedTmdbId = 42;
  final seededAt = DateTime.utc(2026, 7, 30);

  FavoriteEntity entryFor(ItemType type, {int tmdbId = sharedTmdbId, DateTime? at}) {
    return FavoriteEntity.build(type: type, tmdbId: tmdbId, favoritedAt: at ?? seededAt);
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = FavoriteRepo();

    await repo.insertAll([entryFor(ItemType.movie), entryFor(ItemType.show)]);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  test('count spans both item types', () async {
    expect(await repo.count(), 2);

    await repo.delete(ItemType.movie, sharedTmdbId);

    expect(await repo.count(), 1);
  });

  test('deleting the movie row leaves a show with the same tmdb id untouched', () async {
    await repo.delete(ItemType.movie, sharedTmdbId);

    expect(await repo.get(ItemType.movie, sharedTmdbId), isNull);
    expect(await repo.get(ItemType.show, sharedTmdbId), isNotNull);
  });

  test('deleting the show row leaves a movie with the same tmdb id untouched', () async {
    await repo.delete(ItemType.show, sharedTmdbId);

    expect(await repo.get(ItemType.show, sharedTmdbId), isNull);
    expect(await repo.get(ItemType.movie, sharedTmdbId), isNotNull);
  });

  test('the entity exposes the movie or show MediaKey', () async {
    expect((await repo.get(ItemType.movie, sharedTmdbId))?.key, const MediaKey.movie(sharedTmdbId));
    expect((await repo.get(ItemType.show, sharedTmdbId))?.key, const MediaKey.show(sharedTmdbId));
  });

  test('getAllNewestFirst orders by favoritedAt descending and filters by type', () async {
    await repo.insert(entryFor(ItemType.movie, tmdbId: 7, at: DateTime.utc(2026, 8, 1)));
    await repo.insert(entryFor(ItemType.show, tmdbId: 8, at: DateTime.utc(2026, 8, 2)));

    final everything = await repo.getAllNewestFirst([ItemType.movie, ItemType.show]);
    expect(everything.map((e) => (e.type, e.tmdbId)).take(2), [(ItemType.show, 8), (ItemType.movie, 7)]);
    expect(everything, hasLength(4));

    final movies = await repo.getAllNewestFirst([ItemType.movie]);
    expect(movies.map((e) => (e.type, e.tmdbId)), [(ItemType.movie, 7), (ItemType.movie, sharedTmdbId)]);

    final shows = await repo.getAllNewestFirst([ItemType.show]);
    expect(shows.map((e) => (e.type, e.tmdbId)), [(ItemType.show, 8), (ItemType.show, sharedTmdbId)]);
  });

  test('getAllNewestFirst with no types returns nothing rather than running an empty IN', () async {
    expect(await repo.getAllNewestFirst([]), isEmpty);
  });

  test('getAll returns every row, newest first', () async {
    await repo.insert(entryFor(ItemType.movie, tmdbId: 7, at: DateTime.utc(2026, 8, 1)));

    final all = await repo.getAll();

    expect(all, hasLength(3));
    expect(all.first.tmdbId, 7);
  });

  test('inserting an existing key updates its timestamp instead of adding a row', () async {
    final later = DateTime.utc(2026, 9, 1);

    await repo.insert(entryFor(ItemType.movie, at: later));

    expect(await repo.count(), 2);
    expect((await repo.get(ItemType.movie, sharedTmdbId))?.favoritedAt.toUtc(), later);
  });

  test('replaceAll with an empty list clears the table', () async {
    await repo.replaceAll([]);

    expect(await repo.getAll(), isEmpty);
  });

  test('subscribe emits the whole list after a write', () async {
    final emissions = <int>[];
    final subscription = repo.subscribe().listen((rows) => emissions.add(rows.length));
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await repo.insert(entryFor(ItemType.show, tmdbId: 8));
    await pumpEventQueue();

    expect(emissions, [2, 3]);
  });
}
