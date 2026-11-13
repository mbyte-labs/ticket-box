import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';

part 'up_next_to_watch_actions_state.freezed.dart';

@freezed
abstract class UpNextToWatchActionsState with _$UpNextToWatchActionsState {
  const factory UpNextToWatchActionsState({
    required bool initialLoading,
    required ShowEntity? show,
    required EpisodeEntity? episode,
    required String title,
    required String showTitle,
    required bool seasonPremiere,
    required bool seasonFinale,
    required bool seriesFinale,
    required bool midSeasonFinale,
    required int rating,
  }) = _UpNextToWatchActionsState;

  factory UpNextToWatchActionsState.initial() {
    return const UpNextToWatchActionsState(
      initialLoading: true,
      title: '',
      showTitle: '',
      seasonPremiere: false,
      seasonFinale: false,
      seriesFinale: false,
      midSeasonFinale: false,
      rating: 0,
      show: null,
      episode: null,
    );
  }
}
