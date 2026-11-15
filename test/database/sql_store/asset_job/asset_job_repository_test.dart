import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/asset_job_status.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';

/// Guards the artwork download queue: `dest_path` is the idempotency key (a re-enqueue after a
/// crash is a no-op), the worker drains pending rows by id and only once their retry time has
/// passed, a retry counts its attempts, and the resets / deletes are scoped to one path or one
/// owning item — a movie and a show with the same TMDB id own separate artwork.
void main() {
  late DatabaseConnectionManager db;
  late AssetJobRepo repo;

  final createdAt = DateTime.utc(2026, 7, 1);
  final now = DateTime.utc(2026, 7, 2, 12);

  NewAssetJob job(String destPath, {ItemType mediaType = ItemType.movie, int itemId = 1, String kind = 'poster', String size = 'w342'}) {
    return NewAssetJob(
      mediaType: mediaType,
      itemId: itemId,
      kind: kind,
      size: size,
      sourceUrl: 'https://image.tmdb.org/t/p/$size$destPath',
      destPath: destPath,
    );
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = AssetJobRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  group('insertIgnore', () {
    test('queues the jobs as pending with the bookkeeping zeroed', () async {
      await repo.insertIgnore([job('/a.jpg'), job('/b.jpg', kind: 'backdrop', size: 'w1280')], createdAt: createdAt);

      final rows = await repo.getByDestPaths(['/a.jpg', '/b.jpg']);
      expect(rows.keys, unorderedEquals(['/a.jpg', '/b.jpg']));
      final a = rows['/a.jpg']!;
      expect(a.status, AssetJobStatus.pending);
      expect(a.provider, 'tmdb');
      expect(a.mediaType, ItemType.movie);
      expect(a.itemId, 1);
      expect(a.kind, 'poster');
      expect(a.size, 'w342');
      expect(a.sourceUrl, 'https://image.tmdb.org/t/p/w342/a.jpg');
      expect(a.attempts, 0);
      expect(a.nextRetryAt, isNull);
      expect(a.lastError, isNull);
      // Compared as instants: drift reads DateTimes back in local time.
      expect(a.createdAt.toUtc(), createdAt);
      expect(rows['/b.jpg']!.size, 'w1280');
    });

    test('is idempotent on dest_path: a second enqueue leaves the first row as it is', () async {
      await repo.insertIgnore([job('/a.jpg', size: 'w342')], createdAt: createdAt);
      final first = (await repo.getByDestPaths(['/a.jpg']))['/a.jpg']!;
      await repo.markDone(first.id);

      await repo.insertIgnore([job('/a.jpg', size: 'w780'), job('/c.jpg')], createdAt: DateTime.utc(2026, 8, 1));

      final rows = await repo.getByDestPaths(['/a.jpg', '/c.jpg']);
      final a = rows['/a.jpg']!;
      expect(a.id, first.id);
      expect(a.status, AssetJobStatus.done, reason: 'a re-enqueue must not re-download a finished file');
      expect(a.size, 'w342');
      expect(a.createdAt.toUtc(), createdAt);
      expect(rows['/c.jpg']!.status, AssetJobStatus.pending, reason: 'the new path in the same batch is still inserted');
      expect(await repo.countAllPending(), 1);
    });

    test('can insert rows as done, for a file already on disk', () async {
      await repo.insertIgnore([job('/a.jpg')], createdAt: createdAt, status: AssetJobStatus.done);

      expect((await repo.getByDestPaths(['/a.jpg']))['/a.jpg']!.status, AssetJobStatus.done);
      expect(await repo.donePaths(), ['/a.jpg']);
      expect(await repo.countAllPending(), 0);
    });

    test('an empty list is a no-op', () async {
      await repo.insertIgnore([], createdAt: createdAt);

      expect(await repo.countAllPending(), 0);
    });
  });

  group('getByDestPaths', () {
    test('returns the known paths only and nothing for an empty input', () async {
      await repo.insertIgnore([job('/a.jpg')], createdAt: createdAt);

      expect((await repo.getByDestPaths(['/a.jpg', '/missing.jpg', '/a.jpg'])).keys, ['/a.jpg']);
      expect(await repo.getByDestPaths([]), isEmpty);
    });

    test('spans multiple chunks for a large path list', () async {
      // Above the 500-path chunk size, so the lookup has to concatenate two queries.
      const count = 750;
      await repo.insertIgnore(List.generate(count, (index) => job('/$index.jpg', itemId: index)), createdAt: createdAt);

      final rows = await repo.getByDestPaths(List.generate(count, (index) => '/$index.jpg'));

      expect(rows, hasLength(count));
    });
  });

  group('getPending', () {
    test('returns pending rows by id, limited, after the given id', () async {
      await repo.insertIgnore([job('/a.jpg'), job('/b.jpg'), job('/c.jpg'), job('/d.jpg')], createdAt: createdAt);
      final ids = (await repo.getByDestPaths(['/a.jpg', '/b.jpg', '/c.jpg', '/d.jpg'])).map((path, row) => MapEntry(path, row.id));

      final firstPage = await repo.getPending(2, now: now);
      expect(firstPage.map((r) => r.destPath), ['/a.jpg', '/b.jpg']);
      expect(firstPage.map((r) => r.id), [ids['/a.jpg'], ids['/b.jpg']]);

      final secondPage = await repo.getPending(2, afterId: firstPage.last.id, now: now);
      expect(secondPage.map((r) => r.destPath), ['/c.jpg', '/d.jpg']);

      expect(await repo.getPending(2, afterId: secondPage.last.id, now: now), isEmpty);
    });

    test('skips done and failed rows', () async {
      await repo.insertIgnore([job('/a.jpg'), job('/b.jpg'), job('/c.jpg')], createdAt: createdAt);
      final rows = await repo.getByDestPaths(['/a.jpg', '/b.jpg']);
      await repo.markDone(rows['/a.jpg']!.id);
      await repo.markFailed(rows['/b.jpg']!.id, 'gone');

      expect((await repo.getPending(10, now: now)).map((r) => r.destPath), ['/c.jpg']);
    });

    test('holds back a row whose retry time has not come, and releases it once it has', () async {
      await repo.insertIgnore([job('/a.jpg'), job('/b.jpg')], createdAt: createdAt);
      final a = (await repo.getByDestPaths(['/a.jpg']))['/a.jpg']!;
      final retryAt = now.add(const Duration(hours: 1));
      await repo.markRetry(a.id, 'timeout', retryAt);

      expect((await repo.getPending(10, now: now)).map((r) => r.destPath), ['/b.jpg']);
      expect(await repo.countPending(now: now), 1);
      expect(await repo.countAllPending(), 2, reason: 'a waiting retry is still pending');

      expect((await repo.getPending(10, now: retryAt)).map((r) => r.destPath), [
        '/a.jpg',
        '/b.jpg',
      ], reason: 'due at the retry time itself');
      expect(await repo.countPending(now: retryAt.add(const Duration(minutes: 1))), 2);
    });

    test('is empty for an empty table', () async {
      expect(await repo.getPending(10, now: now), isEmpty);
    });
  });

  group('outcome writes', () {
    late int id;

    setUp(() async {
      await repo.insertIgnore([job('/a.jpg')], createdAt: createdAt);
      id = (await repo.getByDestPaths(['/a.jpg']))['/a.jpg']!.id;
    });

    Future<void> expectRow({required AssetJobStatus status, required int attempts, DateTime? nextRetryAt, String? lastError}) async {
      final row = (await repo.getByDestPaths(['/a.jpg']))['/a.jpg']!;
      expect(row.status, status);
      expect(row.attempts, attempts);
      expect(row.nextRetryAt?.toUtc(), nextRetryAt);
      expect(row.lastError, lastError);
    }

    test('markRetry increments attempts and records the error and the retry time', () async {
      final retryAt = now.add(const Duration(minutes: 5));

      await repo.markRetry(id, 'timeout', retryAt);
      await expectRow(status: AssetJobStatus.pending, attempts: 1, nextRetryAt: retryAt, lastError: 'timeout');

      final laterRetry = now.add(const Duration(minutes: 30));
      await repo.markRetry(id, 'reset by peer', laterRetry);
      await expectRow(status: AssetJobStatus.pending, attempts: 2, nextRetryAt: laterRetry, lastError: 'reset by peer');
    });

    test('markDone clears the retry bookkeeping and keeps the attempt count', () async {
      await repo.markRetry(id, 'timeout', now);

      await repo.markDone(id);

      await expectRow(status: AssetJobStatus.done, attempts: 1);
      expect(await repo.donePaths(), ['/a.jpg']);
    });

    test('markFailed records the error, keeps the attempts and clears the retry time', () async {
      await repo.markRetry(id, 'timeout', now);

      await repo.markFailed(id, '404');

      await expectRow(status: AssetJobStatus.failed, attempts: 1, lastError: '404');
      expect(await repo.countFailed(), 1);
      expect(await repo.countAllPending(), 0);
    });

    test('resetForNewSize re-queues the path with the new size and URL and zeroed bookkeeping', () async {
      await repo.markRetry(id, 'timeout', now);
      await repo.markFailed(id, '404');

      await repo.resetForNewSize('/a.jpg', size: 'w780', sourceUrl: 'https://image.tmdb.org/t/p/w780/a.jpg');

      await expectRow(status: AssetJobStatus.pending, attempts: 0);
      final row = (await repo.getByDestPaths(['/a.jpg']))['/a.jpg']!;
      expect(row.id, id, reason: 'the same row, not a new one');
      expect(row.size, 'w780');
      expect(row.sourceUrl, 'https://image.tmdb.org/t/p/w780/a.jpg');
    });

    test('resetForNewSize is a no-op for an unknown path', () async {
      await repo.resetForNewSize('/missing.jpg', size: 'w780', sourceUrl: 'x');

      expect(await repo.getByDestPaths(['/missing.jpg']), isEmpty);
      await expectRow(status: AssetJobStatus.pending, attempts: 0);
    });
  });

  group('resetFailed', () {
    setUp(() async {
      await repo.insertIgnore([
        job('/m1-a.jpg', mediaType: ItemType.movie, itemId: 1),
        job('/m1-b.jpg', mediaType: ItemType.movie, itemId: 1),
        job('/s1-a.jpg', mediaType: ItemType.show, itemId: 1),
        job('/m2-a.jpg', mediaType: ItemType.movie, itemId: 2),
      ], createdAt: createdAt);
      final rows = await repo.getByDestPaths(['/m1-a.jpg', '/s1-a.jpg', '/m2-a.jpg']);
      for (final row in rows.values) {
        await repo.markRetry(row.id, 'timeout', now);
        await repo.markFailed(row.id, 'gave up');
      }
    });

    test('scoped to one item re-queues that item\'s failed rows only', () async {
      await repo.resetFailed(item: const MediaKey.movie(1));

      final rows = await repo.getByDestPaths(['/m1-a.jpg', '/m1-b.jpg', '/s1-a.jpg', '/m2-a.jpg']);
      expect(rows['/m1-a.jpg']!.status, AssetJobStatus.pending);
      expect(rows['/m1-a.jpg']!.attempts, 0);
      expect(rows['/m1-a.jpg']!.nextRetryAt, isNull);
      expect(rows['/m1-a.jpg']!.lastError, isNull);
      expect(rows['/m1-b.jpg']!.status, AssetJobStatus.pending, reason: 'was never failed');
      expect(rows['/s1-a.jpg']!.status, AssetJobStatus.failed, reason: 'the show with the same id is another item');
      expect(rows['/m2-a.jpg']!.status, AssetJobStatus.failed);
      expect(await repo.countFailed(), 2);
    });

    test('unscoped re-queues every failed row', () async {
      await repo.resetFailed();

      expect(await repo.countFailed(), 0);
      expect(await repo.countAllPending(), 4);
      expect(await repo.countPending(now: now), 4, reason: 'the retry time is cleared too');
    });
  });

  group('deletes', () {
    test('deleteByDestPath removes just that row', () async {
      await repo.insertIgnore([job('/a.jpg'), job('/b.jpg')], createdAt: createdAt);

      await repo.deleteByDestPath('/a.jpg');

      expect((await repo.getByDestPaths(['/a.jpg', '/b.jpg'])).keys, ['/b.jpg']);
    });

    test('deleteForItem removes every row of one movie or show, not the other type with the same id', () async {
      await repo.insertIgnore([
        job('/m5-poster.jpg', mediaType: ItemType.movie, itemId: 5),
        job('/m5-backdrop.jpg', mediaType: ItemType.movie, itemId: 5, kind: 'backdrop'),
        job('/s5-poster.jpg', mediaType: ItemType.show, itemId: 5),
        job('/m6-poster.jpg', mediaType: ItemType.movie, itemId: 6),
      ], createdAt: createdAt);

      await repo.deleteForItem(ItemType.movie, 5);

      final left = await repo.getByDestPaths(['/m5-poster.jpg', '/m5-backdrop.jpg', '/s5-poster.jpg', '/m6-poster.jpg']);
      expect(left.keys, unorderedEquals(['/s5-poster.jpg', '/m6-poster.jpg']));
    });
  });

  group('counts', () {
    test('countPending, countAllPending and countFailed read their own status', () async {
      await repo.insertIgnore([job('/a.jpg'), job('/b.jpg'), job('/c.jpg'), job('/d.jpg')], createdAt: createdAt);
      final rows = await repo.getByDestPaths(['/a.jpg', '/b.jpg', '/c.jpg']);
      await repo.markDone(rows['/a.jpg']!.id);
      await repo.markFailed(rows['/b.jpg']!.id, 'gone');
      await repo.markRetry(rows['/c.jpg']!.id, 'timeout', now.add(const Duration(hours: 1)));

      expect(await repo.countPending(now: now), 1);
      expect(await repo.countAllPending(), 2);
      expect(await repo.countFailed(), 1);
    });

    test('are 0 for an empty table', () async {
      expect(await repo.countPending(now: now), 0);
      expect(await repo.countAllPending(), 0);
      expect(await repo.countFailed(), 0);
    });

    test('watchPendingCount emits the pending count after every write', () async {
      final emissions = <int>[];
      final subscription = repo.watchPendingCount().listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await repo.insertIgnore([job('/a.jpg'), job('/b.jpg')], createdAt: createdAt);
      await pumpEventQueue();
      final a = (await repo.getByDestPaths(['/a.jpg']))['/a.jpg']!;
      await repo.markDone(a.id);
      await pumpEventQueue();

      expect(emissions, [0, 2, 1]);
    });
  });

  test('donePaths lists the downloaded files only', () async {
    await repo.insertIgnore([job('/a.jpg'), job('/b.jpg'), job('/c.jpg')], createdAt: createdAt);
    final rows = await repo.getByDestPaths(['/a.jpg', '/b.jpg']);
    await repo.markDone(rows['/a.jpg']!.id);
    await repo.markFailed(rows['/b.jpg']!.id, 'gone');

    expect(await repo.donePaths(), ['/a.jpg']);
  });
}
