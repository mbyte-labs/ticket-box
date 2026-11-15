import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/database/sql_store/favorites/favorite_repository.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';

/// Which repository changed. [catalogRepo] is the `movies` / `shows` tables: a title or an artwork
/// path landing (the backfill, a refresh), which the grids render from. No bloc writes the
/// catalogue, so reacting to it cannot loop.
enum DataChangeEvent { historyRepo, showStateRepo, watchlistRepo, userRatingRepo, favoriteRepo, catalogRepo }

/// The one debounced broadcast of "a repository changed".
///
/// List blocs subscribe to it, re-run their query and re-mark their tiles. Events are collected
/// into a [Set] and flushed a second after the first change, so a batch of writes repaints once.
class DataChangeMonitor {
  static final _log = Logger('[Service] DataChangeMonitor');

  static const _debounceDuration = Duration(seconds: 1);

  final _controller = StreamController<Set<DataChangeEvent>>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<DataChangeEvent> _pendingEvents = {};
  Timer? _debounceTimer;

  DataChangeMonitor._() {
    _subscriptions.addAll([
      HistoryRepo().listenForChanges().listen((event) {
        _log.fine('HistoryRepo change detected: ${event.length} items');
        notify(DataChangeEvent.historyRepo);
      }),
      ShowStateRepo().listenForChanges().listen((_) {
        _log.fine('ShowStateRepo change detected');
        notify(DataChangeEvent.showStateRepo);
      }),
      WatchlistRepo().listenForChanges().listen((event) {
        _log.fine('WatchlistRepo change detected: ${event.length} items');
        notify(DataChangeEvent.watchlistRepo);
      }),
      UserRatingRepo().listenForChanges().listen((event) {
        _log.fine('UserRatingRepo change detected: ${event.length} items');
        notify(DataChangeEvent.userRatingRepo);
      }),
      FavoriteRepo().subscribe().listen((event) {
        _log.fine('FavoriteRepo change detected: ${event.length} items');
        notify(DataChangeEvent.favoriteRepo);
      }),
      MovieRepo().listenForChanges().listen((_) {
        _log.fine('Movies changed');
        notify(DataChangeEvent.catalogRepo);
      }),
      ShowRepo().listenForChanges().listen((_) {
        _log.fine('Shows changed');
        notify(DataChangeEvent.catalogRepo);
      }),
    ]);
  }

  static DataChangeMonitor instance() {
    if (GetIt.I.isRegistered<DataChangeMonitor>()) {
      return GetIt.I.get<DataChangeMonitor>();
    }
    _log.info('New instance created');
    final monitor = DataChangeMonitor._();
    GetIt.I.registerSingleton<DataChangeMonitor>(monitor);
    return monitor;
  }

  Stream<Set<DataChangeEvent>> get changes => _controller.stream;

  void notify(DataChangeEvent event) {
    _pendingEvents.add(event);
    _debounceTimer ??= Timer(_debounceDuration, _flush);
  }

  void _flush() {
    _debounceTimer = null;
    if (_pendingEvents.isEmpty) return;
    _log.fine('Flushing ${_pendingEvents.length} change(s): $_pendingEvents');
    _controller.add(Set.unmodifiable(_pendingEvents));
    _pendingEvents.clear();
  }

  void dispose() {
    _debounceTimer?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _controller.close();
  }
}
