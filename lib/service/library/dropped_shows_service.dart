import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_entity.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/library/show_state_service.dart';

/// The shows the user has dropped ("ignore"), as the pages use them. Dropping is always
/// show-wide — there is no episode- or season-level dropped list — so callers on the episode and
/// season pages must pass the parent show's id and make that scope clear in the UI.
///
/// A dropped show is a `show_states` row with the sticky `dropped` status ([ShowStateService]);
/// the Up Next and Show Progress queries leave those out. Dropping a show not in the library adds
/// it first (the tracking gate, TMDB's one involvement); un-dropping lands it on `watching` and
/// recomputes, and queues it for the deletion sweep when nothing else references it.
class DroppedShowsService {
  final ShowStateService _state;
  final LibraryService _library;

  DroppedShowsService({ShowStateService? state, LibraryService? library})
    : _state = state ?? ShowStateService(),
      _library = library ?? LibraryService.instance();

  Future<void> drop(int showTmdbId) async {
    await _library.ensureTracked(MediaKey.show(showTmdbId));
    await _state.drop(showTmdbId);
  }

  Future<void> undrop(int showTmdbId) async {
    await _state.undrop(showTmdbId);
    await _library.onReferenceRemoved(MediaKey.show(showTmdbId));
  }

  Future<bool> isDropped(int showTmdbId) => _state.isDropped(showTmdbId);

  /// Every dropped show, the most recently dropped first.
  Future<List<ShowStateEntity>> getAll() => _state.getDropped();

  Future<int> count() => _state.countDropped();
}
