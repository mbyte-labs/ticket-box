import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/service/library/check_in_service.dart';
import 'package:ticketbox/ui/general_widget/confirmation/check_in_remove/check_in_remove_confirmation_state.dart';

/// Cancels the check-in the user currently has running.
///
/// Not item-type specific: a check-in is one future-dated history row whatever it is for, so the
/// same flow serves both episodes and movies.
class CheckInRemoveConfirmationBloc extends Cubit<CheckInRemoveConfirmationState> {
  static final _log = Logger('CheckInRemoveConfirmationBloc');

  CheckInRemoveConfirmationBloc(HistoryEntity historyItem) : super(CheckInRemoveConfirmationState.initial(historyItem)) {
    _log.finest('Bloc created');
    _init();
  }

  Future<void> remove() async {
    emit(state.copyWith(isLoading: true));
    try {
      // The heads-up banner is driven by the future-dated check-in row in the history table, so
      // deleting it is what makes the banner go away.
      await CheckInService().cancel(state.historyItem.historyId);
    } catch (e, stackTrace) {
      _log.severe('Exception cancelling the check-in', e, stackTrace);
    }
    if (isClosed) {
      return;
    }
    emit(state.copyWith(isWorkFinished: true));
  }

  Future<void> _init() async {
    emit(state.copyWith(isInitialized: true));
  }
}
