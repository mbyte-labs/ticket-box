import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/show_progress_order_by.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/common/model/up_next_to_watch_order_by.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';

import '../../../service/catalog/catalog_test_support.dart';

/// Progress is derived at query time from `episodes`, `history_items` and `show_states`. The aired
/// predicate is `season > 0 AND air_date IS NOT NULL AND air_date <= today`, every count is per
/// episode (never per play), and specials only ever count for "any play" / "last watched".
void main() {
  late DatabaseConnectionManager db;
  late ShowProgressQueries queries;

  // Pinned "today": 15 June 2026.
  final now = DateTime(2026, 6, 15, 12);
  const show = 10;

  setUp(() {
    db = openTestDatabase();
    queries = ShowProgressQueries();
  });

  tearDown(() => closeTestDatabase(db));

  /// S0E1 special, S1E1/E2 aired, S1E3 airs today, S1E4 tomorrow, S1E5 undated.
  Future<void> seedCatalogue() async {
    await seedShow(show, title: 'Alpha');
    await seedEpisode(show, 0, 1, airDate: '2026-01-01');
    await seedEpisode(show, 1, 1, airDate: '2026-06-01');
    await seedEpisode(show, 1, 2, airDate: '2026-06-10');
    await seedEpisode(show, 1, 3, airDate: '2026-06-15');
    await seedEpisode(show, 1, 4, airDate: '2026-06-16');
    await seedEpisode(show, 1, 5);
  }

  group('showCounts', () {
    test('today counts as aired, tomorrow and an undated episode do not, specials never', () async {
      await seedCatalogue();

      final counts = await queries.showCounts(show, now: now);

      expect(counts.aired, 3);
      expect(counts.total, 5, reason: 'specials are not part of the show total');
      expect(counts.watched, 0);
      expect(counts.anyPlay, isFalse);
      expect(counts.lastWatchedAt, isNull);
      expect(counts.isComplete, isFalse);
    });

    test('three plays of one episode read as one watched episode', () async {
      await seedCatalogue();
      for (final day in [2, 3, 4]) {
        await playEpisode(show, 1, 1, at: DateTime.utc(2026, 6, day));
      }

      final counts = await queries.showCounts(show, now: now);

      expect(counts.watchedAired, 1);
      expect(counts.watched, 1);
      expect(counts.anyPlay, isTrue);
      expect(counts.lastWatchedAt?.toUtc(), DateTime.utc(2026, 6, 4));
    });

    test('a watched special counts for anyPlay and lastWatchedAt but for no episode count', () async {
      await seedCatalogue();
      await playEpisode(show, 0, 1, at: DateTime.utc(2026, 6, 5));

      final counts = await queries.showCounts(show, now: now);

      expect(counts.anyPlay, isTrue);
      expect(counts.lastWatchedAt?.toUtc(), DateTime.utc(2026, 6, 5));
      expect(counts.watched, 0);
      expect(counts.watchedAired, 0);
      expect(counts.isComplete, isFalse);
    });

    test('a play of an unaired episode is watched but not watchedAired', () async {
      await seedCatalogue();
      await playEpisode(show, 1, 4);

      final counts = await queries.showCounts(show, now: now);

      expect(counts.watched, 1);
      expect(counts.watchedAired, 0);
    });

    test('isComplete once every aired episode has a play, whatever is still to come', () async {
      await seedCatalogue();
      for (final e in [1, 2, 3]) {
        await playEpisode(show, 1, e);
      }

      expect((await queries.showCounts(show, now: now)).isComplete, isTrue);
      // The day after, S1E4 has aired and the show is open again.
      expect((await queries.showCounts(show, now: now.add(const Duration(days: 1)))).isComplete, isFalse);
    });

    test('a show with nothing aired is never complete', () async {
      await seedShow(show);
      await seedEpisode(show, 1, 1);

      expect((await queries.showCounts(show, now: now)).isComplete, isFalse);
      expect(await queries.showCounts(99, now: now), isA<ShowCounts>().having((c) => c.total, 'total', 0));
    });
  });

  group('seasonCounts', () {
    test('specials count their own episodes for display', () async {
      await seedCatalogue();
      await playEpisode(show, 0, 1);
      await playEpisode(show, 1, 2);

      final counts = await queries.seasonCounts(show, now: now);

      expect(counts.keys, [0, 1]);
      expect((counts[0]!.aired, counts[0]!.watchedAired, counts[0]!.watched, counts[0]!.total), (1, 1, 1, 1));
      expect((counts[1]!.aired, counts[1]!.watchedAired, counts[1]!.watched, counts[1]!.total), (3, 1, 1, 5));
    });

    test('a season without episode rows is absent', () async {
      await seedShow(show);
      await seedSeason(show, 1);

      expect(await queries.seasonCounts(show, now: now), isEmpty);
    });
  });

  group('nextEpisode', () {
    test('no plays means no next episode', () async {
      await seedCatalogue();

      expect(await queries.nextEpisode(show, NextEpisodeMode.afterLatestAiredWatched, now: now), isNull);
      expect(await queries.nextEpisode(show, NextEpisodeMode.afterMostRecentlyWatched, now: now), isNull);
    });

    test('after S1E2 the answer is S1E3, never S1E1, in both modes', () async {
      await seedCatalogue();
      await playEpisode(show, 1, 2);

      for (final mode in NextEpisodeMode.values) {
        final next = await queries.nextEpisode(show, mode, now: now);
        expect((next!.season, next.episode), (1, 3), reason: mode.name);
        expect(next.aired, isTrue);
        expect(next.title, 'S1E3');
        expect(next.airDate, '2026-06-15');
      }
    });

    test('afterLatestAiredWatched skips a gap earlier in the show', () async {
      await seedCatalogue();
      await playEpisode(show, 1, 1, at: DateTime.utc(2026, 6, 2));
      await playEpisode(show, 1, 3, at: DateTime.utc(2026, 6, 3));

      final next = await queries.nextEpisode(show, NextEpisodeMode.afterLatestAiredWatched, now: now);

      expect((next!.season, next.episode), (1, 4));
      expect(next.aired, isFalse, reason: 'S1E4 airs tomorrow; it is still the pick, flagged unaired');
    });

    test('afterMostRecentlyWatched continues from the most recent play', () async {
      await seedCatalogue();
      await playEpisode(show, 1, 3, at: DateTime.utc(2026, 6, 2));
      await playEpisode(show, 1, 1, at: DateTime.utc(2026, 6, 3));

      final next = await queries.nextEpisode(show, NextEpisodeMode.afterMostRecentlyWatched, now: now);

      expect((next!.season, next.episode), (1, 2));
      expect((await queries.nextEpisode(show, NextEpisodeMode.afterLatestAiredWatched, now: now))!.episode, 4);
    });

    test('afterMostRecentlyWatched breaks a tie on watched_at by position', () async {
      await seedCatalogue();
      final instant = DateTime.utc(2026, 6, 2);
      await playEpisode(show, 1, 3, at: instant);
      await playEpisode(show, 1, 1, at: instant);

      final next = await queries.nextEpisode(show, NextEpisodeMode.afterMostRecentlyWatched, now: now);

      expect((next!.season, next.episode), (1, 4));
    });

    test('a finished show has none; a special play alone anchors nothing', () async {
      await seedCatalogue();
      await playEpisode(show, 0, 1);
      expect(await queries.nextEpisode(show, NextEpisodeMode.afterLatestAiredWatched, now: now), isNull);

      for (final e in [1, 2, 3, 4, 5]) {
        await playEpisode(show, 1, e);
      }
      expect(await queries.nextEpisode(show, NextEpisodeMode.afterLatestAiredWatched, now: now), isNull);
      expect(await queries.nextEpisode(show, NextEpisodeMode.afterMostRecentlyWatched, now: now), isNull);
    });
  });

  group('upNext and listing', () {
    /// Alpha: next aired; Beta: dropped; Gamma: finished; Delta: next unaired; Epsilon: next
    /// undated; Zeta: followed with nothing aired.
    Future<void> seedLibrary() async {
      await seedShow(10, title: 'Alpha', posterPath: '/alpha.jpg');
      await seedSeason(10, 1, posterPath: '/alpha-s1.jpg');
      await seedEpisode(10, 1, 1, airDate: '2026-06-01');
      await seedEpisode(10, 1, 2, airDate: '2026-06-10', title: 'Alpha two');
      await seedEpisode(10, 1, 3, airDate: '2026-06-20');
      await playEpisode(10, 1, 1, at: DateTime.utc(2026, 6, 2));
      await seedState(10, ShowWatchStatus.watching);

      await seedShow(20, title: 'Beta');
      await seedEpisode(20, 1, 1, airDate: '2026-05-01');
      await seedEpisode(20, 1, 2, airDate: '2026-05-08');
      await playEpisode(20, 1, 1, at: DateTime.utc(2026, 6, 5));
      await seedState(20, ShowWatchStatus.dropped);

      await seedShow(30, title: 'Gamma');
      await seedEpisode(30, 1, 1, airDate: '2026-05-01');
      await seedEpisode(30, 1, 2, airDate: '2026-05-02');
      await playEpisode(30, 1, 1, at: DateTime.utc(2026, 6, 1));
      await playEpisode(30, 1, 2, at: DateTime.utc(2026, 6, 3));
      await seedState(30, ShowWatchStatus.watched);

      await seedShow(40, title: 'Delta');
      await seedEpisode(40, 1, 1, airDate: '2026-06-01');
      await seedEpisode(40, 1, 2, airDate: '2026-06-30');
      await playEpisode(40, 1, 1, at: DateTime.utc(2026, 6, 4));
      await seedState(40, ShowWatchStatus.watching);

      await seedShow(50, title: 'Epsilon');
      await seedEpisode(50, 1, 1, airDate: '2026-06-01');
      await seedEpisode(50, 1, 2);
      await playEpisode(50, 1, 1, at: DateTime.utc(2026, 6, 6));
      await seedState(50, ShowWatchStatus.watching);

      await seedShow(60, title: 'Zeta');
      await seedEpisode(60, 1, 1);
      await seedState(60, ShowWatchStatus.watching);
    }

    Future<List<UpNextRow>> upNext({
      bool onlyWithReleaseDate = false,
      bool displayAiredOnly = false,
      UpNextToWatchOrderBy orderBy = UpNextToWatchOrderBy.showName,
      OrderType orderType = OrderType.ascending,
      NextEpisodeMode mode = NextEpisodeMode.afterLatestAiredWatched,
    }) {
      return queries.upNext(
        onlyWithReleaseDate: onlyWithReleaseDate,
        displayAiredOnly: displayAiredOnly,
        orderBy: orderBy,
        orderType: orderType,
        mode: mode,
        now: now,
      );
    }

    test('one row per followed show with a next episode; dropped and finished shows are absent', () async {
      await seedLibrary();

      final rows = await upNext();

      expect(rows.map((r) => r.next.showTmdbId), [10, 40, 50]);
      final alpha = rows.first;
      expect((alpha.next.season, alpha.next.episode), (1, 2));
      expect(alpha.next.title, 'Alpha two');
      expect(alpha.next.aired, isTrue);
      expect(alpha.showTitle, 'Alpha');
      expect(alpha.showPosterPath, '/alpha.jpg');
      expect(alpha.seasonPosterPath, '/alpha-s1.jpg');
      expect(alpha.lastWatchedAt?.toUtc(), DateTime.utc(2026, 6, 2));
      expect(rows[1].seasonPosterPath, isNull, reason: 'the raw season value, no fallback to the show poster');
      expect(rows[1].next.aired, isFalse);
      expect(rows[2].next.airDate, isNull);
    });

    test('displayAiredOnly keeps aired next episodes; onlyWithReleaseDate keeps dated ones', () async {
      await seedLibrary();

      expect((await upNext(displayAiredOnly: true)).map((r) => r.next.showTmdbId), [10]);
      expect((await upNext(onlyWithReleaseDate: true)).map((r) => r.next.showTmdbId), [10, 40]);
      expect((await upNext(onlyWithReleaseDate: true, displayAiredOnly: true)).map((r) => r.next.showTmdbId), [10]);
    });

    test('orders by last watched, show name and release date in both directions', () async {
      await seedLibrary();

      Future<List<int>> ids(UpNextToWatchOrderBy by, OrderType type, {bool dated = false}) async {
        return (await upNext(orderBy: by, orderType: type, onlyWithReleaseDate: dated)).map((r) => r.next.showTmdbId).toList();
      }

      expect(await ids(UpNextToWatchOrderBy.lastWatched, OrderType.ascending), [10, 40, 50]);
      expect(await ids(UpNextToWatchOrderBy.lastWatched, OrderType.descending), [50, 40, 10]);
      expect(await ids(UpNextToWatchOrderBy.showName, OrderType.ascending), [10, 40, 50]);
      expect(await ids(UpNextToWatchOrderBy.showName, OrderType.descending), [50, 40, 10]);
      expect(await ids(UpNextToWatchOrderBy.episodeReleaseDate, OrderType.ascending, dated: true), [10, 40]);
      expect(await ids(UpNextToWatchOrderBy.episodeReleaseDate, OrderType.descending, dated: true), [40, 10]);
    });

    test('the most-recently-watched mode moves the pointer per show', () async {
      await seedLibrary();
      // Alpha: S1E3 watched later than S1E1 — latest-aired continues after E3, recent after E3 too;
      // make E1 the most recent instead so the two modes differ.
      await playEpisode(10, 1, 3, at: DateTime.utc(2026, 6, 7));
      await playEpisode(10, 1, 1, at: DateTime.utc(2026, 6, 8));

      final latest = await upNext();
      final recent = await upNext(mode: NextEpisodeMode.afterMostRecentlyWatched);

      expect(latest.map((r) => r.next.showTmdbId), [40, 50], reason: 'nothing after S1E3 for Alpha');
      expect(recent.firstWhere((r) => r.next.showTmdbId == 10).next.episode, 2);
    });

    test('listing has every non-dropped state row with aired and completed counts', () async {
      await seedLibrary();

      final items = await queries.listing(
        hideCompleted: false,
        orderBy: ShowProgressOrderBy.showName,
        orderType: OrderType.ascending,
        now: now,
      );

      expect(items.map((i) => i.showTmdbId), [10, 40, 50, 30, 60]);
      expect(items.map((i) => (i.aired, i.completed)), [(2, 1), (1, 1), (1, 1), (2, 2), (0, 0)]);
      expect(items.first.title, 'Alpha');
      expect(items.first.posterPath, '/alpha.jpg');
      expect(items.first.status, ShowWatchStatus.watching);
      expect(items.first.lastWatchedAt?.toUtc(), DateTime.utc(2026, 6, 2));
      expect(items.last.lastWatchedAt, isNull);
    });

    test('hideCompleted leaves out completed shows but keeps ones with nothing aired', () async {
      await seedLibrary();

      final items = await queries.listing(
        hideCompleted: true,
        orderBy: ShowProgressOrderBy.showName,
        orderType: OrderType.ascending,
        now: now,
      );

      expect(items.map((i) => i.showTmdbId), [10, 60]);
    });

    test('progress ordering ranks by completed / aired, ties by title', () async {
      await seedLibrary();

      Future<List<int>> ids(OrderType type) async {
        final items = await queries.listing(hideCompleted: false, orderBy: ShowProgressOrderBy.progress, orderType: type, now: now);
        return items.map((i) => i.showTmdbId).toList();
      }

      expect(await ids(OrderType.ascending), [60, 10, 40, 50, 30]);
      expect(await ids(OrderType.descending), [40, 50, 30, 10, 60]);
    });

    test('last watched ordering', () async {
      await seedLibrary();

      final items = await queries.listing(
        hideCompleted: false,
        orderBy: ShowProgressOrderBy.lastWatched,
        orderType: OrderType.descending,
        now: now,
      );

      expect(items.map((i) => i.showTmdbId).take(3), [50, 40, 30]);
    });
  });
}
