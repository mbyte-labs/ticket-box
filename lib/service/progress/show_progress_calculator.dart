import 'package:ticketbox/common/model/history_action_type.dart';

/// Which watched episode the "up next" pointer continues from.
///
/// Mirrors the two `last_activity` flavours of the v3 progress endpoint, which this calculator replaces.
enum NextEpisodeMode {
  /// The v3 default (`last_activity=aired`): next = first unwatched episode after the LATEST-AIRED episode
  /// the user has watched (in season/episode order). Gaps earlier in the show are skipped.
  afterLatestAiredWatched,

  /// The v3 `last_activity=watched`: next = first unwatched episode after the MOST RECENTLY watched episode
  /// (by `watchedAt`).
  afterMostRecentlyWatched,
}

/// One episode of the TMDB catalogue for a show.
class CatalogueEpisode {
  final int season;
  final int episode;
  final DateTime? firstAired;

  const CatalogueEpisode({required this.season, required this.episode, required this.firstAired});
}

/// One row of the local watch history for a show.
class WatchedEpisode {
  final int season;
  final int episode;
  final DateTime watchedAt;
  final HistoryAction action;

  const WatchedEpisode({required this.season, required this.episode, required this.watchedAt, required this.action});
}

/// Aired/completed counters for one season.
class SeasonProgress {
  final int season;
  final int aired;
  final int completed;

  const SeasonProgress({required this.season, required this.aired, required this.completed});

  @override
  bool operator ==(Object other) =>
      other is SeasonProgress && other.season == season && other.aired == aired && other.completed == completed;

  @override
  int get hashCode => Object.hash(season, aired, completed);

  @override
  String toString() => 'SeasonProgress(season: $season, aired: $aired, completed: $completed)';
}

/// Completed flag for one catalogue episode.
class EpisodeProgress {
  final int season;
  final int episode;
  final bool completed;

  const EpisodeProgress({required this.season, required this.episode, required this.completed});

  @override
  bool operator ==(Object other) =>
      other is EpisodeProgress && other.season == season && other.episode == episode && other.completed == completed;

  @override
  int get hashCode => Object.hash(season, episode, completed);

  @override
  String toString() => 'EpisodeProgress(S${season}E$episode, completed: $completed)';
}

/// A season/episode coordinate, ordered season first then episode.
class EpisodePosition implements Comparable<EpisodePosition> {
  final int season;
  final int episode;

  const EpisodePosition({required this.season, required this.episode});

  @override
  int compareTo(EpisodePosition other) {
    final bySeason = season.compareTo(other.season);
    return bySeason != 0 ? bySeason : episode.compareTo(other.episode);
  }

  bool operator <(EpisodePosition other) => compareTo(other) < 0;

  bool operator >(EpisodePosition other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is EpisodePosition && other.season == season && other.episode == episode;

  @override
  int get hashCode => Object.hash(season, episode);

  @override
  String toString() => 'S${season}E$episode';
}

/// Everything the progress and up-next stores need for one show.
class ShowProgressResult {
  final int aired;
  final int completed;
  final DateTime? lastWatchedAt;
  final List<SeasonProgress> seasons;
  final List<EpisodeProgress> episodes;

  /// `null` means there is no up-next row for this show.
  final EpisodePosition? nextEpisode;

  /// `false` when the show has no watch history at all; the caller then deletes the progress and
  /// up-next rows instead of writing zeros.
  final bool hasAnyWatched;

  const ShowProgressResult({
    required this.aired,
    required this.completed,
    required this.lastWatchedAt,
    required this.seasons,
    required this.episodes,
    required this.nextEpisode,
    required this.hasAnyWatched,
  });
}

/// Pure computation of a show's watch progress from its TMDB episode catalogue and the local watch history.
///
/// Reproduces what the v3 sync backend's `/shows/{id}/progress/watched` used to return:
/// - an episode is *aired* when it is not a special, has a first-aired date and that date is no later than
///   the end of the current local day (an episode airing later today counts, matching the up-next repo);
/// - an episode is *completed* when at least one watch history row exists for it, whatever the action and
///   even if the row is future-dated (a running check-in is future-dated and already counts as watched);
/// - specials (season 0) are left out of every counter and never become the up-next episode.
class ShowProgressCalculator {
  const ShowProgressCalculator._();

  static ShowProgressResult compute({
    required List<CatalogueEpisode> catalogue,
    required List<WatchedEpisode> watched,
    required DateTime now,
    NextEpisodeMode mode = NextEpisodeMode.afterLatestAiredWatched,
  }) {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    // Season 0 is dropped up-front; sorted copies keep the result deterministic without touching the inputs.
    final regularCatalogue = catalogue.where((item) => item.season != 0).toList()..sort((a, b) => _positionOf(a).compareTo(_positionOf(b)));
    final regularWatched = watched.where((item) => item.season != 0).toList();

    final watchedPositions = <EpisodePosition>{for (final item in regularWatched) _positionOfWatched(item)};

    final airedBySeason = <int, int>{};
    final completedBySeason = <int, int>{};
    final episodes = <EpisodeProgress>[];
    var aired = 0;
    var completed = 0;
    final seenPositions = <EpisodePosition>{};

    for (final item in regularCatalogue) {
      final position = _positionOf(item);
      if (!seenPositions.add(position)) {
        // A duplicate catalogue row would otherwise double-count the episode.
        continue;
      }

      airedBySeason.putIfAbsent(item.season, () => 0);
      completedBySeason.putIfAbsent(item.season, () => 0);

      final isAired = item.firstAired != null && !item.firstAired!.isAfter(endOfToday);
      if (isAired) {
        aired++;
        airedBySeason[item.season] = airedBySeason[item.season]! + 1;
      }

      final isCompleted = watchedPositions.contains(position);
      if (isCompleted) {
        completed++;
        completedBySeason[item.season] = completedBySeason[item.season]! + 1;
      }

      episodes.add(EpisodeProgress(season: item.season, episode: item.episode, completed: isCompleted));
    }

    final seasonNumbers = airedBySeason.keys.toList()..sort();
    final seasons = [
      for (final season in seasonNumbers)
        SeasonProgress(season: season, aired: airedBySeason[season]!, completed: completedBySeason[season]!),
    ];

    DateTime? lastWatchedAt;
    for (final item in watched) {
      if (lastWatchedAt == null || item.watchedAt.isAfter(lastWatchedAt)) {
        lastWatchedAt = item.watchedAt;
      }
    }

    final last = _lastWatchedPosition(regularWatched, mode);
    final nextEpisode = _firstUnwatchedAfter(regularCatalogue, watchedPositions, last);

    return ShowProgressResult(
      aired: aired,
      completed: completed,
      lastWatchedAt: lastWatchedAt,
      seasons: seasons,
      episodes: episodes,
      nextEpisode: nextEpisode,
      hasAnyWatched: watched.isNotEmpty,
    );
  }

  /// The position the up-next search continues from, or `null` when nothing (non-special) is watched.
  static EpisodePosition? _lastWatchedPosition(List<WatchedEpisode> regularWatched, NextEpisodeMode mode) {
    if (regularWatched.isEmpty) {
      return null;
    }

    switch (mode) {
      case NextEpisodeMode.afterLatestAiredWatched:
        return regularWatched.map(_positionOfWatched).reduce((a, b) => b > a ? b : a);
      case NextEpisodeMode.afterMostRecentlyWatched:
        var best = regularWatched.first;
        for (final item in regularWatched.skip(1)) {
          final byTime = item.watchedAt.compareTo(best.watchedAt);
          if (byTime > 0 || (byTime == 0 && _positionOfWatched(item) > _positionOfWatched(best))) {
            best = item;
          }
        }
        return _positionOfWatched(best);
    }
  }

  /// First catalogue episode strictly after [last] (or the first one at all when [last] is `null`) that has no
  /// watch history. Unaired episodes are eligible — the up-next repo filters those at read time.
  static EpisodePosition? _firstUnwatchedAfter(
    List<CatalogueEpisode> sortedCatalogue,
    Set<EpisodePosition> watchedPositions,
    EpisodePosition? last,
  ) {
    for (final item in sortedCatalogue) {
      final position = _positionOf(item);
      if (last != null && !(position > last)) {
        continue;
      }
      if (!watchedPositions.contains(position)) {
        return position;
      }
    }
    return null;
  }

  static EpisodePosition _positionOf(CatalogueEpisode item) => EpisodePosition(season: item.season, episode: item.episode);

  static EpisodePosition _positionOfWatched(WatchedEpisode item) => EpisodePosition(season: item.season, episode: item.episode);
}
