import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/pending_deletion/pending_deletion_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_entity.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/service/library/library_service.dart';

import '../catalog/catalog_test_support.dart';
import '../catalog/snapshot_fixtures.dart';

/// `LibraryService` is how items enter (one fetch on the first tracking action, nothing on a
/// tracked one) and leave (a deferred sweep once nothing references them) the library.
void main() {
  late DatabaseConnectionManager db;
  late LibraryService service;
  final requests = <Request>[];
  late Future<Response> Function(Request request) answer;

  final now = DateTime.utc(2026, 6, 15, 12);
  const movieId = 550;
  const showId = 1399;

  setUp(() {
    requests.clear();
    answer = snapshotAnswers(movie: rawMovie(), showRoot: showRootBody());
    // The API wrappers are singletons that capture the first client; routing through `answer`
    // keeps every test's handler in charge.
    TmdbHttpClient.forTesting(
      MockClient((request) {
        requests.add(request);
        return answer(request);
      }),
    );
    db = openTestDatabase(withPreferences: true);
    service = LibraryService(artwork: noArtwork);
  });

  tearDown(() async {
    TmdbHttpClient.resetForTesting();
    await closeTestDatabase(db);
  });

  group('ensureTracked', () {
    test('a tracked movie or show makes no request', () async {
      await seedMovie(movieId);
      await seedShow(showId);

      await service.ensureTracked(const MediaKey.movie(movieId));
      await service.ensureTracked(const MediaKey.episode(showId, 1, 1));

      expect(requests, isEmpty);
      expect(await service.isTracked(const MediaKey.season(showId, 2)), isTrue);
      expect(await service.isTracked(const MediaKey.show(movieId)), isFalse, reason: 'a movie id is not a show id');
    });

    test('an untracked movie fetches /3/movie/{id} once and writes the row and document', () async {
      await service.ensureTracked(const MediaKey.movie(movieId));

      expect(requests.map((r) => r.url.path), ['/3/movie/$movieId']);
      final row = await MovieRepo().get(movieId);
      expect(row?.title, 'Fight Club');
      expect(row?.fetchedAt, isNotNull);
      expect(await SnapshotDocumentRepo().getMovie(movieId), isNotNull);
      expect(await service.trackedKeys(), {const MediaKey.movie(movieId)});
    });

    test('an untracked show fetches the root, then the seasons only, and writes every season and episode', () async {
      await service.ensureTracked(const MediaKey.episode(showId, 2, 1));

      expect(requests.map((r) => r.url.path), ['/3/tv/$showId', '/3/tv/$showId']);
      expect(requests.first.url.queryParameters['append_to_response'], contains('aggregate_credits'));
      expect(appendedSeasonsOf(requests.first), isEmpty);
      expect(requests.last.url.queryParameters['append_to_response'], 'season/1,season/2');
      final seasons = await SeasonRepo().getAllForShow(showId);
      expect(seasons.map((s) => (s.season, s.hasSnapshot)), [(1, true), (2, true)]);
      expect((await EpisodeRepo().getAllForShow(showId)).length, 4);
      expect(await SnapshotDocumentRepo().getShow(showId), isNotNull);
      expect(await SnapshotDocumentRepo().getSeason(showId, 2), isNotNull);
      expect((await ShowRepo().get(showId))?.watchProvidersRegion, isNull, reason: 'no region configured');
    });

    test('a transport failure throws TrackingUnavailableException and writes nothing', () async {
      answer = (_) => throw ClientException('connection refused');

      await expectLater(
        service.ensureTracked(const MediaKey.movie(movieId)),
        throwsA(isA<TrackingUnavailableException>().having((e) => e.code, 'code', JobErrorCode.networkError)),
      );

      expect(await MovieRepo().get(movieId), isNull);
      expect(await SnapshotDocumentRepo().getMovie(movieId), isNull);
    });

    test('a 404 throws ItemGoneException for a movie and for a show', () async {
      answer = snapshotAnswers();

      await expectLater(service.ensureTracked(const MediaKey.movie(movieId)), throwsA(isA<ItemGoneException>()));
      await expectLater(service.ensureTracked(const MediaKey.show(showId)), throwsA(isA<ItemGoneException>()));

      expect(await MovieRepo().get(movieId), isNull);
      expect(await ShowRepo().get(showId), isNull);
    });

    test('materialise removes a pending deletion row', () async {
      await PendingDeletionRepo().enqueue(ItemType.movie, movieId, now);

      await service.materialise(const MediaKey.movie(movieId), now: now);

      expect(await PendingDeletionRepo().getAll(), isEmpty);
      expect((await MovieRepo().get(movieId))?.fetchedAt?.toUtc(), now);
    });
  });

  group('referenceCount', () {
    test('counts each reference kind once and tells movie 5 from show 5', () async {
      await playMovie(5);
      await playMovie(5);
      await FavoriteRepo().insert(FavoriteEntity.build(type: ItemType.movie, tmdbId: 5, favoritedAt: now));
      await UserRatingRepo().insert(UserRatingEntity.build(type: ItemType.show, tmdbId: 5, rating: 8, ratedAt: now));
      await WatchlistRepo().insert(WatchlistEntity.build(type: ItemType.episode, tmdbId: 5, season: 1, episode: 2, listedAt: now));
      await seedState(5, ShowWatchStatus.dropped);

      expect(await service.referenceCount(const MediaKey.movie(5)), 2);
      expect(await service.referenceCount(const MediaKey.episode(5, 1, 2)), 3);
      expect(await service.referenceCount(const MediaKey.movie(6)), 0);
    });

    test('an episode play references the show, not a movie with the same id', () async {
      await playEpisode(5, 1, 1);

      expect(await service.referenceCount(const MediaKey.show(5)), 1);
      expect(await service.referenceCount(const MediaKey.movie(5)), 0);
    });
  });

  group('onReferenceRemoved', () {
    test('queues a tracked item with no references left', () async {
      await seedMovie(movieId);

      await service.onReferenceRemoved(const MediaKey.movie(movieId), now: now);

      final queued = (await PendingDeletionRepo().getAll()).single;
      expect((queued.type, queued.tmdbId), (ItemType.movie, movieId));
      expect(queued.queuedAt.toUtc(), now);
    });

    test('queues nothing while a reference remains, or for an untracked item', () async {
      await seedMovie(movieId);
      await playMovie(movieId);
      await service.onReferenceRemoved(const MediaKey.movie(movieId), now: now);

      await service.onReferenceRemoved(const MediaKey.show(showId), now: now);

      expect(await PendingDeletionRepo().getAll(), isEmpty);
    });
  });

  group('sweepPendingDeletions', () {
    const job = NewAssetJob(
      mediaType: ItemType.show,
      itemId: showId,
      kind: 'poster',
      size: 'w500',
      sourceUrl: 'u',
      destPath: 'show/1399/p.jpg',
    );

    Future<void> seedTrackedShow() async {
      await seedShow(showId, fetchedAt: now);
      await seedSeason(showId, 1, fetchedAt: now);
      await seedEpisode(showId, 1, 1, airDate: '2026-01-01');
      await SnapshotDocumentRepo().upsertAll([
        SnapshotDocumentEntity.show(showId, '{"id": $showId}'),
        SnapshotDocumentEntity.season(showId, 1, '{"season_number": 1}'),
      ]);
      await AssetJobRepo().insertIgnore([job], createdAt: now);
    }

    test('respects the grace period', () async {
      await seedMovie(movieId);
      await PendingDeletionRepo().enqueue(ItemType.movie, movieId, now.subtract(const Duration(days: 2)));

      expect(await service.sweepPendingDeletions(now: now), 0);

      expect(await MovieRepo().get(movieId), isNotNull);
      expect(await PendingDeletionRepo().count(), 1);
    });

    test('a re-referenced item just loses its queue row', () async {
      await seedMovie(movieId);
      await PendingDeletionRepo().enqueue(ItemType.movie, movieId, now.subtract(const Duration(days: 8)));
      await playMovie(movieId);

      expect(await service.sweepPendingDeletions(now: now), 0);

      expect(await MovieRepo().get(movieId), isNotNull);
      expect(await PendingDeletionRepo().count(), 0);
    });

    test('removes the rows, documents, state and asset jobs of the others', () async {
      await seedTrackedShow();
      await seedMovie(movieId);
      await SnapshotDocumentRepo().upsert(SnapshotDocumentEntity.movie(movieId, '{"id": $movieId}'));
      await PendingDeletionRepo().enqueue(ItemType.show, showId, now.subtract(const Duration(days: 8)));
      await PendingDeletionRepo().enqueue(ItemType.movie, movieId, now.subtract(const Duration(days: 8)));

      expect(await service.sweepPendingDeletions(now: now), 2);

      expect(await ShowRepo().get(showId), isNull);
      expect(await SeasonRepo().getAllForShow(showId), isEmpty);
      expect(await EpisodeRepo().getAllForShow(showId), isEmpty);
      expect(await ShowStateRepo().get(showId), isNull);
      expect(await SnapshotDocumentRepo().getShow(showId), isNull);
      expect(await SnapshotDocumentRepo().getSeason(showId, 1), isNull);
      expect(await AssetJobRepo().countAllPending(), 0);
      expect(await MovieRepo().get(movieId), isNull);
      expect(await SnapshotDocumentRepo().getMovie(movieId), isNull);
      expect(await PendingDeletionRepo().count(), 0);
    });

    test('a shorter grace can be given', () async {
      await seedMovie(movieId);
      await PendingDeletionRepo().enqueue(ItemType.movie, movieId, now.subtract(const Duration(hours: 1)));

      expect(await service.sweepPendingDeletions(grace: Duration.zero, now: now), 1);
    });
  });

  test('enqueueUnreferenced queues every tracked item nothing references', () async {
    await seedMovie(1);
    await seedMovie(2);
    await seedShow(3);
    await seedShow(4);
    await playMovie(1);
    await seedState(4, ShowWatchStatus.watching);

    await service.enqueueUnreferenced(now: now);

    final queued = (await PendingDeletionRepo().getAll()).map((p) => (p.type, p.tmdbId)).toSet();
    expect(queued, {(ItemType.movie, 2), (ItemType.show, 3)});
  });
}
