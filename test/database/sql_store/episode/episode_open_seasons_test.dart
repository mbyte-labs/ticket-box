import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';

/// Guards [EpisodeRepo.getOpenSeasons], the refresh scheduler's re-fetch list: the highest-numbered
/// season is always open, a non-special season with an undated or future episode is open, a
/// closed past season is not, and specials never qualify through the episode rule.
void main() {
  late DatabaseConnectionManager db;
  late EpisodeRepo repo;
  late SeasonRepo seasonRepo;

  const showId = 1;
  const today = '2026-07-15';

  SeasonEntity season(int number, {int show = showId}) {
    return SeasonEntity.build(
      showTmdbId: show,
      season: number,
      tmdbId: show * 100 + number,
      title: null,
      episodeCount: null,
      airDate: null,
      posterPath: null,
      fetchedAt: null,
    );
  }

  EpisodeEntity episode(int seasonNr, int number, {String? airDate, int show = showId}) {
    return EpisodeEntity.build(
      showTmdbId: show,
      season: seasonNr,
      episode: number,
      tmdbId: null,
      imdbId: null,
      title: null,
      overview: null,
      voteAverage: 0,
      voteCount: 0,
      runtime: null,
      airDate: airDate,
      episodeType: null,
      stillPath: null,
    );
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = EpisodeRepo();
    seasonRepo = SeasonRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  test('the highest season is open even when every episode of it has aired', () async {
    await seasonRepo.insertAll([season(1), season(2), season(3)]);
    await repo.insertAll([
      episode(1, 1, airDate: '2020-01-01'),
      episode(2, 1, airDate: '2021-01-01'),
      episode(3, 1, airDate: '2022-01-01'),
    ]);

    expect(await repo.getOpenSeasons(showId, today), [3]);
  });

  test('a closed past season is not open', () async {
    await seasonRepo.insertAll([season(1), season(2)]);
    await repo.insertAll([
      episode(1, 1, airDate: '2020-01-01'),
      episode(1, 2, airDate: '2020-01-08'),
      episode(2, 1, airDate: '2021-01-01'),
    ]);

    expect(await repo.getOpenSeasons(showId, today), [2]);
  });

  test('a season with an undated episode is open', () async {
    await seasonRepo.insertAll([season(1), season(2), season(3)]);
    await repo.insertAll([episode(1, 1, airDate: '2020-01-01'), episode(1, 2), episode(2, 1, airDate: '2021-01-01'), episode(3, 1)]);

    expect(await repo.getOpenSeasons(showId, today), [1, 3]);
  });

  test('a season with an episode airing after today is open', () async {
    await seasonRepo.insertAll([season(1), season(2), season(3)]);
    await repo.insertAll([
      episode(1, 1, airDate: '2020-01-01'),
      episode(2, 1, airDate: '2026-07-01'),
      episode(2, 2, airDate: '2026-07-16'), // tomorrow
      episode(3, 1, airDate: '2026-07-01'),
    ]);

    expect(await repo.getOpenSeasons(showId, today), [2, 3]);
  });

  test('an episode airing today counts as aired, so it alone does not keep a season open', () async {
    await seasonRepo.insertAll([season(1), season(2)]);
    await repo.insertAll([episode(1, 1, airDate: '2026-07-14'), episode(1, 2, airDate: today), episode(2, 1, airDate: '2026-07-01')]);

    expect(await repo.getOpenSeasons(showId, today), [2]);
  });

  test('specials never qualify through the episode rule', () async {
    await seasonRepo.insertAll([season(0), season(1), season(2)]);
    await repo.insertAll([
      episode(0, 1), // undated special
      episode(0, 2, airDate: '2030-01-01'), // future special
      episode(1, 1, airDate: '2020-01-01'),
      episode(2, 1, airDate: '2021-01-01'),
    ]);

    expect(await repo.getOpenSeasons(showId, today), [2]);
  });

  test('a specials-only show still re-fetches its one season as the highest', () async {
    await seasonRepo.insert(season(0));
    await repo.insert(episode(0, 1, airDate: '2020-01-01'));

    expect(await repo.getOpenSeasons(showId, today), [0]);
  });

  test('every open season is listed once, in order, with the highest not duplicated', () async {
    await seasonRepo.insertAll([season(1), season(2), season(3), season(4)]);
    await repo.insertAll([
      episode(1, 1), // undated
      episode(1, 2), // undated, same season
      episode(2, 1, airDate: '2020-01-01'),
      episode(3, 1, airDate: '2030-01-01'),
      episode(4, 1), // undated and the highest
    ]);

    expect(await repo.getOpenSeasons(showId, today), [1, 3, 4]);
  });

  test('the highest season is read from the season rows, not the episodes', () async {
    // The root document listed a season whose episode list has not been fetched yet.
    await seasonRepo.insertAll([season(1), season(2)]);
    await repo.insert(episode(1, 1, airDate: '2020-01-01'));

    expect(await repo.getOpenSeasons(showId, today), [2]);
  });

  test('another show\'s seasons and episodes do not leak in', () async {
    await seasonRepo.insertAll([season(1), season(5, show: 2)]);
    await repo.insertAll([episode(1, 1, airDate: '2020-01-01'), episode(1, 2, show: 2), episode(5, 1, show: 2)]);

    expect(await repo.getOpenSeasons(showId, today), [1]);
    expect(await repo.getOpenSeasons(2, today), [1, 5]);
  });

  test('is empty for a show with no seasons', () async {
    expect(await repo.getOpenSeasons(404, today), isEmpty);
  });
}
