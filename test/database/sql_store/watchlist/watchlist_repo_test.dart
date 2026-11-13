import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';

/// Covers the type isolation [AddToHistoryService._clearWatchlist] leans on: a movie and a show
/// can share the same numeric TMDB id, and the ids of a show's season/episode rows are the
/// show's own, so every delete must discriminate on [ItemType]. The movie branch of the clear
/// used to be missing, which made marking a movie watched delete a show-typed row keyed on the
/// movie's id and then cascade into that show's season and episode rows.
void main() {
  late DatabaseConnectionManager db;
  late WatchlistRepo repo;

  // A movie and an unrelated show that happen to share one TMDB id.
  const sharedTmdbId = 42;

  WatchlistEntity entryFor(ItemType type, {int season = 0, int episode = 0}) {
    return WatchlistEntity.build(type: type, tmdbId: sharedTmdbId, season: season, episode: episode, listedAt: DateTime.utc(2026, 7, 30));
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = WatchlistRepo();

    await repo.insertAll([
      entryFor(ItemType.movie),
      entryFor(ItemType.show),
      entryFor(ItemType.season, season: 1),
      entryFor(ItemType.episode, season: 1, episode: 3),
    ]);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  test('count spans every item type', () async {
    expect(await repo.count(), 4);

    await repo.delete(sharedTmdbId, ItemType.movie);

    expect(await repo.count(), 3);
  });

  test('deleting the movie row leaves a show with the same tmdb id untouched', () async {
    // What _clearWatchlist's movie branch runs after a movie is marked watched.
    await repo.delete(sharedTmdbId, ItemType.movie);

    expect(await repo.getItem(ItemType.movie, sharedTmdbId), isNull);
    expect(await repo.getItem(ItemType.show, sharedTmdbId), isNotNull);
    expect(await repo.getItem(ItemType.season, sharedTmdbId, 1), isNotNull);
    expect(await repo.getItem(ItemType.episode, sharedTmdbId, 1, 3), isNotNull);
  });

  test('deleting the show row leaves a movie with the same tmdb id untouched', () async {
    await repo.delete(sharedTmdbId, ItemType.show);

    expect(await repo.getItem(ItemType.show, sharedTmdbId), isNull);
    expect(await repo.getItem(ItemType.movie, sharedTmdbId), isNotNull);
  });

  test('getAll returns every row, newest first', () async {
    // A fifth row listed after the four seeded at the same instant.
    await repo.insert(WatchlistEntity.build(type: ItemType.movie, tmdbId: 7, listedAt: DateTime.utc(2026, 8, 1)));

    final all = await repo.getAll();

    expect(all, hasLength(5));
    expect(all.first.tmdbId, 7);
    expect(all.map((e) => e.type), containsAll([ItemType.movie, ItemType.show, ItemType.season, ItemType.episode]));
  });

  test('the season and episode cascade never touches the movie row', () async {
    // The rest of the show-shaped cascade _clearWatchlist runs for an episode target.
    await repo.delete(sharedTmdbId, ItemType.show);
    await repo.deleteSeason(sharedTmdbId, 1);
    await repo.deleteEpisode(sharedTmdbId, 1, 3);

    expect(await repo.getItem(ItemType.movie, sharedTmdbId), isNotNull);
    expect(await repo.getItem(ItemType.season, sharedTmdbId, 1), isNull);
    expect(await repo.getItem(ItemType.episode, sharedTmdbId, 1, 3), isNull);
  });

  test('getByKey and deleteByKey address one row through its MediaKey', () async {
    const episodeKey = MediaKey.episode(sharedTmdbId, 1, 3);

    expect((await repo.getByKey(episodeKey))?.key, episodeKey);

    await repo.deleteByKey(episodeKey);

    expect(await repo.getByKey(episodeKey), isNull);
    expect(await repo.getByKey(const MediaKey.season(sharedTmdbId, 1)), isNotNull);
    expect(await repo.getByKey(const MediaKey.show(sharedTmdbId)), isNotNull);
    expect(await repo.getByKey(const MediaKey.movie(sharedTmdbId)), isNotNull);
  });

  test('deleteByType clears only that type', () async {
    await repo.deleteByType(ItemType.episode);

    final all = await repo.getAll();
    expect(all, hasLength(3));
    expect(all.map((e) => e.type), isNot(contains(ItemType.episode)));
  });

  test('replaceAll with an empty list clears the table', () async {
    await repo.replaceAll([]);

    expect(await repo.getAll(), isEmpty);
  });
}
