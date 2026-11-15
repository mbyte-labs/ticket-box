import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_entity.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';

/// Guards the `show_states` reads the pages and the sweep run: the dropped / non-dropped / finished
/// id sets must partition on [ShowWatchStatus], [ShowStateRepo.deleteNonDropped] must keep the
/// user's dropped rows (the one value the system never writes), and the Dropped Shows page reads
/// most recently dropped first.
void main() {
  late DatabaseConnectionManager db;
  late ShowStateRepo repo;

  final at = DateTime.utc(2026, 7, 1);

  ShowStateEntity state(int showId, ShowWatchStatus status, {DateTime? updatedAt}) {
    return ShowStateEntity.build(showTmdbId: showId, status: status, updatedAt: updatedAt ?? at);
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = ShowStateRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('upsert', () {
    test('inserts a row and reads it back', () async {
      await repo.upsert(1, ShowWatchStatus.watching, at);

      final stored = await repo.get(1);
      expect(stored, isNotNull);
      expect(stored!.showTmdbId, 1);
      expect(stored.status, ShowWatchStatus.watching);
      // Compared as instants: drift reads DateTimes back in local time.
      expect(stored.updatedAt.toUtc(), at);
      expect(stored.isDropped, isFalse);
    });

    test('replaces the status and timestamp of an existing row', () async {
      await repo.upsert(1, ShowWatchStatus.watching, at);
      final later = DateTime.utc(2026, 8, 1);

      await repo.upsert(1, ShowWatchStatus.watched, later);

      final stored = await repo.get(1);
      expect(stored?.status, ShowWatchStatus.watched);
      expect(stored?.updatedAt.toUtc(), later);
      expect(await repo.getNonDroppedIds(), {1}, reason: 'still one row');
    });

    test('get is null for a show without a row', () async {
      expect(await repo.get(404), isNull);
      expect(await repo.isDropped(404), isFalse);
    });
  });

  group('upsertAll', () {
    test('writes every row, replacing existing ones', () async {
      await repo.upsert(1, ShowWatchStatus.watching, at);

      await repo.upsertAll([state(1, ShowWatchStatus.watched), state(2, ShowWatchStatus.dropped)]);

      expect((await repo.get(1))?.status, ShowWatchStatus.watched);
      expect((await repo.get(2))?.status, ShowWatchStatus.dropped);
    });

    test('an empty list is a no-op', () async {
      await repo.upsertAll([]);

      expect(await repo.getNonDroppedIds(), isEmpty);
      expect(await repo.getDroppedIds(), isEmpty);
    });
  });

  group('status partitions', () {
    setUp(() async {
      await repo.upsertAll([
        state(1, ShowWatchStatus.watching),
        state(2, ShowWatchStatus.watched),
        state(3, ShowWatchStatus.dropped, updatedAt: DateTime.utc(2026, 7, 2)),
        state(4, ShowWatchStatus.dropped, updatedAt: DateTime.utc(2026, 7, 5)),
        state(5, ShowWatchStatus.watched),
      ]);
    });

    test('isDropped is true for dropped rows only', () async {
      expect(await repo.isDropped(3), isTrue);
      expect(await repo.isDropped(1), isFalse);
      expect(await repo.isDropped(2), isFalse);
    });

    test('getDropped lists the dropped shows, most recently dropped first', () async {
      final dropped = await repo.getDropped();

      expect(dropped.map((s) => s.showTmdbId), [4, 3]);
      expect(dropped.every((s) => s.isDropped), isTrue);
    });

    test('getDroppedIds, getNonDroppedIds and getFinishedIds partition on the status', () async {
      expect(await repo.getDroppedIds(), {3, 4});
      expect(await repo.getNonDroppedIds(), {1, 2, 5});
      expect(await repo.getFinishedIds(), {2, 5});
    });

    test('countDropped counts the dropped rows only', () async {
      expect(await repo.countDropped(), 2);
    });

    test('deleteNonDropped removes the system-maintained rows and keeps the dropped ones', () async {
      await repo.deleteNonDropped();

      expect(await repo.getNonDroppedIds(), isEmpty);
      expect(await repo.getFinishedIds(), isEmpty);
      expect(await repo.getDroppedIds(), {3, 4});
      expect(await repo.get(1), isNull);
    });

    test('delete removes just that show', () async {
      await repo.delete(3);

      expect(await repo.get(3), isNull);
      expect(await repo.getDroppedIds(), {4});
      expect(await repo.getNonDroppedIds(), {1, 2, 5});
    });
  });

  test('the sets and count are empty for an empty table', () async {
    expect(await repo.getDroppedIds(), isEmpty);
    expect(await repo.getNonDroppedIds(), isEmpty);
    expect(await repo.getFinishedIds(), isEmpty);
    expect(await repo.getDropped(), isEmpty);
    expect(await repo.countDropped(), 0);
  });

  test('listenForChanges fires after a write', () async {
    var emissions = 0;
    final subscription = repo.listenForChanges().listen((_) => emissions++);
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await repo.upsert(1, ShowWatchStatus.watching, at);
    await pumpEventQueue();

    expect(emissions, 2);
  });
}
