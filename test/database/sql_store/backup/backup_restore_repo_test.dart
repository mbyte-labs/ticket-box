import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/backup/backup_restore_repo.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/pending_deletion/pending_deletion_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';

/// Guards [BackupRestoreRepo.replaceUserData]: every user table is swapped for the backup's rows,
/// the restore is a tracking action (a catalogue stub for every movie and show the restored rows
/// name, never touching a row that exists), the system-maintained show states go for the sweep to
/// recompute while the user's dropped ones stay, the pending deletions are cleared, and the
/// restored history rows get fresh ids.
void main() {
  late DatabaseConnectionManager db;
  late BackupRestoreRepo repo;
  late HistoryRepo historyRepo;
  late UserRatingRepo ratingRepo;
  late WatchlistRepo watchlistRepo;
  late FavoriteRepo favoriteRepo;
  late MovieRepo movieRepo;
  late ShowRepo showRepo;
  late ShowStateRepo showStateRepo;
  late PendingDeletionRepo pendingDeletionRepo;

  final at = DateTime.utc(2026, 7, 1);
  final now = DateTime.utc(2026, 8, 1, 10);

  NewHistoryEntry moviePlay(int tmdbId) => NewHistoryEntry.movie(tmdbId: tmdbId, action: HistoryAction.watch, watchedAt: at);

  NewHistoryEntry episodePlay(int showId, int season, int episode) =>
      NewHistoryEntry.episode(showTmdbId: showId, season: season, episode: episode, action: HistoryAction.watch, watchedAt: at);

  UserRatingEntity rating(ItemType type, int tmdbId, {int season = 0, int episode = 0}) =>
      UserRatingEntity.build(type: type, tmdbId: tmdbId, season: season, episode: episode, rating: 8, ratedAt: at);

  WatchlistEntity listed(ItemType type, int tmdbId, {int season = 0, int episode = 0}) =>
      WatchlistEntity.build(type: type, tmdbId: tmdbId, season: season, episode: episode, listedAt: at);

  FavoriteEntity favorite(ItemType type, int tmdbId) => FavoriteEntity.build(type: type, tmdbId: tmdbId, favoritedAt: at);

  MovieEntity movie(int tmdbId) {
    return MovieEntity.build(
      tmdbId: tmdbId,
      imdbId: null,
      title: 'Movie $tmdbId',
      year: 2020,
      overview: null,
      tagline: null,
      releaseDate: null,
      runtime: 100,
      certification: null,
      country: null,
      language: null,
      trailer: null,
      homepage: null,
      voteAverage: 7,
      voteCount: 10,
      popularity: 1,
      genres: '',
      status: null,
      posterPath: null,
      backdropPath: null,
      fetchedAt: at,
      trackedAt: at,
      watchProvidersRegion: null,
    );
  }

  ShowEntity show(int tmdbId) {
    return ShowEntity.build(
      tmdbId: tmdbId,
      imdbId: null,
      title: 'Show $tmdbId',
      year: 2020,
      overview: null,
      tagline: null,
      firstAirDate: null,
      lastAirDate: null,
      runtime: 40,
      certification: null,
      network: null,
      country: null,
      language: null,
      trailer: null,
      homepage: null,
      voteAverage: 7,
      voteCount: 10,
      popularity: 1,
      numberOfSeasons: 1,
      nextEpisodeAirDate: null,
      nextEpisodeSeason: null,
      nextEpisodeNumber: null,
      genres: '',
      status: null,
      posterPath: null,
      backdropPath: null,
      fetchedAt: at,
      trackedAt: at,
      watchProvidersRegion: null,
    );
  }

  Future<void> restore({
    List<NewHistoryEntry> history = const [],
    List<UserRatingEntity> ratings = const [],
    List<WatchlistEntity> watchlist = const [],
    List<FavoriteEntity>? favorites = const [],
  }) {
    return repo.replaceUserData(history: history, ratings: ratings, watchlist: watchlist, favorites: favorites, now: now);
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = BackupRestoreRepo();
    historyRepo = HistoryRepo();
    ratingRepo = UserRatingRepo();
    watchlistRepo = WatchlistRepo();
    favoriteRepo = FavoriteRepo();
    movieRepo = MovieRepo();
    showRepo = ShowRepo();
    showStateRepo = ShowStateRepo();
    pendingDeletionRepo = PendingDeletionRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('user tables', () {
    test('are replaced by the backup\'s rows', () async {
      await historyRepo.insertNew(moviePlay(100));
      await ratingRepo.insert(rating(ItemType.movie, 100));
      await watchlistRepo.insert(listed(ItemType.show, 100));
      await favoriteRepo.insert(favorite(ItemType.show, 100));

      await restore(
        history: [moviePlay(1), episodePlay(2, 1, 1)],
        ratings: [rating(ItemType.show, 2)],
        watchlist: [listed(ItemType.movie, 3)],
        favorites: [favorite(ItemType.movie, 1)],
      );

      final history = await historyRepo.getAll();
      expect(history.map((e) => (e.type, e.tmdbId)), unorderedEquals([(ItemType.movie, 1), (ItemType.episode, 2)]));
      expect((await ratingRepo.getAll()).map((e) => e.key), [rating(ItemType.show, 2).key]);
      expect((await watchlistRepo.getAll()).map((e) => e.key), [listed(ItemType.movie, 3).key]);
      expect((await favoriteRepo.getAll()).map((e) => e.key), [favorite(ItemType.movie, 1).key]);
    });

    test('a null favorites section keeps the device\'s favorites', () async {
      await favoriteRepo.insert(favorite(ItemType.show, 100));

      await restore(history: [moviePlay(1)], favorites: null);

      expect((await favoriteRepo.getAll()).map((e) => e.tmdbId), [100]);
      expect((await historyRepo.getAll()).map((e) => e.tmdbId), [1]);
    });

    test('an empty backup empties the tables', () async {
      await historyRepo.insertNew(moviePlay(100));
      await ratingRepo.insert(rating(ItemType.movie, 100));
      await watchlistRepo.insert(listed(ItemType.show, 100));
      await favoriteRepo.insert(favorite(ItemType.show, 100));

      await restore();

      expect(await historyRepo.getAll(), isEmpty);
      expect(await ratingRepo.getAll(), isEmpty);
      expect(await watchlistRepo.getAll(), isEmpty);
      expect(await favoriteRepo.getAll(), isEmpty);
    });
  });

  group('history ids', () {
    test('are fresh: the restored rows never reuse an id a deleted row had', () async {
      final oldId = await historyRepo.insertNew(moviePlay(100));
      await historyRepo.insertNew(moviePlay(101));

      await restore(history: [moviePlay(1), moviePlay(2), moviePlay(3)]);

      final restored = await historyRepo.getAll();
      expect(restored, hasLength(3));
      expect(restored.map((e) => e.historyId).toSet(), hasLength(3));
      expect(restored.every((e) => e.historyId > oldId + 1), isTrue, reason: 'AUTOINCREMENT continues past the deleted rows');
      expect(await historyRepo.getByHistoryId(oldId), isNull);
    });

    test('an entry restored twice in a row keeps counting upwards', () async {
      await restore(history: [moviePlay(1)]);
      final first = (await historyRepo.getAll()).single.historyId;

      await restore(history: [moviePlay(1)]);

      expect((await historyRepo.getAll()).single.historyId, greaterThan(first));
    });
  });

  group('catalogue stubs', () {
    test('are created for every movie and show the restored rows reference', () async {
      await restore(
        history: [moviePlay(1), episodePlay(2, 1, 1)],
        ratings: [rating(ItemType.movie, 3), rating(ItemType.show, 4), rating(ItemType.episode, 5, season: 1, episode: 2)],
        watchlist: [listed(ItemType.movie, 6), listed(ItemType.season, 7, season: 2)],
        favorites: [favorite(ItemType.movie, 8), favorite(ItemType.show, 9)],
      );

      expect(await movieRepo.getAllIds(), {1, 3, 6, 8});
      expect(await showRepo.getAllIds(), {2, 4, 5, 7, 9});
      final movie1 = await movieRepo.get(1);
      expect(movie1?.fetchedAt, isNull, reason: 'the backfill fetches the snapshot');
      expect(movie1?.title, isNull);
      // Compared as instants: drift reads DateTimes back in local time.
      expect(movie1?.trackedAt.toUtc(), now);
      final show5 = await showRepo.get(5);
      expect(show5?.fetchedAt, isNull);
      expect(show5?.trackedAt.toUtc(), now);
      expect(await movieRepo.getIdsWithoutSnapshot(), unorderedEquals([1, 3, 6, 8]));
      expect(await showRepo.getIdsWithoutSnapshot(), unorderedEquals([2, 4, 5, 7, 9]));
    });

    test('an id referenced by several rows gets one stub', () async {
      await restore(history: [moviePlay(1), moviePlay(1)], ratings: [rating(ItemType.movie, 1)], watchlist: [listed(ItemType.movie, 1)]);

      expect(await movieRepo.getAll(), hasLength(1));
    });

    test('leave an existing catalogue row untouched', () async {
      await movieRepo.insert(movie(1));
      await showRepo.insert(show(2));

      await restore(history: [moviePlay(1), episodePlay(2, 1, 1)]);

      final storedMovie = await movieRepo.get(1);
      expect(storedMovie?.title, 'Movie 1');
      expect(storedMovie?.fetchedAt?.toUtc(), at);
      expect(storedMovie?.trackedAt.toUtc(), at, reason: 'the movie did not enter the library again');
      final storedShow = await showRepo.get(2);
      expect(storedShow?.title, 'Show 2');
      expect(storedShow?.fetchedAt?.toUtc(), at);
      expect(storedShow?.trackedAt.toUtc(), at);
      expect(await movieRepo.getIdsWithoutSnapshot(), isEmpty);
      expect(await showRepo.getIdsWithoutSnapshot(), isEmpty);
    });

    test('a movie and a show with the same tmdb id each get their own stub', () async {
      await restore(history: [moviePlay(5), episodePlay(5, 1, 1)]);

      expect(await movieRepo.getAllIds(), {5});
      expect(await showRepo.getAllIds(), {5});
    });

    test('catalogue rows the backup does not reference are kept', () async {
      await movieRepo.insert(movie(100));
      await showRepo.insert(show(200));

      await restore(history: [moviePlay(1)]);

      expect(await movieRepo.getAllIds(), {1, 100});
      expect(await showRepo.getAllIds(), {200});
    });
  });

  group('show states', () {
    test('non-dropped states are deleted while dropped ones are kept', () async {
      await showStateRepo.upsert(1, ShowWatchStatus.watching, at);
      await showStateRepo.upsert(2, ShowWatchStatus.watched, at);
      await showStateRepo.upsert(3, ShowWatchStatus.dropped, at);

      await restore(history: [episodePlay(1, 1, 1)]);

      expect(await showStateRepo.getNonDroppedIds(), isEmpty, reason: 'the sweep recomputes them from the restored log');
      expect(await showStateRepo.getDroppedIds(), {3});
    });
  });

  group('pending deletions', () {
    test('are cleared', () async {
      await pendingDeletionRepo.enqueue(ItemType.movie, 1, at);
      await pendingDeletionRepo.enqueue(ItemType.show, 2, at);

      await restore(history: [moviePlay(1)]);

      expect(await pendingDeletionRepo.count(), 0);
    });
  });
}
