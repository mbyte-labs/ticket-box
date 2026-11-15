import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/pending_deletion/pending_deletion_repository.dart';

/// Guards the deferred-deletion queue: an item queued twice keeps its first timestamp (the grace
/// period runs from the first un-track, not the last), a movie and a show with the same TMDB id
/// are two rows, and the sweep reads what was queued at or before its cutoff, oldest first.
void main() {
  late DatabaseConnectionManager db;
  late PendingDeletionRepo repo;

  // A movie and an unrelated show that happen to share one TMDB id.
  const sharedTmdbId = 5;
  final queuedAt = DateTime.utc(2026, 7, 1);

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = PendingDeletionRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('enqueue', () {
    test('stores the item with its timestamp', () async {
      await repo.enqueue(ItemType.movie, 1, queuedAt);

      final stored = await repo.getAll();
      expect(stored, hasLength(1));
      expect(stored.single.type, ItemType.movie);
      expect(stored.single.tmdbId, 1);
      // Compared as instants: drift reads DateTimes back in local time.
      expect(stored.single.queuedAt.toUtc(), queuedAt);
    });

    test('an already queued item keeps its first timestamp', () async {
      await repo.enqueue(ItemType.movie, 1, queuedAt);

      await repo.enqueue(ItemType.movie, 1, DateTime.utc(2026, 8, 1));

      final stored = await repo.getAll();
      expect(stored, hasLength(1));
      expect(stored.single.queuedAt.toUtc(), queuedAt, reason: 'the grace period runs from the first un-track');
    });

    test('a movie and a show with the same tmdb id are different rows', () async {
      await repo.enqueue(ItemType.movie, sharedTmdbId, queuedAt);
      await repo.enqueue(ItemType.show, sharedTmdbId, DateTime.utc(2026, 7, 2));

      final stored = await repo.getAll();
      expect(stored.map((e) => (e.type, e.tmdbId)), unorderedEquals([(ItemType.movie, sharedTmdbId), (ItemType.show, sharedTmdbId)]));
      expect(await repo.count(), 2);
    });
  });

  group('delete', () {
    test('dequeues just that item, leaving the other type with the same id', () async {
      await repo.enqueue(ItemType.movie, sharedTmdbId, queuedAt);
      await repo.enqueue(ItemType.show, sharedTmdbId, queuedAt);

      await repo.delete(ItemType.movie, sharedTmdbId);

      final stored = await repo.getAll();
      expect(stored.single.type, ItemType.show);
      expect(stored.single.tmdbId, sharedTmdbId);
    });

    test('is a no-op for an item that is not queued', () async {
      await repo.enqueue(ItemType.show, 1, queuedAt);

      await repo.delete(ItemType.movie, 1);
      await repo.delete(ItemType.show, 404);

      expect(await repo.count(), 1);
    });

    test('deleteAll empties the queue', () async {
      await repo.enqueue(ItemType.movie, 1, queuedAt);
      await repo.enqueue(ItemType.show, 2, queuedAt);

      await repo.deleteAll();

      expect(await repo.getAll(), isEmpty);
      expect(await repo.count(), 0);
    });
  });

  group('getDue', () {
    test('returns the items queued at or before the cutoff, oldest first', () async {
      await repo.enqueue(ItemType.movie, 3, DateTime.utc(2026, 7, 3));
      await repo.enqueue(ItemType.show, 1, DateTime.utc(2026, 7, 1));
      await repo.enqueue(ItemType.movie, 2, DateTime.utc(2026, 7, 2));
      await repo.enqueue(ItemType.show, 4, DateTime.utc(2026, 7, 4));

      final due = await repo.getDue(DateTime.utc(2026, 7, 3));

      expect(due.map((e) => e.tmdbId), [1, 2, 3], reason: 'the cutoff itself is due; what came after is not');
      expect(due.first.type, ItemType.show);
    });

    test('is empty when nothing is old enough', () async {
      await repo.enqueue(ItemType.movie, 1, DateTime.utc(2026, 7, 2));

      expect(await repo.getDue(DateTime.utc(2026, 7, 1)), isEmpty);
    });
  });

  test('count and getAll are 0 and empty for an empty table', () async {
    expect(await repo.count(), 0);
    expect(await repo.getAll(), isEmpty);
  });
}
