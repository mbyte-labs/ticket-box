import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';

part 'check_in_remove_confirmation_state.freezed.dart';

@freezed
abstract class CheckInRemoveConfirmationState with _$CheckInRemoveConfirmationState {
  const factory CheckInRemoveConfirmationState({
    required HistoryEntity historyItem,
    required bool isInitialized,
    required bool isLoading,

    /// This is true only when the modal can pe programmatically closed
    required bool isWorkFinished,
  }) = _CheckInRemoveConfirmationState;

  factory CheckInRemoveConfirmationState.initial(HistoryEntity historyItem) {
    return CheckInRemoveConfirmationState(historyItem: historyItem, isInitialized: false, isLoading: false, isWorkFinished: false);
  }
}
