import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/http/image_download_client.dart';
import 'package:ticketbox/common/model/asset_job_status.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/database/sql_store/job_state/job_constants.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/service/artwork/artwork_index.dart';
import 'package:ticketbox/service/artwork/artwork_manifest.dart';
import 'package:ticketbox/service/artwork/asset_download_worker.dart';

import 'artwork_test_support.dart';

/// Runs in real time: a body read goes through the stall guard in `TimeoutClient`, which never
/// completes under fake time. The tests that hit the client's one retry pay its half-second
/// back-off once (the four rows of a chunk retry in parallel).
void main() {
  final harness = ArtworkTestHarness();

  setUp(() => harness.setUp());
  tearDown(() => harness.tearDown());

  String castUrl(int i) => 'https://image.tmdb.org/t/p/w185/f$i.jpg';
  String castPath(int i) => 'video/movies/1/cast/f$i.jpg';

  /// [count] cast rows of movie 1, ids 1..count.
  Future<void> enqueueCast(int count) => harness.queue().enqueue([
    for (var i = 0; i < count; i++)
      NewAssetJob(mediaType: ItemType.movie, itemId: 1, kind: 'cast', size: 'w185', sourceUrl: castUrl(i), destPath: castPath(i)),
  ]);

  final movie = ArtworkManifest.movie(tmdbId: 1, posterPath: '/p.jpg', backdropPath: '/b.jpg');
  const posterUrl = 'https://image.tmdb.org/t/p/w342/p.jpg';
  const posterPath = 'video/movies/1/poster.jpg';
  const backdropPath = 'video/movies/1/backdrop.jpg';

  Matcher within(Duration expected, {Duration tolerance = const Duration(seconds: 10)}) {
    final now = DateTime.now();
    return predicate<DateTime?>(
      (at) => at != null && at.isAfter(now.add(expected - tolerance)) && at.isBefore(now.add(expected + tolerance)),
      'within $tolerance of now + $expected',
    );
  }

  test('happy path: bytes on disk, no .part left, rows done, index updated, arrivals emitted, job finished', () async {
    await harness.queue().enqueueManifest(movie);
    final arrivals = <ArtworkArrival>[];
    final subscription = harness.index.arrivals.listen(arrivals.add);

    await harness.worker().drain();
    await Future<void>.delayed(Duration.zero);

    expect(await harness.filesOnDisk(), [backdropPath, posterPath]);
    expect(await harness.file(posterPath).readAsBytes(), ArtworkTestHarness.jpegBytes);
    expect(harness.requests.map((r) => r.url.toString()), [posterUrl, 'https://image.tmdb.org/t/p/w1280/b.jpg']);
    expect(harness.requests.map((r) => r.headers['Accept']).toSet(), {'image/*'});
    final rows = await harness.rows();
    expect(rows.map((row) => row.status).toSet(), {AssetJobStatus.done});
    expect(rows.map((row) => row.lastError).toSet(), {null});
    expect(harness.index.contains(posterPath), isTrue);
    expect(harness.index.contains(backdropPath), isTrue);
    expect(arrivals.map((a) => (a.relativePath, a.replaced)), [(posterPath, false), (backdropPath, false)]);
    final job = await harness.jobStates.get(ARTWORK_DOWNLOAD_JOB_ID);
    expect(job.state, JobState.finished);
    expect(job.errorCode, JobErrorCode.none);
    expect(job.userMessage, isNull);
    await subscription.cancel();
  });

  test('a file in the browse cache is promoted with zero requests', () async {
    await harness.queue().enqueueManifest(ArtworkManifest.movie(tmdbId: 1, posterPath: '/p.jpg'));
    const cachedBytes = [9, 9, 9, 9];
    await harness.writeCached(posterUrl, cachedBytes);

    await harness.worker().drain();

    expect(harness.requests, isEmpty);
    expect(await harness.file(posterPath).readAsBytes(), cachedBytes);
    expect((await harness.rows()).single.status, AssetJobStatus.done);
    expect(harness.index.contains(posterPath), isTrue);
    expect(await harness.filesOnDisk(), [posterPath]);
  });

  test('a download over an existing file arrives as replaced', () async {
    await harness.writeFile(posterPath, [1, 1, 1]);
    final queue = harness.queue();
    await queue.enqueueManifest(ArtworkManifest.movie(tmdbId: 1, posterPath: '/p.jpg'));
    await harness.repo.resetForNewSize(posterPath, size: 'w342', sourceUrl: posterUrl);
    final arrivals = <ArtworkArrival>[];
    final subscription = harness.index.arrivals.listen(arrivals.add);

    await harness.worker().drain();
    await Future<void>.delayed(Duration.zero);

    expect(await harness.file(posterPath).readAsBytes(), ArtworkTestHarness.jpegBytes);
    expect(arrivals.map((a) => (a.relativePath, a.replaced)), [(posterPath, true)]);
    await subscription.cancel();
  });

  test('a 404 fails the row for good, marks the path missing and the drain goes on', () async {
    harness.handler = (request) async => request.url.path.endsWith('f0.jpg') ? ArtworkTestHarness.status(404) : ArtworkTestHarness.jpeg();
    await enqueueCast(2);

    await harness.worker().drain();

    final rows = await harness.rows();
    expect(rows[0].status, AssetJobStatus.failed);
    expect(rows[0].lastError, 'notFound');
    expect(rows[1].status, AssetJobStatus.done);
    expect(harness.index.isMissing(castPath(0)), isTrue);
    expect(harness.index.contains(castPath(1)), isTrue);
    expect(await harness.filesOnDisk(), [castPath(1)]);
    expect((await harness.jobStates.get(ARTWORK_DOWNLOAD_JOB_ID)).errorCode, JobErrorCode.none);
  });

  test('a transport failure stops the drain: the chunk in flight is stamped, the rest untouched', () async {
    harness.handler = (request) async => throw ClientException('connection reset', request.url);
    await enqueueCast(8);

    await harness.worker().drain();

    expect(harness.requests.map((r) => r.url.path).toSet().length, AssetDownloadWorker.concurrency);
    final rows = await harness.rows();
    for (final row in rows.take(4)) {
      expect(row.status, AssetJobStatus.pending);
      expect(row.attempts, 1);
      expect(row.nextRetryAt, within(AssetDownloadWorker.unreachableRetryDelay));
      expect(row.lastError, startsWith('network'));
    }
    for (final row in rows.skip(4)) {
      expect(row.status, AssetJobStatus.pending);
      expect(row.attempts, 0);
      expect(row.nextRetryAt, isNull);
      expect(row.lastError, isNull);
    }
    final job = await harness.jobStates.get(ARTWORK_DOWNLOAD_JOB_ID);
    expect(job.state, JobState.failed);
    expect(job.errorCode, JobErrorCode.networkError);
    expect(job.userMessage, isNull);
    expect(await harness.filesOnDisk(), isEmpty);
  });

  test('a 5xx stops the drain the same way, as serviceDown', () async {
    harness.handler = (request) async => ArtworkTestHarness.status(503);
    await enqueueCast(6);

    await harness.worker().drain();

    expect(harness.requests.map((r) => r.url.path).toSet().length, 4);
    final rows = await harness.rows();
    expect(rows.take(4).map((row) => row.attempts).toSet(), {1});
    expect(rows.take(4).map((row) => row.lastError).toSet(), {'http 503'});
    expect(rows.skip(4).map((row) => row.attempts).toSet(), {0});
    expect((await harness.jobStates.get(ARTWORK_DOWNLOAD_JOB_ID)).errorCode, JobErrorCode.serviceDown);
  });

  test('a 429 stops the drain as rateLimited', () async {
    harness.handler = (request) async => ArtworkTestHarness.status(429);
    await enqueueCast(1);

    await harness.worker().drain();

    expect((await harness.rows()).single.lastError, 'rateLimited');
    expect((await harness.jobStates.get(ARTWORK_DOWNLOAD_JOB_ID)).errorCode, JobErrorCode.rateLimited);
  });

  test('a non-image body is a failure of the row: retried with a growing back-off', () async {
    harness.handler = (request) async => ArtworkTestHarness.html();
    await enqueueCast(1);
    final worker = harness.worker();

    await worker.drain();

    var row = (await harness.rows()).single;
    expect(row.status, AssetJobStatus.pending);
    expect(row.attempts, 1);
    expect(row.lastError, 'not an image: text/html');
    expect(row.nextRetryAt, within(const Duration(minutes: 1)));
    expect(await harness.filesOnDisk(), isEmpty);
    expect((await harness.jobStates.get(ARTWORK_DOWNLOAD_JOB_ID)).errorCode, JobErrorCode.none);

    // Second attempt, once due: ten minutes.
    await harness.repo.markRetry(row.id, 'x', DateTime.now().subtract(const Duration(hours: 1)));
    await harness.repo.markRetry(row.id, 'x', DateTime.now().subtract(const Duration(hours: 1)));
    await harness.db.customUpdate('UPDATE asset_jobs SET attempts = 1');
    await worker.drain();

    row = (await harness.rows()).single;
    expect(row.attempts, 2);
    expect(row.nextRetryAt, within(const Duration(minutes: 10)));
  });

  test('a row failing for the fifth time is given up on', () async {
    harness.handler = (request) async => ArtworkTestHarness.html();
    await enqueueCast(1);
    for (var i = 0; i < AssetDownloadWorker.maxAttempts - 1; i++) {
      await harness.repo.markRetry(1, 'x', DateTime.now().subtract(const Duration(hours: 1)));
    }

    await harness.worker().drain();

    final row = (await harness.rows()).single;
    expect(row.status, AssetJobStatus.failed);
    expect(row.attempts, AssetDownloadWorker.maxAttempts - 1);
    expect(row.lastError, 'not an image: text/html');
  });

  test('ten own failures in a row trip the breaker and stop the drain', () async {
    harness.handler = (request) async => ArtworkTestHarness.html();
    await enqueueCast(16);

    await harness.worker().drain();

    // Three chunks of four: the breaker is checked after each chunk, so 12 are tried, 4 are not.
    expect(harness.requests.map((r) => r.url.path).toSet().length, 12);
    final rows = await harness.rows();
    expect(rows.take(12).map((row) => row.attempts).toSet(), {1});
    expect(rows.skip(12).map((row) => row.attempts).toSet(), {0});
    expect(rows.skip(12).map((row) => row.nextRetryAt).toSet(), {null});
    final job = await harness.jobStates.get(ARTWORK_DOWNLOAD_JOB_ID);
    expect(job.state, JobState.finished);
    expect(job.errorCode, JobErrorCode.none);
  });

  test('a body shorter than announced is retried and leaves no file', () async {
    ImageDownloadClient.forTesting(
      MockClient.streaming(
        (request, body) async => StreamedResponse(Stream.value([1, 2, 3]), 200, contentLength: 10, headers: {'content-type': 'image/jpeg'}),
      ),
    );
    await enqueueCast(1);

    await harness.worker().drain();

    final row = (await harness.rows()).single;
    expect(row.status, AssetJobStatus.pending);
    expect(row.attempts, 1);
    expect(row.lastError, 'truncated body: 3 of 10 bytes');
    expect(await harness.filesOnDisk(), isEmpty);
    expect(harness.index.contains(castPath(0)), isFalse);
  });

  test('an empty body is refused too', () async {
    harness.handler = (request) async => Response.bytes(const [], 200, headers: {'content-type': 'image/jpeg'});
    await enqueueCast(1);

    await harness.worker().drain();

    final row = (await harness.rows()).single;
    expect(row.status, AssetJobStatus.pending);
    expect(row.lastError, 'empty body');
    expect(await harness.filesOnDisk(), isEmpty);
  });

  test('crash resume: a pending row with a stray .part is swept and downloaded', () async {
    await enqueueCast(1);
    await harness.writeFile('${castPath(0)}.part', [0, 0, 0]);

    await harness.worker().drain();

    expect(await harness.filesOnDisk(), [castPath(0)]);
    expect(await harness.file(castPath(0)).readAsBytes(), ArtworkTestHarness.jpegBytes);
    expect((await harness.rows()).single.status, AssetJobStatus.done);
  });

  test('two concurrent drains are one run', () async {
    await enqueueCast(6);
    final worker = harness.worker();

    final first = worker.drain();
    final second = worker.drain();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);

    expect(harness.requests.length, 6);
    expect((await harness.rows()).map((row) => row.status).toSet(), {AssetJobStatus.done});

    // And a drain after the first completed is a new run.
    expect(identical(worker.drain(), first), isFalse);
  });

  test('nothing pending: the job row is not touched and nothing is requested', () async {
    await harness.worker().drain();
    await harness.worker().drainIfPending(delay: Duration.zero);

    expect(harness.requests, isEmpty);
    expect((await harness.jobStates.get(ARTWORK_DOWNLOAD_JOB_ID)).state, JobState.idle);
  });

  test('rows whose retry time has not come are left for later', () async {
    await enqueueCast(2);
    await harness.repo.markRetry(1, 'later', DateTime.now().add(const Duration(hours: 1)));

    await harness.worker().drainIfPending(delay: Duration.zero);

    final rows = await harness.rows();
    expect(rows[0].status, AssetJobStatus.pending);
    expect(rows[0].attempts, 1);
    expect(rows[1].status, AssetJobStatus.done);
    expect(harness.requests.length, 1);
  });
}
