import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/key_value_store/keys/tmdb_account_keys.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/library/favorite_service.dart';
import 'package:ticketbox/service/library/rating_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_hooks.dart';
import 'package:ticketbox/service/watchlist/watchlist_service.dart';

import 'tmdb_test_support.dart';

/// The write services queue a TMDB copy of each change — only while logged in with the data set's
/// toggle on, and only for items that have a place on TMDB.
void main() {
  final harness = TmdbTestHarness();
  late TmdbSyncOutboxRepo outbox;
  late TmdbSyncHooks hooks;

  MarkAsWatchedTarget movie(int id) => MarkAsWatchedTarget(type: ItemType.movie, showTmdbId: id, title: 'm', subtitle: '');
  MarkAsWatchedTarget episode(int show, int s, int e) =>
      MarkAsWatchedTarget(type: ItemType.episode, showTmdbId: show, season: s, episode: e, title: 's', subtitle: '');

  setUp(() async {
    await harness.setUp(handler: TmdbTestHarness.ok);
    // The titles the tests write to are already in the library: a write on an untracked title
    // would first fetch it from TMDB, which this harness does not serve.
    final trackedAt = DateTime.utc(2026, 9, 1);
    await MovieRepo().insertStubs([550, 999], trackedAt: trackedAt);
    await ShowRepo().insertStubs([1396, 2000], trackedAt: trackedAt);
    outbox = TmdbSyncOutboxRepo();
    hooks = TmdbSyncHooks(outboxService: NoFlushOutboxService.new);
  });

  tearDown(harness.tearDown);

  test('nothing is queued while logged out', () async {
    await RatingService(hooks: hooks).addRating(target: movie(550), rating: 8);
    await WatchlistService(hooks: hooks).addMovie(550);
    await FavoriteService(hooks: hooks).favorite(ItemType.movie, 550);

    expect(await outbox.count(), 0);
  });

  test('nothing is queued for a data set whose toggle is off', () async {
    await harness.logIn(enabledToggles: {TmdbAccountKeys.syncRatings});

    await WatchlistService(hooks: hooks).addMovie(550);
    await FavoriteService(hooks: hooks).favorite(ItemType.movie, 550);

    expect(await outbox.count(), 0);
  });

  test('a rating and its removal are queued, the removal replacing the rating', () async {
    await harness.logIn(enabledToggles: {TmdbAccountKeys.syncRatings});
    final service = RatingService(hooks: hooks);

    await service.addRating(target: movie(550), rating: 8);
    expect((await outbox.getAll()).single.operation, TmdbSyncOperation.rate);
    expect((await outbox.getAll()).single.rating, 8);

    await service.removeRating(target: movie(550));
    final rows = await outbox.getAll();
    expect(rows.single.operation, TmdbSyncOperation.unrate);
    expect(rows.single.key, const MediaKey.movie(550));
  });

  test('an episode rating is queued under the show id and its numbers', () async {
    await harness.logIn(enabledToggles: {TmdbAccountKeys.syncRatings});

    await RatingService(hooks: hooks).addRating(target: episode(1396, 1, 2), rating: 9);

    expect((await outbox.getAll()).single.key, const MediaKey.episode(1396, 1, 2));
  });

  test('watchlist adds and removes of movies and shows are queued, season and episode rows are not', () async {
    await harness.logIn(enabledToggles: {TmdbAccountKeys.syncWatchlist});
    final service = WatchlistService(hooks: hooks);

    await service.addMovie(550);
    await service.addShow(1396);
    await service.addSeason(1396, 1);
    await service.addEpisode(1396, 1, 2);
    await service.removeShow(1396);

    final rows = await outbox.getAll();
    expect(rows.map((row) => (row.operation, row.key)), [
      (TmdbSyncOperation.watchlistAdd, const MediaKey.movie(550)),
      (TmdbSyncOperation.watchlistRemove, const MediaKey.show(1396)),
    ]);
    expect(await WatchlistRepo().count(), 3, reason: 'the local rows are written regardless');
  });

  test('favorite and unfavorite become favorite writes', () async {
    await harness.logIn(enabledToggles: {TmdbAccountKeys.syncFavorites});
    final service = FavoriteService(hooks: hooks);

    await service.favorite(ItemType.show, 1396);
    await service.unfavorite(ItemType.show, 1396);

    expect((await outbox.getAll()).single.operation, TmdbSyncOperation.favoriteRemove);
  });

  group('clearing the watchlist after a play', () {
    final now = DateTime.utc(2026, 10, 1);

    setUp(() async {
      await harness.logIn(enabledToggles: {TmdbAccountKeys.syncWatchlist});
      await WatchlistRepo().insertAll([
        WatchlistEntity.build(type: ItemType.show, tmdbId: 1396, listedAt: now),
        WatchlistEntity.build(type: ItemType.season, tmdbId: 1396, season: 1, listedAt: now),
        WatchlistEntity.build(type: ItemType.episode, tmdbId: 1396, season: 1, episode: 2, listedAt: now),
        WatchlistEntity.build(type: ItemType.movie, tmdbId: 550, listedAt: now),
      ]);
    });

    test('an episode play clears the show, season and episode rows and tells TMDB about the show', () async {
      await WatchlistService(hooks: hooks).clearForWatched(episode(1396, 1, 2));

      expect((await WatchlistRepo().getAll()).map((row) => row.key), [const MediaKey.movie(550)]);
      final rows = await outbox.getAll();
      expect(rows.map((row) => (row.operation, row.key)), [(TmdbSyncOperation.watchlistRemove, const MediaKey.show(1396))]);
    });

    test('a movie play clears only the movie row', () async {
      await WatchlistService(hooks: hooks).clearForWatched(movie(550));

      expect(await WatchlistRepo().count(), 3);
      expect((await outbox.getAll()).single.key, const MediaKey.movie(550));
    });

    test('a title that was not on the watchlist queues nothing', () async {
      await WatchlistService(hooks: hooks).clearForWatched(movie(999));
      await WatchlistService(hooks: hooks).clearForWatched(episode(2000, 1, 1));

      expect(await outbox.count(), 0);
    });
  });
}
