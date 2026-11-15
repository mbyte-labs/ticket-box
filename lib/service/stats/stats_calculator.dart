import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_list_item.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/service/stats/stats_models.dart';

/// Pure aggregation functions behind the stats page. No IO - everything takes the already
/// loaded rows, so each rule is unit testable on its own.
///
/// All the time bucketing (months, days, weekdays, time of day, streaks) converts the stored UTC
/// instants to local time first: a play at 23:30 belongs to the day the user experienced, not
/// to the UTC date it happened to fall on.
class StatsCalculator {
  /// Below this share of tracked shows with a synced summary the genre chart would say more
  /// about what was browsed than about what was watched, so it is not shown at all.
  static const genreCoverageThreshold = 0.3;

  StatsCalculator._();

  /// 12 months of plays, oldest first, ending with [lastMonth]'s month: the last 12 months when
  /// that is now, January to December of a year when it is that year's December. Months without
  /// a play are present with zero so the chart keeps its gaps.
  static List<MonthlyPlays> monthlyBuckets(List<(ItemType, DateTime)> instants, DateTime lastMonth) {
    final counts = <(int, int), int>{};
    for (final (_, instant) in instants) {
      final local = instant.toLocal();
      counts.update((local.year, local.month), (count) => count + 1, ifAbsent: () => 1);
    }

    return List.generate(12, (index) {
      // DateTime normalizes out-of-range months, so month arithmetic is safe: month 0 is
      // December of the previous year.
      final bucket = DateTime(lastMonth.year, lastMonth.month - (11 - index));
      return MonthlyPlays(year: bucket.year, month: bucket.month, plays: counts[(bucket.year, bucket.month)] ?? 0);
    });
  }

  /// Plays per local weekday, exactly 7 buckets, Monday first. All zero without history.
  static List<int> weekdayPlays(List<(ItemType, DateTime)> instants) {
    final counts = List.filled(DateTime.daysPerWeek, 0);
    for (final (_, instant) in instants) {
      counts[instant.toLocal().weekday - 1]++;
    }
    return counts;
  }

  /// Plays per [DayPart], or null when no play has a real time of day.
  ///
  /// Plays at exactly local midnight are left out: "Watched at release" stores the air date at
  /// 00:00:00.000 local (TMDB has dates, not air times), and counting those would make every
  /// such user look like a night owl.
  static TimeOfDayStats? timeOfDay(List<(ItemType, DateTime)> instants) {
    final counts = List.filled(DayPart.values.length, 0);
    var timed = 0;
    for (final (_, instant) in instants) {
      final local = instant.toLocal();
      if (local.hour == 0 && local.minute == 0 && local.second == 0 && local.millisecond == 0) {
        continue;
      }
      counts[DayPart.ofHour(local.hour).index]++;
      timed++;
    }
    return timed == 0 ? null : TimeOfDayStats(plays: counts);
  }

  /// The longest and the current run of consecutive days with at least one play. The current
  /// streak still counts when the last play was yesterday - today just hasn't happened yet.
  static (int longest, int current) streaks(List<(ItemType, DateTime)> instants, DateTime now) {
    if (instants.isEmpty) {
      return (0, 0);
    }

    final days = instants.map((entry) => _localDay(entry.$2)).toSet().toList()..sort();

    var longest = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      run = days[i].difference(days[i - 1]).inDays == 1 ? run + 1 : 1;
      if (run > longest) {
        longest = run;
      }
    }

    final today = DateTime(now.year, now.month, now.day);
    final sinceLastPlay = today.difference(days.last).inDays;
    final current = sinceLastPlay <= 1 ? run : 0;

    return (longest, current);
  }

  /// Plays per local day for the last [DailyPlays.days] days, ending with [now]'s day. Plays
  /// before that window or after today are left out.
  static DailyPlays dailyPlays(List<(ItemType, DateTime)> instants, DateTime now) {
    return dailyPlaysFrom(instants, DateTime(now.year, now.month, now.day - (DailyPlays.days - 1)), DailyPlays.days);
  }

  /// Plays per local day for the calendar year [year]: January 1st first, 365 or 366 buckets.
  static DailyPlays dailyPlaysOfYear(List<(ItemType, DateTime)> instants, int year) {
    // UTC arithmetic: a local difference would be an hour short across a DST change.
    final days = DateTime.utc(year + 1).difference(DateTime.utc(year)).inDays;
    return dailyPlaysFrom(instants, DateTime(year), days);
  }

  /// Plays per local day for [days] days from the local date [start]. Plays outside that window
  /// are left out.
  static DailyPlays dailyPlaysFrom(List<(ItemType, DateTime)> instants, DateTime start, int days) {
    final counts = <DateTime, int>{};
    for (final (_, instant) in instants) {
      counts.update(_localDay(instant), (count) => count + 1, ifAbsent: () => 1);
    }

    // Same constructor arithmetic as DailyPlays.day, so the keys line up across DST changes.
    final plays = List.generate(days, (index) => counts[DateTime(start.year, start.month, start.day + index)] ?? 0);
    return DailyPlays(start: start, plays: plays);
  }

  /// The first watch (local time) and the days elapsed since, at least 1 once something was
  /// watched.
  static (DateTime?, int) firstWatchAndDaysTracked(List<(ItemType, DateTime)> instants, DateTime now) {
    if (instants.isEmpty) {
      return (null, 0);
    }

    var first = instants.first.$2;
    for (final (_, instant) in instants) {
      if (instant.isBefore(first)) {
        first = instant;
      }
    }

    final days = DateTime(now.year, now.month, now.day).difference(_localDay(first)).inDays;
    return (first.toLocal(), days < 1 ? 1 : days);
  }

  /// Local midnight of the day [instant] fell on, as the user experienced it.
  static DateTime _localDay(DateTime instant) {
    final local = instant.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Count and averages of the locally stored ratings, or null when nothing was rated. Season
  /// ratings count toward the total but get no average of their own - too rare to matter.
  static RatingsGivenStats? ratingsGiven(List<UserRatingEntity> ratings) {
    if (ratings.isEmpty) {
      return null;
    }

    var sum = 0;
    final sums = <ItemType, int>{};
    final counts = <ItemType, int>{};
    for (final rating in ratings) {
      sum += rating.rating;
      sums.update(rating.type, (value) => value + rating.rating, ifAbsent: () => rating.rating);
      counts.update(rating.type, (value) => value + 1, ifAbsent: () => 1);
    }

    double? averageOf(ItemType type) {
      final count = counts[type];
      return count == null ? null : sums[type]! / count;
    }

    return RatingsGivenStats(
      total: ratings.length,
      average: sum / ratings.length,
      movieAverage: averageOf(ItemType.movie),
      showAverage: averageOf(ItemType.show),
      episodeAverage: averageOf(ItemType.episode),
    );
  }

  /// How many ratings of each value 1..10 were given, as a 10 element list for the chart: index
  /// 0 holds the count of 1s, index 9 the count of 10s. Null when nothing was rated. Values
  /// outside 1..10 (there should be none) are ignored rather than crashing the page.
  static List<int>? distributionFromRatings(List<UserRatingEntity> ratings) {
    if (ratings.isEmpty) {
      return null;
    }

    final buckets = List.filled(10, 0);
    for (final rating in ratings) {
      if (rating.rating >= 1 && rating.rating <= 10) {
        buckets[rating.rating - 1]++;
      }
    }
    return buckets;
  }

  /// The movie and show ratings over time, or null when neither type was rated. The monthly
  /// buckets cover the 12 local months ending with [lastMonth]'s (by default [now]'s, the last
  /// 12 months); the recent/earlier split is at [RatingTrendStats.windowDays] before [now] and
  /// covers every rating.
  static RatingTrendStats? ratingTrend(List<UserRatingEntity> ratings, DateTime now, {DateTime? lastMonth}) {
    final endMonth = lastMonth ?? now;
    final judged = ratings.where((rating) => rating.type == ItemType.movie || rating.type == ItemType.show).toList();
    if (judged.isEmpty) {
      return null;
    }

    final sums = <(int, int), int>{};
    final counts = <(int, int), int>{};
    final windowStart = now.subtract(const Duration(days: RatingTrendStats.windowDays));
    var recentSum = 0;
    var recentCount = 0;
    var earlierSum = 0;
    var earlierCount = 0;
    for (final rating in judged) {
      final local = rating.ratedAt.toLocal();
      final month = (local.year, local.month);
      sums.update(month, (sum) => sum + rating.rating, ifAbsent: () => rating.rating);
      counts.update(month, (count) => count + 1, ifAbsent: () => 1);

      if (rating.ratedAt.isBefore(windowStart)) {
        earlierSum += rating.rating;
        earlierCount++;
      } else {
        recentSum += rating.rating;
        recentCount++;
      }
    }

    final monthly = List.generate(12, (index) {
      // Same month arithmetic as monthlyBuckets.
      final bucket = DateTime(endMonth.year, endMonth.month - (11 - index));
      final key = (bucket.year, bucket.month);
      final count = counts[key] ?? 0;
      return MonthlyRating(year: bucket.year, month: bucket.month, count: count, average: count == 0 ? null : sums[key]! / count);
    });

    return RatingTrendStats(
      monthly: monthly,
      recentAverage: recentCount == 0 ? null : recentSum / recentCount,
      recentCount: recentCount,
      earlierAverage: earlierCount == 0 ? null : earlierSum / earlierCount,
      earlierCount: earlierCount,
    );
  }

  /// The watched movies without a movie rating, most recently watched first, at most [limit] of
  /// them, or null when every watched movie is rated. Ties go to the lower id, so the order is
  /// stable across runs. Titles and years come from [movies]; a movie without a row keeps an
  /// empty title rather than dropping off the list.
  static UnratedMoviesStats? unratedMovies(
    List<WatchedAggregate> watched,
    List<UserRatingEntity> ratings,
    Map<int, MovieEntity> movies, {
    int limit = 5,
  }) {
    final rated = {
      for (final rating in ratings)
        if (rating.type == ItemType.movie) rating.tmdbId,
    };
    final unrated = watched.where((item) => item.type == ItemType.movie && !rated.contains(item.tmdbId)).toList()
      ..sort((a, b) {
        final byRecency = b.lastWatchedAt.compareTo(a.lastWatchedAt);
        return byRecency != 0 ? byRecency : a.tmdbId.compareTo(b.tmdbId);
      });
    if (unrated.isEmpty) {
      return null;
    }

    final recent = unrated.take(limit).map((item) {
      final movie = movies[item.tmdbId];
      return UnratedMovie(tmdbId: item.tmdbId, title: movie?.title ?? '', year: movie?.year, lastWatchedAt: item.lastWatchedAt);
    }).toList();
    return UnratedMoviesStats(total: unrated.length, recent: recent);
  }

  /// The movie and show ratings against TMDB's averages from the cached summaries in [movies] /
  /// [shows], or null when fewer than [CrowdComparisonStats.minSample] titles can be compared. A
  /// title without a summary, or whose average rests on fewer than
  /// [CrowdComparisonStats.minVoteCount] votes, counts toward [CrowdComparisonStats.totalRated]
  /// only.
  ///
  /// In each contrarian list, ties go to the title with more TMDB votes (the better-known one),
  /// then to the lower id, so the order is stable across runs. A rating that matches TMDB exactly
  /// is in neither list.
  static CrowdComparisonStats? crowdComparison(List<UserRatingEntity> ratings, Map<int, MovieEntity> movies, Map<int, ShowEntity> shows) {
    final judged = ratings.where((rating) => rating.type == ItemType.movie || rating.type == ItemType.show).toList();

    final gaps = <CrowdGap>[];
    for (final rating in judged) {
      final movie = rating.type == ItemType.movie ? movies[rating.tmdbId] : null;
      final show = rating.type == ItemType.show ? shows[rating.tmdbId] : null;
      final voteAverage = movie?.voteAverage ?? show?.voteAverage;
      final voteCount = movie?.voteCount ?? show?.voteCount ?? 0;
      if (voteAverage == null || voteCount < CrowdComparisonStats.minVoteCount) {
        continue;
      }
      gaps.add(
        CrowdGap(
          type: rating.type,
          tmdbId: rating.tmdbId,
          title: movie?.title ?? show?.title ?? '',
          year: movie?.year ?? show?.year,
          userRating: rating.rating,
          crowdRating: voteAverage,
          voteCount: voteCount,
        ),
      );
    }
    if (gaps.length < CrowdComparisonStats.minSample) {
      return null;
    }

    var userSum = 0;
    var crowdSum = 0.0;
    for (final gap in gaps) {
      userSum += gap.userRating;
      crowdSum += gap.crowdRating;
    }

    int byGapThenFame(CrowdGap a, CrowdGap b) {
      final byGap = b.gap.abs().compareTo(a.gap.abs());
      if (byGap != 0) return byGap;
      final byVotes = b.voteCount.compareTo(a.voteCount);
      return byVotes != 0 ? byVotes : a.tmdbId.compareTo(b.tmdbId);
    }

    final lovedMore = gaps.where((gap) => gap.gap > 0).toList()..sort(byGapThenFame);
    final lovedLess = gaps.where((gap) => gap.gap < 0).toList()..sort(byGapThenFame);

    return CrowdComparisonStats(
      compared: gaps.length,
      totalRated: judged.length,
      userAverage: userSum / gaps.length,
      crowdAverage: crowdSum / gaps.length,
      lovedMore: lovedMore.take(CrowdComparisonStats.listLimit).toList(),
      lovedLess: lovedLess.take(CrowdComparisonStats.listLimit).toList(),
    );
  }

  /// The items watched more than once, most plays first, at most [limit]. Ties go to the more
  /// recently watched item. Titles are left empty - the service fills them in afterward.
  static List<TopRewatchedItem> topRewatched(List<WatchedAggregate> watched, {int limit = 5}) {
    final rewatched = watched.where((item) => item.plays > 1).toList()
      ..sort((a, b) {
        final byPlays = b.plays.compareTo(a.plays);
        return byPlays != 0 ? byPlays : b.lastWatchedAt.compareTo(a.lastWatchedAt);
      });

    return rewatched
        .take(limit)
        .map((item) => TopRewatchedItem(type: item.type, tmdbId: item.tmdbId, title: '', plays: item.plays))
        .toList();
  }

  /// Tracked / completed / in-progress counts and the mean per-show completion. A show whose
  /// summary has not synced yet (aired == 0) cannot say how complete it is, so it stays out of
  /// the mean (the NULLIF trick the progress listing uses, in Dart).
  static ShowCompletionStats completion(List<ShowProgressListItem> items) {
    var completed = 0;
    var ratioSum = 0.0;
    var ratioCount = 0;
    for (final item in items) {
      if (item.aired > 0) {
        final ratio = item.completed / item.aired;
        ratioSum += ratio > 1 ? 1 : ratio;
        ratioCount++;
        if (item.completed >= item.aired) {
          completed++;
        }
      }
    }

    return ShowCompletionStats(
      tracked: items.length,
      completed: completed,
      inProgress: items.length - completed,
      averageCompletion: ratioCount == 0 ? 0 : ratioSum / ratioCount,
      almostThere: almostThere(items),
    );
  }

  /// The partly watched shows with the fewest aired episodes left, at most [limit]. A show
  /// without a synced summary (aired == 0), one not started yet or one already complete does
  /// not qualify. Ties go to the more complete show, then to the lower id.
  static List<AlmostThereShow> almostThere(List<ShowProgressListItem> items, {int limit = 3}) {
    final partial = items.where((item) => item.aired > 0 && item.completed > 0 && item.completed < item.aired).toList()
      ..sort((a, b) {
        final byLeft = (a.aired - a.completed).compareTo(b.aired - b.completed);
        if (byLeft != 0) return byLeft;
        final byCompletion = (b.completed / b.aired).compareTo(a.completed / a.aired);
        return byCompletion != 0 ? byCompletion : a.showTmdbId.compareTo(b.showTmdbId);
      });

    return partial
        .take(limit)
        .map((item) => AlmostThereShow(tmdbId: item.showTmdbId, title: item.title, aired: item.aired, completed: item.completed))
        .toList();
  }

  /// The show with the most watched minutes per [minutesPerShow], or null when no show was
  /// watched. Ties - and the whole ranking while no runtime is cached, when every show sits at
  /// zero - go to the most played show, then the most recently watched, then the lowest id.
  /// Movies in [watched] are ignored.
  static MostWatchedShow? mostWatchedShow(List<WatchedAggregate> watched, Map<int, int> minutesPerShow, Map<int, ShowEntity> shows) {
    final candidates = watched.where((item) => item.type == ItemType.show).toList();
    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) {
      final byMinutes = (minutesPerShow[b.tmdbId] ?? 0).compareTo(minutesPerShow[a.tmdbId] ?? 0);
      if (byMinutes != 0) return byMinutes;
      final byPlays = b.plays.compareTo(a.plays);
      if (byPlays != 0) return byPlays;
      final byRecency = b.lastWatchedAt.compareTo(a.lastWatchedAt);
      return byRecency != 0 ? byRecency : a.tmdbId.compareTo(b.tmdbId);
    });

    final best = candidates.first;
    return MostWatchedShow(
      tmdbId: best.tmdbId,
      title: shows[best.tmdbId]?.title ?? '',
      minutes: minutesPerShow[best.tmdbId] ?? 0,
      episodePlays: best.plays,
      lastWatchedAt: best.lastWatchedAt,
    );
  }

  /// The best rated movies and shows, highest rating first, at most [limit]. Season and episode
  /// ratings are left out. Ties go to the more recently rated title, then to the lower id.
  /// Titles and years come from [movies] / [shows]; a title without a row keeps an empty title
  /// rather than dropping off the list.
  static List<TopRatedTitle> topRated(
    List<UserRatingEntity> ratings,
    Map<int, MovieEntity> movies,
    Map<int, ShowEntity> shows, {
    int limit = 10,
  }) {
    final judged = ratings.where((rating) => rating.type == ItemType.movie || rating.type == ItemType.show).toList()
      ..sort((a, b) {
        final byRating = b.rating.compareTo(a.rating);
        if (byRating != 0) return byRating;
        final byRecency = b.ratedAt.compareTo(a.ratedAt);
        return byRecency != 0 ? byRecency : a.tmdbId.compareTo(b.tmdbId);
      });

    return judged.take(limit).map((rating) {
      final (title, year) = rating.type == ItemType.movie
          ? (movies[rating.tmdbId]?.title, movies[rating.tmdbId]?.year)
          : (shows[rating.tmdbId]?.title, shows[rating.tmdbId]?.year);
      return TopRatedTitle(
        type: rating.type,
        tmdbId: rating.tmdbId,
        title: title ?? '',
        year: year,
        rating: rating.rating,
        ratedAt: rating.ratedAt,
      );
    }).toList();
  }

  /// The most watched genres among the tracked shows, or null when fewer than
  /// [genreCoverageThreshold] of them have a synced summary - a chart built from a thin sample
  /// misleads more than it informs. Genre ids without an entry in [idToName] (the genre table
  /// has not synced, or TMDB retired the id) are labelled `Genre <id>`. Ties sort by id, so the
  /// order is stable across runs.
  static GenreStats? topGenres(List<ShowEntity> summaries, Map<int, String> idToName, int totalShows, {int limit = 5}) {
    if (totalShows == 0 || summaries.length / totalShows < genreCoverageThreshold) {
      return null;
    }

    final counts = <int, int>{};
    for (final summary in summaries) {
      for (final id in summary.genreList) {
        counts.update(id, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    if (counts.isEmpty) {
      return null;
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });

    final top = sorted
        .take(limit)
        .map((entry) => GenreCount(name: idToName[entry.key] ?? 'Genre ${entry.key}', count: entry.value))
        .toList();
    return GenreStats(top: top, coveredShows: summaries.length, totalShows: totalShows);
  }

  /// The release decades of the distinct titles in [watched], or null when none of them has a
  /// known year. A title's year comes from its row in [movies] / [shows]; titles without a row
  /// or a year count toward [DecadeStats.totalTitles] only.
  ///
  /// When several titles share the oldest (or newest) year, the most played one wins, then the
  /// most recently watched, then the lowest id - the better-known title, picked the same way on
  /// every run.
  static DecadeStats? decades(List<WatchedAggregate> watched, Map<int, MovieEntity> movies, Map<int, ShowEntity> shows) {
    final ranked = [...watched]
      ..sort((a, b) {
        final byPlays = b.plays.compareTo(a.plays);
        if (byPlays != 0) return byPlays;
        final byRecency = b.lastWatchedAt.compareTo(a.lastWatchedAt);
        return byRecency != 0 ? byRecency : a.tmdbId.compareTo(b.tmdbId);
      });

    final titles = <EraTitle>[];
    for (final item in ranked) {
      final (title, year) = item.type == ItemType.movie
          ? (movies[item.tmdbId]?.title, movies[item.tmdbId]?.year)
          : (shows[item.tmdbId]?.title, shows[item.tmdbId]?.year);
      // TMDB reports 0 or nothing for an unknown date; neither belongs on the chart.
      if (year != null && year > 0) {
        titles.add(EraTitle(type: item.type, tmdbId: item.tmdbId, title: title ?? '', year: year));
      }
    }
    if (titles.isEmpty) {
      return null;
    }

    var oldest = titles.first;
    var newest = titles.first;
    final counts = <int, int>{};
    for (final title in titles) {
      // Strict comparisons keep the first (best ranked) title on a tie.
      if (title.year < oldest.year) oldest = title;
      if (title.year > newest.year) newest = title;
      counts.update(_decadeOf(title.year), (count) => count + 1, ifAbsent: () => 1);
    }

    final first = _decadeOf(oldest.year);
    final last = _decadeOf(newest.year);
    final decades = [for (var decade = first; decade <= last; decade += 10) DecadeCount(decade: decade, titles: counts[decade] ?? 0)];

    return DecadeStats(decades: decades, oldest: oldest, newest: newest, coveredTitles: titles.length, totalTitles: watched.length);
  }

  static int _decadeOf(int year) => year ~/ 10 * 10;
}
