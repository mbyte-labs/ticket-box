import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/watched_at_options.dart';
import 'package:ticketbox/service/library/check_in_service.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/ui/general_widget/confirmation/mark_as_watched/mark_as_watched_state.dart';
import 'package:ticketbox/ui/general_widget/confirmation/mark_as_watched/mark_as_watched_worker.dart';

class MarkAsWatchedBloc extends Cubit<MarkAsWatchedState> {
  static final _log = Logger('MarkAsWatchedBloc');

  MarkAsWatchedBloc(MarkAsWatchedTarget target) : super(MarkAsWatchedState.initial(target)) {
    _log.finest('Bloc created for ${target.key}');
  }

  Future<void> setWatchedType(WatchedConfirmationDateSelect watchTimeType, DateTime? watchedAt) async {
    MarkAsWatchedState tempState = state.copyWith(selectedDateType: watchTimeType);

    if (WatchedConfirmationDateSelect.custom == watchTimeType && watchedAt != null) {
      tempState = tempState.copyWith(customWatchTime: watchedAt);
    }
    emit(tempState);
  }

  Future<void> setRating(double rating) async {
    emit(state.copyWith(rating: rating));
  }

  Future<MarkAsWatchedOutcome> markAsWatched() async {
    return MarkAsWatchedWorker().work(state);
  }

  /// The other way out of this sheet: instead of logging a finished play, record that the item is
  /// starting *now*. The picked date and rating do not apply — a check-in takes neither.
  /// `null` when the title is not in the library and TMDB could not be reached to add it.
  Future<CheckInOutcome?> checkIn() async {
    try {
      return await CheckInService().checkIn(state.target);
    } on TrackingUnavailableException {
      return null;
    } on ItemGoneException {
      return null;
    }
  }
}
