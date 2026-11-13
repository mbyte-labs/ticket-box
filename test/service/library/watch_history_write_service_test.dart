import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:ticketbox/api/tmdb/tmdb_http_client.dart';
import 'package:ticketbox/common/date_parser_tmdb.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/common/model/watched_at_options.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/library/watch_history_write_service.dart';
import 'package:ticketbox/service/watchlist/watchlist_service.dart';

import '../catalog/catalog_test_support.dart';

/// A library gate that never fetches and records what it was asked.
class _StubLibrary extends LibraryService {
  final tracked = <MediaKey>[];
  final removed = <MediaKey>[];

  _StubLibrary() : super(artwork: noArtwork);

  @override
  Future<void> ensureTracked(MediaKey key) async => tracked.add(key);

  @override
  Future<void> onReferenceRemoved(MediaKey key, {DateTime? now}) async => removed.add(key);
}

/// Every history write: the tracking gate first, then the rows and the show's state in one
/// transaction, then the watchlist cascade. Bulk marks expand to aired episodes only; every mark
/// logs a new play whatever the history holds.
void main() {
  late DatabaseConnectionManager db;
  late WatchHistoryWriteService service;
  late _StubLibrary library;
  final requests = <Request>[];

  const show = 10;
  const movie = 550;
  final today = DateTime.now();
  final e1Aired = today.subtract(const Duration(days: 30));
  final e2Aired = today.subtract(const Duration(days: 7));

  const e1 = MarkAsWatchedTarget(type: ItemType.episode, showTmdbId: show, season: 1, episode: 1, title: 'Alpha', subtitle: 'S1E1');
  const season1 = MarkAsWatchedTarget(type: ItemType.season, showTmdbId: show, season: 1, title: 'Alpha', subtitle: 'S1');
  const wholeShow = MarkAsWatchedTarget(type: ItemType.show, showTmdbId: show, title: 'Alpha', subtitle: '');
  const movieTarget = MarkAsWatchedTarget(type: ItemType.movie, showTmdbId: movie, title: 'Fight Club', subtitle: '1999');

  setUp(() async {
    requests.clear();
    TmdbHttpClient.forTesting(
      MockClient((request) {
        requests.add(request);
        throw ClientException('the write services never need TMDB in these tests');
      }),
    );
    db = openTestDatabase(withPreferences: true);
    library = _StubLibrary();
    final hooks = NoopSyncHooks();
    service = WatchHistoryWriteService(
      watchlist: WatchlistService(library: library, hooks: hooks),
      library: library,
      hooks: hooks,
      artwork: noArtwork,
    );
    // S0E1 special, S1E1 and S1E2 aired, S1E3 next week, S1E4 undated.
    await seedShow(show, title: 'Alpha');
    await seedSeason(show, 0);
    await seedSeason(show, 1);
    await seedEpisode(show, 0, 1, airDate: ymd(today.subtract(const Duration(days: 100))));
    await seedEpisode(show, 1, 1, airDate: ymd(e1Aired));
    await seedEpisode(show, 1, 2, airDate: ymd(e2Aired));
    await seedEpisode(show, 1, 3, airDate: ymd(today.add(const Duration(days: 7))));
    await seedEpisode(show, 1, 4);
  });

  tearDown(() async {
    TmdbHttpClient.resetForTesting();
    await closeTestDatabase(db);
  });

  Future<List<HistoryEntity>> plays() => HistoryRepo().getAll();

  Set<(int, int)> positions(List<HistoryEntity> rows) => {for (final row in rows) (row.season, row.episode)};

  test('a right-now mark of an unwatched episode inserts one row and creates the watching state', () async {
    await service.addToHistory(target: e1);

    final rows = await plays();
    expect(rows, hasLength(1));
    expect((rows.single.type, rows.single.tmdbId, rows.single.season, rows.single.episode), (ItemType.episode, show, 1, 1));
    expect(DateTime.now().difference(rows.single.watchedAt).inSeconds, lessThan(10));
    expect((await ShowStateRepo().get(show))?.status, ShowWatchStatus.watching);
    expect(library.tracked, [e1.key], reason: 'the tracking gate runs before the write');
    expect(requests, isEmpty);
  });

  test('marking an episode again logs a second viewing', () async {
    await service.addToHistory(target: e1);
    await service.addToHistory(target: e1);

    expect(await plays(), hasLength(2));
  });

  test('marking a movie again logs a second viewing', () async {
    await service.addToHistory(target: movieTarget);
    await service.addToHistory(target: movieTarget);

    expect(await plays(), hasLength(2));
  });

  test('repeating a season bulk mark logs a second viewing of every aired episode', () async {
    await service.addToHistory(target: season1);
    await service.addToHistory(target: season1);

    final rows = await plays();
    expect(rows, hasLength(4));
    expect(positions(rows), {(1, 1), (1, 2)});
  });

  test('a custom instant always inserts, stamped as given', () async {
    final instant = DateTime.now().subtract(const Duration(hours: 3));
    await service.addToHistory(target: e1);

    await service.addToHistory(target: e1, selectedDateType: WatchedConfirmationDateSelect.custom, customWatchTime: instant);

    final rows = await plays();
    expect(rows, hasLength(2));
    expect(rows.last.watchedAt.toUtc().millisecondsSinceEpoch ~/ 1000, instant.toUtc().millisecondsSinceEpoch ~/ 1000);
  });

  test('a future custom instant throws and writes nothing', () async {
    final future = DateTime.now().add(const Duration(days: 1));

    await expectLater(
      service.addToHistory(target: e1, selectedDateType: WatchedConfirmationDateSelect.custom, customWatchTime: future),
      throwsArgumentError,
    );

    expect(await plays(), isEmpty);
    expect(await ShowStateRepo().get(show), isNull);
    expect(library.tracked, isEmpty);
  });

  test('a season bulk mark inserts one row per aired non-special episode', () async {
    await service.addToHistory(target: season1);

    final rows = await plays();
    expect(positions(rows), {(1, 1), (1, 2)}, reason: 'S1E3 is unaired, S1E4 undated');
    expect(rows.every((r) => DateTime.now().difference(r.watchedAt).inSeconds < 10), isTrue);
  });

  test('a show bulk mark leaves specials out and logs every aired episode, already played or not', () async {
    await service.addToHistory(target: e1);

    await service.addToHistory(target: wholeShow);

    final rows = await plays();
    expect(rows, hasLength(3), reason: 'S1E1 again, S1E2; the special and the unaired/undated episodes are left out');
    expect(positions(rows), {(1, 1), (1, 2)});
    expect((await ShowStateRepo().get(show))?.status, ShowWatchStatus.watched);
  });

  test('a release-date mark stamps each episode with its local-midnight air date', () async {
    await service.addToHistory(target: season1, selectedDateType: WatchedConfirmationDateSelect.episodeReleaseDate);

    final rows = await plays();
    final byEpisode = {for (final row in rows) row.episode: row.watchedAt.toUtc()};
    expect(byEpisode[1], tmdbDateOrNull(ymd(e1Aired))!.toUtc());
    expect(byEpisode[2], tmdbDateOrNull(ymd(e2Aired))!.toUtc());
    expect(byEpisode[1], DateTime(e1Aired.year, e1Aired.month, e1Aired.day).toUtc());
  });

  test('a single episode marked at release takes its own air date', () async {
    await service.addToHistory(target: e1, selectedDateType: WatchedConfirmationDateSelect.releaseDate);

    expect((await plays()).single.watchedAt.toUtc(), DateTime(e1Aired.year, e1Aired.month, e1Aired.day).toUtc());
  });

  test('a rating lands in user_ratings in the same call', () async {
    await service.addToHistory(target: e1, rating: 8);

    expect((await UserRatingRepo().get(ItemType.episode, show, 1, 1))?.rating, 8);
    expect(await plays(), hasLength(1));
  });

  test('a season cannot be rated, so its rating is dropped and the plays still land', () async {
    await service.addToHistory(target: season1, rating: 7);

    expect(await UserRatingRepo().getAll(), isEmpty);
    expect(await plays(), hasLength(2));
  });

  test('removing the last play removes the state row and reports the lost reference', () async {
    await service.addToHistory(target: e1);
    final row = (await plays()).single;

    await service.removeByHistoryId(row.historyId);

    expect(await plays(), isEmpty);
    expect(await ShowStateRepo().get(show), isNull);
    expect(library.removed, [const MediaKey.show(show)]);
  });

  test('removing one of two plays keeps the state', () async {
    await service.addToHistory(target: season1);

    await service.removeEpisode(show, 1, 2);

    expect(positions(await plays()), {(1, 1)});
    expect((await ShowStateRepo().get(show))?.status, ShowWatchStatus.watching);
    expect(library.removed, [const MediaKey.show(show)], reason: 'the library decides whether anything is left');
  });

  test('removing a movie play reports the movie key', () async {
    await service.addToHistory(target: movieTarget);

    await service.removeMovie(movie);

    expect(await plays(), isEmpty);
    expect(library.removed, [const MediaKey.movie(movie)]);
  });

  test('the watchlist row of a watched movie is cleared', () async {
    await WatchlistRepo().insert(WatchlistEntity.build(type: ItemType.movie, tmdbId: movie, listedAt: DateTime.now()));
    // A show with the same id stays listed: movies and shows share TMDB's id space.
    await WatchlistRepo().insert(WatchlistEntity.build(type: ItemType.show, tmdbId: movie, listedAt: DateTime.now()));

    await service.addToHistory(target: movieTarget);

    expect(await WatchlistRepo().getItem(ItemType.movie, movie), isNull);
    expect(await WatchlistRepo().getItem(ItemType.show, movie), isNotNull);
    expect((await plays()).single.type, ItemType.movie);
  });

  test('an episode play clears the show, season and episode watchlist rows', () async {
    for (final key in [const MediaKey.show(show), const MediaKey.season(show, 1), const MediaKey.episode(show, 1, 1)]) {
      await WatchlistRepo().insert(
        WatchlistEntity.build(type: key.type, tmdbId: key.tmdbId, season: key.season, episode: key.episode, listedAt: DateTime.now()),
      );
    }

    await service.addToHistory(target: e1);

    expect(await WatchlistRepo().getAll(), isEmpty);
  });
}
