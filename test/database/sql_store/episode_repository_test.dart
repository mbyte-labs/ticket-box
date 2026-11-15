import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';

/// Covers [EpisodeRepo.getAllForShow], the catalogue the progress calculator reads, and the
/// delete helpers.
void main() {
  late DatabaseConnectionManager db;
  late EpisodeRepo repo;

  const showId = 10;

  EpisodeEntity episode({int showTmdbId = showId, int season = 1, int number = 1, int? tmdbId = 1, String? airDate}) {
    return EpisodeEntity.build(
      showTmdbId: showTmdbId,
      season: season,
      episode: number,
      tmdbId: tmdbId,
      imdbId: null,
      title: 'Pilot',
      overview: null,
      voteAverage: 7,
      voteCount: 1,
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
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('getAllForShow', () {
    test('lists every cached episode of the show in order, with its air date', () async {
      await repo.insertAll([
        episode(season: 2, number: 1, tmdbId: 21),
        episode(season: 1, number: 2, tmdbId: 12),
        episode(season: 1, number: 1, tmdbId: 11, airDate: '2026-01-05'),
        // Another show's episode must not leak in.
        episode(showTmdbId: 99, tmdbId: 991),
      ]);

      final rows = await repo.getAllForShow(showId);

      expect(rows.map((r) => (r.season, r.episode)), [(1, 1), (1, 2), (2, 1)]);
      expect(rows.first.airDate, '2026-01-05');
      // The derived instant is local midnight of the stored date.
      expect(rows.first.firstAired?.isAtSameMomentAs(DateTime(2026, 1, 5)), isTrue);
      expect(rows.first.tmdbId, 11);
      expect(rows[1].airDate, isNull);
      expect(rows[1].firstAired, isNull, reason: 'no air date reads as not aired in the calculator');
    });

    test('is empty for a show with no cached episodes', () async {
      expect(await repo.getAllForShow(404), isEmpty);
    });
  });

  group('deletes', () {
    test('deleteByEpisodeNr removes that episode only', () async {
      await repo.insertAll([episode(number: 1), episode(number: 2)]);

      await repo.deleteByEpisodeNr(showId, 1, 1);

      expect(await repo.get(showId, 1, 1), isNull);
      expect(await repo.get(showId, 1, 2), isNotNull);
    });

    test('deleteBySeason removes that season only', () async {
      await repo.insertAll([episode(number: 1), episode(season: 2, number: 1)]);

      await repo.deleteBySeason(showId, 1);

      expect(await repo.getAllForSeason(showId, 1), isEmpty);
      expect(await repo.getAllForSeason(showId, 2), hasLength(1));
    });

    test('deleteByShowId removes every episode of the show', () async {
      await repo.insertAll([episode(number: 1), episode(season: 2, number: 1), episode(showTmdbId: 99)]);

      await repo.deleteByShowId(showId);

      expect(await repo.getAllForShow(showId), isEmpty);
      expect(await repo.getAllForShow(99), hasLength(1));
    });
  });
}
