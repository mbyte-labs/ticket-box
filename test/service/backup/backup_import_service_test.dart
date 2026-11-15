import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
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
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/backup/backup_export_service.dart';
import 'package:ticketbox/service/backup/backup_import_service.dart';
import 'package:ticketbox/service/catalog/catalog_refresh_service.dart';

/// A refresh that never reaches TMDB: the restore kicks one off for the stub rows' snapshots,
/// which is the catalogue's business, not this test's.
class _NoTickRefresh extends CatalogRefreshService {
  int ticks = 0;

  @override
  Future<void> tick() async {
    ticks++;
  }
}

/// Restoring a backup: the file written by [BackupExportService] parses back into the same user
/// rows, a restore replaces (never merges) the user tables in one go, every restored title gets a
/// catalogue stub row for the backfill while the show states are recomputed from the restored
/// log, and a bad file is rejected before anything is written. Most cases drive
/// [BackupRestoreRepo] directly; the service-level ones register a [CatalogRefreshService] whose
/// tick is a no-op, since the real one needs TMDB.
void main() {
  late DatabaseConnectionManager db;

  const movieTmdb = 101, showTmdb = 110, otherShowTmdb = 111;
  // Data that is on the device before the restore and must not survive it.
  const staleMovieTmdb = 900, staleShowTmdb = 910;
  // A show the user dropped before the restore: a dropped state is the user's and survives.
  const droppedShowTmdb = 920;

  final early = DateTime.utc(2026, 7, 29, 20);
  final later = DateTime.utc(2026, 7, 30, 12);
  final restoredAt = DateTime.utc(2026, 8, 1, 9);

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  Future<void> seedBackupSource() async {
    await HistoryRepo().insertAll([
      HistoryEntity.build(historyId: 1, tmdbId: movieTmdb, type: ItemType.movie, action: HistoryAction.watch, watchedAt: early),
      HistoryEntity.build(
        historyId: 2,
        tmdbId: showTmdb,
        season: 1,
        episode: 1,
        type: ItemType.episode,
        action: HistoryAction.scrobble,
        watchedAt: early,
      ),
      HistoryEntity.build(
        historyId: 3,
        tmdbId: showTmdb,
        season: 1,
        episode: 2,
        type: ItemType.episode,
        action: HistoryAction.checkin,
        watchedAt: later,
      ),
      HistoryEntity.build(
        historyId: 4,
        tmdbId: otherShowTmdb,
        season: 2,
        episode: 5,
        type: ItemType.episode,
        action: HistoryAction.watch,
        watchedAt: early,
      ),
    ]);
    await UserRatingRepo().insertAll([
      UserRatingEntity.build(type: ItemType.movie, tmdbId: movieTmdb, rating: 8, ratedAt: early),
      UserRatingEntity.build(type: ItemType.show, tmdbId: showTmdb, rating: 9, ratedAt: early),
      UserRatingEntity.build(type: ItemType.episode, tmdbId: showTmdb, season: 1, episode: 2, rating: 10, ratedAt: later),
    ]);
    await WatchlistRepo().insertAll([
      WatchlistEntity.build(type: ItemType.movie, tmdbId: movieTmdb, listedAt: early),
      WatchlistEntity.build(type: ItemType.season, tmdbId: showTmdb, season: 2, listedAt: early),
      WatchlistEntity.build(type: ItemType.episode, tmdbId: showTmdb, season: 2, episode: 1, listedAt: later),
    ]);
    await FavoriteRepo().insertAll([
      FavoriteEntity.build(type: ItemType.movie, tmdbId: movieTmdb, favoritedAt: early),
      FavoriteEntity.build(type: ItemType.show, tmdbId: showTmdb, favoritedAt: later),
    ]);
  }

  /// Replaces every user table with unrelated rows, plus a tracked movie, a computed state and a
  /// pending deletion the backup knows nothing about, and one dropped show that must survive.
  Future<void> seedStaleDeviceData() async {
    await db.delete(db.historyItems).go();
    await db.delete(db.userRatings).go();
    await db.delete(db.watchlists).go();
    await db.delete(db.favoriteItems).go();
    await HistoryRepo().insertAllNew([
      NewHistoryEntry(type: ItemType.movie, tmdbId: staleMovieTmdb, action: HistoryAction.watch, watchedAt: later),
      NewHistoryEntry(type: ItemType.episode, tmdbId: staleShowTmdb, season: 1, episode: 1, action: HistoryAction.watch, watchedAt: later),
    ]);
    await UserRatingRepo().insert(UserRatingEntity.build(type: ItemType.movie, tmdbId: staleMovieTmdb, rating: 3, ratedAt: later));
    await WatchlistRepo().insert(WatchlistEntity.build(type: ItemType.movie, tmdbId: staleMovieTmdb, listedAt: later));
    await FavoriteRepo().insert(FavoriteEntity.build(type: ItemType.movie, tmdbId: staleMovieTmdb, favoritedAt: later));
    await MovieRepo().insert(MovieEntity.stub(tmdbId: staleMovieTmdb, trackedAt: early)..fetchedAt = later);
    await ShowRepo().insert(ShowEntity.stub(tmdbId: staleShowTmdb, trackedAt: early)..fetchedAt = later);
    await ShowStateRepo().upsert(staleShowTmdb, ShowWatchStatus.watching, later);
    await ShowStateRepo().upsert(droppedShowTmdb, ShowWatchStatus.dropped, later);
    await PendingDeletionRepo().enqueue(ItemType.movie, movieTmdb, later);
  }

  Future<void> restore(BackupContents contents) => BackupRestoreRepo().replaceUserData(
    history: contents.history,
    ratings: contents.ratings,
    watchlist: contents.watchlist,
    favorites: contents.favorites,
    now: restoredAt,
  );

  String historySignature(HistoryEntity e) => '${e.type.name}:${e.tmdbId}:${e.season}:${e.episode}:${e.action.name}:${e.watchedAt.toUtc()}';
  String ratingSignature(UserRatingEntity e) => '${e.type.name}:${e.tmdbId}:${e.season}:${e.episode}:${e.rating}:${e.ratedAt.toUtc()}';
  String watchlistSignature(WatchlistEntity e) => '${e.type.name}:${e.tmdbId}:${e.season}:${e.episode}:${e.listedAt.toUtc()}';
  String favoriteSignature(FavoriteEntity e) => '${e.type.name}:${e.tmdbId}:${e.favoritedAt.toUtc()}';

  Future<Map<String, Set<String>>> snapshot() async => {
    'history': (await HistoryRepo().getAll()).map(historySignature).toSet(),
    'ratings': (await UserRatingRepo().getAll()).map(ratingSignature).toSet(),
    'watchlist': (await WatchlistRepo().getAll()).map(watchlistSignature).toSet(),
    'favorites': (await FavoriteRepo().getAll()).map(favoriteSignature).toSet(),
  };

  test('an exported backup restores to the same user rows, replacing what was on the device', () async {
    await seedBackupSource();
    final before = await snapshot();
    final json = jsonEncode(await BackupExportService().buildBackupPayload());

    await seedStaleDeviceData();
    final contents = BackupImportService().parse(json);
    await restore(contents);

    expect(await snapshot(), before);
    expect((await HistoryRepo().getAll()).length, 4);
  });

  test('a version 4 backup restores its recommended section as the favorites', () async {
    await seedBackupSource();
    final expected = (await snapshot())['favorites'];
    final payload = await BackupExportService().buildBackupPayload();
    final section = (payload.remove('favorites') as List).cast<Map<String, dynamic>>();
    payload
      ..['schemaVersion'] = 4
      ..['recommended'] = [
        for (final entry in section) {...entry, 'recommendedAt': entry.remove('favoritedAt')},
      ];
    await seedStaleDeviceData();

    final contents = BackupImportService().parse(jsonEncode(payload));
    expect(contents.favorites, isNotNull);
    await restore(contents);

    expect((await snapshot())['favorites'], expected);
    expect(expected, isNotEmpty);
  });

  test('restored plays get fresh ids past every previous one', () async {
    await seedBackupSource();
    final json = jsonEncode(await BackupExportService().buildBackupPayload());
    await seedStaleDeviceData();
    final staleIds = (await HistoryRepo().getAll()).map((e) => e.historyId).toSet();

    await restore(BackupImportService().parse(json));

    final ids = (await HistoryRepo().getAll()).map((e) => e.historyId);
    expect(ids.every((id) => id > staleIds.reduce((a, b) => a > b ? a : b)), isTrue);
  });

  test('every restored title gets a catalogue stub row, tracked at the restore, for the backfill', () async {
    await seedBackupSource();
    final json = jsonEncode(await BackupExportService().buildBackupPayload());
    await seedStaleDeviceData();

    await restore(BackupImportService().parse(json));

    final movie = (await MovieRepo().get(movieTmdb))!;
    expect(movie.fetchedAt, isNull);
    expect(movie.trackedAt.toUtc(), restoredAt);
    expect(movie.hasSnapshot, isFalse);
    for (final id in [showTmdb, otherShowTmdb]) {
      final show = (await ShowRepo().get(id))!;
      expect(show.fetchedAt, isNull, reason: 'show $id');
      expect(show.trackedAt.toUtc(), restoredAt, reason: 'show $id');
    }
    // A title the device already tracks keeps its row as it was: the stub is insert-or-ignore.
    final stale = (await MovieRepo().get(staleMovieTmdb))!;
    expect(stale.fetchedAt, isNotNull);
    expect(stale.trackedAt.toUtc(), early);
  });

  test('a restore keeps the dropped states, drops the computed ones and clears the pending deletions', () async {
    await seedBackupSource();
    final json = jsonEncode(await BackupExportService().buildBackupPayload());
    await seedStaleDeviceData();

    await restore(BackupImportService().parse(json));

    expect((await ShowStateRepo().get(droppedShowTmdb))?.status, ShowWatchStatus.dropped);
    expect(await ShowStateRepo().get(staleShowTmdb), isNull, reason: 'a computed state is recomputed from the restored log');
    expect(await PendingDeletionRepo().getAll(), isEmpty);
  });

  group('through the service', () {
    late _NoTickRefresh refresh;

    setUp(() {
      refresh = _NoTickRefresh();
      GetIt.I.registerSingleton<CatalogRefreshService>(refresh);
    });

    test('recomputes the show states from the restored plays and starts the catalogue refresh', () async {
      await seedBackupSource();
      final json = jsonEncode(await BackupExportService().buildBackupPayload());
      await seedStaleDeviceData();
      await TmdbSyncOutboxRepo().enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(staleMovieTmdb), rating: 3);

      await BackupImportService().restore(BackupImportService().parse(json));

      // A show with plays and no episode rows yet is watching, never watched.
      expect((await ShowStateRepo().get(showTmdb))?.status, ShowWatchStatus.watching);
      expect((await ShowStateRepo().get(otherShowTmdb))?.status, ShowWatchStatus.watching);
      expect((await ShowStateRepo().get(droppedShowTmdb))?.status, ShowWatchStatus.dropped);
      expect(await ShowStateRepo().get(staleShowTmdb), isNull);
      // The tracked titles nothing references any more go to the deletion sweep.
      expect(
        (await PendingDeletionRepo().getAll()).map((e) => (e.type, e.tmdbId)),
        unorderedEquals([(ItemType.movie, staleMovieTmdb), (ItemType.show, staleShowTmdb)]),
      );
      expect(await TmdbSyncOutboxRepo().count(), 0, reason: 'queued pushes refer to the replaced data');
      expect(refresh.ticks, 1);
    });
  });

  test('a version 3 backup keeps the current favorites', () async {
    await seedBackupSource();
    final payload = await BackupExportService().buildBackupPayload();
    payload
      ..['schemaVersion'] = 3
      ..remove('favorites');
    await seedStaleDeviceData();

    final contents = BackupImportService().parse(jsonEncode(payload));
    expect(contents.favorites, isNull);
    await restore(contents);

    expect((await FavoriteRepo().getAll()).map((e) => e.tmdbId), [staleMovieTmdb]);
    expect((await HistoryRepo().getAll()).length, 4);
  });

  test('season ratings are skipped, other entries are kept', () {
    final contents = BackupImportService().parse(
      jsonEncode({
        'schemaVersion': 5,
        'exportedAt': '2026-07-30T12:00:00.000Z',
        'history': <Object>[],
        'ratings': [
          {'type': 'season', 'tmdbId': 5, 'showTmdbId': showTmdb, 'season': 1, 'rating': 7, 'ratedAt': '2026-07-30T12:00:00.000Z'},
          {
            'type': 'episode',
            'tmdbId': null,
            'imdbId': null,
            'showTmdbId': showTmdb,
            'season': 1,
            'episode': 3,
            'rating': 6,
            'ratedAt': '2026-07-30T12:00:00.000Z',
          },
        ],
        'watchlist': <Object>[],
        'favorites': <Object>[],
      }),
    );

    expect(contents.ratings.map((e) => (e.type, e.tmdbId, e.season, e.episode)), [(ItemType.episode, showTmdb, 1, 3)]);
    expect(contents.exportedAt, DateTime.utc(2026, 7, 30, 12));
  });

  group('rejects', () {
    Map<String, dynamic> valid() => {
      'schemaVersion': 5,
      'exportedAt': '2026-07-30T12:00:00.000Z',
      'history': [
        {'type': 'movie', 'tmdbId': movieTmdb, 'imdbId': null, 'addedAt': '2026-07-30T12:00:00.000Z', 'historyType': 'watch'},
      ],
      'ratings': <Object>[],
      'watchlist': <Object>[],
      'favorites': <Object>[],
    };

    /// [valid] with one key of its single history entry overwritten.
    Map<String, dynamic> withHistoryKey(String key, Object value) {
      final json = valid();
      (json['history'] as List).cast<Map<String, dynamic>>().single[key] = value;
      return json;
    }

    void expectRejected(Object json) {
      expect(() => BackupImportService().parse(json is String ? json : jsonEncode(json)), throwsA(isA<BackupFormatException>()));
    }

    test('the valid baseline parses', () => expect(BackupImportService().parse(jsonEncode(valid())).history, hasLength(1)));
    test('non-JSON', () => expectRejected('not json {'));
    test('a non-object root', () => expectRejected([1, 2]));
    test('an object without the backup keys', () => expectRejected({'foo': 1}));
    test('an older schema version', () => expectRejected(valid()..['schemaVersion'] = 2));
    test('a newer schema version', () => expectRejected(valid()..['schemaVersion'] = 6));
    test('a missing section', () => expectRejected(valid()..remove('watchlist')));
    test('a bad timestamp', () => expectRejected(withHistoryKey('addedAt', 'yesterday')));
    test('an unknown type', () => expectRejected(withHistoryKey('type', 'podcast')));
    test('an unknown history action', () => expectRejected(withHistoryKey('historyType', 'binge')));
    test('an episode without its show id', () {
      expectRejected(
        valid()
          ..['history'] = [
            {'type': 'episode', 'tmdbId': 1, 'season': 1, 'episode': 1, 'addedAt': '2026-07-30T12:00:00.000Z', 'historyType': 'watch'},
          ],
      );
    });
    test('an out-of-range rating', () {
      expectRejected(
        valid()
          ..['ratings'] = [
            {'type': 'movie', 'tmdbId': movieTmdb, 'rating': 11, 'ratedAt': '2026-07-30T12:00:00.000Z'},
          ],
      );
    });
  });
}
