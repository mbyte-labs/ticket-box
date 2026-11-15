import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';

/// Guards [UserRatingRepo.getAll] - the stats page reads the whole table at once to compute the
/// rating averages, so every stored type has to come back - and [UserRatingRepo.listenForChanges],
/// the stream `DataChangeMonitor` reacts to.
void main() {
  late DatabaseConnectionManager db;
  late UserRatingRepo ratingRepo;

  UserRatingEntity rating(ItemType type, int tmdbId, int value, {int season = 0, int episode = 0}) {
    return UserRatingEntity.build(
      type: type,
      tmdbId: tmdbId,
      season: season,
      episode: episode,
      rating: value,
      ratedAt: DateTime.utc(2026, 7, 1),
    );
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    ratingRepo = UserRatingRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  test('returns every rating across all item types', () async {
    await ratingRepo.insertAll([
      rating(ItemType.movie, 1, 8),
      rating(ItemType.show, 2, 9),
      rating(ItemType.episode, 3, 7, season: 1, episode: 2),
      rating(ItemType.season, 3, 6, season: 1),
    ]);

    final result = await ratingRepo.getAll();

    expect(result, hasLength(4));
    expect(result.map((entry) => entry.type), unorderedEquals([ItemType.movie, ItemType.show, ItemType.episode, ItemType.season]));
    expect(result.firstWhere((entry) => entry.type == ItemType.movie).rating, 8);
  });

  test('returns an empty list for an empty table', () async {
    expect(await ratingRepo.getAll(), isEmpty);
  });

  test('a movie and a show with the same tmdb id are different ratings', () async {
    await ratingRepo.insertAll([rating(ItemType.movie, 1, 8), rating(ItemType.show, 1, 3)]);

    expect((await ratingRepo.get(ItemType.movie, 1))?.rating, 8);
    expect((await ratingRepo.get(ItemType.show, 1))?.rating, 3);
    expect((await ratingRepo.getByKey(const MediaKey.show(1)))?.rating, 3);

    await ratingRepo.delete(ItemType.movie, 1);

    expect(await ratingRepo.get(ItemType.movie, 1), isNull);
    expect(await ratingRepo.get(ItemType.show, 1), isNotNull);
  });

  test('rating the same item again replaces the old value', () async {
    await ratingRepo.insert(rating(ItemType.episode, 3, 5, season: 1, episode: 2));
    await ratingRepo.insert(rating(ItemType.episode, 3, 9, season: 1, episode: 2));

    final all = await ratingRepo.getAll();
    expect(all, hasLength(1));
    expect(all.single.rating, 9);
    expect((await ratingRepo.getByKey(const MediaKey.episode(3, 1, 2)))?.rating, 9);
  });

  test("getForSeasonEpisodes returns only that season's episode ratings", () async {
    await ratingRepo.insertAll([
      rating(ItemType.episode, 3, 7, season: 1, episode: 1),
      rating(ItemType.episode, 3, 9, season: 1, episode: 2),
      rating(ItemType.episode, 3, 4, season: 2, episode: 1),
      rating(ItemType.episode, 4, 2, season: 1, episode: 1),
      rating(ItemType.season, 3, 6, season: 1),
      rating(ItemType.show, 3, 5),
    ]);

    final result = await ratingRepo.getForSeasonEpisodes(3, 1);

    expect(result.map((entry) => (entry.episode, entry.rating)), unorderedEquals([(1, 7), (2, 9)]));
  });

  group('listenForChanges', () {
    test('emits the current table first and again after every write', () async {
      await ratingRepo.insert(rating(ItemType.movie, 1, 8));

      final emissions = <List<int>>[];
      final subscription = ratingRepo.listenForChanges().listen((rows) => emissions.add(rows.map((r) => r.rating).toList()..sort()));
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await ratingRepo.insert(rating(ItemType.show, 2, 9));
      await pumpEventQueue();
      await ratingRepo.deleteByKey(const MediaKey.movie(1));
      await pumpEventQueue();

      expect(emissions.first, [8]);
      expect(emissions, anyElement(orderedEquals([8, 9])));
      expect(emissions.last, [9]);
    });

    test('replaceAll publishes only the final state', () async {
      await ratingRepo.insert(rating(ItemType.movie, 1, 8));

      final counts = <int>[];
      final subscription = ratingRepo.listenForChanges().listen((rows) => counts.add(rows.length));
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await ratingRepo.replaceAll([rating(ItemType.movie, 1, 8), rating(ItemType.show, 2, 9), rating(ItemType.show, 3, 7)]);
      await pumpEventQueue();

      expect(counts.first, 1);
      expect(counts.skip(1), isNot(contains(0)), reason: 'one batch = one transaction: the delete must not be observable');
      expect(counts.last, 3);
    });
  });
}
