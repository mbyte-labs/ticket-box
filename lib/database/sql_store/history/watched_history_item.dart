import 'package:ticketbox/common/model/item_type.dart';

/// One watched item, aggregated over every play of it.
///
/// This is a query projection rather than a table row: [HistoryRepo.getLatestEpisodeEntryPerShow]
/// groups the history table, so there is no single `historyId` to carry - a rewatched episode has
/// several.
class WatchedHistoryItem {
  /// Either [ItemType.movie] or [ItemType.episode] - the only two types history rows use.
  final ItemType type;

  /// The movie's TMDB id, or the *show's* TMDB id when [type] is [ItemType.episode].
  final int tmdbId;

  /// 0 for movies.
  final int season;

  /// 0 for movies.
  final int episode;

  /// The most recent `watchedAt` among the plays that matched the query's filters.
  final DateTime lastWatchedAt;

  const WatchedHistoryItem({
    required this.type,
    required this.tmdbId,
    required this.season,
    required this.episode,
    required this.lastWatchedAt,
  });
}
