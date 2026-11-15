import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_list_item.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/service/stats/stats_calculator.dart';
import 'package:ticketbox/service/stats/stats_models.dart';

/// The time based rules all bucket by *local* date, so the fixtures are built from local
/// [DateTime]s converted with `toUtc()` - that way the expectations hold in whatever timezone
/// the test machine runs.
void main() {
  (ItemType, DateTime) play(DateTime local) => (ItemType.episode, local.toUtc());

  UserRatingEntity rating(ItemType type, int value) {
    return UserRatingEntity.build(type: type, tmdbId: 1, rating: value, ratedAt: DateTime.utc(2026, 7, 1));
  }

  WatchedAggregate watched(ItemType type, int tmdbId, int plays, DateTime lastWatchedAt) {
    return WatchedAggregate(type: type, tmdbId: tmdbId, plays: plays, lastWatchedAt: lastWatchedAt);
  }

  ShowProgressListItem progress(int id, int aired, int completed) {
    return ShowProgressListItem(
      showTmdbId: id,
      title: 'Show $id',
      posterPath: null,
      status: ShowWatchStatus.watching,
      aired: aired,
      completed: completed,
      lastWatchedAt: null,
    );
  }

  ShowEntity summary(int tmdbId, String genres, {double voteAverage = 8.0, int voteCount = 100}) {
    return ShowEntity.build(
      tmdbId: tmdbId,
      imdbId: null,
      title: 'Show $tmdbId',
      year: 2020,
      overview: null,
      tagline: null,
      firstAirDate: null,
      lastAirDate: null,
      runtime: 40,
      certification: null,
      network: null,
      country: null,
      language: null,
      trailer: null,
      homepage: null,
      voteAverage: voteAverage,
      voteCount: voteCount,
      popularity: 10,
      numberOfSeasons: 1,
      nextEpisodeAirDate: null,
      nextEpisodeSeason: null,
      nextEpisodeNumber: null,
      genres: genres,
      status: null,
      posterPath: null,
      backdropPath: null,
      fetchedAt: DateTime.utc(2026, 7, 1),
      trackedAt: DateTime.utc(2026, 7, 1),
      watchProvidersRegion: null,
    );
  }

  MovieEntity movieSummary(int tmdbId, double voteAverage, {int voteCount = 1000}) {
    return MovieEntity.build(
      tmdbId: tmdbId,
      imdbId: null,
      title: 'Movie $tmdbId',
      year: 2020,
      overview: null,
      tagline: null,
      releaseDate: null,
      runtime: 120,
      certification: null,
      country: null,
      language: null,
      trailer: null,
      homepage: null,
      voteAverage: voteAverage,
      voteCount: voteCount,
      popularity: 10,
      genres: '',
      status: null,
      posterPath: null,
      backdropPath: null,
      fetchedAt: DateTime.utc(2026, 7, 1),
      trackedAt: DateTime.utc(2026, 7, 1),
      watchProvidersRegion: null,
    );
  }

  group('monthlyBuckets', () {
    test('returns 12 zero-filled buckets ending with the current month', () {
      final now = DateTime(2026, 7, 15);
      final buckets = StatsCalculator.monthlyBuckets([], now);

      expect(buckets, hasLength(12));
      expect((buckets.first.year, buckets.first.month), (2025, 8));
      expect((buckets.last.year, buckets.last.month), (2026, 7));
      expect(buckets.every((bucket) => bucket.plays == 0), isTrue);
    });

    test('counts plays per local month and drops older ones', () {
      final now = DateTime(2026, 7, 15);
      final buckets = StatsCalculator.monthlyBuckets([
        play(DateTime(2026, 7, 1)),
        play(DateTime(2026, 7, 20)),
        play(DateTime(2025, 8, 5)),
        // Just outside the window - must not surface anywhere.
        play(DateTime(2025, 7, 31)),
      ], now);

      expect(buckets.last.plays, 2);
      expect(buckets.first.plays, 1);
      expect(buckets.fold(0, (sum, bucket) => sum + bucket.plays), 3);
    });
  });

  group('weekdayPlays', () {
    test('is seven zeros without history', () {
      expect(StatsCalculator.weekdayPlays([]), [0, 0, 0, 0, 0, 0, 0]);
    });

    test('counts plays per local weekday, Monday first', () {
      // 2026-07-06 is a Monday, 2026-07-07 a Tuesday, 2026-07-12 a Sunday.
      final result = StatsCalculator.weekdayPlays([
        play(DateTime(2026, 7, 7, 20)),
        play(DateTime(2026, 7, 14, 20)),
        play(DateTime(2026, 7, 6, 20)),
        play(DateTime(2026, 7, 12, 23, 30)),
      ]);

      expect(result, [1, 2, 0, 0, 0, 0, 1]);
    });

    test('keeps the synthetic midnight plays', () {
      expect(StatsCalculator.weekdayPlays([play(DateTime(2026, 7, 6))]), [1, 0, 0, 0, 0, 0, 0]);
    });
  });

  group('timeOfDay', () {
    test('is null without history', () {
      expect(StatsCalculator.timeOfDay([]), isNull);
    });

    test('is null when every play sits at exactly local midnight', () {
      expect(StatsCalculator.timeOfDay([play(DateTime(2026, 7, 6)), play(DateTime(2026, 7, 7))]), isNull);
    });

    test('buckets the boundary hours into the right part of the day', () {
      DayPart partOf(DateTime local) => DayPart.values[StatsCalculator.timeOfDay([play(local)])!.plays.indexOf(1)];

      expect(partOf(DateTime(2026, 7, 6, 4, 59)), DayPart.night);
      expect(partOf(DateTime(2026, 7, 6, 5)), DayPart.morning);
      expect(partOf(DateTime(2026, 7, 6, 11, 59)), DayPart.morning);
      expect(partOf(DateTime(2026, 7, 6, 12)), DayPart.afternoon);
      expect(partOf(DateTime(2026, 7, 6, 16, 59)), DayPart.afternoon);
      expect(partOf(DateTime(2026, 7, 6, 17)), DayPart.evening);
      expect(partOf(DateTime(2026, 7, 6, 21, 59)), DayPart.evening);
      expect(partOf(DateTime(2026, 7, 6, 22)), DayPart.night);
      // Only the exact midnight is synthetic - a second later is a real night play.
      expect(partOf(DateTime(2026, 7, 6, 0, 0, 1)), DayPart.night);
    });

    test('leaves the midnight plays out of the counts and the shares', () {
      final result = StatsCalculator.timeOfDay([
        play(DateTime(2026, 7, 6)),
        play(DateTime(2026, 7, 6, 23)),
        play(DateTime(2026, 7, 7, 1)),
        play(DateTime(2026, 7, 7, 20)),
        play(DateTime(2026, 7, 8, 9)),
      ])!;

      expect(result.plays, [1, 0, 1, 2]);
      expect(result.total, 4);
      expect(result.dominant, DayPart.night);
      expect(result.share(DayPart.night), 0.5);
      expect(result.share(DayPart.afternoon), 0);
    });

    test('a tie goes to the earlier part of the day', () {
      final result = StatsCalculator.timeOfDay([play(DateTime(2026, 7, 6, 23)), play(DateTime(2026, 7, 6, 19))])!;

      expect(result.dominant, DayPart.evening);
    });
  });

  group('streaks', () {
    final now = DateTime(2026, 7, 31, 12);

    test('is (0, 0) without history', () {
      expect(StatsCalculator.streaks([], now), (0, 0));
    });

    test('a gap breaks the run and several plays on one day count once', () {
      final (longest, current) = StatsCalculator.streaks([
        play(DateTime(2026, 7, 1, 20)),
        play(DateTime(2026, 7, 2, 9)),
        play(DateTime(2026, 7, 2, 22)),
        play(DateTime(2026, 7, 3, 20)),
        // Gap - the streak restarts here.
        play(DateTime(2026, 7, 10, 20)),
      ], now);

      expect(longest, 3);
      expect(current, 0);
    });

    test('the current streak still counts when the last play was yesterday', () {
      final (longest, current) = StatsCalculator.streaks([play(DateTime(2026, 7, 29, 21)), play(DateTime(2026, 7, 30, 21))], now);

      expect(longest, 2);
      expect(current, 2);
    });

    test('two instants either side of local midnight land on two consecutive days', () {
      final (longest, _) = StatsCalculator.streaks([play(DateTime(2026, 7, 1, 23, 30)), play(DateTime(2026, 7, 2, 0, 30))], now);

      expect(longest, 2);
    });
  });

  group('dailyPlays', () {
    final now = DateTime(2026, 7, 31, 12);

    test('is a year of zeros ending today without history', () {
      final daily = StatsCalculator.dailyPlays([], now);

      expect(daily.plays, hasLength(DailyPlays.days));
      expect(daily.plays.every((count) => count == 0), isTrue);
      expect(daily.start, DateTime(2025, 8, 1));
      expect(daily.day(DailyPlays.days - 1), DateTime(2026, 7, 31));
    });

    test('several plays on one day add up', () {
      final daily = StatsCalculator.dailyPlays([
        play(DateTime(2026, 7, 30, 9)),
        play(DateTime(2026, 7, 30, 21)),
        play(DateTime(2026, 7, 30, 22)),
        play(DateTime(2026, 7, 31, 8)),
      ], now);

      expect(daily.plays[DailyPlays.days - 2], 3);
      expect(daily.plays[DailyPlays.days - 1], 1);
      expect(daily.total, 4);
      expect(daily.activeDays, 2);
    });

    test('two instants either side of local midnight land on consecutive days', () {
      final daily = StatsCalculator.dailyPlays([play(DateTime(2026, 7, 1, 23, 30)), play(DateTime(2026, 7, 2, 0, 30))], now);

      final july1 = (DateTime(2026, 7, 1).difference(daily.start).inHours / 24).round();
      expect(daily.day(july1), DateTime(2026, 7, 1));
      expect(daily.plays[july1], 1);
      expect(daily.plays[july1 + 1], 1);
    });

    test('plays before the window or after today are left out', () {
      final daily = StatsCalculator.dailyPlays([
        play(DateTime(2025, 7, 31, 20)),
        play(DateTime(2025, 8, 1, 20)),
        play(DateTime(2026, 8, 1, 20)),
      ], now);

      expect(daily.total, 1);
      expect(daily.plays.first, 1);
    });

    DailyPlays withCounts(List<int> counts) =>
        DailyPlays(start: DateTime(2025, 8, 1), plays: [...counts, ...List.filled(DailyPlays.days - counts.length, 0)]);

    test('shades are all 0 without plays', () {
      expect(withCounts([]).shades().every((shade) => shade == 0), isTrue);
    });

    test('shades follow the quartiles of the active days, so one huge import day does not wash out the rest', () {
      final shades = withCounts([0, 1, 1, 1, 2, 2, 3, 5, 23, 15830]).shades();

      expect(shades.take(10), [0, 1, 1, 1, 2, 2, 3, 3, 4, 4]);
    });

    test('the busiest day always gets the top shade, also when every active day ties', () {
      expect(withCounts([1, 0, 1]).shades().take(3), [DailyPlays.levels, 0, DailyPlays.levels]);
    });
  });

  group('firstWatchAndDaysTracked', () {
    test('is (null, 0) without history', () {
      expect(StatsCalculator.firstWatchAndDaysTracked([], DateTime(2026, 7, 31)), (null, 0));
    });

    test('finds the oldest play and counts the days since', () {
      final (first, days) = StatsCalculator.firstWatchAndDaysTracked([
        play(DateTime(2026, 7, 20, 21)),
        play(DateTime(2026, 7, 1, 21)),
      ], DateTime(2026, 7, 31, 8));

      expect(first, DateTime(2026, 7, 1, 21));
      expect(days, 30);
    });

    test('a first watch today still counts as one day', () {
      final (_, days) = StatsCalculator.firstWatchAndDaysTracked([play(DateTime(2026, 7, 31, 8))], DateTime(2026, 7, 31, 20));

      expect(days, 1);
    });
  });

  group('ratingsGiven', () {
    test('is null without ratings', () {
      expect(StatsCalculator.ratingsGiven([]), isNull);
    });

    test('averages overall and per type, absent types stay null', () {
      final result = StatsCalculator.ratingsGiven([rating(ItemType.movie, 6), rating(ItemType.movie, 8), rating(ItemType.episode, 10)])!;

      expect(result.total, 3);
      expect(result.average, closeTo(8.0, 0.001));
      expect(result.movieAverage, closeTo(7.0, 0.001));
      expect(result.episodeAverage, closeTo(10.0, 0.001));
      expect(result.showAverage, isNull);
    });

    test('season ratings count toward the total', () {
      expect(StatsCalculator.ratingsGiven([rating(ItemType.season, 5)])!.total, 1);
    });
  });

  group('topRewatched', () {
    test('keeps only items with more than one play, most plays first', () {
      final result = StatsCalculator.topRewatched([
        watched(ItemType.movie, 1, 1, DateTime.utc(2026, 7, 1)),
        watched(ItemType.movie, 2, 3, DateTime.utc(2026, 7, 1)),
        watched(ItemType.show, 3, 5, DateTime.utc(2026, 7, 1)),
        watched(ItemType.movie, 4, 2, DateTime.utc(2026, 7, 1)),
      ]);

      expect(result.map((item) => item.tmdbId), [3, 2, 4]);
      expect(result.first.plays, 5);
    });

    test('ties go to the more recently watched item and the list is capped', () {
      final result = StatsCalculator.topRewatched([
        watched(ItemType.movie, 1, 2, DateTime.utc(2026, 6, 1)),
        watched(ItemType.movie, 2, 2, DateTime.utc(2026, 7, 1)),
      ], limit: 1);

      expect(result.single.tmdbId, 2);
    });
  });

  group('completion', () {
    test('splits tracked shows into completed and in progress and averages the ratios', () {
      final result = StatsCalculator.completion([progress(1, 10, 10), progress(2, 10, 5), progress(3, 8, 0)]);

      expect(result.tracked, 3);
      expect(result.completed, 1);
      expect(result.inProgress, 2);
      expect(result.averageCompletion, closeTo(0.5, 0.001));
    });

    test('a show without a synced summary stays out of the mean instead of dividing by zero', () {
      final result = StatsCalculator.completion([progress(1, 0, 3), progress(2, 10, 10)]);

      expect(result.averageCompletion, closeTo(1.0, 0.001));
      // Without an aired count the show cannot be called completed either.
      expect(result.completed, 1);
    });

    test('is all zeros without tracked shows', () {
      final result = StatsCalculator.completion([]);

      expect(result.tracked, 0);
      expect(result.averageCompletion, 0);
    });
  });

  group('topGenres', () {
    const idToName = {18: 'Drama', 35: 'Comedy'};

    test('is null when too few tracked shows have a synced summary', () {
      expect(StatsCalculator.topGenres([summary(1, '18')], idToName, 10), isNull);
    });

    test('is null without tracked shows', () {
      expect(StatsCalculator.topGenres([], idToName, 0), isNull);
    });

    test('is null when the covered summaries list no genres at all', () {
      expect(StatsCalculator.topGenres([summary(1, '')], idToName, 1), isNull);
    });

    test('counts genres, resolves names and falls back to a generic label for unknown ids', () {
      final result = StatsCalculator.topGenres([summary(1, '18,35'), summary(2, '18'), summary(3, '10765')], idToName, 4)!;

      expect(result.top.map((genre) => genre.name), ['Drama', 'Comedy', 'Genre 10765']);
      expect(result.top.first.count, 2);
      expect(result.coveredShows, 3);
      expect(result.totalShows, 4);
    });

    test('ties are ordered by id so the chart is stable', () {
      final result = StatsCalculator.topGenres([summary(1, '35,18')], idToName, 1)!;

      expect(result.top.map((genre) => genre.name), ['Drama', 'Comedy']);
    });

    test('the list is capped at the limit', () {
      final result = StatsCalculator.topGenres([summary(1, '1,2,3,4,5,6,7')], const {}, 1, limit: 3)!;

      expect(result.top, hasLength(3));
    });
  });

  group('distributionFromRatings', () {
    test('is null without ratings', () {
      expect(StatsCalculator.distributionFromRatings([]), isNull);
    });

    test('counts each value into its 1..10 bucket, index 0 being rating 1', () {
      final result = StatsCalculator.distributionFromRatings([
        rating(ItemType.movie, 1),
        rating(ItemType.movie, 10),
        rating(ItemType.show, 10),
        rating(ItemType.episode, 7),
      ])!;

      expect(result, hasLength(10));
      expect(result[0], 1);
      expect(result[6], 1);
      expect(result[9], 2);
      expect(result.fold(0, (sum, count) => sum + count), 4);
    });

    test('an out of range value is ignored rather than crashing', () {
      final result = StatsCalculator.distributionFromRatings([
        rating(ItemType.movie, 0),
        rating(ItemType.movie, 11),
        rating(ItemType.movie, 5),
      ])!;

      expect(result.fold(0, (sum, count) => sum + count), 1);
      expect(result[4], 1);
    });
  });

  group('HeadlineStats.tvShare', () {
    HeadlineStats headline(int movieMinutes, int episodeMinutes) {
      return HeadlineStats(
        hoursWatched: (movieMinutes + episodeMinutes) ~/ 60,
        movieMinutes: movieMinutes,
        episodeMinutes: episodeMinutes,
        moviesWatched: 0,
        episodesWatched: 0,
        totalPlays: 1,
      );
    }

    test('is null when no play has a cached runtime', () {
      expect(headline(0, 0).tvShare, isNull);
    });

    test('is the episode share of the watched minutes', () {
      expect(headline(38, 62).tvShare, closeTo(0.62, 1e-9));
    });

    test('covers the one-sided libraries', () {
      expect(headline(120, 0).tvShare, 0);
      expect(headline(0, 45).tvShare, 1);
    });
  });

  group('decades', () {
    final synced = DateTime.utc(2026, 7, 1);
    final lastWeek = DateTime.utc(2026, 6, 24);

    MovieEntity movie(int tmdbId, int? year) => MovieEntity.stub(tmdbId: tmdbId, trackedAt: synced, title: 'Movie $tmdbId')..year = year;

    ShowEntity show(int tmdbId, int? year) => ShowEntity.stub(tmdbId: tmdbId, trackedAt: synced, title: 'Show $tmdbId')..year = year;

    test('is null without a single known year', () {
      expect(StatsCalculator.decades([], {}, {}), isNull);
      expect(
        StatsCalculator.decades([watched(ItemType.movie, 1, 1, lastWeek), watched(ItemType.show, 2, 3, lastWeek)], {1: movie(1, null)}, {}),
        isNull,
      );
    });

    test('fills the decades between the oldest and the newest with zero', () {
      final result = StatsCalculator.decades(
        [watched(ItemType.movie, 1, 1, lastWeek), watched(ItemType.show, 2, 1, lastWeek), watched(ItemType.movie, 3, 1, lastWeek)],
        {1: movie(1, 1974), 3: movie(3, 2003)},
        {2: show(2, 2009)},
      )!;

      expect(result.decades.map((decade) => decade.decade), [1970, 1980, 1990, 2000]);
      expect(result.decades.map((decade) => decade.titles), [1, 0, 0, 2]);
      expect(result.favorite.decade, 2000);
      expect(result.share(result.favorite), closeTo(2 / 3, 1e-9));
    });

    test('splits 1999 and 2000 into their own decades', () {
      final result = StatsCalculator.decades(
        [watched(ItemType.movie, 1, 1, lastWeek), watched(ItemType.movie, 2, 1, lastWeek)],
        {1: movie(1, 1999), 2: movie(2, 2000)},
        {},
      )!;

      expect(result.decades.map((decade) => (decade.decade, decade.titles)), [(1990, 1), (2000, 1)]);
    });

    test('picks the oldest and newest titles across movies and shows', () {
      final result = StatsCalculator.decades(
        [watched(ItemType.movie, 1, 1, lastWeek), watched(ItemType.show, 2, 1, lastWeek), watched(ItemType.movie, 3, 1, lastWeek)],
        {1: movie(1, 1985), 3: movie(3, 2024)},
        {2: show(2, 1959)},
      )!;

      expect((result.oldest.type, result.oldest.tmdbId, result.oldest.title, result.oldest.year), (ItemType.show, 2, 'Show 2', 1959));
      expect((result.newest.type, result.newest.tmdbId, result.newest.year), (ItemType.movie, 3, 2024));
      expect(result.singleTitle, isFalse);
    });

    test('breaks a year tie by plays, then by the most recent watch', () {
      final result = StatsCalculator.decades(
        [
          watched(ItemType.movie, 1, 1, lastWeek),
          watched(ItemType.movie, 2, 4, DateTime.utc(2020)),
          watched(ItemType.movie, 3, 1, DateTime.utc(2026, 6, 30)),
          watched(ItemType.movie, 4, 1, lastWeek),
        ],
        {1: movie(1, 1960), 2: movie(2, 1960), 3: movie(3, 2015), 4: movie(4, 2015)},
        {},
      )!;

      expect(result.oldest.tmdbId, 2);
      expect(result.newest.tmdbId, 3);
    });

    test('counts every watched title but charts only the dated ones', () {
      final result = StatsCalculator.decades(
        [watched(ItemType.movie, 1, 1, lastWeek), watched(ItemType.movie, 2, 1, lastWeek), watched(ItemType.show, 3, 1, lastWeek)],
        {1: movie(1, 1994), 2: movie(2, 0)},
        {},
      )!;

      expect(result.coveredTitles, 1);
      expect(result.totalTitles, 3);
      expect(result.singleTitle, isTrue);
    });
  });

  group('ratingTrend', () {
    final now = DateTime(2026, 10, 8, 12);

    UserRatingEntity ratedAt(ItemType type, int value, DateTime local, [int tmdbId = 1]) {
      return UserRatingEntity.build(type: type, tmdbId: tmdbId, rating: value, ratedAt: local.toUtc());
    }

    test('is null without movie or show ratings', () {
      expect(StatsCalculator.ratingTrend([], now), isNull);
      expect(StatsCalculator.ratingTrend([ratedAt(ItemType.episode, 8, DateTime(2026, 10, 1))], now), isNull);
    });

    test('averages movies and shows per local month, leaving episodes out', () {
      final result = StatsCalculator.ratingTrend([
        ratedAt(ItemType.movie, 8, DateTime(2026, 10, 1, 20)),
        ratedAt(ItemType.show, 6, DateTime(2026, 10, 3, 9), 2),
        ratedAt(ItemType.episode, 1, DateTime(2026, 10, 3, 10)),
        // The last minute of September, local time - must not spill into October.
        ratedAt(ItemType.movie, 9, DateTime(2026, 9, 30, 23, 59), 3),
        // Older than the 12 month window - counts for the comparison only.
        ratedAt(ItemType.movie, 5, DateTime(2025, 1, 15), 4),
      ], now)!;

      expect(result.monthly, hasLength(12));
      expect((result.monthly.first.year, result.monthly.first.month), (2025, 11));
      expect((result.monthly.last.year, result.monthly.last.month), (2026, 10));
      expect(result.monthly.last.count, 2);
      expect(result.monthly.last.average, 7.0);
      expect(result.monthly[10].count, 1);
      expect(result.monthly[10].average, 9.0);
      expect(result.monthly.first.count, 0);
      expect(result.monthly.first.average, isNull);
    });

    test('splits recent and earlier ratings at the window', () {
      final result = StatsCalculator.ratingTrend([
        ratedAt(ItemType.movie, 6, now.subtract(const Duration(days: 10))),
        ratedAt(ItemType.movie, 8, now.subtract(const Duration(days: 89)), 2),
        ratedAt(ItemType.movie, 9, now.subtract(const Duration(days: 91)), 3),
      ], now)!;

      expect(result.recentCount, 2);
      expect(result.recentAverage, 7.0);
      expect(result.earlierCount, 1);
      expect(result.earlierAverage, 9.0);
    });

    test('has no delta until both sides have enough ratings', () {
      final recent = [for (var i = 0; i < 3; i++) ratedAt(ItemType.movie, 5, now.subtract(Duration(days: 5 + i)), 10 + i)];
      final earlier = [for (var i = 0; i < 2; i++) ratedAt(ItemType.movie, 8, now.subtract(Duration(days: 200 + i)), 20 + i)];

      final thin = StatsCalculator.ratingTrend([...recent, ...earlier], now)!;
      expect(thin.delta, isNull);
      expect(thin.trend, isNull);

      final enough = StatsCalculator.ratingTrend([
        ...recent,
        ...earlier,
        ratedAt(ItemType.movie, 8, now.subtract(const Duration(days: 300)), 30),
      ], now)!;
      expect(enough.delta, closeTo(-3, 1e-9));
      expect(enough.trend, RatingTrend.harsher);
    });

    test('classifies the delta as harsher, kinder or steady', () {
      RatingTrend? trendOf(int recent, int earlier) {
        return StatsCalculator.ratingTrend([
          for (var i = 0; i < 3; i++) ratedAt(ItemType.movie, recent, now.subtract(Duration(days: 1 + i)), i),
          for (var i = 0; i < 3; i++) ratedAt(ItemType.show, earlier, now.subtract(Duration(days: 100 + i)), 10 + i),
        ], now)!.trend;
      }

      expect(trendOf(6, 8), RatingTrend.harsher);
      expect(trendOf(8, 6), RatingTrend.kinder);
      expect(trendOf(7, 7), RatingTrend.steady);
    });
  });

  group('unratedMovies', () {
    final synced = DateTime.utc(2026, 7, 1);
    final movies = {
      for (final id in [1, 2, 3, 4, 5, 6, 7]) id: MovieEntity.stub(tmdbId: id, trackedAt: synced, title: 'Movie $id')..year = 2000 + id,
    };

    UserRatingEntity rated(ItemType type, int tmdbId) {
      return UserRatingEntity.build(type: type, tmdbId: tmdbId, rating: 7, ratedAt: synced);
    }

    test('is null when every watched movie is rated', () {
      final result = StatsCalculator.unratedMovies(
        [watched(ItemType.movie, 1, 1, DateTime.utc(2026, 1, 1)), watched(ItemType.show, 2, 3, DateTime.utc(2026, 1, 2))],
        [rated(ItemType.movie, 1)],
        movies,
      );
      expect(result, isNull);
    });

    test('lists unrated movies most recently watched first, ignoring shows and other rating types', () {
      final result = StatsCalculator.unratedMovies(
        [
          watched(ItemType.movie, 1, 1, DateTime.utc(2026, 1, 1)),
          watched(ItemType.movie, 2, 1, DateTime.utc(2026, 3, 1)),
          watched(ItemType.movie, 3, 2, DateTime.utc(2026, 2, 1)),
          watched(ItemType.show, 4, 5, DateTime.utc(2026, 4, 1)),
        ],
        // A show rating with a movie's id must not count as rating the movie.
        [rated(ItemType.movie, 3), rated(ItemType.show, 1)],
        movies,
      )!;

      expect(result.total, 2);
      expect(result.recent.map((movie) => movie.tmdbId), [2, 1]);
      expect(result.recent.first.title, 'Movie 2');
      expect(result.recent.first.year, 2002);
      expect(result.recent.first.lastWatchedAt, DateTime.utc(2026, 3, 1));
    });

    test('caps the list but counts every unrated movie', () {
      final result = StatsCalculator.unratedMovies(
        [
          for (final id in [1, 2, 3, 4, 5, 6, 7]) watched(ItemType.movie, id, 1, DateTime.utc(2026, 1, id)),
        ],
        [],
        movies,
        limit: 3,
      )!;

      expect(result.total, 7);
      expect(result.recent.map((movie) => movie.tmdbId), [7, 6, 5]);
    });

    test('breaks ties by id and keeps movies without a library row', () {
      final at = DateTime.utc(2026, 5, 1);
      final result = StatsCalculator.unratedMovies([watched(ItemType.movie, 99, 1, at), watched(ItemType.movie, 2, 1, at)], [], movies)!;

      expect(result.recent.map((movie) => movie.tmdbId), [2, 99]);
      expect(result.recent.last.title, '');
      expect(result.recent.last.year, isNull);
    });
  });

  group('UnratedMovie.watchedAgo', () {
    final now = DateTime(2026, 10, 8, 9);

    String ago(DateTime local) => UnratedMovie(tmdbId: 1, title: '', year: null, lastWatchedAt: local.toUtc()).watchedAgo(now);

    test('counts local calendar days', () {
      expect(ago(DateTime(2026, 10, 8, 0, 30)), 'today');
      // Late last night is yesterday, even though it was less than 24 hours ago.
      expect(ago(DateTime(2026, 10, 7, 23, 50)), 'yesterday');
      expect(ago(DateTime(2026, 10, 5, 12)), '3 days ago');
    });

    test('switches to weeks, months and years', () {
      expect(ago(DateTime(2026, 9, 24)), '2 weeks ago');
      expect(ago(DateTime(2026, 7, 8)), '3 months ago');
      expect(ago(DateTime(2024, 1, 1)), '2 years ago');
    });
  });

  group('crowdComparison', () {
    UserRatingEntity rated(ItemType type, int tmdbId, int value) {
      return UserRatingEntity.build(type: type, tmdbId: tmdbId, rating: value, ratedAt: DateTime.utc(2026, 7, 1));
    }

    /// Five movies rated 8 against a crowd average of 7, ids 1..5.
    final baseRatings = [for (var id = 1; id <= 5; id++) rated(ItemType.movie, id, 8)];
    final baseMovies = {for (var id = 1; id <= 5; id++) id: movieSummary(id, 7.0)};

    test('returns null below the minimum sample', () {
      expect(StatsCalculator.crowdComparison(baseRatings.take(4).toList(), baseMovies, const {}), isNull);
      expect(StatsCalculator.crowdComparison(const [], const {}, const {}), isNull);
    });

    test('compares movies and shows, ignoring episodes, missing summaries and thin vote counts', () {
      final result = StatsCalculator.crowdComparison(
        [
          ...baseRatings,
          rated(ItemType.show, 10, 6),
          rated(ItemType.episode, 10, 1),
          // No cached summary.
          rated(ItemType.movie, 20, 1),
          // Too few TMDB votes to trust.
          rated(ItemType.movie, 21, 1),
        ],
        {...baseMovies, 21: movieSummary(21, 9.0, voteCount: CrowdComparisonStats.minVoteCount - 1)},
        {10: summary(10, '', voteAverage: 6.5, voteCount: 500)},
      )!;

      expect(result.compared, 6);
      // Episodes never count, the uncompared movies still do.
      expect(result.totalRated, 8);
      expect(result.userAverage, closeTo((5 * 8 + 6) / 6, 1e-9));
      expect(result.crowdAverage, closeTo((5 * 7.0 + 6.5) / 6, 1e-9));
      expect(result.delta, closeTo(result.userAverage - result.crowdAverage, 1e-9));
      expect(result.lovedLess.single.type, ItemType.show);
      expect(result.lovedLess.single.title, 'Show 10');
    });

    test('judges the delta against the in-sync threshold', () {
      CrowdVerdict verdictFor(double crowd) {
        return StatsCalculator.crowdComparison(baseRatings, {
          for (var id = 1; id <= 5; id++) id: movieSummary(id, crowd),
        }, const {})!.verdict;
      }

      expect(verdictFor(7.0), CrowdVerdict.kinder);
      expect(verdictFor(8.4), CrowdVerdict.inSync);
      expect(verdictFor(7.6), CrowdVerdict.inSync);
      expect(verdictFor(9.0), CrowdVerdict.harsher);
    });

    test('ranks the biggest gaps per direction, ties to the better-known title then the lower id', () {
      final ratings = [
        rated(ItemType.movie, 1, 10),
        rated(ItemType.movie, 2, 9),
        rated(ItemType.movie, 3, 9),
        rated(ItemType.movie, 4, 9),
        rated(ItemType.movie, 5, 8),
        rated(ItemType.movie, 6, 2),
        rated(ItemType.movie, 7, 7),
      ];
      final movies = {
        1: movieSummary(1, 5.0),
        // 2..4 share a +3 gap; 3 has the most votes, 2 and 4 tie on votes too.
        2: movieSummary(2, 6.0, voteCount: 500),
        3: movieSummary(3, 6.0, voteCount: 5000),
        4: movieSummary(4, 6.0, voteCount: 500),
        5: movieSummary(5, 7.5),
        6: movieSummary(6, 8.5),
        // Exactly the crowd's opinion: in neither list.
        7: movieSummary(7, 7.0),
      };

      final result = StatsCalculator.crowdComparison(ratings, movies, const {})!;

      expect(result.lovedMore.map((gap) => gap.tmdbId), [1, 3, 2]);
      expect(result.lovedLess.map((gap) => gap.tmdbId), [6]);
      expect(result.lovedLess.single.gap, closeTo(-6.5, 1e-9));
    });
  });

  group('almostThere', () {
    test('keeps only partly watched shows with a synced summary, fewest episodes left first', () {
      final result = StatsCalculator.almostThere([
        progress(1, 10, 10), // complete
        progress(2, 8, 0), // not started
        progress(3, 0, 0), // no synced summary
        progress(4, 10, 5), // 5 left
        progress(5, 12, 11), // 1 left
        progress(6, 20, 17), // 3 left
      ]);

      expect(result.map((show) => show.tmdbId), [5, 6, 4]);
      expect(result.first.left, 1);
      expect(result.first.completion, closeTo(11 / 12, 1e-9));
      expect(result.first.title, 'Show 5');
    });

    test('ties on the episodes left go to the more complete show, then to the lower id, and the list is capped', () {
      final result = StatsCalculator.almostThere([progress(3, 4, 2), progress(2, 10, 8), progress(1, 4, 2), progress(4, 6, 4)], limit: 3);

      expect(result.map((show) => show.tmdbId), [2, 4, 1]);
    });

    test('is empty without partly watched shows', () {
      expect(StatsCalculator.almostThere([progress(1, 10, 10), progress(2, 0, 0), progress(3, 5, 0)]), isEmpty);
    });
  });

  group('mostWatchedShow', () {
    final synced = DateTime.utc(2026, 7, 1);
    final day1 = DateTime.utc(2026, 6, 1);
    final day2 = DateTime.utc(2026, 6, 2);
    final shows = {
      for (final id in [1, 2, 3]) id: ShowEntity.stub(tmdbId: id, trackedAt: synced, title: 'Show $id')..year = 2000,
    };

    test('is null when only movies were watched', () {
      expect(StatsCalculator.mostWatchedShow([watched(ItemType.movie, 1, 9, day1)], {1: 900}, shows), isNull);
    });

    test('ranks by watched minutes rather than by plays, ignoring movies', () {
      final result = StatsCalculator.mostWatchedShow(
        [watched(ItemType.show, 1, 50, day1), watched(ItemType.show, 2, 10, day1), watched(ItemType.movie, 3, 99, day2)],
        {1: 50 * 22, 2: 10 * 60, 3: 99 * 120},
        shows,
      )!;

      expect(result.tmdbId, 1);
      expect(result.minutes, 1100);
      expect(result.hours, 18);
      expect(result.episodePlays, 50);
      expect(result.lastWatchedAt, day1);
      expect(result.title, 'Show 1');
    });

    test('falls back to plays, then recency, then id while no runtime is cached', () {
      final byRecency = StatsCalculator.mostWatchedShow(
        [watched(ItemType.show, 2, 10, day1), watched(ItemType.show, 1, 10, day2), watched(ItemType.show, 3, 4, day2)],
        const {},
        shows,
      )!;
      expect(byRecency.tmdbId, 1);
      expect(byRecency.minutes, 0);

      final byId = StatsCalculator.mostWatchedShow(
        [watched(ItemType.show, 2, 10, day1), watched(ItemType.show, 1, 10, day1)],
        const {},
        const {},
      )!;
      expect(byId.tmdbId, 1);
      expect(byId.title, '');
    });
  });

  group('topRated', () {
    final synced = DateTime.utc(2026, 7, 1);
    final movies = {1: MovieEntity.stub(tmdbId: 1, trackedAt: synced, title: 'Movie 1')..year = 2001};
    final shows = {2: ShowEntity.stub(tmdbId: 2, trackedAt: synced, title: 'Show 2')..year = 2002};

    UserRatingEntity rated(ItemType type, int tmdbId, int rating, DateTime ratedAt, {int season = 0, int episode = 0}) {
      return UserRatingEntity.build(type: type, tmdbId: tmdbId, season: season, episode: episode, rating: rating, ratedAt: ratedAt);
    }

    test('is empty without movie or show ratings', () {
      expect(StatsCalculator.topRated([rated(ItemType.episode, 2, 10, synced, season: 1, episode: 1)], movies, shows), isEmpty);
    });

    test('orders by rating, then by the most recent rating, then by id, leaving episodes out', () {
      final result = StatsCalculator.topRated(
        [
          rated(ItemType.movie, 1, 8, DateTime.utc(2026, 1, 1)),
          rated(ItemType.show, 2, 10, DateTime.utc(2026, 1, 1)),
          rated(ItemType.movie, 3, 10, DateTime.utc(2026, 2, 1)),
          rated(ItemType.show, 4, 10, DateTime.utc(2026, 1, 1)),
          rated(ItemType.episode, 2, 10, DateTime.utc(2026, 3, 1), season: 1, episode: 1),
        ],
        movies,
        shows,
      );

      expect(result.map((title) => (title.type, title.tmdbId)), [
        (ItemType.movie, 3),
        (ItemType.show, 2),
        (ItemType.show, 4),
        (ItemType.movie, 1),
      ]);
      expect(result.first.key, const MediaKey.movie(3));
      expect(result.first.rating, 10);
      expect(result[1].title, 'Show 2');
      expect(result[1].year, 2002);
      // No library row: the title stays on the list with an empty title.
      expect(result[2].title, '');
      expect(result[2].year, isNull);
      expect(result.last.title, 'Movie 1');
    });

    test('the list is capped at the limit', () {
      final result = StatsCalculator.topRated(
        [for (var id = 1; id <= 5; id++) rated(ItemType.movie, id, 11 - id, synced)],
        movies,
        shows,
        limit: 2,
      );

      expect(result.map((title) => title.tmdbId), [1, 2]);
    });
  });

  group('calendar year variants', () {
    test('monthlyBuckets ending with December are January to December of that year', () {
      final monthly = StatsCalculator.monthlyBuckets([
        play(DateTime(2024, 1, 1, 0, 30)),
        play(DateTime(2024, 12, 31, 23, 30)),
        play(DateTime(2024, 6, 15)),
      ], DateTime(2024, 12));

      expect(monthly, hasLength(12));
      expect(monthly.first.year, 2024);
      expect(monthly.first.month, 1);
      expect(monthly.last.month, 12);
      expect(monthly.map((month) => month.plays), [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1]);
    });

    test('dailyPlaysOfYear covers the whole year, 366 buckets in a leap year', () {
      final daily = StatsCalculator.dailyPlaysOfYear([
        play(DateTime(2024, 1, 1, 0, 30)),
        play(DateTime(2024, 2, 29, 20)),
        play(DateTime(2024, 12, 31, 23, 30)),
        play(DateTime(2025, 1, 1, 0, 30)),
      ], 2024);

      expect(daily.start, DateTime(2024, 1, 1));
      expect(daily.plays, hasLength(366));
      expect(daily.day(365), DateTime(2024, 12, 31));
      expect(daily.plays.first, 1);
      expect(daily.plays[31 + 28], 1);
      expect(daily.plays.last, 1);
      expect(daily.total, 3);
    });

    test('dailyPlaysOfYear has 365 buckets in a common year', () {
      expect(StatsCalculator.dailyPlaysOfYear([], 2023).plays, hasLength(365));
    });

    test('ratingTrend buckets by lastMonth but splits the window from now', () {
      UserRatingEntity ratedOn(DateTime local, int value) {
        return UserRatingEntity.build(type: ItemType.movie, tmdbId: local.day, rating: value, ratedAt: local.toUtc());
      }

      final trend = StatsCalculator.ratingTrend(
        [ratedOn(DateTime(2024, 2, 10), 6), ratedOn(DateTime(2024, 11, 10), 8), ratedOn(DateTime(2024, 12, 10), 10)],
        DateTime(2024, 12, 31, 23, 59, 59, 999),
        lastMonth: DateTime(2024, 12),
      )!;

      expect(trend.monthly.first.month, 1);
      expect(trend.monthly.last.month, 12);
      expect(trend.monthly[1].average, 6);
      expect(trend.monthly[10].average, 8);
      expect(trend.monthly[11].average, 10);
      // The last 90 days of 2024 start in early October.
      expect(trend.recentCount, 2);
      expect(trend.earlierCount, 1);
    });
  });
}
