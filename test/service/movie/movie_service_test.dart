import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';
import 'package:ticketbox/service/catalog/catalog_writer.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/service/movie/movie_service.dart';

import '../catalog/catalog_test_support.dart';
import '../catalog/snapshot_fixtures.dart';

/// A tracked movie is served from its snapshot and only re-fetched on view once it is stale (or
/// pruned to another region), keeping the stale copy when TMDB cannot be reached; an untracked
/// one is fetched live and nothing is written.
void main() {
  late DatabaseConnectionManager db;
  late MovieService service;
  final requests = <Request>[];
  late Future<Response> Function(Request request) answer;

  final t0 = DateTime.utc(2026, 6, 1, 10);
  const region = 'US';
  const movieId = 550;

  setUp(() {
    requests.clear();
    answer = snapshotAnswers(movie: rawMovie());
    TmdbHttpClient.forTesting(
      MockClient((request) {
        requests.add(request);
        return answer(request);
      }),
    );
    db = openTestDatabase();
    service = MovieService(artwork: noArtwork);
  });

  tearDown(() async {
    TmdbHttpClient.resetForTesting();
    await closeTestDatabase(db);
  });

  Future<void> track({Map<String, dynamic>? raw}) {
    return CatalogWriter().writeMovie(
      SnapshotPruner.movie(raw ?? rawMovie(), region: region),
      now: t0,
      region: region,
    );
  }

  group('getDetails', () {
    test('a tracked movie is served from the stored document without a request', () async {
      await track(raw: rawMovie()..['title'] = 'Stored title');

      final snapshot = await service.getDetails(movieId, region: region);

      expect(requests, isEmpty);
      expect(snapshot.tracked, isTrue);
      expect(snapshot.details.title, 'Stored title');
      expect(snapshot.fetchedAt?.toUtc(), t0);
      expect(snapshot.providersRegion, region);
      expect(snapshot.posterPath, '/p-en-7.jpg');
    });

    test('a tracked movie without a document yet renders the synthetic fallback', () async {
      await seedMovie(7, title: 'Stub');

      final snapshot = await service.getDetails(7, region: region);

      expect(requests, isEmpty);
      expect(snapshot.tracked, isTrue);
      expect(snapshot.fetchedAt, isNull);
      expect(snapshot.details.title, 'Stub');
      expect(snapshot.cast, isEmpty);
    });

    test('an untracked movie is fetched live and nothing is written', () async {
      final snapshot = await service.getDetails(movieId, region: region);

      expect(requests.map((r) => r.url.path), ['/3/movie/$movieId']);
      expect(snapshot.tracked, isFalse);
      expect(snapshot.fetchedAt, isNull);
      expect(snapshot.details.title, 'Fight Club');
      expect(snapshot.providersFor(region)?.providers.map((p) => p.providerId), [9, 8], reason: 'pruned to the region, by priority');
      expect(await MovieRepo().get(movieId), isNull);
      expect(await SnapshotDocumentRepo().getMovie(movieId), isNull);
    });

    test('an untracked movie propagates the transport error', () async {
      answer = (_) => throw ClientException('offline');

      await expectLater(service.getDetails(movieId, region: region), throwsA(isA<ClientException>()));
    });

    test('an untracked movie TMDB does not know throws ItemGoneException', () async {
      answer = snapshotAnswers();

      await expectLater(service.getDetails(movieId, region: region), throwsA(isA<ItemGoneException>()));
    });
  });

  group('refreshIfStale', () {
    test('a fresh snapshot in the same region makes no request', () async {
      await track();

      final result = await service.refreshIfStale(movieId, region: region, now: t0.add(const Duration(hours: 47)));

      expect(result, isNull);
      expect(requests, isEmpty);
    });

    test('a snapshot older than 48 hours is fetched once', () async {
      await track();
      answer = snapshotAnswers(movie: rawMovie()..['title'] = 'Fresh title');
      final later = t0.add(const Duration(hours: 49));

      final result = await service.refreshIfStale(movieId, region: region, now: later);

      expect(requests.map((r) => r.url.path), ['/3/movie/$movieId']);
      expect(result?.details.title, 'Fresh title');
      expect(result?.fetchedAt?.toUtc(), later);
      expect((await MovieRepo().get(movieId))?.fetchedAt?.toUtc(), later);
    });

    test('a snapshot pruned to another region is fetched even when fresh', () async {
      await track();

      final result = await service.refreshIfStale(movieId, region: 'GB', now: t0.add(const Duration(hours: 1)));

      expect(requests, hasLength(1));
      expect(result?.providersRegion, 'GB');
      expect((await MovieRepo().get(movieId))?.watchProvidersRegion, 'GB');
    });

    test('keeps the stale document when the client throws', () async {
      await track();
      final before = await SnapshotDocumentRepo().getMovie(movieId);
      answer = (_) => throw ClientException('offline');

      final result = await service.refreshIfStale(movieId, region: region, now: t0.add(const Duration(days: 3)));

      expect(result, isNull);
      expect(await SnapshotDocumentRepo().getMovie(movieId), before);
      expect((await MovieRepo().get(movieId))?.fetchedAt?.toUtc(), t0);
    });

    test('a 404 stamps fetched_at without touching the document', () async {
      await track();
      final before = await SnapshotDocumentRepo().getMovie(movieId);
      answer = snapshotAnswers();
      final later = t0.add(const Duration(days: 3));

      final result = await service.refreshIfStale(movieId, region: region, now: later);

      expect(result, isNull);
      expect(await SnapshotDocumentRepo().getMovie(movieId), before);
      expect((await MovieRepo().get(movieId))?.fetchedAt?.toUtc(), later);
      expect((await MovieRepo().get(movieId))?.title, 'Fight Club');
    });

    test('an untracked movie is not refreshed', () async {
      expect(await service.refreshIfStale(movieId, region: region), isNull);
      expect(requests, isEmpty);
    });
  });
}
