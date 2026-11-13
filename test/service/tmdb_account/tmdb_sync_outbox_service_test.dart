import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/key_value_store/keys/tmdb_account_keys.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_outbox_service.dart';

import 'tmdb_test_support.dart';

/// What a flush does with each kind of answer from TMDB.
void main() {
  final harness = TmdbTestHarness();
  late TmdbSyncOutboxRepo repo;
  late Future<Response> Function(Request request) answer;

  setUp(() async {
    answer = TmdbTestHarness.ok;
    await harness.setUp(handler: (request) => answer(request));
    repo = TmdbSyncOutboxRepo();
  });

  tearDown(harness.tearDown);

  Future<void> seedAllKinds() async {
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(550), rating: 8);
    await repo.enqueue(operation: TmdbSyncOperation.unrate, key: const MediaKey.show(1396));
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.episode(1396, 1, 2), rating: 9);
    await repo.enqueue(operation: TmdbSyncOperation.watchlistAdd, key: const MediaKey.movie(550));
    await repo.enqueue(operation: TmdbSyncOperation.favoriteRemove, key: const MediaKey.show(1396));
  }

  test('nothing is sent while logged out', () async {
    await seedAllKinds();

    await TmdbSyncOutboxService().flush();

    expect(harness.requests, isEmpty);
    expect(await repo.count(), 5);
  });

  test('every kind of row becomes the matching TMDB call and is deleted once delivered', () async {
    await harness.logIn();
    await seedAllKinds();

    await TmdbSyncOutboxService().flush();

    expect(await repo.count(), 0);
    final calls = harness.requests.map((r) => '${r.method} ${r.url.path}').toList();
    expect(calls, [
      'POST /3/movie/550/rating',
      'DELETE /3/tv/1396/rating',
      'POST /3/tv/1396/season/1/episode/2/rating',
      'POST /3/account/42/watchlist',
      'POST /3/account/42/favorite',
    ]);
    expect(json.decode(harness.requests[0].body), {'value': 8.0});
    expect(json.decode(harness.requests[3].body), {'media_type': 'movie', 'media_id': 550, 'watchlist': true});
    expect(json.decode(harness.requests[4].body), {'media_type': 'tv', 'media_id': 1396, 'favorite': false});
    for (final request in harness.requests) {
      expect(request.url.queryParameters['session_id'], TmdbTestHarness.sessionId);
    }
  });

  test('a session 401 invalidates the session and keeps every row', () async {
    await harness.logIn();
    await seedAllKinds();
    answer = (request) async => Response('{"status_code":3}', 401);

    await TmdbSyncOutboxService().flush();

    expect(harness.session.isLoggedIn, isFalse);
    expect(harness.session.sessionInvalid, isTrue);
    expect(await repo.count(), 5);
  });

  test('when TMDB cannot be reached the flush stops and the rows wait', () async {
    await harness.logIn();
    await seedAllKinds();
    answer = (request) async => throw ClientException('no network');

    await TmdbSyncOutboxService().flush();

    expect(await repo.count(), 5);
    final rows = await repo.getAll();
    expect(rows.where((row) => row.attempts > 0).map((row) => row.lastError).toSet(), {'networkError'});
    // One chunk was attempted (plus the client's own retries), not the whole queue one by one.
    expect(rows.where((row) => row.attempts > 0).length, TmdbSyncOutboxService.chunkSize);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('a title TMDB no longer has is dropped so it cannot block the queue', () async {
    await harness.logIn();
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(1), rating: 5);
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(2), rating: 6);
    answer = (request) async => request.url.path.contains('/movie/1/') ? Response('{"status_code":34}', 404) : TmdbTestHarness.ok(request);

    await TmdbSyncOutboxService().flush();

    expect(await repo.count(), 0);
  });

  test('a row that keeps failing for a reason of its own is retried, then given up on', () async {
    await harness.logIn();
    await repo.enqueue(operation: TmdbSyncOperation.favoriteAdd, key: const MediaKey.movie(550));
    answer = (request) async => Response('{"status_code":5,"status_message":"Invalid parameters"}', 422);

    for (var attempt = 1; attempt < TmdbSyncOutboxService.maxAttempts; attempt++) {
      await TmdbSyncOutboxService().flush();
      expect((await repo.getAll()).single.attempts, attempt, reason: 'attempt $attempt');
    }
    await TmdbSyncOutboxService().flush();

    expect(await repo.count(), 0);
  });

  test('flushIfPending sends nothing when the queue is empty', () async {
    await harness.logIn();

    await TmdbSyncOutboxService().flushIfPending();

    expect(harness.requests, isEmpty);
  });

  test('rows queued while the toggles were on are delivered after a relaunch login', () async {
    await harness.logIn(enabledToggles: {TmdbAccountKeys.syncRatings});
    await repo.enqueue(operation: TmdbSyncOperation.rate, key: const MediaKey.movie(550), rating: 8);

    await TmdbSyncOutboxService().flushIfPending();

    expect(harness.requests.single.url.path, '/3/movie/550/rating');
    expect(await repo.count(), 0);
  });
}
