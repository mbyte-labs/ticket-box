import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';
import 'package:ticketbox/service/catalog/catalog_writer.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/service/show/show_service.dart';

import '../catalog/catalog_test_support.dart';
import '../catalog/snapshot_fixtures.dart';

/// The show counterpart of `MovieService`: one staleness gate for the show, season and episode
/// pages; a stub season is fetched on first view; an episode is its season document's entry; a
/// stale root refresh materialises new seasons and never re-fetches a season it already has.
void main() {
  late DatabaseConnectionManager db;
  late ShowService service;
  final requests = <Request>[];
  late Future<Response> Function(Request request) answer;

  final t0 = DateTime.utc(2026, 6, 1, 10);
  const region = 'US';
  const showId = 1399;

  setUp(() {
    requests.clear();
    answer = snapshotAnswers(showRoot: showRootBody());
    TmdbHttpClient.forTesting(
      MockClient((request) {
        requests.add(request);
        return answer(request);
      }),
    );
    db = openTestDatabase();
    service = ShowService(artwork: noArtwork);
  });

  tearDown(() async {
    TmdbHttpClient.resetForTesting();
    await closeTestDatabase(db);
  });

  /// Writes the show at [t0]; with [seasons] its two seasons are fetched, otherwise they are stubs.
  Future<void> track({bool seasons = true, Map<String, dynamic>? raw}) {
    final pruned = SnapshotPruner.showRoot(raw ?? rawShow(), region: region);
    return CatalogWriter().writeShow(pruned.root, seasons ? pruned.seasons : const {}, now: t0, region: region);
  }

  group('getDetails', () {
    test('a tracked show is served from the stored document without a request', () async {
      await track();

      final snapshot = await service.getDetails(showId, region: region);

      expect(requests, isEmpty);
      expect(snapshot.tracked, isTrue);
      expect(snapshot.details.name, 'Game of Thrones');
      expect(snapshot.fetchedAt?.toUtc(), t0);
      expect(snapshot.seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(snapshot.appendedSeasons, isEmpty);
    });

    test('a tracked show without a document yet renders the synthetic fallback from its rows', () async {
      await seedShow(7, title: 'Stub');
      await seedSeason(7, 1, episodeCount: 3);

      final snapshot = await service.getDetails(7, region: region);

      expect(requests, isEmpty);
      expect(snapshot.tracked, isTrue);
      expect(snapshot.fetchedAt, isNull);
      expect(snapshot.details.name, 'Stub');
      expect(snapshot.seasons.single.episodeCount, 3);
    });

    test('an untracked show is fetched live and nothing is written', () async {
      final snapshot = await service.getDetails(showId, region: region);

      expect(requests.map((r) => r.url.path), ['/3/tv/$showId']);
      expect(appendedSeasonsOf(requests.single), isEmpty);
      expect(snapshot.tracked, isFalse);
      expect(snapshot.details.name, 'Game of Thrones');
      expect(await ShowRepo().get(showId), isNull);
      expect(await SnapshotDocumentRepo().getShow(showId), isNull);
    });

    test('an untracked show propagates the transport error and turns a 404 into ItemGoneException', () async {
      answer = (_) => throw ClientException('offline');
      await expectLater(service.getDetails(showId, region: region), throwsA(isA<ClientException>()));

      answer = snapshotAnswers();
      await expectLater(service.getDetails(showId, region: region), throwsA(isA<ItemGoneException>()));
    });
  });

  group('getSeason and getEpisode', () {
    test('a stub season of a tracked show is fetched once, alone', () async {
      await track(seasons: false);

      final view = await service.getSeason(showId, 2, region: region);

      expect(requests, hasLength(1));
      expect(appendedSeasonsOf(requests.single), [2]);
      expect(view.season.tracked, isTrue);
      expect(view.season.episodes.map((e) => e.episodeNumber), [1, 2]);
      expect(view.show.details.name, 'Game of Thrones');
      expect((await SeasonRepo().getBySeasonNumber(showId, 2))?.hasSnapshot, isTrue);
      expect((await SeasonRepo().getBySeasonNumber(showId, 1))?.hasSnapshot, isFalse, reason: 'only the viewed season is fetched');
      expect((await EpisodeRepo().getAllForSeason(showId, 2)).length, 2);

      await service.getSeason(showId, 2, region: region);
      expect(requests, hasLength(1), reason: 'a fetched season is never re-fetched by a view');
    });

    test('a stub season renders from its rows when TMDB cannot be reached', () async {
      await track(seasons: false);
      answer = (_) => throw ClientException('offline');

      final view = await service.getSeason(showId, 1, region: region);

      expect(view.season.tracked, isTrue);
      expect(view.season.episodes, isEmpty);
      expect(view.season.posterPath, '/s1.jpg');
    });

    test('an episode is its season document\'s entry; one the season does not list is gone', () async {
      await track();

      final view = await service.getEpisode(showId, 1, 2, region: region);
      expect(view.episode.name, 'Episode 2');
      expect(view.season.seasonNumber, 1);

      await expectLater(service.getEpisode(showId, 1, 99, region: region), throwsA(isA<ItemGoneException>()));
      expect(requests, isEmpty);
    });

    test('an untracked show\'s season comes appended to the live root', () async {
      final view = await service.getSeason(showId, 2, region: region);

      expect(requests, hasLength(1));
      expect(appendedSeasonsOf(requests.single), [2]);
      expect(view.season.tracked, isFalse);
      expect(view.season.episodes, hasLength(2));
      expect(await ShowRepo().get(showId), isNull);

      // A season that does not exist comes back as TMDB's error object under its key.
      answer = snapshotAnswers(showRoot: showRootBody(), seasonDoc: (n) => {'success': false, 'status_code': 34});
      await expectLater(service.getSeason(showId, 99, region: region), throwsA(isA<ItemGoneException>()));
    });
  });

  group('refreshIfStale', () {
    test('a fresh snapshot in the same region makes no request', () async {
      await track();

      expect(await service.refreshIfStale(showId, region: region, now: t0.add(const Duration(hours: 47))), isNull);
      expect(requests, isEmpty);
    });

    test('a stale root is re-fetched without its known seasons', () async {
      await track();
      answer = snapshotAnswers(showRoot: showRootBody()..['name'] = 'Fresh name');
      final later = t0.add(const Duration(hours: 49));

      final result = await service.refreshIfStale(showId, region: region, now: later);

      expect(requests.map((r) => r.url.path), ['/3/tv/$showId']);
      expect(appendedSeasonsOf(requests.single), isEmpty);
      expect(result?.details.name, 'Fresh name');
      expect(result?.fetchedAt?.toUtc(), later);
      expect((await SeasonRepo().getAllForShow(showId)).map((s) => s.fetchedAt?.toUtc()), [t0, t0]);
    });

    test('a snapshot pruned to another region is fetched even when fresh', () async {
      await track();

      final result = await service.refreshIfStale(showId, region: 'GB', now: t0.add(const Duration(hours: 1)));

      expect(requests, hasLength(1));
      expect(result?.providersRegion, 'GB');
    });

    test('keeps the stale document when the client throws', () async {
      await track();
      final before = await SnapshotDocumentRepo().getShow(showId);
      answer = (_) => throw ClientException('offline');

      expect(await service.refreshIfStale(showId, region: region, now: t0.add(const Duration(days: 3))), isNull);
      expect(await SnapshotDocumentRepo().getShow(showId), before);
      expect((await ShowRepo().get(showId))?.fetchedAt?.toUtc(), t0);
    });

    test('a 404 stamps fetched_at without touching the document', () async {
      await track();
      final before = await SnapshotDocumentRepo().getShow(showId);
      answer = snapshotAnswers();
      final later = t0.add(const Duration(days: 3));

      expect(await service.refreshIfStale(showId, region: region, now: later), isNull);
      expect(await SnapshotDocumentRepo().getShow(showId), before);
      expect((await ShowRepo().get(showId))?.fetchedAt?.toUtc(), later);
    });

    test('a new season in the fresh root is materialised; an existing season document is untouched', () async {
      await track();
      final season1Before = await SnapshotDocumentRepo().getSeason(showId, 1);
      answer = snapshotAnswers(showRoot: showRootBody(listedSeasons: [1, 2, 3]));
      final later = t0.add(const Duration(days: 3));

      final result = await service.refreshIfStale(showId, region: region, now: later);

      expect(requests.map((r) => r.url.path), ['/3/tv/$showId', '/3/tv/$showId']);
      expect(appendedSeasonsOf(requests.first), isEmpty);
      expect(requests.last.url.queryParameters['append_to_response'], 'season/3');
      expect(result?.seasons.map((s) => s.seasonNumber), [1, 2, 3]);
      final seasons = await SeasonRepo().getAllForShow(showId);
      expect(seasons.map((s) => (s.season, s.fetchedAt?.toUtc())), [(1, t0), (2, t0), (3, later)]);
      expect(await SnapshotDocumentRepo().getSeason(showId, 3), isNotNull);
      expect((await EpisodeRepo().getAllForSeason(showId, 3)).length, 2);
      expect(await SnapshotDocumentRepo().getSeason(showId, 1), season1Before);
    });
  });

  test('refreshForScheduler reports whether anything was written', () async {
    await track();
    expect(await service.refreshForScheduler(showId, region: region, now: t0.add(const Duration(days: 8))), isTrue);

    answer = snapshotAnswers();
    expect(await service.refreshForScheduler(showId, region: region, now: t0.add(const Duration(days: 9))), isFalse);
  });
}
