import 'dart:async';

import 'package:logging/logging.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_account_api.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_account_models.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_rating_api.dart';
import 'package:ticketbox/api/tmdb/v3/model/tmdb_page.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_entity.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/job_state/job_constants.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_entity.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/catalog/catalog_refresh_service.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/progress/progress_error_classifier.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_session_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_outbox_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_support.dart';

/// What to do with one data set when the account is first connected (or on "Sync now").
enum TmdbSyncChoice {
  /// The list on the device becomes a copy of the TMDB list.
  pull,

  /// Every item on the device is written to TMDB; nothing on TMDB is removed.
  push,

  skip,
}

class TmdbSyncChoices {
  final TmdbSyncChoice ratings;
  final TmdbSyncChoice watchlist;
  final TmdbSyncChoice favorites;

  const TmdbSyncChoices({required this.ratings, required this.watchlist, required this.favorites});

  const TmdbSyncChoices.skipAll() : ratings = TmdbSyncChoice.skip, watchlist = TmdbSyncChoice.skip, favorites = TmdbSyncChoice.skip;

  TmdbSyncChoice of(TmdbDataSet dataSet) => switch (dataSet) {
    TmdbDataSet.ratings => ratings,
    TmdbDataSet.watchlist => watchlist,
    TmdbDataSet.favorites => favorites,
  };

  bool get isNoOp => TmdbDataSet.values.every((dataSet) => of(dataSet) == TmdbSyncChoice.skip);

  bool get pullsAnything => TmdbDataSet.values.any((dataSet) => of(dataSet) == TmdbSyncChoice.pull);

  TmdbSyncChoices withChoice(TmdbDataSet dataSet, TmdbSyncChoice choice) => TmdbSyncChoices(
    ratings: dataSet == TmdbDataSet.ratings ? choice : ratings,
    watchlist: dataSet == TmdbDataSet.watchlist ? choice : watchlist,
    favorites: dataSet == TmdbDataSet.favorites ? choice : favorites,
  );
}

/// The outcome for one data set: rows written locally, rows TMDB took, rows left in the outbox.
typedef TmdbDataSetSyncResult = ({int pulled, int pushed, int queued});

class TmdbInitialSyncResult {
  final Map<TmdbDataSet, TmdbDataSetSyncResult> perDataSet;
  final JobErrorCode errorCode;

  /// A user-facing reason when the run stopped early, null when it completed.
  final String? failureMessage;

  const TmdbInitialSyncResult({required this.perDataSet, required this.errorCode, this.failureMessage});

  bool get succeeded => errorCode == JobErrorCode.none;
}

/// The one-time sync run after connecting the TMDB account, and again from "Sync now".
///
/// A **pull** downloads the whole TMDB list (every page, a few at a time) and only then replaces
/// the local rows in one batch, so a failure half-way changes nothing. A **push** sends every local
/// item that has a place on TMDB, a few at a time; an item TMDB refuses is queued in the outbox for
/// a later flush, and as soon as TMDB looks unreachable the rest is queued too instead of timing
/// out one by one. The run reports on the `TMDB_SYNC_JOB_ID` row and never throws; the Settings
/// page reads the returned summary.
class TmdbInitialSyncService {
  static final _log = Logger('[Service] TmdbInitialSyncService');

  static const int chunkSize = 4;

  /// TMDB caps every list at 500 pages.
  static const int maxPages = 500;

  static Future<TmdbInitialSyncResult>? _inFlight;

  final TmdbSessionService Function() _session;
  final TmdbAccountApi _accountApi;
  final TmdbRatingApi _ratingApi;
  final JobStateRepo Function() _jobRepo;
  final UserRatingRepo Function() _ratingRepo;
  final WatchlistRepo Function() _watchlistRepo;
  final FavoriteRepo Function() _favoriteRepo;
  final TmdbSyncOutboxRepo Function() _outboxRepo;
  final TmdbSyncOutboxService Function() _outboxService;
  final MovieRepo Function() _movieRepo;
  final ShowRepo Function() _showRepo;
  final LibraryService Function() _library;

  TmdbInitialSyncService({
    TmdbSessionService Function()? session,
    TmdbAccountApi? accountApi,
    TmdbRatingApi? ratingApi,
    JobStateRepo Function()? jobRepo,
    UserRatingRepo Function()? ratingRepo,
    WatchlistRepo Function()? watchlistRepo,
    FavoriteRepo Function()? favoriteRepo,
    TmdbSyncOutboxRepo Function()? outboxRepo,
    TmdbSyncOutboxService Function()? outboxService,
    MovieRepo Function()? movieRepo,
    ShowRepo Function()? showRepo,
    LibraryService Function()? library,
  }) : _session = session ?? TmdbSessionService.instance,
       _accountApi = accountApi ?? TmdbAccountApi(),
       _ratingApi = ratingApi ?? TmdbRatingApi(),
       _jobRepo = jobRepo ?? JobStateRepo.new,
       _ratingRepo = ratingRepo ?? UserRatingRepo.new,
       _watchlistRepo = watchlistRepo ?? WatchlistRepo.new,
       _favoriteRepo = favoriteRepo ?? FavoriteRepo.new,
       _outboxRepo = outboxRepo ?? TmdbSyncOutboxRepo.new,
       _outboxService = outboxService ?? TmdbSyncOutboxService.instance,
       _movieRepo = movieRepo ?? MovieRepo.new,
       _showRepo = showRepo ?? ShowRepo.new,
       _library = library ?? LibraryService.instance;

  /// Runs [choices], joining a run already in flight instead of starting a second one.
  Future<TmdbInitialSyncResult> run(TmdbSyncChoices choices) {
    final inFlight = _inFlight;
    if (inFlight != null) {
      _log.info('A TMDB sync is already running. Joining it');
      return inFlight;
    }
    late final Future<TmdbInitialSyncResult> run;
    run = _run(choices).whenComplete(() {
      if (_inFlight == run) {
        _inFlight = null;
      }
    });
    _inFlight = run;
    return run;
  }

  Future<TmdbInitialSyncResult> _run(TmdbSyncChoices choices) async {
    final session = _session().session;
    if (session == null) {
      return const TmdbInitialSyncResult(perDataSet: {}, errorCode: JobErrorCode.unknownError, failureMessage: 'Not logged in to TMDB.');
    }
    _log.info(
      'Starting TMDB sync: ratings ${choices.ratings.name}, watchlist ${choices.watchlist.name}, favorites ${choices.favorites.name}',
    );
    final results = <TmdbDataSet, TmdbDataSetSyncResult>{};
    var errorCode = JobErrorCode.none;
    String? failure;
    try {
      await _markStart();
      for (final dataSet in TmdbDataSet.values) {
        final choice = choices.of(dataSet);
        if (choice == TmdbSyncChoice.skip) {
          continue;
        }
        await _jobRepo().updateMessage(
          TMDB_SYNC_JOB_ID,
          '${choice == TmdbSyncChoice.pull ? 'Pulling' : 'Pushing'} ${dataSet.label.toLowerCase()} ${choice == TmdbSyncChoice.pull ? 'from' : 'to'} TMDB…',
        );
        results[dataSet] = choice == TmdbSyncChoice.pull ? await _pull(dataSet, session) : await _push(dataSet, session);
        // A data set the user just synced is kept in sync from here on; a skipped one keeps its toggle.
        await _session().setSyncEnabled(dataSet, true);
      }
    } on ApiUnauthorizedException catch (e, stackTrace) {
      _log.severe('TMDB rejected the session during the sync', e, stackTrace);
      if (e.isSessionProblem) {
        await _session().invalidateSession();
        failure = 'Your TMDB session is no longer valid. Log in again.';
      } else {
        failure = 'TMDB rejected the request.';
      }
      errorCode = JobErrorCode.unknownError;
    } catch (e, stackTrace) {
      _log.severe('TMDB sync failed', e, stackTrace);
      errorCode = classifyJobError(e);
      failure = switch (errorCode) {
        JobErrorCode.networkError => 'TMDB could not be reached. Check your connection and try again.',
        JobErrorCode.serviceDown => 'TMDB is having trouble right now. Try again later.',
        JobErrorCode.rateLimited => 'TMDB asked for a pause. Try again in a minute.',
        JobErrorCode.none || JobErrorCode.unknownError => 'Something went wrong while syncing with TMDB.',
      };
    }
    try {
      await _markFinished(errorCode);
    } catch (e, stackTrace) {
      _log.severe('Could not record the TMDB sync outcome', e, stackTrace);
    }
    _log.info('Finished TMDB sync. Error code: ${errorCode.name}, results: $results');
    unawaited(_outboxService().flush());
    // The pulled titles are stubs until the catalogue refresh fetches their snapshots.
    unawaited(CatalogRefreshService.instance().tick());
    return TmdbInitialSyncResult(perDataSet: results, errorCode: errorCode, failureMessage: failure);
  }

  Future<TmdbDataSetSyncResult> _pull(TmdbDataSet dataSet, TmdbSessionSnapshot session) async {
    final accountId = session.accountId;
    final sessionId = session.sessionId;
    final now = DateTime.now().toUtc();
    final int pulled;
    switch (dataSet) {
      case TmdbDataSet.ratings:
        final movies = await _pullAll((page) => _accountApi.ratedMovies(accountId, sessionId, page));
        final shows = await _pullAll((page) => _accountApi.ratedShows(accountId, sessionId, page));
        final episodes = await _pullAll((page) => _accountApi.ratedEpisodes(accountId, sessionId, page));
        final rows = <UserRatingEntity>[
          for (final movie in movies)
            UserRatingEntity.build(
              type: ItemType.movie,
              tmdbId: movie.id,
              rating: TmdbSyncSupport.roundTmdbRating(movie.rating),
              ratedAt: now,
            ),
          for (final show in shows)
            UserRatingEntity.build(
              type: ItemType.show,
              tmdbId: show.id,
              rating: TmdbSyncSupport.roundTmdbRating(show.rating),
              ratedAt: now,
            ),
          for (final episode in episodes)
            UserRatingEntity.build(
              type: ItemType.episode,
              tmdbId: episode.showId,
              season: episode.seasonNumber,
              episode: episode.episodeNumber,
              rating: TmdbSyncSupport.roundTmdbRating(episode.rating),
              ratedAt: now,
            ),
        ];
        await _ratingRepo().replaceAll(rows);
        await _trackPulled(
          movieIds: [for (final movie in movies) movie.id],
          showIds: [for (final show in shows) show.id, for (final episode in episodes) episode.showId],
          now: now,
        );
        pulled = rows.length;
      case TmdbDataSet.watchlist:
        final movies = await _pullAll((page) => _accountApi.watchlistMovies(accountId, sessionId, page));
        final shows = await _pullAll((page) => _accountApi.watchlistShows(accountId, sessionId, page));
        final rows = <WatchlistEntity>[
          for (final movie in movies) WatchlistEntity.build(type: ItemType.movie, tmdbId: movie.id, listedAt: now),
          for (final show in shows) WatchlistEntity.build(type: ItemType.show, tmdbId: show.id, listedAt: now),
        ];
        await _watchlistRepo().replaceMoviesAndShows(rows);
        await _trackPulled(movieIds: [for (final movie in movies) movie.id], showIds: [for (final show in shows) show.id], now: now);
        pulled = rows.length;
      case TmdbDataSet.favorites:
        final movies = await _pullAll((page) => _accountApi.favoriteMovies(accountId, sessionId, page));
        final shows = await _pullAll((page) => _accountApi.favoriteShows(accountId, sessionId, page));
        final rows = <FavoriteEntity>[
          for (final movie in movies) FavoriteEntity.build(type: ItemType.movie, tmdbId: movie.id, favoritedAt: now),
          for (final show in shows) FavoriteEntity.build(type: ItemType.show, tmdbId: show.id, favoritedAt: now),
        ];
        await _favoriteRepo().replaceAll(rows);
        await _trackPulled(movieIds: [for (final movie in movies) movie.id], showIds: [for (final show in shows) show.id], now: now);
        pulled = rows.length;
    }
    // Pending pushes refer to the list that was just replaced.
    await _outboxRepo().deleteByDataSet(dataSet);
    _log.info('Pulled $pulled ${dataSet.name} row(s) from TMDB');
    return (pulled: pulled, pushed: 0, queued: 0);
  }

  /// A pull is a tracking action: every pulled title gets a catalogue stub row (`fetched_at`
  /// null) so it is in the library; the catalogue refresh backfills the snapshots and artwork
  /// afterwards (see [run]'s tail). Items the pull removed from a list are queued for the
  /// deletion sweep when nothing else references them.
  Future<void> _trackPulled({required List<int> movieIds, required List<int> showIds, required DateTime now}) async {
    await _movieRepo().insertStubs(movieIds, trackedAt: now);
    await _showRepo().insertStubs(showIds, trackedAt: now);
    await _library().enqueueUnreferenced(now: now);
  }

  /// Every row of a paged list: page one, then the rest a few pages at a time.
  Future<List<T>> _pullAll<T>(Future<TmdbPage<T>> Function(int page) fetch) async {
    final first = await fetch(1);
    final results = <T>[...first.results];
    final lastPage = first.totalPages.clamp(0, maxPages);
    if (lastPage <= 1) {
      return results;
    }
    final remaining = [for (var page = 2; page <= lastPage; page++) page];
    for (final chunk in remaining.chunked(chunkSize)) {
      final pages = await Future.wait(chunk.map(fetch));
      for (final page in pages) {
        results.addAll(page.results);
      }
    }
    return results;
  }

  Future<TmdbDataSetSyncResult> _push(TmdbDataSet dataSet, TmdbSessionSnapshot session) async {
    final accountId = session.accountId;
    final sessionId = session.sessionId;
    switch (dataSet) {
      case TmdbDataSet.ratings:
        final rows = (await _ratingRepo().getAll()).where((row) => TmdbSyncSupport.canSync(dataSet, row.key)).toList();
        return _pushAll<UserRatingEntity>(
          dataSet,
          rows,
          key: (row) => row.key,
          operation: (_) => TmdbSyncOperation.rate,
          rating: (row) => row.rating,
          send: (row) async {
            final value = TmdbSyncSupport.toTmdbRating(row.rating);
            switch (row.type) {
              case ItemType.movie:
                await _ratingApi.rateMovie(row.tmdbId, value, sessionId);
              case ItemType.show:
                await _ratingApi.rateShow(row.tmdbId, value, sessionId);
              case ItemType.episode:
                await _ratingApi.rateEpisode(row.tmdbId, row.season, row.episode, value, sessionId);
              case ItemType.season:
                throw ArgumentError('a season cannot be rated');
            }
          },
        );
      case TmdbDataSet.watchlist:
        final rows = (await _watchlistRepo().getAll()).where((row) => TmdbSyncSupport.canSync(dataSet, row.key)).toList();
        return _pushAll<WatchlistEntity>(
          dataSet,
          rows,
          key: (row) => row.key,
          operation: (_) => TmdbSyncOperation.watchlistAdd,
          rating: (_) => null,
          send: (row) => _accountApi.setWatchlist(
            accountId: accountId,
            sessionId: sessionId,
            mediaType: TmdbMediaType.fromItemType(row.type)!,
            mediaId: row.tmdbId,
            listed: true,
          ),
        );
      case TmdbDataSet.favorites:
        final rows = (await _favoriteRepo().getAll()).where((row) => TmdbSyncSupport.canSync(dataSet, row.key)).toList();
        return _pushAll<FavoriteEntity>(
          dataSet,
          rows,
          key: (row) => row.key,
          operation: (_) => TmdbSyncOperation.favoriteAdd,
          rating: (_) => null,
          send: (row) => _accountApi.setFavorite(
            accountId: accountId,
            sessionId: sessionId,
            mediaType: TmdbMediaType.fromItemType(row.type)!,
            mediaId: row.tmdbId,
            favorite: true,
          ),
        );
    }
  }

  /// Sends [items] a chunk at a time. An item TMDB refuses for a reason of its own is queued; the
  /// first sign that TMDB is unreachable queues everything left and stops. A session 401 escapes
  /// to [_run], which invalidates the session.
  Future<TmdbDataSetSyncResult> _pushAll<T>(
    TmdbDataSet dataSet,
    List<T> items, {
    required MediaKey Function(T item) key,
    required TmdbSyncOperation Function(T item) operation,
    required int? Function(T item) rating,
    required Future<void> Function(T item) send,
  }) async {
    var pushed = 0;
    var queued = 0;
    final chunks = items.chunked(chunkSize).toList();
    for (var index = 0; index < chunks.length; index++) {
      final chunk = chunks[index];
      final outcomes = await Future.wait(chunk.map((item) => _sendOne(item, send)));
      var unreachable = false;
      for (var i = 0; i < chunk.length; i++) {
        switch (outcomes[i]) {
          case _PushOk():
            pushed++;
          case _PushDropped():
            break;
          case _PushFailed(:final systemic):
            await _outboxRepo().enqueue(operation: operation(chunk[i]), key: key(chunk[i]), rating: rating(chunk[i]));
            queued++;
            unreachable = unreachable || systemic;
        }
      }
      if (unreachable) {
        for (final item in chunks.skip(index + 1).expand((chunk) => chunk)) {
          await _outboxRepo().enqueue(operation: operation(item), key: key(item), rating: rating(item));
          queued++;
        }
        _log.info('TMDB unreachable while pushing ${dataSet.name}; queued the remaining $queued item(s)');
        break;
      }
    }
    _log.info('Pushed $pushed ${dataSet.name} row(s) to TMDB, queued $queued');
    return (pulled: 0, pushed: pushed, queued: queued);
  }

  Future<_PushOneOutcome> _sendOne<T>(T item, Future<void> Function(T item) send) async {
    try {
      await send(item);
      return const _PushOk();
    } on ApiUnauthorizedException {
      rethrow;
    } on ApiNotFoundException {
      return const _PushDropped();
    } on ArgumentError {
      return const _PushDropped();
    } catch (e, stackTrace) {
      final code = classifyJobError(e);
      _log.warning('Could not push an item to TMDB (${code.name}), queued for later', e, stackTrace);
      return _PushFailed(
        systemic: code == JobErrorCode.networkError || code == JobErrorCode.serviceDown || code == JobErrorCode.rateLimited,
      );
    }
  }

  Future<void> _markStart() async {
    final job = await _jobRepo().get(TMDB_SYNC_JOB_ID);
    job.startedAt = DateTime.now();
    job.state = JobState.running;
    job.errorCode = JobErrorCode.none;
    job.userMessage = null;
    await _jobRepo().insert(job);
  }

  Future<void> _markFinished(JobErrorCode errorCode) async {
    final job = await _jobRepo().get(TMDB_SYNC_JOB_ID);
    job.errorCode = errorCode;
    if (errorCode == JobErrorCode.none) {
      job.state = JobState.finished;
      job.finishedAt = DateTime.now();
    } else {
      job.state = JobState.failed;
    }
    job.userMessage = null;
    await _jobRepo().insert(job);
  }
}

sealed class _PushOneOutcome {
  const _PushOneOutcome();
}

class _PushOk extends _PushOneOutcome {
  const _PushOk();
}

class _PushDropped extends _PushOneOutcome {
  const _PushDropped();
}

class _PushFailed extends _PushOneOutcome {
  final bool systemic;

  const _PushFailed({required this.systemic});
}
