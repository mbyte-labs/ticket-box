import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/service/poster/poster_model.dart';

part 'dropped_shows_state.freezed.dart';

@freezed
abstract class DroppedShowsState with _$DroppedShowsState {
  const factory DroppedShowsState({
    required bool initialLoading,

    /// The tiles of every dropped show, the most recently dropped first, marked. Never holds two
    /// tiles of one show: the grid keys its tiles by the model's id.
    required List<PosterModel> models,

    /// If something goes wrong
    required bool hasError,
    required String message,
  }) = _DroppedShowsState;

  factory DroppedShowsState.initial() {
    return const DroppedShowsState(initialLoading: true, models: [], hasError: false, message: 'Loading your dropped shows');
  }
}
