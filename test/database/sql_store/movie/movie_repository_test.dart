import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';

/// Guards the library reads and writes of [MovieRepo]: the bulk lookup behind the grids
/// ([MovieRepo.getMany] — missing ids silently absent, an empty input must not render the `IN ()`
/// SQLite rejects, an id list larger than one chunk must still come back complete), the stub
/// insert a restore or account pull makes ([MovieRepo.insertStubs] never touches an existing row),
/// the backfill's work list ([MovieRepo.getIdsWithoutSnapshot], oldest in the library first), the
/// 404 silencer ([MovieRepo.stampFetched]) and the sweep's [MovieRepo.delete].
void main() {
  late DatabaseConnectionManager db;
  late MovieRepo movieRepo;

  final fetchedAt = DateTime.utc(2026, 7, 1, 12);
  final trackedAt = DateTime.utc(2026, 6, 1);

  MovieEntity movie(int tmdbId, {String? title, int? year = 2020, DateTime? fetched, DateTime? tracked, String genres = '28'}) {
    return MovieEntity.build(
      tmdbId: tmdbId,
      imdbId: 'tt$tmdbId',
      title: title ?? 'Movie $tmdbId',
      year: year,
      overview: 'Overview $tmdbId',
      tagline: 'Tagline',
      releaseDate: '2020-05-20',
      runtime: 120,
      certification: 'PG-13',
      country: 'US',
      language: 'en',
      trailer: null,
      homepage: null,
      voteAverage: 7.5,
      voteCount: 1000,
      popularity: 42.0,
      genres: genres,
      status: 'released',
      posterPath: '/p$tmdbId.jpg',
      backdropPath: '/b$tmdbId.jpg',
      fetchedAt: fetched ?? fetchedAt,
      trackedAt: tracked ?? trackedAt,
      watchProvidersRegion: 'RO',
    );
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    movieRepo = MovieRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('insert', () {
    test('stores every column and reads it back', () async {
      await movieRepo.insert(movie(1));

      final stored = await movieRepo.get(1);
      expect(stored, isNotNull);
      expect(stored!.title, 'Movie 1');
      expect(stored.imdbId, 'tt1');
      expect(stored.releaseDate, '2020-05-20');
      expect(stored.released, DateTime(2020, 5, 20));
      expect(stored.runtime, 120);
      expect(stored.certification, 'PG-13');
      expect(stored.genreList, [28]);
      expect(stored.posterPath, '/p1.jpg');
      expect(stored.backdropPath, '/b1.jpg');
      expect(stored.watchProvidersRegion, 'RO');
      // Compared as instants: drift reads DateTimes back in local time.
      expect(stored.fetchedAt?.toUtc(), fetchedAt);
      expect(stored.trackedAt.toUtc(), trackedAt);
      expect(stored.hasSnapshot, isTrue);
    });

    test('replaces the whole row of an existing movie', () async {
      await movieRepo.insert(movie(1, title: 'Old'));

      await movieRepo.insert(movie(1, title: 'New', genres: '12,28'));

      final stored = await movieRepo.get(1);
      expect(stored?.title, 'New');
      expect(stored?.genreList, [12, 28]);
      expect(await movieRepo.getAll(), hasLength(1));
    });

    test('get is null and exists false for an unknown movie', () async {
      expect(await movieRepo.get(404), isNull);
      expect(await movieRepo.exists(404), isFalse);
    });
  });

  group('getMany', () {
    test('returns the requested movies keyed by id, missing ids silently absent', () async {
      await movieRepo.insertAll([movie(1), movie(2), movie(3)]);

      final result = await movieRepo.getMany([1, 3, 99]);

      expect(result.keys, unorderedEquals([1, 3]));
      expect(result[3]?.title, 'Movie 3');
    });

    test('returns an empty map for an empty input without a SQL error', () async {
      expect(await movieRepo.getMany([]), isEmpty);
    });

    test('spans multiple chunks for a large id list', () async {
      // Above the 500-id chunk size, so the lookup has to concatenate two queries.
      const count = 750;
      await movieRepo.insertAll(List.generate(count, (index) => movie(index + 1)));

      final result = await movieRepo.getMany(List.generate(count, (index) => index + 1));

      expect(result, hasLength(count));
      expect(result[count]?.title, 'Movie $count');
    });
  });

  group('getAll and getAllIds', () {
    test('return every tracked movie', () async {
      await movieRepo.insertAll([movie(1), movie(2)]);
      await movieRepo.insertStubs([3], trackedAt: trackedAt);

      expect((await movieRepo.getAll()).map((m) => m.tmdbId), unorderedEquals([1, 2, 3]));
      expect(await movieRepo.getAllIds(), {1, 2, 3});
    });

    test('are empty for an empty table', () async {
      expect(await movieRepo.getAll(), isEmpty);
      expect(await movieRepo.getAllIds(), isEmpty);
    });
  });

  group('insertStubs', () {
    test('creates unfetched rows that only know when the movie was tracked', () async {
      await movieRepo.insertStubs([1, 2], trackedAt: trackedAt);

      final stored = await movieRepo.get(1);
      expect(stored, isNotNull);
      expect(stored!.fetchedAt, isNull);
      expect(stored.hasSnapshot, isFalse);
      expect(stored.trackedAt.toUtc(), trackedAt);
      expect(stored.title, isNull);
      expect(stored.runtime, isNull);
      expect(stored.genres, '');
      expect(stored.voteAverage, 0);
      expect(await movieRepo.exists(2), isTrue);
    });

    test('leaves an existing row untouched', () async {
      await movieRepo.insert(movie(1, title: 'Fetched'));

      await movieRepo.insertStubs([1, 2], trackedAt: DateTime.utc(2027)); // a later "tracked at" than the row's

      final stored = await movieRepo.get(1);
      expect(stored?.title, 'Fetched');
      expect(stored?.fetchedAt?.toUtc(), fetchedAt, reason: 'a stub must not wipe the snapshot bookkeeping');
      expect(stored?.trackedAt.toUtc(), trackedAt, reason: 'the movie did not enter the library again');
      expect(await movieRepo.exists(2), isTrue);
    });

    test('inserts a repeated id once and accepts an empty input', () async {
      await movieRepo.insertStubs([5, 5, 5], trackedAt: trackedAt);
      await movieRepo.insertStubs([], trackedAt: trackedAt);

      expect(await movieRepo.getAllIds(), {5});
    });
  });

  group('getIdsWithoutSnapshot', () {
    test('lists the unfetched movies, oldest in the library first', () async {
      await movieRepo.insertStubs([3], trackedAt: DateTime.utc(2026, 3));
      await movieRepo.insertStubs([1], trackedAt: DateTime.utc(2026, 1));
      await movieRepo.insertStubs([2], trackedAt: DateTime.utc(2026, 2));
      // A fetched movie is not on the work list, however old.
      await movieRepo.insert(movie(4, tracked: DateTime.utc(2025)));

      expect(await movieRepo.getIdsWithoutSnapshot(), [1, 2, 3]);
    });

    test('is empty when every movie has a snapshot', () async {
      await movieRepo.insert(movie(1));

      expect(await movieRepo.getIdsWithoutSnapshot(), isEmpty);
    });
  });

  group('stampFetched', () {
    test('moves fetchedAt forward and nothing else', () async {
      await movieRepo.insert(movie(1, title: 'Kept'));
      final later = DateTime.utc(2026, 8, 1);

      await movieRepo.stampFetched(1, later);

      final stored = await movieRepo.get(1);
      expect(stored?.fetchedAt?.toUtc(), later);
      expect(stored?.title, 'Kept');
      expect(stored?.trackedAt.toUtc(), trackedAt);
    });

    test('takes a stub off the backfill work list', () async {
      await movieRepo.insertStubs([1], trackedAt: trackedAt);

      await movieRepo.stampFetched(1, fetchedAt);

      expect(await movieRepo.getIdsWithoutSnapshot(), isEmpty);
      expect((await movieRepo.get(1))?.title, isNull);
    });

    test('is a no-op for an unknown movie', () async {
      await movieRepo.stampFetched(404, fetchedAt);

      expect(await movieRepo.get(404), isNull);
    });
  });

  group('delete', () {
    test('removes just that movie', () async {
      await movieRepo.insertAll([movie(1), movie(2)]);

      await movieRepo.delete(1);

      expect(await movieRepo.get(1), isNull);
      expect(await movieRepo.get(2), isNotNull);
    });

    test('is a no-op for an unknown movie', () async {
      await movieRepo.insert(movie(1));

      await movieRepo.delete(404);

      expect(await movieRepo.getAllIds(), {1});
    });
  });

  test('listenForChanges fires after a write', () async {
    var emissions = 0;
    final subscription = movieRepo.listenForChanges().listen((_) => emissions++);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await movieRepo.insert(movie(1));
    await pumpEventQueue();

    expect(emissions, 2);
  });
}
