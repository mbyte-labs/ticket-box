import 'package:intl/intl.dart';

/// How much of a details page's subject the user has watched, so all three pages derive the same
/// three visual states from one place.
///
/// [total] is the number of *aired* episodes the subject covers — 1 for an episode page — so a
/// still-airing show can read as fully watched.
///
/// A [total] of 0 means the episode count has not loaded yet, which happens on the season page's
/// first cache-only paint (its summary is only fetched on the fresh pass). That is reported as
/// watched-but-unquantified rather than as a ratio, so the button never flashes `5 / 0 watched`,
/// and never claims completion — and with it the badge — on a count it does not have.
class DetailsWatchedStatus {
  final int watched;
  final int total;
  final DateTime? lastWatchedAt;

  const DetailsWatchedStatus({required this.watched, required this.total, this.lastWatchedAt});

  /// Status for a single episode, which is watched or not.
  factory DetailsWatchedStatus.single({required bool watched, DateTime? lastWatchedAt}) {
    return DetailsWatchedStatus(watched: watched ? 1 : 0, total: 1, lastWatchedAt: lastWatchedAt);
  }

  bool get hasKnownTotal => total > 0;

  bool get isNone => watched <= 0;

  bool get isComplete => hasKnownTotal && watched >= total;

  bool get isPartial => !isNone && !isComplete;

  /// Whether the partial state can be drawn as a ratio. False while [total] is still unknown.
  bool get showProgress => isPartial && hasKnownTotal;

  /// 0..1, for the progress bar shown in the partial state.
  double get progress => hasKnownTotal ? (watched / total).clamp(0.0, 1.0) : 0;

  /// Label for the primary action button. Reads as a call to action while unwatched and as a
  /// status once there is something to report.
  String get label {
    if (isNone) {
      return 'Mark As Watched';
    }
    if (isPartial) {
      return hasKnownTotal ? '$watched / $total watched' : 'Watched';
    }

    final watchedAt = lastWatchedAt;
    return watchedAt == null ? 'Watched' : 'Watched · ${DateFormat.yMMMd().format(watchedAt)}';
  }
}
