import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/library/dropped_shows_service.dart';
import 'package:ticketbox/service/poster/library_marks_service.dart';
import 'package:ticketbox/service/poster/poster_model_resolver.dart';
import 'package:ticketbox/ui/pages/dropped_shows/dropped_shows_state.dart';

/// Every show the user has dropped, as a poster grid.
///
/// Unlike the watchlist there is no paging: the dropped list is a handful of shows and is read
/// whole. The tiles come from the local catalogue and the user tables - never a request.
class DroppedShowsBloc extends Cubit<DroppedShowsState> {
  static final _log = Logger('DroppedShowsBloc');

  /// The tables the grid is built from. The show states decide which shows are listed; the
  /// catalogue brings titles and artwork paths (the backfill); the rest are the pills.
  static const _sources = {
    DataChangeEvent.showStateRepo,
    DataChangeEvent.catalogRepo,
    DataChangeEvent.historyRepo,
    DataChangeEvent.watchlistRepo,
    DataChangeEvent.userRatingRepo,
    DataChangeEvent.favoriteRepo,
  };

  final _droppedShowsService = DroppedShowsService();
  final _resolver = PosterModelResolver();
  final _marksService = LibraryMarksService();

  StreamSubscription<Set<DataChangeEvent>>? _dataChangeSubscription;

  bool _isProcessing = false;
  bool _reloadRequested = false;

  DroppedShowsBloc() : super(DroppedShowsState.initial()) {
    _log.finest('Bloc created');
  }

  @override
  Future<void> close() async {
    await _dataChangeSubscription?.cancel();
    await super.close();
  }

  Future<void> init() async {
    _dataChangeSubscription = DataChangeMonitor.instance().changes.listen((events) {
      if (events.any(_sources.contains)) {
        unawaited(_run());
      }
    });

    await _run();
  }

  /// Runs one load at a time; a request arriving mid-load is replayed once it finishes.
  Future<void> _run() async {
    if (_isProcessing) {
      _reloadRequested = true;
      return;
    }

    _isProcessing = true;
    try {
      do {
        _reloadRequested = false;
        try {
          await _load();
        } catch (e, stackTrace) {
          _log.severe('Error loading the dropped shows', e, stackTrace);
          if (isClosed) return;
          // models is kept on purpose: a transient failure must not wipe what is on screen.
          emit(state.copyWith(initialLoading: false, hasError: true, message: e.toString()));
        }
      } while (_reloadRequested && !isClosed);
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _load() async {
    final dropped = await _droppedShowsService.getAll();
    final models = await _resolver.resolve(dropped.map((item) => MediaKey.show(item.showTmdbId)));
    final marks = await _marksService.load();
    final marked = LibraryMarksService.mark(models, marks);

    if (isClosed) return;
    emit(state.copyWith(models: marked, initialLoading: false, hasError: false, message: ''));
  }
}
