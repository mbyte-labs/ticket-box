import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/filter/page_details.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';

/// Guards the watch history page's per-play paging ([HistoryRepo.getPlays]), the aggregating reads
/// of [HistoryRepo] — the "last watched 19x20 ..." line of the Show
/// Progress page, the stats page's plays / minutes roll-ups — and the id handling of
/// [HistoryRepo.insertNew]: a new play gets the next AUTOINCREMENT id, which must keep counting past
/// the v3-era ids the migration preserved so a deleted id is never reused.
void main() {
  late DatabaseConnectionManager db;
  late HistoryRepo historyRepo;

  var nextHistoryId = 1;

  HistoryEntity episodePlay(int showId, int season, int episode, DateTime watchedAt, {HistoryAction action = HistoryAction.watch}) {
    return HistoryEntity.build(
      historyId: nextHistoryId++,
      tmdbId: showId,
      season: season,
      episode: episode,
      type: ItemType.episode,
      action: action,
      watchedAt: watchedAt,
    );
  }

  HistoryEntity moviePlay(int movieId, DateTime watchedAt) {
    return HistoryEntity.build(
      historyId: nextHistoryId++,
      tmdbId: movieId,
      type: ItemType.movie,
      action: HistoryAction.watch,
      watchedAt: watchedAt,
    );
  }

  MovieEntity movieRow(int tmdbId, int? runtime) {
    return MovieEntity.build(
      tmdbId: tmdbId,
      imdbId: null,
      title: 'Movie $tmdbId',
      year: 2020,
      overview: null,
      tagline: null,
      releaseDate: null,
      runtime: runtime,
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
      fetchedAt: DateTime.utc(2026, 7, 1),
      trackedAt: DateTime.utc(2026, 7, 1),
      watchProvidersRegion: null,
    );
  }

  ShowEntity showRow(int tmdbId, int? runtime) {
    return ShowEntity.build(
      tmdbId: tmdbId,
      imdbId: null,
      title: 'Show $tmdbId',
      year: 2020,
      overview: null,
      tagline: null,
      firstAirDate: null,
      lastAirDate: null,
      runtime: runtime,
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
      fetchedAt: DateTime.utc(2026, 7, 1),
      trackedAt: DateTime.utc(2026, 7, 1),
      watchProvidersRegion: null,
    );
  }

  EpisodeEntity episodeRow(int showId, int season, int episode, int? runtime) {
    return EpisodeEntity.build(
      showTmdbId: showId,
      season: season,
      episode: episode,
      tmdbId: null,
      imdbId: null,
      title: null,
      overview: null,
      voteAverage: 7,
      voteCount: 10,
      runtime: runtime,
      airDate: null,
      episodeType: null,
      stillPath: null,
    );
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    historyRepo = HistoryRepo();
    nextHistoryId = 1;
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('getPlays', () {
    const allActions = [HistoryAction.scrobble, HistoryAction.checkin, HistoryAction.watch];
    const bothTypes = [ItemType.movie, ItemType.episode];
    int now() => DateTime.now().millisecondsSinceEpoch;

    test('lists every watch of a rewatched episode, newest first', () async {
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)),
        moviePlay(7, DateTime.utc(2026, 7, 5)),
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 10)),
      ]);

      final result = await historyRepo.getPlays(now(), allActions, bothTypes, const PageDetails(page: 0, pageSize: 50));

      expect(result.totalPages, 1);
      expect([for (final play in result.data) play.historyId], [3, 2, 1]);
      expect(result.data.first.watchedAt.toUtc(), DateTime.utc(2026, 7, 10));
    });

    test('breaks a watchedAt tie by id, so pages neither repeat nor skip a play', () async {
      final instant = DateTime.utc(2026, 7, 1);
      await historyRepo.insertAll([for (var episode = 1; episode <= 5; episode++) episodePlay(1, 1, episode, instant)]);

      final first = await historyRepo.getPlays(now(), allActions, bothTypes, const PageDetails(page: 0, pageSize: 3));
      final second = await historyRepo.getPlays(now(), allActions, bothTypes, const PageDetails(page: 1, pageSize: 3));

      expect(first.totalPages, 2);
      expect([for (final play in first.data) play.historyId], [5, 4, 3]);
      expect([for (final play in second.data) play.historyId], [2, 1]);
    });

    test('leaves out the future dated row of an in-progress check-in', () async {
      final future = DateTime.now().add(const Duration(minutes: 30)).toUtc();
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)),
        episodePlay(1, 1, 2, future, action: HistoryAction.checkin),
      ]);

      final result = await historyRepo.getPlays(now(), allActions, bothTypes, const PageDetails(page: 0, pageSize: 50));

      expect([for (final play in result.data) play.historyId], [1]);
    });

    test('applies the action and type filters', () async {
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)),
        episodePlay(1, 1, 2, DateTime.utc(2026, 7, 2), action: HistoryAction.scrobble),
        moviePlay(7, DateTime.utc(2026, 7, 3)),
      ]);

      final episodesWatched = await historyRepo.getPlays(
        now(),
        [HistoryAction.watch],
        [ItemType.episode],
        const PageDetails(page: 0, pageSize: 50),
      );

      expect([for (final play in episodesWatched.data) play.historyId], [1]);
    });

    test('returns an empty page for empty filters instead of invalid SQL', () async {
      await historyRepo.insert(moviePlay(7, DateTime.utc(2026, 7, 1)));

      final noActions = await historyRepo.getPlays(now(), [], bothTypes, const PageDetails(page: 0, pageSize: 50));
      final noTypes = await historyRepo.getPlays(now(), allActions, [], const PageDetails(page: 0, pageSize: 50));

      expect(noActions.data, isEmpty);
      expect(noTypes.data, isEmpty);
    });
  });

  group('getLatestEpisodeEntryPerShow', () {
    test('returns the newest episode play of each show', () async {
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)),
        episodePlay(1, 6, 6, DateTime.utc(2026, 7, 20)),
        episodePlay(1, 3, 4, DateTime.utc(2026, 7, 10)),
        episodePlay(2, 19, 20, DateTime.utc(2026, 6, 21)),
      ]);

      final result = await historyRepo.getLatestEpisodeEntryPerShow();

      expect(result.keys, unorderedEquals([1, 2]));
      expect(result[1]!.season, 6);
      expect(result[1]!.episode, 6);
      // Drift hands DateTimes back in local time; compare the instant, not the zone.
      expect(result[1]!.lastWatchedAt.toUtc(), DateTime.utc(2026, 7, 20));
      expect(result[2]!.season, 19);
      expect(result[2]!.episode, 20);
    });

    test('ignores movie plays', () async {
      await historyRepo.insert(moviePlay(7, DateTime.utc(2026, 7, 1)));

      expect(await historyRepo.getLatestEpisodeEntryPerShow(), isEmpty);
    });

    test('ignores the future dated row of an in-progress check-in', () async {
      final future = DateTime.now().add(const Duration(minutes: 30)).toUtc();
      await historyRepo.insertAll([episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)), episodePlay(1, 1, 2, future)]);

      final result = await historyRepo.getLatestEpisodeEntryPerShow();

      expect(result[1]!.episode, 1);
    });
  });

  group('getAllWatchInstants', () {
    test('returns every play with its converted item type', () async {
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)),
        episodePlay(1, 1, 2, DateTime.utc(2026, 7, 2)),
        moviePlay(7, DateTime.utc(2026, 7, 3)),
      ]);

      final result = await historyRepo.getAllWatchInstants();

      expect(result, hasLength(3));
      // readWithConverter regression guard: the type must come back as the enum, not the raw String.
      expect(result.where((entry) => entry.$1 == ItemType.episode), hasLength(2));
      expect(result.where((entry) => entry.$1 == ItemType.movie), hasLength(1));
      expect(result.map((entry) => entry.$2.toUtc()), contains(DateTime.utc(2026, 7, 3)));
    });

    test('ignores the future dated row of an in-progress check-in', () async {
      final future = DateTime.now().add(const Duration(minutes: 30)).toUtc();
      await historyRepo.insertAll([episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)), episodePlay(1, 1, 2, future)]);

      final result = await historyRepo.getAllWatchInstants();

      expect(result, hasLength(1));
      expect(result.single.$2.toUtc(), DateTime.utc(2026, 7, 1));
    });

    test('returns an empty list for an empty table', () async {
      expect(await historyRepo.getAllWatchInstants(), isEmpty);
    });
  });

  group('insertNew', () {
    test('returns the id the database assigned and stores the row under it', () async {
      final id = await historyRepo.insertNew(
        NewHistoryEntry.episode(showTmdbId: 1, season: 2, episode: 3, action: HistoryAction.checkin, watchedAt: DateTime.utc(2026, 7, 1)),
      );

      final stored = await historyRepo.getByHistoryId(id);
      expect(stored, isNotNull);
      expect(stored!.type, ItemType.episode);
      expect(stored.tmdbId, 1);
      expect(stored.season, 2);
      expect(stored.episode, 3);
      expect(stored.action, HistoryAction.checkin);
      expect(stored.watchedAt.toUtc(), DateTime.utc(2026, 7, 1));
    });

    test('a movie entry stores season and episode as 0', () async {
      final id = await historyRepo.insertNew(
        NewHistoryEntry.movie(tmdbId: 9, action: HistoryAction.watch, watchedAt: DateTime.utc(2026, 7, 1)),
      );

      final stored = await historyRepo.getByHistoryId(id);
      expect(stored!.type, ItemType.movie);
      expect(stored.season, 0);
      expect(stored.episode, 0);
    });

    test('ids keep counting after an explicitly inserted larger id', () async {
      // What the v3→v4 migration leaves behind: the v3 database's own (large) history ids.
      nextHistoryId = 500;
      await historyRepo.insert(moviePlay(7, DateTime.utc(2026, 7, 1)));

      final first = await historyRepo.insertNew(
        NewHistoryEntry.movie(tmdbId: 8, action: HistoryAction.watch, watchedAt: DateTime.utc(2026, 7, 2)),
      );
      final second = await historyRepo.insertNew(
        NewHistoryEntry.movie(tmdbId: 8, action: HistoryAction.watch, watchedAt: DateTime.utc(2026, 7, 3)),
      );

      expect(first, 501);
      expect(second, 502);
    });

    test('a deleted id is never handed out again', () async {
      final id = await historyRepo.insertNew(
        NewHistoryEntry.movie(tmdbId: 8, action: HistoryAction.watch, watchedAt: DateTime.utc(2026, 7, 2)),
      );
      await historyRepo.deleteByHistoryId(id);

      final next = await historyRepo.insertNew(
        NewHistoryEntry.movie(tmdbId: 8, action: HistoryAction.watch, watchedAt: DateTime.utc(2026, 7, 3)),
      );

      // AUTOINCREMENT, not plain rowid: the check-in cancel flow deletes by id and must not hit a
      // row written in the meantime.
      expect(next, greaterThan(id));
    });
  });

  group('insertAllNew', () {
    test('writes every entry with distinct ids', () async {
      await historyRepo.insertAllNew([
        for (var e = 1; e <= 4; e++)
          NewHistoryEntry.episode(showTmdbId: 1, season: 1, episode: e, action: HistoryAction.watch, watchedAt: DateTime.utc(2026, 7, 1)),
      ]);

      final all = await historyRepo.getAll();
      expect(all, hasLength(4));
      expect(all.map((e) => e.historyId).toSet(), hasLength(4));
      expect(all.map((e) => e.episode), unorderedEquals([1, 2, 3, 4]));
    });

    test('an empty list is a no-op', () async {
      await historyRepo.insertAllNew([]);

      expect(await historyRepo.getAll(), isEmpty);
    });
  });

  group('getPlayAggregates', () {
    test('rolls episode plays up to their show and counts movie plays separately', () async {
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)),
        episodePlay(1, 1, 2, DateTime.utc(2026, 7, 5)),
        episodePlay(1, 1, 2, DateTime.utc(2026, 7, 9)), // a rewatch
        episodePlay(2, 1, 1, DateTime.utc(2026, 6, 1)),
        moviePlay(1, DateTime.utc(2026, 7, 3)), // same number as show 1, different item
        moviePlay(1, DateTime.utc(2026, 7, 4)),
      ]);

      final result = await historyRepo.getPlayAggregates();

      expect(result, hasLength(3));
      final show1 = result.singleWhere((a) => a.type == ItemType.show && a.tmdbId == 1);
      expect(show1.plays, 3);
      expect(show1.lastWatchedAt.toUtc(), DateTime.utc(2026, 7, 9));
      final show2 = result.singleWhere((a) => a.type == ItemType.show && a.tmdbId == 2);
      expect(show2.plays, 1);
      final movie1 = result.singleWhere((a) => a.type == ItemType.movie && a.tmdbId == 1);
      expect(movie1.plays, 2);
      expect(movie1.lastWatchedAt.toUtc(), DateTime.utc(2026, 7, 4));
    });

    test('excludes the future dated row of an in-progress check-in', () async {
      final future = DateTime.now().add(const Duration(minutes: 30)).toUtc();
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)),
        episodePlay(1, 1, 2, future, action: HistoryAction.checkin),
      ]);

      final result = await historyRepo.getPlayAggregates();

      expect(result.single.plays, 1);
      expect(result.single.lastWatchedAt.toUtc(), DateTime.utc(2026, 7, 1));
    });

    test('returns an empty list for an empty table', () async {
      expect(await historyRepo.getPlayAggregates(), isEmpty);
    });
  });

  group('getWatchedMinutes', () {
    late MovieRepo movieRepo;
    late ShowRepo showRepo;
    late EpisodeRepo episodeRepo;

    setUp(() {
      movieRepo = MovieRepo();
      showRepo = ShowRepo();
      episodeRepo = EpisodeRepo();
    });

    test('sums movie runtimes from the movie rows, once per play', () async {
      await movieRepo.insert(movieRow(1, 120));
      await movieRepo.insert(movieRow(2, 90));
      await historyRepo.insertAll([
        moviePlay(1, DateTime.utc(2026, 7, 1)),
        moviePlay(1, DateTime.utc(2026, 7, 2)),
        moviePlay(2, DateTime.utc(2026, 7, 3)),
      ]);

      expect(await historyRepo.getWatchedMinutes(), (movies: 330, episodes: 0));
    });

    test('sums episode runtimes from the episode rows', () async {
      await episodeRepo.insert(episodeRow(1, 1, 1, 60));
      await episodeRepo.insert(episodeRow(1, 1, 2, 45));
      await historyRepo.insertAll([episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)), episodePlay(1, 1, 2, DateTime.utc(2026, 7, 2))]);

      expect(await historyRepo.getWatchedMinutes(), (movies: 0, episodes: 105));
    });

    test('falls back to the show runtime when the episode row has none', () async {
      await showRepo.insert(showRow(1, 42));
      // One episode with its own runtime, one whose row lacks it, one with no row at all.
      await episodeRepo.insert(episodeRow(1, 1, 1, 60));
      await episodeRepo.insert(episodeRow(1, 1, 2, null));
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)),
        episodePlay(1, 1, 2, DateTime.utc(2026, 7, 2)),
        episodePlay(1, 1, 3, DateTime.utc(2026, 7, 3)),
      ]);

      expect(await historyRepo.getWatchedMinutes(), (movies: 0, episodes: 60 + 42 + 42));
    });

    test('a play with no runtime anywhere contributes nothing', () async {
      await movieRepo.insert(movieRow(1, null));
      await historyRepo.insertAll([
        moviePlay(1, DateTime.utc(2026, 7, 1)),
        moviePlay(2, DateTime.utc(2026, 7, 2)),
        episodePlay(5, 1, 1, DateTime.utc(2026, 7, 3)),
      ]);

      expect(await historyRepo.getWatchedMinutes(), (movies: 0, episodes: 0));
    });

    test('a movie and a show with the same tmdb id are kept apart, each in its own sum', () async {
      await movieRepo.insert(movieRow(1, 100));
      await showRepo.insert(showRow(1, 30));
      await historyRepo.insertAll([moviePlay(1, DateTime.utc(2026, 7, 1)), episodePlay(1, 1, 1, DateTime.utc(2026, 7, 2))]);

      expect(await historyRepo.getWatchedMinutes(), (movies: 100, episodes: 30));
    });

    test('excludes the future dated row of an in-progress check-in', () async {
      final future = DateTime.now().add(const Duration(minutes: 30)).toUtc();
      await movieRepo.insert(movieRow(1, 100));
      await showRepo.insert(showRow(2, 30));
      await historyRepo.insertAll([
        moviePlay(1, DateTime.utc(2026, 7, 1)),
        HistoryEntity.build(historyId: nextHistoryId++, tmdbId: 1, type: ItemType.movie, action: HistoryAction.checkin, watchedAt: future),
        episodePlay(2, 1, 1, future, action: HistoryAction.checkin),
      ]);

      expect(await historyRepo.getWatchedMinutes(), (movies: 100, episodes: 0));
    });

    test('is 0 for an empty table', () async {
      expect(await historyRepo.getWatchedMinutes(), (movies: 0, episodes: 0));
    });
  });

  group('getWatchedShowIds', () {
    test('returns each show with an episode play once, never a movie', () async {
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)),
        episodePlay(1, 1, 2, DateTime.utc(2026, 7, 2)),
        episodePlay(3, 2, 1, DateTime.utc(2026, 7, 3)),
        moviePlay(7, DateTime.utc(2026, 7, 4)),
      ]);

      expect(await historyRepo.getWatchedShowIds(), {1, 3});
    });

    test('is empty for an empty table', () async {
      expect(await historyRepo.getWatchedShowIds(), isEmpty);
    });
  });

  group('getWatchedMovieIds', () {
    test('returns each movie with a play once, never a show', () async {
      await historyRepo.insertAll([
        moviePlay(7, DateTime.utc(2026, 7, 4)),
        moviePlay(7, DateTime.utc(2026, 7, 5)),
        moviePlay(9, DateTime.utc(2026, 7, 6)),
        episodePlay(7, 1, 1, DateTime.utc(2026, 7, 1)),
      ]);

      expect(await historyRepo.getWatchedMovieIds(), {7, 9});
    });

    test('is empty for an empty table', () async {
      expect(await historyRepo.getWatchedMovieIds(), isEmpty);
    });
  });

  group('seasonWatchedEpisodeCount', () {
    test('counts distinct episodes, not plays, of just that season', () async {
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 1)),
        episodePlay(1, 1, 1, DateTime.utc(2026, 7, 2)), // rewatch of the same episode
        episodePlay(1, 1, 2, DateTime.utc(2026, 7, 3)),
        episodePlay(1, 2, 1, DateTime.utc(2026, 7, 4)), // another season
        episodePlay(2, 1, 3, DateTime.utc(2026, 7, 5)), // another show
      ]);

      expect(await historyRepo.seasonWatchedEpisodeCount(1, 1), 2);
      expect(await historyRepo.seasonWatchedEpisodeCount(1, 2), 1);
      expect(await historyRepo.seasonWatchedEpisodeCount(1, 3), 0);
    });
  });

  group('isEpisodeWatched', () {
    test('is true only for the exact show, season and episode', () async {
      await historyRepo.insertAll([episodePlay(1, 2, 3, DateTime.utc(2026, 7, 1)), moviePlay(1, DateTime.utc(2026, 7, 2))]);

      expect(await historyRepo.isEpisodeWatched(1, 2, 3), isTrue);
      expect(await historyRepo.isEpisodeWatched(1, 2, 4), isFalse);
      expect(await historyRepo.isEpisodeWatched(1, 3, 3), isFalse);
      expect(await historyRepo.isEpisodeWatched(2, 2, 3), isFalse);
      // The movie row shares the number but not the type.
      expect(await historyRepo.isEpisodeWatched(1, 0, 0), isFalse);
      expect(await historyRepo.isMovieWatched(1), isTrue);
    });
  });

  group('stats period bounds', () {
    late EpisodeRepo episodeRepo;

    final from = DateTime.utc(2024);
    final before = DateTime.utc(2025);

    setUp(() {
      episodeRepo = EpisodeRepo();
    });

    Future<void> seedTwoYears() async {
      await historyRepo.insertAll([
        episodePlay(1, 1, 1, DateTime.utc(2023, 12, 31, 23, 59, 59)),
        episodePlay(1, 1, 2, DateTime.utc(2024, 1, 1)),
        episodePlay(1, 1, 2, DateTime.utc(2024, 6, 1)),
        moviePlay(7, DateTime.utc(2024, 7, 1)),
        moviePlay(8, DateTime.utc(2025, 1, 1)),
      ]);
    }

    test('getAllWatchInstants keeps the plays in [from, before)', () async {
      await seedTwoYears();

      final result = await historyRepo.getAllWatchInstants(from: from, before: before);

      expect(result.map((entry) => entry.$2.toUtc()), [DateTime.utc(2024, 1, 1), DateTime.utc(2024, 6, 1), DateTime.utc(2024, 7, 1)]);
      expect(await historyRepo.getAllWatchInstants(), hasLength(5));
    });

    test('getPlayAggregates counts only the plays in the window', () async {
      await seedTwoYears();

      final result = await historyRepo.getPlayAggregates(from: from, before: before);

      expect(result, hasLength(2));
      final show = result.singleWhere((item) => item.type == ItemType.show);
      expect(show.plays, 2);
      expect(show.lastWatchedAt.toUtc(), DateTime.utc(2024, 6, 1));
      expect(result.singleWhere((item) => item.type == ItemType.movie).tmdbId, 7);
    });

    test('getWatchedMinutes and getEpisodeMinutesPerShow sum only the window', () async {
      await MovieRepo().insert(movieRow(7, 100));
      await MovieRepo().insert(movieRow(8, 50));
      await episodeRepo.insert(episodeRow(1, 1, 1, 30));
      await episodeRepo.insert(episodeRow(1, 1, 2, 20));
      await seedTwoYears();

      expect(await historyRepo.getWatchedMinutes(from: from, before: before), (movies: 100, episodes: 40));
      expect(await historyRepo.getWatchedMinutes(), (movies: 150, episodes: 70));
      expect(await historyRepo.getEpisodeMinutesPerShow(from: from, before: before), {1: 40});
    });

    test('getFirstPlay is the oldest play in the window', () async {
      await seedTwoYears();

      final first = await historyRepo.getFirstPlay(from: from, before: before);

      expect(first!.watchedAt.toUtc(), DateTime.utc(2024, 1, 1));
      expect((await historyRepo.getFirstPlay())!.watchedAt.toUtc(), DateTime.utc(2023, 12, 31, 23, 59, 59));
      expect(await historyRepo.getFirstPlay(from: DateTime.utc(2030)), isNull);
    });

    test('countDistinctEpisodesWatched counts a rewatched episode once and respects the window', () async {
      await seedTwoYears();

      expect(await historyRepo.countDistinctEpisodesWatched(from: from, before: before), 1);
      expect(await historyRepo.countDistinctEpisodesWatched(), 2);
      expect(await historyRepo.countDistinctEpisodesWatched(from: DateTime.utc(2030)), 0);
    });

    test('a future dated check-in stays out even inside the window', () async {
      final future = DateTime.now().add(const Duration(minutes: 30)).toUtc();
      await historyRepo.insertAll([episodePlay(1, 1, 1, future)]);

      expect(await historyRepo.getAllWatchInstants(from: DateTime.utc(2000), before: DateTime.utc(2100)), isEmpty);
      expect(await historyRepo.countDistinctEpisodesWatched(from: DateTime.utc(2000), before: DateTime.utc(2100)), 0);
    });
  });
}
