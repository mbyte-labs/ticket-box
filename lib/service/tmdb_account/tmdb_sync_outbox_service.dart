import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_account_api.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_account_models.dart';
import 'package:ticketbox/api/tmdb/v3/account/tmdb_rating_api.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_entity.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';
import 'package:ticketbox/service/progress/progress_error_classifier.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_session_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_support.dart';

/// Drains the TMDB sync outbox: every queued write is sent, in order, a few at a time.
///
/// Never throws and joins a run already in flight. A row that TMDB took is deleted; a row TMDB
/// has no title for is dropped; a row that failed for a reason of its own is retried on later
/// flushes and dropped after [maxAttempts]; and when TMDB is unreachable (no network, 5xx, 429)
/// the flush stops and keeps every remaining row for the next launch or resume. A 401 against the
/// session invalidates it and stops the flush too — the rows wait for a new login.
class TmdbSyncOutboxService {
  static final _log = Logger('[Service] TmdbSyncOutboxService');

  /// Requests in flight at once, like the other bounded fan-outs (see AGENTS.md).
  static const int chunkSize = 4;

  /// Rows read per round trip to the database.
  static const int batchSize = 50;

  /// A row still failing after this many flushes is given up on so it cannot block the queue.
  static const int maxAttempts = 5;

  final TmdbSessionService Function() _session;
  final TmdbSyncOutboxRepo Function() _repo;
  final TmdbRatingApi _ratingApi;
  final TmdbAccountApi _accountApi;

  Future<void>? _inFlight;

  TmdbSyncOutboxService({
    TmdbSessionService Function()? session,
    TmdbSyncOutboxRepo Function()? repo,
    TmdbRatingApi? ratingApi,
    TmdbAccountApi? accountApi,
  }) : _session = session ?? TmdbSessionService.instance,
       _repo = repo ?? TmdbSyncOutboxRepo.new,
       _ratingApi = ratingApi ?? TmdbRatingApi(),
       _accountApi = accountApi ?? TmdbAccountApi();

  static TmdbSyncOutboxService instance() {
    if (GetIt.I.isRegistered<TmdbSyncOutboxService>()) {
      return GetIt.I.get<TmdbSyncOutboxService>();
    }
    _log.info('New instance created');
    final service = TmdbSyncOutboxService();
    GetIt.I.registerSingleton<TmdbSyncOutboxService>(service);
    return service;
  }

  /// Sends everything that is waiting, joining a flush already running instead of starting another.
  Future<void> flush() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<void> run;
    run = _flush().whenComplete(() {
      if (_inFlight == run) {
        _inFlight = null;
      }
    });
    _inFlight = run;
    return run;
  }

  /// [flush], but only after checking there is something to send — for launch and resume, where
  /// an empty outbox is the common case.
  Future<void> flushIfPending() async {
    if (!_session().isLoggedIn) {
      return;
    }
    try {
      if (await _repo().count() == 0) {
        return;
      }
    } catch (e, stackTrace) {
      _log.warning('Could not read the TMDB sync outbox', e, stackTrace);
      return;
    }
    await flush();
  }

  Future<void> _flush() async {
    final session = _session().session;
    if (session == null) {
      _log.fine('Not logged in to TMDB, leaving the outbox as it is');
      return;
    }
    try {
      final repo = _repo();
      var lastId = 0;
      var delivered = 0;
      var stop = false;
      while (!stop) {
        final rows = await repo.getPending(batchSize, afterId: lastId);
        if (rows.isEmpty) {
          break;
        }
        lastId = rows.last.id;
        for (final chunk in rows.chunked(chunkSize)) {
          final outcomes = await Future.wait(chunk.map((row) => _push(row, session)));
          for (var i = 0; i < chunk.length; i++) {
            final row = chunk[i];
            switch (outcomes[i]) {
              case _Delivered():
                delivered++;
                await repo.delete(row.id);
              case _Dropped(:final reason):
                _log.warning('Dropping outbox row $row: $reason');
                await repo.delete(row.id);
              case _FailedOnce(:final reason):
                if (row.attempts + 1 >= maxAttempts) {
                  _log.warning('Giving up on outbox row $row after $maxAttempts attempts: $reason');
                  await repo.delete(row.id);
                } else {
                  await repo.markAttempt(row.id, reason);
                }
              case _Unreachable(:final reason):
                _log.info('TMDB unreachable ($reason); keeping the outbox for a later flush');
                await repo.markAttempt(row.id, reason);
                stop = true;
              case _SessionInvalid():
                await _session().invalidateSession();
                stop = true;
            }
          }
          if (stop) {
            break;
          }
        }
      }
      if (delivered > 0) {
        _log.info('Delivered $delivered queued change(s) to TMDB');
      }
    } catch (e, stackTrace) {
      _log.severe('Flushing the TMDB sync outbox failed', e, stackTrace);
    }
  }

  Future<_PushOutcome> _push(TmdbSyncOutboxEntity row, TmdbSessionSnapshot session) async {
    try {
      await _send(row, session);
      return const _Delivered();
    } on ApiUnauthorizedException catch (e) {
      if (e.isSessionProblem) {
        return const _SessionInvalid();
      }
      _log.severe('TMDB rejected the API key while pushing $row', e);
      return const _FailedOnce('unauthorized');
    } on ApiNotFoundException {
      return const _Dropped('TMDB has no such title');
    } on ArgumentError catch (e) {
      return _Dropped('$e');
    } catch (e, stackTrace) {
      final code = classifyJobError(e);
      if (code == JobErrorCode.networkError || code == JobErrorCode.serviceDown || code == JobErrorCode.rateLimited) {
        return _Unreachable(code.name);
      }
      _log.warning('Could not push $row', e, stackTrace);
      return _FailedOnce(code.name);
    }
  }

  Future<void> _send(TmdbSyncOutboxEntity row, TmdbSessionSnapshot session) async {
    final sessionId = session.sessionId;
    switch (row.operation) {
      case TmdbSyncOperation.rate:
        final rating = row.rating;
        if (rating == null) {
          throw ArgumentError('a rate operation without a rating');
        }
        final value = TmdbSyncSupport.toTmdbRating(rating);
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
      case TmdbSyncOperation.unrate:
        switch (row.type) {
          case ItemType.movie:
            await _ratingApi.deleteMovieRating(row.tmdbId, sessionId);
          case ItemType.show:
            await _ratingApi.deleteShowRating(row.tmdbId, sessionId);
          case ItemType.episode:
            await _ratingApi.deleteEpisodeRating(row.tmdbId, row.season, row.episode, sessionId);
          case ItemType.season:
            throw ArgumentError('a season cannot be rated');
        }
      case TmdbSyncOperation.watchlistAdd:
      case TmdbSyncOperation.watchlistRemove:
        await _accountApi.setWatchlist(
          accountId: session.accountId,
          sessionId: sessionId,
          mediaType: _mediaType(row.type),
          mediaId: row.tmdbId,
          listed: row.operation == TmdbSyncOperation.watchlistAdd,
        );
      case TmdbSyncOperation.favoriteAdd:
      case TmdbSyncOperation.favoriteRemove:
        await _accountApi.setFavorite(
          accountId: session.accountId,
          sessionId: sessionId,
          mediaType: _mediaType(row.type),
          mediaId: row.tmdbId,
          favorite: row.operation == TmdbSyncOperation.favoriteAdd,
        );
    }
  }

  static TmdbMediaType _mediaType(ItemType type) {
    final mediaType = TmdbMediaType.fromItemType(type);
    if (mediaType == null) {
      throw ArgumentError('a ${type.name} has no place on a TMDB list');
    }
    return mediaType;
  }
}

sealed class _PushOutcome {
  const _PushOutcome();
}

class _Delivered extends _PushOutcome {
  const _Delivered();
}

class _Dropped extends _PushOutcome {
  final String reason;

  const _Dropped(this.reason);
}

class _FailedOnce extends _PushOutcome {
  final String reason;

  const _FailedOnce(this.reason);
}

class _Unreachable extends _PushOutcome {
  final String reason;

  const _Unreachable(this.reason);
}

class _SessionInvalid extends _PushOutcome {
  const _SessionInvalid();
}
