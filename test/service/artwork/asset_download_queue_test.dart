import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/asset_job_status.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/service/artwork/artwork_manifest.dart';

import 'artwork_test_support.dart';

void main() {
  final harness = ArtworkTestHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  NewAssetJob job(String destPath, {String size = 'w342', String url = 'https://image.tmdb.org/t/p/w342/x.jpg'}) =>
      NewAssetJob(mediaType: ItemType.movie, itemId: 1, kind: 'poster', size: size, sourceUrl: url, destPath: destPath);

  test('enqueue inserts pending rows once; a second enqueue of the same paths is a no-op', () async {
    final queue = harness.queue();

    final first = await queue.enqueue([job('video/movies/1/poster.jpg'), job('video/movies/1/backdrop.jpg')]);
    final again = await queue.enqueue([job('video/movies/1/poster.jpg'), job('video/movies/1/backdrop.jpg')]);

    expect(first, 2);
    expect(again, 2);
    final rows = await harness.rows();
    expect(rows.map((row) => row.destPath), ['video/movies/1/poster.jpg', 'video/movies/1/backdrop.jpg']);
    expect(rows.map((row) => row.status).toSet(), {AssetJobStatus.pending});
    expect(rows.map((row) => row.id), [1, 2]);
  });

  test('a file already on disk with no row is recorded done, not downloaded again', () async {
    await harness.writeFile('video/movies/1/poster.jpg');

    final pending = await harness.queue().enqueue([job('video/movies/1/poster.jpg'), job('video/movies/1/backdrop.jpg')]);

    expect(pending, 1);
    final rows = await harness.rows();
    expect(rows.singleWhere((row) => row.destPath == 'video/movies/1/poster.jpg').status, AssetJobStatus.done);
    expect(rows.singleWhere((row) => row.destPath == 'video/movies/1/backdrop.jpg').status, AssetJobStatus.pending);
  });

  test('a new size re-queues a done row with the new URL and a clean attempt count', () async {
    final queue = harness.queue();
    await queue.enqueue([job('video/movies/1/poster.jpg')]);
    await harness.repo.markDone(1);
    await harness.repo.markRetry(1, 'x', DateTime.now());

    final pending = await queue.enqueue([job('video/movies/1/poster.jpg', size: 'w500', url: 'https://image.tmdb.org/t/p/w500/x.jpg')]);

    expect(pending, 1);
    final row = (await harness.rows()).single;
    expect(row.status, AssetJobStatus.pending);
    expect(row.size, 'w500');
    expect(row.sourceUrl, 'https://image.tmdb.org/t/p/w500/x.jpg');
    expect(row.attempts, 0);
    expect(row.nextRetryAt, isNull);
    expect(row.lastError, isNull);
  });

  test('a failed row stays failed unless resetFailed is asked for', () async {
    final queue = harness.queue();
    await queue.enqueue([job('video/movies/1/poster.jpg')]);
    await harness.repo.markFailed(1, 'notFound');

    expect(await queue.enqueue([job('video/movies/1/poster.jpg')]), 0);
    expect((await harness.rows()).single.status, AssetJobStatus.failed);

    expect(await queue.enqueue([job('video/movies/1/poster.jpg')], resetFailed: true), 1);
    final row = (await harness.rows()).single;
    expect(row.status, AssetJobStatus.pending);
    expect(row.attempts, 0);
    expect(row.lastError, isNull);
  });

  test('a done row stays done and a pending row keeps its attempts', () async {
    final queue = harness.queue();
    await queue.enqueue([job('video/movies/1/poster.jpg'), job('video/movies/1/backdrop.jpg')]);
    await harness.repo.markDone(1);
    await harness.repo.markRetry(2, 'blip', DateTime.now().subtract(const Duration(minutes: 1)));

    final pending = await queue.enqueue([job('video/movies/1/poster.jpg'), job('video/movies/1/backdrop.jpg')], resetFailed: true);

    expect(pending, 1);
    final rows = await harness.rows();
    expect(rows[0].status, AssetJobStatus.done);
    expect(rows[1].status, AssetJobStatus.pending);
    expect(rows[1].attempts, 1);
    expect(rows[1].lastError, 'blip');
  });

  test('enqueueManifest reads the quality once and queues every wanted file', () async {
    final manifest = ArtworkManifest.show(
      tmdbId: 3,
      posterPath: '/p.jpg',
      backdropPath: '/b.jpg',
      seasonPosterPaths: {1: '/s1.jpg'},
      stillPaths: {(1, 1): '/e.jpg'},
      castProfilePaths: {'/f.jpg'},
    );

    final pending = await harness.queue(quality: PosterQualityOption.highest).enqueueManifest(manifest);

    expect(pending, 5);
    final rows = await harness.rows();
    expect(rows.map((row) => row.destPath), [
      'video/shows/3/poster.jpg',
      'video/shows/3/backdrop.jpg',
      'video/shows/3/seasons/1/poster.jpg',
      'video/shows/3/episodes/1-1/still.jpg',
      'video/shows/3/cast/f.jpg',
    ]);
    expect(rows.map((row) => row.size), ['w780', 'w1280', 'w780', 'original', 'w185']);
    expect(rows.map((row) => row.mediaType).toSet(), {ItemType.show});
    expect(rows.map((row) => row.itemId).toSet(), {3});
  });
}
