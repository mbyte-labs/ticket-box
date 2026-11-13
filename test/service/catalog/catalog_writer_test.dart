import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';
import 'package:ticketbox/service/catalog/catalog_writer.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';

import 'catalog_test_support.dart';
import 'snapshot_fixtures.dart';

/// `CatalogWriter` turns pruned TMDB documents into catalogue rows plus the verbatim document, one
/// transaction per item; a rewrite keeps `trackedAt`, season stubs never touch a fetched season's
/// `fetchedAt`, and a season TMDB stops listing goes with its episodes and document.
void main() {
  late DatabaseConnectionManager db;
  late CatalogWriter writer;
  late SnapshotDocumentRepo documents;

  final t1 = DateTime.utc(2026, 6, 1, 10);
  final t2 = DateTime.utc(2026, 6, 3, 10);
  const region = 'US';
  const movieId = 550;
  const showId = 1399;

  setUp(() {
    db = openTestDatabase();
    writer = CatalogWriter();
    documents = SnapshotDocumentRepo();
  });

  tearDown(() => closeTestDatabase(db));

  Future<void> writeShow({DateTime? now, Map<String, dynamic>? raw, bool withSeasons = true}) async {
    final pruned = SnapshotPruner.showRoot(raw ?? rawShow(), region: region);
    await writer.writeShow(pruned.root, withSeasons ? pruned.seasons : const {}, now: now ?? t1, region: region);
  }

  group('writeMovie', () {
    test('writes the row and the document together', () async {
      final pruned = SnapshotPruner.movie(rawMovie(), region: region);

      final written = await writer.writeMovie(pruned, now: t1, region: region);

      final row = await MovieRepo().get(movieId);
      expect(row, isNotNull);
      expect(row!.title, 'Fight Club');
      expect(row.imdbId, 'tt0137523');
      expect(row.fetchedAt?.toUtc(), t1);
      expect(row.trackedAt.toUtc(), t1);
      expect(row.watchProvidersRegion, region);
      expect(json.decode((await documents.getMovie(movieId))!), pruned);
      expect(written.movie.tmdbId, movieId);
      expect(written.details.title, 'Fight Club');
    });

    test('derives poster and backdrop from the best English image, else the best voted', () async {
      await writer.writeMovie(
        SnapshotPruner.movie(rawMovie(), region: region),
        now: t1,
        region: region,
      );

      final row = (await MovieRepo().get(movieId))!;
      expect(row.posterPath, '/p-en-7.jpg', reason: 'the German 9.0 poster loses to the best English one');
      expect(row.backdropPath, '/b-2.jpg', reason: 'no English backdrop: the best voted wins');
    });

    test('falls back to the body path without an images section', () async {
      final raw = rawMovie()..remove('images');

      await writer.writeMovie(
        SnapshotPruner.movie(raw, region: region),
        now: t1,
        region: region,
      );

      final row = (await MovieRepo().get(movieId))!;
      expect(row.posterPath, '/top-level-poster.jpg');
      expect(row.backdropPath, '/top-level-backdrop.jpg');
    });

    test('a rewrite keeps trackedAt and moves fetchedAt', () async {
      await writer.writeMovie(
        SnapshotPruner.movie(rawMovie(), region: region),
        now: t1,
        region: region,
      );
      final changed = rawMovie()..['title'] = 'Fight Club (restored)';

      await writer.writeMovie(
        SnapshotPruner.movie(changed, region: 'GB'),
        now: t2,
        region: 'GB',
      );

      final row = (await MovieRepo().get(movieId))!;
      expect(row.trackedAt.toUtc(), t1);
      expect(row.fetchedAt?.toUtc(), t2);
      expect(row.title, 'Fight Club (restored)');
      expect(row.watchProvidersRegion, 'GB');
      expect((json.decode((await documents.getMovie(movieId))!) as Map<String, dynamic>)['title'], 'Fight Club (restored)');
    });
  });

  group('writeShow', () {
    test('writes the row, the root document, the fetched seasons with their episodes and documents', () async {
      final pruned = SnapshotPruner.showRoot(rawShow(), region: region);

      final written = await writer.writeShow(pruned.root, pruned.seasons, now: t1, region: region);

      final row = (await ShowRepo().get(showId))!;
      expect(row.title, 'Game of Thrones');
      expect(row.fetchedAt?.toUtc(), t1);
      expect(row.trackedAt.toUtc(), t1);
      expect(row.status, 'ended');
      expect(row.posterPath, '/sp-en-7.jpg', reason: 'best English poster over the better voted language-less one');
      expect(row.backdropPath, '/sb-1.jpg');
      expect(json.decode((await documents.getShow(showId))!), pruned.root);

      final seasons = await SeasonRepo().getAllForShow(showId);
      expect(seasons.map((s) => s.season), [1, 2]);
      expect(seasons.map((s) => s.fetchedAt?.toUtc()), [t1, t1]);
      expect(seasons.map((s) => s.tmdbId), [3624, 3625], reason: 'the appended documents carry no id; the stubs do');
      expect(seasons.first.posterPath, '/season-1.jpg');
      expect((await EpisodeRepo().getAllForShow(showId)).map((e) => (e.season, e.episode)), [(1, 1), (1, 2), (2, 1), (2, 2)]);
      expect(json.decode((await documents.getSeason(showId, 1))!), pruned.seasons[1]);
      expect(json.decode((await documents.getSeason(showId, 2))!), pruned.seasons[2]);
      expect(written.seasons, hasLength(2));
      expect(written.episodes, hasLength(4));
    });

    test('a root alone writes season stubs with no fetchedAt and no document', () async {
      await writeShow(withSeasons: false);

      final seasons = await SeasonRepo().getAllForShow(showId);
      expect(seasons.map((s) => s.season), [1, 2]);
      expect(seasons.every((s) => s.fetchedAt == null), isTrue);
      expect(seasons.first.episodeCount, 2);
      expect(await EpisodeRepo().getAllForShow(showId), isEmpty);
      expect(await documents.getSeason(showId, 1), isNull);
      expect(await SeasonRepo().getUnfetchedSeasonNumbers(showId), [1, 2]);
    });

    test('a rewrite keeps trackedAt, and the stubs leave a fetched season\'s fetchedAt alone', () async {
      await writeShow(now: t1);

      await writeShow(
        now: t2,
        withSeasons: false,
        raw: showRootBody(listedSeasons: [1, 2, 3]),
      );

      final row = (await ShowRepo().get(showId))!;
      expect(row.trackedAt.toUtc(), t1);
      expect(row.fetchedAt?.toUtc(), t2);
      final seasons = await SeasonRepo().getAllForShow(showId);
      expect(seasons.map((s) => (s.season, s.fetchedAt?.toUtc())), [(1, t1), (2, t1), (3, null)]);
      expect((await EpisodeRepo().getAllForShow(showId)).length, 4, reason: 'the fetched seasons keep their episodes');
      expect(await documents.getSeason(showId, 1), isNotNull);
    });

    test('a season TMDB no longer lists is removed with its episodes and document', () async {
      await writeShow(now: t1);

      await writeShow(
        now: t2,
        withSeasons: false,
        raw: showRootBody(listedSeasons: [1]),
      );

      expect((await SeasonRepo().getAllForShow(showId)).map((s) => s.season), [1]);
      expect((await EpisodeRepo().getAllForShow(showId)).map((e) => e.season).toSet(), {1});
      expect(await documents.getSeason(showId, 2), isNull);
      expect(await documents.getSeason(showId, 1), isNotNull);
    });

    test('a season document for a season the root does not list is ignored', () async {
      final pruned = SnapshotPruner.showRoot(rawShow(), region: region);

      await writer.writeShow(pruned.root, {1: pruned.seasons[1]!, 7: rawAppendedSeason(7)}, now: t1, region: region);

      expect((await SeasonRepo().getAllForShow(showId)).map((s) => s.season), [1, 2]);
      expect(await documents.getSeason(showId, 7), isNull);
      expect((await SeasonRepo().getBySeasonNumber(showId, 2))!.fetchedAt, isNull);
    });

    test('replacing a season keeps an episode imdb_id set earlier and drops episodes no longer listed', () async {
      await writeShow(now: t1);
      await EpisodeRepo().updateImdbId(showId, 1, 1, 'tt1');
      final shorter = rawShow()..['season/1'] = rawAppendedSeason(1, episodes: 1);

      await writeShow(now: t2, raw: shorter);

      final episodes = await EpisodeRepo().getAllForSeason(showId, 1);
      expect(episodes.map((e) => e.episode), [1]);
      expect(episodes.single.imdbId, 'tt1');
      expect((await SeasonRepo().getBySeasonNumber(showId, 1))!.fetchedAt?.toUtc(), t2);
    });
  });
}
