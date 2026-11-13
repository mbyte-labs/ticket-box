import 'package:logging/logging.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/catalog/outage_breaker.dart';
import 'package:ticketbox/service/catalog/show_snapshot_refresher.dart';
import 'package:ticketbox/service/catalog/watch_region.dart';
import 'package:ticketbox/service/library/library_exceptions.dart';
import 'package:ticketbox/service/library/library_service.dart';

/// Fetches the snapshots the library is still missing: every tracked movie and show with no
/// document yet (the rows the v10 migration, a backup restore or a TMDB account pull created), then
/// the seasons of fetched shows that were never fetched.
///
/// Resumable by construction — whatever was written stays and the next tick continues; it stops
/// at the tick's circuit breaker. Runs inside the catalogue refresh tick, which reports it on the
/// job row and ends with the state sweep.
class LibraryBackfillService {
  static final _log = Logger('[Service] LibraryBackfillService');

  static const int chunkSize = 3;

  final MovieRepo _movieRepo;
  final ShowRepo _showRepo;
  final SeasonRepo _seasonRepo;
  final LibraryService _library;
  final ShowSnapshotRefresher _shows;

  LibraryBackfillService({
    MovieRepo? movieRepo,
    ShowRepo? showRepo,
    SeasonRepo? seasonRepo,
    LibraryService? library,
    ShowSnapshotRefresher? shows,
  }) : _movieRepo = movieRepo ?? MovieRepo(),
       _showRepo = showRepo ?? ShowRepo(),
       _seasonRepo = seasonRepo ?? SeasonRepo(),
       _library = library ?? LibraryService.instance(),
       _shows = shows ?? ShowSnapshotRefresher();

  /// How many tracked items still have no snapshot.
  Future<int> pendingCount() async {
    return (await _movieRepo.getIdsWithoutSnapshot()).length + (await _showRepo.getIdsWithoutSnapshot()).length;
  }

  Future<bool> hasPending() async => await pendingCount() > 0;

  /// Materialises the missing snapshots, [chunkSize] at a time, reporting through [onProgress].
  /// Returns how many items were fetched; stops early when [breaker] trips.
  Future<int> run({required OutageBreaker breaker, void Function(String message)? onProgress, DateTime? now}) async {
    final keys = [
      ...(await _movieRepo.getIdsWithoutSnapshot()).map(MediaKey.movie),
      ...(await _showRepo.getIdsWithoutSnapshot()).map(MediaKey.show),
    ];
    var fetched = 0;
    if (keys.isNotEmpty) {
      _log.info('Backfilling ${keys.length} snapshot(s)');
      for (final chunk in keys.chunked(chunkSize)) {
        if (breaker.tripped) {
          break;
        }
        onProgress?.call('Saving offline copies: $fetched of ${keys.length}…');
        await Future.wait(
          chunk.map((key) async {
            try {
              await _library.materialise(key, now: now);
              breaker.recordSuccess();
              fetched++;
            } on ItemGoneException {
              _log.warning('$key is gone from TMDB; its rows stay as they are');
              await _stampGone(key, now);
            } on TrackingUnavailableException catch (e) {
              if (!breaker.record(e.cause)) {
                _log.warning('Could not backfill $key: ${e.cause}');
              }
            } catch (e, stackTrace) {
              _log.warning('Could not backfill $key: $e', e, stackTrace);
              breaker.record(e);
            }
          }),
        );
      }
    }
    if (!breaker.tripped) {
      fetched += await _fetchUnfetchedSeasons(breaker, now);
    }
    return fetched;
  }

  /// Seasons of fetched shows that have no document (a tracking action interrupted half-way).
  Future<int> _fetchUnfetchedSeasons(OutageBreaker breaker, DateTime? now) async {
    final region = await WatchRegion.configured();
    var fetched = 0;
    for (final show in await _showRepo.getAll()) {
      if (breaker.tripped) {
        break;
      }
      if (!show.hasSnapshot) {
        continue;
      }
      final missing = await _seasonRepo.getUnfetchedSeasonNumbers(show.tmdbId);
      if (missing.isEmpty) {
        continue;
      }
      try {
        await _shows.fetchSeasons(show.tmdbId, missing, region: region, now: now);
        breaker.recordSuccess();
        fetched++;
      } catch (e, stackTrace) {
        _log.warning('Could not fetch the missing seasons of show ${show.tmdbId}: $e', e, stackTrace);
        breaker.record(e);
      }
    }
    return fetched;
  }

  /// A row TMDB has no item for keeps serving what it has; stamping it takes it off the work list.
  Future<void> _stampGone(MediaKey key, DateTime? now) async {
    final moment = now ?? DateTime.now().toUtc();
    if (key.type == ItemType.movie) {
      await _movieRepo.stampFetched(key.tmdbId, moment);
    } else {
      await _showRepo.stampFetched(key.tmdbId, moment);
    }
  }
}
