import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/tmdb/v3/movie/movie_details_api.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/pending_deletion/pending_deletion_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/catalog/catalog_artwork_manifests.dart';
import 'package:ticketbox/service/catalog/catalog_writer.dart';
import 'package:ticketbox/service/catalog/show_snapshot_refresher.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';
import 'package:ticketbox/service/catalog/watch_region.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/service/progress/progress_error_classifier.dart';

/// What is in the library, and how things enter and leave it.
///
/// An item is *tracked* when it has a catalogue row, and it gets one through exactly one path:
/// [ensureTracked], which the write services call before their local write. The first tracking
/// action on an untracked id fetches the snapshot (a show: its root and every season), writes the
/// catalogue rows and enqueues the artwork; with TMDB down it throws and writes nothing. On a
/// tracked item it returns at once — a tracked item never needs TMDB for anything the user does.
///
/// Leaving is deferred: when the last *reference* (a play, a rating, a watchlist or favorite row,
/// a state row — a check-in is a play, a drop is a state) is removed, [onReferenceRemoved] queues
/// the item in `pending_deletions`; [sweepPendingDeletions] re-checks after a grace period and
/// only then removes the rows and the artwork directory. Re-tracking in between drops the queue
/// row. Until swept, the item keeps serving from its snapshot.
class LibraryService {
  static final _log = Logger('[Service] LibraryService');

  /// How long a de-referenced item keeps its rows and artwork before the sweep removes them.
  static const Duration deletionGrace = Duration(days: 7);

  final MovieRepo _movieRepo;
  final ShowRepo _showRepo;
  final SeasonRepo _seasonRepo;
  final EpisodeRepo _episodeRepo;
  final ShowStateRepo _stateRepo;
  final SnapshotDocumentRepo _documents;
  final PendingDeletionRepo _pending;
  final AssetJobRepo _assetJobs;
  final TmdbMovieDetailsApi _movieApi;
  final CatalogWriter _writer;
  final ShowSnapshotRefresher _shows;
  final CatalogArtworkManifests _manifests;
  final ArtworkService Function() _artwork;
  final DatabaseConnectionManager _db;

  LibraryService({
    MovieRepo? movieRepo,
    ShowRepo? showRepo,
    SeasonRepo? seasonRepo,
    EpisodeRepo? episodeRepo,
    ShowStateRepo? stateRepo,
    SnapshotDocumentRepo? documents,
    PendingDeletionRepo? pending,
    AssetJobRepo? assetJobs,
    TmdbMovieDetailsApi? movieApi,
    CatalogWriter? writer,
    ShowSnapshotRefresher? shows,
    CatalogArtworkManifests? manifests,
    ArtworkService Function()? artwork,
  }) : _movieRepo = movieRepo ?? MovieRepo(),
       _showRepo = showRepo ?? ShowRepo(),
       _seasonRepo = seasonRepo ?? SeasonRepo(),
       _episodeRepo = episodeRepo ?? EpisodeRepo(),
       _stateRepo = stateRepo ?? ShowStateRepo(),
       _documents = documents ?? SnapshotDocumentRepo(),
       _pending = pending ?? PendingDeletionRepo(),
       _assetJobs = assetJobs ?? AssetJobRepo(),
       _movieApi = movieApi ?? TmdbMovieDetailsApi(),
       _writer = writer ?? CatalogWriter(),
       _shows = shows ?? ShowSnapshotRefresher(),
       _manifests = manifests ?? CatalogArtworkManifests(),
       _artwork = artwork ?? ArtworkService.instance,
       _db = DatabaseConnectionInitializer.getConnection();

  static LibraryService instance() {
    if (GetIt.I.isRegistered<LibraryService>()) {
      return GetIt.I.get<LibraryService>();
    }
    final service = LibraryService();
    GetIt.I.registerSingleton<LibraryService>(service);
    return service;
  }

  /// Whether the movie, or the show a season/episode key belongs to, is in the library.
  Future<bool> isTracked(MediaKey key) {
    final item = key.showKey;
    return item.type == ItemType.movie ? _movieRepo.exists(item.tmdbId) : _showRepo.exists(item.tmdbId);
  }

  /// Makes sure [key]'s movie or show is in the library before a tracking action. Tracked: returns
  /// without touching TMDB. Untracked: [materialise]s it, or throws [TrackingUnavailableException]
  /// (TMDB unreachable, nothing written) / [ItemGoneException] (TMDB has no such item).
  Future<void> ensureTracked(MediaKey key) async {
    if (await isTracked(key)) {
      return;
    }
    await materialise(key);
  }

  /// Fetches the snapshot of [key]'s movie or show, writes its catalogue rows and enqueues its
  /// artwork. A show is materialised whole: root, every season, every episode.
  Future<void> materialise(MediaKey key, {DateTime? now}) async {
    final item = key.showKey;
    final region = await WatchRegion.configured();
    try {
      if (item.type == ItemType.movie) {
        final raw = await _movieApi.getRaw(item.tmdbId);
        if (raw == null) {
          throw ItemGoneException(item);
        }
        await _writer.writeMovie(
          SnapshotPruner.movie(raw, region: region),
          now: now ?? DateTime.now().toUtc(),
          region: region,
        );
      } else {
        final written = await _shows.materialise(item.tmdbId, region: region, now: now);
        if (written == null) {
          throw ItemGoneException(item);
        }
      }
    } on ItemGoneException {
      rethrow;
    } on ApiNotFoundException {
      throw ItemGoneException(item);
    } catch (e, stackTrace) {
      _log.warning('Could not add $item to the library: $e', e, stackTrace);
      throw TrackingUnavailableException(item, classifyJobError(e), e);
    }
    await _pending.delete(item.type, item.tmdbId);
    _log.info('Added $item to the library');
    await _enqueueArtwork(item);
  }

  /// How many user-data rows name [key]'s movie or show. Both predicates carry the type: movies
  /// and shows share TMDB's id space.
  Future<int> referenceCount(MediaKey key) async {
    final item = key.showKey;
    final sql = item.type == ItemType.movie
        ? '''
      SELECT (EXISTS (SELECT 1 FROM history_items WHERE type = 'movie' AND tmdb_id = ?1))
        + (EXISTS (SELECT 1 FROM user_ratings WHERE type = 'movie' AND tmdb_id = ?1))
        + (EXISTS (SELECT 1 FROM watchlists WHERE type = 'movie' AND tmdb_id = ?1))
        + (EXISTS (SELECT 1 FROM favorite_items WHERE type = 'movie' AND tmdb_id = ?1)) AS refs'''
        : '''
      SELECT (EXISTS (SELECT 1 FROM history_items WHERE type = 'episode' AND tmdb_id = ?1))
        + (EXISTS (SELECT 1 FROM user_ratings WHERE type IN ('show', 'season', 'episode') AND tmdb_id = ?1))
        + (EXISTS (SELECT 1 FROM watchlists WHERE type IN ('show', 'season', 'episode') AND tmdb_id = ?1))
        + (EXISTS (SELECT 1 FROM favorite_items WHERE type = 'show' AND tmdb_id = ?1))
        + (EXISTS (SELECT 1 FROM show_states WHERE show_tmdb_id = ?1)) AS refs''';
    final row = await _db
        .customSelect(
          sql,
          variables: [Variable.withInt(item.tmdbId)],
          readsFrom: {_db.historyItems, _db.userRatings, _db.watchlists, _db.favoriteItems, _db.showStates},
        )
        .getSingle();
    return row.read<int>('refs');
  }

  /// After a user-data row was removed: queues the item for deletion when nothing references it
  /// any more. Deletes nothing itself.
  Future<void> onReferenceRemoved(MediaKey key, {DateTime? now}) async {
    final item = key.showKey;
    if (await referenceCount(item) > 0) {
      return;
    }
    if (!await isTracked(item)) {
      return;
    }
    _log.info('$item lost its last reference; queued for deletion');
    await _pending.enqueue(item.type, item.tmdbId, now ?? DateTime.now().toUtc());
  }

  /// Queues every tracked item nothing references — after a restore replaced the user data.
  Future<void> enqueueUnreferenced({DateTime? now}) async {
    for (final id in await _movieRepo.getAllIds()) {
      await onReferenceRemoved(MediaKey.movie(id), now: now);
    }
    for (final id in await _showRepo.getAllIds()) {
      await onReferenceRemoved(MediaKey.show(id), now: now);
    }
  }

  /// Removes the items queued for longer than [grace] that are still unreferenced: the user-data
  /// stragglers, seasons, episodes, state, documents, queue rows and the catalogue row in one
  /// transaction, then the artwork directory. A re-referenced item just loses its queue row.
  Future<int> sweepPendingDeletions({Duration grace = deletionGrace, DateTime? now}) async {
    final moment = now ?? DateTime.now().toUtc();
    final due = await _pending.getDue(moment.subtract(grace));
    var removed = 0;
    for (final entry in due) {
      final item = MediaKey(type: entry.type, tmdbId: entry.tmdbId);
      if (await referenceCount(item) > 0) {
        await _pending.delete(entry.type, entry.tmdbId);
        continue;
      }
      await _db.transaction(() async {
        if (entry.type == ItemType.movie) {
          await _movieRepo.delete(entry.tmdbId);
        } else {
          await _episodeRepo.deleteByShowId(entry.tmdbId);
          await _seasonRepo.deleteByShowId(entry.tmdbId);
          await _stateRepo.delete(entry.tmdbId);
          await _showRepo.delete(entry.tmdbId);
        }
        await _documents.deleteFor(entry.type, entry.tmdbId);
        await _assetJobs.deleteForItem(entry.type, entry.tmdbId);
        await _pending.delete(entry.type, entry.tmdbId);
      });
      try {
        await _artwork().itemUntracked(item);
      } catch (e, stackTrace) {
        _log.warning('Could not remove the artwork of $item: $e', e, stackTrace);
      }
      removed++;
      _log.info('Removed $item from the library');
    }
    return removed;
  }

  /// Every tracked movie and show key — for the library marks on browse grids.
  Future<Set<MediaKey>> trackedKeys() async {
    return {
      for (final id in await _movieRepo.getAllIds()) MediaKey.movie(id),
      for (final id in await _showRepo.getAllIds()) MediaKey.show(id),
    };
  }

  Future<void> _enqueueArtwork(MediaKey item) async {
    try {
      final manifest = item.type == ItemType.movie ? await _manifests.forMovie(item.tmdbId) : await _manifests.forShow(item.tmdbId);
      if (manifest != null) {
        await _artwork().itemTracked(manifest);
      }
    } catch (e, stackTrace) {
      _log.warning('Could not queue the artwork of $item: $e', e, stackTrace);
    }
  }
}
