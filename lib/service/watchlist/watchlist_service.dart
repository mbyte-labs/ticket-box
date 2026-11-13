import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/filter/order_type.dart';
import 'package:ticketbox/common/model/filter/page_details.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/paged_response.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlistrepo_order_by.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_hooks.dart';

/// The user's watchlist. Device-local: every row is keyed on the movie's TMDB id, or on the show's
/// TMDB id plus season/episode numbers — the only identity the app has for seasons and episodes.
///
/// Every write goes through here — including the rows a "mark as watched" or a check-in clears,
/// via [clearForWatched] — so [TmdbSyncHooks] sees each one. Only movie and show rows can reach
/// the TMDB watchlist; the hooks skip the season and episode rows. Adding a title not in the
/// library adds it first (the tracking gate); removing the last reference to one queues it for
/// the deferred deletion sweep.
class WatchlistService {
  static final _log = Logger('[Service] WatchlistService');

  final WatchlistRepo _repo;
  final LibraryService _library;
  final TmdbSyncHooks _hooks;

  WatchlistService({WatchlistRepo? repo, LibraryService? library, TmdbSyncHooks? hooks})
    : _repo = repo ?? WatchlistRepo(),
      _library = library ?? LibraryService.instance(),
      _hooks = hooks ?? TmdbSyncHooks.instance();

  Future<PagedResponse<List<WatchlistEntity>>> get(List<ItemType> types, OrderType orderType, PageDetails paged) async {
    final repoPage = paged.copyWith(page: paged.page - 1);
    final response = await _repo.get(types, WatchlistRepoOrderBy.addDate, orderType, repoPage);
    return response.copyWith(page: paged.page);
  }

  /// The number of watchlisted items of every type.
  Future<int> count() => _repo.count();

  Future<WatchlistEntity?> getWatchlistMovie(int tmdbId) => _repo.getItem(ItemType.movie, tmdbId);

  Future<WatchlistEntity?> getWatchlistShow(int showTmdbId) => _repo.getItem(ItemType.show, showTmdbId);

  Future<WatchlistEntity?> getWatchlistSeason(int showTmdbId, int season) => _repo.getItem(ItemType.season, showTmdbId, season);

  Future<WatchlistEntity?> getWatchlistEpisode(int showTmdbId, int season, int episode) =>
      _repo.getItem(ItemType.episode, showTmdbId, season, episode);

  Future<void> addMovie(int tmdbId) => _add(ItemType.movie, tmdbId);

  Future<void> addShow(int showTmdbId) => _add(ItemType.show, showTmdbId);

  Future<void> addSeason(int showTmdbId, int season) => _add(ItemType.season, showTmdbId, season);

  Future<void> addEpisode(int showTmdbId, int season, int episode) => _add(ItemType.episode, showTmdbId, season, episode);

  Future<void> removeMovie(int tmdbId) async {
    _log.info('Removing movie $tmdbId from the watchlist');
    await _repo.delete(tmdbId, ItemType.movie);
    await _hooks.watchlistChanged(MediaKey.movie(tmdbId), listed: false);
    await _library.onReferenceRemoved(MediaKey.movie(tmdbId));
  }

  Future<void> removeShow(int showTmdbId) async {
    _log.info('Removing show $showTmdbId from the watchlist');
    await _repo.delete(showTmdbId, ItemType.show);
    await _hooks.watchlistChanged(MediaKey.show(showTmdbId), listed: false);
    await _library.onReferenceRemoved(MediaKey.show(showTmdbId));
  }

  Future<void> removeSeason(int showTmdbId, int season) async {
    _log.info('Removing show $showTmdbId S$season from the watchlist');
    await _repo.deleteSeason(showTmdbId, season);
    await _library.onReferenceRemoved(MediaKey.show(showTmdbId));
  }

  Future<void> removeEpisode(int showTmdbId, int season, int episode) async {
    _log.info('Removing show $showTmdbId S${season}E$episode from the watchlist');
    await _repo.deleteEpisode(showTmdbId, season, episode);
    await _library.onReferenceRemoved(MediaKey.show(showTmdbId));
  }

  /// Clears the watchlist rows a play of [target] made moot: a movie's own row; for a show, season
  /// or episode the show's row, then the season's, then the episode's — finishing part of a show
  /// takes the whole thing off the watchlist. TMDB only hears about a movie or show row that
  /// actually existed, so marking things watched does not flood the outbox with no-op removes.
  Future<void> clearForWatched(MarkAsWatchedTarget target) async {
    // Movies and shows share TMDB's numeric id space: the show-shaped cascade must not run for a movie.
    if (target.type == ItemType.movie) {
      await _removeIfListed(MediaKey.movie(target.showTmdbId));
      return;
    }
    await _removeIfListed(MediaKey.show(target.showTmdbId));
    if (target.type == ItemType.show) {
      return;
    }
    await _repo.deleteSeason(target.showTmdbId, target.season);
    if (target.type == ItemType.season) {
      return;
    }
    await _repo.deleteEpisode(target.showTmdbId, target.season, target.episode);
  }

  Future<void> _removeIfListed(MediaKey key) async {
    if (await _repo.getByKey(key) == null) {
      return;
    }
    _log.info('Removing $key from the watchlist: it was watched');
    await _repo.deleteByKey(key);
    await _hooks.watchlistChanged(key, listed: false);
  }

  Future<void> _add(ItemType type, int tmdbId, [int season = 0, int episode = 0]) async {
    _log.info('Adding ${type.name} $tmdbId S${season}E$episode to the watchlist');
    await _library.ensureTracked(MediaKey(type: type, tmdbId: tmdbId, season: season, episode: episode));
    await _repo.insert(
      WatchlistEntity.build(type: type, tmdbId: tmdbId, season: season, episode: episode, listedAt: DateTime.now().toUtc()),
    );
    await _hooks.watchlistChanged(MediaKey(type: type, tmdbId: tmdbId, season: season, episode: episode), listed: true);
  }
}
