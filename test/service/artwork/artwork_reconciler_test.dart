import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/asset_job_status.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/service/artwork/artwork_manifest.dart';

import 'artwork_test_support.dart';

void main() {
  final harness = ArtworkTestHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  const show1 = [
    'video/shows/1/poster.jpg',
    'video/shows/1/backdrop.jpg',
    'video/shows/1/seasons/1/poster.jpg',
    'video/shows/1/seasons/2/poster.jpg',
    'video/shows/1/episodes/1-1/still.jpg',
    'video/shows/1/episodes/1-2/still.jpg',
    'video/shows/1/episodes/2-1/still.jpg',
  ];
  const stray = 'video/shows/1/cast/stray.jpg';
  const others = ['video/shows/2/poster.jpg', 'video/movies/1/poster.jpg'];

  final before = ArtworkManifest.show(
    tmdbId: 1,
    posterPath: '/p.jpg',
    backdropPath: '/b.jpg',
    seasonPosterPaths: {1: '/s1.jpg', 2: '/s2.jpg'},
    stillPaths: {(1, 1): '/e11.jpg', (1, 2): '/e12.jpg', (2, 1): '/e21.jpg'},
    castProfilePaths: {'/stray.jpg'},
  );

  /// Season 1 and 2 as before, minus still 1-2, plus a new still 2-2; no cast.
  final after = ArtworkManifest.show(
    tmdbId: 1,
    posterPath: '/p.jpg',
    backdropPath: '/b.jpg',
    seasonPosterPaths: {1: '/s1.jpg', 2: '/s2.jpg'},
    stillPaths: {(1, 1): '/e11.jpg', (2, 1): '/e21.jpg', (2, 2): '/e22.jpg'},
  );

  Future<void> seed() async {
    for (final path in [...show1, stray, ...others]) {
      await harness.writeFile(path);
    }
    await harness.index.load(harness.paths);
    // Rows for everything on disk (done, the files exist) plus the other items'.
    await harness.queue().enqueueManifest(before);
    await harness.queue().enqueue([
      const NewAssetJob(
        mediaType: ItemType.show,
        itemId: 2,
        kind: 'poster',
        size: 'w342',
        sourceUrl: 'u',
        destPath: 'video/shows/2/poster.jpg',
      ),
      const NewAssetJob(
        mediaType: ItemType.movie,
        itemId: 1,
        kind: 'poster',
        size: 'w342',
        sourceUrl: 'u',
        destPath: 'video/movies/1/poster.jpg',
      ),
    ]);
  }

  test('reconcile deletes exactly the files the manifest no longer names and queues the new one', () async {
    await seed();
    expect((await harness.rows()).map((row) => row.status).toSet(), {AssetJobStatus.done});

    final result = await harness.reconciler().reconcile(after);

    expect(result, (deleted: 2, enqueued: 1));
    expect(await harness.filesOnDisk(), [
      'video/movies/1/poster.jpg',
      'video/shows/1/backdrop.jpg',
      'video/shows/1/episodes/1-1/still.jpg',
      'video/shows/1/episodes/2-1/still.jpg',
      'video/shows/1/poster.jpg',
      'video/shows/1/seasons/1/poster.jpg',
      'video/shows/1/seasons/2/poster.jpg',
      'video/shows/2/poster.jpg',
    ]);
    expect(await harness.file('video/shows/1/episodes/1-2/still.jpg').parent.exists(), isFalse, reason: 'empty directories are pruned');
    expect(await harness.file(stray).parent.exists(), isFalse);
    expect(harness.index.contains('video/shows/1/episodes/1-2/still.jpg'), isFalse);
    expect(harness.index.contains(stray), isFalse);
    expect(harness.index.contains('video/shows/1/seasons/2/poster.jpg'), isTrue);

    final rows = await harness.repo.getByDestPaths([...show1, stray, ...others, 'video/shows/1/episodes/2-2/still.jpg']);
    expect(rows.containsKey('video/shows/1/episodes/1-2/still.jpg'), isFalse);
    expect(rows.containsKey(stray), isFalse);
    expect(rows['video/shows/1/episodes/2-2/still.jpg']!.status, AssetJobStatus.pending);
    expect(rows.length, show1.length - 1 + others.length + 1);
    expect(rows.values.where((row) => row.destPath != 'video/shows/1/episodes/2-2/still.jpg').map((row) => row.status).toSet(), {
      AssetJobStatus.done,
    });
  });

  test('reconcile gives failed rows another go by default, and not when asked not to', () async {
    await seed();
    final poster = (await harness.repo.getByDestPaths(['video/shows/1/poster.jpg'])).values.single;
    await harness.repo.markFailed(poster.id, 'notFound');

    await harness.reconciler().reconcile(after, resetFailed: false);
    expect((await harness.repo.getByDestPaths(['video/shows/1/poster.jpg'])).values.single.status, AssetJobStatus.failed);

    await harness.reconciler().reconcile(after);
    expect((await harness.repo.getByDestPaths(['video/shows/1/poster.jpg'])).values.single.status, AssetJobStatus.pending);
  });

  test('reconciling an item with nothing on disk only queues', () async {
    final result = await harness.reconciler().reconcile(after);

    expect(result, (deleted: 0, enqueued: 7));
    expect(await harness.filesOnDisk(), isEmpty);
  });

  test('deleteItemDirectory removes one item and leaves the others alone', () async {
    await seed();

    await harness.reconciler().deleteItemDirectory(const MediaKey.show(1));

    expect(await harness.filesOnDisk(), ['video/movies/1/poster.jpg', 'video/shows/2/poster.jpg']);
    expect(await harness.file('video/shows/1/poster.jpg').parent.exists(), isFalse);
    final rows = await harness.rows();
    expect(rows.map((row) => row.destPath), ['video/shows/2/poster.jpg', 'video/movies/1/poster.jpg']);
    expect(harness.index.contains('video/shows/1/poster.jpg'), isFalse);
    expect(harness.index.contains('video/shows/2/poster.jpg'), isTrue);
    expect(harness.index.contains('video/movies/1/poster.jpg'), isTrue);
  });

  test('deleteItemDirectory of a season key resolves to its show', () async {
    await seed();

    await harness.reconciler().deleteItemDirectory(const MediaKey.season(1, 2));

    expect(await harness.filesOnDisk(), ['video/movies/1/poster.jpg', 'video/shows/2/poster.jpg']);
  });
}
