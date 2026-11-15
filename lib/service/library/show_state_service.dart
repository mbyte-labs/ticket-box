import 'package:logging/logging.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/common/model/show_watch_status.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_entity.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';

/// The one writer of a show's `status` — see [ShowWatchStatus].
///
/// [recomputeShowStatus] is reproducible from `episodes` + the watch log alone and runs after every
/// history write, check-in, cancel and un-drop, and over every followed show at the end of every
/// catalogue refresh tick ([recomputeAll]), which is what flips `watched` back to `watching` when
/// an episode aired overnight with nothing fetched. It never touches TMDB. `dropped` is the user's
/// and sticky: the recompute carries it through unchanged.
class ShowStateService {
  static final _log = Logger('[Service] ShowStateService');

  final ShowStateRepo _stateRepo;
  final HistoryRepo _historyRepo;
  final ShowProgressQueries _queries;
  final DatabaseConnectionManager _db;

  ShowStateService({ShowStateRepo? stateRepo, HistoryRepo? historyRepo, ShowProgressQueries? queries})
    : _stateRepo = stateRepo ?? ShowStateRepo(),
      _historyRepo = historyRepo ?? HistoryRepo(),
      _queries = queries ?? ShowProgressQueries(),
      _db = DatabaseConnectionInitializer.getConnection();

  /// Recomputes one show's status from its catalogue and plays: a first play creates `watching`;
  /// every aired non-special episode played flips it to `watched`; a newly aired one flips it
  /// back; no plays left removes the row. A dropped show is left alone.
  Future<void> recomputeShowStatus(int showTmdbId, {DateTime? now}) async {
    final current = await _stateRepo.get(showTmdbId);
    if (current?.status == ShowWatchStatus.dropped) {
      return;
    }
    final counts = await _queries.showCounts(showTmdbId, now: now);
    if (!counts.anyPlay) {
      if (current != null) {
        _log.fine('Show $showTmdbId has no plays left, removing its state');
        await _stateRepo.delete(showTmdbId);
      }
      return;
    }
    final next = counts.isComplete ? ShowWatchStatus.watched : ShowWatchStatus.watching;
    if (current?.status != next) {
      _log.fine('Show $showTmdbId: ${counts.watchedAired}/${counts.aired} aired episodes watched, state ${next.name}');
      await _stateRepo.upsert(showTmdbId, next, now ?? DateTime.now().toUtc());
    }
  }

  /// The sweep: every show with an episode play or a non-dropped state, in one transaction.
  Future<void> recomputeAll({DateTime? now}) async {
    final ids = <int>{...await _historyRepo.getWatchedShowIds(), ...await _stateRepo.getNonDroppedIds()};
    if (ids.isEmpty) {
      return;
    }
    _log.fine('Recomputing the state of ${ids.length} show(s)');
    await _db.transaction(() async {
      for (final chunk in ids.toList().chunked(16)) {
        for (final id in chunk) {
          await recomputeShowStatus(id, now: now);
        }
      }
    });
  }

  /// The user drops ("ignores") a show. Always show-wide; the row stays `dropped` until [undrop].
  /// The caller makes sure the show is tracked first.
  Future<void> drop(int showTmdbId, {DateTime? now}) async {
    _log.info('Dropping show $showTmdbId');
    await _stateRepo.upsert(showTmdbId, ShowWatchStatus.dropped, now ?? DateTime.now().toUtc());
  }

  /// Un-drops a show: it lands on `watching` and is recomputed at once, so a show dropped after
  /// finishing comes back `watched`, and one whose plays were deleted since collapses to no row.
  Future<void> undrop(int showTmdbId, {DateTime? now}) async {
    _log.info('Un-dropping show $showTmdbId');
    final current = await _stateRepo.get(showTmdbId);
    if (current == null || !current.isDropped) {
      return;
    }
    await _stateRepo.upsert(showTmdbId, ShowWatchStatus.watching, now ?? DateTime.now().toUtc());
    await recomputeShowStatus(showTmdbId, now: now);
  }

  Future<bool> isDropped(int showTmdbId) => _stateRepo.isDropped(showTmdbId);

  Future<ShowStateEntity?> get(int showTmdbId) => _stateRepo.get(showTmdbId);

  /// Every dropped show, the most recently dropped first.
  Future<List<ShowStateEntity>> getDropped() => _stateRepo.getDropped();

  Future<int> countDropped() => _stateRepo.countDropped();
}
