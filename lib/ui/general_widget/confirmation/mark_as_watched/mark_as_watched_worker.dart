import 'package:logging/logging.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/service/library/watch_history_write_service.dart';
import 'package:ticketbox/ui/general_widget/confirmation/mark_as_watched/mark_as_watched_state.dart';

/// Why a mark-as-watched did not happen, for the sheet to tell the user.
enum MarkAsWatchedOutcome {
  done,

  /// The title is not in the library yet and TMDB could not be reached to add it.
  needsConnection,

  /// TMDB has no such title any more.
  gone,
  failed,
}

/// Performs the history (and optional rating) write for the mark-as-watched confirmation: one
/// call, one transaction, the rating riding along.
class MarkAsWatchedWorker {
  final _log = Logger('MarkAsWatchedWorker');

  final WatchHistoryWriteService _historyService;

  MarkAsWatchedWorker({WatchHistoryWriteService? historyService}) : _historyService = historyService ?? WatchHistoryWriteService();

  Future<MarkAsWatchedOutcome> work(MarkAsWatchedState state) async {
    final target = state.target;
    try {
      await _historyService.addToHistory(
        target: target,
        selectedDateType: state.selectedDateType,
        customWatchTime: state.customWatchTime,
        rating: state.rating == 0 || !target.supportsRating ? null : state.rating.toInt(),
      );
      return MarkAsWatchedOutcome.done;
    } on TrackingUnavailableException catch (e) {
      _log.warning('Could not mark ${target.key} as watched: the title is not in the library and TMDB is unreachable (${e.code.name})');
      return MarkAsWatchedOutcome.needsConnection;
    } on ItemGoneException {
      _log.warning('Could not mark ${target.key} as watched: TMDB has no such title');
      return MarkAsWatchedOutcome.gone;
    } catch (e, stacktrace) {
      _log.severe('Unknown thrown object marking ${target.type.name} as watched', e, stacktrace);
      return MarkAsWatchedOutcome.failed;
    }
  }
}
