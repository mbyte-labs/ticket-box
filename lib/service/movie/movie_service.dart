import 'package:logging/logging.dart';
import 'package:ticketbox/api/tmdb/v3/movie/movie_details_api.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/snapshot/snapshot_document_repo.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/catalog/catalog_artwork_manifests.dart';
import 'package:ticketbox/service/catalog/catalog_writer.dart';
import 'package:ticketbox/service/catalog/snapshot_fallback.dart';
import 'package:ticketbox/service/catalog/snapshot_freshness.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';
import 'package:ticketbox/service/catalog/snapshots.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';

/// A movie's details, the way the movie page reads them.
///
/// Tracked: served from the stored snapshot, immediately and offline; the page then asks
/// [refreshIfStale], which re-fetches once the snapshot is older than
/// [SnapshotFreshness.viewTtl] (or was pruned to another watch region) and keeps the stale copy
/// when TMDB cannot be reached. Untracked: fetched live and discarded — nothing is written by a
/// view — and an outage surfaces as the transport error for the page to render.
class MovieService {
  static final _log = Logger('[Service] MovieService');

  final MovieRepo _movieRepo;
  final SnapshotDocumentRepo _documents;
  final TmdbMovieDetailsApi _api;
  final CatalogWriter _writer;
  final CatalogArtworkManifests _manifests;
  final ArtworkService Function() _artwork;

  MovieService({
    MovieRepo? movieRepo,
    SnapshotDocumentRepo? documents,
    TmdbMovieDetailsApi? api,
    CatalogWriter? writer,
    CatalogArtworkManifests? manifests,
    ArtworkService Function()? artwork,
  }) : _movieRepo = movieRepo ?? MovieRepo(),
       _documents = documents ?? SnapshotDocumentRepo(),
       _api = api ?? TmdbMovieDetailsApi(),
       _writer = writer ?? CatalogWriter(),
       _manifests = manifests ?? CatalogArtworkManifests(),
       _artwork = artwork ?? ArtworkService.instance;

  /// The stored snapshot of a tracked movie (synthetic from the convenience columns while the
  /// backfill has not fetched the document yet), or null when the movie is not in the library.
  Future<MovieSnapshot?> getLocal(int tmdbId) async {
    final row = await _movieRepo.get(tmdbId);
    if (row == null) {
      return null;
    }
    final json = row.hasSnapshot ? await _documents.getMovie(tmdbId) : null;
    if (json == null) {
      return SnapshotFallback.movie(row);
    }
    try {
      return MovieSnapshot.fromJson(json, fetchedAt: row.fetchedAt, providersRegion: row.watchProvidersRegion);
    } catch (e, stackTrace) {
      _log.warning('Corrupt snapshot of movie $tmdbId, rendering the row: $e', e, stackTrace);
      return SnapshotFallback.movie(row);
    }
  }

  /// Tracked → the local snapshot; untracked → live from TMDB, nothing written. Throws
  /// [ItemGoneException] when TMDB has no such movie, and the transport error when an untracked
  /// movie cannot be fetched.
  Future<MovieSnapshot> getDetails(int tmdbId, {required String? region}) async {
    final local = await getLocal(tmdbId);
    if (local != null) {
      return local;
    }
    final raw = await _api.getRaw(tmdbId);
    if (raw == null) {
      throw ItemGoneException(MediaKey.movie(tmdbId));
    }
    return MovieSnapshot.live(raw, region: region);
  }

  /// Re-fetches a tracked movie whose snapshot is stale or pruned to another region; the fresh
  /// snapshot, or null when nothing was refreshed (fresh, untracked, or TMDB unreachable — logged,
  /// the stale copy stays).
  Future<MovieSnapshot?> refreshIfStale(int tmdbId, {required String? region, DateTime? now}) async {
    final row = await _movieRepo.get(tmdbId);
    if (row == null) {
      return null;
    }
    if (!SnapshotFreshness.isStale(row.fetchedAt, now: now) && row.watchProvidersRegion == region) {
      return null;
    }
    try {
      if (!await refresh(tmdbId, region: region, now: now)) {
        return null;
      }
    } catch (e, stackTrace) {
      _log.warning('Serving the stale snapshot of movie $tmdbId: $e', e, stackTrace);
      return null;
    }
    return getLocal(tmdbId);
  }

  /// Fetches and stores a tracked movie's snapshot (the scheduler, the backfill, a stale view).
  /// A 404 keeps the row and moves its freshness forward (false); transport errors propagate.
  Future<bool> refresh(int tmdbId, {required String? region, DateTime? now}) async {
    final moment = now ?? DateTime.now().toUtc();
    final raw = await _api.getRaw(tmdbId);
    if (raw == null) {
      _log.warning('Movie $tmdbId is gone from TMDB, keeping the local copy');
      await _movieRepo.stampFetched(tmdbId, moment);
      return false;
    }
    await _writer.writeMovie(
      SnapshotPruner.movie(raw, region: region),
      now: moment,
      region: region,
    );
    try {
      final manifest = await _manifests.forMovie(tmdbId);
      if (manifest != null) {
        await _artwork().itemRefreshed(manifest);
      }
    } catch (e, stackTrace) {
      _log.warning('Could not reconcile the artwork of movie $tmdbId: $e', e, stackTrace);
    }
    return true;
  }
}
