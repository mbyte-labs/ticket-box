import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/v3/tv_seasons/season_details.dart';
import 'package:ticketbox/api/tmdb/v3/tv_show/show_details_api.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/catalog/catalog_artwork_manifests.dart';
import 'package:ticketbox/service/catalog/show_snapshot_refresher.dart';
import 'package:ticketbox/service/catalog/snapshot_fallback.dart';
import 'package:ticketbox/service/catalog/snapshot_freshness.dart';
import 'package:ticketbox/service/catalog/snapshots.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';

/// A show, a season or an episode as the details pages read them.
typedef SeasonView = ({ShowSnapshot show, SeasonSnapshot season});
typedef EpisodeView = ({ShowSnapshot show, SeasonSnapshot season, TmdbSeasonEpisode episode});

/// A show's details, the way the show, season and episode pages read them — the show counterpart
/// of `MovieService`, with one staleness gate for every addressing form: a season or episode page
/// of a tracked show goes through the same `fetched_at` check as the show page, and a view never
/// re-fetches a season document it already has. Seasons and episodes have no documents of their
/// own to refresh: an episode is a projection of its season's document.
class ShowService {
  static final _log = Logger('[Service] ShowService');

  final ShowRepo _showRepo;
  final SeasonRepo _seasonRepo;
  final EpisodeRepo _episodeRepo;
  final SnapshotDocumentRepo _documents;
  final TmdbShowDetailsApi _api;
  final ShowSnapshotRefresher _refresher;
  final CatalogArtworkManifests _manifests;
  final ArtworkService Function() _artwork;

  ShowService({
    ShowRepo? showRepo,
    SeasonRepo? seasonRepo,
    EpisodeRepo? episodeRepo,
    SnapshotDocumentRepo? documents,
    TmdbShowDetailsApi? api,
    ShowSnapshotRefresher? refresher,
    CatalogArtworkManifests? manifests,
    ArtworkService Function()? artwork,
  }) : _showRepo = showRepo ?? ShowRepo(),
       _seasonRepo = seasonRepo ?? SeasonRepo(),
       _episodeRepo = episodeRepo ?? EpisodeRepo(),
       _documents = documents ?? SnapshotDocumentRepo(),
       _api = api ?? TmdbShowDetailsApi(),
       _refresher = refresher ?? ShowSnapshotRefresher(),
       _manifests = manifests ?? CatalogArtworkManifests(),
       _artwork = artwork ?? ArtworkService.instance;

  /// The stored snapshot of a tracked show (synthetic from the rows while the backfill has not
  /// fetched the document yet), or null when the show is not in the library.
  Future<ShowSnapshot?> getLocal(int tmdbId) async {
    final row = await _showRepo.get(tmdbId);
    if (row == null) {
      return null;
    }
    final json = row.hasSnapshot ? await _documents.getShow(tmdbId) : null;
    if (json == null) {
      return SnapshotFallback.show(row, await _seasonRepo.getAllForShow(tmdbId));
    }
    try {
      return ShowSnapshot.fromJson(json, fetchedAt: row.fetchedAt, providersRegion: row.watchProvidersRegion);
    } catch (e, stackTrace) {
      _log.warning('Corrupt snapshot of show $tmdbId, rendering the rows: $e', e, stackTrace);
      return SnapshotFallback.show(row, await _seasonRepo.getAllForShow(tmdbId));
    }
  }

  /// The stored season document of a tracked show (synthetic from the rows when there is none),
  /// or null when the show is not in the library.
  Future<SeasonSnapshot?> getLocalSeason(int showTmdbId, int season) async {
    final row = await _seasonRepo.getBySeasonNumber(showTmdbId, season);
    if (row == null) {
      return null;
    }
    final json = row.hasSnapshot ? await _documents.getSeason(showTmdbId, season) : null;
    if (json == null) {
      return SnapshotFallback.season(row, await _episodeRepo.getAllForSeason(showTmdbId, season));
    }
    try {
      return SeasonSnapshot.fromJson(json, fetchedAt: row.fetchedAt);
    } catch (e, stackTrace) {
      _log.warning('Corrupt snapshot of show $showTmdbId season $season, rendering the rows: $e', e, stackTrace);
      return SnapshotFallback.season(row, await _episodeRepo.getAllForSeason(showTmdbId, season));
    }
  }

  /// Tracked → the local snapshot; untracked → live from TMDB, nothing written.
  Future<ShowSnapshot> getDetails(int tmdbId, {required String? region}) async {
    final local = await getLocal(tmdbId);
    if (local != null) {
      return local;
    }
    return _live(tmdbId, region: region);
  }

  /// A season with its show. For a tracked show whose season was never fetched (a stub ahead of
  /// the backfill) the one season is fetched now; offline it renders from the rows.
  Future<SeasonView> getSeason(int showTmdbId, int season, {required String? region}) async {
    final show = await getLocal(showTmdbId);
    if (show == null) {
      final live = await _live(showTmdbId, region: region, appendSeasons: {season});
      final appended = live.appendedSeasons[season];
      if (appended == null) {
        throw ItemGoneException(MediaKey.season(showTmdbId, season));
      }
      return (show: live, season: appended);
    }
    final local = await _ensureSeasonFetched(showTmdbId, season, region: region);
    if (local == null) {
      throw ItemGoneException(MediaKey.season(showTmdbId, season));
    }
    return (show: show, season: local);
  }

  /// An episode with its season and show — the episode is its season document's entry.
  Future<EpisodeView> getEpisode(int showTmdbId, int season, int episode, {required String? region}) async {
    final view = await getSeason(showTmdbId, season, region: region);
    final entry = view.season.episode(episode);
    if (entry == null) {
      throw ItemGoneException(MediaKey.episode(showTmdbId, season, episode));
    }
    return (show: view.show, season: view.season, episode: entry);
  }

  /// Re-fetches a tracked show's root (and any new season) once the snapshot is stale or pruned to
  /// another region; the fresh snapshot, or null when nothing was refreshed (TMDB unreachable is
  /// logged and the stale copy stays).
  Future<ShowSnapshot?> refreshIfStale(int tmdbId, {required String? region, DateTime? now}) async {
    final row = await _showRepo.get(tmdbId);
    if (row == null) {
      return null;
    }
    if (!SnapshotFreshness.isStale(row.fetchedAt, now: now) && row.watchProvidersRegion == region) {
      return null;
    }
    try {
      if (!await _refresher.refreshRoot(tmdbId, region: region, now: now)) {
        return null;
      }
    } catch (e, stackTrace) {
      _log.warning('Serving the stale snapshot of show $tmdbId: $e', e, stackTrace);
      return null;
    }
    await _reconcileArtwork(tmdbId);
    return getLocal(tmdbId);
  }

  /// The scheduler's refresh of a tracked show: root, open seasons, new seasons. A 404 keeps the
  /// rows (false); transport errors propagate.
  Future<bool> refreshForScheduler(int tmdbId, {required String? region, DateTime? now}) async {
    final written = await _refresher.refreshForScheduler(tmdbId, region: region, now: now);
    if (written) {
      await _reconcileArtwork(tmdbId);
    }
    return written;
  }

  Future<ShowSnapshot> _live(int tmdbId, {required String? region, Iterable<int> appendSeasons = const []}) async {
    final raw = await _api.getRaw(tmdbId, appendSeasons: appendSeasons);
    if (raw == null) {
      throw ItemGoneException(MediaKey.show(tmdbId));
    }
    return ShowSnapshot.live(raw, region: region);
  }

  Future<SeasonSnapshot?> _ensureSeasonFetched(int showTmdbId, int season, {required String? region}) async {
    final row = await _seasonRepo.getBySeasonNumber(showTmdbId, season);
    if (row != null && row.hasSnapshot) {
      return getLocalSeason(showTmdbId, season);
    }
    try {
      await _refresher.fetchSeasons(showTmdbId, [season], region: region);
      await _reconcileArtwork(showTmdbId);
    } catch (e, stackTrace) {
      _log.warning('Could not fetch season $season of show $showTmdbId, rendering the rows: $e', e, stackTrace);
    }
    return getLocalSeason(showTmdbId, season);
  }

  Future<void> _reconcileArtwork(int showTmdbId) async {
    try {
      final manifest = await _manifests.forShow(showTmdbId);
      if (manifest != null) {
        await _artwork().itemRefreshed(manifest);
      }
    } catch (e, stackTrace) {
      _log.warning('Could not reconcile the artwork of show $showTmdbId: $e', e, stackTrace);
    }
  }
}
