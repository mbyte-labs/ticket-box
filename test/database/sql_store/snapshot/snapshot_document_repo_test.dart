import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_entity.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';

/// Guards the document store's keying: a movie, a show and that show's seasons can all carry the
/// same numeric TMDB id and must stay apart, and removing a show takes its root and every season
/// document with it while a movie with the same id stays.
void main() {
  late DatabaseConnectionManager db;
  late SnapshotDocumentRepo repo;

  // A movie and an unrelated show that happen to share one TMDB id.
  const sharedTmdbId = 42;

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    // The repos resolve their connection through GetIt rather than taking it as a parameter.
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = SnapshotDocumentRepo();

    await repo.upsertAll([
      SnapshotDocumentEntity.movie(sharedTmdbId, '{"movie":42}'),
      SnapshotDocumentEntity.show(sharedTmdbId, '{"show":42}'),
      SnapshotDocumentEntity.season(sharedTmdbId, 1, '{"season":1}'),
      SnapshotDocumentEntity.season(sharedTmdbId, 2, '{"season":2}'),
      SnapshotDocumentEntity.show(7, '{"show":7}'),
      SnapshotDocumentEntity.season(7, 1, '{"show":7,"season":1}'),
    ]);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  test('a movie, a show and its seasons with the same tmdb id are separate documents', () async {
    expect(await repo.getMovie(sharedTmdbId), '{"movie":42}');
    expect(await repo.getShow(sharedTmdbId), '{"show":42}');
    expect(await repo.getSeason(sharedTmdbId, 1), '{"season":1}');
    expect(await repo.getSeason(sharedTmdbId, 2), '{"season":2}');
  });

  test('a missing document reads as null', () async {
    expect(await repo.getMovie(7), isNull);
    expect(await repo.getSeason(sharedTmdbId, 3), isNull);
    expect(await repo.getShow(404), isNull);
  });

  test('the entity constructors key movies and shows at season 0', () {
    final movie = SnapshotDocumentEntity.movie(1, '{}');
    expect((movie.type, movie.tmdbId, movie.season), (ItemType.movie, 1, 0));
    final show = SnapshotDocumentEntity.show(1, '{}');
    expect((show.type, show.tmdbId, show.season), (ItemType.show, 1, 0));
    final season = SnapshotDocumentEntity.season(1, 3, '{}');
    expect((season.type, season.tmdbId, season.season), (ItemType.season, 1, 3));
  });

  test('upsert replaces the document of an existing key only', () async {
    await repo.upsert(SnapshotDocumentEntity.show(sharedTmdbId, '{"show":42,"v":2}'));

    expect(await repo.getShow(sharedTmdbId), '{"show":42,"v":2}');
    expect(await repo.getMovie(sharedTmdbId), '{"movie":42}');
    expect(await repo.getSeason(sharedTmdbId, 1), '{"season":1}');
  });

  test('upsertAll with an empty list is a no-op', () async {
    await repo.upsertAll([]);

    expect(await repo.getShow(sharedTmdbId), '{"show":42}');
  });

  test('deleteFor(movie) removes the movie document and nothing of the show with the same id', () async {
    await repo.deleteFor(ItemType.movie, sharedTmdbId);

    expect(await repo.getMovie(sharedTmdbId), isNull);
    expect(await repo.getShow(sharedTmdbId), isNotNull);
    expect(await repo.getSeason(sharedTmdbId, 1), isNotNull);
  });

  test('deleteFor(show) removes the root and every season document, not the movie or other shows', () async {
    await repo.deleteFor(ItemType.show, sharedTmdbId);

    expect(await repo.getShow(sharedTmdbId), isNull);
    expect(await repo.getSeason(sharedTmdbId, 1), isNull);
    expect(await repo.getSeason(sharedTmdbId, 2), isNull);
    expect(await repo.getMovie(sharedTmdbId), isNotNull);
    expect(await repo.getShow(7), isNotNull);
    expect(await repo.getSeason(7, 1), isNotNull);
  });

  test('deleteSeason removes one season document only', () async {
    await repo.deleteSeason(sharedTmdbId, 1);

    expect(await repo.getSeason(sharedTmdbId, 1), isNull);
    expect(await repo.getSeason(sharedTmdbId, 2), isNotNull);
    expect(await repo.getShow(sharedTmdbId), isNotNull);
    expect(await repo.getSeason(7, 1), isNotNull);
  });
}
