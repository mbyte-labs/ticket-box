import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/watched_at_options.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/library/show_state_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_hooks.dart';
import 'package:ticketbox/service/watchlist/watchlist_service.dart';

/// Writes the user's watch history. A play is a row in `HistoryItems`: a watch is an event, so
/// the log keeps every viewing, and every write for a show ends with the show's state recomputed
/// in the same transaction so Up Next and the status follow at once.
///
/// Order of every write: the tracking gate first (a movie or show not in the library is added,
/// which is the one place TMDB may be needed; an item already in the library never is), then the
/// local rows and the status recompute inside one transaction, then the cascades that may reach
/// out (watchlist rows through the service so a connected TMDB account hears about them, the
/// artwork queue) after the commit.
///
/// Marking a show or a season watched expands into one row per **aired** episode (specials only
/// when season 0 is targeted explicitly), from the local catalogue only. Every mark logs a new
/// play, whatever the history already holds — marking something again is how a rewatch is
/// logged, for a single movie or episode as much as for a whole season.
///
/// "Watched at release" uses the TMDB air date at local midnight: TMDB publishes dates, not
/// instants, so there is no air time to add.
class WatchHistoryWriteService {
  static final _log = Logger('[Service] WatchHistoryWriteService');

  final HistoryRepo _historyRepo;
  final EpisodeRepo _episodeRepo;
  final SeasonRepo _seasonRepo;
  final MovieRepo _movieRepo;
  final UserRatingRepo _ratingRepo;
  final WatchlistService _watchlist;
  final LibraryService _library;
  final ShowStateService _state;
  final TmdbSyncHooks _hooks;
  final ArtworkService Function() _artwork;
  final DatabaseConnectionManager _db;

  WatchHistoryWriteService({
    HistoryRepo? historyRepo,
    EpisodeRepo? episodeRepo,
    SeasonRepo? seasonRepo,
    MovieRepo? movieRepo,
    UserRatingRepo? ratingRepo,
    WatchlistService? watchlist,
    LibraryService? library,
    ShowStateService? state,
    TmdbSyncHooks? hooks,
    ArtworkService Function()? artwork,
  }) : _historyRepo = historyRepo ?? HistoryRepo(),
       _episodeRepo = episodeRepo ?? EpisodeRepo(),
       _seasonRepo = seasonRepo ?? SeasonRepo(),
       _movieRepo = movieRepo ?? MovieRepo(),
       _ratingRepo = ratingRepo ?? UserRatingRepo(),
       _watchlist = watchlist ?? WatchlistService(),
       _library = library ?? LibraryService.instance(),
       _state = state ?? ShowStateService(),
       _hooks = hooks ?? TmdbSyncHooks.instance(),
       _artwork = artwork ?? ArtworkService.instance,
       _db = DatabaseConnectionInitializer.getConnection();

  /// Records [target] as watched.
  ///
  /// [selectedDateType] picks the timestamp:
  /// * `rightNow` — now, the same instant for every expanded episode;
  /// * `releaseDate` / `seasonReleaseDate` / `episodeReleaseDate` — each covered episode's own air
  ///   date (a movie: its release date);
  /// * `custom` — [customWatchTime], which the caller must supply and which may not be in the
  ///   future.
  ///
  /// Every mark inserts, whatever the history already holds. An optional [rating] rides the same
  /// transaction.
  /// Throws `TrackingUnavailableException` when the title is not in the library and TMDB cannot
  /// be reached — nothing is written then.
  Future<void> addToHistory({
    required MarkAsWatchedTarget target,
    WatchedConfirmationDateSelect selectedDateType = WatchedConfirmationDateSelect.rightNow,
    DateTime? customWatchTime,
    int? rating,
  }) async {
    final now = DateTime.now().toUtc();
    if (selectedDateType == WatchedConfirmationDateSelect.custom && customWatchTime != null && customWatchTime.toUtc().isAfter(now)) {
      throw ArgumentError.value(customWatchTime, 'customWatchTime', 'A play cannot be in the future');
    }
    _log.info('Adding ${target.key} to history as ${selectedDateType.name}');

    await _library.ensureTracked(target.key);

    final fixedInstant = switch (selectedDateType) {
      WatchedConfirmationDateSelect.custom => (customWatchTime ?? DateTime.now()).toUtc(),
      WatchedConfirmationDateSelect.rightNow => now,
      _ => null,
    };
    final entries = await _expand(target, fixedInstant: fixedInstant, now: now);
    final rateable = rating != null && target.supportsRating;
    if (entries.isEmpty && !rateable) {
      _log.info('Nothing to record for ${target.key}: no aired episodes');
      return;
    }

    await _db.transaction(() async {
      if (entries.isNotEmpty) {
        await _historyRepo.insertAllNew(entries);
      }
      if (rateable) {
        await _ratingRepo.insert(
          UserRatingEntity.build(
            type: target.type,
            tmdbId: target.showTmdbId,
            season: target.season,
            episode: target.episode,
            rating: rating,
            ratedAt: now,
          ),
        );
      }
      if (target.type != ItemType.movie) {
        await _state.recomputeShowStatus(target.showTmdbId, now: now);
      }
    });

    await _watchlist.clearForWatched(target);
    if (rateable) {
      await _hooks.ratingChanged(target.key, rating);
    }
    _artwork().kick();
  }

  /// Removes one play by its id; the show's state follows in the same transaction (removing the
  /// last play un-watches a movie or collapses a show's state row).
  Future<void> removeByHistoryId(int historyId) async {
    final row = await _historyRepo.getByHistoryId(historyId);
    if (row == null) {
      return;
    }
    _log.info('Removing history entry $historyId (${row.type.name} ${row.tmdbId})');
    await _db.transaction(() async {
      await _historyRepo.deleteByHistoryId(historyId);
      if (row.type == ItemType.episode) {
        await _state.recomputeShowStatus(row.tmdbId);
      }
    });
    await _library.onReferenceRemoved(row.type == ItemType.episode ? MediaKey.show(row.tmdbId) : MediaKey.movie(row.tmdbId));
  }

  Future<void> removeMovie(int tmdbId) async {
    _log.info('Removing movie $tmdbId from history');
    await _historyRepo.deleteMovie(tmdbId);
    await _library.onReferenceRemoved(MediaKey.movie(tmdbId));
  }

  Future<void> removeEpisode(int showTmdbId, int season, int episode) async {
    _log.info('Removing show $showTmdbId S${season}E$episode from history');
    await _removeShowRows(showTmdbId, () => _historyRepo.deleteEpisode(showTmdbId, season, episode));
  }

  Future<void> removeSeason(int showTmdbId, int season) async {
    _log.info('Removing show $showTmdbId S$season from history');
    await _removeShowRows(showTmdbId, () => _historyRepo.deleteBySeason(showTmdbId, season));
  }

  Future<void> removeShow(int showTmdbId) async {
    _log.info('Removing show $showTmdbId from history');
    await _removeShowRows(showTmdbId, () => _historyRepo.deleteByShowId(showTmdbId));
  }

  Future<void> _removeShowRows(int showTmdbId, Future<void> Function() delete) async {
    await _db.transaction(() async {
      await delete();
      await _state.recomputeShowStatus(showTmdbId);
    });
    await _library.onReferenceRemoved(MediaKey.show(showTmdbId));
  }

  Future<List<NewHistoryEntry>> _expand(MarkAsWatchedTarget target, {required DateTime? fixedInstant, required DateTime now}) async {
    switch (target.type) {
      case ItemType.movie:
        final released = fixedInstant ?? (await _movieRepo.get(target.showTmdbId))?.released ?? now;
        return [NewHistoryEntry.movie(tmdbId: target.showTmdbId, action: HistoryAction.watch, watchedAt: released.toUtc())];
      case ItemType.episode:
        if (fixedInstant != null) {
          return [_episodeEntry(target.showTmdbId, target.season, target.episode, fixedInstant)];
        }
        final episode = await _episodeRepo.get(target.showTmdbId, target.season, target.episode);
        return [_episodeEntry(target.showTmdbId, target.season, target.episode, episode?.firstAired?.toUtc() ?? now)];
      case ItemType.season:
        return _airedEpisodeEntries(target.showTmdbId, {target.season}, fixedInstant, now);
      case ItemType.show:
        final seasons = (await _seasonRepo.getAllForShow(target.showTmdbId)).map((s) => s.season).where((s) => s != 0).toSet();
        return _airedEpisodeEntries(target.showTmdbId, seasons, fixedInstant, now);
    }
  }

  /// One entry per aired episode of [seasons]. With no fixed instant each episode is stamped with
  /// its own air date; a show's "release date" option collapses to that too.
  Future<List<NewHistoryEntry>> _airedEpisodeEntries(int showTmdbId, Set<int> seasons, DateTime? fixedInstant, DateTime now) async {
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final entries = <NewHistoryEntry>[];
    for (final season in seasons) {
      final episodes = await _episodeRepo.getAllForSeason(showTmdbId, season);
      for (final episode in episodes) {
        final aired = episode.firstAired;
        if (aired == null || aired.isAfter(endOfToday)) {
          continue;
        }
        entries.add(_episodeEntry(showTmdbId, season, episode.episode, fixedInstant ?? aired.toUtc()));
      }
    }
    return entries;
  }

  /// The idempotent first mark: entries whose episode (or movie) already has a play are dropped.
  NewHistoryEntry _episodeEntry(int showTmdbId, int season, int episode, DateTime watchedAt) {
    return NewHistoryEntry.episode(
      showTmdbId: showTmdbId,
      season: season,
      episode: episode,
      action: HistoryAction.watch,
      watchedAt: watchedAt,
    );
  }
}
