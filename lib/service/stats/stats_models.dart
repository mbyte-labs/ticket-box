import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/stats/stats_period.dart';

/// Plain immutable holders for the stats page (no Freezed - pure data, no copyWith needed).

/// Everything the stats page renders, computed in one go by `StatsService`.
class StatsOverview {
  /// The window every number below was computed over.
  final StatsPeriod period;

  final HeadlineStats headline;

  /// Votes for ratings 1..10 over the locally stored ratings, index 0 being rating 1. Null when
  /// nothing was rated.
  final List<int>? ratingDistribution;

  /// Aggregations over the locally stored ratings. Null when the user has rated nothing.
  final RatingsGivenStats? ratingsGiven;

  /// How the movie and show ratings moved over time. Null when no movie or show was rated.
  final RatingTrendStats? ratingTrend;

  /// Watched movies the user has not rated yet. Null when every watched movie is rated.
  final UnratedMoviesStats? unratedMovies;

  /// The movie and show ratings against TMDB's averages. Null when too few rated titles have a
  /// cached TMDB average to compare with.
  final CrowdComparisonStats? crowdComparison;

  final WatchActivityStats activity;

  /// The show with the most watched time. Null when no show episode was watched.
  final MostWatchedShow? mostWatchedShow;

  /// The best rated movies and shows, best first. Empty when none was rated.
  final List<TopRatedTitle> topRated;

  /// Items watched more than once, most plays first. Empty when nothing was rewatched.
  final List<TopRewatchedItem> topRewatched;

  final ShowCompletionStats completion;

  /// Null when too few tracked shows have a synced summary for the numbers to mean anything.
  final GenreStats? topGenres;

  /// Release decades of the watched titles. Null when no watched title has a known year.
  final DecadeStats? decades;

  const StatsOverview({
    required this.period,
    required this.headline,
    required this.ratingDistribution,
    required this.ratingsGiven,
    required this.ratingTrend,
    required this.unratedMovies,
    required this.crowdComparison,
    required this.activity,
    required this.mostWatchedShow,
    required this.topRated,
    required this.topRewatched,
    required this.completion,
    required this.topGenres,
    required this.decades,
  });

  /// Nothing watched, nothing rated - the page shows its empty state instead of zeros.
  bool get isEmpty => headline.totalPlays == 0 && (ratingsGiven == null || ratingsGiven!.total == 0) && completion.tracked == 0;
}

class HeadlineStats {
  /// Whole hours over every play, from the runtimes cached in the movie and episode summaries.
  /// A play whose runtime is not cached yet counts as zero minutes, so this can only grow.
  final int hoursWatched;

  /// The minutes behind [hoursWatched], split by type. Same caveat: an uncached runtime counts
  /// as zero.
  final int movieMinutes;
  final int episodeMinutes;

  final int moviesWatched;
  final int episodesWatched;
  final int totalPlays;

  const HeadlineStats({
    required this.hoursWatched,
    required this.movieMinutes,
    required this.episodeMinutes,
    required this.moviesWatched,
    required this.episodesWatched,
    required this.totalPlays,
  });

  /// The share of watched time spent on episodes, 0..1. Null when no play has a cached runtime
  /// yet, so there is no time to split.
  double? get tvShare {
    final total = movieMinutes + episodeMinutes;
    return total == 0 ? null : episodeMinutes / total;
  }
}

class RatingsGivenStats {
  final int total;
  final double average;
  final double? movieAverage;
  final double? showAverage;
  final double? episodeAverage;

  const RatingsGivenStats({
    required this.total,
    required this.average,
    required this.movieAverage,
    required this.showAverage,
    required this.episodeAverage,
  });
}

/// Which way the recent ratings lean compared to the earlier ones.
enum RatingTrend { harsher, kinder, steady }

/// The movie and show ratings over time: the average per month, plus the recent window compared
/// with everything before it. Episode ratings are left out - they come in binge bursts and would
/// swing the averages with what was being watched rather than how it was judged.
class RatingTrendStats {
  /// The length of the "recent" window, ending now.
  static const windowDays = 90;

  /// Ratings each side of the comparison needs before a [delta] is worth stating.
  static const minSample = 3;

  /// A [delta] smaller than this (either way) reads as [RatingTrend.steady].
  static const steadyThreshold = 0.3;

  /// Exactly 12 buckets, oldest first, ending with the current month. Months without a rating
  /// are present with a zero count and a null average.
  final List<MonthlyRating> monthly;

  /// Average of the ratings given in the last [windowDays] days, null when there are none.
  final double? recentAverage;
  final int recentCount;

  /// Average of every rating given before that window, null when there are none.
  final double? earlierAverage;
  final int earlierCount;

  const RatingTrendStats({
    required this.monthly,
    required this.recentAverage,
    required this.recentCount,
    required this.earlierAverage,
    required this.earlierCount,
  });

  /// Recent minus earlier average. Null unless both sides have at least [minSample] ratings.
  double? get delta {
    if (recentCount < minSample || earlierCount < minSample) {
      return null;
    }
    return recentAverage! - earlierAverage!;
  }

  /// Null when there is no [delta] to judge by.
  RatingTrend? get trend {
    final value = delta;
    if (value == null) return null;
    if (value <= -steadyThreshold) return RatingTrend.harsher;
    if (value >= steadyThreshold) return RatingTrend.kinder;
    return RatingTrend.steady;
  }
}

class MonthlyRating {
  final int year;
  final int month;
  final int count;

  /// Null when nothing was rated that month.
  final double? average;

  const MonthlyRating({required this.year, required this.month, required this.count, required this.average});
}

/// Which way the user's ratings lean compared to TMDB's averages.
enum CrowdVerdict { harsher, kinder, inSync }

/// The user's movie and show ratings against TMDB's `voteAverage` for the same titles, plus the
/// titles where the two disagree the most in each direction. Only titles with a cached summary
/// and enough TMDB votes are compared; episode ratings are left out, as in [RatingTrendStats].
class CrowdComparisonStats {
  /// TMDB averages from fewer votes than this are too noisy to compare with.
  static const minVoteCount = 50;

  /// Compared titles needed before the comparison is worth showing.
  static const minSample = 5;

  /// A [delta] smaller than this (either way) reads as [CrowdVerdict.inSync].
  static const inSyncThreshold = 0.5;

  /// The length of each contrarian list.
  static const listLimit = 3;

  /// The titles that had a TMDB average to compare with.
  final int compared;

  /// Every movie and show rating, compared or not.
  final int totalRated;

  /// The user's average over the compared titles only.
  final double userAverage;

  /// TMDB's average over the same titles.
  final double crowdAverage;

  /// Rated above TMDB's average, biggest gap first, at most [listLimit].
  final List<CrowdGap> lovedMore;

  /// Rated below TMDB's average, biggest gap first, at most [listLimit].
  final List<CrowdGap> lovedLess;

  const CrowdComparisonStats({
    required this.compared,
    required this.totalRated,
    required this.userAverage,
    required this.crowdAverage,
    required this.lovedMore,
    required this.lovedLess,
  });

  /// The user's average minus TMDB's, which is also the mean per-title gap.
  double get delta => userAverage - crowdAverage;

  CrowdVerdict get verdict {
    final value = delta;
    if (value <= -inSyncThreshold) return CrowdVerdict.harsher;
    if (value >= inSyncThreshold) return CrowdVerdict.kinder;
    return CrowdVerdict.inSync;
  }
}

/// One rated movie or show next to TMDB's average for it.
class CrowdGap {
  /// [ItemType.movie] or [ItemType.show].
  final ItemType type;
  final int tmdbId;

  /// Empty when the summary has no title.
  final String title;

  /// Null when unknown.
  final int? year;
  final int userRating;
  final double crowdRating;
  final int voteCount;

  const CrowdGap({
    required this.type,
    required this.tmdbId,
    required this.title,
    required this.year,
    required this.userRating,
    required this.crowdRating,
    required this.voteCount,
  });

  /// Positive when the user rated it higher than TMDB.
  double get gap => userRating - crowdRating;
}

/// The watched movies without a rating: how many, and the most recently watched of them.
class UnratedMoviesStats {
  final int total;

  /// Most recently watched first, at most a handful.
  final List<UnratedMovie> recent;

  const UnratedMoviesStats({required this.total, required this.recent});
}

class UnratedMovie {
  final int tmdbId;

  /// Empty when the movie's row is not in the local library.
  final String title;

  /// Null when unknown.
  final int? year;
  final DateTime lastWatchedAt;

  const UnratedMovie({required this.tmdbId, required this.title, required this.year, required this.lastWatchedAt});

  /// How long ago the movie was last watched, see [watchedAgoText].
  String watchedAgo(DateTime now) => watchedAgoText(lastWatchedAt, now);
}

/// How long ago [watchedAt] was, by local calendar day: "today", "yesterday", "3 days ago",
/// "2 weeks ago", "4 months ago", "2 years ago".
String watchedAgoText(DateTime watchedAt, DateTime now) {
  final local = watchedAt.toLocal();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(local.year, local.month, local.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 14) return '$days days ago';
  if (days < 60) return '${days ~/ 7} weeks ago';
  if (days < 730) return '${days ~/ 30} months ago';
  return '${days ~/ 365} years ago';
}

/// The artwork of a movie or show on the stats page, either URL null when TMDB has none or it
/// could not load.
class TitleArtwork {
  static const none = TitleArtwork(posterPath: null, backdropPath: null);

  /// TMDB relative paths; the artwork layer turns them into local files or URLs.
  final String? posterPath;
  final String? backdropPath;

  const TitleArtwork({required this.posterPath, required this.backdropPath});
}

/// The show with the most watched time: the runtimes of its episode plays summed, with the play
/// count as the tie breaker - and as the ranking itself while no runtime is cached yet.
class MostWatchedShow {
  final int tmdbId;

  /// Empty when the show's row is not in the local library.
  final String title;

  /// Runtime minutes over every episode play; 0 until the episode summaries are cached.
  final int minutes;
  final int episodePlays;
  final DateTime lastWatchedAt;

  const MostWatchedShow({
    required this.tmdbId,
    required this.title,
    required this.minutes,
    required this.episodePlays,
    required this.lastWatchedAt,
  });

  int get hours => minutes ~/ 60;

  /// How long ago the show was last watched, see [watchedAgoText].
  String watchedAgo(DateTime now) => watchedAgoText(lastWatchedAt, now);
}

/// One of the user's best rated movies or shows.
class TopRatedTitle {
  /// [ItemType.movie] or [ItemType.show].
  final ItemType type;
  final int tmdbId;

  /// Empty when the title's row is not in the local library.
  final String title;

  /// Null when unknown.
  final int? year;
  final int rating;
  final DateTime ratedAt;

  const TopRatedTitle({
    required this.type,
    required this.tmdbId,
    required this.title,
    required this.year,
    required this.rating,
    required this.ratedAt,
  });

  MediaKey get key => MediaKey(type: type, tmdbId: tmdbId);
}

/// An in-progress show with only a few aired episodes left to watch.
class AlmostThereShow {
  final int tmdbId;

  /// Empty when the show's row has not been synchronized yet.
  final String title;
  final int aired;
  final int completed;

  const AlmostThereShow({required this.tmdbId, required this.title, required this.aired, required this.completed});

  int get left => aired - completed;

  /// Completed over aired, 0..1.
  double get completion => completed / aired;
}

/// The oldest play on record: a movie or an episode of a show.
class FirstPlay {
  /// A movie key or an episode key; [MediaKey.showKey] is what the artwork and the tap use.
  final MediaKey key;

  /// The movie's or the show's title, empty when its row is not in the local library.
  final String title;
  final DateTime watchedAt;

  const FirstPlay({required this.key, required this.title, required this.watchedAt});

  /// "S1E1" for an episode, null for a movie.
  String? get episodeLabel => key.type == ItemType.episode ? 'S${key.season}E${key.episode}' : null;
}

class WatchActivityStats {
  /// Exactly 12 buckets, oldest first: the last 12 months for all time, January to December
  /// for a year. Months without plays are present with zero.
  final List<MonthlyPlays> monthly;

  /// Plays per local weekday, exactly 7 buckets, Monday first. All zero without history.
  final List<int> weekdayPlays;

  /// Plays per part of the day. Null when no play has a real time of day.
  final TimeOfDayStats? timeOfDay;

  final int longestStreakDays;
  final int currentStreakDays;

  /// The oldest play on record, in local time. Null when there is no history at all.
  final DateTime? firstWatch;

  /// Days elapsed since [firstWatch], at least 1 once something was watched.
  final int daysTracked;

  /// Plays per local day for the year heatmap: the last 365 days for all time, the calendar
  /// year otherwise.
  final DailyPlays daily;

  /// The title behind [firstWatch]. Null when there is no history at all.
  final FirstPlay? firstPlay;

  const WatchActivityStats({
    required this.monthly,
    required this.weekdayPlays,
    required this.timeOfDay,
    required this.longestStreakDays,
    required this.currentStreakDays,
    required this.firstWatch,
    required this.daysTracked,
    required this.daily,
    required this.firstPlay,
  });
}

/// Plays per local day, one bucket per day from [start]: the rolling window ending today, or a
/// whole calendar year.
class DailyPlays {
  /// The number of days the rolling window covers, today included.
  static const days = 365;

  /// The number of intensity levels above "no plays" the heatmap shades with.
  static const levels = 4;

  /// Local midnight of the first (oldest) bucket.
  final DateTime start;

  /// One bucket per day, oldest first ([days] of them for the rolling window, 365 or 366 for a
  /// calendar year). Days without a play are present with zero.
  final List<int> plays;

  const DailyPlays({required this.start, required this.plays});

  /// The local date of bucket [index]. Built with the [DateTime] constructor rather than by
  /// adding a [Duration], so a DST change cannot shift it onto the neighbouring day.
  DateTime day(int index) => DateTime(start.year, start.month, start.day + index);

  int get total => plays.fold(0, (sum, count) => sum + count);

  /// Days with at least one play.
  int get activeDays => plays.where((count) => count > 0).length;

  /// The heatmap shade of every bucket: 0 for no plays, otherwise 1..[levels] by quartile of the
  /// active days, with the busiest day always on the top shade. Quartiles rather than a share
  /// of [max], because one bulk import day with thousands of plays would otherwise leave every
  /// other day on the faintest shade.
  List<int> shades() {
    final active = plays.where((count) => count > 0).toList()..sort();
    if (active.isEmpty) {
      return List.filled(plays.length, 0);
    }

    final busiest = active.last;
    final quartiles = [for (var k = 1; k < levels; k++) active[(active.length * k / levels).floor().clamp(0, active.length - 1)]];
    return [
      for (final count in plays)
        if (count == 0) 0 else if (count == busiest) levels else 1 + quartiles.where((threshold) => count > threshold).length,
    ];
  }
}

/// The four parts of the day the time-of-day split buckets plays into, by local hour:
/// morning 05-12, afternoon 12-17, evening 17-22, night 22-05.
enum DayPart {
  morning(label: 'Morning', persona: 'Early bird', hours: '05-12', rangeText: 'between 05:00 and 12:00'),
  afternoon(label: 'Afternoon', persona: 'Afternoon viewer', hours: '12-17', rangeText: 'between 12:00 and 17:00'),
  evening(label: 'Evening', persona: 'Prime-time viewer', hours: '17-22', rangeText: 'between 17:00 and 22:00'),
  night(label: 'Night', persona: 'Night owl', hours: '22-05', rangeText: 'after 22:00');

  final String label;

  /// What the user is called when this part of the day dominates.
  final String persona;

  /// Short hour range for tooltips.
  final String hours;

  /// Completes "41% ..." in the headline fact.
  final String rangeText;

  const DayPart({required this.label, required this.persona, required this.hours, required this.rangeText});

  static DayPart ofHour(int hour) {
    if (hour >= 5 && hour < 12) return DayPart.morning;
    if (hour >= 12 && hour < 17) return DayPart.afternoon;
    if (hour >= 17 && hour < 22) return DayPart.evening;
    return DayPart.night;
  }
}

class TimeOfDayStats {
  /// Plays per part of the day, in [DayPart.values] order.
  final List<int> plays;

  const TimeOfDayStats({required this.plays});

  int get total => plays.fold(0, (sum, count) => sum + count);

  /// The part of the day with the most plays. Ties go to the earlier part (morning first).
  DayPart get dominant {
    var best = 0;
    for (var index = 1; index < plays.length; index++) {
      if (plays[index] > plays[best]) {
        best = index;
      }
    }
    return DayPart.values[best];
  }

  /// The share of plays in [part], 0..1.
  double share(DayPart part) => total == 0 ? 0 : plays[part.index] / total;
}

class MonthlyPlays {
  final int year;
  final int month;
  final int plays;

  const MonthlyPlays({required this.year, required this.month, required this.plays});
}

class TopRewatchedItem {
  /// [ItemType.movie] or [ItemType.show].
  final ItemType type;
  final int tmdbId;
  final String title;
  final int plays;

  const TopRewatchedItem({required this.type, required this.tmdbId, required this.title, required this.plays});
}

class ShowCompletionStats {
  final int tracked;
  final int completed;
  final int inProgress;

  /// Mean of the per-show `completed / aired` ratios, 0..1. Shows whose summary has not synced
  /// yet (aired == 0) are left out of the mean.
  final double averageCompletion;

  /// The in-progress shows closest to their last aired episode, fewest left first, at most a
  /// handful. Empty when no show is partly watched.
  final List<AlmostThereShow> almostThere;

  const ShowCompletionStats({
    required this.tracked,
    required this.completed,
    required this.inProgress,
    required this.averageCompletion,
    required this.almostThere,
  });
}

class GenreStats {
  /// The most watched genres, biggest first, at most five.
  final List<GenreCount> top;

  /// How many of the tracked shows actually had a synced summary to read genres from.
  final int coveredShows;

  final int totalShows;

  const GenreStats({required this.top, required this.coveredShows, required this.totalShows});
}

class GenreCount {
  final String name;
  final int count;

  const GenreCount({required this.name, required this.count});
}

/// The release decades of the distinct titles watched (each movie once, each show with a watched
/// episode once), plus the oldest and the newest of them.
class DecadeStats {
  /// Contiguous from the oldest to the newest decade, oldest first. Decades without a title are
  /// present with zero so the chart keeps its gaps.
  final List<DecadeCount> decades;

  final EraTitle oldest;
  final EraTitle newest;

  /// How many of the watched titles had a known release year.
  final int coveredTitles;

  /// Every distinct title watched.
  final int totalTitles;

  const DecadeStats({
    required this.decades,
    required this.oldest,
    required this.newest,
    required this.coveredTitles,
    required this.totalTitles,
  });

  /// The decade with the most titles. Ties go to the more recent decade.
  DecadeCount get favorite {
    var best = decades.first;
    for (final decade in decades) {
      if (decade.titles >= best.titles) {
        best = decade;
      }
    }
    return best;
  }

  /// The share of [coveredTitles] released in [decade], 0..1.
  double share(DecadeCount decade) => coveredTitles == 0 ? 0 : decade.titles / coveredTitles;

  /// Oldest and newest are the same title - only one title has a known year.
  bool get singleTitle => oldest.type == newest.type && oldest.tmdbId == newest.tmdbId;
}

class DecadeCount {
  /// The first year of the decade, e.g. 1990.
  final int decade;
  final int titles;

  const DecadeCount({required this.decade, required this.titles});
}

/// A watched movie or show with its release (first-air) year.
class EraTitle {
  /// [ItemType.movie] or [ItemType.show].
  final ItemType type;
  final int tmdbId;
  final String title;
  final int year;

  const EraTitle({required this.type, required this.tmdbId, required this.title, required this.year});
}
