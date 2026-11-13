import 'dart:math';

import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/show_progress_order_by.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_list_item.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/genres/genres_service.dart';
import 'package:ticketbox/service/stats/stats_calculator.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/service/stats/stats_period.dart';

/// Assembles the [StatsOverview] the stats page renders, entirely from the local library: the
/// history, rating and progress rows are read and fed through [StatsCalculator].
///
/// No caching - every call recomputes from the local DB, which is one bulk two-column read, a
/// few aggregate queries and small tables. No network either, so it cannot fail for reasons
/// outside the device. The one exception is [artwork], the posters and backdrops of the titles
/// the page names, which the page loads separately and treats as optional.
class StatsService {
  static final _log = Logger('[Service] StatsService');

  static final StatsService _singleton = StatsService._internal();

  StatsService._internal();

  factory StatsService() {
    return _singleton;
  }

  /// The overview over [period]: everything for all time, or only the plays and ratings of one
  /// local year. A year has no progress-based numbers (the progress table is current state,
  /// without dates), so its "Episodes" headline counts the distinct episodes played that year,
  /// its genres come from the shows played that year and its completion stays empty.
  Future<StatsOverview> compute({StatsPeriod period = const StatsPeriod.allTime()}) async {
    final stopwatch = Stopwatch()..start();
    final from = period.start;
    final before = period.end;

    final (instants, allRatings, aggregates, watchedMinutes, progressItems, minutesPerShow, firstPlayRow, yearEpisodes) = await (
      HistoryRepo().getAllWatchInstants(from: from, before: before),
      UserRatingRepo().getAll(),
      HistoryRepo().getPlayAggregates(from: from, before: before),
      HistoryRepo().getWatchedMinutes(from: from, before: before),
      period.isAllTime
          ? ShowProgressQueries().listing(hideCompleted: false, orderBy: ShowProgressOrderBy.lastWatched, orderType: OrderType.descending)
          : Future.value(const <ShowProgressListItem>[]),
      HistoryRepo().getEpisodeMinutesPerShow(from: from, before: before),
      HistoryRepo().getFirstPlay(from: from, before: before),
      period.isAllTime ? Future.value(0) : HistoryRepo().countDistinctEpisodesWatched(from: from, before: before),
    ).wait;
    final ratings = period.isAllTime ? allRatings : allRatings.where((rating) => period.contains(rating.ratedAt)).toList();

    // The shallow rows give the titles and years of everything the page names: the watched
    // titles (rewatched, decades, most watched), the rated ones (highest rated) and the first
    // play. An episode row carries its show's id.
    final movieIds = {
      for (final item in aggregates)
        if (item.type == ItemType.movie) item.tmdbId,
      for (final rating in ratings)
        if (rating.type == ItemType.movie) rating.tmdbId,
      if (firstPlayRow != null && firstPlayRow.type == ItemType.movie) firstPlayRow.tmdbId,
    };
    final showIds = {
      for (final item in aggregates)
        if (item.type == ItemType.show) item.tmdbId,
      for (final rating in ratings)
        if (rating.type == ItemType.show) rating.tmdbId,
      if (firstPlayRow != null && firstPlayRow.type != ItemType.movie) firstPlayRow.tmdbId,
    };
    // The shows the genre chart is about: every tracked show for all time, the shows with a
    // play in the year otherwise.
    final genreShowIds = period.isAllTime
        ? progressItems.map((item) => item.showTmdbId).toList()
        : [
            for (final item in aggregates)
              if (item.type == ItemType.show) item.tmdbId,
          ];

    final (genreShows, genreNames, movies, shows, ratedMovies, ratedShows) = await (
      ShowRepo().getMany(genreShowIds),
      _genreNames(),
      MovieRepo().getMany(movieIds.toList()),
      ShowRepo().getMany(showIds.toList()),
      // TMDB's averages for the crowd comparison, from the catalogue rows only.
      MovieRepo().getMany([
        for (final rating in ratings)
          if (rating.type == ItemType.movie) rating.tmdbId,
      ]),
      ShowRepo().getMany([
        for (final rating in ratings)
          if (rating.type == ItemType.show) rating.tmdbId,
      ]),
    ).wait;

    final now = DateTime.now();
    final year = period.year;
    final (longestStreak, currentStreak) = StatsCalculator.streaks(instants, now);
    final (firstWatch, daysTracked) = StatsCalculator.firstWatchAndDaysTracked(instants, now);

    final topRewatched = await _fillTitles(StatsCalculator.topRewatched(aggregates));

    final overview = StatsOverview(
      period: period,
      headline: _headline(aggregates, watchedMinutes, instants.length, period.isAllTime ? _completedEpisodes(progressItems) : yearEpisodes),
      ratingDistribution: StatsCalculator.distributionFromRatings(ratings),
      ratingsGiven: StatsCalculator.ratingsGiven(ratings),
      ratingTrend: StatsCalculator.ratingTrend(ratings, period.reference(now), lastMonth: period.lastMonth(now)),
      unratedMovies: StatsCalculator.unratedMovies(aggregates, ratings, movies),
      crowdComparison: StatsCalculator.crowdComparison(ratings, ratedMovies, ratedShows),
      activity: WatchActivityStats(
        monthly: StatsCalculator.monthlyBuckets(instants, period.lastMonth(now)),
        weekdayPlays: StatsCalculator.weekdayPlays(instants),
        timeOfDay: StatsCalculator.timeOfDay(instants),
        longestStreakDays: longestStreak,
        currentStreakDays: currentStreak,
        firstWatch: firstWatch,
        daysTracked: daysTracked,
        daily: year == null ? StatsCalculator.dailyPlays(instants, now) : StatsCalculator.dailyPlaysOfYear(instants, year),
        firstPlay: _firstPlay(firstPlayRow, movies, shows),
      ),
      mostWatchedShow: StatsCalculator.mostWatchedShow(aggregates, minutesPerShow, shows),
      topRated: StatsCalculator.topRated(ratings, movies, shows),
      topRewatched: topRewatched,
      completion: StatsCalculator.completion(progressItems),
      topGenres: StatsCalculator.topGenres(genreShows.values.toList(), genreNames, genreShowIds.length),
      decades: StatsCalculator.decades(aggregates, movies, shows),
    );

    _log.fine('Computed the $period stats overview from ${instants.length} plays in ${stopwatch.elapsedMilliseconds}ms');
    return overview;
  }

  /// The period the page opens on: the current local year when at least one play falls in it,
  /// all time otherwise. Ratings do not count - a year with only ratings would open on a page of
  /// zeros for every play-based section.
  Future<StatsPeriod> defaultPeriod() async {
    final thisYear = StatsPeriod.year(DateTime.now().year);
    final play = await HistoryRepo().getFirstPlay(from: thisYear.start, before: thisYear.end);
    return play == null ? const StatsPeriod.allTime() : thisYear;
  }

  /// The years the selector offers, newest first: every local year from the first play or the
  /// first rating up to this one. Empty while there is no history and no rating at all.
  Future<List<int>> availableYears() async {
    final (firstPlay, ratings) = await (HistoryRepo().getFirstPlay(), UserRatingRepo().getAll()).wait;
    final starts = [if (firstPlay != null) firstPlay.watchedAt.toLocal().year, for (final rating in ratings) rating.ratedAt.toLocal().year];
    if (starts.isEmpty) {
      return const [];
    }
    final now = DateTime.now();
    final first = starts.reduce(min);
    // A clock set back below the first year still yields that year, never an empty list.
    final last = max(first, now.year);
    return [for (var year = last; year >= first; year--) year];
  }

  /// The poster and backdrop paths of each title, from the catalogue rows — no network, and a
  /// title not in the library (or not backfilled yet) comes back as [TitleArtwork.none]. Season and
  /// episode keys resolve to their show's artwork.
  Future<Map<MediaKey, TitleArtwork>> artwork(List<MediaKey> keys) async {
    final movieIds = [
      for (final key in keys)
        if (key.type == ItemType.movie) key.tmdbId,
    ];
    final showIds = [
      for (final key in keys)
        if (key.type != ItemType.movie) key.tmdbId,
    ];
    final (movies, shows) = await (MovieRepo().getMany(movieIds), ShowRepo().getMany(showIds)).wait;
    return {
      for (final key in keys)
        key: key.type == ItemType.movie
            ? _artworkOf(movies[key.tmdbId]?.posterPath, movies[key.tmdbId]?.backdropPath)
            : _artworkOf(shows[key.tmdbId]?.posterPath, shows[key.tmdbId]?.backdropPath),
    };
  }

  TitleArtwork _artworkOf(String? posterPath, String? backdropPath) {
    return posterPath == null && backdropPath == null
        ? TitleArtwork.none
        : TitleArtwork(posterPath: posterPath, backdropPath: backdropPath);
  }

  /// The per-show completed counts summed - the all-time "Episodes" headline.
  static int _completedEpisodes(List<ShowProgressListItem> progressItems) {
    var episodesWatched = 0;
    for (final item in progressItems) {
      episodesWatched += item.completed;
    }
    return episodesWatched;
  }

  /// `moviesWatched` is the distinct movies with at least one play, `totalPlays` every history
  /// row and `hoursWatched` the cached runtimes of those plays, which are also kept per type for
  /// the movies vs TV split.
  HeadlineStats _headline(
    List<WatchedAggregate> aggregates,
    ({int movies, int episodes}) watchedMinutes,
    int totalPlays,
    int episodesWatched,
  ) {
    return HeadlineStats(
      hoursWatched: (watchedMinutes.movies + watchedMinutes.episodes) ~/ 60,
      movieMinutes: watchedMinutes.movies,
      episodeMinutes: watchedMinutes.episodes,
      moviesWatched: aggregates.where((item) => item.type == ItemType.movie).length,
      episodesWatched: episodesWatched,
      totalPlays: totalPlays,
    );
  }

  /// The oldest play as a movie or episode key with its title from the shallow rows. A title
  /// whose row is gone keeps an empty title rather than hiding the play.
  FirstPlay? _firstPlay(HistoryEntity? row, Map<int, MovieEntity> movies, Map<int, ShowEntity> shows) {
    if (row == null) {
      return null;
    }
    if (row.type == ItemType.movie) {
      return FirstPlay(key: MediaKey.movie(row.tmdbId), title: movies[row.tmdbId]?.title ?? '', watchedAt: row.watchedAt);
    }
    return FirstPlay(
      key: MediaKey.episode(row.tmdbId, row.season, row.episode),
      title: shows[row.tmdbId]?.title ?? '',
      watchedAt: row.watchedAt,
    );
  }

  /// The genre labels, from the cached list only: the stats page must not become a network
  /// call, and a missing table just means `Genre <id>` labels until the discover page syncs it.
  Future<Map<int, String>> _genreNames() async {
    try {
      return await GenresService().namesByType(ItemType.show);
    } catch (e, stackTrace) {
      _log.warning('Could not load the genre names for the stats page', e, stackTrace);
      return const {};
    }
  }

  /// Resolves the titles of the rewatched items from the local library. An item whose row is
  /// gone keeps an empty title rather than dropping off the list.
  Future<List<TopRewatchedItem>> _fillTitles(List<TopRewatchedItem> items) async {
    final movieRepo = MovieRepo();
    final showRepo = ShowRepo();

    return Future.wait(
      items.map((item) async {
        final title = item.type == ItemType.movie ? (await movieRepo.get(item.tmdbId))?.title : (await showRepo.get(item.tmdbId))?.title;
        return TopRewatchedItem(type: item.type, tmdbId: item.tmdbId, title: title ?? '', plays: item.plays);
      }),
    );
  }
}
