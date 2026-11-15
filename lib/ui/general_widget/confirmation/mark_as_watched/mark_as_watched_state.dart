import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/watched_at_options.dart';

part 'mark_as_watched_state.freezed.dart';

@freezed
abstract class MarkAsWatchedState with _$MarkAsWatchedState {
  const factory MarkAsWatchedState({
    required MarkAsWatchedTarget target,
    required bool isInitialized,
    required bool isLoading,
    required double rating,
    required DateTime? customWatchTime,
    required WatchedConfirmationDateSelect selectedDateType,
  }) = _MarkAsWatchedState;

  factory MarkAsWatchedState.initial(MarkAsWatchedTarget target) {
    return MarkAsWatchedState(
      target: target,
      isInitialized: true,
      isLoading: false,
      rating: 0,
      customWatchTime: null,
      selectedDateType: WatchedConfirmationDateSelect.rightNow,
    );
  }
}
