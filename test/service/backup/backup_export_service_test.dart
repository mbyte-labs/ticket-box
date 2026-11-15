import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/backup/backup_export_service.dart';

/// Pins the `schemaVersion` 5 backup shape an external importer (sofalog) is built against: the
/// exact key sets per entry type, the show-scoped keys appearing only on season/episode entries,
/// a season's or episode's own TMDB id recovered from the cached catalogue by number, an entry
/// kept with a `null` tmdb id when its show is not cached, every timestamp written as UTC `Z`,
/// and the `favorites` section (version 4 added it as `recommended`, version 5 renamed it).
void main() {
  late DatabaseConnectionManager db;

  // One movie and one show with a season and an episode, all cached locally.
  const movieTmdb = 101, movieImdb = 'tt0000101';
  const showTmdb = 110, showImdb = 'tt0000110';
  const seasonTmdb = 120, seasonNumber = 1;
  const episodeTmdb = 130, episodeImdb = 'tt0000130', episodeNumber = 3;
  // A show the library never cached.
  const missingShowTmdb = 99;

  final instant = DateTime.utc(2026, 7, 30, 12);
  const instantIso = '2026-07-30T12:00:00.000Z';
  final synced = DateTime.utc(2026, 7, 1);

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);

    await MovieRepo().insertAll([MovieEntity.stub(tmdbId: movieTmdb, trackedAt: synced, title: 'Movie')..imdbId = movieImdb]);
    await ShowRepo().insertAll([ShowEntity.stub(tmdbId: showTmdb, trackedAt: synced, title: 'Show')..imdbId = showImdb]);
    await SeasonRepo().insertAll([
      SeasonEntity.build(
        showTmdbId: showTmdb,
        season: seasonNumber,
        tmdbId: seasonTmdb,
        title: null,
        episodeCount: 10,
        airDate: null,
        posterPath: null,
        fetchedAt: synced,
      ),
    ]);
    await EpisodeRepo().insertAll([
      EpisodeEntity.build(
        showTmdbId: showTmdb,
        season: seasonNumber,
        episode: episodeNumber,
        tmdbId: episodeTmdb,
        imdbId: episodeImdb,
        title: null,
        overview: null,
        voteAverage: 0,
        voteCount: 0,
        runtime: null,
        airDate: null,
        episodeType: null,
        stillPath: null,
      ),
    ]);

    await HistoryRepo().insertAll([
      HistoryEntity.build(historyId: 1, tmdbId: movieTmdb, type: ItemType.movie, action: HistoryAction.watch, watchedAt: instant),
      HistoryEntity.build(
        historyId: 2,
        tmdbId: showTmdb,
        season: seasonNumber,
        episode: episodeNumber,
        type: ItemType.episode,
        action: HistoryAction.scrobble,
        watchedAt: instant,
      ),
      HistoryEntity.build(
        historyId: 3,
        tmdbId: missingShowTmdb,
        season: 2,
        episode: 1,
        type: ItemType.episode,
        action: HistoryAction.checkin,
        watchedAt: instant,
      ),
    ]);
    await UserRatingRepo().insertAll([
      UserRatingEntity.build(type: ItemType.movie, tmdbId: movieTmdb, rating: 8, ratedAt: instant),
      UserRatingEntity.build(type: ItemType.show, tmdbId: showTmdb, rating: 9, ratedAt: instant),
      UserRatingEntity.build(type: ItemType.season, tmdbId: showTmdb, season: seasonNumber, rating: 7, ratedAt: instant),
      UserRatingEntity.build(
        type: ItemType.episode,
        tmdbId: showTmdb,
        season: seasonNumber,
        episode: episodeNumber,
        rating: 10,
        ratedAt: instant,
      ),
    ]);
    await WatchlistRepo().insertAll([
      WatchlistEntity.build(type: ItemType.movie, tmdbId: movieTmdb, listedAt: instant),
      WatchlistEntity.build(type: ItemType.show, tmdbId: showTmdb, listedAt: instant),
      WatchlistEntity.build(type: ItemType.season, tmdbId: showTmdb, season: seasonNumber, listedAt: instant),
      WatchlistEntity.build(type: ItemType.episode, tmdbId: showTmdb, season: seasonNumber, episode: episodeNumber, listedAt: instant),
    ]);
    await FavoriteRepo().insertAll([
      FavoriteEntity.build(type: ItemType.movie, tmdbId: movieTmdb, favoritedAt: instant),
      FavoriteEntity.build(type: ItemType.show, tmdbId: showTmdb, favoritedAt: instant),
    ]);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  Future<Map<String, dynamic>> payload() => BackupExportService().buildBackupPayload();

  List<Map<String, dynamic>> section(Map<String, dynamic> json, String key) => (json[key] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic> entry(Map<String, dynamic> json, String key, ItemType type) =>
      section(json, key).singleWhere((e) => e['type'] == type.name);

  test('the payload is schemaVersion 5 with exactly the documented top-level keys', () async {
    final json = await payload();

    expect(json['schemaVersion'], 5);
    expect(json.keys, unorderedEquals(['schemaVersion', 'exportedAt', 'history', 'ratings', 'watchlist', 'favorites']));
    expect(json['exportedAt'], endsWith('Z'));
  });

  test('no entry carries a legacy sync id any more', () async {
    final json = await payload();

    for (final key in ['history', 'ratings', 'watchlist', 'favorites']) {
      for (final item in section(json, key)) {
        expect(item.keys.where((k) => k.toLowerCase().contains('trakt')), isEmpty, reason: '$key: $item');
      }
    }
  });

  test('a movie history entry carries its ids and no show-scoped keys', () async {
    final json = await payload();
    final movie = entry(json, 'history', ItemType.movie);

    expect(movie.keys, unorderedEquals(['type', 'tmdbId', 'imdbId', 'addedAt', 'historyType']));
    expect(movie['tmdbId'], movieTmdb);
    expect(movie['imdbId'], movieImdb);
    expect(movie['historyType'], 'watch');
  });

  test('an episode history entry is identified by the episode, scoped to its show', () async {
    final json = await payload();
    final episode = section(json, 'history').singleWhere((e) => e['type'] == 'episode' && e['showTmdbId'] == showTmdb);

    expect(episode.keys, unorderedEquals(['type', 'tmdbId', 'imdbId', 'showTmdbId', 'season', 'episode', 'addedAt', 'historyType']));
    expect(episode['tmdbId'], episodeTmdb);
    expect(episode['imdbId'], episodeImdb);
    expect(episode['showTmdbId'], showTmdb);
    expect(episode['season'], seasonNumber);
    expect(episode['episode'], episodeNumber);
    expect(episode['historyType'], 'scrobble');
  });

  test('a season rating has a season but no episode key and no imdbId', () async {
    final json = await payload();
    final season = entry(json, 'ratings', ItemType.season);

    expect(season.keys, unorderedEquals(['type', 'tmdbId', 'showTmdbId', 'season', 'rating', 'ratedAt']));
    expect(season['tmdbId'], seasonTmdb);
    expect(season['showTmdbId'], showTmdb);
    expect(season['season'], seasonNumber);
    expect(season['rating'], 7);
  });

  test('movie and show ratings carry their ids and no show-scoped keys', () async {
    final json = await payload();

    for (final type in [ItemType.movie, ItemType.show]) {
      expect(entry(json, 'ratings', type).keys, unorderedEquals(['type', 'tmdbId', 'imdbId', 'rating', 'ratedAt']), reason: type.name);
    }
    expect(entry(json, 'ratings', ItemType.show)['tmdbId'], showTmdb);
    expect(entry(json, 'ratings', ItemType.show)['imdbId'], showImdb);
  });

  test('a season watchlist row resolves its own TMDB id from the cached seasons', () async {
    final json = await payload();
    final season = entry(json, 'watchlist', ItemType.season);

    expect(season.keys, unorderedEquals(['type', 'tmdbId', 'showTmdbId', 'season', 'listedAt']));
    expect(season['tmdbId'], seasonTmdb);
    expect(season['showTmdbId'], showTmdb);
  });

  test('a cached season without a TMDB id of its own exports a null tmdbId', () async {
    // Rows migrated from an older schema have no season id; the key stays, the value is null.
    await SeasonRepo().insert(
      SeasonEntity.build(
        showTmdbId: showTmdb,
        season: 2,
        tmdbId: null,
        title: null,
        episodeCount: 8,
        airDate: null,
        posterPath: null,
        fetchedAt: null,
      ),
    );
    await WatchlistRepo().insert(WatchlistEntity.build(type: ItemType.season, tmdbId: showTmdb, season: 2, listedAt: instant));

    final json = await payload();
    final season = section(json, 'watchlist').singleWhere((e) => e['type'] == 'season' && e['season'] == 2);

    expect(season.keys, unorderedEquals(['type', 'tmdbId', 'showTmdbId', 'season', 'listedAt']));
    expect(season.containsKey('tmdbId'), isTrue);
    expect(season['tmdbId'], isNull);
    expect(season['showTmdbId'], showTmdb);
  });

  test('an episode watchlist entry carries the episode key', () async {
    final json = await payload();
    final episode = entry(json, 'watchlist', ItemType.episode);

    expect(episode.keys, unorderedEquals(['type', 'tmdbId', 'imdbId', 'showTmdbId', 'season', 'episode', 'listedAt']));
    expect(episode['tmdbId'], episodeTmdb);
    expect(episode['episode'], episodeNumber);
    expect(entry(json, 'watchlist', ItemType.movie).keys, unorderedEquals(['type', 'tmdbId', 'imdbId', 'listedAt']));
  });

  test('favorite entries are movies and shows with their ids and a favoritedAt', () async {
    final json = await payload();

    expect(section(json, 'favorites'), hasLength(2));
    final movie = entry(json, 'favorites', ItemType.movie);
    expect(movie.keys, unorderedEquals(['type', 'tmdbId', 'imdbId', 'favoritedAt']));
    expect(movie['tmdbId'], movieTmdb);
    expect(movie['imdbId'], movieImdb);
    final show = entry(json, 'favorites', ItemType.show);
    expect(show.keys, unorderedEquals(['type', 'tmdbId', 'imdbId', 'favoritedAt']));
    expect(show['tmdbId'], showTmdb);
    expect(show['imdbId'], showImdb);
  });

  test('an entry whose show is not cached is kept with null tmdb and imdb ids', () async {
    final json = await payload();
    final orphan = section(json, 'history').singleWhere((e) => e['showTmdbId'] == missingShowTmdb);

    expect(orphan['tmdbId'], isNull);
    expect(orphan['imdbId'], isNull);
    expect(orphan['showTmdbId'], missingShowTmdb);
    expect(orphan['season'], 2);
    expect(orphan['episode'], 1);
  });

  test('every timestamp is written as UTC with a Z suffix', () async {
    final json = await payload();

    for (final item in section(json, 'history')) {
      expect(item['addedAt'], instantIso);
    }
    for (final item in section(json, 'ratings')) {
      expect(item['ratedAt'], instantIso);
    }
    for (final item in section(json, 'watchlist')) {
      expect(item['listedAt'], instantIso);
    }
    for (final item in section(json, 'favorites')) {
      expect(item['favoritedAt'], instantIso);
    }
  });
}
