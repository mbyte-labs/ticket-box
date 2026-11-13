import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/database/sql_store/catalog/catalog_refresh_queries.dart';
import 'package:ticketbox/database/sql_store/job_state/job_constants.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_repository.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/service/artwork/artwork_service.dart';
import 'package:ticketbox/service/catalog/library_backfill_service.dart';
import 'package:ticketbox/service/catalog/outage_breaker.dart';
import 'package:ticketbox/service/catalog/watch_region.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/library/show_state_service.dart';
import 'package:ticketbox/service/movie/movie_service.dart';
import 'package:ticketbox/service/progress/progress_error_classifier.dart';
import 'package:ticketbox/service/show/show_service.dart';

/// The one scheduler: keeps the library's snapshots fresh without a render-path request.
///
/// A tick runs on launch, on resume and from a foreground timer, gated by [isDue] (a cooldown,
/// or missing snapshots). It selects by `fetched_at`, the only freshness state — the row's
/// timestamp *is* the schedule, so a restart self-heals and a page view that refreshed an item
/// merely postpones it:
///
/// 1. the backfill of snapshots still missing;
/// 2. the ACTIVE class ([activeInterval]): every movie and show on the watchlist or favorites, plus
///    followed shows still in production — and followed shows whose announced episode has aired
///    since the snapshot, whatever its age;
/// 3. the ARCHIVE class ([archiveInterval]): watched movies and followed ended / canceled shows on
///    no list;
/// 4. the items whose stored watch providers were pruned to another region than the configured one.
///
/// Per show the root plus the open seasons are refreshed and new seasons materialised. A circuit
/// breaker abandons fetching after three consecutive outages. **Every tick ends with the state
/// sweep** (which needs no network and flips `watched → watching` when an episode aired overnight)
/// and the deletion sweep. The tick never throws: its outcome lands on the
/// [CATALOG_REFRESH_JOB_ID] row the app-bar indicator renders.
class CatalogRefreshService {
  static final _log = Logger('[Service] CatalogRefreshService');

  static const Duration activeInterval = Duration(days: 7);
  static const Duration archiveInterval = Duration(days: 90);
  static const Duration tickCooldown = Duration(minutes: 15);
  static const Duration foregroundPeriod = Duration(hours: 6);
  static const int outageLimit = 3;
  static const int chunkSize = 3;

  static Future<void>? _inFlight;
  static Timer? _timer;

  final JobStateRepo _jobRepo;
  final CatalogRefreshQueries _queries;
  final MovieService _movies;
  final ShowService _shows;
  final LibraryBackfillService _backfill;
  final ShowStateService _state;
  final LibraryService _library;
  final ArtworkService Function() _artwork;

  CatalogRefreshService({
    JobStateRepo? jobRepo,
    CatalogRefreshQueries? queries,
    MovieService? movies,
    ShowService? shows,
    LibraryBackfillService? backfill,
    ShowStateService? state,
    LibraryService? library,
    ArtworkService Function()? artwork,
  }) : _jobRepo = jobRepo ?? JobStateRepo(),
       _queries = queries ?? CatalogRefreshQueries(),
       _movies = movies ?? MovieService(),
       _shows = shows ?? ShowService(),
       _backfill = backfill ?? LibraryBackfillService(),
       _state = state ?? ShowStateService(),
       _library = library ?? LibraryService.instance(),
       _artwork = artwork ?? ArtworkService.instance;

  static CatalogRefreshService instance() {
    if (GetIt.I.isRegistered<CatalogRefreshService>()) {
      return GetIt.I.get<CatalogRefreshService>();
    }
    final service = CatalogRefreshService();
    GetIt.I.registerSingleton<CatalogRefreshService>(service);
    return service;
  }

  /// Whether a tick is worth starting: never ran, failed last time, the cooldown elapsed, or
  /// snapshots are missing.
  Future<bool> isDue() async {
    final job = await _jobRepo.get(CATALOG_REFRESH_JOB_ID);
    if (job.state == JobState.idle || job.state == JobState.failed) {
      return true;
    }
    final lastAttempt = job.finishedAt.isAfter(job.startedAt) ? job.finishedAt : job.startedAt;
    if (DateTime.now().difference(lastAttempt) >= tickCooldown) {
      return true;
    }
    return _backfill.hasPending();
  }

  /// Starts a tick in the background when one is due. Never throws.
  Future<void> tickIfDue() async {
    try {
      if (!await isDue()) {
        _log.fine('Catalogue refreshed recently. Skipping');
        return;
      }
    } catch (e, stackTrace) {
      _log.warning('Could not decide whether a refresh is due: $e', e, stackTrace);
      return;
    }
    unawaited(tick());
  }

  /// Runs a tick, joining one already in flight instead of starting a second.
  Future<void> tick() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      _log.info('Catalogue refresh already in progress. Joining the run in flight');
      return inFlight;
    }
    late final Future<void> run;
    run = _tick().whenComplete(() {
      if (_inFlight == run) {
        _inFlight = null;
      }
    });
    _inFlight = run;
    return run;
  }

  /// A periodic tick while the app stays in the foreground; idempotent.
  void startForegroundTimer() {
    _timer ??= Timer.periodic(foregroundPeriod, (_) => unawaited(tickIfDue()));
  }

  static void stopForegroundTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    _log.info('Starting catalogue refresh');
    var errorCode = JobErrorCode.none;
    try {
      await _markStart();
      errorCode = await _run();
    } catch (e, stackTrace) {
      _log.severe('Exception refreshing the catalogue', e, stackTrace);
      errorCode = classifyJobError(e);
    }
    try {
      await _markFinished(errorCode);
    } catch (e, stackTrace) {
      _log.severe('Could not record the catalogue refresh outcome', e, stackTrace);
    }
    _log.info('Finished catalogue refresh. Error code: ${errorCode.name}');
  }

  Future<JobErrorCode> _run() async {
    final breaker = OutageBreaker(limit: outageLimit);
    final now = DateTime.now().toUtc();
    final region = await WatchRegion.configured();

    final backfilled = await _backfill.run(
      breaker: breaker,
      now: now,
      onProgress: (message) => _jobRepo.updateMessage(CATALOG_REFRESH_JOB_ID, message),
    );
    if (backfilled > 0) {
      _log.info('Backfilled $backfilled snapshot(s)');
    }

    if (!breaker.tripped) {
      final today = ShowProgressQueries.today(now);
      final movieIds = <int>{
        ...await _queries.activeMovieIds(now.subtract(activeInterval)),
        ...await _queries.archiveMovieIds(now.subtract(archiveInterval)),
        ...await _queries.movieIdsWithOtherRegion(region),
      };
      final showIds = <int>{
        ...await _queries.activeShowIds(now.subtract(activeInterval), today),
        ...await _queries.archiveShowIds(now.subtract(archiveInterval)),
        ...await _queries.showIdsWithOtherRegion(region),
      };
      if (movieIds.isEmpty && showIds.isEmpty) {
        _log.info('Nothing to refresh: every snapshot is current');
      } else {
        _log.info('Refreshing ${movieIds.length} movie(s) and ${showIds.length} show(s)');
        await _jobRepo.updateMessage(CATALOG_REFRESH_JOB_ID, 'Refreshing ${movieIds.length + showIds.length} title(s)…');
        await _refreshAll(movieIds.toList(), (id) => _movies.refresh(id, region: region, now: now), breaker);
        await _refreshAll(showIds.toList(), (id) => _shows.refreshForScheduler(id, region: region, now: now), breaker);
      }
    }

    // Always, even with the breaker tripped: it needs no network.
    await _state.recomputeAll(now: now);
    final removed = await _library.sweepPendingDeletions(now: now);
    if (removed > 0) {
      _log.info('Removed $removed item(s) nothing referenced any more');
    }
    _artwork().kick();
    return breaker.code;
  }

  Future<void> _refreshAll(List<int> ids, Future<bool> Function(int id) refresh, OutageBreaker breaker) async {
    for (final chunk in ids.chunked(chunkSize)) {
      if (breaker.tripped) {
        _log.warning('TMDB unreachable; abandoning the refresh until the next tick');
        return;
      }
      await Future.wait(
        chunk.map((id) async {
          try {
            await refresh(id);
            breaker.recordSuccess();
          } catch (e, stackTrace) {
            if (!breaker.record(e)) {
              _log.warning('Could not refresh $id: $e', e, stackTrace);
            }
          }
        }),
      );
    }
  }

  Future<void> _markStart() async {
    final job = await _jobRepo.get(CATALOG_REFRESH_JOB_ID);
    job.startedAt = DateTime.now();
    job.state = JobState.running;
    job.errorCode = JobErrorCode.none;
    job.userMessage = null;
    await _jobRepo.insert(job);
  }

  Future<void> _markFinished(JobErrorCode errorCode) async {
    final job = await _jobRepo.get(CATALOG_REFRESH_JOB_ID);
    job.errorCode = errorCode;
    if (errorCode == JobErrorCode.none) {
      job.state = JobState.finished;
      job.finishedAt = DateTime.now();
    } else {
      job.state = JobState.failed;
    }
    job.userMessage = null;
    await _jobRepo.insert(job);
  }
}
