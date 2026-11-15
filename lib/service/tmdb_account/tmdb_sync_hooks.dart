import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_operation.dart';
import 'package:ticketbox/database/sql_store/tmdb_sync/tmdb_sync_outbox_repo.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_session_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_outbox_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_support.dart';

/// What the local write services call after a rating, watchlist or favorites write succeeded.
///
/// When the user is logged in to TMDB and the data set's toggle is on, the change is queued in the
/// outbox and a flush is started; otherwise nothing happens. Never throws: the local write is
/// already done and a sync problem must not undo or fail it.
class TmdbSyncHooks {
  static final _log = Logger('[Service] TmdbSyncHooks');

  final TmdbSessionService Function() _session;
  final TmdbSyncOutboxRepo Function() _repo;
  final TmdbSyncOutboxService Function() _outboxService;

  TmdbSyncHooks({
    TmdbSessionService Function()? session,
    TmdbSyncOutboxRepo Function()? repo,
    TmdbSyncOutboxService Function()? outboxService,
  }) : _session = session ?? TmdbSessionService.instance,
       _repo = repo ?? TmdbSyncOutboxRepo.new,
       _outboxService = outboxService ?? TmdbSyncOutboxService.instance;

  static TmdbSyncHooks instance() {
    if (GetIt.I.isRegistered<TmdbSyncHooks>()) {
      return GetIt.I.get<TmdbSyncHooks>();
    }
    final hooks = TmdbSyncHooks();
    GetIt.I.registerSingleton<TmdbSyncHooks>(hooks);
    return hooks;
  }

  /// [rating] is the new 1–10 value, or null when the rating was removed.
  Future<void> ratingChanged(MediaKey key, int? rating) =>
      _enqueue(TmdbDataSet.ratings, rating == null ? TmdbSyncOperation.unrate : TmdbSyncOperation.rate, key, rating);

  Future<void> watchlistChanged(MediaKey key, {required bool listed}) =>
      _enqueue(TmdbDataSet.watchlist, listed ? TmdbSyncOperation.watchlistAdd : TmdbSyncOperation.watchlistRemove, key, null);

  Future<void> favoriteChanged(MediaKey key, {required bool favorite}) =>
      _enqueue(TmdbDataSet.favorites, favorite ? TmdbSyncOperation.favoriteAdd : TmdbSyncOperation.favoriteRemove, key, null);

  Future<void> _enqueue(TmdbDataSet dataSet, TmdbSyncOperation operation, MediaKey key, int? rating) async {
    try {
      if (!_session().isSyncEnabled(dataSet)) {
        return;
      }
      if (!TmdbSyncSupport.canSync(dataSet, key)) {
        _log.fine('$key has no place in the TMDB ${dataSet.name}; not synced');
        return;
      }
      await _repo().enqueue(operation: operation, key: key, rating: rating);
      _log.fine('Queued ${operation.name} $key for TMDB');
      unawaited(_outboxService().flush());
    } catch (e, stackTrace) {
      _log.warning('Could not queue ${operation.name} $key for TMDB', e, stackTrace);
    }
  }
}
