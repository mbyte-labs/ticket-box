import 'package:ticketbox/common/model/show_watch_status.dart';

/// One followed show together with its watched-progress counts, derived at query time.
///
/// A query projection rather than a table row: `ShowProgressQueries.listing` counts the show's
/// aired and played episodes and joins `shows` for the title, so there is no backing entity.
class ShowProgressListItem {
  final int showTmdbId;

  /// Empty when the show row has no title yet (a stub waiting for the backfill).
  final String title;
  final String? posterPath;
  final ShowWatchStatus status;

  /// Aired, non-special episodes.
  final int aired;

  /// Aired, non-special episodes with at least one play.
  final int completed;
  final DateTime? lastWatchedAt;

  const ShowProgressListItem({
    required this.showTmdbId,
    required this.title,
    required this.posterPath,
    required this.status,
    required this.aired,
    required this.completed,
    required this.lastWatchedAt,
  });
}
