import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/genres/genres.dart';
import 'package:ticketbox/database/sql_store/genres/genres_repository.dart';

/// Covers the composite {id, type} primary key: TMDB's movie and TV genre lists mostly share ids
/// and names, so with `id` alone the movie sync's upserts would silently overwrite every show genre
/// on each full sync — `getByType(show)` would then return only show-exclusive genres. And
/// [GenresRepo.replaceByType] must clear exactly one type.
void main() {
  late DatabaseConnectionManager db;
  late GenresRepo repo;

  GenreEntity genre(int id, String name, ItemType type) {
    return GenreEntity.build(id: id, name: name, type: type, synchronizedAt: DateTime.utc(2026, 8));
  }

  setUp(() async {
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    repo = GenresRepo();
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  test('the same genre id coexists for shows and movies', () async {
    await repo.insertAll([genre(28, 'Action', ItemType.show), genre(28, 'Action', ItemType.movie)]);

    expect(await repo.getByType(ItemType.show), hasLength(1));
    expect(await repo.getByType(ItemType.movie), hasLength(1));
  });

  test('a second sync of each type keeps both (the exact regression the key change fixes)', () async {
    await repo.replaceByType(ItemType.show, [genre(28, 'Action', ItemType.show), genre(18, 'Drama', ItemType.show)]);
    await repo.replaceByType(ItemType.movie, [genre(28, 'Action', ItemType.movie)]);
    await repo.replaceByType(ItemType.show, [genre(28, 'Action', ItemType.show), genre(18, 'Drama', ItemType.show)]);
    await repo.replaceByType(ItemType.movie, [genre(28, 'Action', ItemType.movie)]);

    final shows = await repo.getByType(ItemType.show);
    expect(shows.map((g) => g.name).toSet(), {'Action', 'Drama'});
    expect(await repo.getByType(ItemType.movie), hasLength(1));
  });

  test('replaceByType only clears the given type', () async {
    await repo.insertAll([genre(28, 'Action', ItemType.show), genre(18, 'Drama', ItemType.show), genre(28, 'Action', ItemType.movie)]);

    await repo.replaceByType(ItemType.show, [genre(10759, 'Action & Adventure', ItemType.show)]);

    expect((await repo.getByType(ItemType.show)).map((g) => g.id), [10759]);
    expect((await repo.getByType(ItemType.movie)).map((g) => g.id), [28], reason: 'the movie list must be untouched');
  });

  test('replaceByType with an empty list clears just that type', () async {
    await repo.insertAll([genre(28, 'Action', ItemType.show), genre(28, 'Action', ItemType.movie)]);

    await repo.replaceByType(ItemType.show, []);

    expect(await repo.getByType(ItemType.show), isEmpty);
    expect(await repo.getByType(ItemType.movie), hasLength(1));
  });

  test('getByType returns the names in alphabetical order', () async {
    await repo.insertAll([genre(18, 'Drama', ItemType.movie), genre(28, 'Action', ItemType.movie), genre(35, 'Comedy', ItemType.movie)]);

    expect((await repo.getByType(ItemType.movie)).map((g) => g.name), ['Action', 'Comedy', 'Drama']);
  });

  test('get looks one genre up by type and id', () async {
    await repo.insertAll([genre(28, 'Action', ItemType.show), genre(28, 'Action!', ItemType.movie)]);

    expect((await repo.get(ItemType.movie, 28))?.name, 'Action!');
    expect((await repo.get(ItemType.show, 28))?.name, 'Action');
    expect(await repo.get(ItemType.show, 99), isNull);
  });

  test('deleteAll clears both types', () async {
    await repo.insertAll([genre(28, 'Action', ItemType.show), genre(28, 'Action', ItemType.movie)]);

    await repo.deleteAll();

    expect(await repo.getByType(ItemType.show), isEmpty);
    expect(await repo.getByType(ItemType.movie), isEmpty);
  });
}
