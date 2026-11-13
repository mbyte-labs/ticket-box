import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/library/show_state_service.dart';
import 'package:ticketbox/service/watchlist/watchlist_service.dart';

enum CheckInOutcome {
  started,

  /// Another check-in is still running; only one at a time.
  alreadyActive,

  /// Shows and seasons cannot be checked into — only one playable thing at a time.
  unsupportedType,
}

/// "Watching now".
///
/// A check-in is a history row with `action = checkin` dated at the moment the item *ends*
/// (start + runtime). While that instant is in the future the banner shows it as running; once it
/// passes, the row is an ordinary play. The show's state counts the episode from the start, so
/// nothing needs to happen at expiry. The runtime comes from the local catalogue — a check-in on
/// an untracked title first adds it to the library, which is the only time TMDB is involved.
class CheckInService {
  static final _log = Logger('[Service] CheckInService');

  /// Runtime to assume when TMDB has none for the item, matching the fallbacks the check-in
  /// banner uses to draw its progress bar.
  static const fallbackEpisodeRuntime = Duration(minutes: 40);
  static const fallbackMovieRuntime = Duration(minutes: 120);

  final HistoryRepo _historyRepo;
  final MovieRepo _movieRepo;
  final ShowRepo _showRepo;
  final EpisodeRepo _episodeRepo;
  final WatchlistService _watchlist;
  final LibraryService _library;
  final ShowStateService _state;
  final DatabaseConnectionManager _db;

  CheckInService({
    HistoryRepo? historyRepo,
    MovieRepo? movieRepo,
    ShowRepo? showRepo,
    EpisodeRepo? episodeRepo,
    WatchlistService? watchlist,
    LibraryService? library,
    ShowStateService? state,
  }) : _historyRepo = historyRepo ?? HistoryRepo(),
       _movieRepo = movieRepo ?? MovieRepo(),
       _showRepo = showRepo ?? ShowRepo(),
       _episodeRepo = episodeRepo ?? EpisodeRepo(),
       _watchlist = watchlist ?? WatchlistService(),
       _library = library ?? LibraryService.instance(),
       _state = state ?? ShowStateService(),
       _db = DatabaseConnectionInitializer.getConnection();

  Future<CheckInOutcome> checkIn(MarkAsWatchedTarget target) async {
    if (!target.supportsCheckIn) {
      _log.warning('No check-in for a ${target.type.name}; ignoring');
      return CheckInOutcome.unsupportedType;
    }
    final running = await _historyRepo.getCurrentCheckInItems();
    if (running.isNotEmpty) {
      _log.warning('A check-in is already running until ${running.first.watchedAt}');
      return CheckInOutcome.alreadyActive;
    }
    await _library.ensureTracked(target.key);
    final now = DateTime.now().toUtc();
    final runtime = await _runtime(target);
    final endsAt = now.add(runtime);
    late final int historyId;
    await _db.transaction(() async {
      historyId = await _historyRepo.insertNew(
        NewHistoryEntry(
          type: target.type,
          tmdbId: target.showTmdbId,
          season: target.season,
          episode: target.episode,
          action: HistoryAction.checkin,
          watchedAt: endsAt,
        ),
      );
      if (target.type == ItemType.episode) {
        await _state.recomputeShowStatus(target.showTmdbId, now: now);
      }
    });
    _log.info('Checked in ${target.key} as history $historyId, ends at $endsAt');
    await _watchlist.clearForWatched(target);
    return CheckInOutcome.started;
  }

  /// Cancels a running check-in: the row goes, and so does the episode's "watched" state.
  Future<void> cancel(int historyId) async {
    final row = await _historyRepo.getByHistoryId(historyId);
    await _db.transaction(() async {
      await _historyRepo.deleteByHistoryId(historyId);
      if (row != null && row.type == ItemType.episode) {
        await _state.recomputeShowStatus(row.tmdbId);
      }
    });
    _log.info('Cancelled check-in $historyId');
    if (row != null) {
      await _library.onReferenceRemoved(row.type == ItemType.episode ? MediaKey.show(row.tmdbId) : MediaKey.movie(row.tmdbId));
    }
  }

  Future<Duration> _runtime(MarkAsWatchedTarget target) async {
    try {
      if (target.type == ItemType.movie) {
        return _minutes((await _movieRepo.get(target.showTmdbId))?.runtime, fallbackMovieRuntime);
      }
      final episode = await _episodeRepo.get(target.showTmdbId, target.season, target.episode);
      final showRuntime = (await _showRepo.get(target.showTmdbId))?.runtime;
      return _minutes(episode?.runtime ?? showRuntime, fallbackEpisodeRuntime);
    } catch (e, stackTrace) {
      _log.warning('Could not resolve the runtime of ${target.key}, using the fallback: $e', e, stackTrace);
      return target.type == ItemType.movie ? fallbackMovieRuntime : fallbackEpisodeRuntime;
    }
  }

  Duration _minutes(int? minutes, Duration fallback) => (minutes == null || minutes == 0) ? fallback : Duration(minutes: minutes);
}
