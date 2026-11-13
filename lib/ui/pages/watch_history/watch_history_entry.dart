import 'package:ticketbox/service/poster/poster_model.dart';

/// One tile of the watch history grid: a single play and the poster of what was watched.
///
/// A rewatched episode has one entry per watch, all sharing the same [model], so the grid keys its
/// tiles by [historyId] rather than by the model's id.
class WatchHistoryEntry {
  /// The play's row id - unique across the grid, and what "Remove this watch" deletes.
  final int historyId;

  /// When the play happened, as stored (UTC).
  final DateTime watchedAt;

  /// The marked poster of the movie or episode that was watched.
  final PosterModel model;

  const WatchHistoryEntry({required this.historyId, required this.watchedAt, required this.model});

  @override
  bool operator ==(Object other) =>
      other is WatchHistoryEntry && other.historyId == historyId && other.watchedAt == watchedAt && other.model == model;

  @override
  int get hashCode => Object.hash(historyId, watchedAt, model);

  @override
  String toString() => 'WatchHistoryEntry($historyId, $watchedAt, $model)';
}
