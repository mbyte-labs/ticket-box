import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/pending_deletion/pending_deletion_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/library/check_in_service.dart';
import 'package:ticketbox/service/library/library_service.dart';

/// A check-in on a title that is not in the library would add it first, which is the one place
/// TMDB is involved; the fixtures below are tracked, so the real gate returns at once. This
/// subclass records the calls so the test can say the gate ran without stubbing it away.
class _RecordingLibrary extends LibraryService {
  final ensured = <MediaKey>[];

  @override
  Future<void> ensureTracked(MediaKey key) async {
    ensured.add(key);
    return super.ensureTracked(key);
  }
}

/// A check-in is a future-dated play: it counts as watched from the start, so the show's state is
/// recomputed in the same transaction and rolled back when the check-in is cancelled.
void main() {
  late DatabaseConnectionManager db;
  late CheckInService service;
  late _RecordingLibrary library;
  const show = 1396;
  const movie = 550;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    KeyValueStore.instance();
    library = _RecordingLibrary();
    GetIt.I.registerSingleton<LibraryService>(library);
    service = CheckInService(library: library);
    final now = DateTime.now().toUtc();
    final aired = now.subtract(const Duration(days: 10));
    final airDate = '${aired.year}-${aired.month.toString().padLeft(2, '0')}-${aired.day.toString().padLeft(2, '0')}';
    await ShowRepo().insert(ShowEntity.stub(tmdbId: show, trackedAt: now, title: 'Breaking Bad')..runtime = 47);
    await MovieRepo().insert(MovieEntity.stub(tmdbId: movie, trackedAt: now, title: 'Fight Club')..runtime = 139);
    for (final e in [1, 2]) {
      await EpisodeRepo().insert(
        EpisodeEntity.build(
          showTmdbId: show,
          season: 1,
          episode: e,
          tmdbId: null,
          imdbId: null,
          title: 'E$e',
          overview: null,
          voteAverage: 0,
          voteCount: 0,
          runtime: e == 1 ? 58 : null,
          airDate: airDate,
          episodeType: null,
          stillPath: null,
        ),
      );
    }
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  const target = MarkAsWatchedTarget(
    type: ItemType.episode,
    showTmdbId: show,
    season: 1,
    episode: 1,
    title: 'Breaking Bad',
    subtitle: 'S1xE1',
  );

  test('starts a check-in as a future-dated history row and counts it as watched', () async {
    await WatchlistRepo().insert(WatchlistEntity.build(type: ItemType.show, tmdbId: show, listedAt: DateTime.now()));

    final outcome = await service.checkIn(target);

    expect(outcome, CheckInOutcome.started);
    expect(library.ensured, [target.key], reason: 'the tracking gate runs before the write');
    final running = await HistoryRepo().getCurrentCheckInItems();
    expect(running.single.action, HistoryAction.checkin);
    // 58 minutes from now, give or take the test's own runtime.
    expect(running.single.watchedAt.difference(DateTime.now()).inMinutes, inInclusiveRange(56, 58));
    expect(await WatchlistRepo().getItem(ItemType.show, show), isNull, reason: 'watching something removes it from the watchlist');
    final state = await ShowStateRepo().get(show);
    expect(state?.status, ShowWatchStatus.watching, reason: 'the state treats the running check-in as a play');
  });

  test('an episode without a runtime of its own falls back to the show runtime', () async {
    const second = MarkAsWatchedTarget(
      type: ItemType.episode,
      showTmdbId: show,
      season: 1,
      episode: 2,
      title: 'Breaking Bad',
      subtitle: 'S1xE2',
    );

    await service.checkIn(second);

    final running = (await HistoryRepo().getCurrentCheckInItems()).single;
    expect(running.watchedAt.difference(DateTime.now()).inMinutes, inInclusiveRange(45, 47));
  });

  test('a movie check-in uses the movie runtime and writes no show state', () async {
    const movieTarget = MarkAsWatchedTarget(type: ItemType.movie, showTmdbId: movie, title: 'Fight Club', subtitle: '');

    expect(await service.checkIn(movieTarget), CheckInOutcome.started);

    final running = (await HistoryRepo().getCurrentCheckInItems()).single;
    expect(running.type, ItemType.movie);
    expect(running.watchedAt.difference(DateTime.now()).inMinutes, inInclusiveRange(137, 139));
    expect(await ShowStateRepo().get(movie), isNull);
  });

  test('only one check-in can run at a time', () async {
    await service.checkIn(target);

    final second = await service.checkIn(target);

    expect(second, CheckInOutcome.alreadyActive);
    expect((await HistoryRepo().getCurrentCheckInItems()).length, 1);
  });

  test('shows and seasons cannot be checked into', () async {
    const showTarget = MarkAsWatchedTarget(type: ItemType.show, showTmdbId: show, title: 'Breaking Bad', subtitle: '');
    expect(await service.checkIn(showTarget), CheckInOutcome.unsupportedType);
    expect(library.ensured, isEmpty);
  });

  test('cancelling removes the row and rolls the show state back', () async {
    await service.checkIn(target);
    final running = (await HistoryRepo().getCurrentCheckInItems()).single;

    await service.cancel(running.historyId);

    expect(await HistoryRepo().getCurrentCheckInItems(), isEmpty);
    expect(await ShowStateRepo().get(show), isNull, reason: 'no plays left, so no state row');
    // The show lost its last reference, so it is queued for the deletion sweep.
    expect((await PendingDeletionRepo().getAll()).map((e) => (e.type, e.tmdbId)), [(ItemType.show, show)]);
  });

  test('cancelling one of several plays keeps the show state', () async {
    await service.checkIn(target);
    final first = (await HistoryRepo().getCurrentCheckInItems()).single;
    await HistoryRepo().deleteByHistoryId(first.historyId);
    await service.checkIn(
      const MarkAsWatchedTarget(type: ItemType.episode, showTmdbId: show, season: 1, episode: 2, title: 'Breaking Bad', subtitle: ''),
    );
    await WatchlistRepo().insert(WatchlistEntity.build(type: ItemType.show, tmdbId: show, listedAt: DateTime.now()));
    final second = (await HistoryRepo().getCurrentCheckInItems()).single;

    await service.cancel(second.historyId);

    expect(await ShowStateRepo().get(show), isNull);
    expect(await PendingDeletionRepo().getAll(), isEmpty, reason: 'the watchlist row still references the show');
  });
}
