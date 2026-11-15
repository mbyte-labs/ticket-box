import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';

/// Guards the two season writes and the per-show reads of [SeasonRepo].
///
/// [SeasonRepo.upsertStubs] comes from a show's root document: it may say a season exists, how
/// many episodes it has and what its poster is, but must not touch an existing row's `fetchedAt`
/// (or a stub would fake a stale episode list as fresh), and must not blank a `posterPath` or
/// `tmdbId` the stub does not carry. [SeasonRepo.replaceSeasons] is the full season fetch: one
/// batch that swaps the season's episode list, so an episode TMDB no longer lists disappears.
void main() {
  late DatabaseConnectionManager db;
  late SeasonRepo repo;
  late EpisodeRepo episodeRepo;

  const showId = 1;
  final fetchedAt = DateTime.utc(2026, 7, 1, 12);

  /// A fetched season row: it has a TMDB id, a poster and a `fetchedAt`.
  SeasonEntity season(int number, {int? episodeCount, String? title, String? posterPath = '/poster.jpg', int show = showId}) {
    return SeasonEntity.build(
      showTmdbId: show,
      season: number,
      tmdbId: show * 100 + number,
      title: title,
      episodeCount: episodeCount,
      airDate: null,
      posterPath: posterPath,
      fetchedAt: fetchedAt,
    );
  }

  /// A stub as the show's `seasons[]` lists it: no `fetchedAt`, and by default no id or poster.
  SeasonEntity stub(int number, {int? episodeCount, String? title, int? tmdbId, String? posterPath, String? airDate, int show = showId}) {
    return SeasonEntity.build(
      showTmdbId: show,
      season: number,
      tmdbId: tmdbId,
      title: title,
      episodeCount: episodeCount,
      airDate: airDate,
      posterPath: posterPath,
      fetchedAt: null,
    );
  }

  EpisodeEntity episode(int seasonNr, int number, {String? imdbId, String? overview}) {
    return EpisodeEntity.build(
      showTmdbId: showId,
      season: seasonNr,
      episode: number,
      tmdbId: seasonNr * 1000 + number,
      imdbId: imdbId,
      title: 'E$number',
      overview: overview ?? 'Overview $number',
      voteAverage: 7,
      voteCount: 1,
      runtime: 42,
      airDate: null,
      episodeType: null,
      stillPath: null,
    );
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = SeasonRepo();
    episodeRepo = EpisodeRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('upsertStubs', () {
    test('inserts seasons that are not cached yet, unfetched', () async {
      await repo.upsertStubs([stub(1, episodeCount: 10, tmdbId: 101, posterPath: '/s1.jpg'), stub(2, episodeCount: 8)]);

      final stored = await repo.getAllForShow(showId);
      expect(stored.map((s) => s.season), [1, 2]);
      expect(stored.first.episodeCount, 10);
      expect(stored.first.tmdbId, 101);
      expect(stored.first.posterPath, '/s1.jpg');
      expect(stored.first.fetchedAt, isNull);
      expect(stored.first.hasSnapshot, isFalse);
      expect(stored[1].tmdbId, isNull);
      expect(stored[1].posterPath, isNull);
    });

    test('keeps an existing row\'s fetchedAt while refreshing the stub columns', () async {
      await repo.insert(season(1, episodeCount: 10, title: 'Season One'));

      await repo.upsertStubs([stub(1, episodeCount: 11, title: 'Season 1', airDate: '2020-01-01')]);

      final stored = await repo.getBySeasonNumber(showId, 1);
      // Compared as instants: drift reads DateTimes back in local time.
      expect(stored!.fetchedAt?.toUtc(), fetchedAt, reason: 'a stub must not fake the episode list as fresh');
      expect(stored.episodeCount, 11, reason: 'the stub columns must still be updated');
      expect(stored.title, 'Season 1');
      expect(stored.airDate, '2020-01-01');
    });

    test('keeps the stored posterPath and tmdbId when the stub has none', () async {
      await repo.insert(season(1, posterPath: '/old.jpg'));

      await repo.upsertStubs([stub(1, tmdbId: null, posterPath: null)]);

      final stored = await repo.getBySeasonNumber(showId, 1);
      expect(stored!.posterPath, '/old.jpg');
      expect(stored.tmdbId, showId * 100 + 1);
    });

    test('a stub that carries a posterPath or tmdbId overrides the stored ones', () async {
      await repo.insert(season(1, posterPath: '/old.jpg'));

      await repo.upsertStubs([stub(1, tmdbId: 777, posterPath: '/new.jpg')]);

      final stored = await repo.getBySeasonNumber(showId, 1);
      expect(stored!.posterPath, '/new.jpg');
      expect(stored.tmdbId, 777);
    });

    test('an empty list is a no-op', () async {
      await repo.upsertStubs([]);

      expect(await repo.getAllForShow(showId), isEmpty);
    });
  });

  group('replaceSeasons', () {
    test('writes the season and its episodes in one call', () async {
      await repo.replaceSeasons(showId, [season(1, episodeCount: 2)], [episode(1, 1), episode(1, 2)]);

      final stored = await repo.getBySeasonNumber(showId, 1);
      expect(stored?.episodeCount, 2);
      expect(stored?.fetchedAt?.toUtc(), fetchedAt);
      expect(stored?.hasSnapshot, isTrue);
      expect(await episodeRepo.getAllForSeason(showId, 1), hasLength(2));
      expect((await episodeRepo.get(showId, 1, 1))?.overview, 'Overview 1');
    });

    test('turns a stub into a fetched season', () async {
      await repo.upsertStubs([stub(1, episodeCount: 1)]);

      await repo.replaceSeasons(showId, [season(1, episodeCount: 1)], [episode(1, 1)]);

      expect((await repo.getBySeasonNumber(showId, 1))?.fetchedAt?.toUtc(), fetchedAt);
      expect(await repo.getUnfetchedSeasonNumbers(showId), isEmpty);
    });

    test('removes the episodes TMDB no longer lists for the season', () async {
      await repo.replaceSeasons(showId, [season(1, episodeCount: 3)], [episode(1, 1), episode(1, 2), episode(1, 3)]);

      await repo.replaceSeasons(showId, [season(1, episodeCount: 2)], [episode(1, 1), episode(1, 2)]);

      expect((await episodeRepo.getAllForSeason(showId, 1)).map((e) => e.episode), [1, 2]);
    });

    test('a season fetched with no episodes loses every stored one', () async {
      await repo.replaceSeasons(showId, [season(1, episodeCount: 2)], [episode(1, 1), episode(1, 2)]);

      await repo.replaceSeasons(showId, [season(1, episodeCount: 0)], []);

      expect(await episodeRepo.getAllForSeason(showId, 1), isEmpty);
      expect(await repo.getBySeasonNumber(showId, 1), isNotNull);
    });

    test('leaves the other seasons of the show, and other shows, alone', () async {
      await repo.replaceSeasons(showId, [season(1), season(2)], [episode(1, 1), episode(2, 1)]);
      await repo.insert(season(1, show: 2));

      await repo.replaceSeasons(showId, [season(2)], [episode(2, 1), episode(2, 2)]);

      expect(await episodeRepo.getAllForSeason(showId, 1), hasLength(1));
      expect(await episodeRepo.getAllForSeason(showId, 2), hasLength(2));
      expect(await repo.getAllForShow(2), hasLength(1));
    });

    test('preserves an imdbId looked up earlier when the fetch does not carry one', () async {
      // Season payloads have no external ids; an imdbId found through /external_ids must survive
      // the next full fetch of the season — which is what EpisodeRepo.fullConflict's COALESCE is for.
      await repo.replaceSeasons(showId, [season(1)], [episode(1, 1, imdbId: 'tt0001')]);

      await repo.replaceSeasons(showId, [season(1)], [episode(1, 1, imdbId: null)]);

      expect((await episodeRepo.get(showId, 1, 1))?.imdbId, 'tt0001');
    });

    test('a refetch overwrites the episode details', () async {
      await repo.replaceSeasons(showId, [season(1)], [episode(1, 1, overview: 'Old')]);

      await repo.replaceSeasons(showId, [season(1)], [episode(1, 1, overview: 'New')]);

      expect((await episodeRepo.get(showId, 1, 1))?.overview, 'New');
    });

    test('an empty season list is a no-op', () async {
      await repo.replaceSeasons(showId, [season(1)], [episode(1, 1)]);

      await repo.replaceSeasons(showId, [], []);

      expect(await episodeRepo.getAllForSeason(showId, 1), hasLength(1));
    });
  });

  group('getAllForShow', () {
    test('returns the show\'s seasons ordered by number, specials first', () async {
      await repo.insertAll([season(3), season(0), season(2), season(1), season(1, show: 2)]);

      final stored = await repo.getAllForShow(showId);

      expect(stored.map((s) => s.season), [0, 1, 2, 3]);
      expect(stored.every((s) => s.showTmdbId == showId), isTrue);
    });

    test('is empty for an unknown show', () async {
      expect(await repo.getAllForShow(404), isEmpty);
    });
  });

  group('getMany', () {
    test('returns just the requested (show, season) keys, keyed back the same way', () async {
      await repo.insertAll([season(1), season(2), season(1, show: 2), season(2, show: 2)]);

      final result = await repo.getMany([(showId, 1), (2, 2), (2, 9), (3, 1)]);

      expect(result.keys, unorderedEquals([(showId, 1), (2, 2)]));
      expect(result[(2, 2)]?.showTmdbId, 2);
    });

    test('is empty for no keys', () async {
      expect(await repo.getMany([]), isEmpty);
    });
  });

  group('getUnfetchedSeasonNumbers', () {
    test('lists the stubs of one show, in order', () async {
      await repo.insertAll([season(1), stub(3), stub(2), stub(1, show: 2)]);

      expect(await repo.getUnfetchedSeasonNumbers(showId), [2, 3]);
      expect(await repo.getUnfetchedSeasonNumbers(2), [1]);
      expect(await repo.getUnfetchedSeasonNumbers(404), isEmpty);
    });
  });

  group('deletes', () {
    test('deleteBySeasonNr removes one season, deleteByShowId all of them', () async {
      await repo.insertAll([season(1), season(2), season(1, show: 2)]);

      await repo.deleteBySeasonNr(showId, 1);
      expect((await repo.getAllForShow(showId)).map((s) => s.season), [2]);

      await repo.deleteByShowId(showId);
      expect(await repo.getAllForShow(showId), isEmpty);
      expect(await repo.getAllForShow(2), hasLength(1));
    });
  });
}
