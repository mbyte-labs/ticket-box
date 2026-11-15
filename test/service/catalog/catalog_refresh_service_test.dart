import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/catalog/catalog_refresh_queries.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/job_state/job_constants.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/catalog/catalog_refresh_service.dart';
import 'package:ticketbox/service/catalog/catalog_writer.dart';
import 'package:ticketbox/service/catalog/library_backfill_service.dart';
import 'package:ticketbox/service/catalog/outage_breaker.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/library/show_state_service.dart';
import 'package:ticketbox/service/movie/movie_service.dart';
import 'package:ticketbox/service/show/show_service.dart';

import 'catalog_test_support.dart';
import 'snapshot_fixtures.dart';

/// The scheduler's selections over `fetched_at`, the tick's circuit breaker and job row, and the
/// backfill of rows without a snapshot.
void main() {
  late DatabaseConnectionManager db;
  late LibraryService library;
  final requests = <Request>[];
  late Future<Response> Function(Request request) answer;

  // The services read the device clock, so the seeds are relative to it.
  final now = nowToTheSecond();
  final old = now.subtract(const Duration(days: 8));
  final older = now.subtract(const Duration(days: 9));
  final fresh = now.subtract(const Duration(hours: 1));
  final archiveOld = now.subtract(const Duration(days: 91));

  setUp(() {
    requests.clear();
    answer = snapshotAnswers(movie: rawMovie(), showRoot: showRootBody());
    TmdbHttpClient.forTesting(
      MockClient((request) {
        requests.add(request);
        return answer(request);
      }),
    );
    db = openTestDatabase(withPreferences: true);
    library = LibraryService(artwork: noArtwork);
  });

  tearDown(() async {
    TmdbHttpClient.resetForTesting();
    await closeTestDatabase(db);
  });

  Future<void> watchlist(ItemType type, int id) => WatchlistRepo().insert(WatchlistEntity.build(type: type, tmdbId: id, listedAt: now));

  Future<void> favorite(ItemType type, int id) => FavoriteRepo().insert(FavoriteEntity.build(type: type, tmdbId: id, favoritedAt: now));

  group('CatalogRefreshQueries', () {
    late CatalogRefreshQueries queries;
    final cutoff = now.subtract(CatalogRefreshService.activeInterval);
    final archiveCutoff = now.subtract(CatalogRefreshService.archiveInterval);

    setUp(() => queries = CatalogRefreshQueries());

    Future<void> seedMovies() async {
      await seedMovie(1, fetchedAt: older);
      await watchlist(ItemType.movie, 1);
      await seedMovie(2, fetchedAt: old);
      await favorite(ItemType.movie, 2);
      await seedMovie(3, fetchedAt: archiveOld);
      await playMovie(3);
      await seedMovie(4, fetchedAt: fresh);
      await watchlist(ItemType.movie, 4);
      await seedMovie(5);
      await watchlist(ItemType.movie, 5);
      await seedMovie(6, fetchedAt: old);
      await playMovie(6);
    }

    Future<void> seedShows() async {
      await seedShow(11, fetchedAt: older);
      await seedState(11, ShowWatchStatus.watching);
      await seedShow(12, fetchedAt: old, status: 'returningSeries');
      await seedState(12, ShowWatchStatus.watched);
      await seedShow(13, fetchedAt: archiveOld, status: 'ended');
      await seedState(13, ShowWatchStatus.watched);
      await seedShow(14, fetchedAt: old, status: 'ended');
      await watchlist(ItemType.show, 14);
      await seedShow(15, fetchedAt: old, status: 'returningSeries');
      await seedState(15, ShowWatchStatus.dropped);
      await seedShow(
        16,
        fetchedAt: now.subtract(const Duration(days: 3)),
        status: 'returningSeries',
        nextEpisodeAirDate: ymd(now.toLocal()),
      );
      await seedState(16, ShowWatchStatus.watched);
      await seedShow(17, fetchedAt: fresh, status: 'returningSeries', nextEpisodeAirDate: ymd(now.toLocal().add(const Duration(days: 1))));
      await seedState(17, ShowWatchStatus.watching);
      await seedShow(
        18,
        fetchedAt: now.subtract(const Duration(days: 3)),
        status: 'returningSeries',
        nextEpisodeAirDate: ymd(now.toLocal().subtract(const Duration(days: 5))),
      );
      await seedState(18, ShowWatchStatus.watching);
      await seedShow(19, fetchedAt: archiveOld, status: 'canceled');
      await seedState(19, ShowWatchStatus.watching);
    }

    test('active movies: on the watchlist or favorites and older than the cutoff', () async {
      await seedMovies();

      expect(await queries.activeMovieIds(cutoff), [1, 2]);
    });

    test('active shows: listed, or followed and not concluded (NULL status counts), plus the aired announced episode', () async {
      await seedShows();

      final ids = await queries.activeShowIds(cutoff, ymd(now.toLocal()));

      expect(ids.toSet(), {11, 12, 14, 16});
      expect(ids.first, 11, reason: 'oldest snapshot first');
    });

    test('archive movies: watched, on no list, older than the archive cutoff', () async {
      await seedMovies();

      expect(await queries.archiveMovieIds(archiveCutoff), [3]);
    });

    test('archive shows: followed, ended or canceled, on no list, older than the archive cutoff', () async {
      await seedShows();

      expect((await queries.archiveShowIds(archiveCutoff)).toSet(), {13, 19});
    });

    test('the active and archive classes are disjoint', () async {
      await seedMovies();
      await seedShows();
      await favorite(ItemType.show, 13);

      final activeMovies = await queries.activeMovieIds(now);
      final archiveMovies = await queries.archiveMovieIds(now);
      final activeShows = await queries.activeShowIds(now, ymd(now.toLocal()));
      final archiveShows = await queries.archiveShowIds(now);

      expect(activeMovies.toSet().intersection(archiveMovies.toSet()), isEmpty);
      expect(activeShows.toSet().intersection(archiveShows.toSet()), isEmpty);
      expect(activeShows, contains(13), reason: 'a favorite ended show takes the active cadence');
    });

    test('region mismatch: rows pruned to another region than the configured one', () async {
      await seedMovie(1, fetchedAt: old, region: 'US');
      await seedMovie(2, fetchedAt: old, region: 'GB');
      await seedMovie(3, fetchedAt: old);
      await seedMovie(4, region: 'GB');
      await seedShow(1, fetchedAt: old, region: 'US');
      await seedShow(2, fetchedAt: old);

      expect((await queries.movieIdsWithOtherRegion('US')).toSet(), {2, 3});
      expect(await queries.showIdsWithOtherRegion('US'), [2]);
    });

    test('with no region configured, rows never pruned to a region are not re-selected', () async {
      await seedMovie(1, fetchedAt: old, region: 'US');
      await seedMovie(3, fetchedAt: old);
      await seedShow(2, fetchedAt: old);

      expect(await queries.movieIdsWithOtherRegion(null), [1]);
      expect(await queries.showIdsWithOtherRegion(null), isEmpty);
    });
  });

  group('CatalogRefreshService.tick', () {
    late CatalogRefreshService service;

    setUp(() {
      service = CatalogRefreshService(
        movies: MovieService(artwork: noArtwork),
        shows: ShowService(artwork: noArtwork),
        backfill: LibraryBackfillService(library: library),
        state: ShowStateService(),
        library: library,
        artwork: noArtwork,
      );
    });

    Future<void> seedStaleMovies(int count) async {
      for (var id = 1; id <= count; id++) {
        await seedMovie(id, fetchedAt: old, region: 'US');
        await watchlist(ItemType.movie, id);
      }
    }

    test('trips the breaker after three consecutive network failures; the state sweep still runs', () async {
      await seedStaleMovies(5);
      await seedShow(10, fetchedAt: fresh, region: 'US');
      await seedEpisodeAndPlay(10);
      answer = (_) => throw ClientException('offline');

      await service.tick();

      expect(distinctPaths(requests), hasLength(3), reason: 'the first chunk of three failed; the rest was abandoned');
      final job = await JobStateRepo().get(CATALOG_REFRESH_JOB_ID);
      expect(job.state, JobState.failed);
      expect(job.errorCode, JobErrorCode.networkError);
      expect((await ShowStateRepo().get(10))?.status, ShowWatchStatus.watching);
    });

    test('a 404 does not count against the breaker and stamps fetched_at', () async {
      await seedStaleMovies(4);
      answer = snapshotAnswers();

      await service.tick();

      expect(requests, hasLength(4));
      final job = await JobStateRepo().get(CATALOG_REFRESH_JOB_ID);
      expect(job.state, JobState.finished);
      expect(job.errorCode, JobErrorCode.none);
      for (final movie in await MovieRepo().getAll()) {
        expect(movie.fetchedAt!.toUtc().isAfter(fresh), isTrue);
        expect(await SnapshotDocumentRepo().getMovie(movie.tmdbId), isNull, reason: 'nothing was written for a gone item');
      }
    });

    test('the job row goes running, then finished', () async {
      await seedStaleMovies(1);
      JobState? seen;
      answer = (request) async {
        seen = (await JobStateRepo().get(CATALOG_REFRESH_JOB_ID)).state;
        return jsonResponse(rawMovie()..['id'] = 1);
      };

      await service.tick();

      expect(seen, JobState.running);
      final job = await JobStateRepo().get(CATALOG_REFRESH_JOB_ID);
      expect(job.state, JobState.finished);
      expect(job.errorCode, JobErrorCode.none);
      expect(job.finishedAt.isBefore(job.startedAt), isFalse);
      expect((await MovieRepo().get(1))?.title, 'Fight Club');
      expect(await SnapshotDocumentRepo().getMovie(1), isNotNull);
    });

    test('a second tick while one runs joins it', () async {
      await seedStaleMovies(1);
      final gate = Completer<void>();
      answer = (request) async {
        await gate.future;
        return jsonResponse(rawMovie());
      };

      final first = service.tick();
      await pumpEventQueue();
      final second = service.tick();
      expect(identical(first, second), isTrue);
      gate.complete();
      await Future.wait([first, second]);

      expect(requests, hasLength(1));
      expect((await JobStateRepo().get(CATALOG_REFRESH_JOB_ID)).state, JobState.finished);
    });

    test('with nothing to refresh the tick finishes clean', () async {
      await service.tick();

      expect(requests, isEmpty);
      expect((await JobStateRepo().get(CATALOG_REFRESH_JOB_ID)).state, JobState.finished);
    });
  });

  group('LibraryBackfillService.run', () {
    late LibraryBackfillService backfill;

    setUp(() => backfill = LibraryBackfillService(library: library));

    test('fetches every row with no snapshot', () async {
      await seedMovie(1);
      await seedMovie(2);
      await seedShow(1399);
      await seedMovie(3, fetchedAt: fresh);
      expect(await backfill.hasPending(), isTrue);

      final fetched = await backfill.run(breaker: OutageBreaker());

      expect(fetched, 3);
      expect(requests.map((r) => r.url.path).toSet(), {'/3/movie/1', '/3/movie/2', '/3/tv/1399'});
      expect(requests.where((r) => r.url.path == '/3/tv/1399'), hasLength(2), reason: 'the root, then the seasons');
      expect(await MovieRepo().getIdsWithoutSnapshot(), isEmpty);
      expect(await ShowRepo().getIdsWithoutSnapshot(), isEmpty);
      expect(await SnapshotDocumentRepo().getSeason(1399, 2), isNotNull);
      expect(await backfill.pendingCount(), 0);
    });

    test('stops at the breaker', () async {
      for (var id = 1; id <= 5; id++) {
        await seedMovie(id);
      }
      answer = (_) => throw ClientException('offline');
      final breaker = OutageBreaker();

      final fetched = await backfill.run(breaker: breaker);

      expect(fetched, 0);
      expect(distinctPaths(requests), hasLength(3));
      expect(breaker.tripped, isTrue);
      expect(breaker.code, JobErrorCode.networkError);
      expect(await backfill.pendingCount(), 5);
    });

    test('stamps items TMDB no longer has, without a document', () async {
      await seedMovie(1);
      answer = snapshotAnswers();

      final fetched = await backfill.run(breaker: OutageBreaker(), now: now);

      expect(fetched, 0);
      expect((await MovieRepo().get(1))?.fetchedAt?.toUtc(), now);
      expect(await SnapshotDocumentRepo().getMovie(1), isNull);
      expect(await backfill.pendingCount(), 0);
    });

    test('fetches the stub seasons of a show that already has its root', () async {
      final pruned = SnapshotPruner.showRoot(rawShow(), region: null);
      await CatalogWriter().writeShow(pruned.root, const {}, now: old, region: null);

      final fetched = await backfill.run(breaker: OutageBreaker());

      expect(fetched, 1);
      expect(requests, hasLength(1));
      expect(requests.single.url.queryParameters['append_to_response'], contains('season/1,season/2'));
      expect(await SeasonRepo().getUnfetchedSeasonNumbers(1399), isEmpty);
    });
  });
}

/// Two aired episodes of [showId], one played, and no state row — what the state sweep turns into `watching`.
Future<void> seedEpisodeAndPlay(int showId) async {
  await seedEpisode(showId, 1, 1, airDate: '2026-01-01');
  await seedEpisode(showId, 1, 2, airDate: '2026-01-08');
  await playEpisode(showId, 1, 1);
}
