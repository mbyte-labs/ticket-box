import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/job_state/job_constants.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/catalog/catalog_refresh_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_initial_sync_service.dart';

import 'tmdb_test_support.dart';

/// The one-time pull / push: pull replaces local lists from every page, push sends what fits and
/// queues what TMDB would not take.
void main() {
  final harness = TmdbTestHarness();
  late Future<Response> Function(Request request) answer;
  final now = DateTime.utc(2026, 10, 1);

  TmdbInitialSyncService service() => TmdbInitialSyncService(outboxService: NoFlushOutboxService.new);

  setUp(() async {
    answer = TmdbTestHarness.ok;
    await harness.setUp(handler: (request) => answer(request));
    await harness.logIn();
    // A finished sync kicks the catalogue refresh without awaiting it; the real one would keep
    // using the database after the test closed it.
    GetIt.I.registerSingleton<CatalogRefreshService>(_NoTickRefresh());
  });

  tearDown(harness.tearDown);

  /// A TMDB account with two pages of rated movies, one rated show, two rated episodes, a
  /// watchlist and favorites.
  Future<Response> account(Request request) async {
    final path = request.url.path;
    final page = int.parse(request.url.queryParameters['page'] ?? '1');
    if (path.endsWith('/rated/movies')) {
      return page == 1
          ? TmdbTestHarness.page(1, 2, [
              {'id': 550, 'rating': 7.5},
              {'id': 551, 'rating': 10},
            ])
          : TmdbTestHarness.page(2, 2, [
              {'id': 552, 'rating': 0.5},
            ]);
    }
    if (path.endsWith('/rated/tv')) {
      return TmdbTestHarness.page(1, 1, [
        {'id': 1396, 'rating': 9},
      ]);
    }
    if (path.endsWith('/rated/tv/episodes')) {
      return TmdbTestHarness.page(1, 1, [
        {'id': 1, 'show_id': 1396, 'season_number': 1, 'episode_number': 1, 'rating': 8},
        {'id': 2, 'show_id': 1396, 'season_number': 1, 'episode_number': 2, 'rating': 6.5},
      ]);
    }
    if (path.endsWith('/watchlist/movies')) {
      return TmdbTestHarness.page(1, 1, [
        {'id': 603, 'title': 'The Matrix'},
      ]);
    }
    if (path.endsWith('/watchlist/tv')) {
      return TmdbTestHarness.page(1, 1, [
        {'id': 1399, 'name': 'Game of Thrones'},
      ]);
    }
    if (path.endsWith('/favorite/movies')) {
      return TmdbTestHarness.page(1, 1, []);
    }
    if (path.endsWith('/favorite/tv')) {
      return TmdbTestHarness.page(1, 1, [
        {'id': 1396, 'name': 'Breaking Bad'},
      ]);
    }
    return TmdbTestHarness.ok(request);
  }

  group('pull', () {
    setUp(() {
      answer = account;
    });

    test('ratings become a copy of TMDB, rounded, across every page', () async {
      await UserRatingRepo().insert(UserRatingEntity.build(type: ItemType.movie, tmdbId: 999, rating: 3, ratedAt: now));
      await TmdbSyncOutboxRepo().enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(999), rating: 3);

      final result = await service().run(
        const TmdbSyncChoices(ratings: TmdbSyncChoice.pull, watchlist: TmdbSyncChoice.skip, favorites: TmdbSyncChoice.skip),
      );

      expect(result.succeeded, isTrue);
      expect(result.perDataSet[TmdbDataSet.ratings], (pulled: 6, pushed: 0, queued: 0));
      final rows = await UserRatingRepo().getAll();
      final byKey = {for (final row in rows) row.key: row.rating};
      expect(byKey, {
        const MediaKey.movie(550): 8,
        const MediaKey.movie(551): 10,
        const MediaKey.movie(552): 1,
        const MediaKey.show(1396): 9,
        const MediaKey.episode(1396, 1, 1): 8,
        const MediaKey.episode(1396, 1, 2): 7,
      });
      expect(await TmdbSyncOutboxRepo().count(), 0, reason: 'pending pushes refer to the replaced list');
      expect(harness.session.isSyncEnabled(TmdbDataSet.ratings), isTrue);
      expect(harness.session.isSyncEnabled(TmdbDataSet.watchlist), isFalse);
    });

    test('a pulled watchlist replaces the movie and show rows but keeps seasons and episodes', () async {
      final repo = WatchlistRepo();
      await repo.insertAll([
        WatchlistEntity.build(type: ItemType.movie, tmdbId: 1, listedAt: now),
        WatchlistEntity.build(type: ItemType.show, tmdbId: 2, listedAt: now),
        WatchlistEntity.build(type: ItemType.season, tmdbId: 2, season: 1, listedAt: now),
        WatchlistEntity.build(type: ItemType.episode, tmdbId: 2, season: 1, episode: 3, listedAt: now),
      ]);

      final result = await service().run(
        const TmdbSyncChoices(ratings: TmdbSyncChoice.skip, watchlist: TmdbSyncChoice.pull, favorites: TmdbSyncChoice.skip),
      );

      expect(result.perDataSet[TmdbDataSet.watchlist], (pulled: 2, pushed: 0, queued: 0));
      final keys = (await repo.getAll()).map((row) => row.key).toSet();
      expect(keys, {const MediaKey.movie(603), const MediaKey.show(1399), const MediaKey.season(2, 1), const MediaKey.episode(2, 1, 3)});
    });

    test('TMDB favorites become the favorites list', () async {
      await FavoriteRepo().insert(FavoriteEntity.build(type: ItemType.movie, tmdbId: 1, favoritedAt: now));

      await service().run(
        const TmdbSyncChoices(ratings: TmdbSyncChoice.skip, watchlist: TmdbSyncChoice.skip, favorites: TmdbSyncChoice.pull),
      );

      expect((await FavoriteRepo().getAll()).map((row) => row.key), [const MediaKey.show(1396)]);
    });

    test('the job row runs and finishes', () async {
      await service().run(
        const TmdbSyncChoices(ratings: TmdbSyncChoice.pull, watchlist: TmdbSyncChoice.pull, favorites: TmdbSyncChoice.pull),
      );

      final job = await JobStateRepo().get(TMDB_SYNC_JOB_ID);
      expect(job.state, JobState.finished);
      expect(job.errorCode, JobErrorCode.none);
    });

    test('a pull that fails half-way changes nothing locally', () async {
      await UserRatingRepo().insert(UserRatingEntity.build(type: ItemType.movie, tmdbId: 999, rating: 3, ratedAt: now));
      answer = (request) async => request.url.path.endsWith('/rated/tv/episodes') ? Response('oops', 500) : account(request);

      final result = await service().run(
        const TmdbSyncChoices(ratings: TmdbSyncChoice.pull, watchlist: TmdbSyncChoice.skip, favorites: TmdbSyncChoice.skip),
      );

      expect(result.succeeded, isFalse);
      expect(result.errorCode, JobErrorCode.serviceDown);
      expect(result.failureMessage, isNotNull);
      expect((await UserRatingRepo().getAll()).single.tmdbId, 999);
      expect(harness.session.isSyncEnabled(TmdbDataSet.ratings), isFalse);
      expect((await JobStateRepo().get(TMDB_SYNC_JOB_ID)).state, JobState.failed);
    }, timeout: const Timeout(Duration(minutes: 1)));
  });

  group('push', () {
    setUp(() async {
      await UserRatingRepo().insertAll([
        UserRatingEntity.build(type: ItemType.movie, tmdbId: 550, rating: 8, ratedAt: now),
        UserRatingEntity.build(type: ItemType.show, tmdbId: 1396, rating: 9, ratedAt: now),
        UserRatingEntity.build(type: ItemType.episode, tmdbId: 1396, season: 1, episode: 2, rating: 7, ratedAt: now),
      ]);
      await WatchlistRepo().insertAll([
        WatchlistEntity.build(type: ItemType.movie, tmdbId: 603, listedAt: now),
        WatchlistEntity.build(type: ItemType.season, tmdbId: 1396, season: 2, listedAt: now),
      ]);
      await FavoriteRepo().insert(FavoriteEntity.build(type: ItemType.show, tmdbId: 1399, favoritedAt: now));
    });

    test('every local item with a place on TMDB is sent; season rows are not', () async {
      final result = await service().run(
        const TmdbSyncChoices(ratings: TmdbSyncChoice.push, watchlist: TmdbSyncChoice.push, favorites: TmdbSyncChoice.push),
      );

      expect(result.succeeded, isTrue);
      expect(result.perDataSet[TmdbDataSet.ratings], (pulled: 0, pushed: 3, queued: 0));
      expect(result.perDataSet[TmdbDataSet.watchlist], (pulled: 0, pushed: 1, queued: 0));
      expect(result.perDataSet[TmdbDataSet.favorites], (pulled: 0, pushed: 1, queued: 0));
      final calls = harness.requests.map((r) => '${r.method} ${r.url.path}').toSet();
      expect(calls, {
        'POST /3/movie/550/rating',
        'POST /3/tv/1396/rating',
        'POST /3/tv/1396/season/1/episode/2/rating',
        'POST /3/account/42/watchlist',
        'POST /3/account/42/favorite',
      });
      expect(await TmdbSyncOutboxRepo().count(), 0);
      expect(harness.session.enabledDataSets, TmdbDataSet.values.toSet());
    });

    test('a title TMDB refuses is queued for later and the rest still goes', () async {
      answer = (request) async =>
          request.url.path == '/3/tv/1396/rating' ? Response('{"status_code":5}', 422) : TmdbTestHarness.ok(request);

      final result = await service().run(
        const TmdbSyncChoices(ratings: TmdbSyncChoice.push, watchlist: TmdbSyncChoice.skip, favorites: TmdbSyncChoice.skip),
      );

      expect(result.succeeded, isTrue);
      expect(result.perDataSet[TmdbDataSet.ratings], (pulled: 0, pushed: 2, queued: 1));
      final queued = (await TmdbSyncOutboxRepo().getAll()).single;
      expect(queued.operation, TmdbSyncOperation.rate);
      expect(queued.key, const MediaKey.show(1396));
      expect(queued.rating, 9);
    });

    test('a vanished title is skipped rather than queued', () async {
      answer = (request) async =>
          request.url.path == '/3/movie/550/rating' ? Response('{"status_code":34}', 404) : TmdbTestHarness.ok(request);

      final result = await service().run(
        const TmdbSyncChoices(ratings: TmdbSyncChoice.push, watchlist: TmdbSyncChoice.skip, favorites: TmdbSyncChoice.skip),
      );

      expect(result.perDataSet[TmdbDataSet.ratings], (pulled: 0, pushed: 2, queued: 0));
      expect(await TmdbSyncOutboxRepo().count(), 0);
    });

    test('when TMDB cannot be reached everything is queued and the run still completes', () async {
      answer = (request) async => throw ClientException('no network');

      final result = await service().run(
        const TmdbSyncChoices(ratings: TmdbSyncChoice.push, watchlist: TmdbSyncChoice.skip, favorites: TmdbSyncChoice.skip),
      );

      expect(result.succeeded, isTrue);
      expect(result.perDataSet[TmdbDataSet.ratings], (pulled: 0, pushed: 0, queued: 3));
      expect(await TmdbSyncOutboxRepo().count(), 3);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('a session 401 invalidates the session and stops the run', () async {
      answer = (request) async => Response('{"status_code":3}', 401);

      final result = await service().run(
        const TmdbSyncChoices(ratings: TmdbSyncChoice.push, watchlist: TmdbSyncChoice.push, favorites: TmdbSyncChoice.skip),
      );

      expect(result.succeeded, isFalse);
      expect(result.failureMessage, contains('Log in again'));
      expect(harness.session.isLoggedIn, isFalse);
      expect(harness.session.sessionInvalid, isTrue);
      expect(harness.session.enabledDataSets, isEmpty, reason: 'no data set finished');
    });
  });

  test('skipping everything is a no-op that touches neither TMDB nor the toggles', () async {
    final result = await service().run(const TmdbSyncChoices.skipAll());

    expect(result.succeeded, isTrue);
    expect(result.perDataSet, isEmpty);
    expect(harness.requests, isEmpty);
    expect(harness.session.enabledDataSets, isEmpty);
  });
}

class _NoTickRefresh extends CatalogRefreshService {
  @override
  Future<void> tick() async {}
}
