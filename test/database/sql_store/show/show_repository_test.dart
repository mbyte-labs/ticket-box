import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';

/// Guards the library reads and writes of [ShowRepo]: the bulk lookup behind the grids
/// ([ShowRepo.getMany] — missing ids silently absent, an empty input must not render the `IN ()`
/// SQLite rejects, an id list larger than one chunk must still come back complete), the stub
/// insert a restore or account pull makes ([ShowRepo.insertStubs] never touches an existing row),
/// the backfill's work list ([ShowRepo.getIdsWithoutSnapshot], oldest in the library first), the
/// 404 silencer ([ShowRepo.stampFetched]) and the sweep's [ShowRepo.delete].
void main() {
  late DatabaseConnectionManager db;
  late ShowRepo showRepo;

  final fetchedAt = DateTime.utc(2026, 7, 1, 12);
  final trackedAt = DateTime.utc(2026, 6, 1);

  ShowEntity show(int tmdbId, {String? title, int? year = 2020, DateTime? fetched, DateTime? tracked, String genres = '18'}) {
    return ShowEntity.build(
      tmdbId: tmdbId,
      imdbId: 'tt$tmdbId',
      title: title ?? 'Show $tmdbId',
      year: year,
      overview: 'Overview $tmdbId',
      tagline: null,
      firstAirDate: '2020-01-15',
      lastAirDate: '2021-03-01',
      runtime: 40,
      certification: null,
      network: 'HBO',
      country: 'US',
      language: 'en',
      trailer: null,
      homepage: null,
      voteAverage: 8.0,
      voteCount: 100,
      popularity: 12.5,
      numberOfSeasons: 2,
      nextEpisodeAirDate: '2026-09-01',
      nextEpisodeSeason: 3,
      nextEpisodeNumber: 1,
      genres: genres,
      status: 'returning',
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
    showRepo = ShowRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('insert', () {
    test('stores every column and reads it back', () async {
      await showRepo.insert(show(1));

      final stored = await showRepo.get(1);
      expect(stored, isNotNull);
      expect(stored!.title, 'Show 1');
      expect(stored.imdbId, 'tt1');
      expect(stored.firstAirDate, '2020-01-15');
      expect(stored.firstAired, DateTime(2020, 1, 15));
      expect(stored.lastAired, DateTime(2021, 3, 1));
      expect(stored.nextEpisodeAirsAt, DateTime(2026, 9, 1));
      expect(stored.nextEpisodeSeason, 3);
      expect(stored.numberOfSeasons, 2);
      expect(stored.genreList, [18]);
      expect(stored.posterPath, '/p1.jpg');
      expect(stored.watchProvidersRegion, 'RO');
      // Compared as instants: drift reads DateTimes back in local time.
      expect(stored.fetchedAt?.toUtc(), fetchedAt);
      expect(stored.trackedAt.toUtc(), trackedAt);
      expect(stored.hasSnapshot, isTrue);
    });

    test('replaces the whole row of an existing show', () async {
      await showRepo.insert(show(1, title: 'Old'));

      await showRepo.insert(show(1, title: 'New', genres: '35,18'));

      final stored = await showRepo.get(1);
      expect(stored?.title, 'New');
      expect(stored?.genreList, [35, 18]);
      expect(await showRepo.getAll(), hasLength(1));
    });

    test('get is null and exists false for an unknown show', () async {
      expect(await showRepo.get(404), isNull);
      expect(await showRepo.exists(404), isFalse);
    });
  });

  group('getMany', () {
    test('returns the requested shows keyed by id, missing ids silently absent', () async {
      await showRepo.insertAll([show(1), show(2), show(3)]);

      final result = await showRepo.getMany([1, 3, 99]);

      expect(result.keys, unorderedEquals([1, 3]));
      expect(result[3]?.title, 'Show 3');
    });

    test('returns an empty map for an empty input without a SQL error', () async {
      expect(await showRepo.getMany([]), isEmpty);
    });

    test('spans multiple chunks for a large id list', () async {
      // Above the 500-id chunk size, so the lookup has to concatenate two queries.
      const count = 750;
      await showRepo.insertAll(List.generate(count, (index) => show(index + 1)));

      final result = await showRepo.getMany(List.generate(count, (index) => index + 1));

      expect(result, hasLength(count));
      expect(result[count]?.title, 'Show $count');
    });
  });

  group('getAll and getAllIds', () {
    test('return every tracked show', () async {
      await showRepo.insertAll([show(1), show(2)]);
      await showRepo.insertStubs([3], trackedAt: trackedAt);

      expect((await showRepo.getAll()).map((s) => s.tmdbId), unorderedEquals([1, 2, 3]));
      expect(await showRepo.getAllIds(), {1, 2, 3});
    });

    test('are empty for an empty table', () async {
      expect(await showRepo.getAll(), isEmpty);
      expect(await showRepo.getAllIds(), isEmpty);
    });
  });

  group('insertStubs', () {
    test('creates unfetched rows that only know when the show was tracked', () async {
      await showRepo.insertStubs([1, 2], trackedAt: trackedAt);

      final stored = await showRepo.get(1);
      expect(stored, isNotNull);
      expect(stored!.fetchedAt, isNull);
      expect(stored.hasSnapshot, isFalse);
      expect(stored.trackedAt.toUtc(), trackedAt);
      expect(stored.title, isNull);
      expect(stored.genres, '');
      expect(stored.voteAverage, 0);
      expect(stored.numberOfSeasons, 0);
      expect(await showRepo.exists(2), isTrue);
    });

    test('leaves an existing row untouched', () async {
      await showRepo.insert(show(1, title: 'Fetched'));

      await showRepo.insertStubs([1, 2], trackedAt: DateTime.utc(2027)); // a later "tracked at" than the row's

      final stored = await showRepo.get(1);
      expect(stored?.title, 'Fetched');
      expect(stored?.fetchedAt?.toUtc(), fetchedAt, reason: 'a stub must not wipe the snapshot bookkeeping');
      expect(stored?.trackedAt.toUtc(), trackedAt, reason: 'the show did not enter the library again');
      expect(await showRepo.exists(2), isTrue);
    });

    test('inserts a repeated id once and accepts an empty input', () async {
      await showRepo.insertStubs([5, 5, 5], trackedAt: trackedAt);
      await showRepo.insertStubs([], trackedAt: trackedAt);

      expect(await showRepo.getAllIds(), {5});
    });
  });

  group('getIdsWithoutSnapshot', () {
    test('lists the unfetched shows, oldest in the library first', () async {
      await showRepo.insertStubs([3], trackedAt: DateTime.utc(2026, 3));
      await showRepo.insertStubs([1], trackedAt: DateTime.utc(2026, 1));
      await showRepo.insertStubs([2], trackedAt: DateTime.utc(2026, 2));
      // A fetched show is not on the work list, however old.
      await showRepo.insert(show(4, tracked: DateTime.utc(2025)));

      expect(await showRepo.getIdsWithoutSnapshot(), [1, 2, 3]);
    });

    test('is empty when every show has a snapshot', () async {
      await showRepo.insert(show(1));

      expect(await showRepo.getIdsWithoutSnapshot(), isEmpty);
    });
  });

  group('stampFetched', () {
    test('moves fetchedAt forward and nothing else', () async {
      await showRepo.insert(show(1, title: 'Kept'));
      final later = DateTime.utc(2026, 8, 1);

      await showRepo.stampFetched(1, later);

      final stored = await showRepo.get(1);
      expect(stored?.fetchedAt?.toUtc(), later);
      expect(stored?.title, 'Kept');
      expect(stored?.trackedAt.toUtc(), trackedAt);
    });

    test('takes a stub off the backfill work list', () async {
      await showRepo.insertStubs([1], trackedAt: trackedAt);

      await showRepo.stampFetched(1, fetchedAt);

      expect(await showRepo.getIdsWithoutSnapshot(), isEmpty);
      expect((await showRepo.get(1))?.title, isNull);
    });

    test('is a no-op for an unknown show', () async {
      await showRepo.stampFetched(404, fetchedAt);

      expect(await showRepo.get(404), isNull);
    });
  });

  group('delete', () {
    test('removes just that show', () async {
      await showRepo.insertAll([show(1), show(2)]);

      await showRepo.delete(1);

      expect(await showRepo.get(1), isNull);
      expect(await showRepo.get(2), isNotNull);
    });

    test('is a no-op for an unknown show', () async {
      await showRepo.insert(show(1));

      await showRepo.delete(404);

      expect(await showRepo.getAllIds(), {1});
    });
  });

  test('listenForChanges fires after a write', () async {
    var emissions = 0;
    final subscription = showRepo.listenForChanges().listen((_) => emissions++);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await showRepo.insert(show(1));
    await pumpEventQueue();

    expect(emissions, 2);
  });
}
