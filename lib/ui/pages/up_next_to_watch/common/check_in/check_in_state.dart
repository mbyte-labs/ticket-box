import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';

part 'check_in_state.freezed.dart';

@freezed
abstract class CheckInState with _$CheckInState {
  const factory CheckInState({
    required bool isWatching,

    /// The headline of the check-in.
    ///
    /// Contains:
    /// for movie: Movie Title
    /// for episodes: Show Name
    required String title,

    /// The second line of the check-in, empty for movies.
    ///
    /// For episodes: S3xE9 Episode Title
    required String subtitle,
    required ItemType type,
    required double percentageWatched,
    required DateTime startedAt,
    required DateTime endAt,

    /// TMDB id of the show (for episodes) or of the movie.
    ///
    /// Together with [season] and [episode] this is everything needed to
    /// navigate to the checked-in item.
    int? tmdbId,
    int? season,
    int? episode,
    HistoryEntity? checkInItem,
  }) = _CheckInState;

  factory CheckInState.initial() {
    return CheckInState(
      isWatching: false,
      title: '',
      subtitle: '',
      type: ItemType.episode,
      percentageWatched: 0.0,
      startedAt: DateTime.now(),
      endAt: DateTime.now(),
    );
  }
}
