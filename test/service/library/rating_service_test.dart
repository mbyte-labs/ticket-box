import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/pending_deletion/pending_deletion_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/library/rating_service.dart';

/// The real gate, with the calls recorded: the fixtures are tracked, so it never reaches TMDB.
class _RecordingLibrary extends LibraryService {
  final ensured = <MediaKey>[];

  @override
  Future<void> ensureTracked(MediaKey key) async {
    ensured.add(key);
    return super.ensureTracked(key);
  }
}

/// Seasons are not rated directly: [RatingService.seasonAverage] derives their score from the
/// episode ratings and the service refuses season targets. A rating is a tracking action: adding
/// one runs the library gate first, removing the last reference queues the title for deletion.
void main() {
  late DatabaseConnectionManager db;
  late RatingService service;
  late _RecordingLibrary library;

  const show = 1396;
  const movie = 550;

  MarkAsWatchedTarget episode(int season, int number) {
    return MarkAsWatchedTarget(type: ItemType.episode, showTmdbId: show, season: season, episode: number, title: 'Show', subtitle: '');
  }

  const seasonTarget = MarkAsWatchedTarget(type: ItemType.season, showTmdbId: show, season: 1, title: 'Show', subtitle: '');
  const movieTarget = MarkAsWatchedTarget(type: ItemType.movie, showTmdbId: movie, title: 'Movie', subtitle: '');

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    KeyValueStore.instance();
    library = _RecordingLibrary();
    GetIt.I.registerSingleton<LibraryService>(library);
    service = RatingService(library: library);
    final now = DateTime.now().toUtc();
    await ShowRepo().insert(ShowEntity.stub(tmdbId: show, trackedAt: now, title: 'Show'));
    await MovieRepo().insert(MovieEntity.stub(tmdbId: movie, trackedAt: now, title: 'Movie'));
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('seasonAverage', () {
    test('is null while no episode of the season is rated', () async {
      await service.addRating(target: episode(2, 1), rating: 9);

      expect(await service.seasonAverage(show, 1), isNull);
    });

    test("averages the season's episode ratings and counts them", () async {
      await service.addRating(target: episode(1, 1), rating: 7);
      await service.addRating(target: episode(1, 2), rating: 8);
      await service.addRating(target: episode(1, 3), rating: 8);
      await service.addRating(target: episode(2, 1), rating: 1);

      final average = await service.seasonAverage(show, 1);

      expect(average?.count, 3);
      expect(average?.average, closeTo(7.667, 0.001));
      expect(RatingService.formatAverage(average!.average), '7.7');
    });

    test('follows the ratings as they are removed', () async {
      await service.addRating(target: episode(1, 1), rating: 7);
      await service.addRating(target: episode(1, 2), rating: 8);
      expect((await service.seasonAverage(show, 1))?.average, 7.5);

      await service.removeRating(target: episode(1, 2));
      expect((await service.seasonAverage(show, 1))?.average, 7.0);

      await service.removeRating(target: episode(1, 1));
      expect(await service.seasonAverage(show, 1), isNull);
    });
  });

  test('refuses to rate or un-rate a season', () async {
    await expectLater(service.addRating(target: seasonTarget, rating: 7), throwsArgumentError);
    await expectLater(service.removeRating(target: seasonTarget), throwsArgumentError);
    expect(await UserRatingRepo().getAll(), isEmpty);
    expect(library.ensured, isEmpty);
  });

  test('re-rating overwrites the row rather than adding one', () async {
    await service.addRating(target: movieTarget, rating: 6);
    await service.addRating(target: movieTarget, rating: 9);

    final rows = await UserRatingRepo().getAll();
    expect(rows.single.rating, 9);
  });

  test('adding a rating runs the tracking gate on the title first', () async {
    await service.addRating(target: episode(1, 1), rating: 7);
    await service.addRating(target: movieTarget, rating: 8);

    expect(library.ensured, [episode(1, 1).key, movieTarget.key]);
  });

  test('removing the last reference of a tracked title queues it for deletion', () async {
    await service.addRating(target: movieTarget, rating: 8);
    expect(await PendingDeletionRepo().getAll(), isEmpty);

    await service.removeRating(target: movieTarget);

    expect((await PendingDeletionRepo().getAll()).map((e) => (e.type, e.tmdbId)), [(ItemType.movie, movie)]);
  });

  test('removing one rating of a show still rated elsewhere queues nothing', () async {
    await service.addRating(target: episode(1, 1), rating: 7);
    await service.addRating(target: episode(1, 2), rating: 8);

    await service.removeRating(target: episode(1, 2));
    expect(await PendingDeletionRepo().getAll(), isEmpty);

    await service.removeRating(target: episode(1, 1));
    expect((await PendingDeletionRepo().getAll()).map((e) => (e.type, e.tmdbId)), [(ItemType.show, show)]);
  });

  test('removing the rating of an untracked title queues nothing', () async {
    const untracked = MarkAsWatchedTarget(type: ItemType.movie, showTmdbId: 999, title: 'Gone', subtitle: '');

    await service.removeRating(target: untracked);

    expect(await PendingDeletionRepo().getAll(), isEmpty);
  });
}
